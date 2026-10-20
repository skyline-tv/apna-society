import { Types } from 'mongoose';
import { CacheKeys, hashFilters } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { BillModel } from '../../billing/models/bill.model';
import { PaymentModel } from '../../billing/models/payment.model';
import { normalizeReportDateRange, resolveWingCode, societyMatch } from '../utils/filters';
import { collectionPercentage } from '../utils/report-math';

export type FinancialReportQuery = {
  from?: Date;
  to?: Date;
  wingCode?: string;
  wingId?: string;
  flatId?: string;
  paymentMethod?: string;
  paymentStatus?: string;
};

function billMatch(
  societyId: string,
  from: Date,
  to: Date,
  wingCode: string | undefined,
  flatId: string | undefined,
): Record<string, unknown> {
  // Accounting period filter (not generation wall-clock) so historical periods stay queryable.
  const match: Record<string, unknown> = {
    ...societyMatch(societyId),
    billingPeriodStart: { $gte: from, $lte: to },
    status: { $ne: 'CANCELLED' },
  };
  if (wingCode) match.wingCodeSnapshot = wingCode;
  if (flatId) match.flatId = new Types.ObjectId(flatId);
  return match;
}

function paymentMatch(
  societyId: string,
  from: Date,
  to: Date,
  flatId: string | undefined,
  paymentMethod: string | undefined,
  paymentStatus: string | undefined,
  billIds?: Types.ObjectId[],
): Record<string, unknown> {
  const match: Record<string, unknown> = {
    ...societyMatch(societyId),
    $or: [
      { paidAt: { $gte: from, $lte: to } },
      { paidAt: null, createdAt: { $gte: from, $lte: to } },
    ],
  };
  if (flatId) match.flatId = new Types.ObjectId(flatId);
  if (paymentMethod) match.paymentMethod = paymentMethod;
  if (paymentStatus) match.status = paymentStatus;
  if (billIds) match.billId = { $in: billIds };
  return match;
}

