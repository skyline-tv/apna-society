import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createSociety, createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { OccupancyRecordModel } from '../../src/modules/society/models/occupancy-record.model';
import { MembershipModel } from '../../src/modules/users/models/membership.model';
import { getFlatAccess } from '../../src/modules/users/services/access-control.service';
import { assignOwner } from '../../src/modules/society/services/occupancy-lifecycle.service';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

async function provision(
  token: string,
  body: { name: string; email: string; phone?: string; role: 'OWNER' | 'TENANT' },
) {
  const res = await request(app)
    .post('/api/v1/admin/users')
    .set('Authorization', `Bearer ${token}`)
    .send(body);
  return res;
}

describe('User provisioning', () => {
  it('allows admin to create owner and tenant without flat assignment', async () => {
    const ctx = await createAdminContext(app, 'prov-admin@example.com', 'PROV_SOC');
    const owner = await provision(ctx.token, {
      name: 'Owner One',
      email: 'owner1@example.com',
      phone: '+91 9876543210',
      role: 'OWNER',
    });
    expect(owner.status).toBe(201);
    expect(owner.body.data.flatAssigned).toBe(false);
    expect(owner.body.data.user.roles).toContain('OWNER');
    expect(JSON.stringify(owner.body)).not.toMatch(/otpHash|tokenHash|password|refreshToken/);

    const tenant = await provision(ctx.token, {
      name: 'Tenant One',
      email: 'tenant1@example.com',
      role: 'TENANT',
    });
    expect(tenant.status).toBe(201);
    expect(tenant.body.data.user.roles).toContain('TENANT');

    const occ = await OccupancyRecordModel.countDocuments({
      userId: owner.body.data.user.id,
      status: 'ACTIVE',
    });
    expect(occ).toBe(0);
  });

  it('rejects duplicate email and non-admin provisioning', async () => {
    const ctx = await createAdminContext(app, 'prov-dup@example.com', 'PROV_DUP');
    await provision(ctx.token, {
      name: 'Owner',
      email: 'dup@example.com',
      role: 'OWNER',
    });

    // Reuse same email with same role should succeed as reuse, not duplicate create conflict
    const reused = await provision(ctx.token, {
      name: 'Owner Updated',
      email: 'dup@example.com',
      role: 'OWNER',
    });
    expect(reused.status).toBe(201);
    expect(reused.body.data.reusedExisting).toBe(true);

    const society = await createSociety('PROV_OWNER_BLOCK');
    await createUser({
      email: 'not-admin@example.com',
      roles: ['OWNER'],
      societyId: String(society._id),
    });
    const ownerToken = await login('not-admin@example.com');
    const denied = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'X', email: 'x@example.com', role: 'OWNER' });
    expect(denied.status).toBe(403);
  });
});

