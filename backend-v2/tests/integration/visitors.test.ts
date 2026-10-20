import { describe, expect, it, beforeEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { testOtpInbox } from '../helpers/setup';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { VisitorLogModel } from '../../src/modules/visitors/models/visitor-log.model';
import {
  testVisitorOtpInbox,
  clearTestVisitorOtpInbox,
} from '../../src/modules/visitors/providers/visitor-otp-email.provider';
import {
  setVisitorEventEmitterForTests,
  type VisitorEventPayload,
  type VisitorSocketEvent,
} from '../../src/modules/visitors/services/visitor-events.service';
import { runVisitorExpiryPass } from '../../src/modules/visitors/services/visitor-expiry.service';
import { hashToken } from '../../src/utils/crypto';
import { resetEnvCache, loadEnv } from '../../src/config/env';

const app = createApp();

async function login(email: string) {
  await request(app).post('/api/v1/auth/request-otp').send({ email });
  const otp = testOtpInbox.find((item) => item.email === email)!.otp;
  const res = await request(app).post('/api/v1/auth/verify-otp').send({ email, otp });
  return res.body.data.accessToken as string;
}

async function setupSociety(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'V',
    flatRates: [4000, 4000],
  });
  const owner = await createUser({
    email: `${prefix}-owner@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });
  const tenant = await createUser({
    email: `${prefix}-tenant@example.com`,
    roles: ['TENANT'],
    societyId: ctx.societyId,
  });

  await FlatModel.updateOne(
    { _id: flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
  );

  const guardRes = await request(app)
    .post('/api/v1/admin/guards')
    .set('Authorization', `Bearer ${ctx.token}`)
    .send({
      name: 'Gate Guard',
      email: `${prefix}-guard@example.com`,
      phone: '+91 9000000001',
    });
  expect(guardRes.status).toBe(201);
  const guardToken = await login(`${prefix}-guard@example.com`);

  return {
    ctx,
    owner,
    tenant,
    flats,
    guardToken,
    guardId: guardRes.body.data.guard.id as string,
    ownerFlatId: String(flats[0]._id),
    vacantFlatId: String(flats[1]._id),
  };
}

describe('Guard provisioning', () => {
  it('allows admin create, rejects non-admin and duplicates, deactivates access', async () => {
    const ctx = await createAdminContext(app, 'gprov-admin@example.com', 'GPROV');
    const created = await request(app)
      .post('/api/v1/admin/guards')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ name: 'Guard One', email: 'gprov-guard@example.com' });
    expect(created.status).toBe(201);
    expect(created.body.data.guard.roles).toContain('GUARD');
    expect(JSON.stringify(created.body)).not.toMatch(/otpHash|tokenHash|refreshToken/);

    const owner = await createUser({
      email: 'gprov-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
    });
    const ownerToken = await login(owner.email);
    const denied = await request(app)
      .post('/api/v1/admin/guards')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'X', email: 'x@example.com' });
    expect(denied.status).toBe(403);

    const dup = await request(app)
      .post('/api/v1/admin/guards')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ name: 'Guard One', email: 'gprov-guard@example.com' });
    expect(dup.status).toBe(409);

    const guardToken = await login('gprov-guard@example.com');
    const before = await request(app)
      .get('/api/v1/guard/dashboard')
      .set('Authorization', `Bearer ${guardToken}`);
    expect(before.status).toBe(200);

    const billingDenied = await request(app)
      .get('/api/v1/admin/billing/summary')
      .set('Authorization', `Bearer ${guardToken}`);
    expect(billingDenied.status).toBe(403);

    const residentBilling = await request(app)
      .get('/api/v1/resident/billing/bills')
      .set('Authorization', `Bearer ${guardToken}`)
      .set('x-society-id', ctx.societyId);
    expect(residentBilling.status).toBe(403);

    await request(app)
      .post(`/api/v1/admin/guards/${created.body.data.guard.id}/deactivate`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ reason: 'Shift ended' });

    const after = await request(app)
      .get('/api/v1/guard/dashboard')
      .set('Authorization', `Bearer ${guardToken}`);
    expect(after.status).toBe(403);
  });
});

describe('Visitor registration and routing', () => {
  it('routes owner/tenant correctly and rejects vacant/cross-society/inactive flats', async () => {
    const setup = await setupSociety('vreg');

    const ownerReq = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Guest A',
        visitorPhone: '+91 9876500001',
        visitorType: 'GUEST',
        purpose: 'Visit',
        numberOfVisitors: 1,
      });
    expect(ownerReq.status).toBe(201);
    expect(ownerReq.body.data.assignedResidentUserId).toBe(String(setup.owner._id));
    expect(ownerReq.body.data.assignedResidentRole).toBe('OWNER');
    expect(ownerReq.body.data.visitorPhone).not.toBe('+91 9876500001');
    expect(ownerReq.body.data.visitorPhone).toMatch(/\d{4}$/);

    await FlatModel.updateOne(
      { _id: setup.flats[0]._id },
      {
        occupancyStatus: 'TENANT_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: setup.tenant._id,
      },
    );

    const tenantReq = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Guest B',
        visitorPhone: '+91 9876500002',
        visitorType: 'DELIVERY',
        purpose: 'Parcel',
        numberOfVisitors: 1,
      });
    expect(tenantReq.status).toBe(201);
    expect(tenantReq.body.data.assignedResidentUserId).toBe(String(setup.tenant._id));
    expect(tenantReq.body.data.assignedResidentRole).toBe('TENANT');

    const vacant = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.vacantFlatId,
        visitorName: 'Guest C',
        visitorPhone: '+91 9876500003',
        visitorType: 'GUEST',
        purpose: 'Visit',
        numberOfVisitors: 1,
      });
    expect(vacant.status).toBe(400);
    expect(vacant.body.error.code).toBe('NO_ACTIVE_RESIDENT');

    const other = await createAdminContext(app, 'vreg-other@example.com', 'VREGX');
    const { flats: otherFlats } = await createWingWithFlats({
      societyId: other.societyId,
      code: 'X',
      flatRates: [4000],
    });
    const cross = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: String(otherFlats[0]._id),
        visitorName: 'Guest D',
        visitorPhone: '+91 9876500004',
        visitorType: 'GUEST',
        purpose: 'Visit',
        numberOfVisitors: 1,
      });
    expect(cross.status).toBe(404);

    await FlatModel.updateOne({ _id: setup.flats[0]._id }, { isActive: false });
    const inactive = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Guest E',
        visitorPhone: '+91 9876500005',
        visitorType: 'GUEST',
        purpose: 'Visit',
        numberOfVisitors: 1,
      });
    expect(inactive.status).toBe(400);
  });
});

describe('Resident approval, OTP, entry/exit', () => {
  const captured: Array<{ event: VisitorSocketEvent; payload: VisitorEventPayload }> = [];

  beforeEach(() => {
    captured.length = 0;
    clearTestVisitorOtpInbox();
    setVisitorEventEmitterForTests((event, _rooms, payload) => {
      captured.push({ event, payload });
    });
  });

  it('enforces approver rules, OTP security, entry/exit and socket payloads', async () => {
    const setup = await setupSociety('votp');
    const ownerToken = await login(setup.owner.email);
    const tenantToken = await login(setup.tenant.email);

    const created = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Courier',
        visitorPhone: '+91 9876511111',
        visitorType: 'COURIER',
        purpose: 'Delivery',
        numberOfVisitors: 1,
      });
    const visitorId = created.body.data.id as string;
    expect(captured.some((c) => c.event === 'visitor:approval_requested')).toBe(true);

    // Tenant cannot approve owner-occupied request
    const tenantDenied = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/approve`)
      .set('Authorization', `Bearer ${tenantToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect([403, 404]).toContain(tenantDenied.status);

    // Cannot enter before approval
    const earlyEntry = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/verify-entry-otp`)
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ otp: '123456' });
    expect(earlyEntry.status).toBe(400);

    const approved = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/approve`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(approved.status).toBe(200);
    expect(approved.body.data.approvalStatus).toBe('APPROVED');
    expect(JSON.stringify(approved.body)).not.toMatch(/\b\d{6}\b/);
    expect(captured.some((c) => c.event === 'visitor:approved')).toBe(true);
    expect(JSON.stringify(captured)).not.toMatch(/otpHash|"otp"/);

    const again = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/approve`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(again.status).toBe(200);

    expect(testVisitorOtpInbox.length).toBe(1);
    const otp = testVisitorOtpInbox[0].otp;
    const stored = await VisitorLogModel.findById(visitorId).lean();
    expect(stored?.entryOtpHash).toBe(hashToken(otp));
    expect(stored?.entryOtpHash).not.toBe(otp);

    const guardList = await request(app)
      .get(`/api/v1/guard/visitors/${visitorId}`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(JSON.stringify(guardList.body)).not.toContain(otp);

    const wrong = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/verify-entry-otp`)
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ otp: '000000' });
    expect(wrong.status).toBe(403);

    const entered = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/verify-entry-otp`)
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ otp });
    expect(entered.status).toBe(200);
    expect(entered.body.data.entryStatus).toBe('ENTERED');
    expect(entered.body.data.checkedInBy).toBe(setup.guardId);
    expect(captured.some((c) => c.event === 'visitor:entered')).toBe(true);

    const reuse = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/verify-entry-otp`)
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({ otp });
    expect(reuse.status).toBeGreaterThanOrEqual(400);

    const checkout = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/checkout`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(checkout.status).toBe(200);
    expect(checkout.body.data.entryStatus).toBe('EXITED');
    expect(checkout.body.data.checkedOutBy).toBe(setup.guardId);

    const dupCheckout = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/checkout`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(dupCheckout.status).toBe(200);

    const history = await request(app)
      .get(`/api/v1/resident/visitors/${visitorId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(history.status).toBe(200);
    expect(history.body.data.entryStatus).toBe('EXITED');

    // Owner cannot approve while tenant occupies — use lifecycle APIs for real occupancy state.
    // Ensure owner occupancy record exists first (setup used a direct flat update).
    await request(app)
      .post(`/api/v1/admin/flats/${setup.ownerFlatId}/assign-owner`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        userId: String(setup.owner._id),
        effectiveFrom: new Date().toISOString(),
      });

    const assignTenant = await request(app)
      .post(`/api/v1/admin/flats/${setup.ownerFlatId}/assign-tenant`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        userId: String(setup.tenant._id),
        effectiveFrom: new Date().toISOString(),
      });
    expect(assignTenant.status).toBe(201);

    const tenantVisitor = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Guest T',
        visitorPhone: '+91 9876522222',
        visitorType: 'GUEST',
        purpose: 'Visit',
        numberOfVisitors: 1,
      });
    expect(tenantVisitor.status).toBe(201);
    expect(tenantVisitor.body.data.assignedResidentUserId).toBe(String(setup.tenant._id));

    const ownerBlocked = await request(app)
      .post(`/api/v1/resident/visitors/${tenantVisitor.body.data.id}/approve`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect([403, 404]).toContain(ownerBlocked.status);

    const tenantOk = await request(app)
      .post(`/api/v1/resident/visitors/${tenantVisitor.body.data.id}/approve`)
      .set('Authorization', `Bearer ${tenantToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(tenantOk.status).toBe(200);

    // Previous tenant loses access after occupancy ends
    const endTenant = await request(app)
      .post(`/api/v1/admin/flats/${setup.ownerFlatId}/end-tenant-occupancy`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        effectiveTo: new Date().toISOString(),
        reason: 'Lease ended',
      });
    expect(endTenant.status).toBe(200);

    const prevTenant = await request(app)
      .post(`/api/v1/resident/visitors/${tenantVisitor.body.data.id}/reject`)
      .set('Authorization', `Bearer ${tenantToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ reason: 'no' });
    expect([403, 404, 409]).toContain(prevTenant.status);

    setVisitorEventEmitterForTests(null);
  });

  it('expires unused OTP and pending requests; never expires visitors inside', async () => {
    const prevPending = process.env.VISITOR_PENDING_TTL_MS;
    const prevOtpTtl = process.env.VISITOR_OTP_TTL_MS;
    try {
      process.env.VISITOR_PENDING_TTL_MS = String(30 * 60 * 1000);
      process.env.VISITOR_OTP_TTL_MS = String(10 * 60 * 1000);
      resetEnvCache();
      loadEnv();

      const setup = await setupSociety('vexp');
      const ownerToken = await login(setup.owner.email);

      const pending = await request(app)
        .post('/api/v1/guard/visitors')
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({
          flatId: setup.ownerFlatId,
          visitorName: 'Pending',
          visitorPhone: '+91 9876533333',
          visitorType: 'GUEST',
          purpose: 'Visit',
          numberOfVisitors: 1,
        });

      const toApprove = await request(app)
        .post('/api/v1/guard/visitors')
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({
          flatId: setup.ownerFlatId,
          visitorName: 'ApproveMe',
          visitorPhone: '+91 9876544444',
          visitorType: 'GUEST',
          purpose: 'Visit',
          numberOfVisitors: 1,
        });
      await request(app)
        .post(`/api/v1/resident/visitors/${toApprove.body.data.id}/approve`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', setup.ctx.societyId);

      clearTestVisitorOtpInbox();
      const inside = await request(app)
        .post('/api/v1/guard/visitors')
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({
          flatId: setup.ownerFlatId,
          visitorName: 'Inside',
          visitorPhone: '+91 9876555555',
          visitorType: 'GUEST',
          purpose: 'Visit',
          numberOfVisitors: 1,
        });
      await request(app)
        .post(`/api/v1/resident/visitors/${inside.body.data.id}/approve`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', setup.ctx.societyId);
      expect(testVisitorOtpInbox.length).toBeGreaterThan(0);
      const otp = testVisitorOtpInbox[0].otp;
      const enter = await request(app)
        .post(`/api/v1/guard/visitors/${inside.body.data.id}/verify-entry-otp`)
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({ otp });
      expect(enter.status).toBe(200);

      await VisitorLogModel.updateOne(
        { _id: toApprove.body.data.id },
        { $set: { entryOtpExpiresAt: new Date(Date.now() - 1000) } },
      );
      await VisitorLogModel.collection.updateOne(
        { _id: (await VisitorLogModel.findById(pending.body.data.id))!._id },
        { $set: { createdAt: new Date(Date.now() - 60 * 60 * 1000) } },
      );

      // Temporarily tighten pending TTL for the expiry pass only.
      process.env.VISITOR_PENDING_TTL_MS = '1000';
      resetEnvCache();
      loadEnv();

      const first = await runVisitorExpiryPass();
      expect(first.otpExpired).toBeGreaterThanOrEqual(1);
      expect(first.pendingExpired).toBeGreaterThanOrEqual(1);
      expect(first.pendingExpired + first.otpExpired).toBeGreaterThanOrEqual(2);
      const second = await runVisitorExpiryPass();
      expect(second.pendingExpired + second.otpExpired).toBe(0);

      const insideDoc = await VisitorLogModel.findById(inside.body.data.id).lean();
      expect(insideDoc?.entryStatus).toBe('ENTERED');
      expect(insideDoc?.approvalStatus).toBe('APPROVED');
    } finally {
      process.env.VISITOR_PENDING_TTL_MS = prevPending ?? String(30 * 60 * 1000);
      process.env.VISITOR_OTP_TTL_MS = prevOtpTtl ?? String(10 * 60 * 1000);
      resetEnvCache();
      loadEnv();
      setVisitorEventEmitterForTests(null);
    }
  });

  it('enforces max OTP attempts and expired OTP rejection', async () => {
    const prevMax = process.env.VISITOR_OTP_MAX_ATTEMPTS;
    const prevTtl = process.env.VISITOR_OTP_TTL_MS;
    try {
      process.env.VISITOR_OTP_MAX_ATTEMPTS = '2';
      process.env.VISITOR_OTP_TTL_MS = String(10 * 60 * 1000);
      resetEnvCache();
      loadEnv();

      const setup = await setupSociety('vmax');
      const ownerToken = await login(setup.owner.email);
      clearTestVisitorOtpInbox();
      const created = await request(app)
        .post('/api/v1/guard/visitors')
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({
          flatId: setup.ownerFlatId,
          visitorName: 'Max',
          visitorPhone: '+91 9876566666',
          visitorType: 'GUEST',
          purpose: 'Visit',
          numberOfVisitors: 1,
        });
      await request(app)
        .post(`/api/v1/resident/visitors/${created.body.data.id}/approve`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', setup.ctx.societyId);

      await request(app)
        .post(`/api/v1/guard/visitors/${created.body.data.id}/verify-entry-otp`)
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({ otp: '111111' });
      await request(app)
        .post(`/api/v1/guard/visitors/${created.body.data.id}/verify-entry-otp`)
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({ otp: '222222' });
      const maxed = await request(app)
        .post(`/api/v1/guard/visitors/${created.body.data.id}/verify-entry-otp`)
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({ otp: '333333' });
      expect(maxed.status).toBe(403);
      expect(maxed.body.error.code).toBe('OTP_MAX_ATTEMPTS');

      clearTestVisitorOtpInbox();
      const created2 = await request(app)
        .post('/api/v1/guard/visitors')
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({
          flatId: setup.ownerFlatId,
          visitorName: 'Exp',
          visitorPhone: '+91 9876577777',
          visitorType: 'GUEST',
          purpose: 'Visit',
          numberOfVisitors: 1,
        });
      await request(app)
        .post(`/api/v1/resident/visitors/${created2.body.data.id}/approve`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', setup.ctx.societyId);
      await VisitorLogModel.updateOne(
        { _id: created2.body.data.id },
        { entryOtpExpiresAt: new Date(Date.now() - 1000) },
      );
      const expired = await request(app)
        .post(`/api/v1/guard/visitors/${created2.body.data.id}/verify-entry-otp`)
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({ otp: testVisitorOtpInbox[0].otp });
      expect(expired.status).toBe(400);
      expect(expired.body.error.code).toBe('OTP_EXPIRED');
    } finally {
      process.env.VISITOR_OTP_MAX_ATTEMPTS = prevMax ?? '5';
      process.env.VISITOR_OTP_TTL_MS = prevTtl ?? String(10 * 60 * 1000);
      resetEnvCache();
      loadEnv();
      setVisitorEventEmitterForTests(null);
    }
  });
});
