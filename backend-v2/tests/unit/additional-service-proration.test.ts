import { describe, expect, it } from 'vitest';
import { chargeAdditionalServiceForPeriod } from '../../src/modules/billing/utils/additional-service-proration';
import { zonedMidnight, endOfZonedDay } from '../../src/modules/billing/utils/billing-calendar';

const april = {
  start: zonedMidnight(2026, 4, 1),
  end: endOfZonedDay(2026, 4, 30),
};

function service(overrides: Partial<Parameters<typeof chargeAdditionalServiceForPeriod>[0]> = {}) {
  return {
    id: 'svc1',
    name: 'Additional car parking',
    monthlyChargePaise: 50_000,
    quantity: 1,
    effectiveFrom: zonedMidnight(2026, 4, 1),
    isActive: true,
    ...overrides,
  };
}

describe('additional service calendar-day proration', () => {
  it('charges a full month when the service is active every day', () => {
    const line = chargeAdditionalServiceForPeriod(service(), april.start, april.end);
    expect(line?.amountPaise).toBe(50_000);
    expect(line?.applicableDays).toBe(30);
    expect(line?.prorationPolicy).toBe('calendar_day_per_civil_month');
  });

  it('prorates a mid-month start and never silently bills a full month', () => {
    const line = chargeAdditionalServiceForPeriod(
      service({ effectiveFrom: zonedMidnight(2026, 4, 16) }),
      april.start,
      april.end,
    );
    // 15 of 30 days → ₹250
    expect(line?.amountPaise).toBe(25_000);
    expect(line?.applicableDays).toBe(15);
  });

  it('prorates an inclusive end date', () => {
    const line = chargeAdditionalServiceForPeriod(
      service({ effectiveTo: endOfZonedDay(2026, 4, 15) }),
      april.start,
      april.end,
    );
    expect(line?.amountPaise).toBe(25_000);
    expect(line?.applicableDays).toBe(15);
  });

  it('excludes deactivated services', () => {
    const line = chargeAdditionalServiceForPeriod(
      service({ isActive: false }),
      april.start,
      april.end,
    );
    expect(line).toBeNull();
  });

  it('sums quantity across a 3-month period', () => {
    const line = chargeAdditionalServiceForPeriod(
      service({
        quantity: 2,
        monthlyChargePaise: 20_000,
        effectiveFrom: zonedMidnight(2026, 1, 1),
      }),
      zonedMidnight(2026, 1, 1),
      endOfZonedDay(2026, 3, 31),
    );
    expect(line?.amountPaise).toBe(20_000 * 2 * 3);
  });

  it('uses leap-year February day count', () => {
    const line = chargeAdditionalServiceForPeriod(
      service({
        effectiveFrom: zonedMidnight(2028, 2, 15),
        monthlyChargePaise: 29_000,
      }),
      zonedMidnight(2028, 2, 1),
      endOfZonedDay(2028, 2, 29),
    );
    // 15 of 29 days (15–29 inclusive)
    expect(line?.applicableDays).toBe(15);
    expect(line?.amountPaise).toBe(Math.floor((29_000 * 15) / 29));
  });
});
