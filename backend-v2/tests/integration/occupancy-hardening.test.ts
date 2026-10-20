import { afterEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createSociety, createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { testOtpInbox } from '../helpers/setup';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { OccupancyRecordModel } from '../../src/modules/society/models/occupancy-record.model';
import { MembershipModel } from '../../src/modules/users/models/membership.model';
import { AuditLogModel } from '../../src/modules/auth/models/audit-log.model';
import { UserModel } from '../../src/modules/users/models/user.model';
import {
  assertFinancialAccess,
  assertResidentialAccess,
} from '../../src/modules/users/services/access-control.service';
import {
  assignOwner,
  assignTenant,
  occupancyTestHooks,
  resetOccupancyTestHooks,
} from '../../src/modules/society/services/occupancy-lifecycle.service';
import { AppError } from '../../src/shared/errors/app-error';

const app = createApp();

afterEach(() => {
  resetOccupancyTestHooks();
});

async function login(email: string) {
  await request(app).post('/api/v1/auth/request-otp').send({ email });
  const otp = testOtpInbox.find((item) => item.email === email)!.otp;
  const res = await request(app).post('/api/v1/auth/verify-otp').send({ email, otp });
  return res.body.data.accessToken as string;
}

async function provision(
  token: string,
  body: { name: string; email: string; phone?: string; role: 'OWNER' | 'TENANT' },
) {
  return request(app).post('/api/v1/admin/users').set('Authorization', `Bearer ${token}`).send(body);
}

describe('Provisioning hardening', () => {
  it('deactivates residents safely and blocks unsafe deactivation paths', async () => {
    const ctx = await createAdminContext(app, 'deact-admin@example.com', 'DEACT_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);

    const owner = await provision(ctx.token, {
      name: 'Deact Owner',
      email: 'deact-owner@example.com',
      role: 'OWNER',
    });
    const ownerId = owner.body.data.user.id as string;

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });

    const blockedActive = await request(app)
      .post(`/api/v1/admin/users/${ownerId}/deactivate`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Should fail' });
    expect(blockedActive.status).toBe(403);
    expect(blockedActive.body.error.code).toBe('ACTIVE_OCCUPANCY_EXISTS');

    const self = await request(app)
      .post(`/api/v1/admin/users/${ctx.userId}/deactivate`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Self' });
    expect(self.status).toBe(403);
    expect(self.body.error.code).toBe('SELF_DEACTIVATION');

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Ended for deactivation' });

    const deactivated = await request(app)
      .post(`/api/v1/admin/users/${ownerId}/deactivate`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Left society' });
    expect(deactivated.status).toBe(200);
    expect(deactivated.body.data.isActive).toBe(false);
    expect(deactivated.body.data.canLogin).toBe(false);
    expect(JSON.stringify(deactivated.body)).not.toMatch(/otpHash|tokenHash|password|refreshToken/);

    const audit = await AuditLogModel.findOne({
      action: 'USER_DEACTIVATED',
      targetId: ownerId,
    }).lean();
    expect(audit).toBeTruthy();
  });

  it('never returns secrets from user list/get endpoints', async () => {
    const ctx = await createAdminContext(app, 'secret-admin@example.com', 'SECRET_SOC');
    await provision(ctx.token, {
      name: 'Secret Owner',
      email: 'secret-owner@example.com',
      role: 'OWNER',
    });

    const list = await request(app)
      .get('/api/v1/admin/users')
      .query({ search: 'secret-owner' })
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(list.status).toBe(200);
    expect(JSON.stringify(list.body)).not.toMatch(/otpHash|tokenHash|password|refreshToken|JWT/);

    const userId = list.body.data.items[0].id as string;
    const one = await request(app)
      .get(`/api/v1/admin/users/${userId}`)
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(one.status).toBe(200);
    expect(JSON.stringify(one.body)).not.toMatch(/otpHash|tokenHash|password|refreshToken/);
  });
});

describe('Ownership constraints and history', () => {
  it('rejects the same owner holding two active flats in one society', async () => {
    const ctx = await createAdminContext(app, 'multi-admin@example.com', 'MULTI_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      flatRates: [4000, 4000],
    });
    const owner = await provision(ctx.token, {
      name: 'Multi Owner',
      email: 'multi-owner@example.com',
      role: 'OWNER',
    });
    const ownerId = owner.body.data.user.id as string;

    const first = await request(app)
      .post(`/api/v1/admin/flats/${flats[0]._id}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });
    expect(first.status).toBe(201);

    const second = await request(app)
      .post(`/api/v1/admin/flats/${flats[1]._id}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });
    expect(second.status).toBe(409);
    expect(second.body.error.code).toBe('DUPLICATE_ACTIVE_ASSIGNMENT');
  });

  it('preserves historical occupancy and memberships after end, and allows reassignment', async () => {
    const ctx = await createAdminContext(app, 'hist-admin@example.com', 'HIST_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'B',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    const owner = await provision(ctx.token, {
      name: 'Hist Owner',
      email: 'hist-owner@example.com',
      role: 'OWNER',
    });
    const ownerId = owner.body.data.user.id as string;

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString(), notes: 'first term' });

    const activeMembership = await MembershipModel.findOne({
      userId: ownerId,
      flatId,
      role: 'OWNER',
      isActive: true,
    }).lean();
    expect(activeMembership).toBeTruthy();

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Sold once' });

    const endedRecords = await OccupancyRecordModel.find({
      flatId,
      userId: ownerId,
      role: 'OWNER',
      status: 'ENDED',
    }).lean();
    expect(endedRecords).toHaveLength(1);
    expect(endedRecords[0].endReason).toBe('Sold once');

    const inactiveMemberships = await MembershipModel.find({
      userId: ownerId,
      flatId,
      role: 'OWNER',
      isActive: false,
    }).lean();
    expect(inactiveMemberships.length).toBeGreaterThanOrEqual(1);

    const reassign = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString(), notes: 'second term' });
    expect(reassign.status).toBe(201);

    const history = await request(app)
      .get(`/api/v1/admin/flats/${flatId}/occupancy-history`)
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(history.body.data.items.length).toBeGreaterThanOrEqual(2);
    expect(history.body.data.items.some((row: { status: string }) => row.status === 'ENDED')).toBe(
      true,
    );
    expect(history.body.data.items.some((row: { status: string }) => row.status === 'ACTIVE')).toBe(
      true,
    );

    const audits = await AuditLogModel.find({
      targetId: flatId,
      action: { $in: ['OWNER_ASSIGNED', 'OWNER_OCCUPANCY_ENDED'] },
    }).lean();
    expect(audits.length).toBeGreaterThanOrEqual(3);
  });
});

