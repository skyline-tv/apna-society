import { describe, expect, it } from 'vitest';
import { computeInterestFromPrincipalTimeline } from '../../src/modules/billing/services/interest.service';
import { calculateSimpleDailyInterestPaise } from '../../src/modules/billing/utils/money';
import { zonedMidnight } from '../../src/modules/billing/utils/billing-calendar';

describe('segment interest from principal ledger', () => {
  const dueDate = new Date('2026-04-10T23:59:59.999+05:30');
  const opening = 400_000;

  it('accrues full principal until a mid-period partial payment, then reduced principal', () => {
    const result = computeInterestFromPrincipalTimeline({
      dueDate,
      openingPrincipalPaise: opening,
      events: [
        {
          deltaPrincipalPaise: opening,
          principalAfterPaise: opening,
          effectiveAt: zonedMidnight(2026, 4, 1),
        },
        {
          deltaPrincipalPaise: -100_000,
          principalAfterPaise: 300_000,
          effectiveAt: zonedMidnight(2026, 4, 15),
        },
      ],
      asOf: new Date('2026-04-16T10:00:00+05:30'),
      timeZone: 'Asia/Kolkata',
      annualRateBps: 2400,
    });

    const expected =
      calculateSimpleDailyInterestPaise(400_000, 4, 2400) +
      calculateSimpleDailyInterestPaise(300_000, 2, 2400);
    expect(result.accruedInterestPaise).toBe(expected);
    expect(result.principalOutstandingPaise).toBe(300_000);
    expect(result.segments.length).toBeGreaterThanOrEqual(2);
  });

  it('ignores later payments when calculating a historical as-of date', () => {
    const result = computeInterestFromPrincipalTimeline({
      dueDate,
      openingPrincipalPaise: opening,
      events: [
        {
          deltaPrincipalPaise: opening,
          principalAfterPaise: opening,
          effectiveAt: zonedMidnight(2026, 4, 1),
        },
        {
          deltaPrincipalPaise: -100_000,
          principalAfterPaise: 300_000,
          effectiveAt: zonedMidnight(2026, 4, 15),
        },
      ],
      asOf: new Date('2026-04-14T12:00:00+05:30'),
      timeZone: 'Asia/Kolkata',
      annualRateBps: 2400,
    });

    expect(result.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400),
    );
    expect(result.principalOutstandingPaise).toBe(400_000);
  });

  it('handles multiple partial payments chronologically without compounding', () => {
    const result = computeInterestFromPrincipalTimeline({
      dueDate,
      openingPrincipalPaise: opening,
      events: [
        {
          deltaPrincipalPaise: opening,
          principalAfterPaise: opening,
          effectiveAt: zonedMidnight(2026, 4, 1),
        },
        {
          deltaPrincipalPaise: -100_000,
          principalAfterPaise: 300_000,
          effectiveAt: zonedMidnight(2026, 4, 13),
        },
        {
          deltaPrincipalPaise: -100_000,
          principalAfterPaise: 200_000,
          effectiveAt: zonedMidnight(2026, 4, 16),
        },
      ],
      asOf: new Date('2026-04-18T12:00:00+05:30'),
      timeZone: 'Asia/Kolkata',
      annualRateBps: 2400,
    });

    const expected =
      calculateSimpleDailyInterestPaise(400_000, 2, 2400) + // 11-12
      calculateSimpleDailyInterestPaise(300_000, 3, 2400) + // 13-15
      calculateSimpleDailyInterestPaise(200_000, 3, 2400); // 16-18
    expect(result.accruedInterestPaise).toBe(expected);
    // Not equal to interest-on-interest or single reduced-principal backfill
    expect(result.accruedInterestPaise).not.toBe(
      calculateSimpleDailyInterestPaise(200_000, 8, 2400),
    );
  });

  it('stops accruing after principal reaches zero and preserves prior accrued interest', () => {
    const result = computeInterestFromPrincipalTimeline({
      dueDate,
      openingPrincipalPaise: opening,
      events: [
        {
          deltaPrincipalPaise: opening,
          principalAfterPaise: opening,
          effectiveAt: zonedMidnight(2026, 4, 1),
        },
        {
          deltaPrincipalPaise: -400_000,
          principalAfterPaise: 0,
          effectiveAt: zonedMidnight(2026, 4, 15),
        },
      ],
      asOf: new Date('2026-04-30T12:00:00+05:30'),
      timeZone: 'Asia/Kolkata',
      annualRateBps: 2400,
    });

    expect(result.principalOutstandingPaise).toBe(0);
    expect(result.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 4, 2400),
    );
  });

  it('uses the stored due date so interest starts the day after a 15th due date', () => {
    const customDue = new Date('2026-04-15T23:59:59.999+05:30');
    const onDue = computeInterestFromPrincipalTimeline({
      dueDate: customDue,
      openingPrincipalPaise: opening,
      events: [
        {
          deltaPrincipalPaise: opening,
          principalAfterPaise: opening,
          effectiveAt: zonedMidnight(2026, 4, 1),
        },
      ],
      asOf: new Date('2026-04-15T23:00:00+05:30'),
      timeZone: 'Asia/Kolkata',
      annualRateBps: 2400,
    });
    expect(onDue.overdueDays).toBe(0);
    expect(onDue.accruedInterestPaise).toBe(0);

    const afterPartial = computeInterestFromPrincipalTimeline({
      dueDate: customDue,
      openingPrincipalPaise: opening,
      events: [
        {
          deltaPrincipalPaise: opening,
          principalAfterPaise: opening,
          effectiveAt: zonedMidnight(2026, 4, 1),
        },
        {
          deltaPrincipalPaise: -100_000,
          principalAfterPaise: 300_000,
          effectiveAt: zonedMidnight(2026, 4, 18),
        },
      ],
      asOf: new Date('2026-04-20T12:00:00+05:30'),
      timeZone: 'Asia/Kolkata',
      annualRateBps: 2400,
    });
    expect(afterPartial.overdueDays).toBe(5);
    expect(afterPartial.accruedInterestPaise).toBe(
      calculateSimpleDailyInterestPaise(400_000, 2, 2400) + // 16-17
        calculateSimpleDailyInterestPaise(300_000, 3, 2400), // 18-20
    );
    expect(afterPartial.principalOutstandingPaise).toBe(300_000);
  });

  it('applies refund restoration to future interest only', () => {
    const result = computeInterestFromPrincipalTimeline({
      dueDate,
      openingPrincipalPaise: opening,
      events: [
        {
          deltaPrincipalPaise: opening,
          principalAfterPaise: opening,
          effectiveAt: zonedMidnight(2026, 4, 1),
        },
        {
          deltaPrincipalPaise: -400_000,
          principalAfterPaise: 0,
          effectiveAt: zonedMidnight(2026, 4, 12),
        },
        {
          deltaPrincipalPaise: 400_000,
          principalAfterPaise: 400_000,
          effectiveAt: zonedMidnight(2026, 4, 15),
        },
      ],
      asOf: new Date('2026-04-17T12:00:00+05:30'),
      timeZone: 'Asia/Kolkata',
      annualRateBps: 2400,
    });

    const expected =
      calculateSimpleDailyInterestPaise(400_000, 1, 2400) + // 11
      // 12-14 at 0
      calculateSimpleDailyInterestPaise(400_000, 3, 2400); // 15-17
    expect(result.accruedInterestPaise).toBe(expected);
  });
});
