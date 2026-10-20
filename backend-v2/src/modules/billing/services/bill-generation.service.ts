import type { ClientSession } from 'mongoose';
import { withTransaction } from '../../../database/connection';
import { badRequest, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError, isTransientTransactionError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { FlatModel } from '../../society/models/flat.model';
import { SocietyModel } from '../../society/models/society.model';
import { WingModel } from '../../society/models/wing.model';
import { UserModel } from '../../users/models/user.model';
import { BillModel } from '../models/bill.model';
import { appendPrincipalEvent } from '../models/principal-ledger.model';
import { nextSequence } from '../models/sequence.model';
import {
  billingPeriodBounds,
  dueDateForBillingPeriod,
  periodsOverlap,
  startOfCivilDay,
} from '../utils/billing-calendar';
import { multiplyPaise, rupeesIntegerToPaise } from '../utils/money';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

export interface GenerateBillsInput {
  billingPeriodStart: Date;
  numberOfMonths: 1 | 3;
  notes?: string;
}

function serializeBill(bill: {
  _id: { toString(): string };
  billNumber: string;
  flatId: { toString(): string };
  ownerUserId: { toString(): string };
  billingPeriodStart: Date;
  billingPeriodEnd: Date;
  numberOfMonths: number;
  monthlyRatePaise: number;
  baseAmountPaise: number;
  totalAmountPaise: number;
  outstandingPrincipalPaise: number;
  interestAccruedPaise: number;
  amountPaidPaise: number;
  dueDate: Date;
  status: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  flatTypeSnapshot: string;
  ownerNameSnapshot: string;
  ownerEmailSnapshot: string;
}) {
  return {
    id: String(bill._id),
    billNumber: bill.billNumber,
    flatId: String(bill.flatId),
    ownerUserId: String(bill.ownerUserId),
    billingPeriodStart: bill.billingPeriodStart.toISOString(),
    billingPeriodEnd: bill.billingPeriodEnd.toISOString(),
    numberOfMonths: bill.numberOfMonths,
    monthlyRatePaise: bill.monthlyRatePaise,
    baseAmountPaise: bill.baseAmountPaise,
    totalAmountPaise: bill.totalAmountPaise,
    outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
    interestAccruedPaise: bill.interestAccruedPaise,
    amountPaidPaise: bill.amountPaidPaise,
    dueDate: bill.dueDate.toISOString(),
    status: bill.status,
    flatNumberSnapshot: bill.flatNumberSnapshot,
    wingCodeSnapshot: bill.wingCodeSnapshot,
    flatTypeSnapshot: bill.flatTypeSnapshot,
    ownerNameSnapshot: bill.ownerNameSnapshot,
    ownerEmailSnapshot: bill.ownerEmailSnapshot,
  };
}

async function createBillNumber(
  societyId: string,
  periodStart: Date,
  session: ClientSession,
): Promise<string> {
  const year = periodStart.getUTCFullYear();
  const seq = await nextSequence(societyId, `bill-${year}`, session);
  return `BILL-${year}-${seq.toString().padStart(6, '0')}`;
}

export async function listEligibleFlats(societyId: string) {
  const flats = await FlatModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
    activeOwnerUserId: { $exists: true, $ne: null },
    occupancyStatus: { $in: ['OWNER_OCCUPIED', 'TENANT_OCCUPIED'] },
  })
    .sort({ number: 1 })
    .lean();

  const wings = await WingModel.find({ societyId }).select('code').lean();
  const wingMap = new Map(wings.map((w) => [String(w._id), w.code]));

  return flats.map((flat) => ({
    id: String(flat._id),
    number: flat.number,
    wingCode: wingMap.get(String(flat.wingId)) ?? '',
    flatType: flat.flatType,
    monthlyRatePaise: rupeesIntegerToPaise(flat.maintenanceRate),
    ownerUserId: String(flat.activeOwnerUserId),
    occupancyStatus: flat.occupancyStatus,
  }));
}

