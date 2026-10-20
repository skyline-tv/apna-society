import { CacheKeys, CachePatterns } from './cache-keys';
import { cacheDelete, cacheDeleteByPattern } from './cache.service';

/** Call only after the related MongoDB transaction/write has committed. */
export async function invalidateFinancialCaches(societyId: string): Promise<void> {
  await Promise.all([
    cacheDeleteByPattern(CachePatterns.societyReports(societyId)),
    cacheDeleteByPattern(CachePatterns.societyBilling(societyId)),
    cacheDeleteByPattern(CachePatterns.societyDashboard(societyId)),
    cacheDelete(CacheKeys.dashboardOverview(societyId)),
  ]);
}

export async function invalidateOccupancyCaches(societyId: string): Promise<void> {
  await Promise.all([
    cacheDelete(CacheKeys.dashboardOverview(societyId)),
    cacheDeleteByPattern(CachePatterns.societyDashboard(societyId)),
    cacheDeleteByPattern(CachePatterns.societyWings(societyId)),
    cacheDeleteByPattern(CachePatterns.societyAnnouncements(societyId)),
  ]);
}

export async function invalidateWingCaches(societyId: string): Promise<void> {
  await Promise.all([
    cacheDeleteByPattern(CachePatterns.societyWings(societyId)),
    cacheDelete(CacheKeys.dashboardOverview(societyId)),
  ]);
}

export async function invalidateFacilityCaches(societyId: string): Promise<void> {
  await cacheDeleteByPattern(CachePatterns.societyFacilities(societyId));
}

export async function invalidateAnnouncementCaches(societyId: string): Promise<void> {
  await cacheDeleteByPattern(CachePatterns.societyAnnouncements(societyId));
}

export async function invalidateComplaintCaches(societyId: string): Promise<void> {
  await cacheDeleteByPattern(CachePatterns.societyReports(societyId));
}
