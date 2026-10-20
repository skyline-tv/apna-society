export const OTP_TTL_MS = 5 * 60 * 1000;
export const OTP_MAX_ATTEMPTS = 5;
export const OTP_RESEND_COOLDOWN_MS = 60 * 1000;
export const OTP_REQUEST_WINDOW_MS = 15 * 60 * 1000;
export const OTP_MAX_REQUESTS_PER_WINDOW = 5;
export const OTP_LENGTH = 6;

/** Password login lockout after consecutive failures. */
export const LOGIN_MAX_FAILED_ATTEMPTS = 5;
export const LOGIN_LOCKOUT_MS = 15 * 60 * 1000;

export const API_PREFIX = '/api/v1';

export const ROLES = ['ADMIN', 'OWNER', 'TENANT', 'GUARD'] as const;
export type Role = (typeof ROLES)[number];

export const FLAT_TYPES = ['2BHK', '3BHK'] as const;
export type FlatType = (typeof FLAT_TYPES)[number];

export const OCCUPANCY_STATUSES = ['OWNER_OCCUPIED', 'TENANT_OCCUPIED', 'VACANT'] as const;
export type OccupancyStatus = (typeof OCCUPANCY_STATUSES)[number];

export const DEFAULT_TIMEZONE = 'Asia/Kolkata';