describe('Transaction rollback', () => {
  it('rolls back occupancy and membership when failure occurs after occupancy create', async () => {
    const ctx = await createAdminContext(app, 'txn-admin@example.com', 'TXN_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'T',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    const owner = await provision(ctx.token, {
      name: 'Txn Owner',
      email: 'txn-owner@example.com',
      role: 'OWNER',
    });
    const ownerId = owner.body.data.user.id as string;

    occupancyTestHooks.failAfter = 'occupancy_created';

    await expect(
      assignOwner(
        ctx.societyId,
        flatId,
        { userId: ownerId, effectiveFrom: new Date() },
        { userId: ctx.userId },
      ),
    ).rejects.toThrow(/TEST_FORCED_TRANSACTION_FAILURE/);

    expect(await OccupancyRecordModel.countDocuments({ flatId })).toBe(0);
    expect(
      await MembershipModel.countDocuments({
        flatId,
        role: 'OWNER',
        isActive: true,
      }),
    ).toBe(0);

    const flat = await FlatModel.findById(flatId).lean();
    expect(flat?.occupancyStatus).toBe('VACANT');
    expect(flat?.activeOwnerUserId).toBeFalsy();
    expect(flat?.activeTenantUserId).toBeFalsy();
  });

  it('rolls back tenant assignment when failure occurs after membership upsert', async () => {
    const ctx = await createAdminContext(app, 'txn2-admin@example.com', 'TXN2_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'U',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    const owner = await provision(ctx.token, {
      name: 'Txn2 Owner',
      email: 'txn2-owner@example.com',
      role: 'OWNER',
    });
    const tenant = await provision(ctx.token, {
      name: 'Txn2 Tenant',
      email: 'txn2-tenant@example.com',
      role: 'TENANT',
    });

    await assignOwner(
      ctx.societyId,
      flatId,
      { userId: owner.body.data.user.id, effectiveFrom: new Date() },
      { userId: ctx.userId },
    );

    occupancyTestHooks.failAfter = 'membership_upserted';

    await expect(
      assignTenant(
        ctx.societyId,
        flatId,
        { userId: tenant.body.data.user.id, effectiveFrom: new Date() },
        { userId: ctx.userId },
      ),
    ).rejects.toThrow(/TEST_FORCED_TRANSACTION_FAILURE/);

    expect(await OccupancyRecordModel.countDocuments({ flatId, role: 'TENANT' })).toBe(0);
    expect(
      await MembershipModel.countDocuments({
        flatId,
        role: 'TENANT',
        isActive: true,
      }),
    ).toBe(0);

    const flat = await FlatModel.findById(flatId).lean();
    expect(flat?.occupancyStatus).toBe('OWNER_OCCUPIED');
    expect(String(flat?.activeOwnerUserId)).toBe(owner.body.data.user.id);
    expect(flat?.activeTenantUserId).toBeFalsy();
  });
});