export async function generateBills(
  societyId: string,
  input: GenerateBillsInput,
  actor: Actor,
) {
  if (input.numberOfMonths !== 1 && input.numberOfMonths !== 3) {
    throw badRequest('numberOfMonths must be 1 or 3', 'INVALID_BILLING_MONTHS');
  }

  const society = await SocietyModel.findById(parseObjectId(societyId, 'societyId'));
  if (!society) {
    throw notFound('Society not found');
  }
  const timeZone = society.config?.timezone ?? 'Asia/Kolkata';

  let periodStart: Date;
  let periodEnd: Date;
  try {
    const bounds = billingPeriodBounds(input.billingPeriodStart, input.numberOfMonths, timeZone);
    periodStart = bounds.periodStart;
    periodEnd = bounds.periodEnd;
  } catch {
    throw badRequest(
      'billingPeriodStart must be the 1st of a calendar month',
      'INVALID_BILLING_PERIOD_START',
    );
  }

  const dueDate = dueDateForBillingPeriod(periodStart, timeZone);
  const flats = await FlatModel.find({
    societyId,
    isActive: true,
  }).lean();

  const wings = await WingModel.find({ societyId }).lean();
  const wingMap = new Map(wings.map((w) => [String(w._id), w]));

  const created: ReturnType<typeof serializeBill>[] = [];
  const skipped: Array<{ flatId: string; number: string; reason: string }> = [];
  const conflicts: Array<{ flatId: string; number: string; reason: string; billId?: string }> = [];

  for (const flat of flats) {
    if (!flat.activeOwnerUserId || flat.occupancyStatus === 'VACANT') {
      skipped.push({
        flatId: String(flat._id),
        number: flat.number,
        reason: 'VACANT_OR_UNASSIGNED',
      });
      continue;
    }

    const existing = await BillModel.find({
      societyId,
      flatId: flat._id,
      status: { $ne: 'CANCELLED' },
    }).lean();

    const overlap = existing.find((bill) =>
      periodsOverlap(periodStart, periodEnd, bill.billingPeriodStart, bill.billingPeriodEnd),
    );
    if (overlap) {
      conflicts.push({
        flatId: String(flat._id),
        number: flat.number,
        reason: 'OVERLAPPING_BILLING_PERIOD',
        billId: String(overlap._id),
      });
      continue;
    }

    const owner = await UserModel.findById(flat.activeOwnerUserId).lean();
    if (!owner || !owner.isActive) {
      skipped.push({
        flatId: String(flat._id),
        number: flat.number,
        reason: 'OWNER_INACTIVE_OR_MISSING',
      });
      continue;
    }

    const wing = wingMap.get(String(flat.wingId));
    const monthlyRatePaise = rupeesIntegerToPaise(flat.maintenanceRate);
    const baseAmountPaise = multiplyPaise(monthlyRatePaise, input.numberOfMonths);

    try {
      const bill = await withTransaction(async (session) => {
        const billNumber = await createBillNumber(societyId, periodStart, session);
        const [doc] = await BillModel.create(
          [
            {
              societyId,
              flatId: flat._id,
              billNumber,
              billingPeriodStart: periodStart,
              billingPeriodEnd: periodEnd,
              numberOfMonths: input.numberOfMonths,
              ownerUserId: owner._id,
              ownerNameSnapshot: owner.name,
              ownerEmailSnapshot: owner.email,
              flatNumberSnapshot: flat.number,
              wingCodeSnapshot: wing?.code ?? '',
              flatTypeSnapshot: flat.flatType,
              monthlyRatePaise,
              baseAmountPaise,
              adjustmentsPaise: 0,
              totalAmountPaise: baseAmountPaise,
              amountPaidPaise: 0,
              outstandingPrincipalPaise: baseAmountPaise,
              interestAccruedPaise: 0,
              dueDate,
              status: 'ISSUED',
              generatedAt: new Date(),
              notes: input.notes,
              createdBy: actor.userId,
            },
          ],
          { session },
        );

        await appendPrincipalEvent(
          {
            societyId,
            billId: doc._id,
            eventType: 'OPENING',
            deltaPrincipalPaise: baseAmountPaise,
            principalAfterPaise: baseAmountPaise,
            effectiveAt: startOfCivilDay(periodStart, timeZone),
            sourceType: 'bill',
            sourceId: String(doc._id),
            notes: 'Bill opening principal',
          },
          session,
        );

        await writeAuditLog(
          {
            action: 'BILL_GENERATED',
            actorUserId: actor.userId,
            societyId,
            targetType: 'Bill',
            targetId: String(doc._id),
            metadata: {
              billNumber,
              flatId: String(flat._id),
              ownerUserId: String(owner._id),
              numberOfMonths: input.numberOfMonths,
              totalAmountPaise: baseAmountPaise,
            },
            ipAddress: actor.ipAddress,
            userAgent: actor.userAgent,
          },
          session,
        );

        return doc;
      });

      const serialized = serializeBill(bill);
      created.push(serialized);
      await notifyBusinessEvent({
        societyId,
        recipientUserId: String(bill.ownerUserId),
        type: 'BILL_GENERATED',
        title: 'Maintenance bill generated',
        body: `Bill ${serialized.billNumber} for ${serialized.wingCodeSnapshot}-${serialized.flatNumberSnapshot}`,
        relatedEntityType: 'Bill',
        relatedEntityId: String(bill._id),
        idempotencyKey: `BILL_GENERATED:${String(bill._id)}`,
      });
    } catch (error) {
      if (isDuplicateKeyError(error) || isTransientTransactionError(error)) {
        const existingBill = await BillModel.findOne({
          societyId,
          flatId: flat._id,
          billingPeriodStart: periodStart,
          billingPeriodEnd: periodEnd,
          status: { $ne: 'CANCELLED' },
        })
          .select('_id')
          .lean();
        conflicts.push({
          flatId: String(flat._id),
          number: flat.number,
          reason: isDuplicateKeyError(error) ? 'DUPLICATE_BILL' : 'CONCURRENT_BILL_CONFLICT',
          billId: existingBill ? String(existingBill._id) : undefined,
        });
        continue;
      }
      throw error;
    }
  }

  const totalBilledPaise = created.reduce((sum, b) => sum + b.totalAmountPaise, 0);

  if (created.length > 0) {
    const { invalidateFinancialCaches } = await import('../../../cache/cache-invalidation');
    await invalidateFinancialCaches(societyId);
  }

  return {
    periodStart: periodStart.toISOString(),
    periodEnd: periodEnd.toISOString(),
    dueDate: dueDate.toISOString(),
    numberOfMonths: input.numberOfMonths,
    createdCount: created.length,
    skippedCount: skipped.length,
    conflictCount: conflicts.length,
    totalBilledPaise,
    created,
    skipped,
    conflicts,
  };
}

