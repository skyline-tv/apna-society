import {
  addCalendarMonths,
  civilDateInTimeZone,
  daysInMonth,
  endOfZonedDay,
  zonedMidnight,
  type CivilDate,
} from './billing-calendar';

export interface AdditionalServiceChargeInput {
  id: string;
  name: string;
  description?: string;
  monthlyChargePaise: number;
  quantity: number;
  effectiveFrom: Date;
  effectiveTo?: Date;
  isActive: boolean;
}

export interface AdditionalServiceLineSnapshot {
  type: 'ADDITIONAL_SERVICE';
  serviceId: string;
  name: string;
  description?: string;
  quantity: number;
  unitAmountPaise: number;
  amountPaise: number;
  applicableDays: number;
  billedDays: number;
  prorationPolicy: 'calendar_day_per_civil_month';
}

/**
 * Calendar-day proration per civil month (society timezone, default IST).
 *
 * A service applies on civil day D when:
 * - it is active
 * - D is on/after effectiveFrom
 * - D is on/before effectiveTo (if set; inclusive)
 *
 * Month charge = floor(monthlyChargePaise × quantity × applicableDays / daysInMonth)
 * Period charge = sum of month charges in the billing period.
 *
 * A service active for every day of a month is charged the full monthly amount.
 * A mid-month start/end is charged only for the applicable days — never a silent full month.
 */
export function chargeAdditionalServiceForPeriod(
  service: AdditionalServiceChargeInput,
  periodStart: Date,
  periodEnd: Date,
  timeZone = 'Asia/Kolkata',
): AdditionalServiceLineSnapshot | null {
  if (!service.isActive) return null;
  if (service.monthlyChargePaise <= 0 || service.quantity <= 0) return null;

  const startCivil = civilDateInTimeZone(periodStart, timeZone);
  const endCivil = civilDateInTimeZone(periodEnd, timeZone);
  const fromCivil = civilDateInTimeZone(service.effectiveFrom, timeZone);
  const toCivil = service.effectiveTo
    ? civilDateInTimeZone(service.effectiveTo, timeZone)
    : undefined;

  let cursor: CivilDate = { year: startCivil.year, month: startCivil.month, day: 1 };
  const lastMonth: CivilDate = { year: endCivil.year, month: endCivil.month, day: 1 };

  let amountPaise = 0;
  let applicableDays = 0;
  let billedDays = 0;

  while (
    cursor.year < lastMonth.year ||
    (cursor.year === lastMonth.year && cursor.month <= lastMonth.month)
  ) {
    const dim = daysInMonth(cursor.year, cursor.month);
    const monthStart = zonedMidnight(cursor.year, cursor.month, 1);
    const monthEnd = endOfZonedDay(cursor.year, cursor.month, dim);
    const windowStart = monthStart.getTime() < periodStart.getTime() ? periodStart : monthStart;
    const windowEnd = monthEnd.getTime() > periodEnd.getTime() ? periodEnd : monthEnd;

    const windowStartCivil = civilDateInTimeZone(windowStart, timeZone);
    const windowEndCivil = civilDateInTimeZone(windowEnd, timeZone);
    const daysInWindow = windowEndCivil.day - windowStartCivil.day + 1;
    billedDays += Math.max(0, daysInWindow);

    let days = 0;
    for (let day = windowStartCivil.day; day <= windowEndCivil.day; day += 1) {
      if (civilDayApplies(cursor.year, cursor.month, day, fromCivil, toCivil)) {
        days += 1;
      }
    }
    applicableDays += days;
    if (days > 0) {
      amountPaise += prorateMonth(service.monthlyChargePaise, service.quantity, days, dim);
    }

    cursor = addCalendarMonths(cursor, 1);
  }

  if (amountPaise <= 0 || applicableDays <= 0) return null;

  return {
    type: 'ADDITIONAL_SERVICE',
    serviceId: service.id,
    name: service.name,
    description: service.description,
    quantity: service.quantity,
    unitAmountPaise: service.monthlyChargePaise,
    amountPaise,
    applicableDays,
    billedDays,
    prorationPolicy: 'calendar_day_per_civil_month',
  };
}

function civilDayApplies(
  year: number,
  month: number,
  day: number,
  from: CivilDate,
  to?: CivilDate,
): boolean {
  if (compareCivil({ year, month, day }, from) < 0) return false;
  if (to && compareCivil({ year, month, day }, to) > 0) return false;
  return true;
}

function compareCivil(a: CivilDate, b: CivilDate): number {
  if (a.year !== b.year) return a.year - b.year;
  if (a.month !== b.month) return a.month - b.month;
  return a.day - b.day;
}

function prorateMonth(
  monthlyChargePaise: number,
  quantity: number,
  applicableDays: number,
  daysInThisMonth: number,
): number {
  if (applicableDays <= 0 || daysInThisMonth <= 0) return 0;
  if (applicableDays >= daysInThisMonth) {
    return monthlyChargePaise * quantity;
  }
  const numerator =
    BigInt(monthlyChargePaise) * BigInt(quantity) * BigInt(applicableDays);
  return Number(numerator / BigInt(daysInThisMonth));
}
