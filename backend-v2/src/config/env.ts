import { config as loadDotenv } from 'dotenv';
import { z } from 'zod';

loadDotenv();

const boolFromEnv = z
  .enum(['true', 'false'])
  .default('false')
  .transform((v) => v === 'true');

const envSchema = z
  .object({
    PORT: z.coerce.number().int().positive().default(4000),
    /** Bind address. Default `0.0.0.0` so LAN devices can reach the API. */
    HOST: z.string().min(1).default('0.0.0.0'),
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    MONGODB_URI: z.string().min(1, 'MONGODB_URI is required'),
    JWT_ACCESS_SECRET: z.string().min(32, 'JWT_ACCESS_SECRET must be at least 32 characters'),
    JWT_REFRESH_SECRET: z.string().min(32, 'JWT_REFRESH_SECRET must be at least 32 characters'),
    ACCESS_TOKEN_EXPIRY: z.string().default('15m'),
    REFRESH_TOKEN_EXPIRY: z.string().default('30d'),
    RESEND_API_KEY: z.string().optional().default(''),
    EMAIL_FROM: z.string().default('Apna Society <noreply@example.com>'),
    // Mobile SMS OTP (MSG91). Keep SMS_OTP_ENABLED=false until DLT/template/sender are approved.
    SMS_PROVIDER: z.enum(['msg91', 'memory']).default('msg91'),
    SMS_OTP_ENABLED: boolFromEnv,
    /**
     * Dev-only: skip MSG91 and accept fixed OTP `123456`.
     * Forbidden in production.
     */
    SMS_OTP_DEV_BYPASS: boolFromEnv,
    MSG91_AUTH_KEY: z.string().optional().default(''),
    MSG91_TEMPLATE_ID: z.string().optional().default(''),
    MSG91_SENDER_ID: z.string().optional().default(''),
    MSG91_BASE_URL: z.string().optional().default('https://control.msg91.com/api/v5'),
    SMS_OTP_EXPIRY_MINUTES: z.coerce.number().int().min(1).max(60).default(5),
    SMS_OTP_LENGTH: z.coerce.number().int().min(4).max(9).default(6),
    CORS_ORIGINS: z.string().default('http://localhost:3000'),
    LOG_LEVEL: z
      .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
      .default('info'),
    // Billing / payments
    BILLING_ANNUAL_INTEREST_BPS: z.coerce.number().int().min(0).max(100_000).default(2400),
    OFFLINE_PAYMENTS_ENABLED: boolFromEnv,
    PAYMENT_GATEWAY_PROVIDER: z.enum(['razorpay', 'mock']).default('mock'),
    RAZORPAY_KEY_ID: z.string().optional().default(''),
    RAZORPAY_KEY_SECRET: z.string().optional().default(''),
    RAZORPAY_WEBHOOK_SECRET: z.string().optional().default(''),
    /** Explicit opt-in required before live Razorpay charges are allowed. */
    PAYMENTS_LIVE_ENABLED: boolFromEnv,
    // Visitors / security (email-only OTP delivery — no SMS)
    VISITOR_OTP_TTL_MS: z.coerce.number().int().positive().default(10 * 60 * 1000),
    VISITOR_OTP_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(20).default(5),
    VISITOR_PENDING_TTL_MS: z.coerce.number().int().positive().default(30 * 60 * 1000),
    VISITOR_EXPIRY_WORKER_ENABLED: boolFromEnv,
    VISITOR_EXPIRY_WORKER_INTERVAL_MS: z.coerce.number().int().positive().default(60_000),
    // Complaints / attachments
    COMPLAINT_STORAGE_PROVIDER: z.enum(['local', 'memory', 's3']).default('local'),
    COMPLAINT_STORAGE_LOCAL_DIR: z.string().default('./storage/complaints'),
    COMPLAINT_ATTACHMENT_MAX_BYTES: z.coerce
      .number()
      .int()
      .positive()
      .default(5 * 1024 * 1024),
    COMPLAINT_ATTACHMENT_MAX_COUNT: z.coerce.number().int().min(1).max(20).default(5),
    COMPLAINT_ALLOWED_MIME_TYPES: z
      .string()
      .default('image/jpeg,image/png,image/webp,image/gif'),
    // Facilities
    FACILITY_PENDING_BOOKING_TTL_MS: z.coerce
      .number()
      .int()
      .positive()
      .default(24 * 60 * 60 * 1000),
    FACILITY_BOOKING_WORKER_ENABLED: boolFromEnv,
    FACILITY_BOOKING_WORKER_INTERVAL_MS: z.coerce.number().int().positive().default(60_000),
    // Announcements / notifications
    ANNOUNCEMENT_WORKER_ENABLED: boolFromEnv,
    ANNOUNCEMENT_WORKER_INTERVAL_MS: z.coerce.number().int().positive().default(30_000),
    /**
     * Daily overdue-interest accrual. Recomputes stored summaries from the ledger
     * (idempotent; never adds the same civil day twice). Default on.
     */
    INTEREST_WORKER_ENABLED: z
      .enum(['true', 'false'])
      .default('true')
      .transform((v) => v === 'true'),
    INTEREST_WORKER_INTERVAL_MS: z.coerce.number().int().positive().default(60 * 60 * 1000),
    ANNOUNCEMENT_STORAGE_PROVIDER: z.enum(['local', 'memory', 's3']).default('local'),
    ANNOUNCEMENT_STORAGE_LOCAL_DIR: z.string().default('./storage/announcements'),
    ANNOUNCEMENT_ATTACHMENT_MAX_BYTES: z.coerce
      .number()
      .int()
      .positive()
      .default(5 * 1024 * 1024),
    ANNOUNCEMENT_ATTACHMENT_MAX_COUNT: z.coerce.number().int().min(1).max(20).default(5),
    ANNOUNCEMENT_ALLOWED_MIME_TYPES: z
      .string()
      .default('image/jpeg,image/png,image/webp,image/gif,application/pdf'),
    // Optional S3-compatible object storage (MinIO / AWS / R2)
    S3_ENDPOINT: z.string().optional().default(''),
    S3_REGION: z.string().optional().default('auto'),
    S3_BUCKET: z.string().optional().default(''),
    S3_ACCESS_KEY_ID: z.string().optional().default(''),
    S3_SECRET_ACCESS_KEY: z.string().optional().default(''),
    S3_FORCE_PATH_STYLE: z
      .enum(['true', 'false'])
      .default('true')
      .transform((v) => v === 'true'),
    S3_KEY_PREFIX: z.string().optional().default('apna-society'),
    // Redis cache (optional — fail-open to MongoDB when unavailable)
    REDIS_ENABLED: boolFromEnv,
    REDIS_URL: z.string().optional().default(''),
    REDIS_PASSWORD: z.string().optional().default(''),
    REDIS_KEY_PREFIX: z.string().default('apna:'),
    CACHE_TTL_DASHBOARD_SECONDS: z.coerce.number().int().min(1).max(3600).default(45),
    CACHE_TTL_REPORTS_SECONDS: z.coerce.number().int().min(1).max(3600).default(45),
    CACHE_TTL_WINGS_SECONDS: z.coerce.number().int().min(1).max(3600).default(300),
    CACHE_TTL_FACILITIES_SECONDS: z.coerce.number().int().min(1).max(3600).default(120),
    CACHE_TTL_ANNOUNCEMENTS_SECONDS: z.coerce.number().int().min(1).max(3600).default(45),
  })
  .superRefine((data, ctx) => {
    if (data.JWT_ACCESS_SECRET === data.JWT_REFRESH_SECRET) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be distinct',
        path: ['JWT_REFRESH_SECRET'],
      });
    }

    const weakPatterns = [/change-me/i, /example/i, /your[_-]?secret/i, /^test-/i];
    if (data.NODE_ENV === 'production') {
      for (const [key, value] of [
        ['JWT_ACCESS_SECRET', data.JWT_ACCESS_SECRET],
        ['JWT_REFRESH_SECRET', data.JWT_REFRESH_SECRET],
      ] as const) {
        if (weakPatterns.some((re) => re.test(value))) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `${key} looks like a placeholder and is not allowed in production`,
            path: [key],
          });
        }
      }
      if (!data.RESEND_API_KEY || data.RESEND_API_KEY.length < 10) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'RESEND_API_KEY is required in production (notification email delivery)',
          path: ['RESEND_API_KEY'],
        });
      }
      if (data.SMS_OTP_DEV_BYPASS) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'SMS_OTP_DEV_BYPASS is not allowed in production',
          path: ['SMS_OTP_DEV_BYPASS'],
        });
      }
      if (data.SMS_OTP_ENABLED && !data.SMS_OTP_DEV_BYPASS) {
        if (data.SMS_PROVIDER === 'msg91') {
          if (!data.MSG91_AUTH_KEY || data.MSG91_AUTH_KEY.length < 8) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: 'MSG91_AUTH_KEY is required when SMS_OTP_ENABLED=true',
              path: ['MSG91_AUTH_KEY'],
            });
          }
          if (!data.MSG91_TEMPLATE_ID) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: 'MSG91_TEMPLATE_ID is required when SMS_OTP_ENABLED=true',
              path: ['MSG91_TEMPLATE_ID'],
            });
          }
        }
        if (data.SMS_PROVIDER === 'memory') {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: 'memory SMS provider is not allowed in production',
            path: ['SMS_PROVIDER'],
          });
        }
      }
      if (!data.MONGODB_URI.includes('replicaSet=') && !data.MONGODB_URI.includes('mongodb+srv://')) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message:
            'Production MONGODB_URI should use a replica set (replicaSet=) or mongodb+srv for transactions',
          path: ['MONGODB_URI'],
        });
      }
      if (data.PAYMENT_GATEWAY_PROVIDER === 'razorpay' || data.PAYMENTS_LIVE_ENABLED) {
        if (!data.RAZORPAY_KEY_ID || !data.RAZORPAY_KEY_SECRET || !data.RAZORPAY_WEBHOOK_SECRET) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message:
              'Live Razorpay requires RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, and RAZORPAY_WEBHOOK_SECRET',
            path: ['RAZORPAY_KEY_SECRET'],
          });
        }
        if (data.PAYMENTS_LIVE_ENABLED && data.PAYMENT_GATEWAY_PROVIDER !== 'razorpay') {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: 'PAYMENTS_LIVE_ENABLED requires PAYMENT_GATEWAY_PROVIDER=razorpay',
            path: ['PAYMENT_GATEWAY_PROVIDER'],
          });
        }
      }
      if (
        data.COMPLAINT_STORAGE_PROVIDER === 's3' ||
        data.ANNOUNCEMENT_STORAGE_PROVIDER === 's3'
      ) {
        if (
          !data.S3_BUCKET ||
          !data.S3_ACCESS_KEY_ID ||
          !data.S3_SECRET_ACCESS_KEY ||
          !data.S3_ENDPOINT
        ) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message:
              'S3 storage requires S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY',
            path: ['S3_BUCKET'],
          });
        }
      }
      if (data.COMPLAINT_STORAGE_PROVIDER === 'memory' || data.ANNOUNCEMENT_STORAGE_PROVIDER === 'memory') {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'memory storage provider is not allowed in production',
          path: ['COMPLAINT_STORAGE_PROVIDER'],
        });
      }
    }

    if (data.PAYMENT_GATEWAY_PROVIDER === 'razorpay' && data.NODE_ENV !== 'test') {
      if (!data.RAZORPAY_KEY_ID || !data.RAZORPAY_KEY_SECRET) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'PAYMENT_GATEWAY_PROVIDER=razorpay requires Razorpay key id and secret',
          path: ['RAZORPAY_KEY_ID'],
        });
      }
    }
  });

export type Env = z.infer<typeof envSchema>;

let cached: Env | null = null;

export function loadEnv(overrides?: Partial<NodeJS.ProcessEnv>): Env {
  const source = { ...process.env, ...overrides };
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((issue) => `${issue.path.join('.')}: ${issue.message}`)
      .join('; ');
    throw new Error(`Invalid environment configuration: ${details}`);
  }
  cached = parsed.data;
  return cached;
}

export function getEnv(): Env {
  if (!cached) {
    return loadEnv();
  }
  return cached;
}

export function resetEnvCache(): void {
  cached = null;
}

export function getCorsOrigins(env: Env = getEnv()): string[] {
  return env.CORS_ORIGINS.split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}

/** True when live gateway charges are explicitly enabled. */
export function isLivePaymentsEnabled(env: Env = getEnv()): boolean {
  return (
    env.PAYMENTS_LIVE_ENABLED &&
    env.PAYMENT_GATEWAY_PROVIDER === 'razorpay' &&
    Boolean(env.RAZORPAY_KEY_ID && env.RAZORPAY_KEY_SECRET && env.RAZORPAY_WEBHOOK_SECRET)
  );
}
