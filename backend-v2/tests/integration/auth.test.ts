import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createSociety, createUser } from '../helpers/factories';
import { OtpChallengeModel } from '../../src/modules/auth/models/otp-challenge.model';
import { getMemorySmsProvider } from '../../src/modules/auth/providers/memory-sms.provider';
import { OTP_MAX_ATTEMPTS, OTP_RESEND_COOLDOWN_MS } from '../../src/config/constants';

const app = createApp();

async function requestAndCaptureOtp(mobile: string) {
  const res = await request(app).post('/api/v1/auth/request-otp').send({ mobile });
  expect(res.status).toBe(200);
  const digits = mobile.replace(/\D/g, '');
  const e164 = digits.length === 10 ? `91${digits}` : digits;
  const otp = getMemorySmsProvider().peekOtp(e164);
  expect(otp).toMatch(/^\d{6}$/);
  return otp!;
}

function mobileUser(email: string, mobile: string, extra: Parameters<typeof createUser>[0] = { email }) {
  const digits = mobile.replace(/\D/g, '');
  const mobileE164 = digits.length === 10 ? `91${digits}` : digits;
  return createUser({
    ...extra,
    email,
    mobileE164,
    mobileVerified: extra.mobileVerified ?? true,
  });
}

describe('Authentication (mobile SMS OTP)', () => {
  it('prevents enumeration for unknown mobiles', async () => {
    const res = await request(app).post('/api/v1/auth/request-otp').send({ mobile: '9876500001' });
    expect(res.status).toBe(200);
    expect(res.body.data.message).toMatch(/if an account exists/i);
    expect(getMemorySmsProvider().peekOtp('919876500001')).toBeUndefined();
  });

  it('does not send OTP when mobile is unverified', async () => {
    await mobileUser('unverified@example.com', '9876500002', {
      email: 'unverified@example.com',
      mobileVerified: false,
    });
    const res = await request(app).post('/api/v1/auth/request-otp').send({ mobile: '9876500002' });
    expect(res.status).toBe(200);
    expect(getMemorySmsProvider().peekOtp('919876500002')).toBeUndefined();
  });

  it('does not send OTP when canLogin is false', async () => {
    await mobileUser('locked@example.com', '9876500003', {
      email: 'locked@example.com',
      canLogin: false,
    });
    const res = await request(app).post('/api/v1/auth/request-otp').send({ mobile: '9876500003' });
    expect(res.status).toBe(200);
    expect(getMemorySmsProvider().peekOtp('919876500003')).toBeUndefined();
  });

  it('verifies OTP and returns tokens without leaking secrets', async () => {
    const society = await createSociety();
    await mobileUser('owner@example.com', '9876500004', {
      email: 'owner@example.com',
      roles: ['OWNER'],
      societyId: String(society._id),
    });
    const otp = await requestAndCaptureOtp('9876500004');
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500004', otp });
    expect(res.status).toBe(200);
    expect(res.body.data.accessToken).toBeTruthy();
    expect(res.body.data.refreshToken).toBeTruthy();
    expect(JSON.stringify(res.body)).not.toMatch(/otpHash|tokenHash|MSG91|authkey/i);
  });

  it('rejects incorrect OTP', async () => {
    await mobileUser('badotp@example.com', '9876500005');
    await requestAndCaptureOtp('9876500005');
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500005', otp: '000000' });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_OTP');
  });

  it('enforces OTP expiration', async () => {
    await mobileUser('expired@example.com', '9876500006');
    const otp = await requestAndCaptureOtp('9876500006');
    await OtpChallengeModel.updateOne(
      { mobileE164: '919876500006' },
      { $set: { expiresAt: new Date(Date.now() - 1000) } },
    );
    const res = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500006', otp });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_OTP');
  });

  it('enforces maximum verification attempts', async () => {
    await mobileUser('attempts@example.com', '9876500007');
    await requestAndCaptureOtp('9876500007');

    for (let i = 0; i < OTP_MAX_ATTEMPTS - 1; i += 1) {
      const res = await request(app)
        .post('/api/v1/auth/verify-otp')
        .send({ mobile: '9876500007', otp: '111111' });
      expect(res.status).toBe(401);
    }

    const locked = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500007', otp: '111111' });
    expect(locked.status).toBe(429);
    expect(locked.body.error.code).toBe('OTP_ATTEMPTS_EXCEEDED');
  });

  it('enforces OTP resend cooldown', async () => {
    await mobileUser('cooldown@example.com', '9876500008');
    await requestAndCaptureOtp('9876500008');
    const res = await request(app).post('/api/v1/auth/request-otp').send({ mobile: '9876500008' });
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe('OTP_COOLDOWN');
  });

  it('allows resend after cooldown window', async () => {
    await mobileUser('resend@example.com', '9876500009');
    await requestAndCaptureOtp('9876500009');
    await OtpChallengeModel.updateOne(
      { mobileE164: '919876500009', consumedAt: { $exists: false } },
      { $set: { lastSentAt: new Date(Date.now() - OTP_RESEND_COOLDOWN_MS - 1000) } },
    );
    const otp2 = await requestAndCaptureOtp('9876500009');
    expect(otp2).toMatch(/^\d{6}$/);
  });

  it('rejects duplicate verified mobiles at the model layer', async () => {
    await mobileUser('dup1@example.com', '9876500010');
    await expect(
      mobileUser('dup2@example.com', '9876500010', { email: 'dup2@example.com' }),
    ).rejects.toThrow();
  });

  it('rotates refresh tokens', async () => {
    await mobileUser('refresh@example.com', '9876500011');
    const otp = await requestAndCaptureOtp('9876500011');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500011', otp });
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

  it('logs out a single session', async () => {
    await mobileUser('logout@example.com', '9876500012');
    const otp = await requestAndCaptureOtp('9876500012');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500012', otp });
    const refreshToken = login.body.data.refreshToken as string;

    const logout = await request(app).post('/api/v1/auth/logout').send({ refreshToken });
    expect(logout.status).toBe(200);

    const refresh = await request(app).post('/api/v1/auth/refresh').send({ refreshToken });
    expect(refresh.status).toBe(401);
  });

  it('returns authenticated profile via /me including mobile fields', async () => {
    const society = await createSociety('ME_SOC');
    await mobileUser('me@example.com', '9876500013', {
      email: 'me@example.com',
      name: 'Me User',
      roles: ['ADMIN'],
      societyId: String(society._id),
    });
    const otp = await requestAndCaptureOtp('9876500013');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '+91 98765 00013', otp });
    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${login.body.data.accessToken}`);
    expect(me.status).toBe(200);
    expect(me.body.data.email).toBe('me@example.com');
    expect(me.body.data.mobileE164).toBe('919876500013');
    expect(me.body.data.mobileVerified).toBe(true);
  });

  it('logs out all devices', async () => {
    await mobileUser('logoutall@example.com', '9876500014');
    const otp = await requestAndCaptureOtp('9876500014');
    const login = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500014', otp });

    const accessToken = login.body.data.accessToken as string;
    const refreshToken = login.body.data.refreshToken as string;

    const otp2 = await requestAndCaptureOtp('9876500014');
    const login2 = await request(app)
      .post('/api/v1/auth/verify-otp')
      .send({ mobile: '9876500014', otp: otp2 });
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
});
