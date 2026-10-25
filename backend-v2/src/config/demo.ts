import { getEnv, type Env } from './env';

/** Visible in the app, receipts, and public environment endpoint. */
export const DEMO_MODE_LABEL = 'DEMO MODE — SAMPLE DATA';

export const DEMO_SOCIETY_CODE = 'MAPLE_GROVE_DEMO';
export const DEMO_SOCIETY_NAME = 'Maple Grove Residences';

/** Reusable, non-expiring visitor entry OTP. Used only when DEMO_MODE=true. */
export const DEMO_VISITOR_OTP = '246810';

/** Reusable login OTP for the optional mobile flow. Used only when DEMO_MODE=true. */
export const DEMO_LOGIN_OTP = '123456';

export const DEMO_ACCOUNTS = {
  admin: {
    username: 'demo_admin',
    password: 'demo@12345',
    email: 'demo.admin@example.com',
    name: 'Priya Sharma',
    mobileE164: '919000000001',
    role: 'ADMIN' as const,
  },
  owner: {
    username: 'demo_owner',
    password: 'demo@12345',
    email: 'demo.owner@example.com',
    name: 'Rahul Mehta',
    mobileE164: '919000000002',
    role: 'OWNER' as const,
  },
  tenant: {
    username: 'demo_tenant',
    password: 'demo@12345',
    email: 'demo.tenant@example.com',
    name: 'Ananya Iyer',
    mobileE164: '919000000003',
    role: 'TENANT' as const,
  },
  guard: {
    username: 'demo_guard',
    password: 'demo@12345',
    email: 'demo.guard@example.com',
    name: 'Suresh Kulkarni',
    mobileE164: '919000000004',
    role: 'GUARD' as const,
  },
} as const;

export const DEMO_USERNAMES = new Set<string>(
  Object.values(DEMO_ACCOUNTS).map((account) => account.username),
);

export function isDemoMode(env: Env = getEnv()): boolean {
  return env.DEMO_MODE === true;
}

export function isReservedDemoUsername(username: string): boolean {
  return DEMO_USERNAMES.has(username.trim().toLowerCase());
}

/** Database name from a Mongo URI, or empty when the URI cannot be parsed. */
export function mongoDatabaseName(uri: string): string {
  try {
    const normalized = uri.replace(/^mongodb(\+srv)?:\/\//i, 'http://');
    const parsed = new URL(normalized);
    return decodeURIComponent(parsed.pathname.replace(/^\//, '').split('/')[0] ?? '');
  } catch {
    return '';
  }
}

export function mongoConnectionIdentity(uri: string): string {
  try {
    const normalized = uri.replace(/^mongodb(\+srv)?:\/\//i, 'http://');
    const parsed = new URL(normalized);
    return `${parsed.host}/${mongoDatabaseName(uri)}`.toLowerCase();
  } catch {
    return uri.trim().toLowerCase();
  }
}

/** Production default database name — demo seed and DEMO_MODE must never use it. */
export const PRODUCTION_DATABASE_NAME = 'apna_society';

export function assertSafeDemoMongoUri(uri: string): void {
  const name = mongoDatabaseName(uri);
  if (!uri.trim()) {
    throw new Error('DEMO_MONGODB_URI is required when DEMO_MODE=true');
  }
  if (name === PRODUCTION_DATABASE_NAME) {
    throw new Error(
      `DEMO_MONGODB_URI must not use the production database name "${PRODUCTION_DATABASE_NAME}"`,
    );
  }
}

export function getMongoUri(env: Env = getEnv()): string {
  if (isDemoMode(env)) {
    assertSafeDemoMongoUri(env.DEMO_MONGODB_URI);
    return env.DEMO_MONGODB_URI;
  }
  return env.MONGODB_URI;
}
