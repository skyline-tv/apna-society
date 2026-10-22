import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { loginAs as loginAsHelper, loginByEmail } from '../helpers/auth-login';
import { createSociety, createUser } from '../helpers/factories';
import { createAdminContext, createWingWithFlats } from '../helpers/admin';
import { FlatModel } from '../../src/modules/society/models/flat.model';
import { signAccessToken } from '../../src/modules/auth/services/token.service';

const app = createApp();

async function loginAs(email: string, roles: ('ADMIN' | 'OWNER' | 'TENANT' | 'GUARD')[], societyId?: string) {
  const { token } = await loginAsHelper(app, email, roles, societyId);
  return token;
}

describe('Role middleware and society isolation', () => {
  it('blocks non-admin from user listing', async () => {
    const token = await loginAs('owner-role@example.com', ['OWNER']);
    const res = await request(app)
      .get('/api/v1/users')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN_ROLE');
  });

  it('allows admin role through role middleware', async () => {
    const token = await loginAs('admin-role@example.com', ['ADMIN']);
    const res = await request(app)
      .get('/api/v1/users')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('enforces society isolation', async () => {
    const societyA = await createSociety('ISO_A');
    const societyB = await createSociety('ISO_B');
    const token = await loginAs('iso@example.com', ['OWNER'], String(societyA._id));

    const allowed = await request(app)
      .get(`/api/v1/societies/${societyA._id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(allowed.status).toBe(200);

    const denied = await request(app)
      .get(`/api/v1/societies/${societyB._id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(denied.status).toBe(403);
    expect(denied.body.error.code).toBe('SOCIETY_ISOLATION');
  });

  it('rejects invalid access tokens', async () => {
    const res = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer not-a-real-token');
    expect(res.status).toBe(401);
  });

  it('rejects forged tokens with wrong secret payload shape via verify', async () => {
    const token = signAccessToken({
      sub: '507f1f77bcf86cd799439011',
      email: 'x@example.com',
      roles: ['ADMIN'],
      societyIds: [],
    });
    const res = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${token}`);
    // Token is validly signed but user does not exist
    expect(res.status).toBe(401);
  });
});

describe('Input validation and error handling', () => {
  it('validates request-otp body', async () => {
    const res = await request(app).post('/api/v1/auth/request-otp').send({});
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.requestId).toBeTruthy();
  });

  it('validates verify-otp otp format', async () => {
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876543210', otp: 'abc' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('returns structured 404 for unknown routes', async () => {
    const res = await request(app).get('/api/v1/does-not-exist');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('ROUTE_NOT_FOUND');
    expect(res.body.success).toBe(false);
  });

  it('exposes health endpoints', async () => {
    const root = await request(app).get('/health');
    expect(root.status).toBe(200);
    const api = await request(app).get('/api/v1/health');
    expect(api.status).toBe(200);
    expect(api.body.data.database.status).toBe('up');
  });
});

describe('Guard resident privacy', () => {
  it('hides occupancy and resident identity from guard APIs', async () => {
    const ctx = await createAdminContext(app, 'gpriv-admin@example.com', 'GPRIV');
    const { flats } = await createWingWithFlats({
      societyId: ctx.societyId,
      code: 'E',
      flatRates: [4000],
    });
    const owner = await createUser({
      email: 'gpriv-owner@example.com',
      name: 'Hidden Owner',
      roles: ['OWNER'],
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
        email: 'gpriv-guard@example.com',
        phone: '+91 9000000099',
        password: 'TestPassw0rd!',
      });
    expect(guardRes.status).toBe(201);
    const guardToken = (await loginByEmail(app, 'gpriv-guard@example.com')).token;
    const ownerToken = (await loginByEmail(app, owner.email)).token;

    const publicFlats = await request(app)
      .get(`/api/v1/societies/${ctx.societyId}/flats`)
      .set('Authorization', `Bearer ${guardToken}`);
    expect(publicFlats.status).toBe(200);
    expect(publicFlats.body.data).toHaveLength(1);
    expect(publicFlats.body.data[0].label).toBe('E-101');
    expect(JSON.stringify(publicFlats.body)).not.toMatch(
      /occupancyStatus|activeOwner|activeTenant|Hidden Owner|OWNER_OCCUPIED|email/,
    );

    const residentProfile = await request(app)
      .get('/api/v1/resident/profile')
      .set('Authorization', `Bearer ${guardToken}`)
      .set('x-society-id', ctx.societyId);
    expect(residentProfile.status).toBe(403);

    const adminFlats = await request(app)
      .get('/api/v1/admin/flats')
      .set('Authorization', `Bearer ${guardToken}`)
      .set('x-society-id', ctx.societyId);
    expect(adminFlats.status).toBe(403);

    const adminUsers = await request(app)
      .get('/api/v1/admin/users')
      .set('Authorization', `Bearer ${guardToken}`)
      .set('x-society-id', ctx.societyId);
    expect(adminUsers.status).toBe(403);

    const ownerProfile = await request(app)
      .get('/api/v1/resident/profile')
      .set('Authorization', `Bearer ${ownerToken}`)
      .set('x-society-id', ctx.societyId);
    expect(ownerProfile.status).toBe(200);
    expect(ownerProfile.body.data.name).toBe('Hidden Owner');

    const adminList = await request(app)
      .get('/api/v1/admin/flats')
      .set('Authorization', `Bearer ${ctx.token}`)
      .set('x-society-id', ctx.societyId);
    expect(adminList.status).toBe(200);
    expect(adminList.body.data.items[0].occupancyStatus).toBe('OWNER_OCCUPIED');
    expect(adminList.body.data.items[0].label).toBe('E-101');
  });
});
