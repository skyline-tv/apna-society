import type { ClientSession } from 'mongoose';
import { withTransaction } from '../../../database/connection';
import { badRequest, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError, isTransientTransactionError } from '../../../utils/mongo-errors';
import { formatFlatLabel } from '../../../utils/flat-label';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { FlatModel } from '../../society/models/flat.model';
import { SocietyModel } from '../../society/models/society.model';
import { WingModel } from '../../society/models/wing.model';
import { UserModel } from '../../users/models/user.model';
import { FlatAdditionalServiceModel } from '../models/additional-service.model';
import { BillModel, type BillLineItem } from '../models/bill.model';
import { PaymentModel } from '../models/payment.model';
import { ReceiptModel } from '../models/receipt.model';
import { appendPrincipalEvent } from '../models/principal-ledger.model';
import { nextSequence } from '../models/sequence.model';
import {
  billingPeriodBounds,
  dueDateForBillingPeriod,
  periodsOverlap,
  startOfCivilDay,
} from '../utils/billing-calendar';
import { billComputedTotalPaise } from '../utils/bill-totals';
import { multiplyPaise, rupeesIntegerToPaise } from '../utils/money';
import { getBillInterest } from './interest.service';
import { ensureSocietyInterestCurrent } from './interest-worker.service';
import { chargeAdditionalServiceForPeriod } from '../utils/additional-service-proration';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

export interface GenerateBillsInput {
  billingPeriodStart: Date;
  numberOfMonths: 1 | 3;
  notes?: string;
}

const UNASSIGNED_OWNER_NAME = 'Unassigned';

function serializeLineItem(item: BillLineItem) {
  return {
    type: item.type,
    serviceId: item.serviceId ? String(item.serviceId) : undefined,
    name: item.name,
    description: item.description,
    quantity: item.quantity,
    unitAmountPaise: item.unitAmountPaise,
    amountPaise: item.amountPaise,
    applicableDays: item.applicableDays,
    billedDays: item.billedDays,
    prorationPolicy: item.prorationPolicy,
  };
}