async function loadFinancialReport(societyId: string, query: FinancialReportQuery = {}) {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);

  const match = billMatch(societyId, from, to, wingCode, query.flatId);

  const [billAgg] = await BillModel.aggregate<{
    totalBilledPaise: number;
    totalCollectedPaise: number;
    totalOutstandingPrincipalPaise: number;
    totalAccruedInterestPaise: number;
    billCount: number;
  }>([
    { $match: match },
    {
      $group: {
        _id: null,
        totalBilledPaise: { $sum: '$totalAmountPaise' },
        totalCollectedPaise: { $sum: '$amountPaidPaise' },
        totalOutstandingPrincipalPaise: { $sum: '$outstandingPrincipalPaise' },
        totalAccruedInterestPaise: { $sum: '$interestAccruedPaise' },
        billCount: { $sum: 1 },
      },
    },
  ]);

  const totals = billAgg ?? {
    totalBilledPaise: 0,
    totalCollectedPaise: 0,
    totalOutstandingPrincipalPaise: 0,
    totalAccruedInterestPaise: 0,
    billCount: 0,
  };

  // When wing filter is set, scope payment aggregates to bills in that wing.
  let billIds: Types.ObjectId[] | undefined;
  if (wingCode) {
    const ids = await BillModel.find(match).select('_id').lean();
    billIds = ids.map((b) => b._id as Types.ObjectId);
  }

  const pMatch = paymentMatch(
    societyId,
    from,
    to,
    query.flatId,
    query.paymentMethod,
    query.paymentStatus,
    billIds,
  );

  const paymentAgg = await PaymentModel.aggregate<{
    _id: { status: string; method: string };
    count: number;
    amountPaise: number;
  }>([
    { $match: pMatch },
    {
      $group: {
        _id: { status: '$status', method: '$paymentMethod' },
        count: { $sum: 1 },
        amountPaise: { $sum: '$amountPaise' },
      },
    },
  ]);

  let totalRefundsPaise = 0;
  let totalOfflineCollectionsPaise = 0;
  let totalOnlineCollectionsPaise = 0;
  let paymentSuccessCount = 0;
  let paymentFailureCount = 0;
  let paymentRefundedCount = 0;
  let paymentPendingCount = 0;

  for (const row of paymentAgg) {
    const { status, method } = row._id;
    if (status === 'SUCCESS') {
      paymentSuccessCount += row.count;
      if (method === 'OFFLINE') totalOfflineCollectionsPaise += row.amountPaise;
      else totalOnlineCollectionsPaise += row.amountPaise;
    } else if (status === 'FAILED') {
      paymentFailureCount += row.count;
    } else if (status === 'REFUNDED') {
      paymentRefundedCount += row.count;
      totalRefundsPaise += row.amountPaise;
    } else if (status === 'PENDING') {
      paymentPendingCount += row.count;
    }
  }

  const monthly = await BillModel.aggregate<{
    year: number;
    month: number;
    billedPaise: number;
    collectedPaise: number;
    outstandingPrincipalPaise: number;
    accruedInterestPaise: number;
    billCount: number;
  }>([
    { $match: match },
    {
      $group: {
        _id: {
          year: { $year: '$billingPeriodStart' },
          month: { $month: '$billingPeriodStart' },
        },
        billedPaise: { $sum: '$totalAmountPaise' },
        collectedPaise: { $sum: '$amountPaidPaise' },
        outstandingPrincipalPaise: { $sum: '$outstandingPrincipalPaise' },
        accruedInterestPaise: { $sum: '$interestAccruedPaise' },
        billCount: { $sum: 1 },
      },
    },
    { $sort: { '_id.year': 1, '_id.month': 1 } },
    {
      $project: {
        _id: 0,
        year: '$_id.year',
        month: '$_id.month',
        billedPaise: 1,
        collectedPaise: 1,
        outstandingPrincipalPaise: 1,
        accruedInterestPaise: 1,
        billCount: 1,
      },
    },
  ]);

  const yearly = await BillModel.aggregate<{
    year: number;
    billedPaise: number;
    collectedPaise: number;
    outstandingPrincipalPaise: number;
    accruedInterestPaise: number;
    billCount: number;
  }>([
    { $match: match },
    {
      $group: {
        _id: { $year: '$billingPeriodStart' },
        billedPaise: { $sum: '$totalAmountPaise' },
        collectedPaise: { $sum: '$amountPaidPaise' },
        outstandingPrincipalPaise: { $sum: '$outstandingPrincipalPaise' },
        accruedInterestPaise: { $sum: '$interestAccruedPaise' },
        billCount: { $sum: 1 },
      },
    },
    { $sort: { _id: 1 } },
    {
      $project: {
        _id: 0,
        year: '$_id',
        billedPaise: 1,
        collectedPaise: 1,
        outstandingPrincipalPaise: 1,
        accruedInterestPaise: 1,
        billCount: 1,
      },
    },
  ]);

  return {
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: wingCode ?? null,
    flatId: query.flatId ?? null,
    totalBilledPaise: totals.totalBilledPaise,
    totalCollectedPaise: totals.totalCollectedPaise,
    totalOutstandingPrincipalPaise: totals.totalOutstandingPrincipalPaise,
    totalAccruedInterestPaise: totals.totalAccruedInterestPaise,
    totalRefundsPaise,
    totalOfflineCollectionsPaise,
    totalOnlineCollectionsPaise,
    paymentSuccessCount,
    paymentFailureCount,
    paymentRefundedCount,
    paymentPendingCount,
    billCount: totals.billCount,
    collectionPercentage: collectionPercentage(
      totals.totalCollectedPaise,
      totals.totalBilledPaise,
    ),
    monthly,
    yearly,
    note: 'Amounts are integer paise from Bill/Payment snapshots. CANCELLED bills excluded from bill totals.',
  };
}

export async function getFinancialReport(societyId: string, query: FinancialReportQuery = {}) {
  const { from, to } = normalizeReportDateRange(query);
  const filtersHash = hashFilters({
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: query.wingCode ?? null,
    wingId: query.wingId ?? null,
    flatId: query.flatId ?? null,
    paymentMethod: query.paymentMethod ?? null,
    paymentStatus: query.paymentStatus ?? null,
  });
  return cacheAside(
    CacheKeys.financialReport(societyId, filtersHash),
    getEnv().CACHE_TTL_REPORTS_SECONDS,
    () => loadFinancialReport(societyId, query),
  );
}
