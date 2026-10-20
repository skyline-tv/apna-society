import { describe, expect, it } from 'vitest';
import {
  assertValidRegistrationNumber,
  isValidIndianRegistrationNumber,
  normalizeRegistrationNumber,
} from '../../src/modules/vehicles/utils/registration-number';

describe('registration number utils', () => {
  it('normalizes uppercase and strips spaces/hyphens', () => {
    expect(normalizeRegistrationNumber(' mh 12-ab 1234 ')).toBe('MH12AB1234');
  });

  it('accepts common Indian formats', () => {
    expect(isValidIndianRegistrationNumber('MH12AB1234')).toBe(true);
    expect(isValidIndianRegistrationNumber('DL1CAA1234')).toBe(true);
    expect(isValidIndianRegistrationNumber('KA03M1234')).toBe(true);
    expect(isValidIndianRegistrationNumber('22BH1234AA')).toBe(true);
  });

  it('rejects invalid plates', () => {
    expect(isValidIndianRegistrationNumber('ABC')).toBe(false);
    expect(isValidIndianRegistrationNumber('1234567890')).toBe(false);
    expect(() => assertValidRegistrationNumber('not-a-plate')).toThrow(
      'INVALID_REGISTRATION_NUMBER',
    );
  });
});
