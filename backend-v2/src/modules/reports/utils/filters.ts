import { badRequest } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { WingModel } from '../../society/models/wing.model';
import { REPORT_DEFAULT_LOOKBACK_MS, REPORT_MAX_RANGE_MS } from './report-math';

export type ReportDateField = 'generatedAt' | 'paidAt' | 'createdAt' | 'dueDate';

export async function resolveWingCode(
  societyId: string,
  input: { wingCode?: string; wingId?: string },
): Promise<string | undefined> {
  if (input.wingCode) return input.wingCode.trim().toUpperCase();
  if (!input.wingId) return undefined;
  const wing = await WingModel.findOne({
    _id: parseObjectId(input.wingId, 'wingId'),
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
  })
    .select('code')
    .lean();
  if (!wing) throw badRequest('Wing not found in this society', 'INVALID_WING');
  return String(wing.code).toUpperCase();
}

/**
 * Normalize from/to. Defaults to last 365 days when omitted.
 * Rejects inverted ranges and spans longer than REPORT_MAX_RANGE_MS.
 */
export function normalizeReportDateRange(input: {
  from?: Date;
  to?: Date;
  now?: Date;
}): { from: Date; to: Date } {
  const now = input.now ?? new Date();
  let from = input.from;
  let to = input.to;

  if (!from && !to) {
    to = now;
    from = new Date(now.getTime() - REPORT_DEFAULT_LOOKBACK_MS);
  } else if (from && !to) {
    to = now;
  } else if (!from && to) {
    from = new Date(to.getTime() - REPORT_DEFAULT_LOOKBACK_MS);
  }

  if (!from || !to) {
    throw badRequest('Invalid date range', 'INVALID_DATE_RANGE');
  }
  if (from.getTime() > to.getTime()) {
    throw badRequest('from must be before or equal to to', 'INVALID_DATE_RANGE');
  }
  if (to.getTime() - from.getTime() > REPORT_MAX_RANGE_MS) {
    throw badRequest('Date range exceeds maximum of 3 years', 'DATE_RANGE_TOO_LARGE');
  }
  return { from, to };
}

export function societyMatch(societyId: string): { societyId: ReturnType<typeof parseObjectId> } {
  return { societyId: parseObjectId(societyId, 'societyId') };
}
