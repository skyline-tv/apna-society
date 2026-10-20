import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createSociety, createUser } from '../helpers/factories';
import { testOtpInbox } from '../helpers/setup';
import { signAccessToken } from '../../src/modules/auth/services/token.service';

const app = createApp();

async function loginAs(email: string, roles: ('ADMIN' | 'OWNER' | 'TENANT' | 'GUARD')[], societyId?: string) {
  await createUser({ email, roles, societyId });
  await request(app).post('/api/v1/auth/request-otp').send({ email });
  const otp = testOtpInbox.find((x) => x.email === email)!.otp;
  const login = await request(app).post('/api/v1/auth/verify-otp').send({ email, otp });
  return login.body.data.accessToken as string;
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
    const res = await request(app).post('/api/v1/auth/request-otp').send({ email: 'not-an-email' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.requestId).toBeTruthy();
  });

  it('validates verify-otp otp format', async () => {
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'a@example.com', otp: 'abc' });
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
