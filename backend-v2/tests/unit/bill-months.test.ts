import { describe, expect, it } from 'vitest';
import { billedMonthsProgress } from '../../src/modules/billing/utils/bill-months';
import { nextPeriodStart, zonedMidnight } from '../../src/modules/billing/utils/billing-calendar';

describe('billedMonthsProgress', () => {
  const threeMonth = {
    monthlyRatePaise: 400_000,
    numberOfMonths: 3,
    baseAmountPaise: 1_200_000,
    amountPaidPaise: 0,
    outstandingPrincipalPaise: 1_200_000,
    status: 'ISSUED',
  };

  it('starts with all months pending', () => {
    expect(billedMonthsProgress(threeMonth)).toEqual({ paidMonths: 0, pendingMonths: 3 });
  });

  it('counts one paid month after a single monthly payment', () => {
    expect(
      billedMonthsProgress({
        ...threeMonth,
        amountPaidPaise: 400_000,
        outstandingPrincipalPaise: 800_000,
        status: 'PARTIALLY_PAID',
      }),
    ).toEqual({ paidMonths: 1, pendingMonths: 2 });
  });

  it('treats a fully paid bill as all months paid', () => {
    expect(
      billedMonthsProgress({
        ...threeMonth,
        amountPaidPaise: 1_200_000,
        outstandingPrincipalPaise: 0,
        status: 'PAID',
      }),
    ).toEqual({ paidMonths: 3, pendingMonths: 0 });
  });
});

describe('nextPeriodStart', () => {
  it('starts the following month after a period end', () => {
    expect(nextPeriodStart(new Date('2026-06-30T23:59:59.999+05:30')).toISOString()).toBe(
      zonedMidnight(2026, 7, 1).toISOString(),
    );
  });
});
