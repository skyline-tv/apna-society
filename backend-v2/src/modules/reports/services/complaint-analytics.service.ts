import { Types } from 'mongoose';
import { CacheKeys, hashFilters } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { ComplaintModel } from '../../complaints/models/complaint.model';
import { FlatModel } from '../../society/models/flat.model';
import { WingModel } from '../../society/models/wing.model';
import { normalizeReportDateRange, resolveWingCode, societyMatch } from '../utils/filters';

export type ComplaintAnalyticsQuery = {
  from?: Date;
  to?: Date;
  wingCode?: string;
  wingId?: string;
  flatId?: string;
};

async function loadComplaintAnalytics(
  societyId: string,
  query: ComplaintAnalyticsQuery = {},
) {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);
  const societyObjectId = societyMatch(societyId).societyId;

  let flatIds: Types.ObjectId[] | undefined;
  if (wingCode || query.flatId) {
    const flatFilter: Record<string, unknown> = {
      societyId: societyObjectId,
      isActive: true,
    };
    if (query.flatId) {
      flatFilter._id = new Types.ObjectId(query.flatId);
    }
    if (wingCode) {
      const wing = await WingModel.findOne({
        societyId: societyObjectId,
        code: wingCode,
        isActive: true,
      })
        .select('_id')
        .lean();
      if (!wing) {
        return emptyComplaintAnalytics(from, to, wingCode, query.flatId);
      }
      flatFilter.wingId = wing._id;
    }
    const flats = await FlatModel.find(flatFilter).select('_id').lean();
    flatIds = flats.map((f) => f._id as Types.ObjectId);
    if (flatIds.length === 0) {
      return emptyComplaintAnalytics(from, to, wingCode, query.flatId);
    }
  }

  const match: Record<string, unknown> = {
    societyId: societyObjectId,
    createdAt: { $gte: from, $lte: to },
  };
  if (flatIds) match.flatId = { $in: flatIds };

  const byStatus = await ComplaintModel.aggregate<{ _id: string; count: number }>([
    { $match: match },
    { $group: { _id: '$status', count: { $sum: 1 } } },
  ]);
  const statusCounts = Object.fromEntries(byStatus.map((r) => [r._id, r.count])) as Record<
    string,
    number
  >;

  const byCategory = await ComplaintModel.aggregate<{ _id: string; count: number }>([
    { $match: match },
    { $group: { _id: '$category', count: { $sum: 1 } } },
    { $sort: { count: -1 } },
  ]);

  const byPriority = await ComplaintModel.aggregate<{ _id: string; count: number }>([
    { $match: match },
    { $group: { _id: '$priority', count: { $sum: 1 } } },
  ]);

  // Wing breakdown via Flat join (complaints store flatId only).
  const byWing = await ComplaintModel.aggregate<{
    wingCode: string;
    count: number;
  }>([
    { $match: match },
    {
      $lookup: {
        from: 'flats',
        localField: 'flatId',
        foreignField: '_id',
        as: 'flat',
      },
    },
    { $unwind: { path: '$flat', preserveNullAndEmptyArrays: true } },
    {
      $lookup: {
        from: 'wings',
        localField: 'flat.wingId',
        foreignField: '_id',
        as: 'wing',
      },
    },
    { $unwind: { path: '$wing', preserveNullAndEmptyArrays: true } },
    {
      $group: {
        _id: { $ifNull: ['$wing.code', 'UNKNOWN'] },
        count: { $sum: 1 },
      },
    },
    { $sort: { _id: 1 } },
    { $project: { _id: 0, wingCode: '$_id', count: 1 } },
  ]);

  // Average resolution time only where resolvedAt exists (never invent timestamps).
  const [resolution] = await ComplaintModel.aggregate<{
    avgResolutionMs: number | null;
    resolvedCount: number;
  }>([
    {
      $match: {
        ...match,
        resolvedAt: { $exists: true, $ne: null },
      },
    },
    {
      $project: {
        durationMs: { $subtract: ['$resolvedAt', '$createdAt'] },
      },
    },
    {
      $group: {
        _id: null,
        avgResolutionMs: { $avg: '$durationMs' },
        resolvedCount: { $sum: 1 },
      },
    },
  ]);

  const trends = await ComplaintModel.aggregate<{
    year: number;
    month: number;
    count: number;
  }>([
    { $match: match },
    {
      $group: {
        _id: {
          year: { $year: '$createdAt' },
          month: { $month: '$createdAt' },
        },
        count: { $sum: 1 },
      },
    },
    { $sort: { '_id.year': 1, '_id.month': 1 } },
    {
      $project: {
        _id: 0,
        year: '$_id.year',
        month: '$_id.month',
        count: 1,
      },
    },
  ]);

  const workload = await ComplaintModel.aggregate<{
    assignedToUserId: string | null;
    assignedToName: string;
    openAssigned: number;
  }>([
    {
      $match: {
        ...match,
        status: { $in: ['ASSIGNED', 'IN_PROGRESS'] },
      },
    },
    {
      $group: {
        _id: {
          userId: '$assignedToUserId',
          name: { $ifNull: ['$assignedToNameSnapshot', 'UNASSIGNED'] },
        },
        openAssigned: { $sum: 1 },
      },
    },
    { $sort: { openAssigned: -1 } },
    {
      $project: {
        _id: 0,
        assignedToUserId: {
          $cond: [
            { $ifNull: ['$_id.userId', false] },
            { $toString: '$_id.userId' },
            null,
          ],
        },
        assignedToName: '$_id.name',
        openAssigned: 1,
      },
    },
  ]);

  const total = byStatus.reduce((n, r) => n + r.count, 0);
  const avgMs = resolution?.avgResolutionMs;
  const averageResolutionHours =
    avgMs === null || avgMs === undefined
      ? null
      : Math.round((avgMs / (1000 * 60 * 60)) * 100) / 100;

  return {
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: wingCode ?? null,
    flatId: query.flatId ?? null,
    totalComplaints: total,
    open: statusCounts.OPEN ?? 0,
    assigned: statusCounts.ASSIGNED ?? 0,
    inProgress: statusCounts.IN_PROGRESS ?? 0,
    resolved: statusCounts.RESOLVED ?? 0,
    closed: statusCounts.CLOSED ?? 0,
    cancelled: statusCounts.CANCELLED ?? 0,
    byCategory: Object.fromEntries(byCategory.map((r) => [r._id, r.count])),
    byPriority: Object.fromEntries(byPriority.map((r) => [r._id, r.count])),
    byWing,
    averageResolutionHours,
    resolvedWithTimestampCount: resolution?.resolvedCount ?? 0,
    trends,
    workload,
    note: 'averageResolutionHours uses resolvedAt - createdAt only when resolvedAt is present.',
  };
}

