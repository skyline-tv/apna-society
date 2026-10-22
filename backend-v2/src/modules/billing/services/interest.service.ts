import { getEnv } from '../../../config/env';
import { notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { SocietyModel } from '../../society/models/society.model';
import { BillModel, type BillDocument } from '../models/bill.model';
import { PrincipalLedgerModel } from '../models/principal-ledger.model';
import {
  inclusiveCivilDays,
  interestStartForDueDate,
  overdueDaysAsOf,
  startOfCivilDay,
} from '../utils/billing-calendar';
import { calculateSimpleDailyInterestPaise } from '../utils/money';
import { billComputedTotalPaise } from '../utils/bill-totals';

function annualRateBpsForSociety(society?: { config?: { annualInterestRateBps?: number } }) {
  return society?.config?.annualInterestRateBps ?? getEnv().BILLING_ANNUAL_INTEREST_BPS;
}

export interface InterestSegment {
  from: string;
  to: string;
  days: number;
  principalPaise: number;
  interestPaise: number;
}

export interface InterestBreakdown {
  billId: string;
  principalOutstandingPaise: number;
  overdueDays: number;
  annualInterestRateBps: number;
  annualInterestRatePercent: number;
  accruedInterestPaise: number;
  asOf: string;
  dueDate: string;
  dayCountConvention: 'actual/365';
  rounding: 'floor_via_bigint_division';
  /**
   * Principal change for interest takes effect at civil midnight of the settlement date
   * (society timezone). Past segments are never recomputed with a later principal.
   */
  principalEffectiveConvention: 'civil_midnight_of_settlement_date';
  segments: InterestSegment[];
}

export interface PrincipalEventLike {
  deltaPrincipalPaise: number;
  principalAfterPaise: number;
  effectiveAt: Date;
}

/**
 * Segment interest from the immutable principal timeline.
 *
 * Conventions:
 * - Day-count: actual/365 simple (no compounding).
 * - Accrual starts on the civil day after the due date (11th when due is the 10th).
 * - Interest for civil day D uses the principal outstanding at the start of D.
 * - A payment/refund effective on civil day T changes principal from the start of T onward.
 * - Rounding: floor via BigInt per segment (never on floating point).
 * - Historical as-of ignores ledger events after the as-of civil day.
 */
export function computeInterestFromPrincipalTimeline(
  input: {
    dueDate: Date;
    openingPrincipalPaise: number;
    events: PrincipalEventLike[];
    asOf: Date;
    timeZone: string;
    annualRateBps?: number;
  },
): Omit<InterestBreakdown, 'billId'> & { billId?: string } {
  const annualRateBps = input.annualRateBps ?? getEnv().BILLING_ANNUAL_INTEREST_BPS;
  const asOfDay = startOfCivilDay(input.asOf, input.timeZone);
  const interestStart = interestStartForDueDate(input.dueDate, input.timeZone);
  const overdueDays = overdueDaysAsOf(input.dueDate, input.asOf, input.timeZone);

  const events = [...input.events]
    .map((e) => ({
      ...e,
      effectiveAt: startOfCivilDay(e.effectiveAt, input.timeZone),
    }))
    .sort((a, b) => {
      const t = a.effectiveAt.getTime() - b.effectiveAt.getTime();
      if (t !== 0) return t;
      return a.deltaPrincipalPaise - b.deltaPrincipalPaise;
    });

  // Principal at/before interest start (events on or before interestStart apply).
  let principal = input.openingPrincipalPaise;
  for (const event of events) {
    if (event.effectiveAt.getTime() <= interestStart.getTime()) {
      principal = event.principalAfterPaise;
    }
  }

  if (asOfDay.getTime() < interestStart.getTime() || overdueDays === 0) {
    let principalAtAsOf = input.openingPrincipalPaise;
    for (const event of events) {
      if (event.effectiveAt.getTime() <= asOfDay.getTime()) {
        principalAtAsOf = event.principalAfterPaise;
      }
    }
    return {
      billId: '',
      principalOutstandingPaise: Math.max(0, principalAtAsOf),
      overdueDays: 0,
      annualInterestRateBps: annualRateBps,
      annualInterestRatePercent: annualRateBps / 100,
      accruedInterestPaise: 0,
      asOf: input.asOf.toISOString(),
      dueDate: input.dueDate.toISOString(),
      dayCountConvention: 'actual/365',
      rounding: 'floor_via_bigint_division',
      principalEffectiveConvention: 'civil_midnight_of_settlement_date',
      segments: [],
    };
  }

  const changePoints = events.filter(
    (e) =>
      e.effectiveAt.getTime() > interestStart.getTime() &&
      e.effectiveAt.getTime() <= asOfDay.getTime(),
  );

  const segments: InterestSegment[] = [];
  let cursor = interestStart;
  let accrued = 0;

  for (const event of changePoints) {
    const days = inclusiveCivilDays(cursor, new Date(event.effectiveAt.getTime() - 86_400_000));
    if (days > 0 && principal > 0) {
      const interestPaise = calculateSimpleDailyInterestPaise(principal, days, annualRateBps);
      accrued += interestPaise;
      segments.push({
        from: cursor.toISOString(),
        to: new Date(event.effectiveAt.getTime() - 86_400_000).toISOString(),
        days,
        principalPaise: principal,
        interestPaise,
      });
    } else if (days > 0 && principal <= 0) {
      segments.push({
        from: cursor.toISOString(),
        to: new Date(event.effectiveAt.getTime() - 86_400_000).toISOString(),
        days,
        principalPaise: 0,
        interestPaise: 0,
      });
    }
    principal = event.principalAfterPaise;
    cursor = event.effectiveAt;
  }

  const tailDays = inclusiveCivilDays(cursor, asOfDay);
  if (tailDays > 0) {
    const interestPaise =
      principal > 0
        ? calculateSimpleDailyInterestPaise(principal, tailDays, annualRateBps)
        : 0;
    accrued += interestPaise;
    segments.push({
      from: cursor.toISOString(),
      to: asOfDay.toISOString(),
      days: tailDays,
      principalPaise: Math.max(0, principal),
      interestPaise,
    });
  }

  let principalAtAsOf = input.openingPrincipalPaise;
  for (const event of events) {
    if (event.effectiveAt.getTime() <= asOfDay.getTime()) {
      principalAtAsOf = event.principalAfterPaise;
    }
  }

  return {
    billId: '',
    principalOutstandingPaise: Math.max(0, principalAtAsOf),
    overdueDays,
    annualInterestRateBps: annualRateBps,
    annualInterestRatePercent: annualRateBps / 100,
    accruedInterestPaise: accrued,
    asOf: input.asOf.toISOString(),
    dueDate: input.dueDate.toISOString(),
    dayCountConvention: 'actual/365',
    rounding: 'floor_via_bigint_division',
    principalEffectiveConvention: 'civil_midnight_of_settlement_date',
    segments,
  };
}

export async function loadPrincipalEvents(billId: string) {
  return PrincipalLedgerModel.find({ billId: parseObjectId(billId, 'billId') })
    .sort({ effectiveAt: 1, createdAt: 1 })
    .lean();
}

export async function computeInterestForBill(
  bill: Pick<
    BillDocument,
    | '_id'
    | 'outstandingPrincipalPaise'
    | 'dueDate'
    | 'status'
    | 'amountPaidPaise'
    | 'totalAmountPaise'
    | 'baseAmountPaise'
    | 'additionalServicesTotalPaise'
    | 'adjustmentsPaise'
  >,
  asOf: Date,
  timeZone: string,
  annualRateBps = getEnv().BILLING_ANNUAL_INTEREST_BPS,
): Promise<InterestBreakdown> {
  if (bill.status === 'CANCELLED') {
    return {
      billId: String(bill._id),
      principalOutstandingPaise: Math.max(0, bill.outstandingPrincipalPaise),
      overdueDays: 0,
      annualInterestRateBps: annualRateBps,
      annualInterestRatePercent: annualRateBps / 100,
      accruedInterestPaise: 0,
      asOf: asOf.toISOString(),
      dueDate: bill.dueDate.toISOString(),
      dayCountConvention: 'actual/365',
      rounding: 'floor_via_bigint_division',
      principalEffectiveConvention: 'civil_midnight_of_settlement_date',
      segments: [],
    };
  }

  const events = await loadPrincipalEvents(String(bill._id));
  const opening =
    events.find((e) => e.eventType === 'OPENING')?.principalAfterPaise ??
    billComputedTotalPaise(bill);

  const breakdown = computeInterestFromPrincipalTimeline({
    dueDate: bill.dueDate,
    openingPrincipalPaise: opening,
    events,
    asOf,
    timeZone,
    annualRateBps,
  });
  breakdown.billId = String(bill._id);
  return breakdown as InterestBreakdown;
}

/** Sync helper for callers that already loaded ledger events (e.g. inside a transaction). */
export function computeInterestForBillWithEvents(
  bill: Pick<
    BillDocument,
    | '_id'
    | 'dueDate'
    | 'status'
    | 'outstandingPrincipalPaise'
    | 'baseAmountPaise'
    | 'additionalServicesTotalPaise'
    | 'adjustmentsPaise'
  >,
  events: PrincipalEventLike[],
  asOf: Date,
  timeZone: string,
  openingPrincipalPaise?: number,
  annualRateBps = getEnv().BILLING_ANNUAL_INTEREST_BPS,
): InterestBreakdown {
  if (bill.status === 'CANCELLED') {
    return {
      billId: String(bill._id),
      principalOutstandingPaise: Math.max(0, bill.outstandingPrincipalPaise),
      overdueDays: 0,
      annualInterestRateBps: annualRateBps,
      annualInterestRatePercent: annualRateBps / 100,
      accruedInterestPaise: 0,
      asOf: asOf.toISOString(),
      dueDate: bill.dueDate.toISOString(),
      dayCountConvention: 'actual/365',
      rounding: 'floor_via_bigint_division',
      principalEffectiveConvention: 'civil_midnight_of_settlement_date',
      segments: [],
    };
  }

  const opening = openingPrincipalPaise ?? billComputedTotalPaise(bill);
  const breakdown = computeInterestFromPrincipalTimeline({
    dueDate: bill.dueDate,
    openingPrincipalPaise: opening,
    events,
    asOf,
    timeZone,
    annualRateBps,
  });
  breakdown.billId = String(bill._id);
  return breakdown as InterestBreakdown;
}

export async function getBillInterest(
  societyId: string,
  billId: string,
  asOf = new Date(),
): Promise<InterestBreakdown> {
  const society = await SocietyModel.findById(parseObjectId(societyId, 'societyId')).lean();
  if (!society) {
    throw notFound('Society not found');
  }
  const timeZone = society.config?.timezone ?? 'Asia/Kolkata';
  const annualRateBps = annualRateBpsForSociety(society);
  const bill = await BillModel.findOne({
    _id: parseObjectId(billId, 'billId'),
    societyId,
  });
  if (!bill) {
    throw notFound('Bill not found');
  }

  const breakdown = await computeInterestForBill(bill, asOf, timeZone, annualRateBps);

  // Refresh stored summary idempotently from the ledger-derived total.
  bill.interestAccruedPaise = breakdown.accruedInterestPaise;
  bill.interestCalculatedAsOf = asOf;
  if (
    bill.status !== 'CANCELLED' &&
    bill.status !== 'PAID' &&
    breakdown.overdueDays > 0 &&
    bill.outstandingPrincipalPaise > 0
  ) {
    bill.status = 'OVERDUE';
  }
  await bill.save();

  return breakdown;
}

export async function refreshSocietyInterestSummaries(
  societyId: string,
  asOf = new Date(),
): Promise<{ updated: number }> {
  const society = await SocietyModel.findById(parseObjectId(societyId, 'societyId')).lean();
  if (!society) {
    throw notFound('Society not found');
  }
  const timeZone = society.config?.timezone ?? 'Asia/Kolkata';
  const annualRateBps = annualRateBpsForSociety(society);
  const bills = await BillModel.find({
    societyId,
    status: { $in: ['ISSUED', 'PARTIALLY_PAID', 'OVERDUE', 'PAID'] },
  });

  let updated = 0;
  for (const bill of bills) {
    if (bill.status === 'CANCELLED') continue;
    const breakdown = await computeInterestForBill(bill, asOf, timeZone, annualRateBps);
    bill.interestAccruedPaise = breakdown.accruedInterestPaise;
    bill.interestCalculatedAsOf = asOf;
    if (
      bill.status !== 'PAID' &&
      breakdown.overdueDays > 0 &&
      bill.outstandingPrincipalPaise > 0
    ) {
      bill.status = 'OVERDUE';
    }
    await bill.save();
    updated += 1;
  }
  return { updated };
}
