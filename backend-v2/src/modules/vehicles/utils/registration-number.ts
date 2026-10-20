/**
 * Normalize Indian vehicle registration numbers for storage and uniqueness.
 * Uppercase; strip spaces and hyphens.
 */
export function normalizeRegistrationNumber(raw: string): string {
  return raw.trim().toUpperCase().replace(/[\s-]+/g, '');
}

/**
 * Practical Indian plate formats (after normalization):
 * - State series: MH12AB1234, DL1CAA1234, KA03M1234
 * - Bharat series: 22BH1234AA
 */
export function isValidIndianRegistrationNumber(normalized: string): boolean {
  if (!normalized || normalized.length < 6 || normalized.length > 12) {
    return false;
  }
  const stateSeries = /^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$/;
  const bharatSeries = /^[0-9]{2}BH[0-9]{4}[A-Z]{1,2}$/;
  return stateSeries.test(normalized) || bharatSeries.test(normalized);
}

export function assertValidRegistrationNumber(raw: string): string {
  const normalized = normalizeRegistrationNumber(raw);
  if (!isValidIndianRegistrationNumber(normalized)) {
    throw new Error('INVALID_REGISTRATION_NUMBER');
  }
  return normalized;
}