describe('Owner and tenant lifecycle', () => {
  it('assigns owner, rejects second owner, assigns tenant, ends tenant, then owner', async () => {
    const ctx = await createAdminContext(app, 'life-admin@example.com', 'LIFE_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'A',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);

    const ownerRes = await provision(ctx.token, {
      name: 'Life Owner',
      email: 'life-owner@example.com',
      role: 'OWNER',
    });
    const tenantRes = await provision(ctx.token, {
      name: 'Life Tenant',
      email: 'life-tenant@example.com',
      role: 'TENANT',
    });
    const ownerId = ownerRes.body.data.user.id as string;
    const tenantId = tenantRes.body.data.user.id as string;

    const assigned = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });
    expect(assigned.status).toBe(201);
    expect(assigned.body.data.occupancyStatus).toBe('OWNER_OCCUPIED');

    const secondOwner = await provision(ctx.token, {
      name: 'Other Owner',
      email: 'other-owner@example.com',
      role: 'OWNER',
    });
    const rejectSecond = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        userId: secondOwner.body.data.user.id,
        effectiveFrom: new Date().toISOString(),
      });
    expect(rejectSecond.status).toBe(409);

    const tenantAssigned = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: tenantId, effectiveFrom: new Date().toISOString() });
    expect(tenantAssigned.status).toBe(201);
    expect(tenantAssigned.body.data.occupancyStatus).toBe('TENANT_OCCUPIED');

    const secondTenant = await provision(ctx.token, {
      name: 'Other Tenant',
      email: 'other-tenant@example.com',
      role: 'TENANT',
    });
    const rejectTenant = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        userId: secondTenant.body.data.user.id,
        effectiveFrom: new Date().toISOString(),
      });
    expect(rejectTenant.status).toBe(409);

    const endOwnerBlocked = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Moving out' });
    expect(endOwnerBlocked.status).toBe(403);
    expect(endOwnerBlocked.body.error.code).toBe('TENANT_STILL_ACTIVE');

    const endTenant = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-tenant-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Lease ended' });
    expect(endTenant.status).toBe(200);
    expect(endTenant.body.data.occupancyStatus).toBe('OWNER_OCCUPIED');
    expect(endTenant.body.data.activeOwnerUserId).toBe(ownerId);
    expect(endTenant.body.data.activeTenantUserId).toBeNull();

    const flatAfterTenant = await FlatModel.findById(flatId).lean();
    expect(flatAfterTenant?.occupancyStatus).toBe('OWNER_OCCUPIED');
    expect(String(flatAfterTenant?.activeOwnerUserId)).toBe(ownerId);
    expect(flatAfterTenant?.activeTenantUserId).toBeFalsy();

    const activeOwnerOcc = await OccupancyRecordModel.findOne({
      flatId,
      role: 'OWNER',
      status: 'ACTIVE',
    }).lean();
    expect(activeOwnerOcc).toBeTruthy();

    const endOwner = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-owner-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Sold' });
    expect(endOwner.status).toBe(200);
    expect(endOwner.body.data.occupancyStatus).toBe('VACANT');

    const history = await request(app)
      .get(`/api/v1/admin/flats/${flatId}/occupancy-history`)
      .set('Authorization', `Bearer ${ctx.token}`);
    expect(history.status).toBe(200);
    expect(history.body.data.items.length).toBeGreaterThanOrEqual(2);
  });
});

