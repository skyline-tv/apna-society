import { createHash } from 'crypto';

const SOCIETY_ID_RE = /^[a-f\d]{24}$/i;
const SAFE_SEGMENT_RE = /^[a-zA-Z0-9:_-]{1,64}$/;

function assertSocietyId(societyId: string): string {
  if (!SOCIETY_ID_RE.test(societyId)) {
    throw new Error('Invalid societyId for cache key');
  }
  return societyId;
}

function assertSegment(segment: string): string {
  if (!SAFE_SEGMENT_RE.test(segment)) {
    throw new Error('Invalid cache key segment');
  }
  return segment;
}

/** Stable, non-user-controlled hash of filter objects for report keys. */
export function hashFilters(filters: unknown): string {
  const json = JSON.stringify(filters ?? {});
  return createHash('sha256').update(json).digest('hex').slice(0, 16);
}

export function societyKey(societyId: string, ...parts: string[]): string {
  const sid = assertSocietyId(societyId);
  const safe = parts.map(assertSegment);
  return ['society', sid, ...safe].join(':');
}

export const CacheKeys = {
  dashboardOverview: (societyId: string) => societyKey(societyId, 'dashboard', 'overview'),
  reportsDashboard: (societyId: string, filtersHash: string) =>
    societyKey(societyId, 'reports', 'dashboard', filtersHash),
  financialReport: (societyId: string, filtersHash: string) =>
    societyKey(societyId, 'reports', 'financial', filtersHash),
  collectionReport: (societyId: string, filtersHash: string) =>
    societyKey(societyId, 'reports', 'collection', filtersHash),
  billingSummary: (societyId: string, filtersHash: string) =>
    societyKey(societyId, 'billing', 'summary', filtersHash),
  wingsList: (societyId: string) => societyKey(societyId, 'wings', 'list'),
  facilitiesList: (societyId: string, filtersHash: string) =>
    societyKey(societyId, 'facilities', 'list', filtersHash),
  announcementsFeedMeta: (societyId: string) =>
    societyKey(societyId, 'announcements', 'feed', 'meta'),
  complaintAnalytics: (societyId: string, filtersHash: string) =>
    societyKey(societyId, 'reports', 'complaints', filtersHash),
};

/** Prefix patterns used for safe SCAN-based invalidation (no raw user input). */
export const CachePatterns = {
  societyAll: (societyId: string) => `society:${assertSocietyId(societyId)}:*`,
  societyReports: (societyId: string) => `society:${assertSocietyId(societyId)}:reports:*`,
  societyBilling: (societyId: string) => `society:${assertSocietyId(societyId)}:billing:*`,
  societyDashboard: (societyId: string) => `society:${assertSocietyId(societyId)}:dashboard:*`,
  societyWings: (societyId: string) => `society:${assertSocietyId(societyId)}:wings:*`,
  societyFacilities: (societyId: string) => `society:${assertSocietyId(societyId)}:facilities:*`,
  societyAnnouncements: (societyId: string) =>
    `society:${assertSocietyId(societyId)}:announcements:*`,
};