describe('Concurrent assignments', () => {
  it('allows only one concurrent tenant assignment via HTTP', async () => {
    const ctx = await createAdminContext(app, 'conc-t-admin@example.com', 'CONC_T_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'C',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    const owner = await provision(ctx.token, {
      name: 'CT Owner',
      email: 'ct-owner@example.com',
      role: 'OWNER',
    });
    const t1 = await provision(ctx.token, {
      name: 'CT1',
      email: 'ct1@example.com',
      role: 'TENANT',
    });
    const t2 = await provision(ctx.token, {
      name: 'CT2',
      email: 'ct2@example.com',
      role: 'TENANT',
    });

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: owner.body.data.user.id, effectiveFrom: new Date().toISOString() });

    const [r1, r2] = await Promise.all([
      request(app)
        .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
        .set('Authorization', `Bearer ${ctx.token}`)
        .send({ userId: t1.body.data.user.id, effectiveFrom: new Date().toISOString() }),
      request(app)
        .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
        .set('Authorization', `Bearer ${ctx.token}`)
        .send({ userId: t2.body.data.user.id, effectiveFrom: new Date().toISOString() }),
    ]);

    const statuses = [r1.status, r2.status].sort((a, b) => a - b);
    expect(statuses[0]).toBe(201);
    expect([409, 403]).toContain(statuses[1]);
    if (statuses[1] === 409) {
      const loser = r1.status === 409 ? r1 : r2;
      expect(['ACTIVE_TENANT_EXISTS', 'DUPLICATE_ACTIVE_ASSIGNMENT', 'TRANSACTION_CONFLICT']).toContain(
        loser.body.error.code,
      );
    }

    expect(
      await OccupancyRecordModel.countDocuments({ flatId, role: 'TENANT', status: 'ACTIVE' }),
    ).toBe(1);

    const flat = await FlatModel.findById(flatId).lean();
    expect(flat?.occupancyStatus).toBe('TENANT_OCCUPIED');
    expect(flat?.activeTenantUserId).toBeTruthy();
  });

  it('returns conflict codes for concurrent owner race via HTTP', async () => {
    const ctx = await createAdminContext(app, 'conc-o-admin@example.com', 'CONC_O_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'D',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    const o1 = await provision(ctx.token, {
      name: 'CO1',
      email: 'co1@example.com',
      role: 'OWNER',
    });
    const o2 = await provision(ctx.token, {
      name: 'CO2',
      email: 'co2@example.com',
      role: 'OWNER',
    });

    const [r1, r2] = await Promise.all([
      request(app)
        .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
        .set('Authorization', `Bearer ${ctx.token}`)
        .send({ userId: o1.body.data.user.id, effectiveFrom: new Date().toISOString() }),
      request(app)
        .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
        .set('Authorization', `Bearer ${ctx.token}`)
        .send({ userId: o2.body.data.user.id, effectiveFrom: new Date().toISOString() }),
    ]);

    const statuses = [r1.status, r2.status].sort((a, b) => a - b);
    expect(statuses[0]).toBe(201);
    expect([409, 403]).toContain(statuses[1]);
    expect(
      await OccupancyRecordModel.countDocuments({ flatId, role: 'OWNER', status: 'ACTIVE' }),
    ).toBe(1);
  });
});

