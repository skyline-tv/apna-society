import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginByEmail } from '../helpers/auth-login';
import { createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { NotificationModel } from '../../src/modules/notifications/models/notification.model';
import { DeviceTokenModel } from '../../src/modules/notifications/models/device-token.model';
import { createNotification } from '../../src/modules/notifications/services/notification.service';
import {
  clearCapturedPushMessages,
  getCapturedPushMessages,
  setPushSenderForTests,
  type PushSender,
} from '../../src/modules/notifications/services/push-sender';
import { deliverPushForNotification } from '../../src/modules/notifications/services/push-delivery.service';

const app = createApp();

async function setupOwner(prefix: string) {
  const ctx = await createAdminContext(app, `${prefix}-admin@example.com`, prefix.toUpperCase());
  const { flats } = await createWingWithFlats({
    societyId: ctx.societyId,
    code: 'P',
    flatRates: [4000],
  });
  const owner = await createUser({
    email: `${prefix}-owner@example.com`,
    roles: ['OWNER'],
    societyId: ctx.societyId,
  });
  await FlatModel.updateOne(
    { _id: flats[0]._id },
    { occupancyStatus: 'OWNER_OCCUPIED', activeOwnerUserId: owner._id },
  );
  const { token } = await loginByEmail(app, owner.email);
  return { ctx, owner, token, societyId: ctx.societyId };
}

describe('Device tokens and push delivery', () => {
  it('registers multiple devices, reassigns a token, and unregisters', async () => {
    const setup = await setupOwner('dtoken');
    const first = await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${setup.token}`)
      .send({ token: 'fcm-token-android-device-one-aaa', platform: 'android', deviceId: 'dev-1' });
    expect(first.status).toBe(201);
    expect(first.body.data.token).toBeUndefined();
    expect(first.body.data.platform).toBe('android');
    expect(first.body.data.isActive).toBe(true);

    const second = await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${setup.token}`)
      .send({ token: 'fcm-token-android-device-two-bbb', platform: 'android', deviceId: 'dev-2' });
    expect(second.status).toBe(201);

    const count = await DeviceTokenModel.countDocuments({
      userId: setup.owner._id,
      isActive: true,
    });
    expect(count).toBe(2);

    const other = await createUser({
      email: 'dtoken-other@example.com',
      roles: ['OWNER'],
      societyId: setup.societyId,
    });
    const { token: otherToken } = await loginByEmail(app, other.email);
    const reassigned = await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${otherToken}`)
      .send({ token: 'fcm-token-android-device-one-aaa', platform: 'android' });
    expect(reassigned.status).toBe(201);
    const moved = await DeviceTokenModel.findOne({ token: 'fcm-token-android-device-one-aaa' }).lean();
    expect(String(moved?.userId)).toBe(String(other._id));

    const removed = await request(app)
      .delete('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${setup.token}`)
      .send({ token: 'fcm-token-android-device-two-bbb' });
    expect(removed.status).toBe(200);
    expect(removed.body.data.unregistered).toBe(true);

    const inactive = await DeviceTokenModel.findOne({
      token: 'fcm-token-android-device-two-bbb',
    }).lean();
    expect(inactive?.isActive).toBe(false);
  });

  it('sends push only when a notification is newly created and strips secrets from payloads', async () => {
    const setup = await setupOwner('dpush');
    await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${setup.token}`)
      .send({ token: 'fcm-token-push-target-ccccccc', platform: 'android' });

    const created = await createNotification({
      societyId: setup.societyId,
      recipientUserId: String(setup.owner._id),
      type: 'VISITOR_ENTERED',
      title: 'Visitor Entered Society',
      body: 'Your visitor has entered the society.',
      relatedEntityType: 'VisitorLog',
      relatedEntityId: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      idempotencyKey: `VISITOR_ENTERED:aaaaaaaaaaaaaaaaaaaaaaaa`,
      metadata: {
        visitorName: 'Ravi',
        otp: '123456',
        password: 'secret',
        deepLink: 'apnasociety://visitor/aaaaaaaaaaaaaaaaaaaaaaaa',
      },
      deliverPush: false,
    });
    expect(created.created).toBe(true);

    await deliverPushForNotification(created.notification.id);
    const messages = getCapturedPushMessages();
    expect(messages.length).toBe(1);
    expect(messages[0]?.title).toBe('Visitor Entered Society');
    expect(JSON.stringify(messages[0]?.data)).not.toMatch(/123456|secret|otp|password/i);
    expect(messages[0]?.data.type).toBe('VISITOR_ENTERED');
    expect(messages[0]?.data.visitorName).toBe('Ravi');

    const duplicate = await createNotification({
      societyId: setup.societyId,
      recipientUserId: String(setup.owner._id),
      type: 'VISITOR_ENTERED',
      title: 'Visitor Entered Society',
      body: 'Your visitor has entered the society.',
      relatedEntityType: 'VisitorLog',
      relatedEntityId: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      idempotencyKey: `VISITOR_ENTERED:aaaaaaaaaaaaaaaaaaaaaaaa`,
      deliverPush: false,
    });
    expect(duplicate.created).toBe(false);
    expect(getCapturedPushMessages().length).toBe(1);
    expect(
      await NotificationModel.countDocuments({
        idempotencyKey: 'VISITOR_ENTERED:aaaaaaaaaaaaaaaaaaaaaaaa',
      }),
    ).toBe(1);
    expect(created.notification.metadata?.otp).toBeUndefined();
  });

  it('sends data-only high-priority Android FCM for walk-in visitor requests', async () => {
    clearCapturedPushMessages();
    const setup = await setupOwner('wcall');
    await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${setup.token}`)
      .send({ token: 'fcm-token-walkin-call-iiiiiiii', platform: 'android' });

    const created = await createNotification({
      societyId: setup.societyId,
      recipientUserId: String(setup.owner._id),
      type: 'VISITOR_REQUEST',
      title: 'Incoming visitor',
      body: 'Guest is at the gate for A-101',
      relatedEntityType: 'VisitorLog',
      relatedEntityId: 'bbbbbbbbbbbbbbbbbbbbbbbb',
      idempotencyKey: 'VISITOR_REQUEST:bbbbbbbbbbbbbbbbbbbbbbbb',
      metadata: {
        visitorName: 'Guest',
        purpose: 'Family visit',
        flatLabel: 'A-101',
        entryMode: 'WALK_IN',
        priority: 'high',
        channel: 'incoming_visitor_call',
        otp: '999999',
      },
      deliverPush: false,
    });
    expect(created.notification.metadata?.otp).toBeUndefined();
    await deliverPushForNotification(created.notification.id);
    const messages = getCapturedPushMessages();
    expect(messages).toHaveLength(1);
    expect(messages[0]?.androidDataOnly).toBe(true);
    expect(messages[0]?.priority).toBe('high');
    expect(messages[0]?.androidChannelId).toBe('incoming_visitor_call');
    expect(messages[0]?.ttlSeconds).toBe(120);
    expect(messages[0]?.data.entryMode).toBe('WALK_IN');
    expect(messages[0]?.data.visitorName).toBe('Guest');
    expect(messages[0]?.data.purpose).toBe('Family visit');
    expect(messages[0]?.data.title).toBe('Incoming visitor');
    expect(JSON.stringify(messages[0]?.data)).not.toMatch(/999999|otp/i);
  });

  it('deactivates unregistered FCM tokens', async () => {
    const setup = await setupOwner('dbad');
    await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${setup.token}`)
      .send({ token: 'fcm-token-invalid-now-ddddddd', platform: 'android' });

    const failingSender: PushSender = {
      isConfigured: () => true,
      send: async (messages) =>
        messages.map((message) => ({
          token: message.token,
          success: false,
          errorCode: 'UNREGISTERED',
        })),
    };
    setPushSenderForTests(failingSender);

    const created = await createNotification({
      societyId: setup.societyId,
      recipientUserId: String(setup.owner._id),
      type: 'SYSTEM',
      title: 'Test',
      body: 'Token cleanup',
      idempotencyKey: `SYSTEM:token-cleanup:${String(setup.owner._id)}`,
      deliverPush: false,
    });
    await deliverPushForNotification(created.notification.id);
    const token = await DeviceTokenModel.findOne({ token: 'fcm-token-invalid-now-ddddddd' }).lean();
    expect(token?.isActive).toBe(false);
    expect(token?.deactivationReason).toBe('UNREGISTERED');
  });

  it('rejects admin and guard device-token registration', async () => {
    const ctx = await createAdminContext(app, 'fcm-admin@example.com', 'FCMADM');
    const adminDenied = await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ token: 'fcm-token-admin-must-not-register', platform: 'android' });
    expect(adminDenied.status).toBe(403);
    expect(adminDenied.body.error.code).toBe('FCM_RESIDENT_ONLY');

    const guardRes = await request(app)
      .post('/api/v1/admin/guards')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Gate',
        email: 'fcm-guard@example.com',
        password: 'TestPassw0rd!',
      });
    expect(guardRes.status).toBe(201);
    const { token: guardToken } = await loginByEmail(app, 'fcm-guard@example.com');
    const guardDenied = await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${guardToken}`)
      .send({ token: 'fcm-token-guard-must-not-register', platform: 'android' });
    expect(guardDenied.status).toBe(403);
    expect(await DeviceTokenModel.countDocuments({})).toBe(0);
  });

  it('lets tenants register tokens and refreshes the token for the same device', async () => {
    const ctx = await createAdminContext(app, 'fcm-ten-admin@example.com', 'FCMTEN');
    const tenant = await createUser({
      email: 'fcm-tenant@example.com',
      roles: ['TENANT'],
      societyId: ctx.societyId,
    });
    const { token } = await loginByEmail(app, tenant.email);
    const first = await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${token}`)
      .send({
        token: 'fcm-token-tenant-device-old-aaaaaa',
        platform: 'android',
        deviceId: 'pixel-1',
      });
    expect(first.status).toBe(201);
    const rotated = await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${token}`)
      .send({
        token: 'fcm-token-tenant-device-new-bbbbbb',
        platform: 'android',
        deviceId: 'pixel-1',
      });
    expect(rotated.status).toBe(201);
    const old = await DeviceTokenModel.findOne({
      token: 'fcm-token-tenant-device-old-aaaaaa',
    }).lean();
    const next = await DeviceTokenModel.findOne({
      token: 'fcm-token-tenant-device-new-bbbbbb',
    }).lean();
    expect(old?.isActive).toBe(false);
    expect(old?.deactivationReason).toBe('TOKEN_REFRESH');
    expect(next?.isActive).toBe(true);
    expect(
      await DeviceTokenModel.countDocuments({ userId: tenant._id, isActive: true }),
    ).toBe(1);
  });

  it('deactivates the current device token on logout and all tokens on logout-all', async () => {
    const setup = await setupOwner('fcmlo');
    const { refreshToken } = await loginByEmail(app, setup.owner.email);
    await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${setup.token}`)
      .send({ token: 'fcm-token-logout-device-eeeeeee', platform: 'android' });
    const logout = await request(app)
      .post('/api/v1/auth/logout')
      .send({ refreshToken, deviceToken: 'fcm-token-logout-device-eeeeeee' });
    expect(logout.status).toBe(200);
    const afterLogout = await DeviceTokenModel.findOne({
      token: 'fcm-token-logout-device-eeeeeee',
    }).lean();
    expect(afterLogout?.isActive).toBe(false);

    const again = await setupOwner('fcmloa');
    await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${again.token}`)
      .send({ token: 'fcm-token-logout-all-one-fffffff', platform: 'android' });
    await request(app)
      .post('/api/v1/me/device-tokens')
      .set('Authorization', `Bearer ${again.token}`)
      .send({ token: 'fcm-token-logout-all-two-ggggggg', platform: 'ios' });
    const logoutAll = await request(app)
      .post('/api/v1/auth/logout-all')
      .set('Authorization', `Bearer ${again.token}`)
      .send();
    expect(logoutAll.status).toBe(200);
    expect(
      await DeviceTokenModel.countDocuments({ userId: again.owner._id, isActive: true }),
    ).toBe(0);
    const one = await DeviceTokenModel.findOne({
      token: 'fcm-token-logout-all-one-fffffff',
    }).lean();
    expect(one?.deactivationReason).toBe('LOGOUT');
  });

  it('does not send FCM to guards even if a token were present', async () => {
    const ctx = await createAdminContext(app, 'fcm-skip-admin@example.com', 'FCMSKIP');
    const guardRes = await request(app)
      .post('/api/v1/admin/guards')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Gate',
        email: 'fcm-skip-guard@example.com',
        password: 'TestPassw0rd!',
      });
    const guardId = guardRes.body.data.guard.id as string;
    await DeviceTokenModel.create({
      userId: guardId,
      societyId: ctx.societyId,
      token: 'fcm-token-guard-stale-hhhhhhhh',
      platform: 'android',
      isActive: true,
      lastSeenAt: new Date(),
    });
    const created = await createNotification({
      societyId: ctx.societyId,
      recipientUserId: guardId,
      type: 'VISITOR_APPROVED',
      title: 'Visitor approved',
      body: 'Confirm entry at the gate.',
      idempotencyKey: `VISITOR_APPROVED:guard-fcm-skip`,
      deliverPush: false,
    });
    await deliverPushForNotification(created.notification.id);
    expect(getCapturedPushMessages()).toHaveLength(0);
    const stored = await NotificationModel.findById(created.notification.id).lean();
    expect(stored?.pushStatus).toBe('SKIPPED');
  });

  it('lets guards read their own inbox via /me/notifications', async () => {
    const ctx = await createAdminContext(app, 'gnote-admin@example.com', 'GNOTE');
    const guardRes = await request(app)
      .post('/api/v1/admin/guards')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Gate',
        email: 'gnote-guard@example.com',
        password: 'TestPassw0rd!',
      });
    expect(guardRes.status).toBe(201);
    const { token } = await loginByEmail(app, 'gnote-guard@example.com');
    await createNotification({
      societyId: ctx.societyId,
      recipientUserId: guardRes.body.data.guard.id as string,
      type: 'VISITOR_APPROVED',
      title: 'Visitor approved',
      body: 'Confirm entry at the gate.',
      idempotencyKey: `VISITOR_APPROVED:guard-inbox-1`,
      deliverPush: false,
    });
    const list = await request(app)
      .get('/api/v1/me/notifications')
      .set('Authorization', `Bearer ${token}`);
    expect(list.status).toBe(200);
    expect(list.body.data.items.some((n: { type: string }) => n.type === 'VISITOR_APPROVED')).toBe(
      true,
    );
  });
});