export async function getBill(societyId: string, billId: string) {
  const bill = await BillModel.findOne({
    _id: parseObjectId(billId, 'billId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!bill) {
    throw notFound('Bill not found');
  }
  return serializeBill(bill);
}

export async function listBills(
  societyId: string,
  query: {
    status?: string;
    flatId?: string;
    ownerUserId?: string;
    wingCode?: string;
    billingPeriodStart?: Date;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.status) filter.status = query.status;
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.ownerUserId) filter.ownerUserId = parseObjectId(query.ownerUserId, 'ownerUserId');
  if (query.wingCode) filter.wingCodeSnapshot = query.wingCode.toUpperCase();
  if (query.billingPeriodStart) filter.billingPeriodStart = query.billingPeriodStart;

  const [total, rows] = await Promise.all([
    BillModel.countDocuments(filter),
    BillModel.find(filter)
      .sort({ billingPeriodStart: -1, flatNumberSnapshot: 1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((row) => serializeBill(row)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

/**
 * Admin adjustment: changes adjustmentsPaise / total / outstanding without mutating
 * the original base amount or monthly rate snapshot. Audited.
 */
export async function adjustBill(
  societyId: string,
  billId: string,
  input: { adjustmentsPaise: number; notes?: string },
  actor: Actor,
) {
  if (!Number.isInteger(input.adjustmentsPaise)) {
    throw badRequest('adjustmentsPaise must be an integer', 'INVALID_ADJUSTMENT');
  }

  const bill = await BillModel.findOne({
    _id: parseObjectId(billId, 'billId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!bill) {
    throw notFound('Bill not found');
  }
  if (bill.status === 'CANCELLED' || bill.status === 'PAID') {
    throw badRequest('Cannot adjust cancelled or paid bills', 'BILL_NOT_ADJUSTABLE');
  }

  const previous = {
    adjustmentsPaise: bill.adjustmentsPaise,
    totalAmountPaise: bill.totalAmountPaise,
    outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
  };

  const newTotal = bill.baseAmountPaise + input.adjustmentsPaise;
  if (newTotal < bill.amountPaidPaise) {
    throw badRequest(
      'Adjustment would make total less than amount already paid',
      'INVALID_ADJUSTMENT',
    );
  }

  const society = await SocietyModel.findById(societyId).lean();
  const timeZone = society?.config?.timezone ?? 'Asia/Kolkata';
  const delta = input.adjustmentsPaise - bill.adjustmentsPaise;

  await withTransaction(async (session) => {
    bill.adjustmentsPaise = input.adjustmentsPaise;
    bill.totalAmountPaise = newTotal;
    bill.outstandingPrincipalPaise = newTotal - bill.amountPaidPaise;
    if (input.notes) {
      bill.notes = [bill.notes, input.notes].filter(Boolean).join('\n');
    }
    bill.updatedBy = parseObjectId(actor.userId, 'userId');
    if (bill.outstandingPrincipalPaise <= 0) {
      bill.status = 'PAID';
    } else if (bill.amountPaidPaise > 0) {
      bill.status = Date.now() > bill.dueDate.getTime() ? 'OVERDUE' : 'PARTIALLY_PAID';
    } else if (Date.now() > bill.dueDate.getTime()) {
      bill.status = 'OVERDUE';
    }
    await bill.save({ session });

    await appendPrincipalEvent(
      {
        societyId,
        billId: bill._id,
        eventType: 'ADJUSTMENT',
        deltaPrincipalPaise: delta,
        principalAfterPaise: bill.outstandingPrincipalPaise,
        effectiveAt: startOfCivilDay(new Date(), timeZone),
        sourceType: 'adjustment',
        sourceId: `${billId}:${Date.now()}`,
        notes: input.notes,
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'BILL_ADJUSTED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Bill',
        targetId: billId,
        metadata: {
          previous,
          adjustmentsPaise: bill.adjustmentsPaise,
          totalAmountPaise: bill.totalAmountPaise,
          outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
          baseAmountPaise: bill.baseAmountPaise,
          monthlyRatePaise: bill.monthlyRatePaise,
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
  });

  return serializeBill(bill);
}

export async function cancelBill(
  societyId: string,
  billId: string,
  reason: string,
  actor: Actor,
) {
  const bill = await BillModel.findOne({
    _id: parseObjectId(billId, 'billId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!bill) {
    throw notFound('Bill not found');
  }
  if (bill.status === 'CANCELLED') {
    return serializeBill(bill);
  }
  if (bill.amountPaidPaise > 0) {
    throw badRequest('Cannot cancel a bill with successful payments', 'BILL_HAS_PAYMENTS');
  }

  bill.status = 'CANCELLED';
  bill.cancelledAt = new Date();
  bill.cancellationReason = reason;
  bill.updatedBy = parseObjectId(actor.userId, 'userId');
  await bill.save();

  await writeAuditLog({
    action: 'BILL_CANCELLED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Bill',
    targetId: billId,
    metadata: { reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeBill(bill);
}

export { serializeBill };
