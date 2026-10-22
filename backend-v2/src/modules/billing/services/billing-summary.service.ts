import { getEnv } from '../../../config/env';
import { CacheKeys, hashFilters } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { parseObjectId } from '../../../utils/object-id';
import { FlatModel } from '../../society/models/flat.model';
import { BillModel } from '../models/bill.model';
import { PaymentModel } from '../models/payment.model';

type BillingSummaryQuery = {
  billingPeriodStart?: Date;
  wingCode?: string;
  flatId?: string;
  status?: string;
  ownerUserId?: string;
  paymentStatus?: string;
  occupancyStatus?: string;
  floor?: number;
  ownerAssigned?: boolean;
};

async function loadBillingSummary(societyId: string, query: BillingSummaryQuery) {
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const billFilter: Record<string, unknown> = { societyId: societyObjectId };
  if (query.billingPeriodStart) billFilter.billingPeriodStart = query.billingPeriodStart;
  if (query.wingCode) billFilter.wingCodeSnapshot = query.wingCode.toUpperCase();
  if (query.flatId) billFilter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.status) billFilter.status = query.status;
  if (query.ownerUserId) {
    billFilter.ownerUserId = parseObjectId(query.ownerUserId, 'ownerUserId');
  }
  if (query.occupancyStatus) billFilter.occupancyStatusSnapshot = query.occupancyStatus;
  if (query.floor !== undefined) billFilter.floorSnapshot = query.floor;
  if (query.ownerAssigned === true) {
    billFilter.ownerUserId = { $exists: true, $ne: null };
  } else if (query.ownerAssigned === false) {
    billFilter.$or = [{ ownerUserId: { $exists: false } }, { ownerUserId: null }];
  }

  const [billAgg, wingAgg, vacantOrUnassigned, configuredFlats] = await Promise.all([
    BillModel.aggregate<{
      totalBilledPaise: number;
      totalMaintenanceBilledPaise: number;
      totalAdditionalServicesBilledPaise: number;
      totalCollectedPaise: number;
      totalOutstandingPrincipalPaise: number;
      totalAccruedInterestPaise: number;
      paidBills: number;
      partiallyPaidBills: number;
      overdueBills: number;
      issuedBills: number;
      cancelledBills: number;
      vacantFlatBills: number;
      unassignedFlatBills: number;
      billCount: number;
    }>([
      { $match: billFilter },
      {
        $group: {
          _id: null,
          totalBilledPaise: {
            $sum: { $cond: [{ $ne: ['$status', 'CANCELLED'] }, '$totalAmountPaise', 0] },
          },
          totalMaintenanceBilledPaise: {
            $sum: { $cond: [{ $ne: ['$status', 'CANCELLED'] }, '$baseAmountPaise', 0] },
          },
          totalAdditionalServicesBilledPaise: {
            $sum: {
              $cond: [
                { $ne: ['$status', 'CANCELLED'] },
                { $ifNull: ['$additionalServicesTotalPaise', 0] },
                0,
              ],
            },
          },
          totalCollectedPaise: {
            $sum: { $cond: [{ $ne: ['$status', 'CANCELLED'] }, '$amountPaidPaise', 0] },
          },
          totalOutstandingPrincipalPaise: {
            $sum: {
              $cond: [{ $ne: ['$status', 'CANCELLED'] }, '$outstandingPrincipalPaise', 0],
            },
          },
          totalAccruedInterestPaise: {
            $sum: { $cond: [{ $ne: ['$status', 'CANCELLED'] }, '$interestAccruedPaise', 0] },
          },
          paidBills: {
            $sum: { $cond: [{ $eq: ['$status', 'PAID'] }, 1, 0] },
          },
          partiallyPaidBills: {
            $sum: { $cond: [{ $eq: ['$status', 'PARTIALLY_PAID'] }, 1, 0] },
          },
          overdueBills: {
            $sum: { $cond: [{ $eq: ['$status', 'OVERDUE'] }, 1, 0] },
          },
          issuedBills: {
            $sum: { $cond: [{ $eq: ['$status', 'ISSUED'] }, 1, 0] },
          },
          cancelledBills: {
            $sum: { $cond: [{ $eq: ['$status', 'CANCELLED'] }, 1, 0] },
          },
          vacantFlatBills: {
            $sum: {
              $cond: [
                {
                  $and: [
                    { $ne: ['$status', 'CANCELLED'] },
                    { $eq: ['$occupancyStatusSnapshot', 'VACANT'] },
                  ],
                },
                1,
                0,
              ],
            },
          },
          unassignedFlatBills: {
            $sum: {
              $cond: [
                {
                  $and: [
                    { $ne: ['$status', 'CANCELLED'] },
                    {
                      $or: [
                        { $eq: [{ $ifNull: ['$ownerUserId', null] }, null] },
                      ],
                    },
                  ],
                },
                1,
                0,
              ],
            },
          },
          billCount: {
            $sum: { $cond: [{ $ne: ['$status', 'CANCELLED'] }, 1, 0] },
          },
        },
      },
    ]),
    BillModel.aggregate<{
      wingCode: string;
      billedPaise: number;
      collectedPaise: number;
      outstandingPrincipalPaise: number;
      billCount: number;
    }>([
      { $match: { ...billFilter, status: { $ne: 'CANCELLED' } } },
      {
        $group: {
          _id: { $ifNull: ['$wingCodeSnapshot', 'UNKNOWN'] },
          billedPaise: { $sum: '$totalAmountPaise' },
          collectedPaise: { $sum: '$amountPaidPaise' },
          outstandingPrincipalPaise: { $sum: '$outstandingPrincipalPaise' },
          billCount: { $sum: 1 },
        },
      },
      {
        $project: {
          _id: 0,
          wingCode: '$_id',
          billedPaise: 1,
          collectedPaise: 1,
          outstandingPrincipalPaise: 1,
          billCount: 1,
        },
      },
      { $sort: { wingCode: 1 } },
    ]),
    FlatModel.countDocuments({
      societyId: societyObjectId,
      $or: [
        { occupancyStatus: 'VACANT' },
        { activeOwnerUserId: { $exists: false } },
        { activeOwnerUserId: null },
      ],
    }),
    FlatModel.countDocuments({ societyId: societyObjectId }),
  ]);

  const totals = billAgg[0] ?? {
    totalBilledPaise: 0,
    totalMaintenanceBilledPaise: 0,
    totalAdditionalServicesBilledPaise: 0,
    totalCollectedPaise: 0,
    totalOutstandingPrincipalPaise: 0,
    totalAccruedInterestPaise: 0,
    paidBills: 0,
    partiallyPaidBills: 0,
    overdueBills: 0,
    issuedBills: 0,
    cancelledBills: 0,
    vacantFlatBills: 0,
    unassignedFlatBills: 0,
    billCount: 0,
  };

  const collectionPercentage =
    totals.totalBilledPaise === 0
      ? 0
      : Math.floor((totals.totalCollectedPaise * 10_000) / totals.totalBilledPaise) / 100;

  const paymentFilter: Record<string, unknown> = { societyId: societyObjectId };
  if (query.paymentStatus) paymentFilter.status = query.paymentStatus;
  if (query.flatId) paymentFilter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.ownerUserId) {
    paymentFilter.ownerUserId = parseObjectId(query.ownerUserId, 'ownerUserId');
  }

  const paymentCounts = await PaymentModel.aggregate<{
    _id: string;
    count: number;
    amountPaise: number;
  }>([
    { $match: paymentFilter },
    {
      $group: {
        _id: '$status',
        count: { $sum: 1 },
        amountPaise: { $sum: '$amountPaise' },
      },
    },
  ]);

  return {
    totalConfiguredFlats: configuredFlats,
    totalBilledPaise: totals.totalBilledPaise,
    totalMaintenanceBilledPaise: totals.totalMaintenanceBilledPaise,
    totalAdditionalServicesBilledPaise: totals.totalAdditionalServicesBilledPaise,
    totalCollectedPaise: totals.totalCollectedPaise,
    totalOutstandingPrincipalPaise: totals.totalOutstandingPrincipalPaise,
    totalAccruedInterestPaise: totals.totalAccruedInterestPaise,
    paidBills: totals.paidBills,
    partiallyPaidBills: totals.partiallyPaidBills,
    pendingBills: totals.issuedBills + totals.partiallyPaidBills,
    overdueBills: totals.overdueBills,
    issuedBills: totals.issuedBills,
    cancelledBills: totals.cancelledBills,
    vacantFlatBills: totals.vacantFlatBills,
    unassignedFlatBills: totals.unassignedFlatBills,
    vacantOrUnassignedFlatsSkipped: vacantOrUnassigned,
    collectionPercentage,
    billCount: totals.billCount,
    wingWise: wingAgg,
    paymentsByStatus: Object.fromEntries(
      paymentCounts.map((row) => [
        row._id,
        { count: row.count, amountPaise: row.amountPaise },
      ]),
    ),
  };
}

export async function getBillingSummary(societyId: string, query: BillingSummaryQuery = {}) {
  const env = getEnv();
  const filtersHash = hashFilters({
    billingPeriodStart: query.billingPeriodStart?.toISOString() ?? null,
    wingCode: query.wingCode?.toUpperCase() ?? null,
    flatId: query.flatId ?? null,
    status: query.status ?? null,
    ownerUserId: query.ownerUserId ?? null,
    paymentStatus: query.paymentStatus ?? null,
    occupancyStatus: query.occupancyStatus ?? null,
    floor: query.floor ?? null,
    ownerAssigned: query.ownerAssigned ?? null,
  });
  return cacheAside(
    CacheKeys.billingSummary(societyId, filtersHash),
    env.CACHE_TTL_REPORTS_SECONDS,
    () => loadBillingSummary(societyId, query),
  );
}
