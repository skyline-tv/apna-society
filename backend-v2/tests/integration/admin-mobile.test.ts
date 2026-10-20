import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { createAdminContext } from '../helpers/admin';
import { createUser } from '../helpers/factories';
import { loginByEmail } from '../helpers/auth-login';
import { UserModel } from '../../src/modules/users/models/user.model';
import { getMemorySmsProvider } from '../../src/modules/auth/providers/memory-sms.provider';

const app = createApp();

describe('Admin mobile workflow', () => {
  it('sets mobile unverified, then confirms ownership for login', async () => {
    const ctx = await createAdminContext(app, 'mobile-admin@example.com', 'MOB_ADM');
    const user = await createUser({
      email: 'mobile-owner@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
      skipMobile: true,
      mobileVerified: false,
    });

    expect(user.mobileE164).toBeUndefined();

    const setRes = await request(app)
      .put(`/api/v1/admin/users/${user._id}/mobile`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ mobile: '9876512345' });
    expect(setRes.status).toBe(200);
    expect(setRes.body.data.mobileE164).toBe('919876512345');
    expect(setRes.body.data.mobileVerified).toBe(false);

    // Unverified — OTP is not delivered.
    const blocked = await request(app)
      .post('/api/v1/auth/request-otp')
      .send({ mobile: '9876512345' });
    expect(blocked.status).toBe(200);
    expect(getMemorySmsProvider().peekOtp('919876512345')).toBeUndefined();

    const confirm = await request(app)
      .post(`/api/v1/admin/users/${user._id}/mobile/confirm`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send();
    expect(confirm.status).toBe(200);
    expect(confirm.body.data.mobileVerified).toBe(true);

    const { token } = await loginByEmail(app, 'mobile-owner@example.com');
    expect(token).toBeTruthy();

    const refreshed = await UserModel.findById(user._id).lean();
    expect(refreshed?.mobileE164).toBe('919876512345');
    expect(refreshed?.mobileVerifiedAt).toBeTruthy();
  });

  it('rejects duplicate verified mobiles', async () => {
    const ctx = await createAdminContext(app, 'mobile-dup-admin@example.com', 'MOB_DUP');
    await createUser({
      email: 'dup-a@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
      mobileE164: '919876599001',
      mobileVerified: true,
    });
    const other = await createUser({
      email: 'dup-b@example.com',
      roles: ['OWNER'],
      societyId: ctx.societyId,
      skipMobile: true,
    });

    const res = await request(app)
      .put(`/api/v1/admin/users/${other._id}/mobile`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({ mobile: '9876599001' });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('DUPLICATE_MOBILE');
  });
});
