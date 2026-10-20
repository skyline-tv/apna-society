import request from 'supertest';
import type { Express } from 'express';
import type { Role } from '../../src/config/constants';
import { UserModel } from '../../src/modules/users/models/user.model';
import { createUser, TEST_PASSWORD } from './factories';

/** Login via username/password (primary auth path). */
export async function loginAs(
  app: Express,
  email: string,
  roles: Role[] = ['OWNER'],
  societyId?: string,
) {
  const user = await createUser({ email, roles, societyId });
  const result = await loginWithPassword(app, user.username!, TEST_PASSWORD);
  return {
    ...result,
    userId: String(user._id),
    username: user.username!,
    user,
  };
}

/** Login an already-created user by email. */
export async function loginByEmail(app: Express, email: string, password = TEST_PASSWORD) {
  const user = await UserModel.findOne({ email: email.toLowerCase().trim() });
  if (!user) {
    throw new Error(`User not found for login: ${email}`);
  }
  if (!user.username) {
    throw new Error(`User ${email} has no username`);
  }
  return loginWithPassword(app, user.username, password);
}

export async function loginWithPassword(app: Express, username: string, password: string) {
  const login = await request(app).post('/api/v1/auth/login').send({ username, password });
  if (login.status !== 200) {
    throw new Error(`Login failed: ${JSON.stringify(login.body)}`);
  }
  return {
    token: login.body.data.accessToken as string,
    refreshToken: login.body.data.refreshToken as string,
    username,
    mustChangePassword: Boolean(login.body.data.mustChangePassword),
  };
}

/** @deprecated Prefer loginWithPassword — kept for transitional OTP tests only. */
export async function ensureVerifiedMobileForEmail(email: string): Promise<string> {
  const user = await UserModel.findOne({ email: email.toLowerCase().trim() });
  if (!user) {
    throw new Error(`User not found for login: ${email}`);
  }
  if (!user.mobileE164) {
    const { nextTestMobileE164 } = await import('./factories');
    user.mobileE164 = nextTestMobileE164();
    user.phone = user.phone ?? `+${user.mobileE164}`;
  }
  if (!user.mobileVerifiedAt) {
    user.mobileVerifiedAt = new Date();
  }
  await user.save();
  return user.mobileE164;
}
