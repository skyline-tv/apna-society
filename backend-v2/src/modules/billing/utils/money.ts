/**
 * All financial amounts are stored and computed in integer paise (1 INR = 100 paise).
 * Never use floating-point arithmetic for money.
 */

export function rupeesIntegerToPaise(rupees: number): number {
  if (!Number.isInteger(rupees) || rupees < 0) {
    throw new Error(`Expected non-negative integer rupees, got ${rupees}`);
  }
  return rupees * 100;
}

export function paiseToRupeesDisplay(paise: number): string {
  const sign = paise < 0 ? '-' : '';
  const abs = Math.abs(paise);
  const whole = Math.floor(abs / 100);
  const fraction = abs % 100;
  return `${sign}${whole}.${fraction.toString().padStart(2, '0')}`;
}

/**
 * Simple daily interest at annual rate (basis points).
 * Default 2400 bps = 24.00% p.a.
 *
 * interest = floor(principalPaise * annualRateBps * overdueDays / (10000 * 365))
 *
 * Rounding: truncate toward zero via BigInt division (floor for non-negative amounts).
 * Day-count: actual/365 (simple), calendar days overdue after due date.
 */
export function calculateSimpleDailyInterestPaise(
  principalPaise: number,
  overdueDays: number,
  annualRateBps = 2400,
): number {
  if (principalPaise <= 0 || overdueDays <= 0 || annualRateBps <= 0) {
    return 0;
  }
  const numerator =
    BigInt(principalPaise) * BigInt(annualRateBps) * BigInt(overdueDays);
  const denominator = BigInt(10_000) * BigInt(365);
  return Number(numerator / denominator);
}

export function multiplyPaise(paise: number, factor: number): number {
  if (!Number.isInteger(paise) || !Number.isInteger(factor) || factor < 0) {
    throw new Error('multiplyPaise requires non-negative integers');
  }
  return paise * factor;
}
