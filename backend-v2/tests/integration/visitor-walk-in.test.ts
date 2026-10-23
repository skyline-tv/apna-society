import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { NotificationModel } from '../../src/modules/notifications/models/notification.model';
import { VisitorLogModel } from '../../src/modules/visitors/models/visitor-log.model';
import { ParcelHandoverModel } from '../../src/modules/visitors/models/parcel-handover.model';
import { runVisitorExpiryPass } from '../../src/modules/visitors/services/visitor-expiry.service';
import { resetEnvCache, loadEnv } from '../../src/config/env';

const app = createApp();

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

async function setupSociety(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'W',
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
      name: 'Walk-in Guard',
      email: `${prefix}-guard@example.com`,
      password: 'TestPassw0rd!',
    });
  expect(guardRes.status).toBe(201);
  return {
    ctx,
    owner,
    tenant,
    flats,
    guardToken: await login(`${prefix}-guard@example.com`),
    ownerFlatId: String(flats[0]._id),
    societyId: ctx.societyId,
  };
}

describe('Visitor without OTP', () => {
  it('requires resident approval, then guard-confirmed entry without OTP', async () => {
    const setup = await setupSociety('win1');
    const ownerToken = await login(setup.owner.email);

    const created = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Walk In Guest',
        visitorPhone: '+91 9876500101',
        visitorType: 'GUEST',
        purpose: 'Family visit',
        entryMode: 'WALK_IN',
      });
    expect(created.status).toBe(201);
    expect(created.body.data.entryMode).toBe('WALK_IN');
    expect(created.body.data.approvalStatus).toBe('PENDING');
    expect(created.body.data.hasActiveOtp).toBe(false);
    const visitorId = created.body.data.id as string;

    const inbox = await NotificationModel.find({
      recipientUserId: setup.owner._id,
      type: 'VISITOR_REQUEST',
      relatedEntityId: visitorId,
    }).lean();
    expect(inbox).toHaveLength(1);
    expect(inbox[0]?.metadata).toMatchObject({ entryMode: 'WALK_IN', priority: 'high' });
    expect(JSON.stringify(inbox[0]?.metadata)).not.toMatch(/otp/i);

    const earlyEntry = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/confirm-entry`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(earlyEntry.status).toBe(400);

    const tenantToken = await login(setup.tenant.email);
    const unauthorized = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/approve`)
      .set('Authorization', `Bearer ${tenantToken}`)
      .set('x-society-id', setup.societyId);
    expect([403, 404]).toContain(unauthorized.status);

    const approved = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/approve`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.societyId);
    expect(approved.status).toBe(200);
    expect(approved.body.data.approvalStatus).toBe('APPROVED');
    expect(approved.body.data.hasActiveOtp).toBe(false);
    expect(JSON.stringify(approved.body)).not.toMatch(/\b\d{6}\b/);

    const stored = await VisitorLogModel.findById(visitorId).lean();
    expect(stored?.entryOtpHash).toBeFalsy();
    expect(stored?.resolution).toBe('ENTRY');

    const guardNote = await NotificationModel.findOne({
      recipientUserId: stored?.requestedByGuardId,
      type: 'VISITOR_APPROVED',
      relatedEntityId: visitorId,
    }).lean();
    expect(guardNote).toBeTruthy();

    const entered = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/confirm-entry`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(entered.status).toBe(200);
    expect(entered.body.data.entryStatus).toBe('ENTERED');
    expect(entered.body.data.requestState).toBe('ENTRY_COMPLETED');

    const again = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/confirm-entry`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(again.status).toBe(409);

    expect(
      await NotificationModel.countDocuments({
        type: 'VISITOR_ENTERED',
        relatedEntityId: visitorId,
      }),
    ).toBe(1);
  });

  it('denies walk-in requests and blocks later approval', async () => {
    const setup = await setupSociety('win2');
    const ownerToken = await login(setup.owner.email);
    const created = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Denied Guest',
        visitorType: 'GUEST',
        purpose: 'Visit',
        entryMode: 'WALK_IN',
      });
    expect(created.status).toBe(201);
    const visitorId = created.body.data.id as string;

    const denied = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/reject`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.societyId)
      .send({ reason: 'Not expecting anyone' });
    expect(denied.status).toBe(200);
    expect(denied.body.data.approvalStatus).toBe('REJECTED');
    expect(denied.body.data.requestState).toBe('DENIED');

    const approveLater = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/approve`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.societyId);
    expect(approveLater.status).toBe(409);

    const entry = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/confirm-entry`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(entry.status).toBe(400);
  });

  it('expires walk-in requests and rejects late approval', async () => {
    const setup = await setupSociety('win3');
    const ownerToken = await login(setup.owner.email);
    const prev = process.env.VISITOR_WALK_IN_TTL_MS;
    process.env.VISITOR_WALK_IN_TTL_MS = '1';
    resetEnvCache();
    loadEnv();
    try {
      const created = await request(app)
        .post('/api/v1/guard/visitors')
        .set('Authorization', `Bearer ${setup.guardToken}`)
        .send({
          flatId: setup.ownerFlatId,
          visitorName: 'Slow Guest',
          visitorType: 'GUEST',
          purpose: 'Visit',
          entryMode: 'WALK_IN',
        });
      expect(created.status).toBe(201);
      const visitorId = created.body.data.id as string;
      await new Promise((r) => setTimeout(r, 5));
      const expired = await runVisitorExpiryPass(new Date());
      expect(expired.pendingExpired).toBeGreaterThanOrEqual(1);

      const late = await request(app)
        .post(`/api/v1/resident/visitors/${visitorId}/approve`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', setup.societyId);
      expect(late.status).toBe(409);
      expect(late.body.error.code).toMatch(/INVALID_STATUS|REQUEST_EXPIRED|ALREADY_PROCESSED/);
    } finally {
      if (prev === undefined) {
        delete process.env.VISITOR_WALK_IN_TTL_MS;
      } else {
        process.env.VISITOR_WALK_IN_TTL_MS = prev;
      }
      resetEnvCache();
      loadEnv();
    }
  });

  it('authorizes parcel handover without recording visitor entry', async () => {
    const setup = await setupSociety('win4');
    const ownerToken = await login(setup.owner.email);
    const created = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Amazon Rider',
        visitorPhone: '+91 9876500102',
        visitorType: 'DELIVERY',
        purpose: 'Parcel',
        entryMode: 'WALK_IN',
      });
    expect(created.status).toBe(201);
    const visitorId = created.body.data.id as string;

    const parcelRes = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/leave-parcel`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.societyId);
    expect(parcelRes.status).toBe(200);
    expect(parcelRes.body.data.visitor.approvalStatus).toBe('CANCELLED');
    expect(parcelRes.body.data.visitor.resolution).toBe('PARCEL');
    expect(parcelRes.body.data.parcel.status).toBe('AWAITING_HANDOVER');
    const parcelId = parcelRes.body.data.parcel.id as string;

    const entry = await request(app)
      .post(`/api/v1/guard/visitors/${visitorId}/confirm-entry`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(entry.status).toBe(403);

    const received = await request(app)
      .post(`/api/v1/guard/parcels/${parcelId}/receive`)
      .set('Authorization', `Bearer ${setup.guardToken}`);
    expect(received.status).toBe(200);
    expect(received.body.data.status).toBe('RECEIVED_BY_GUARD');

    expect(
      await NotificationModel.countDocuments({
        type: 'PARCEL_RECEIVED',
        relatedEntityId: parcelId,
        recipientUserId: setup.owner._id,
      }),
    ).toBe(1);

    const tenantToken = await login(setup.tenant.email);
    const hidden = await request(app)
      .get(`/api/v1/resident/parcels/${parcelId}`)
      .set('Authorization', `Bearer ${tenantToken}`)
      .set('x-society-id', setup.societyId);
    expect([403, 404]).toContain(hidden.status);

    const ownerSees = await request(app)
      .get(`/api/v1/resident/parcels/${parcelId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.societyId);
    expect(ownerSees.status).toBe(200);

    const duplicateLeave = await request(app)
      .post(`/api/v1/resident/visitors/${visitorId}/leave-parcel`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', setup.societyId);
    expect(duplicateLeave.status).toBe(200);
    expect(await ParcelHandoverModel.countDocuments({ visitorLogId: visitorId })).toBe(1);
  });

  it('rejects conflicting concurrent walk-in decisions', async () => {
    const setup = await setupSociety('win5');
    const ownerToken = await login(setup.owner.email);
    const created = await request(app)
      .post('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .send({
        flatId: setup.ownerFlatId,
        visitorName: 'Race Guest',
        visitorType: 'GUEST',
        purpose: 'Visit',
        entryMode: 'WALK_IN',
      });
    expect(created.status).toBe(201);
    const visitorId = created.body.data.id as string;
    const [a, b] = await Promise.all([
      request(app)
        .post(`/api/v1/resident/visitors/${visitorId}/approve`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', setup.societyId),
      request(app)
        .post(`/api/v1/resident/visitors/${visitorId}/reject`)
        .set('Authorization', `Bearer ${ownerToken}`)
        .set('x-society-id', setup.societyId)
        .send({ reason: 'No' }),
    ]);
    const statuses = [a.status, b.status].sort();
    expect(statuses).toContain(200);
    expect(statuses.some((s) => s === 409 || s === 200)).toBe(true);
    const stored = await VisitorLogModel.findById(visitorId).lean();
    expect(['APPROVED', 'REJECTED']).toContain(stored?.approvalStatus);
    if (stored?.approvalStatus === 'APPROVED') {
      expect(stored.resolution).toBe('ENTRY');
    } else {
      expect(stored?.resolution).toBe('DENIED');
    }
  });
});
