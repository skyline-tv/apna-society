import { Types } from 'mongoose';
import { CacheKeys, hashFilters } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { BillModel } from '../../billing/models/bill.model';
import { normalizeReportDateRange, resolveWingCode, societyMatch } from '../utils/filters';
import { collectionPercentage } from '../utils/report-math';

export type CollectionReportQuery = {
  from?: Date;
  to?: Date;
  wingCode?: string;
  wingId?: string;
  flatId?: string;
  page?: number;
  limit?: number;
};

function activeBillMatch(
  societyId: string,
  from: Date,
  to: Date,
  wingCode: string | undefined,
  flatId: string | undefined,
): Record<string, unknown> {
  const match: Record<string, unknown> = {
    ...societyMatch(societyId),
    billingPeriodStart: { $gte: from, $lte: to },
    status: { $ne: 'CANCELLED' },
  };
  if (wingCode) match.wingCodeSnapshot = wingCode;
  if (flatId) match.flatId = new Types.ObjectId(flatId);
  return match;
}

async function loadCollectionReport(societyId: string, query: CollectionReportQuery = {}) {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);
  const match = activeBillMatch(societyId, from, to, wingCode, query.flatId);

  const [totals] = await BillModel.aggregate<{
    totalBillsGenerated: number;
    totalAmountCollectedPaise: number;
    totalAmountOutstandingPaise: number;
    totalBilledPaise: number;
    paidBills: number;
    partiallyPaidBills: number;
    unpaidBills: number;
    overdueBills: number;
  }>([
    { $match: match },
    {
      $group: {
        _id: null,
        totalBillsGenerated: { $sum: 1 },
        totalAmountCollectedPaise: { $sum: '$amountPaidPaise' },
        totalAmountOutstandingPaise: { $sum: '$outstandingPrincipalPaise' },
        totalBilledPaise: { $sum: '$totalAmountPaise' },
        paidBills: { $sum: { $cond: [{ $eq: ['$status', 'PAID'] }, 1, 0] } },
        partiallyPaidBills: {
          $sum: { $cond: [{ $eq: ['$status', 'PARTIALLY_PAID'] }, 1, 0] },
        },
        unpaidBills: {
          $sum: {
            $cond: [{ $in: ['$status', ['ISSUED', 'DRAFT', 'OVERDUE']] }, 1, 0],
          },
        },
        overdueBills: { $sum: { $cond: [{ $eq: ['$status', 'OVERDUE'] }, 1, 0] } },
      },
    },
  ]);

  const t = totals ?? {
    totalBillsGenerated: 0,
    totalAmountCollectedPaise: 0,
    totalAmountOutstandingPaise: 0,
    totalBilledPaise: 0,
    paidBills: 0,
    partiallyPaidBills: 0,
    unpaidBills: 0,
    overdueBills: 0,
  };

  const wingWise = await BillModel.aggregate<{
    _id: string;
    billedPaise: number;
    collectedPaise: number;
    outstandingPrincipalPaise: number;
    billCount: number;
  }>([
    { $match: match },
    {
      $group: {
        _id: '$wingCodeSnapshot',
        billedPaise: { $sum: '$totalAmountPaise' },
        collectedPaise: { $sum: '$amountPaidPaise' },
        outstandingPrincipalPaise: { $sum: '$outstandingPrincipalPaise' },
        billCount: { $sum: 1 },
      },
    },
    { $sort: { _id: 1 } },
  ]);

  const monthlyTrends = await BillModel.aggregate<{
    _id: { year: number; month: number };
    billedPaise: number;
    collectedPaise: number;
    outstandingPrincipalPaise: number;
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
        billCount: { $sum: 1 },
      },
    },
    { $sort: { '_id.year': 1, '_id.month': 1 } },
  ]);

  return {
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: wingCode ?? null,
    flatId: query.flatId ?? null,
    totalBillsGenerated: t.totalBillsGenerated,
    totalAmountCollectedPaise: t.totalAmountCollectedPaise,
    totalAmountOutstandingPaise: t.totalAmountOutstandingPaise,
    totalBilledPaise: t.totalBilledPaise,
    paidBills: t.paidBills,
    partiallyPaidBills: t.partiallyPaidBills,
    unpaidBills: t.unpaidBills,
    overdueBills: t.overdueBills,
    collectionPercentage: collectionPercentage(t.totalAmountCollectedPaise, t.totalBilledPaise),
    collectionPercentageFormula:
      'floor(collectedPaise * 10000 / billedPaise) / 100; 0 when billedPaise is 0',
    wingWise: wingWise.map((w) => ({
      wingCode: w._id,
      billedPaise: w.billedPaise,
      collectedPaise: w.collectedPaise,
      outstandingPrincipalPaise: w.outstandingPrincipalPaise,
      billCount: w.billCount,
      collectionPercentage: collectionPercentage(w.collectedPaise, w.billedPaise),
    })),
    monthlyTrends: monthlyTrends.map((m) => ({
      year: m._id.year,
      month: m._id.month,
      billedPaise: m.billedPaise,
      collectedPaise: m.collectedPaise,
      outstandingPrincipalPaise: m.outstandingPrincipalPaise,
      billCount: m.billCount,
      collectionPercentage: collectionPercentage(m.collectedPaise, m.billedPaise),
    })),
  };
}

