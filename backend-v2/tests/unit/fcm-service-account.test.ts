import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { loadEnv, resetEnvCache } from '../../src/config/env';
import { isResidentPushRole } from '../../src/modules/notifications/services/fcm-access';
import {
  readFirebaseServiceAccount,
  resetPushSenderForTests,
} from '../../src/modules/notifications/services/push-sender';

const base = {
  MONGODB_URI: 'mongodb://127.0.0.1:27017/apna_society_test',
  JWT_ACCESS_SECRET: 'test-access-secret-which-is-long-enough-32',
  JWT_REFRESH_SECRET: 'test-refresh-secret-which-is-long-enough-32',
  NODE_ENV: 'test',
  RESEND_API_KEY: '',
  FCM_ENABLED: 'false',
};

afterEach(() => {
  resetPushSenderForTests();
  resetEnvCache();
  process.env.NODE_ENV = 'test';
  loadEnv();
});

describe('Firebase service account loading', () => {
  it('reads credentials from FIREBASE_SERVICE_ACCOUNT_PATH without logging them', () => {
    const dir = mkdtempSync(join(tmpdir(), 'apna-fcm-'));
    const path = join(dir, 'firebase-service-account.json');
    writeFileSync(
      path,
      JSON.stringify({
        type: 'service_account',
        project_id: 'apna-society-test',
        client_email: 'firebase-adminsdk@apna-society-test.iam.gserviceaccount.com',
        private_key: '-----BEGIN PRIVATE KEY-----\\nTEST\\n-----END PRIVATE KEY-----\\n',
      }),
    );
    resetEnvCache();
    loadEnv({
      ...base,
      FIREBASE_SERVICE_ACCOUNT_PATH: path,
      FCM_SERVICE_ACCOUNT_JSON: '',
    });
    const parsed = readFirebaseServiceAccount() as { project_id?: string };
    expect(parsed.project_id).toBe('apna-society-test');
  });

  it('returns null when the service account path is missing', () => {
    resetEnvCache();
    loadEnv({
      ...base,
      FIREBASE_SERVICE_ACCOUNT_PATH: '/tmp/apna-does-not-exist-firebase.json',
      FCM_SERVICE_ACCOUNT_JSON: '',
    });
    expect(readFirebaseServiceAccount()).toBeNull();
  });
});

describe('resident FCM access', () => {
  it('allows owners and tenants and rejects staff', () => {
    expect(isResidentPushRole(['OWNER'])).toBe(true);
    expect(isResidentPushRole(['TENANT'])).toBe(true);
    expect(isResidentPushRole(['ADMIN'])).toBe(false);
    expect(isResidentPushRole(['GUARD'])).toBe(false);
    expect(isResidentPushRole(['OWNER', 'ADMIN'])).toBe(false);
    expect(isResidentPushRole(['TENANT', 'GUARD'])).toBe(false);
  });
});
