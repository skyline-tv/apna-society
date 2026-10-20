import { describe, expect, it } from 'vitest';
import { generateOtp, hashToken, normalizeEmail, safeEqualHex } from '../../src/utils/crypto';

describe('crypto utils', () => {
  it('normalizes email', () => {
    expect(normalizeEmail('  Foo.Bar@Example.COM ')).toBe('foo.bar@example.com');
  });

  it('generates fixed-length OTP', () => {
    expect(generateOtp(6)).toMatch(/^\d{6}$/);
  });

  it('hashes deterministically and compares safely', () => {
    const a = hashToken('123456');
    const b = hashToken('123456');
    expect(a).toBe(b);
    expect(safeEqualHex(a, b)).toBe(true);
    expect(safeEqualHex(a, hashToken('000000'))).toBe(false);
  });
});
