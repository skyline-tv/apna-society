import { afterEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import {
  DEMO_ACCOUNTS,
  DEMO_LOGIN_OTP,
  DEMO_MODE_LABEL,
  DEMO_VISITOR_OTP,
} from '../../src/config/demo';
import { loadEnv, resetEnvCache } from '../../src/config/env';
import { seedDemoDataset } from '../../src/modules/demo/seed-demo';
import { UserModel } from '../../src/modules/users/models/user.model';
import { TEST_PASSWORD, createUser } from '../helpers/factories';

const app = createApp();

function enableDemoEnv() {
  resetEnvCache();
  loadEnv({
    ...process.env,
    DEMO_MODE: 'true',
    DEMO_MONGODB_URI: `${process.env.MONGODB_URI?.replace(
      /\/[^/?]+(\?|$)/,
      '/apna_society_demo_test$1',
    )}`,
    PAYMENT_GATEWAY_PROVIDER: 'mock',
    PAYMENTS_LIVE_ENABLED: 'false',
  });
}

function restoreTestEnv() {
  resetEnvCache();
  loadEnv();
}

afterEach(() => {
  restoreTestEnv();
});

describe('Google Play demo environment', () => {
  it('seeds fictional data and logs in all four reviewer accounts', async () => {
    enableDemoEnv();
    const seeded = await seedDemoDataset();
    expect(seeded.societyName).toBe('Maple Grove Residences');

    const env = await request(app).get('/api/v1/public/environment');
    expect(env.status).toBe(200);
    expect(env.body.data.demoMode).toBe(true);
    expect(env.body.data.label).toBe(DEMO_MODE_LABEL);
    expect(env.body.data.simulatedPayments).toBe(true);

    for (const account of Object.values(DEMO_ACCOUNTS)) {
      const login = await request(app).post('/api/v1/auth/login').send({
        username: account.username,
        password: account.password,
      });
      expect(login.status).toBe(200);
      expect(login.body.data.accessToken).toBeTruthy();
      expect(login.body.data.mustChangePassword).toBe(false);
      const me = await request(app)
        .get('/api/v1/auth/me')
        .set('Authorization', `Bearer ${login.body.data.accessToken}`);
      expect(me.status).toBe(200);
      expect(me.body.data.roles).toContain(account.role);
    }
  }, 120_000);

  it('accepts the reusable demo login OTP and visitor OTP', async () => {
    enableDemoEnv();
    await seedDemoDataset();

    const otp = await request(app)
      .post('/api/v1/auth/request-otp')
      .send({ mobile: `+${DEMO_ACCOUNTS.owner.mobileE164}` });
    expect(otp.status).toBe(200);
    expect(otp.body.data.debugOtp).toBe(DEMO_LOGIN_OTP);

    const verified = await request(app).post('/api/v1/auth/verify-otp').send({
      mobile: `+${DEMO_ACCOUNTS.owner.mobileE164}`,
      otp: DEMO_LOGIN_OTP,
    });
    expect(verified.status).toBe(200);
    expect(verified.body.data.accessToken).toBeTruthy();

    const guardLogin = await request(app).post('/api/v1/auth/login').send({
      username: DEMO_ACCOUNTS.guard.username,
      password: DEMO_ACCOUNTS.guard.password,
    });
    const token = guardLogin.body.data.accessToken as string;
    const visitors = await request(app)
      .get('/api/v1/guard/visitors')
      .set('Authorization', `Bearer ${token}`);
    expect(visitors.status).toBe(200);
    const pending = (visitors.body.data.items as Array<{ id: string; entryStatus: string }>).find(
      (row) => row.entryStatus === 'NOT_ENTERED',
    );
    expect(pending).toBeTruthy();
    const check = await request(app)
      .post(`/api/v1/guard/visitors/${pending!.id}/verify-entry-otp`)
      .set('Authorization', `Bearer ${token}`)
      .send({ otp: DEMO_VISITOR_OTP });
    expect(check.status).toBe(200);
  }, 120_000);

  it('rejects reserved demo usernames on a non-demo process even if the user exists', async () => {
    restoreTestEnv();
    await createUser({
      email: 'leaked-demo@example.com',
      username: DEMO_ACCOUNTS.admin.username,
      password: TEST_PASSWORD,
      roles: ['ADMIN'],
    });
    const login = await request(app).post('/api/v1/auth/login').send({
      username: DEMO_ACCOUNTS.admin.username,
      password: TEST_PASSWORD,
    });
    expect(login.status).toBe(401);
    expect(login.body.error.code).toBe('INVALID_CREDENTIALS');
    const stillThere = await UserModel.findOne({ username: DEMO_ACCOUNTS.admin.username });
    expect(stillThere).toBeTruthy();
  });

  it('keeps tenant tokens off admin billing routes', async () => {
    enableDemoEnv();
    await seedDemoDataset();
    const tenant = await request(app).post('/api/v1/auth/login').send({
      username: DEMO_ACCOUNTS.tenant.username,
      password: DEMO_ACCOUNTS.tenant.password,
    });
    const denied = await request(app)
      .post('/api/v1/admin/billing/generate')
      .set('Authorization', `Bearer ${tenant.body.data.accessToken}`)
      .send({
        billingPeriodStart: '2026-07-01T00:00:00.000+05:30',
        numberOfMonths: 1,
      });
    expect(denied.status).toBe(403);
  }, 120_000);
});
