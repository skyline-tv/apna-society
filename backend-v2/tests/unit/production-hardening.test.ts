import { describe, expect, it, afterEach } from 'vitest';
import { loadEnv, resetEnvCache } from '../../src/config/env';
import { escapeCsvCell } from '../../src/modules/reports/utils/csv';

const base = {
  MONGODB_URI: 'mongodb://127.0.0.1:27017/apna?replicaSet=rs0',
  JWT_ACCESS_SECRET: 'prod-access-secret-which-is-long-enough-32',
  JWT_REFRESH_SECRET: 'prod-refresh-secret-which-is-long-enough-32',
  RESEND_API_KEY: 're_live_key_example_value',
  NODE_ENV: 'production',
  PAYMENT_GATEWAY_PROVIDER: 'mock',
  PAYMENTS_LIVE_ENABLED: 'false',
  COMPLAINT_STORAGE_PROVIDER: 'local',
  ANNOUNCEMENT_STORAGE_PROVIDER: 'local',
};

afterEach(() => {
  resetEnvCache();
  process.env.NODE_ENV = 'test';
});

describe('production env hardening', () => {
  it('rejects placeholder JWT secrets in production', () => {
    expect(() =>
      loadEnv({
        ...base,
        JWT_ACCESS_SECRET: 'change-me-access-secret-min-32-chars!!',
        JWT_REFRESH_SECRET: 'change-me-refresh-secret-min-32-chars-different!!',
      }),
    ).toThrow(/placeholder/);
  });

  it('requires Resend API key in production', () => {
    expect(() =>
      loadEnv({
        ...base,
        RESEND_API_KEY: '',
      }),
    ).toThrow(/RESEND_API_KEY/);
  });

  it('requires distinct JWT secrets', () => {
    expect(() =>
      loadEnv({
        ...base,
        JWT_REFRESH_SECRET: base.JWT_ACCESS_SECRET,
      }),
    ).toThrow(/distinct/);
  });

  it('requires live Razorpay secrets when PAYMENTS_LIVE_ENABLED', () => {
    expect(() =>
      loadEnv({
        ...base,
        PAYMENT_GATEWAY_PROVIDER: 'razorpay',
        PAYMENTS_LIVE_ENABLED: 'true',
        RAZORPAY_KEY_ID: '',
        RAZORPAY_KEY_SECRET: '',
        RAZORPAY_WEBHOOK_SECRET: '',
      }),
    ).toThrow(/Razorpay/);
  });

  it('accepts a valid production configuration', () => {
    const env = loadEnv({ ...base });
    expect(env.NODE_ENV).toBe('production');
    expect(env.RESEND_API_KEY).toBeTruthy();
  });
});

describe('security helpers still active', () => {
  it('csv escape remains formula-safe', () => {
    expect(escapeCsvCell('=cmd()')).toBe("'=cmd()");
  });
});