export async function getCollectionReport(societyId: string, query: CollectionReportQuery = {}) {
  const { from, to } = normalizeReportDateRange(query);
  const filtersHash = hashFilters({
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: query.wingCode ?? null,
    wingId: query.wingId ?? null,
    flatId: query.flatId ?? null,
  });
  return cacheAside(
    CacheKeys.collectionReport(societyId, filtersHash),
    getEnv().CACHE_TTL_REPORTS_SECONDS,
    () => loadCollectionReport(societyId, query),
  );
}

/** Flat-wise outstanding balances (paginated). Uses bill snapshots, not live flat rates. */
export async function getOutstandingReport(societyId: string, query: CollectionReportQuery = {}) {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);
  const page = query.page ?? 1;
  const limit = query.limit ?? 50;
  const match = activeBillMatch(societyId, from, to, wingCode, query.flatId);
  // Outstanding rows only where principal remains.
  const outstandingMatch = {
    ...match,
    outstandingPrincipalPaise: { $gt: 0 },
  };

  const [countRow] = await BillModel.aggregate<{ total: number }>([
    { $match: outstandingMatch },
    {
      $group: {
        _id: { flatId: '$flatId', wingCode: '$wingCodeSnapshot', flatNumber: '$flatNumberSnapshot' },
      },
    },
    { $count: 'total' },
  ]);
  const total = countRow?.total ?? 0;

  const items = await BillModel.aggregate<{
    flatId: string;
    wingCode: string;
    flatNumber: string;
    ownerNameSnapshot: string;
    billedPaise: number;
    collectedPaise: number;
    outstandingPrincipalPaise: number;
    accruedInterestPaise: number;
    billCount: number;
  }>([
    { $match: outstandingMatch },
    {
      $group: {
        _id: {
          flatId: '$flatId',
          wingCode: '$wingCodeSnapshot',
          flatNumber: '$flatNumberSnapshot',
        },
        ownerNameSnapshot: { $last: '$ownerNameSnapshot' },
        billedPaise: { $sum: '$totalAmountPaise' },
        collectedPaise: { $sum: '$amountPaidPaise' },
        outstandingPrincipalPaise: { $sum: '$outstandingPrincipalPaise' },
        accruedInterestPaise: { $sum: '$interestAccruedPaise' },
        billCount: { $sum: 1 },
      },
    },
    { $sort: { outstandingPrincipalPaise: -1, '_id.wingCode': 1, '_id.flatNumber': 1 } },
    { $skip: (page - 1) * limit },
    { $limit: limit },
    {
      $project: {
        _id: 0,
        flatId: { $toString: '$_id.flatId' },
        wingCode: '$_id.wingCode',
        flatNumber: '$_id.flatNumber',
        ownerNameSnapshot: 1,
        billedPaise: 1,
        collectedPaise: 1,
        outstandingPrincipalPaise: 1,
        accruedInterestPaise: 1,
        billCount: 1,
      },
    },
  ]);

  const [sumRow] = await BillModel.aggregate<{
    outstandingPrincipalPaise: number;
    accruedInterestPaise: number;
  }>([
    { $match: outstandingMatch },
    {
      $group: {
        _id: null,
        outstandingPrincipalPaise: { $sum: '$outstandingPrincipalPaise' },
        accruedInterestPaise: { $sum: '$interestAccruedPaise' },
      },
    },
  ]);

  return {
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: wingCode ?? null,
    items,
    totals: {
      outstandingPrincipalPaise: sumRow?.outstandingPrincipalPaise ?? 0,
      accruedInterestPaise: sumRow?.accruedInterestPaise ?? 0,
      flatCount: total,
    },
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}
