import {
  addCalendarMonths,
  billingPeriodBounds,
  civilDateInTimeZone,
  zonedMidnight,
} from './billing-calendar';

export function billedMonthsProgress(bill: {
  monthlyRatePaise: number;
  numberOfMonths: number;
  baseAmountPaise: number;
  amountPaidPaise: number;
  outstandingPrincipalPaise: number;
  status: string;
}): { paidMonths: number; pendingMonths: number } {
  if (bill.status === 'PAID' || bill.status === 'CANCELLED' || bill.outstandingPrincipalPaise <= 0) {
    return { paidMonths: bill.numberOfMonths, pendingMonths: 0 };
  }
  if (bill.monthlyRatePaise <= 0 || bill.numberOfMonths <= 0) {
    return { paidMonths: 0, pendingMonths: Math.max(0, bill.numberOfMonths) };
  }
  const paidTowardBase = Math.min(Math.max(0, bill.amountPaidPaise), bill.baseAmountPaise);
  const paidMonths = Math.min(
    bill.numberOfMonths,
    Math.floor(paidTowardBase / bill.monthlyRatePaise),
  );
  return { paidMonths, pendingMonths: bill.numberOfMonths - paidMonths };
}

function monthsFromPrincipal(
  principalPaise: number,
  monthlyRatePaise: number,
  numberOfMonths: number,
  baseAmountPaise: number,
): number {
  if (monthlyRatePaise <= 0 || numberOfMonths <= 0) return 0;
  const towardBase = Math.min(Math.max(0, principalPaise), Math.max(0, baseAmountPaise));
  if (towardBase >= baseAmountPaise && baseAmountPaise > 0) return numberOfMonths;
  return Math.min(numberOfMonths, Math.floor(towardBase / monthlyRatePaise));
}

/**
 * Calendar months this payment covers on a bill (not the full bill period).
 * Example: bill Sep–Dec, Sep already paid, this payment settles Oct–Dec.
 */
export function paymentCoveredPeriod(
  bill: {
    billingPeriodStart: Date;
    billingPeriodEnd: Date;
    monthlyRatePaise: number;
    numberOfMonths: number;
    baseAmountPaise: number;
  },
  input: {
    priorPrincipalPaise: number;
    allocatedToPrincipalPaise: number;
  },
  timeZone = 'Asia/Kolkata',
): { periodStart: Date; periodEnd: Date; months: number } {
  const fallback = {
    periodStart: bill.billingPeriodStart,
    periodEnd: bill.billingPeriodEnd,
    months: bill.numberOfMonths,
  };
  if (
    !bill.billingPeriodStart ||
    !bill.billingPeriodEnd ||
    bill.monthlyRatePaise <= 0 ||
    bill.numberOfMonths <= 0
  ) {
    return fallback;
  }

  const priorMonths = monthsFromPrincipal(
    input.priorPrincipalPaise,
    bill.monthlyRatePaise,
    bill.numberOfMonths,
    bill.baseAmountPaise,
  );
  const afterMonths = monthsFromPrincipal(
    input.priorPrincipalPaise + Math.max(0, input.allocatedToPrincipalPaise),
    bill.monthlyRatePaise,
    bill.numberOfMonths,
    bill.baseAmountPaise,
  );
  let thisMonths = Math.max(0, afterMonths - priorMonths);
  if (
    thisMonths === 0 &&
    input.allocatedToPrincipalPaise > 0 &&
    priorMonths < bill.numberOfMonths
  ) {
    // Partial month still counts as covering the next unpaid month for labels/filenames.
    thisMonths = 1;
  }
  if (thisMonths <= 0) return fallback;

  try {
    const startCivil = civilDateInTimeZone(bill.billingPeriodStart, timeZone);
    const coveredStart = addCalendarMonths(startCivil, priorMonths);
    const bounds = billingPeriodBounds(
      zonedMidnight(coveredStart.year, coveredStart.month, 1),
      thisMonths,
      timeZone,
    );
    return {
      periodStart: bounds.periodStart,
      periodEnd: bounds.periodEnd,
      months: thisMonths,
    };
  } catch {
    return fallback;
  }
}
