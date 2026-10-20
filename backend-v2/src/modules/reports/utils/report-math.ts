/**
 * Collection percentage with two decimal places of precision.
 * Formula: floor(collectedPaise * 10000 / billedPaise) / 100
 * Returns 0 when billed is zero (safe empty/zero-bill societies).
 * Uses integer arithmetic for the ratio; display value may be IEEE float.
 */
export function collectionPercentage(collectedPaise: number, billedPaise: number): number {
  if (!Number.isInteger(collectedPaise) || !Number.isInteger(billedPaise)) {
    throw new Error('collectionPercentage requires integer paise amounts');
  }
  if (billedPaise <= 0) return 0;
  if (collectedPaise <= 0) return 0;
  return Math.floor((collectedPaise * 10_000) / billedPaise) / 100;
}

/** Max inclusive span for report date filters (3 years). */
export const REPORT_MAX_RANGE_MS = 3 * 366 * 24 * 60 * 60 * 1000;

/** Default lookback when no date filter is provided. */
export const REPORT_DEFAULT_LOOKBACK_MS = 365 * 24 * 60 * 60 * 1000;
