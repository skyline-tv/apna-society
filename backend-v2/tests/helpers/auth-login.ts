import request from 'supertest';
import type { Express } from 'express';
import type { Role } from '../../src/config/constants';
import { UserModel } from '../../src/modules/users/models/user.model';
import { getMemorySmsProvider } from '../../src/modules/auth/providers/memory-sms.provider';
import { createUser, nextTestMobileE164 } from './factories';

/** Ensure a user has a verified mobile suitable for SMS OTP login (tests only). */
export async function ensureVerifiedMobileForEmail(email: string): Promise<string> {
  const user = await UserModel.findOne({ email: email.toLowerCase().trim() });
  if (!user) {
    throw new Error(`User not found for login: ${email}`);
  }
  if (!user.mobileE164) {
    user.mobileE164 = nextTestMobileE164();
    user.phone = user.phone ?? `+${user.mobileE164}`;
  }
  if (!user.mobileVerifiedAt) {
    user.mobileVerifiedAt = new Date();
  }
  await user.save();
  return user.mobileE164;
}

/** Login via mobile SMS OTP (memory provider in tests). */
export async function loginAs(
  app: Express,
  email: string,
  roles: Role[] = ['OWNER'],
  societyId?: string,
) {
  const user = await createUser({ email, roles, societyId });
  const result = await loginExistingUser(app, user.mobileE164!);
  return {
    ...result,
    userId: String(user._id),
    mobileE164: user.mobileE164!,
    user,
  };
}

/** Login an already-created user by email (assigns verified mobile if missing). */
export async function loginByEmail(app: Express, email: string) {
  const mobileE164 = await ensureVerifiedMobileForEmail(email);
  return loginExistingUser(app, mobileE164);
}

/** Login an already-created user that has a verified mobileE164. */
export async function loginExistingUser(app: Express, mobileE164: string) {
  await request(app).post('/api/v1/auth/request-otp').send({ mobile: `+${mobileE164}` });
  const otp = getMemorySmsProvider().peekOtp(mobileE164);
  if (!otp) {
    throw new Error(`Expected memory SMS OTP for ${mobileE164}`);
  }
  const login = await request(app)
    .post('/api/v1/auth/verify-otp')
    .send({ mobile: `+${mobileE164}`, otp });
  if (login.status !== 200) {
    throw new Error(`Login failed: ${JSON.stringify(login.body)}`);
  }
  return {
    token: login.body.data.accessToken as string,
    refreshToken: login.body.data.refreshToken as string,
    mobileE164,
  };
}
