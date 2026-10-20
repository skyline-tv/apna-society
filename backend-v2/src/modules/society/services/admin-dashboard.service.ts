import { CacheKeys } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { parseObjectId } from '../../../utils/object-id';
import { FlatModel } from '../models/flat.model';
import { WingModel } from '../models/wing.model';
import type { DashboardStats } from '../types/society.types';

async function loadAdminDashboard(societyId: string): Promise<DashboardStats> {
  const societyObjectId = parseObjectId(societyId, 'societyId');

  const [wings, societyAgg, wingAgg] = await Promise.all([
    WingModel.find({ societyId: societyObjectId }).sort({ sortOrder: 1, code: 1 }).lean(),
    FlatModel.aggregate<{
      flats: number;
      activeFlats: number;
      inactiveFlats: number;
      ownerOccupiedFlats: number;
      tenantOccupiedFlats: number;
      vacantFlats: number;
      twoBhkCount: number;
      threeBhkCount: number;
      monthlyMaintenanceTotal: number;
    }>([
      { $match: { societyId: societyObjectId } },
      {
        $group: {
          _id: null,
          flats: { $sum: 1 },
          activeFlats: { $sum: { $cond: ['$isActive', 1, 0] } },
          inactiveFlats: { $sum: { $cond: ['$isActive', 0, 1] } },
          ownerOccupiedFlats: {
            $sum: { $cond: [{ $eq: ['$occupancyStatus', 'OWNER_OCCUPIED'] }, 1, 0] },
          },
          tenantOccupiedFlats: {
            $sum: { $cond: [{ $eq: ['$occupancyStatus', 'TENANT_OCCUPIED'] }, 1, 0] },
          },
          vacantFlats: {
            $sum: { $cond: [{ $eq: ['$occupancyStatus', 'VACANT'] }, 1, 0] },
          },
          twoBhkCount: {
            $sum: { $cond: [{ $eq: ['$flatType', '2BHK'] }, 1, 0] },
          },
          threeBhkCount: {
            $sum: { $cond: [{ $eq: ['$flatType', '3BHK'] }, 1, 0] },
          },
          monthlyMaintenanceTotal: { $sum: '$maintenanceRate' },
        },
      },
    ]),
    FlatModel.aggregate<{
      _id: unknown;
      flatCount: number;
      activeFlats: number;
      inactiveFlats: number;
      ownerOccupiedFlats: number;
      tenantOccupiedFlats: number;
      vacantFlats: number;
      twoBhkCount: number;
      threeBhkCount: number;
      monthlyMaintenanceTotal: number;
    }>([
      { $match: { societyId: societyObjectId } },
      {
        $group: {
          _id: '$wingId',
          flatCount: { $sum: 1 },
          activeFlats: { $sum: { $cond: ['$isActive', 1, 0] } },
          inactiveFlats: { $sum: { $cond: ['$isActive', 0, 1] } },
          ownerOccupiedFlats: {
            $sum: { $cond: [{ $eq: ['$occupancyStatus', 'OWNER_OCCUPIED'] }, 1, 0] },
          },
          tenantOccupiedFlats: {
            $sum: { $cond: [{ $eq: ['$occupancyStatus', 'TENANT_OCCUPIED'] }, 1, 0] },
          },
          vacantFlats: {
            $sum: { $cond: [{ $eq: ['$occupancyStatus', 'VACANT'] }, 1, 0] },
          },
          twoBhkCount: {
            $sum: { $cond: [{ $eq: ['$flatType', '2BHK'] }, 1, 0] },
          },
          threeBhkCount: {
            $sum: { $cond: [{ $eq: ['$flatType', '3BHK'] }, 1, 0] },
          },
          monthlyMaintenanceTotal: { $sum: '$maintenanceRate' },
        },
      },
    ]),
  ]);

  const totals = societyAgg[0] ?? {
    flats: 0,
    activeFlats: 0,
    inactiveFlats: 0,
    ownerOccupiedFlats: 0,
    tenantOccupiedFlats: 0,
    vacantFlats: 0,
    twoBhkCount: 0,
    threeBhkCount: 0,
    monthlyMaintenanceTotal: 0,
  };

  const wingStatsMap = new Map(wingAgg.map((row) => [String(row._id), row]));

  return {
    totals: {
      wings: wings.length,
      flats: totals.flats,
      activeFlats: totals.activeFlats,
      inactiveFlats: totals.inactiveFlats,
      ownerOccupiedFlats: totals.ownerOccupiedFlats,
      tenantOccupiedFlats: totals.tenantOccupiedFlats,
      vacantFlats: totals.vacantFlats,
      twoBhkCount: totals.twoBhkCount,
      threeBhkCount: totals.threeBhkCount,
      monthlyMaintenanceTotal: totals.monthlyMaintenanceTotal,
    },
    wings: wings.map((wing) => {
      const stats = wingStatsMap.get(String(wing._id));
      return {
        id: String(wing._id),
        code: wing.code,
        name: wing.name,
        flatCount: stats?.flatCount ?? 0,
        activeFlats: stats?.activeFlats ?? 0,
        inactiveFlats: stats?.inactiveFlats ?? 0,
        ownerOccupiedFlats: stats?.ownerOccupiedFlats ?? 0,
        tenantOccupiedFlats: stats?.tenantOccupiedFlats ?? 0,
        vacantFlats: stats?.vacantFlats ?? 0,
        twoBhkCount: stats?.twoBhkCount ?? 0,
        threeBhkCount: stats?.threeBhkCount ?? 0,
        monthlyMaintenanceTotal: stats?.monthlyMaintenanceTotal ?? 0,
      };
    }),
  };
}

export async function getAdminDashboard(societyId: string): Promise<DashboardStats> {
  return cacheAside(
    CacheKeys.dashboardOverview(societyId),
    getEnv().CACHE_TTL_DASHBOARD_SECONDS,
    () => loadAdminDashboard(societyId),
  );
}
