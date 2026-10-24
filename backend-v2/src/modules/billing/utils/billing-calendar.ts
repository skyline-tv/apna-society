const IST_OFFSET = '+05:30';

export interface CivilDate {
  year: number;
  month: number; // 1-12
  day: number;
}

export function formatCivilDate(civil: CivilDate): string {
  const mm = civil.month.toString().padStart(2, '0');
  const dd = civil.day.toString().padStart(2, '0');
  return `${civil.year}-${mm}-${dd}`;
}

/** YYYY-MM-DD of `date` in the society timezone. */
export function civilDateKey(date: Date, timeZone = 'Asia/Kolkata'): string {
  return formatCivilDate(civilDateInTimeZone(date, timeZone));
}

/** Read calendar Y-M-D in a fixed-offset timezone (Asia/Kolkata has no DST). */
export function civilDateInTimeZone(date: Date, timeZone = 'Asia/Kolkata'): CivilDate {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const parts = fmt.formatToParts(date);
  const year = Number(parts.find((p) => p.type === 'year')?.value);
  const month = Number(parts.find((p) => p.type === 'month')?.value);
  const day = Number(parts.find((p) => p.type === 'day')?.value);
  return { year, month, day };
}

/** Midnight at the start of a civil day in Asia/Kolkata (or +05:30 zones). */
export function zonedMidnight(year: number, month: number, day: number): Date {
  const mm = month.toString().padStart(2, '0');
  const dd = day.toString().padStart(2, '0');
  return new Date(`${year}-${mm}-${dd}T00:00:00.000${IST_OFFSET}`);
}

export function endOfZonedDay(year: number, month: number, day: number): Date {
  const mm = month.toString().padStart(2, '0');
  const dd = day.toString().padStart(2, '0');
  return new Date(`${year}-${mm}-${dd}T23:59:59.999${IST_OFFSET}`);
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

export function addCalendarMonths(start: CivilDate, months: number): CivilDate {
  const idx = start.year * 12 + (start.month - 1) + months;
  const year = Math.floor(idx / 12);
  const month = (idx % 12) + 1;
  return { year, month, day: 1 };
}

export function addCalendarDays(start: CivilDate, days: number): CivilDate {
  const utc = new Date(Date.UTC(start.year, start.month - 1, start.day + days));
  return { year: utc.getUTCFullYear(), month: utc.getUTCMonth() + 1, day: utc.getUTCDate() };
}

/**
 * Billing period for N consecutive calendar months starting on the 1st.
 * Example: 2026-04-01 + 3 months → start 2026-04-01, end 2026-06-30 23:59:59.999 IST
 */
export function billingPeriodBounds(
  billingPeriodStart: Date,
  numberOfMonths: 1 | 3,
  timeZone = 'Asia/Kolkata',
): { periodStart: Date; periodEnd: Date; startCivil: CivilDate } {
  const startCivil = civilDateInTimeZone(billingPeriodStart, timeZone);
  if (startCivil.day !== 1) {
    throw new Error('billingPeriodStart must be the 1st of a calendar month');
  }
  const periodStart = zonedMidnight(startCivil.year, startCivil.month, 1);
  const endMonth = addCalendarMonths(startCivil, numberOfMonths - 1);
  const lastDay = daysInMonth(endMonth.year, endMonth.month);
  const periodEnd = endOfZonedDay(endMonth.year, endMonth.month, lastDay);
  return { periodStart, periodEnd, startCivil };
}

/** Default due date: the 10th of the billing period's first month (end of that day IST). */
export function dueDateForBillingPeriod(periodStart: Date, timeZone = 'Asia/Kolkata'): Date {
  const civil = civilDateInTimeZone(periodStart, timeZone);
  return endOfZonedDay(civil.year, civil.month, 10);
}

/**
 * Due date stored on every bill in a generation batch.
 * Defaults to the 10th when the admin does not supply one. A supplied date is
 * normalized to end-of-day in the society timezone and must fall on a civil
 * day within the billing period.
 */
export function resolveBillDueDate(
  periodStart: Date,
  periodEnd: Date,
  requested: Date | undefined,
  timeZone = 'Asia/Kolkata',
): Date {
  if (!requested) {
    return dueDateForBillingPeriod(periodStart, timeZone);
  }
  const civil = civilDateInTimeZone(requested, timeZone);
  const dueStart = zonedMidnight(civil.year, civil.month, civil.day);
  const startDay = startOfCivilDay(periodStart, timeZone);
  const endDay = startOfCivilDay(periodEnd, timeZone);
  if (dueStart.getTime() < startDay.getTime() || dueStart.getTime() > endDay.getTime()) {
    throw new Error('dueDate must fall within the billing period');
  }
  return endOfZonedDay(civil.year, civil.month, civil.day);
}

/**
 * Overdue days as of `asOf`: 0 on/before the due date;
 * 1 on the following civil day, etc. Uses the society timezone.
 */
export function overdueDaysAsOf(
  dueDate: Date,
  asOf: Date,
  timeZone = 'Asia/Kolkata',
): number {
  const asOfCivil = civilDateInTimeZone(asOf, timeZone);
  const interestStart = interestStartForDueDate(dueDate, timeZone);
  const asOfStart = zonedMidnight(asOfCivil.year, asOfCivil.month, asOfCivil.day);
  if (asOfStart.getTime() < interestStart.getTime()) {
    return 0;
  }
  const ms = asOfStart.getTime() - interestStart.getTime();
  return Math.floor(ms / 86_400_000) + 1;
}

export function periodsOverlap(
  aStart: Date,
  aEnd: Date,
  bStart: Date,
  bEnd: Date,
): boolean {
  return aStart.getTime() <= bEnd.getTime() && bStart.getTime() <= aEnd.getTime();
}

/** Start of the civil day containing `date` in the society timezone. */
export function startOfCivilDay(date: Date, timeZone = 'Asia/Kolkata'): Date {
  const civil = civilDateInTimeZone(date, timeZone);
  return zonedMidnight(civil.year, civil.month, civil.day);
}

/**
 * Inclusive civil-day count from `from` midnight through `to` midnight.
 * Returns 0 when `to` is before `from`.
 */
export function inclusiveCivilDays(from: Date, to: Date): number {
  if (to.getTime() < from.getTime()) return 0;
  return Math.floor((to.getTime() - from.getTime()) / 86_400_000) + 1;
}

/** Interest accrual start: civil midnight of the day after the due date. */
export function interestStartForDueDate(dueDate: Date, timeZone = 'Asia/Kolkata'): Date {
  const next = addCalendarDays(civilDateInTimeZone(dueDate, timeZone), 1);
  return zonedMidnight(next.year, next.month, next.day);
}
