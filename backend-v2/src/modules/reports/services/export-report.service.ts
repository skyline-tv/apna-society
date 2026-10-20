import type { Response } from 'express';
import { Types } from 'mongoose';
import { BillModel } from '../../billing/models/bill.model';
import { PaymentModel } from '../../billing/models/payment.model';
import { ComplaintModel } from '../../complaints/models/complaint.model';
import { FlatModel } from '../../society/models/flat.model';
import { WingModel } from '../../society/models/wing.model';
import {
  csvRow,
  formatIsoDate,
  formatPaiseAsRupees,
} from '../utils/csv';
import { normalizeReportDateRange, resolveWingCode, societyMatch } from '../utils/filters';

export type ExportQuery = {
  from?: Date;
  to?: Date;
  wingCode?: string;
  wingId?: string;
  flatId?: string;
  paymentMethod?: string;
  paymentStatus?: string;
};

function setCsvHeaders(res: Response, filename: string): void {
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Cache-Control', 'no-store');
}

async function wingFlatIds(
  societyId: string,
  wingCode: string | undefined,
  flatId: string | undefined,
): Promise<Types.ObjectId[] | undefined> {
  if (!wingCode && !flatId) return undefined;
  const societyObjectId = societyMatch(societyId).societyId;
  const filter: Record<string, unknown> = { societyId: societyObjectId, isActive: true };
  if (flatId) filter._id = new Types.ObjectId(flatId);
  if (wingCode) {
    const wing = await WingModel.findOne({
      societyId: societyObjectId,
      code: wingCode,
      isActive: true,
    })
      .select('_id')
      .lean();
    if (!wing) return [];
    filter.wingId = wing._id;
  }
  const flats = await FlatModel.find(filter).select('_id').lean();
  return flats.map((f) => f._id as Types.ObjectId);
}

export async function exportFinancialCsv(
  societyId: string,
  query: ExportQuery,
  res: Response,
  filenamePrefix = 'financial-report',
): Promise<void> {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);
  const match: Record<string, unknown> = {
    ...societyMatch(societyId),
    billingPeriodStart: { $gte: from, $lte: to },
    status: { $ne: 'CANCELLED' },
  };
  if (wingCode) match.wingCodeSnapshot = wingCode;
  if (query.flatId) match.flatId = new Types.ObjectId(query.flatId);

  setCsvHeaders(res, `${filenamePrefix}-${from.toISOString().slice(0, 10)}.csv`);
  res.write(
    csvRow([
      'billNumber',
      'wingCode',
      'flatNumber',
      'ownerName',
      'status',
      'billingPeriodStart',
      'dueDate',
      'billedRupees',
      'collectedRupees',
      'outstandingPrincipalRupees',
      'accruedInterestRupees',
      'monthlyRateRupees',
    ]),
  );

  const cursor = BillModel.find(match)
    .select(
      'billNumber wingCodeSnapshot flatNumberSnapshot ownerNameSnapshot status billingPeriodStart dueDate totalAmountPaise amountPaidPaise outstandingPrincipalPaise interestAccruedPaise monthlyRatePaise',
    )
    .sort({ billingPeriodStart: 1, billNumber: 1 })
    .lean()
    .cursor();

  for await (const bill of cursor) {
    res.write(
      csvRow([
        bill.billNumber,
        bill.wingCodeSnapshot,
        bill.flatNumberSnapshot,
        bill.ownerNameSnapshot,
        bill.status,
        formatIsoDate(bill.billingPeriodStart),
        formatIsoDate(bill.dueDate),
        formatPaiseAsRupees(bill.totalAmountPaise),
        formatPaiseAsRupees(bill.amountPaidPaise),
        formatPaiseAsRupees(bill.outstandingPrincipalPaise),
        formatPaiseAsRupees(bill.interestAccruedPaise),
        formatPaiseAsRupees(bill.monthlyRatePaise),
      ]),
    );
  }
  res.end();
}

export async function exportCollectionsCsv(
  societyId: string,
  query: ExportQuery,
  res: Response,
): Promise<void> {
  await exportFinancialCsv(societyId, query, res, 'collection-report');
}

export async function exportOutstandingCsv(
  societyId: string,
  query: ExportQuery,
  res: Response,
): Promise<void> {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);
  const match: Record<string, unknown> = {
    ...societyMatch(societyId),
    billingPeriodStart: { $gte: from, $lte: to },
    status: { $ne: 'CANCELLED' },
    outstandingPrincipalPaise: { $gt: 0 },
  };
  if (wingCode) match.wingCodeSnapshot = wingCode;
  if (query.flatId) match.flatId = new Types.ObjectId(query.flatId);

  setCsvHeaders(res, `outstanding-dues-${from.toISOString().slice(0, 10)}.csv`);
  res.write(
    csvRow([
      'wingCode',
      'flatNumber',
      'ownerName',
      'billNumber',
      'status',
      'dueDate',
      'outstandingPrincipalRupees',
      'accruedInterestRupees',
      'billedRupees',
      'collectedRupees',
    ]),
  );

  const cursor = BillModel.find(match)
    .select(
      'wingCodeSnapshot flatNumberSnapshot ownerNameSnapshot billNumber status dueDate outstandingPrincipalPaise interestAccruedPaise totalAmountPaise amountPaidPaise',
    )
    .sort({ outstandingPrincipalPaise: -1 })
    .lean()
    .cursor();

  for await (const bill of cursor) {
    res.write(
      csvRow([
        bill.wingCodeSnapshot,
        bill.flatNumberSnapshot,
        bill.ownerNameSnapshot,
        bill.billNumber,
        bill.status,
        formatIsoDate(bill.dueDate),
        formatPaiseAsRupees(bill.outstandingPrincipalPaise),
        formatPaiseAsRupees(bill.interestAccruedPaise),
        formatPaiseAsRupees(bill.totalAmountPaise),
        formatPaiseAsRupees(bill.amountPaidPaise),
      ]),
    );
  }
  res.end();
}

