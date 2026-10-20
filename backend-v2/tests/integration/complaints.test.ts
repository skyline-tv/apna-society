import { describe, expect, it, beforeEach } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { testOtpInbox } from '../helpers/setup';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { UserModel } from '../../src/modules/users/models/user.model';
import { ComplaintModel } from '../../src/modules/complaints/models/complaint.model';
import { ComplaintHistoryModel } from '../../src/modules/complaints/models/complaint-history.model';
import {
  setComplaintEventEmitterForTests,
  type ComplaintEventPayload,
  type ComplaintSocketEvent,
} from '../../src/modules/complaints/services/complaint-events.service';
import {
  resolveComplaint,
  startComplaint,
} from '../../src/modules/complaints/services/complaint.service';

const app = createApp();

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(64),
]);

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
    code: 'C',
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
    .send({ name: 'Guard', email: `${prefix}-guard@example.com` });
  expect(guardRes.status).toBe(201);

  return {
    ctx,
    owner,
    tenant,
    flats,
    ownerToken: await login(`${prefix}-owner@example.com`),
    tenantToken: await login(`${prefix}-tenant@example.com`),
    guardToken: await login(`${prefix}-guard@example.com`),
    ownerFlatId: String(flats[0]._id),
    otherFlatId: String(flats[1]._id),
  };
}

