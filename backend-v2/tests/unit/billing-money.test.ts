import { describe, expect, it } from 'vitest';
import {
  calculateSimpleDailyInterestPaise,
  multiplyPaise,
  paiseToRupeesDisplay,
  rupeesIntegerToPaise,
} from '../../src/modules/billing/utils/money';
import {
  billingPeriodBounds,
  dueDateForBillingPeriod,
  overdueDaysAsOf,
  zonedMidnight,
} from '../../src/modules/billing/utils/billing-calendar';

describe('money utils', () => {
  it('converts integer rupees to paise without floats', () => {
    expect(rupeesIntegerToPaise(4000)).toBe(400_000);
    expect(rupeesIntegerToPaise(5000)).toBe(500_000);
    expect(multiplyPaise(400_000, 3)).toBe(1_200_000);
    expect(paiseToRupeesDisplay(588_000_00)).toBe('588000.00');
  });

  it('computes simple daily interest with floor via bigint', () => {
    // 400000 paise * 2400 bps * 1 day / (10000 * 365) = 263.013... → 263
    expect(calculateSimpleDailyInterestPaise(400_000, 1, 2400)).toBe(263);
    expect(calculateSimpleDailyInterestPaise(400_000, 0, 2400)).toBe(0);
    expect(calculateSimpleDailyInterestPaise(0, 10, 2400)).toBe(0);
  });
});

describe('billing calendar', () => {
  it('builds one-month and three-month calendar periods in IST', () => {
    const start = zonedMidnight(2026, 4, 1);
    const one = billingPeriodBounds(start, 1);
    expect(one.periodStart.toISOString()).toBe(zonedMidnight(2026, 4, 1).toISOString());
    expect(one.periodEnd.toISOString()).toBe(
      new Date('2026-04-30T23:59:59.999+05:30').toISOString(),
    );

    const three = billingPeriodBounds(start, 3);
    expect(three.periodEnd.toISOString()).toBe(
      new Date('2026-06-30T23:59:59.999+05:30').toISOString(),
    );

    const due = dueDateForBillingPeriod(start);
    expect(due.toISOString()).toBe(new Date('2026-04-10T23:59:59.999+05:30').toISOString());
  });

  it('counts overdue days from the 11th', () => {
    const due = new Date('2026-04-10T23:59:59.999+05:30');
    expect(overdueDaysAsOf(due, new Date('2026-04-10T12:00:00+05:30'))).toBe(0);
    expect(overdueDaysAsOf(due, new Date('2026-04-11T00:00:00+05:30'))).toBe(1);
    expect(overdueDaysAsOf(due, new Date('2026-04-12T23:00:00+05:30'))).toBe(2);
  });
});