export async function exportPaymentsCsv(
  societyId: string,
  query: ExportQuery,
  res: Response,
): Promise<void> {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);

  let billIds: Types.ObjectId[] | undefined;
  if (wingCode) {
    const bills = await BillModel.find({
      ...societyMatch(societyId),
      wingCodeSnapshot: wingCode,
    })
      .select('_id')
      .lean();
    billIds = bills.map((b) => b._id as Types.ObjectId);
  }

  const match: Record<string, unknown> = {
    ...societyMatch(societyId),
    $or: [
      { paidAt: { $gte: from, $lte: to } },
      { paidAt: null, createdAt: { $gte: from, $lte: to } },
    ],
  };
  if (query.flatId) match.flatId = new Types.ObjectId(query.flatId);
  if (query.paymentMethod) match.paymentMethod = query.paymentMethod;
  if (query.paymentStatus) match.status = query.paymentStatus;
  if (billIds) match.billId = { $in: billIds };

  setCsvHeaders(res, `payment-history-${from.toISOString().slice(0, 10)}.csv`);
  res.write(
    csvRow([
      'paymentNumber',
      'status',
      'paymentMethod',
      'amountRupees',
      'allocatedPrincipalRupees',
      'allocatedInterestRupees',
      'paidAt',
      'createdAt',
      'billId',
      'flatId',
      'referenceNumber',
    ]),
  );

  const cursor = PaymentModel.find(match)
    .select(
      'paymentNumber status paymentMethod amountPaise allocatedToPrincipalPaise allocatedToInterestPaise paidAt createdAt billId flatId referenceNumber',
    )
    .sort({ createdAt: 1 })
    .lean()
    .cursor();

  for await (const payment of cursor) {
    res.write(
      csvRow([
        payment.paymentNumber,
        payment.status,
        payment.paymentMethod,
        formatPaiseAsRupees(payment.amountPaise),
        formatPaiseAsRupees(payment.allocatedToPrincipalPaise),
        formatPaiseAsRupees(payment.allocatedToInterestPaise),
        formatIsoDate(payment.paidAt),
        formatIsoDate(payment.createdAt),
        String(payment.billId),
        String(payment.flatId),
        payment.referenceNumber ?? '',
      ]),
    );
  }
  res.end();
}

export async function exportComplaintsCsv(
  societyId: string,
  query: ExportQuery,
  res: Response,
): Promise<void> {
  const { from, to } = normalizeReportDateRange(query);
  const wingCode = await resolveWingCode(societyId, query);
  const flatIds = await wingFlatIds(societyId, wingCode, query.flatId);

  const match: Record<string, unknown> = {
    ...societyMatch(societyId),
    createdAt: { $gte: from, $lte: to },
  };
  if (flatIds) {
    if (flatIds.length === 0) {
      setCsvHeaders(res, `complaints-${from.toISOString().slice(0, 10)}.csv`);
      res.write(
        csvRow([
          'complaintNumber',
          'status',
          'category',
          'priority',
          'title',
          'flatId',
          'assignedToName',
          'createdAt',
          'resolvedAt',
          'closedAt',
        ]),
      );
      res.end();
      return;
    }
    match.flatId = { $in: flatIds };
  }

  setCsvHeaders(res, `complaints-${from.toISOString().slice(0, 10)}.csv`);
  res.write(
    csvRow([
      'complaintNumber',
      'status',
      'category',
      'priority',
      'title',
      'flatId',
      'assignedToName',
      'createdAt',
      'resolvedAt',
      'closedAt',
    ]),
  );

  const cursor = ComplaintModel.find(match)
    .select(
      'complaintNumber status category priority title flatId assignedToNameSnapshot createdAt resolvedAt closedAt',
    )
    .sort({ createdAt: 1 })
    .lean()
    .cursor();

  for await (const c of cursor) {
    res.write(
      csvRow([
        c.complaintNumber,
        c.status,
        c.category,
        c.priority,
        c.title,
        String(c.flatId),
        c.assignedToNameSnapshot ?? '',
        formatIsoDate(c.createdAt),
        formatIsoDate(c.resolvedAt),
        formatIsoDate(c.closedAt),
      ]),
    );
  }
  res.end();
}
