import { afterEach, describe, expect, it } from 'vitest';
import {
  DEMO_MODE_LABEL,
  getMongoUri,
  isReservedDemoUsername,
  mongoDatabaseName,
} from '../../src/config/demo';
import {
  isDemoPaymentsEnabled,
  isLivePaymentsEnabled,
  loadEnv,
  resetEnvCache,
} from '../../src/config/env';
import { buildReceiptPdf } from '../../src/modules/billing/services/pdf.service';

const demoBase = {
  NODE_ENV: 'test',
  MONGODB_URI: 'mongodb://127.0.0.1:27017/apna_society_unused',
  DEMO_MONGODB_URI: 'mongodb://127.0.0.1:27017/apna_society_demo',
  JWT_ACCESS_SECRET: 'demo-access-secret-which-is-long-enough-32',
  JWT_REFRESH_SECRET: 'demo-refresh-secret-which-is-long-enough-32',
  DEMO_MODE: 'true',
  PAYMENT_GATEWAY_PROVIDER: 'mock',
  PAYMENTS_LIVE_ENABLED: 'false',
  DEMO_PAYMENTS_ENABLED: 'false',
};

afterEach(() => {
  resetEnvCache();
  process.env.NODE_ENV = 'test';
});

describe('demo environment isolation', () => {
  it('requires a dedicated demo database and never falls back to MONGODB_URI', () => {
    const env = loadEnv({ ...demoBase });
    expect(env.DEMO_MODE).toBe(true);
    expect(getMongoUri(env)).toBe(demoBase.DEMO_MONGODB_URI);
    expect(getMongoUri(env)).not.toBe(demoBase.MONGODB_URI);
    expect(mongoDatabaseName(getMongoUri(env))).toBe('apna_society_demo');
    expect(isDemoPaymentsEnabled(env)).toBe(true);
    expect(isLivePaymentsEnabled(env)).toBe(false);
  });

  it('rejects the production database name and identical URIs', () => {
    expect(() =>
      loadEnv({
        ...demoBase,
        DEMO_MONGODB_URI: 'mongodb://127.0.0.1:27017/apna_society',
      }),
    ).toThrow(/production database name/);
    expect(() =>
      loadEnv({
        ...demoBase,
        DEMO_MONGODB_URI: demoBase.MONGODB_URI,
      }),
    ).toThrow(/different database/);
  });

  it('rejects live Razorpay in demo mode', () => {
    expect(() =>
      loadEnv({
        ...demoBase,
        PAYMENT_GATEWAY_PROVIDER: 'razorpay',
        PAYMENTS_LIVE_ENABLED: 'true',
        RAZORPAY_KEY_ID: 'rzp_test',
        RAZORPAY_KEY_SECRET: 'secret',
        RAZORPAY_WEBHOOK_SECRET: 'whsec',
      }),
    ).toThrow(/live Razorpay/);
  });

  it('reserves demo usernames for the demo process only', () => {
    expect(isReservedDemoUsername('demo_admin')).toBe(true);
    expect(isReservedDemoUsername('owner1')).toBe(false);
  });

  it('watermarks demo receipts as simulated sample data', () => {
    const pdf = buildReceiptPdf({
      receiptNumber: 'RCPT-2026-000001',
      societyName: 'Maple Grove Residences',
      flatNumber: '101',
      wingCode: 'A',
      ownerName: 'Rahul Mehta',
      amountPaise: 400_000,
      paymentMethod: 'DEMO',
      paidAt: new Date('2026-03-08T11:00:00.000+05:30'),
      billNumber: 'BILL-2026-000001',
      watermark: DEMO_MODE_LABEL,
    });
    const text = pdf.toString('utf8');
    expect(text).toContain('DEMO MODE - SAMPLE DATA');
    expect(text).toContain('SIMULATED PAYMENT');
    expect(text).toContain('NOT A REAL TRANSACTION');
  });
});
