import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app';
import { LOGIN_MAX_FAILED_ATTEMPTS } from '../../src/config/constants';
import { UserModel } from '../../src/modules/users/models/user.model';
import { RefreshSessionModel } from '../../src/modules/auth/models/refresh-session.model';
import { verifyPassword } from '../../src/utils/password';
import { createAdminContext } from '../helpers/admin';
import { createSociety, createUser, TEST_PASSWORD } from '../helpers/factories';
import { loginWithPassword } from '../helpers/auth-login';

const app = createApp();

describe('Password authentication', () => {
  it('logs in with valid username and password', async () => {
    const user = await createUser({ email: 'pwd-ok@example.com', username: 'pwdok' });
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdok', password: TEST_PASSWORD });
    expect(res.status).toBe(200);
    expect(res.body.data.accessToken).toBeTruthy();
    expect(res.body.data.refreshToken).toBeTruthy();
    expect(res.body.data.mustChangePassword).toBe(false);
    expect(JSON.stringify(res.body)).not.toMatch(/passwordHash|password|otpHash/i);
    expect(String(user._id)).toBeTruthy();
  });

  it('rejects invalid username with generic credentials error', async () => {
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'nobodyhere', password: TEST_PASSWORD });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
    expect(res.body.error.message).toMatch(/invalid username or password/i);
  });

  it('rejects invalid password with generic credentials error', async () => {
    await createUser({ email: 'pwd-bad@example.com', username: 'pwdbad' });
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdbad', password: 'WrongPassw0rd!' });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
  });

  it('rejects disabled accounts with generic credentials error', async () => {
    await createUser({
      email: 'pwd-off@example.com',
      username: 'pwdoff',
      canLogin: false,
    });
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdoff', password: TEST_PASSWORD });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
  });

  it('rejects inactive accounts', async () => {
    await createUser({
      email: 'pwd-inact@example.com',
      username: 'pwdinact',
      isActive: false,
    });
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdinact', password: TEST_PASSWORD });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
  });

  it('rejects users without a password (migration pending credentials)', async () => {
    await createUser({
      email: 'pwd-migr@example.com',
      username: 'pwdmigr',
      skipPassword: true,
    });
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdmigr', password: TEST_PASSWORD });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
  });

  it('stores bcrypt hashes and never returns them', async () => {
    const user = await createUser({ email: 'pwd-hash@example.com', username: 'pwdhash' });
    const stored = await UserModel.findById(user._id).select('+passwordHash').lean();
    expect(stored?.passwordHash).toMatch(/^\$2[aby]?\$/);
    expect(await verifyPassword(TEST_PASSWORD, stored!.passwordHash!)).toBe(true);

    const meLogin = await loginWithPassword(app, 'pwdhash', TEST_PASSWORD);
    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${meLogin.token}`);
    expect(me.status).toBe(200);
    expect(me.body.data.username).toBe('pwdhash');
    expect(me.body.data.mustChangePassword).toBe(false);
    expect(JSON.stringify(me.body)).not.toMatch(/passwordHash/);
  });

  it('enforces unique usernames on provision', async () => {
    const ctx = await createAdminContext(app, 'pwd-dup-admin@example.com', 'PWD_DUP');
    const first = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'One',
        email: 'pwd-dup1@example.com',
        role: 'OWNER',
        username: 'sharedu',
        password: TEST_PASSWORD,
      });
    expect(first.status).toBe(201);

    const second = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({
        name: 'Two',
        email: 'pwd-dup2@example.com',
        role: 'OWNER',
        username: 'sharedu',
        password: TEST_PASSWORD,
      });
    expect(second.status).toBe(409);
    expect(second.body.error.code).toBe('DUPLICATE_USERNAME');
  });

  it('forces password change for temporary credentials', async () => {
    const user = await createUser({
      email: 'pwd-temp@example.com',
      username: 'pwdtemp',
      mustChangePassword: true,
    });
    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdtemp', password: TEST_PASSWORD });
    expect(login.status).toBe(200);
    expect(login.body.data.mustChangePassword).toBe(true);

    const change = await request(app)
      .post('/api/v1/auth/change-password')
      .set('Authorization', `Bearer ${login.body.data.accessToken}`)
      .send({
        currentPassword: TEST_PASSWORD,
        newPassword: 'NewSecure99!',
        confirmPassword: 'NewSecure99!',
      });
    expect(change.status).toBe(200);
    expect(change.body.data.mustChangePassword).toBe(false);

    const refreshed = await UserModel.findById(user._id).lean();
    expect(refreshed?.mustChangePassword).toBe(false);

    // Sessions revoked after password change
    const active = await RefreshSessionModel.countDocuments({
      userId: user._id,
      revokedAt: { $exists: false },
    });
    expect(active).toBe(0);

    const relogin = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdtemp', password: 'NewSecure99!' });
    expect(relogin.status).toBe(200);
    expect(relogin.body.data.mustChangePassword).toBe(false);
  });

  it('requires current password when changing', async () => {
    await createUser({ email: 'pwd-chg@example.com', username: 'pwdchg' });
    const login = await loginWithPassword(app, 'pwdchg', TEST_PASSWORD);
    const bad = await request(app)
      .post('/api/v1/auth/change-password')
      .set('Authorization', `Bearer ${login.token}`)
      .send({
        currentPassword: 'WrongPassw0rd!',
        newPassword: 'NewSecure99!',
        confirmPassword: 'NewSecure99!',
      });
    expect(bad.status).toBe(401);
    expect(bad.body.error.code).toBe('INVALID_CURRENT_PASSWORD');
  });

  it('supports admin-assisted password reset and revokes sessions', async () => {
    const society = await createSociety('PWD_RESET');
    const ctx = await createAdminContext(app, 'pwd-reset-admin@example.com', 'PWD_RESET2');
    // Use ctx society
    const user = await createUser({
      email: 'pwd-reset-user@example.com',
      username: 'pwdreset',
      societyId: ctx.societyId,
    });
    const before = await loginWithPassword(app, 'pwdreset', TEST_PASSWORD);

    const reset = await request(app)
      .post(`/api/v1/admin/users/${user._id}/password`)
      .set('Authorization', `Bearer ${ctx.token}`)
      .send({});
    expect(reset.status).toBe(200);
    expect(reset.body.data.temporaryPassword).toBeTruthy();
    expect(reset.body.data.mustChangePassword).toBe(true);
    expect(JSON.stringify(reset.body)).not.toMatch(/passwordHash/);

    const oldRefresh = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: before.refreshToken });
    expect(oldRefresh.status).toBe(401);

    const fresh = await request(app)
      .post('/api/v1/auth/login')
      .send({
        username: 'pwdreset',
        password: reset.body.data.temporaryPassword,
      });
    expect(fresh.status).toBe(200);
    expect(fresh.body.data.mustChangePassword).toBe(true);
    expect(String(society._id)).toBeTruthy();
  });

  it('rotates refresh tokens and supports logout', async () => {
    await createUser({ email: 'pwd-ref@example.com', username: 'pwdref' });
    const login = await loginWithPassword(app, 'pwdref', TEST_PASSWORD);
    const rotated = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: login.refreshToken });
    expect(rotated.status).toBe(200);
    expect(rotated.body.data.refreshToken).not.toBe(login.refreshToken);

    const reuse = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: login.refreshToken });
    expect(reuse.status).toBe(401);

    await request(app)
      .post('/api/v1/auth/logout')
      .send({ refreshToken: rotated.body.data.refreshToken });

    const afterLogout = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: rotated.body.data.refreshToken });
    expect(afterLogout.status).toBe(401);
  });

  it('locks account after repeated failed login attempts', async () => {
    await createUser({ email: 'pwd-lock@example.com', username: 'pwdlock' });
    for (let i = 0; i < LOGIN_MAX_FAILED_ATTEMPTS; i += 1) {
      const res = await request(app)
        .post('/api/v1/auth/login')
        .send({ username: 'pwdlock', password: 'WrongPassw0rd!' });
      expect(res.status).toBe(401);
    }
    const locked = await request(app)
      .post('/api/v1/auth/login')
      .send({ username: 'pwdlock', password: 'WrongPassw0rd!' });
    expect(locked.status).toBe(429);
    expect(locked.body.error.code).toBe('LOGIN_LOCKED');
  });

  it('preserves roles from server after password login', async () => {
    await createUser({
      email: 'pwd-role@example.com',
      username: 'pwdrole',
      roles: ['ADMIN'],
    });
    const login = await loginWithPassword(app, 'pwdrole', TEST_PASSWORD);
    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${login.token}`);
    expect(me.body.data.roles).toContain('ADMIN');
  });
});