describe('Authorization hardening', () => {
  it('enforces financial/residential guards and previous-tenant isolation from new tenant data', async () => {
    const ctx = await createAdminContext(app, 'authz-admin@example.com', 'AUTHZ_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'E',
      flatRates: [4000, 5000],
    });
    const flatId = String(flats[0]._id);
    const otherFlatId = String(flats[1]._id);

    const owner = await provision(ctx.token, {
      name: 'Authz Owner',
      email: 'authz-owner@example.com',
      role: 'OWNER',
    });
    const tenantA = await provision(ctx.token, {
      name: 'Tenant A',
      email: 'tenant-a@example.com',
      role: 'TENANT',
    });
    const tenantB = await provision(ctx.token, {
      name: 'Tenant B',
      email: 'tenant-b@example.com',
      role: 'TENANT',
    });
    const ownerId = owner.body.data.user.id as string;
    const tenantAId = tenantA.body.data.user.id as string;
    const tenantBId = tenantB.body.data.user.id as string;

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });

    await expect(
      assertFinancialAccess({ userId: ownerId, societyId: ctx.societyId, flatId }),
    ).resolves.toMatchObject({ financial: true, residential: true });
    await expect(
      assertResidentialAccess({ userId: ownerId, societyId: ctx.societyId, flatId }),
    ).resolves.toMatchObject({ residential: true });

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: tenantAId, effectiveFrom: new Date().toISOString() });

    await expect(
      assertFinancialAccess({ userId: ownerId, societyId: ctx.societyId, flatId }),
    ).resolves.toMatchObject({ financial: true, residential: false });
    await expect(
      assertResidentialAccess({ userId: ownerId, societyId: ctx.societyId, flatId }),
    ).rejects.toMatchObject({ code: 'RESIDENTIAL_ACCESS_DENIED' });
    await expect(
      assertFinancialAccess({ userId: tenantAId, societyId: ctx.societyId, flatId }),
    ).rejects.toMatchObject({ code: 'FINANCIAL_ACCESS_DENIED' });
    await expect(
      assertResidentialAccess({ userId: tenantAId, societyId: ctx.societyId, flatId }),
    ).resolves.toMatchObject({ residential: true });

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-tenant-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Lease A ended' });

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: tenantBId, effectiveFrom: new Date().toISOString() });

    const tokenA = await login('tenant-a@example.com');
    const tokenB = await login('tenant-b@example.com');

    const previousFlat = await request(app)
      .get(`/api/v1/resident/flats/${flatId}`)
      .set('Authorization', `Bearer ${tokenA}`);
    expect(previousFlat.status).toBe(403);

    const previousOcc = await request(app)
      .get(`/api/v1/resident/flats/${flatId}/occupancy`)
      .set('Authorization', `Bearer ${tokenA}`);
    expect(previousOcc.status).toBe(200);
    const previousIds = (previousOcc.body.data.items as Array<{ userId: string }>).map(
      (row) => row.userId,
    );
    expect(previousIds.every((id) => id === tenantAId)).toBe(true);
    expect(previousIds).not.toContain(tenantBId);

    const currentOcc = await request(app)
      .get(`/api/v1/resident/flats/${flatId}/occupancy`)
      .set('Authorization', `Bearer ${tokenB}`);
    expect(currentOcc.status).toBe(200);
    expect(
      (currentOcc.body.data.items as Array<{ userId: string; status: string }>).some(
        (row) => row.userId === tenantBId && row.status === 'ACTIVE',
      ),
    ).toBe(true);

    const wrongFlat = await request(app)
      .get(`/api/v1/resident/flats/${otherFlatId}`)
      .set('Authorization', `Bearer ${tokenB}`);
    expect(wrongFlat.status).toBe(403);

    const otherSociety = await createAdminContext(app, 'authz-other@example.com', 'AUTHZ_OTHER');
    const crossAssign = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${otherSociety.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });
    expect(crossAssign.status).toBe(404);

    // User from another society cannot be assigned even when ObjectId is known.
    const foreignOwner = await provision(otherSociety.token, {
      name: 'Foreign Owner',
      email: 'foreign-owner@example.com',
      role: 'OWNER',
    });
    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-tenant-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Clear tenant' });
    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Clear owner' });

    const societyMismatch = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        userId: foreignOwner.body.data.user.id,
        effectiveFrom: new Date().toISOString(),
      });
    expect(societyMismatch.status).toBe(403);
    expect(societyMismatch.body.error.code).toBe('SOCIETY_MISMATCH');
  });

  it('blocks guard financial access through protected assertions', async () => {
    const ctx = await createAdminContext(app, 'guard-admin@example.com', 'GUARD_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'G',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    const owner = await provision(ctx.token, {
      name: 'G Owner',
      email: 'g-owner@example.com',
      role: 'OWNER',
    });
    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: owner.body.data.user.id, effectiveFrom: new Date().toISOString() });

    const guard = await createUser({
      email: 'hard-guard@example.com',
      roles: ['GUARD'],
      societyId: ctx.societyId,
    });

    await expect(
      assertFinancialAccess({
        userId: String(guard._id),
        societyId: ctx.societyId,
        flatId,
      }),
    ).rejects.toBeInstanceOf(AppError);

    const guardToken = await login('hard-guard@example.com');
    const res = await request(app)
      .get(`/api/v1/resident/flats/${flatId}`)
      .set('Authorization', `Bearer ${guardToken}`);
    expect(res.status).toBe(403);
  });
});