describe('Resident complaints authorization', () => {
  it('allows owner/tenant correctly and blocks owner-with-tenant, previous tenant, guard, cross-flat', async () => {
    const setup = await setupSociety('cmp');

    const created = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'PLUMBING',
        title: 'Kitchen leak',
        description: 'Water dripping under sink',
      });
    expect(created.status).toBe(201);
    expect(created.body.data.status).toBe('OPEN');
    expect(created.body.data.priority).toBe('MEDIUM');
    expect(created.body.data.internalNotes).toBeUndefined();

    await FlatModel.updateOne(
      { _id: setup.flats[0]._id },
      {
        occupancyStatus: 'TENANT_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: setup.tenant._id,
      },
    );

    const ownerBlocked = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'ELECTRICAL',
        title: 'Socket issue',
        description: 'Socket not working in living room',
      });
    expect(ownerBlocked.status).toBe(403);

    const tenantCreated = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'ELECTRICAL',
        title: 'Socket issue',
        description: 'Socket not working in living room',
      });
    expect(tenantCreated.status).toBe(201);

    await FlatModel.updateOne(
      { _id: setup.flats[0]._id },
      {
        occupancyStatus: 'OWNER_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: null,
      },
    );

    const previousTenant = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'CLEANING',
        title: 'Common area',
        description: 'Needs cleaning near lift',
      });
    expect(previousTenant.status).toBe(403);

    const guardBlocked = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'SECURITY',
        title: 'Gate',
        description: 'Gate sensor issue reported',
      });
    expect(guardBlocked.status).toBe(403);

    const stranger = await createUser({
      email: 'cmp-stranger@example.com',
      roles: ['OWNER'],
      societyId: setup.ctx.societyId,
    });
    await FlatModel.updateOne(
      { _id: setup.flats[1]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: stranger._id },
    );
    const strangerToken = await login('cmp-stranger@example.com');
    const crossFlat = await request(app)
      .get(`/api/v1/resident/complaints/${created.body.data.id}`)
      .set('Authorization', `Bearer ${strangerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(crossFlat.status).toBe(403);

    const other = await createAdminContext(app, 'cmp-other@example.com', 'CMPX');
    const otherAdminList = await request(app)
      .get('/api/v1/admin/complaints')
      .set('Authorization', `Bearer ${other.token}`);
    expect(otherAdminList.status).toBe(200);
    expect(otherAdminList.body.data.items).toHaveLength(0);
  });

  it('allows cancel only while OPEN and blocks admin-field mutation paths', async () => {
    const setup = await setupSociety('cncl');
    const created = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'LIFT',
        title: 'Lift noise',
        description: 'Unusual noise from lift cabin',
      });
    expect(created.status).toBe(201);

    const badPatch = await request(app)
      .patch(`/api/v1/resident/complaints/${created.body.data.id}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ priority: 'URGENT', status: 'RESOLVED' });
    expect(badPatch.status).toBe(404);

    await request(app)
      .post(`/api/v1/admin/complaints/${created.body.data.id}/assign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        assignmentType: 'INTERNAL',
        assignedToUserId: setup.ctx.userId,
      });

    const cancelAssigned = await request(app)
      .post(`/api/v1/resident/complaints/${created.body.data.id}/cancel`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ reason: 'Fixed myself' });
    expect(cancelAssigned.status).toBe(409);

    const open = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'OTHER',
        title: 'Minor issue',
        description: 'Can cancel this one while open',
      });
    const cancelled = await request(app)
      .post(`/api/v1/resident/complaints/${open.body.data.id}/cancel`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({ reason: 'No longer needed' });
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.data.status).toBe('CANCELLED');
  });
});

describe('Admin complaint lifecycle', () => {
  const events: Array<{
    event: ComplaintSocketEvent;
    rooms: string[];
    payload: ComplaintEventPayload;
  }> = [];

  beforeEach(() => {
    events.length = 0;
    setComplaintEventEmitterForTests((event, rooms, payload) => {
      events.push({ event, rooms, payload });
    });
  });

  it('assigns, reassigns, transitions, resolves, closes with history and notifications', async () => {
    const setup = await setupSociety('life');
    const created = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'WATER_SUPPLY',
        title: 'Low pressure',
        description: 'Water pressure low in bathroom',
      });
    const id = created.body.data.id as string;

    const priority = await request(app)
      .patch(`/api/v1/admin/complaints/${id}/priority`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ priority: 'HIGH' });
    expect(priority.status).toBe(200);
    expect(priority.body.data.priority).toBe('HIGH');

    const historyAfterPriority = await ComplaintHistoryModel.find({ complaintId: id }).lean();
    expect(historyAfterPriority.some((h) => h.action === 'PRIORITY_CHANGED')).toBe(true);

    const inactive = await createUser({
      email: 'life-inactive@example.com',
      roles: ['OWNER'],
      societyId: setup.ctx.societyId,
      isActive: false,
    });
    const badAssignee = await request(app)
      .post(`/api/v1/admin/complaints/${id}/assign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ assignmentType: 'INTERNAL', assignedToUserId: String(inactive._id) });
    expect(badAssignee.status).toBe(400);

    const other = await createAdminContext(app, 'life-other@example.com', 'LIFEX');
    const crossAssignee = await request(app)
      .post(`/api/v1/admin/complaints/${id}/assign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ assignmentType: 'INTERNAL', assignedToUserId: other.userId });
    expect(crossAssignee.status).toBe(400);

    const assign = await request(app)
      .post(`/api/v1/admin/complaints/${id}/assign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        assignmentType: 'INTERNAL',
        assignedToUserId: setup.ctx.userId,
      });
    expect(assign.status).toBe(200);
    expect(assign.body.data.status).toBe('ASSIGNED');
    expect(assign.body.data.assignmentType).toBe('INTERNAL');
    expect(events.some((e) => e.event === 'complaint:assigned')).toBe(true);

    const userCountBefore = await UserModel.countDocuments();
    const vendor = await request(app)
      .post(`/api/v1/admin/complaints/${id}/assign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        assignmentType: 'EXTERNAL',
        externalAssignee: { name: 'Ravi Plumber', phone: '+91 9000012345', company: 'FixIt' },
      });
    expect(vendor.status).toBe(200);
    expect(vendor.body.data.assignmentType).toBe('EXTERNAL');
    expect(vendor.body.data.externalAssignee.name).toBe('Ravi Plumber');
    expect(vendor.body.data.assignedToUserId).toBeUndefined();
    expect(await UserModel.countDocuments()).toBe(userCountBefore);

    const unassign = await request(app)
      .post(`/api/v1/admin/complaints/${id}/unassign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ reason: 'Vendor unavailable' });
    expect(unassign.status).toBe(200);
    expect(unassign.body.data.status).toBe('OPEN');

    await request(app)
      .post(`/api/v1/admin/complaints/${id}/assign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ assignmentType: 'INTERNAL', assignedToUserId: setup.ctx.userId });

    const start = await request(app)
      .post(`/api/v1/admin/complaints/${id}/start`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(start.status).toBe(200);
    expect(start.body.data.status).toBe('IN_PROGRESS');

    const resolveNoNotes = await request(app)
      .post(`/api/v1/admin/complaints/${id}/resolve`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({});
    expect(resolveNoNotes.status).toBe(400);

    const resolve = await request(app)
      .post(`/api/v1/admin/complaints/${id}/resolve`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        resolutionNotes: 'Pipe joint replaced',
        internalNotes: 'Vendor invoice #12',
      });
    expect(resolve.status).toBe(200);
    expect(resolve.body.data.status).toBe('RESOLVED');
    expect(resolve.body.data.internalNotes).toBe('Vendor invoice #12');

    const residentView = await request(app)
      .get(`/api/v1/resident/complaints/${id}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(residentView.status).toBe(200);
    expect(residentView.body.data.resolutionNotes).toBe('Pipe joint replaced');
    expect(residentView.body.data.internalNotes).toBeUndefined();
    expect(
      JSON.stringify(residentView.body.data.history).includes('Vendor invoice'),
    ).toBe(false);

    const close = await request(app)
      .post(`/api/v1/admin/complaints/${id}/close`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(close.status).toBe(200);
    expect(close.body.data.status).toBe('CLOSED');
    expect(close.body.data.resolutionNotes).toBe('Pipe joint replaced');

    const invalid = await request(app)
      .post(`/api/v1/admin/complaints/${id}/start`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(invalid.status).toBe(409);

    const summary = await request(app)
      .get('/api/v1/admin/complaints/summary')
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(summary.status).toBe(200);
    expect(summary.body.data.closed).toBeGreaterThanOrEqual(1);
    expect(summary.body.data.total).toBeGreaterThanOrEqual(1);

    const cancelNoReason = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'PARKING',
        title: 'Slot mark faded',
        description: 'Parking slot paint faded badly',
      });
    const adminCancel = await request(app)
      .post(`/api/v1/admin/complaints/${cancelNoReason.body.data.id}/cancel`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({});
    expect(adminCancel.status).toBe(400);

    const adminCancelOk = await request(app)
      .post(`/api/v1/admin/complaints/${cancelNoReason.body.data.id}/cancel`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ reason: 'Duplicate of earlier ticket' });
    expect(adminCancelOk.status).toBe(200);
    expect(adminCancelOk.body.data.status).toBe('CANCELLED');

    // Notifications only after successful commits
    expect(events.every((e) => e.payload.complaintId)).toBe(true);
    expect(JSON.stringify(events).includes('Vendor invoice')).toBe(false);
  });

  it('rejects concurrent conflicting transitions', async () => {
    const setup = await setupSociety('race');
    const created = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'STRUCTURAL',
        title: 'Crack',
        description: 'Hairline crack on balcony wall',
      });
    const id = created.body.data.id as string;
    await request(app)
      .post(`/api/v1/admin/complaints/${id}/assign`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ assignmentType: 'INTERNAL', assignedToUserId: setup.ctx.userId });
    await startComplaint(setup.ctx.societyId, id, {
      userId: setup.ctx.userId,
      role: 'ADMIN',
    });

    const actor = { userId: setup.ctx.userId, role: 'ADMIN' };
    const results = await Promise.allSettled([
      resolveComplaint(setup.ctx.societyId, id, 'Fixed', undefined, actor),
      resolveComplaint(setup.ctx.societyId, id, 'Also fixed', undefined, actor),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled');
    const fail = results.filter((r) => r.status === 'rejected');
    expect(ok).toHaveLength(1);
    expect(fail).toHaveLength(1);

    const history = await ComplaintHistoryModel.find({
      complaintId: id,
      action: 'RESOLVED',
    }).lean();
    expect(history).toHaveLength(1);
    const doc = await ComplaintModel.findById(id).lean();
    expect(doc?.status).toBe('RESOLVED');
  });
});