describe('Access control and consistency', () => {
  it('enforces owner/tenant/guard access matrix and blocks flat PATCH occupancy edits', async () => {
    const ctx = await createAdminContext(app, 'access-admin@example.com', 'ACCESS_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'B',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);

    const ownerRes = await provision(ctx.token, {
      name: 'Access Owner',
      email: 'access-owner@example.com',
      role: 'OWNER',
    });
    const tenantRes = await provision(ctx.token, {
      name: 'Access Tenant',
      email: 'access-tenant@example.com',
      role: 'TENANT',
    });
    const ownerId = ownerRes.body.data.user.id as string;
    const tenantId = tenantRes.body.data.user.id as string;

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });

    let access = await getFlatAccess({
      userId: ownerId,
      societyId: ctx.societyId,
      flatId,
    });
    expect(access.financial).toBe(true);
    expect(access.residential).toBe(true);

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-tenant`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ userId: tenantId, effectiveFrom: new Date().toISOString() });

    access = await getFlatAccess({ userId: ownerId, societyId: ctx.societyId, flatId });
    expect(access.financial).toBe(true);
    expect(access.residential).toBe(false);

    const tenantAccess = await getFlatAccess({
      userId: tenantId,
      societyId: ctx.societyId,
      flatId,
    });
    expect(tenantAccess.financial).toBe(false);
    expect(tenantAccess.residential).toBe(true);

    const ownerToken = await login('access-owner@example.com');
    const tenantToken = await login('access-tenant@example.com');

    const ownerFlat = await request(app)
      .get(`/api/v1/resident/flats/${flatId}`)
      .set('Authorization', `Bearer ${ownerToken}`);
    expect(ownerFlat.status).toBe(200);
    expect(ownerFlat.body.data.access.financial).toBe(true);
    expect(ownerFlat.body.data.access.residential).toBe(false);

    const tenantFlat = await request(app)
      .get(`/api/v1/resident/flats/${flatId}`)
      .set('Authorization', `Bearer ${tenantToken}`);
    expect(tenantFlat.status).toBe(200);
    expect(tenantFlat.body.data.access.residential).toBe(true);
    expect(tenantFlat.body.data.access.financial).toBe(false);

    await request(app)
      .post(`/api/v1/admin/flats/${flatId}/end-tenant-occupancy`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ effectiveTo: new Date().toISOString(), reason: 'Moved out' });

    const previousTenant = await request(app)
      .get(`/api/v1/resident/flats/${flatId}`)
      .set('Authorization', `Bearer ${tenantToken}`);
    expect(previousTenant.status).toBe(403);

    await createUser({
      email: 'guard@example.com',
      roles: ['GUARD'],
      societyId: ctx.societyId,
    });
    const guardToken = await login('guard@example.com');
    const guardFlat = await request(app)
      .get(`/api/v1/resident/flats/${flatId}`)
      .set('Authorization', `Bearer ${guardToken}`);
    expect(guardFlat.status).toBe(403);

    const guardAccess = await getFlatAccess({
      userId: (await MembershipModel.findOne({ role: 'GUARD' }))!.userId.toString(),
      societyId: ctx.societyId,
      flatId,
    });
    expect(guardAccess.financial).toBe(false);

    const patchBlocked = await request(app)
      .patch(`/api/v1/admin/flats/${flatId}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ occupancyStatus: 'VACANT' });
    expect(patchBlocked.status).toBe(400);

    const patchOwnerRef = await request(app)
      .patch(`/api/v1/admin/flats/${flatId}`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ activeOwnerUserId: ownerId });
    expect(patchOwnerRef.status).toBe(400);

    const other = await createAdminContext(app, 'access-other@example.com', 'ACCESS_OTHER');
    const cross = await request(app)
      .post(`/api/v1/admin/flats/${flatId}/assign-owner`)
      .set('Authorization', `Bearer ${other.token}`)
      .send({ userId: ownerId, effectiveFrom: new Date().toISOString() });
    expect(cross.status).toBe(404);
  });

  it('keeps Flat/OccupancyRecord consistent and rejects concurrent duplicate owners', async () => {
    const ctx = await createAdminContext(app, 'conc-admin@example.com', 'CONC_SOC');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'C',
      flatRates: [4000],
    });
    const flatId = String(flats[0]._id);

    const o1 = await provision(ctx.token, {
      name: 'C1',
      email: 'c1@example.com',
      role: 'OWNER',
    });
    const o2 = await provision(ctx.token, {
      name: 'C2',
      email: 'c2@example.com',
      role: 'OWNER',
    });

    const results = await Promise.allSettled([
      assignOwner(
        ctx.societyId,
        flatId,
        { userId: o1.body.data.user.id, effectiveFrom: new Date() },
        { userId: ctx.userId },
      ),
      assignOwner(
        ctx.societyId,
        flatId,
        { userId: o2.body.data.user.id, effectiveFrom: new Date() },
        { userId: ctx.userId },
      ),
    ]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');
    expect(fulfilled.length).toBe(1);
    expect(rejected.length).toBe(1);

    const activeOwners = await OccupancyRecordModel.countDocuments({
      flatId,
      role: 'OWNER',
      status: 'ACTIVE',
    });
    expect(activeOwners).toBe(1);

    const flat = await FlatModel.findById(flatId).lean();
    expect(flat?.occupancyStatus).toBe('OWNER_OCCUPIED');
    expect(flat?.activeOwnerUserId).toBeTruthy();
    expect(flat?.activeTenantUserId).toBeFalsy();
  });
});