function serializeBill(bill: {
  _id: { toString(): string };
  billNumber: string;
  flatId: { toString(): string };
  ownerUserId?: { toString(): string } | null;
  billingPeriodStart: Date;
  billingPeriodEnd: Date;
  numberOfMonths: number;
  monthlyRatePaise: number;
  baseAmountPaise: number;
  additionalServicesTotalPaise?: number;
  adjustmentsPaise?: number;
  lineItems?: BillLineItem[];
  totalAmountPaise: number;
  outstandingPrincipalPaise: number;
  interestAccruedPaise: number;
  amountPaidPaise: number;
  dueDate: Date;
  status: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  flatTypeSnapshot: string;
  occupancyStatusSnapshot?: string;
  floorSnapshot?: number;
  flatIsActiveSnapshot?: boolean;
  ownerNameSnapshot: string;
  ownerEmailSnapshot: string;
}) {
  const additionalServicesTotalPaise = bill.additionalServicesTotalPaise ?? 0;
  const adjustmentsPaise = bill.adjustmentsPaise ?? 0;
  const lineItems = (bill.lineItems ?? []).map(serializeLineItem);
  const fallbackItems =
    lineItems.length > 0
      ? lineItems
      : [
          {
            type: 'MAINTENANCE' as const,
            serviceId: undefined,
            name: 'Monthly maintenance',
            description: undefined,
            quantity: bill.numberOfMonths,
            unitAmountPaise: bill.monthlyRatePaise,
            amountPaise: bill.baseAmountPaise,
            applicableDays: undefined,
            billedDays: undefined,
            prorationPolicy: undefined,
          },
        ];
  return {
    id: String(bill._id),
    billNumber: bill.billNumber,
    flatId: String(bill.flatId),
    ownerUserId: bill.ownerUserId ? String(bill.ownerUserId) : undefined,
    ownerAssigned: Boolean(bill.ownerUserId),
    billingPeriodStart: bill.billingPeriodStart.toISOString(),
    billingPeriodEnd: bill.billingPeriodEnd.toISOString(),
    numberOfMonths: bill.numberOfMonths,
    monthlyRatePaise: bill.monthlyRatePaise,
    baseAmountPaise: bill.baseAmountPaise,
    additionalServicesTotalPaise,
    adjustmentsPaise,
    lineItems: fallbackItems,
    totalAmountPaise: bill.totalAmountPaise,
    outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
    interestAccruedPaise: bill.interestAccruedPaise,
    totalPayablePaise: bill.outstandingPrincipalPaise + bill.interestAccruedPaise,
    amountPaidPaise: bill.amountPaidPaise,
    dueDate: bill.dueDate.toISOString(),
    status: bill.status,
    flatNumberSnapshot: bill.flatNumberSnapshot,
    wingCodeSnapshot: bill.wingCodeSnapshot,
    flatLabel: formatFlatLabel(bill.wingCodeSnapshot, bill.flatNumberSnapshot),
    flatTypeSnapshot: bill.flatTypeSnapshot,
    occupancyStatusSnapshot: bill.occupancyStatusSnapshot,
    floorSnapshot: bill.floorSnapshot,
    flatIsActiveSnapshot: bill.flatIsActiveSnapshot,
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

/**
 * Every configured flat is billable. Occupancy, active flag, and owner/tenant
 * assignment must never exclude a flat from generation.
 */
export async function listEligibleFlats(societyId: string) {
  const flats = await FlatModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
  })
    .sort({ number: 1 })
    .lean();

  const wings = await WingModel.find({ societyId }).select('code').lean();
  const wingMap = new Map(wings.map((w) => [String(w._id), w.code]));

  const services = await FlatAdditionalServiceModel.find({
    societyId,
    isActive: true,
  })
    .select('flatId monthlyChargePaise quantity')
    .lean();
  const additionalByFlat = new Map<string, number>();
  for (const service of services) {
    const key = String(service.flatId);
    additionalByFlat.set(
      key,
      (additionalByFlat.get(key) ?? 0) + service.monthlyChargePaise * service.quantity,
    );
  }

  return flats.map((flat) => {
    const monthlyRatePaise = rupeesIntegerToPaise(flat.maintenanceRate);
    const recurringAdditionalPaise = additionalByFlat.get(String(flat._id)) ?? 0;
    return {
      id: String(flat._id),
      number: flat.number,
      wingCode: wingMap.get(String(flat.wingId)) ?? '',
      floor: flat.floor,
      flatType: flat.flatType,
      monthlyRatePaise,
      recurringAdditionalPaise,
      recurringMonthlyTotalPaise: monthlyRatePaise + recurringAdditionalPaise,
      ownerUserId: flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : undefined,
      occupancyStatus: flat.occupancyStatus,
      isActive: flat.isActive,
      ownerAssigned: Boolean(flat.activeOwnerUserId),
    };
  });
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
  const flats = await FlatModel.find({ societyId }).sort({ number: 1 }).lean();

  const wings = await WingModel.find({ societyId }).lean();
  const wingMap = new Map(wings.map((w) => [String(w._id), w]));

  const ownerIds = flats
    .map((flat) => flat.activeOwnerUserId)
    .filter((id): id is NonNullable<typeof id> => Boolean(id));
  const owners = await UserModel.find({ _id: { $in: ownerIds } }).lean();
  const ownerMap = new Map(owners.map((owner) => [String(owner._id), owner]));

  const services = await FlatAdditionalServiceModel.find({ societyId }).lean();
  const servicesByFlat = new Map<string, typeof services>();
  for (const service of services) {
    const key = String(service.flatId);
    const list = servicesByFlat.get(key) ?? [];
    list.push(service);
    servicesByFlat.set(key, list);
  }

  const created: ReturnType<typeof serializeBill>[] = [];
  const skipped: Array<{ flatId: string; number: string; reason: string }> = [];
  const conflicts: Array<{ flatId: string; number: string; reason: string; billId?: string }> = [];
  let vacantOrUnassignedCount = 0;

  for (const flat of flats) {
    const unassigned = !flat.activeOwnerUserId || flat.occupancyStatus === 'VACANT';
    if (unassigned) vacantOrUnassignedCount += 1;

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

    const owner = flat.activeOwnerUserId
      ? ownerMap.get(String(flat.activeOwnerUserId))
      : undefined;
    const wing = wingMap.get(String(flat.wingId));
    const monthlyRatePaise = rupeesIntegerToPaise(flat.maintenanceRate);
    const baseAmountPaise = multiplyPaise(monthlyRatePaise, input.numberOfMonths);

    const lineItems: BillLineItem[] = [
      {
        type: 'MAINTENANCE',
        name: 'Monthly maintenance',
        quantity: input.numberOfMonths,
        unitAmountPaise: monthlyRatePaise,
        amountPaise: baseAmountPaise,
      },
    ];

    let additionalServicesTotalPaise = 0;
    for (const service of servicesByFlat.get(String(flat._id)) ?? []) {
      const snapshot = chargeAdditionalServiceForPeriod(
        {
          id: String(service._id),
          name: service.name,
          description: service.description,
          monthlyChargePaise: service.monthlyChargePaise,
          quantity: service.quantity,
          effectiveFrom: service.effectiveFrom,
          effectiveTo: service.effectiveTo,
          isActive: service.isActive,
        },
        periodStart,
        periodEnd,
        timeZone,
      );
      if (!snapshot) continue;
      additionalServicesTotalPaise += snapshot.amountPaise;
      lineItems.push({
        type: 'ADDITIONAL_SERVICE',
        serviceId: service._id,
        name: snapshot.name,
        description: snapshot.description,
        quantity: snapshot.quantity,
        unitAmountPaise: snapshot.unitAmountPaise,
        amountPaise: snapshot.amountPaise,
        applicableDays: snapshot.applicableDays,
        billedDays: snapshot.billedDays,
        prorationPolicy: snapshot.prorationPolicy,
      });
    }

    const totalAmountPaise = billComputedTotalPaise({
      baseAmountPaise,
      additionalServicesTotalPaise,
      adjustmentsPaise: 0,
    });

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
              ownerUserId: owner?._id,
              ownerNameSnapshot: owner?.name ?? UNASSIGNED_OWNER_NAME,
              ownerEmailSnapshot: owner?.email || 'unassigned',
              flatNumberSnapshot: flat.number,
              wingCodeSnapshot: wing?.code ?? '',
              flatTypeSnapshot: flat.flatType,
              occupancyStatusSnapshot: flat.occupancyStatus,
              floorSnapshot: flat.floor,
              flatIsActiveSnapshot: flat.isActive,
              monthlyRatePaise,
              baseAmountPaise,
              additionalServicesTotalPaise,
              adjustmentsPaise: 0,
              lineItems,
              totalAmountPaise,
              amountPaidPaise: 0,
              outstandingPrincipalPaise: totalAmountPaise,
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
            deltaPrincipalPaise: totalAmountPaise,
            principalAfterPaise: totalAmountPaise,
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
              ownerUserId: owner ? String(owner._id) : null,
              numberOfMonths: input.numberOfMonths,
              baseAmountPaise,
              additionalServicesTotalPaise,
              totalAmountPaise,
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
      if (bill.ownerUserId) {
        const month = new Intl.DateTimeFormat('en-IN', {
          month: 'long',
          year: 'numeric',
          timeZone: 'Asia/Kolkata',
        }).format(bill.billingPeriodStart);
        const flatLabel = formatFlatLabel(serialized.wingCodeSnapshot, serialized.flatNumberSnapshot);
        await notifyBusinessEvent({
          societyId,
          recipientUserId: String(bill.ownerUserId),
          type: 'BILL_GENERATED',
          title: 'Monthly Maintenance Bill Generated',
          body: `Your maintenance bill for ${month} has been generated.`,
          relatedEntityType: 'Bill',
          relatedEntityId: String(bill._id),
          idempotencyKey: `BILL_GENERATED:${String(bill._id)}`,
          metadata: {
            flatLabel,
            billingMonth: month,
            originalAmountPaise: bill.totalAmountPaise,
            outstandingAmountPaise: bill.outstandingPrincipalPaise,
            dueDate: bill.dueDate.toISOString(),
            deepLink: `apnasociety://bill/${String(bill._id)}`,
          },
        });
      }
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
  const totalMaintenancePaise = created.reduce((sum, b) => sum + b.baseAmountPaise, 0);
  const totalAdditionalPaise = created.reduce(
    (sum, b) => sum + b.additionalServicesTotalPaise,
    0,
  );

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
    vacantOrUnassignedCount,
    totalBilledPaise,
    totalMaintenancePaise,
    totalAdditionalServicesPaise: totalAdditionalPaise,
    created,
    skipped,
    conflicts,
  };
}

