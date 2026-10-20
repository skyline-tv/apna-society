import { randomBytes } from 'crypto';
import bcrypt from 'bcryptjs';
import { badRequest } from '../shared/errors/app-error';

/** bcrypt cost factor — balanced for interactive login on typical VPS hardware. */
export const PASSWORD_BCRYPT_ROUNDS = 12;

export const PASSWORD_MIN_LENGTH = 10;
export const PASSWORD_MAX_LENGTH = 128;

const HAS_LETTER = /[A-Za-z]/;
const HAS_DIGIT = /\d/;

export function assertPasswordStrength(password: string): void {
  if (typeof password !== 'string') {
    throw badRequest('Password is required', 'WEAK_PASSWORD');
  }
  if (password.length < PASSWORD_MIN_LENGTH) {
    throw badRequest(
      `Password must be at least ${PASSWORD_MIN_LENGTH} characters`,
      'WEAK_PASSWORD',
    );
  }
  if (password.length > PASSWORD_MAX_LENGTH) {
    throw badRequest(
      `Password must be at most ${PASSWORD_MAX_LENGTH} characters`,
      'WEAK_PASSWORD',
    );
  }
  if (/\s/.test(password)) {
    throw badRequest('Password must not contain whitespace', 'WEAK_PASSWORD');
  }
  if (!HAS_LETTER.test(password) || !HAS_DIGIT.test(password)) {
    throw badRequest(
      'Password must include at least one letter and one number',
      'WEAK_PASSWORD',
    );
  }
}

export async function hashPassword(plain: string): Promise<string> {
  assertPasswordStrength(plain);
  return bcrypt.hash(plain, PASSWORD_BCRYPT_ROUNDS);
}

export async function verifyPassword(plain: string, passwordHash: string): Promise<boolean> {
  if (!plain || !passwordHash) return false;
  try {
    return await bcrypt.compare(plain, passwordHash);
  } catch {
    return false;
  }
}

/**
 * Cryptographically strong temporary password for admin provisioning / reset.
 * Never log the returned value.
 */
export function generateTemporaryPassword(length = 16): string {
  const alphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%';
  const bytes = randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i += 1) {
    out += alphabet[bytes[i]! % alphabet.length];
  }
  // Guarantee letter + digit for strength rules.
  if (!HAS_LETTER.test(out)) out = `A${out.slice(1)}`;
  if (!HAS_DIGIT.test(out)) out = `${out.slice(0, -1)}7`;
  return out;
}
