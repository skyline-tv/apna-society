import { CacheKeys, hashFilters } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { normalizeReportDateRange } from '../utils/filters';
import { getCollectionReport, getOutstandingReport } from './collection-report.service';
import { getComplaintAnalytics } from './complaint-analytics.service';
import { getFinancialReport } from './financial-report.service';

export type DashboardQuery = {
  from?: Date;
  to?: Date;
  wingCode?: string;
  wingId?: string;
};

async function loadReportsDashboard(societyId: string, query: DashboardQuery = {}) {
  const [financial, collections, outstanding, complaints] = await Promise.all([
    getFinancialReport(societyId, query),
    getCollectionReport(societyId, query),
    getOutstandingReport(societyId, { ...query, page: 1, limit: 5 }),
    getComplaintAnalytics(societyId, query),
  ]);

  return {
    from: financial.from,
    to: financial.to,
    wingCode: financial.wingCode,
    financial: {
      totalBilledPaise: financial.totalBilledPaise,
      totalCollectedPaise: financial.totalCollectedPaise,
      totalOutstandingPrincipalPaise: financial.totalOutstandingPrincipalPaise,
      totalAccruedInterestPaise: financial.totalAccruedInterestPaise,
      totalRefundsPaise: financial.totalRefundsPaise,
      totalOfflineCollectionsPaise: financial.totalOfflineCollectionsPaise,
      totalOnlineCollectionsPaise: financial.totalOnlineCollectionsPaise,
      paymentSuccessCount: financial.paymentSuccessCount,
      paymentFailureCount: financial.paymentFailureCount,
      collectionPercentage: financial.collectionPercentage,
    },
    collections: {
      totalBillsGenerated: collections.totalBillsGenerated,
      paidBills: collections.paidBills,
      partiallyPaidBills: collections.partiallyPaidBills,
      unpaidBills: collections.unpaidBills,
      overdueBills: collections.overdueBills,
      collectionPercentage: collections.collectionPercentage,
      wingWise: collections.wingWise,
    },
    outstanding: {
      totals: outstanding.totals,
      topFlats: outstanding.items,
    },
    complaints: {
      totalComplaints: complaints.totalComplaints,
      open: complaints.open,
      assigned: complaints.assigned,
      inProgress: complaints.inProgress,
      resolved: complaints.resolved,
      closed: complaints.closed,
      cancelled: complaints.cancelled,
      averageResolutionHours: complaints.averageResolutionHours,
      byCategory: complaints.byCategory,
    },
  };
}

/**
 * Compact admin dashboard payload — reuses report aggregations (no full collection scans in app memory).
 */
export async function getReportsDashboard(societyId: string, query: DashboardQuery = {}) {
  const { from, to } = normalizeReportDateRange(query);
  const filtersHash = hashFilters({
    from: from.toISOString(),
    to: to.toISOString(),
    wingCode: query.wingCode ?? null,
    wingId: query.wingId ?? null,
  });
  return cacheAside(
    CacheKeys.reportsDashboard(societyId, filtersHash),
    getEnv().CACHE_TTL_DASHBOARD_SECONDS,
    () => loadReportsDashboard(societyId, query),
  );
}
