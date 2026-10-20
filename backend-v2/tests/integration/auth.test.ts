import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createSociety, createUser } from '../helpers/factories';
import { testOtpInbox } from '../helpers/setup';
import { OtpChallengeModel } from '../../src/modules/auth/models/otp-challenge.model';
import { RefreshSessionModel } from '../../src/modules/auth/models/refresh-session.model';
import { hashToken } from '../../src/utils/crypto';
import { OTP_MAX_ATTEMPTS, OTP_RESEND_COOLDOWN_MS } from '../../src/config/constants';

const app = createApp();

async function requestAndCaptureOtp(email: string) {
  const before = testOtpInbox.length;
  const res = await request(app).post('/api/v1/auth/request-otp').send({ email });
  expect(res.status).toBe(200);
  const entry = testOtpInbox.slice(before).find((item) => item.email === email);
  expect(entry?.otp).toMatch(/^\d{6}$/);
  return entry!.otp;
}

describe('Authentication', () => {
  it('prevents email enumeration for unknown users', async () => {
    const res = await request(app)
      .post('/api/v1/auth/request-otp')
      .send({ email: 'nobody@example.com' });
    expect(res.status).toBe(200);
    expect(res.body.data.message).toMatch(/if an account exists/i);
    expect(testOtpInbox).toHaveLength(0);
  });

  it('does not send OTP when canLogin is false', async () => {
    await createUser({ email: 'locked@example.com', canLogin: false });
    const res = await request(app)
      .post('/api/v1/auth/request-otp')
      .send({ email: 'locked@example.com' });
    expect(res.status).toBe(200);
    expect(testOtpInbox).toHaveLength(0);
  });

  it('verifies OTP and returns tokens without leaking hashes', async () => {
    const society = await createSociety();
    await createUser({
      email: 'owner@example.com',
      roles: ['OWNER'],
      societyId: String(society._id),
    });
    const otp = await requestAndCaptureOtp('owner@example.com');
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'owner@example.com', otp });
    expect(res.status).toBe(200);
    expect(res.body.data.accessToken).toBeTruthy();
    expect(res.body.data.refreshToken).toBeTruthy();
    expect(JSON.stringify(res.body)).not.toMatch(/otpHash|tokenHash/);
  });

  it('rejects invalid OTP', async () => {
    await createUser({ email: 'badotp@example.com' });
    await requestAndCaptureOtp('badotp@example.com');
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'badotp@example.com', otp: '000000' });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_OTP');
  });

  it('enforces OTP expiration', async () => {
    await createUser({ email: 'expired@example.com' });
    const otp = await requestAndCaptureOtp('expired@example.com');
    await OtpChallengeModel.updateOne(
      { email: 'expired@example.com' },
      { $set: { expiresAt: new Date(Date.now() - 1000) } },
    );
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'expired@example.com', otp });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_OTP');
  });

  it('enforces maximum verification attempts', async () => {
    await createUser({ email: 'attempts@example.com' });
    await requestAndCaptureOtp('attempts@example.com');

    for (let i = 0; i < OTP_MAX_ATTEMPTS - 1; i += 1) {
      const res = await request(app)
        .post('/api/v1/auth/verify-otp')
        .send({ email: 'attempts@example.com', otp: '111111' });
      expect(res.status).toBe(401);
    }

    const locked = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'attempts@example.com', otp: '111111' });
    expect(locked.status).toBe(429);
    expect(locked.body.error.code).toBe('OTP_ATTEMPTS_EXCEEDED');
  });

  it('enforces OTP resend cooldown', async () => {
    await createUser({ email: 'cooldown@example.com' });
    await requestAndCaptureOtp('cooldown@example.com');
    const res = await request(app)
      .post('/api/v1/auth/request-otp')
      .send({ email: 'cooldown@example.com' });
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe('OTP_COOLDOWN');
  });

  it('allows resend after cooldown window', async () => {
    await createUser({ email: 'resend@example.com' });
    await requestAndCaptureOtp('resend@example.com');
    await OtpChallengeModel.updateOne(
      { email: 'resend@example.com', consumedAt: { $exists: false } },
      { $set: { lastSentAt: new Date(Date.now() - OTP_RESEND_COOLDOWN_MS - 1000) } },
    );
    const otp2 = await requestAndCaptureOtp('resend@example.com');
    expect(otp2).toMatch(/^\d{6}$/);
  });

  it('rotates refresh tokens', async () => {
    await createUser({ email: 'refresh@example.com' });
    const otp = await requestAndCaptureOtp('refresh@example.com');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'refresh@example.com', otp });
    const firstRefresh = login.body.data.refreshToken as string;

    const rotated = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: firstRefresh });
    expect(rotated.status).toBe(200);
    expect(rotated.body.data.refreshToken).not.toBe(firstRefresh);

    const reuseOld = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: firstRefresh });
    expect(reuseOld.status).toBe(401);
    expect(reuseOld.body.error.code).toBe('REFRESH_REUSE');
  });

  it('detects refresh token reuse and revokes family', async () => {
    await createUser({ email: 'reuse@example.com' });
    const otp = await requestAndCaptureOtp('reuse@example.com');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'reuse@example.com', otp });

    const r1 = login.body.data.refreshToken as string;
    const rot1 = await request(app).post('/api/v1/auth/refresh').send({ refreshToken: r1 });
    const r2 = rot1.body.data.refreshToken as string;

    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: r1 });
    const afterReuse = await request(app).post('/api/v1/auth/refresh').send({ refreshToken: r2 });
    expect(afterReuse.status).toBe(401);

    const active = await RefreshSessionModel.countDocuments({
      tokenHash: hashToken(r2),
      revokedAt: { $exists: false },
    });
    expect(active).toBe(0);
  });

  it('logs out a single session', async () => {
    await createUser({ email: 'logout@example.com' });
    const otp = await requestAndCaptureOtp('logout@example.com');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'logout@example.com', otp });
    const refreshToken = login.body.data.refreshToken as string;

    const logout = await request(app).post('/api/v1/auth/logout').send({ refreshToken });
    expect(logout.status).toBe(200);

    const refresh = await request(app).post('/api/v1/auth/refresh').send({ refreshToken });
    expect(refresh.status).toBe(401);
  });

  it('logs out all devices', async () => {
    await createUser({ email: 'logoutall@example.com' });
    const otp = await requestAndCaptureOtp('logoutall@example.com');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'logoutall@example.com', otp });

    const accessToken = login.body.data.accessToken as string;
    const refreshToken = login.body.data.refreshToken as string;

    // Second session (prior challenge was consumed, so no resend cooldown applies)
    const otp2 = await requestAndCaptureOtp('logoutall@example.com');
    const login2 = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'logoutall@example.com', otp: otp2 });
    const refresh2 = login2.body.data.refreshToken as string;

    const logoutAll = await request(app)
      .post('/api/v1/auth/logout-all')
      .set('Authorization', `Bearer ${accessToken}`)
      .send();
    expect(logoutAll.status).toBe(200);
    expect(logoutAll.body.data.revoked).toBeGreaterThanOrEqual(2);

    const a = await request(app).post('/api/v1/auth/refresh').send({ refreshToken });
    const b = await request(app).post('/api/v1/auth/refresh').send({ refreshToken: refresh2 });
    expect(a.status).toBe(401);
    expect(b.status).toBe(401);
  });

  it('returns authenticated profile via /me', async () => {
    const society = await createSociety('ME_SOC');
    await createUser({
      email: 'me@example.com',
      name: 'Me User',
      roles: ['ADMIN'],
      societyId: String(society._id),
    });
    const otp = await requestAndCaptureOtp('me@example.com');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'Me@Example.com', otp });
    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${login.body.data.accessToken}`);
    expect(me.status).toBe(200);
    expect(me.body.data.email).toBe('me@example.com');
    expect(me.body.data.name).toBe('Me User');
  });
});
