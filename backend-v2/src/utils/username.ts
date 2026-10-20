import { badRequest } from '../shared/errors/app-error';

export const USERNAME_MIN_LENGTH = 3;
export const USERNAME_MAX_LENGTH = 32;

/** Lowercase alphanumeric plus underscore and hyphen. */
const USERNAME_PATTERN = /^[a-z0-9][a-z0-9_-]*$/;

/**
 * Trim, lowercase, and validate username.
 * Callers should persist the normalized form and enforce DB uniqueness.
 */
export function normalizeUsername(raw: string): string {
  return String(raw ?? '')
    .trim()
    .toLowerCase();
}

export function assertValidUsername(raw: string): string {
  const username = normalizeUsername(raw);
  if (username.length < USERNAME_MIN_LENGTH || username.length > USERNAME_MAX_LENGTH) {
    throw badRequest(
      `Username must be ${USERNAME_MIN_LENGTH}–${USERNAME_MAX_LENGTH} characters`,
      'INVALID_USERNAME',
    );
  }
  if (!USERNAME_PATTERN.test(username)) {
    throw badRequest(
      'Username may only contain lowercase letters, numbers, underscore, and hyphen',
      'INVALID_USERNAME',
    );
  }
  return username;
}

/** Derive a username candidate from an email local-part (migration helper). */
export function usernameFromEmail(email: string): string {
  const local = String(email ?? '')
    .split('@')[0]
    ?.toLowerCase()
    .replace(/[^a-z0-9_-]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^[-_]+|[-_]+$/g, '') ?? '';
  if (local.length >= USERNAME_MIN_LENGTH) {
    return local.slice(0, USERNAME_MAX_LENGTH);
  }
  return `user_${local || 'account'}`.slice(0, USERNAME_MAX_LENGTH);
}