describe('Index and consistency invariants', () => {
  it('keeps Flat references aligned with active OccupancyRecords after transitions', async () => {
    const ctx = await createAdminContext(app, 'inv-admin@example.com', 'INV_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'I',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);
    const owner = await provision(ctx.token, {
      name: 'Inv Owner',
      email: 'inv-owner@example.com',
      role: 'OWNER',
    });
    const tenant = await provision(ctx.token, {
      name: 'Inv Tenant',
      email: 'inv-tenant@example.com',
      role: 'TENANT',
    });

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: owner.body.data.user.id, effectiveFrom: new Date().toISOString() });
    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: tenant.body.data.user.id, effectiveFrom: new Date().toISOString() });

    let flat = await FlatModel.findById(flatId).lean();
    let activeOwner = await OccupancyRecordModel.findOne({
      flatId,
      role: 'OWNER',
      status: 'ACTIVE',
    }).lean();
    let activeTenant = await OccupancyRecordModel.findOne({
      flatId,
      role: 'TENANT',
      status: 'ACTIVE',
    }).lean();
    expect(flat?.occupancyStatus).toBe('TENANT_OCCUPIED');
    expect(String(flat?.activeOwnerUserId)).toBe(String(activeOwner?.userId));
    expect(String(flat?.activeTenantUserId)).toBe(String(activeTenant?.userId));

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-tenant-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'done' });

    flat = await FlatModel.findById(flatId).lean();
    activeOwner = await OccupancyRecordModel.findOne({
      flatId,
      role: 'OWNER',
      status: 'ACTIVE',
    }).lean();
    activeTenant = await OccupancyRecordModel.findOne({
      flatId,
      role: 'TENANT',
      status: 'ACTIVE',
    }).lean();
    expect(flat?.occupancyStatus).toBe('OWNER_OCCUPIED');
    expect(String(flat?.activeOwnerUserId)).toBe(String(activeOwner?.userId));
    expect(activeTenant).toBeNull();
    expect(flat?.activeTenantUserId).toBeFalsy();

    // Generic PATCH still rejects occupancy fields.
    const patch = await request(app)
      .patch(`/api/v1/admin/flats/${flatId}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ occupancyStatus: 'VACANT', activeTenantUserId: tenant.body.data.user.id });
    expect(patch.status).toBe(400);
  });

  it('does not create duplicate User documents for the same email', async () => {
    const ctx = await createAdminContext(app, 'uniq-admin@example.com', 'UNIQ_SOC');
    await provision(ctx.token, {
      name: 'Unique',
      email: 'unique@example.com',
      role: 'OWNER',
    });
    await provision(ctx.token, {
      name: 'Unique Again',
      email: 'Unique@example.com',
      role: 'TENANT',
    });
    expect(await UserModel.countDocuments({ email: 'unique@example.com' })).toBe(1);

    const society = await createSociety('UNIQ_OTHER');
    // Direct model create with same email must fail uniqueness.
    await expect(
      UserModel.create({
        email: 'unique@example.com',
        name: 'Dup',
        roles: ['OWNER'],
        primarySocietyId: society._id,
      }),
    ).rejects.toBeTruthy();
  });
});