describe('Complaint attachments', () => {
  it('validates type/size/count and enforces authorization', async () => {
    const setup = await setupSociety('att');
    const created = await request(app)
      .post('/api/v1/resident/complaints')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .send({
        flatId: setup.ownerFlatId,
        category: 'CLEANING',
        title: 'Trash overflow',
        description: 'Bin area overflowing near wing entrance',
      });
    const id = created.body.data.id as string;

    const badType = await request(app)
      .post(`/api/v1/resident/complaints/${id}/attachments`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .attach('file', Buffer.from('hello world not image'), 'note.txt');
    expect(badType.status).toBe(400);

    const ok = await request(app)
      .post(`/api/v1/resident/complaints/${id}/attachments`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId)
      .attach('file', PNG, 'leak.png');
    expect(ok.status).toBe(201);
    expect(ok.body.data.attachment.id).toBeTruthy();
    expect(JSON.stringify(ok.body)).not.toMatch(/storageKey/);

    const attachmentId = ok.body.data.attachment.id as string;
    const download = await request(app)
      .get(`/api/v1/resident/complaints/${id}/attachments/${attachmentId}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(download.status).toBe(200);
    expect(download.headers['content-type']).toMatch(/image\/png/);

    const stranger = await createUser({
      email: 'att-stranger@example.com',
      roles: ['OWNER'],
      societyId: setup.ctx.societyId,
    });
    await FlatModel.updateOne(
      { _id: setup.flats[1]._id },
      { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: stranger._id },
    );
    const strangerToken = await login('att-stranger@example.com');
    const denied = await request(app)
      .get(`/api/v1/resident/complaints/${id}/attachments/${attachmentId}`)
      .set('Authorization', `Bearer ${strangerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(denied.status).toBe(403);
  });
});