/**
 * When an owner is assigned to a previously unassigned/vacant flat, attach
 * existing bills (and related payments/receipts) without recreating amounts.
 */
export async function attachUnassignedBillsToOwner(
  societyId: string,
  flatId: string,
  owner: { _id: { toString(): string }; name: string; email: string },
  actor: Actor,
  session: ClientSession,
): Promise<{ attachedBillCount: number }> {
  const bills = await BillModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    flatId: parseObjectId(flatId, 'flatId'),
    $or: [{ ownerUserId: { $exists: false } }, { ownerUserId: null }],
    status: { $ne: 'CANCELLED' },
  }).session(session);

  if (bills.length === 0) return { attachedBillCount: 0 };

  const billIds = bills.map((bill) => bill._id);
  await BillModel.updateMany(
    { _id: { $in: billIds } },
    {
      $set: {
        ownerUserId: owner._id,
        ownerNameSnapshot: owner.name,
        ownerEmailSnapshot: owner.email,
      },
    },
    { session },
  );
  await PaymentModel.updateMany(
    {
      billId: { $in: billIds },
      $or: [{ ownerUserId: { $exists: false } }, { ownerUserId: null }],
    },
    { $set: { ownerUserId: owner._id } },
    { session },
  );
  await ReceiptModel.updateMany(
    {
      billId: { $in: billIds },
      $or: [{ ownerUserId: { $exists: false } }, { ownerUserId: null }],
    },
    {
      $set: {
        ownerUserId: owner._id,
        ownerNameSnapshot: owner.name,
        ownerEmailSnapshot: owner.email,
      },
    },
    { session },
  );

  await writeAuditLog(
    {
      action: 'BILL_OWNER_ATTACHED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'Flat',
      targetId: flatId,
      metadata: {
        ownerUserId: String(owner._id),
        attachedBillCount: bills.length,
        billIds: bills.map((bill) => String(bill._id)),
      },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    },
    session,
  );

  return { attachedBillCount: bills.length };
}

export async function getBill(societyId: string, billId: string) {
  await getBillInterest(societyId, billId);
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
    occupancyStatus?: string;
    floor?: number;
    ownerAssigned?: boolean;
    page?: number;
    limit?: number;
  },
) {
  await ensureSocietyInterestCurrent(societyId);
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
  if (query.occupancyStatus) filter.occupancyStatusSnapshot = query.occupancyStatus;
  if (query.floor !== undefined) filter.floorSnapshot = query.floor;
  if (query.ownerAssigned === true) {
    filter.ownerUserId = { $exists: true, $ne: null };
  } else if (query.ownerAssigned === false) {
    filter.$or = [{ ownerUserId: { $exists: false } }, { ownerUserId: null }];
  }

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
 * the original base amount, additional-service snapshots, or monthly rate.
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

  const newTotal = billComputedTotalPaise({
    baseAmountPaise: bill.baseAmountPaise,
    additionalServicesTotalPaise: bill.additionalServicesTotalPaise,
    adjustmentsPaise: input.adjustmentsPaise,
  });
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
          additionalServicesTotalPaise: bill.additionalServicesTotalPaise,
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