export async function getComplaintAnalytics(
  societyId: string,
  query: ComplaintAnalyticsQuery = {},
) {
  const { from, to } = normalizeReportDateRange(query);
  const filtersHash = hashFilters({
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: query.wingCode ?? null,
    wingId: query.wingId ?? null,
    flatId: query.flatId ?? null,
  });
  return cacheAside(
    CacheKeys.complaintAnalytics(societyId, filtersHash),
    getEnv().CACHE_TTL_REPORTS_SECONDS,
    () => loadComplaintAnalytics(societyId, query),
  );
}

function emptyComplaintAnalytics(
  from: Date,
  to: Date,
  wingCode: string | undefined,
  flatId: string | undefined,
) {
  return {
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: wingCode ?? null,
    flatId: flatId ?? null,
    totalComplaints: 0,
    open: 0,
    assigned: 0,
    inProgress: 0,
    resolved: 0,
    closed: 0,
    cancelled: 0,
    byCategory: {},
    byPriority: {},
    byWing: [] as { wingCode: string; count: number }[],
    averageResolutionHours: null as number | null,
    resolvedWithTimestampCount: 0,
    trends: [] as { year: number; month: number; count: number }[],
    workload: [] as {
      assignedToUserId: string | null;
      assignedToName: string;
      openAssigned: number;
    }[],
    note: 'averageResolutionHours uses resolvedAt - createdAt only when resolvedAt is present.',
  };
}
