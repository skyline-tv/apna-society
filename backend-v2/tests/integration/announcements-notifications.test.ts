import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { AnnouncementModel } from '../../src/modules/announcements/models/announcement.model';
import { NotificationModel } from '../../src/modules/notifications/models/notification.model';
import {
  claimAndPublishScheduled,
  deliverAnnouncementNotifications,
} from '../../src/modules/announcements/services/announcement-publish.service';
import { createNotification } from '../../src/modules/notifications/services/notification.service';
import {
  setNotificationEventEmitterForTests,
  type NotificationSocketEvent,
  type NotificationSocketPayload,
} from '../../src/modules/notifications/services/notification-events.service';

const app = createApp();

const PNG = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  Buffer.alloc(64),
]);

async function login(email: string) {
  const { token } = await loginByEmail(app, email);
  return token;
}

async function setupSociety(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const wingA = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'A',
    flatRates: [4000, 4000],
  });
  const wingB = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'B',
    flatRates: [4000],
  });
  const otherSociety = await createAdminContext(
    app,
    `${prefix}-other-admin@example.com`,
    `${prefix}OTH`,
  );
  const otherWing = await createWingWithFlats({
    societyId: otherSociety.societyId,
    code: 'X',
    flatRates: [4000],
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
  const ownerB = await createUser({
    email: `${prefix}-ownerb@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });

  await FlatModel.updateOne(
    { _id: wingA.flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
  );
  await FlatModel.updateOne(
    { _id: wingA.flats[1]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: ownerB._id },
  );
  await FlatModel.updateOne(
    { _id: wingB.flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: ownerB._id },
  );

  const guardRes = await request(app)
    .post('/api/v1/admin/guards')
    .set('Authorization', `Bearer ${ctx.token}`)
    .send({ name: 'Guard', email: `${prefix}-guard@example.com` });
  expect(guardRes.status).toBe(201);

  return {
    ctx,
    otherSociety,
    otherWing,
    owner,
    tenant,
    ownerB,
    wingA,
    wingB,
    ownerToken: await login(`${prefix}-owner@example.com`),
    tenantToken: await login(`${prefix}-tenant@example.com`),
    ownerBToken: await login(`${prefix}-ownerb@example.com`),
    guardToken: await login(`${prefix}-guard@example.com`),
    flatA1: String(wingA.flats[0]._id),
    flatA2: String(wingA.flats[1]._id),
    flatB1: String(wingB.flats[0]._id),
  };
}

describe('Announcements admin lifecycle', () => {
  it('creates/edits drafts, publishes, archives; residents cannot create', async () => {
    const setup = await setupSociety('ann1');

    const created = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Water shutdown',
        body: 'Supply interrupted tomorrow 10am-2pm',
        category: 'WATER_SUPPLY',
        priority: 'IMPORTANT',
        audienceType: 'ALL_RESIDENTS',
      });
    expect(created.status).toBe(201);
    expect(created.body.data.status).toBe('DRAFT');
    const id = created.body.data.id as string;

    const patched = await request(app)
      .patch(`/api/v1/admin/announcements/${id}`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ title: 'Water shutdown notice' });
    expect(patched.status).toBe(200);
    expect(patched.body.data.title).toBe('Water shutdown notice');

    const residentCreate = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .send({
        title: 'Nope',
        body: 'Residents cannot publish',
        category: 'GENERAL',
        audienceType: 'ALL_RESIDENTS',
      });
    expect(residentCreate.status).toBe(403);

    const published = await request(app)
      .post(`/api/v1/admin/announcements/${id}/publish`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(published.status).toBe(200);
    expect(published.body.data.status).toBe('PUBLISHED');
    expect(published.body.data.deliveryState).toBe('COMPLETE');

    const feed = await request(app)
      .get('/api/v1/resident/announcements')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(feed.status).toBe(200);
    expect(feed.body.data.items.some((i: { id: string }) => i.id === id)).toBe(true);
    expect(feed.body.data.items[0].adminNotes).toBeUndefined();
    expect(feed.body.data.items[0].deliveryState).toBeUndefined();

    const archived = await request(app)
      .post(`/api/v1/admin/announcements/${id}/archive`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    expect(archived.status).toBe(200);
    expect(archived.body.data.status).toBe('ARCHIVED');
  });

  it('rejects cross-society wing/flat targeting', async () => {
    const setup = await setupSociety('annx');
    const badWing = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Bad wing',
        body: 'Should fail',
        category: 'GENERAL',
        audienceType: 'WING',
        targetWingIds: [String(setup.otherWing.wing._id)],
      });
    expect(badWing.status).toBe(400);

    const badFlat = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Bad flat',
        body: 'Should fail',
        category: 'GENERAL',
        audienceType: 'SELECTED_FLATS',
        targetFlatIds: [String(setup.otherWing.flats[0]._id)],
      });
    expect(badFlat.status).toBe(400);
  });
});

describe('Announcement audience and occupancy', () => {
  it('targets wing and selected flats; respects tenant occupancy and former tenant', async () => {
    const setup = await setupSociety('aud');

    const wingAnn = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Wing A notice',
        body: 'Only wing A',
        category: 'GENERAL',
        audienceType: 'WING',
        targetWingIds: [String(setup.wingA.wing._id)],
      });
    expect(wingAnn.status).toBe(201);
    await request(app)
      .post(`/api/v1/admin/announcements/${wingAnn.body.data.id}/publish`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);

    const ownerSees = await request(app)
      .get('/api/v1/resident/announcements')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(ownerSees.body.data.items.some((i: { title: string }) => i.title === 'Wing A notice')).toBe(
      true,
    );

    const ownerBSees = await request(app)
      .get('/api/v1/resident/announcements')
      .set('Authorization', `Bearer ${setup.ownerBToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(
      ownerBSees.body.data.items.some((i: { title: string }) => i.title === 'Wing A notice'),
    ).toBe(true);

    const flatAnn = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Flat only',
        body: 'Selected flat',
        category: 'MAINTENANCE',
        audienceType: 'SELECTED_FLATS',
        targetFlatIds: [setup.flatA1],
      });
    await request(app)
      .post(`/api/v1/admin/announcements/${flatAnn.body.data.id}/publish`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);

    await FlatModel.updateOne(
      { _id: setup.flatA1 },
      {
        occupancyStatus: 'TENANT_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: setup.tenant._id,
      },
    );

    const ownerBlocked = await request(app)
      .get(`/api/v1/resident/announcements/${flatAnn.body.data.id}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(ownerBlocked.status).toBe(403);

    const tenantSees = await request(app)
      .get(`/api/v1/resident/announcements/${flatAnn.body.data.id}`)
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(tenantSees.status).toBe(200);

    await FlatModel.updateOne(
      { _id: setup.flatA1 },
      {
        occupancyStatus: 'OWNER_OCCUPIED',
        activeOwnerUserId: setup.owner._id,
        activeTenantUserId: null,
      },
    );

    const formerTenant = await request(app)
      .get(`/api/v1/resident/announcements/${flatAnn.body.data.id}`)
      .set('Authorization', `Bearer ${setup.tenantToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(formerTenant.status).toBe(403);

    const guardBlocked = await request(app)
      .get('/api/v1/resident/announcements')
      .set('Authorization', `Bearer ${setup.guardToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(guardBlocked.status).toBe(403);
  });
});

describe('Scheduled publication and cancellation', () => {
  it('publishes scheduled announcements once; cancelled are not delivered; expired hidden', async () => {
    const setup = await setupSociety('sch');

    const scheduledAt = new Date(Date.now() + 60_000);
    const draft = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Scheduled',
        body: 'Later',
        category: 'EVENT',
        audienceType: 'ALL_RESIDENTS',
      });
    const id = draft.body.data.id as string;
    const scheduled = await request(app)
      .post(`/api/v1/admin/announcements/${id}/schedule`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({ scheduledAt: scheduledAt.toISOString() });
    expect(scheduled.status).toBe(200);
    expect(scheduled.body.data.status).toBe('SCHEDULED');

    await AnnouncementModel.updateOne({ _id: id }, { scheduledAt: new Date(Date.now() - 1000) });

    const first = await claimAndPublishScheduled();
    const second = await claimAndPublishScheduled();
    expect(first).not.toBeNull();
    expect(second).toBeNull();

    const count = await NotificationModel.countDocuments({
      type: 'ANNOUNCEMENT',
      relatedEntityId: id,
    });
    expect(count).toBeGreaterThan(0);
    const before = count;
    await deliverAnnouncementNotifications(id);
    expect(await NotificationModel.countDocuments({ type: 'ANNOUNCEMENT', relatedEntityId: id })).toBe(
      before,
    );

    const cancelDraft = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Cancel me',
        body: 'Nope',
        category: 'GENERAL',
        audienceType: 'ALL_RESIDENTS',
      });
    await request(app)
      .post(`/api/v1/admin/announcements/${cancelDraft.body.data.id}/cancel`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    const cancelledNotifs = await NotificationModel.countDocuments({
      relatedEntityId: cancelDraft.body.data.id,
    });
    expect(cancelledNotifs).toBe(0);

    const expired = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Expired soon',
        body: 'Gone',
        category: 'GENERAL',
        audienceType: 'ALL_RESIDENTS',
        expiresAt: new Date(Date.now() + 60_000).toISOString(),
      });
    const expId = expired.body.data.id as string;
    await request(app)
      .post(`/api/v1/admin/announcements/${expId}/publish`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);
    await AnnouncementModel.updateOne({ _id: expId }, { expiresAt: new Date(Date.now() - 1000) });

    const feed = await request(app)
      .get('/api/v1/resident/announcements')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(feed.body.data.items.some((i: { id: string }) => i.id === expId)).toBe(false);
  });
});

describe('Announcement attachments', () => {
  it('accepts image/PDF, rejects invalid content, blocks unauthorized download', async () => {
    const setup = await setupSociety('att');
    const draft = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'With file',
        body: 'Attachment test',
        category: 'GENERAL',
        audienceType: 'SELECTED_FLATS',
        targetFlatIds: [setup.flatA1],
      });
    const id = draft.body.data.id as string;

    const upload = await request(app)
      .post(`/api/v1/admin/announcements/${id}/attachments`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .attach('file', PNG, 'notice.png');
    expect(upload.status).toBe(201);
    const attachmentId = upload.body.data.attachment.id as string;

    const bad = await request(app)
      .post(`/api/v1/admin/announcements/${id}/attachments`)
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .attach('file', Buffer.from('not-a-real-file'), 'bad.txt');
    expect(bad.status).toBe(400);

    await request(app)
      .post(`/api/v1/admin/announcements/${id}/publish`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);

    const ok = await request(app)
      .get(`/api/v1/resident/announcements/${id}/attachments/${attachmentId}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(ok.status).toBe(200);
    expect(ok.headers['content-type']).toContain('image/png');

    const denied = await request(app)
      .get(`/api/v1/resident/announcements/${id}/attachments/${attachmentId}`)
      .set('Authorization', `Bearer ${setup.ownerBToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(denied.status).toBe(403);
  });
});

describe('Notifications APIs and idempotency', () => {
  it('scopes to recipient, idempotent read, no duplicate creates, socket after persist', async () => {
    const setup = await setupSociety('ntf');
    const events: Array<{ event: NotificationSocketEvent; payload: NotificationSocketPayload }> =
      [];
    setNotificationEventEmitterForTests((event, _rooms, payload) => {
      events.push({ event, payload });
    });

    const first = await createNotification({
      societyId: setup.ctx.societyId,
      recipientUserId: String(setup.owner._id),
      type: 'SYSTEM',
      title: 'Hello',
      body: 'World',
      idempotencyKey: `TEST:${setup.ctx.societyId}:1`,
    });
    expect(first.created).toBe(true);
    expect(events.length).toBe(1);

    const dup = await createNotification({
      societyId: setup.ctx.societyId,
      recipientUserId: String(setup.owner._id),
      type: 'SYSTEM',
      title: 'Hello',
      body: 'World',
      idempotencyKey: `TEST:${setup.ctx.societyId}:1`,
    });
    expect(dup.created).toBe(false);
    expect(events.length).toBe(1);

    const list = await request(app)
      .get('/api/v1/resident/notifications')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(list.status).toBe(200);
    expect(list.body.data.items.length).toBeGreaterThanOrEqual(1);
    const nid = first.notification.id;

    const other = await request(app)
      .get(`/api/v1/resident/notifications/${nid}`)
      .set('Authorization', `Bearer ${setup.ownerBToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(other.status).toBe(404);

    const cross = await request(app)
      .get(`/api/v1/resident/notifications/${nid}`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.otherSociety.societyId);
    // No membership in the other society → society isolation (403), not IDOR leak.
    expect(cross.status).toBe(403);

    const read1 = await request(app)
      .post(`/api/v1/resident/notifications/${nid}/read`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    const read2 = await request(app)
      .post(`/api/v1/resident/notifications/${nid}/read`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(read1.status).toBe(200);
    expect(read2.status).toBe(200);
    expect(read2.body.data.isRead).toBe(true);

    const unread = await request(app)
      .get('/api/v1/resident/notifications/unread-count')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(unread.status).toBe(200);

    setNotificationEventEmitterForTests(null);
  });

  it('marks announcement read/unread and unread count', async () => {
    const setup = await setupSociety('read');
    const created = await request(app)
      .post('/api/v1/admin/announcements')
      .set('Authorization', `Bearer ${setup.ctx.token}`)
      .send({
        title: 'Read me',
        body: 'Please read',
        category: 'GENERAL',
        audienceType: 'ALL_RESIDENTS',
      });
    const id = created.body.data.id as string;
    await request(app)
      .post(`/api/v1/admin/announcements/${id}/publish`)
      .set('Authorization', `Bearer ${setup.ctx.token}`);

    const before = await request(app)
      .get('/api/v1/resident/announcements/unread-count')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(before.body.data.unreadCount).toBeGreaterThanOrEqual(1);

    await request(app)
      .post(`/api/v1/resident/announcements/${id}/read`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    await request(app)
      .post(`/api/v1/resident/announcements/${id}/read`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);

    const after = await request(app)
      .get('/api/v1/resident/announcements/unread-count')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(after.body.data.unreadCount).toBe(before.body.data.unreadCount - 1);

    await request(app)
      .post(`/api/v1/resident/announcements/${id}/unread`)
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    const again = await request(app)
      .get('/api/v1/resident/announcements/unread-count')
      .set('Authorization', `Bearer ${setup.ownerToken}`)
      .set('x-society-id', setup.ctx.societyId);
    expect(again.body.data.unreadCount).toBe(before.body.data.unreadCount);
  });
});
