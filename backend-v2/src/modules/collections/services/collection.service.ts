import type { FilterQuery } from 'mongoose';
import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { formatFlatLabel } from '../../../utils/flat-label';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { nextSequence } from '../../billing/models/sequence.model';
import { CollectionAdjustmentModel } from '../models/collection-adjustment.model';
import {
  CollectionChargeModel,
  type CollectionChargeDocument,
  type CollectionChargeStatus,
} from '../models/collection-charge.model';
import { CollectionModel, type CollectionDocument } from '../models/collection.model';
import type {
  AddCollectionFlatsInput,
  AdjustChargeInput,
  CancelCollectionInput,
  CreateCollectionInput,
  ListChargesQuery,
  ListCollectionsQuery,
  UpdateCollectionInput,
} from '../validators/collection.validators';
import { resolveCollectionAssignments } from './assignment.service';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function deriveChargeStatus(outstandingPaise: number, amountPaidPaise: number): CollectionChargeStatus {
  if (outstandingPaise <= 0) return 'PAID';
  if (amountPaidPaise > 0) return 'PARTIALLY_PAID';
  return 'PENDING';
}

function collectionPercentage(collected: number, expected: number): number {
  if (expected <= 0) return 0;
  return Math.floor((collected * 10_000) / expected) / 100;
}

function serializeCollection(doc: CollectionDocument | Record<string, unknown>) {
  const row = doc as CollectionDocument;
  const expected = row.expectedTotalPaise;
  const collected = row.collectedPaise;
  return {
    id: String(row._id),
    collectionNumber: row.collectionNumber,
    title: row.title,
    description: row.description,
    amountMode: row.amountMode,
    assignmentType: row.assignmentType,
    amountPaise: row.amountPaise,
    allowPartialPayment: row.allowPartialPayment,
    dueDate: row.dueDate.toISOString(),
    startDate: row.startDate?.toISOString(),
    paymentInstructions: row.paymentInstructions,
    status: row.status,
    expectedTotalPaise: expected,
    collectedPaise: collected,
    outstandingPaise: Math.max(0, expected - collected),
    assignedFlatCount: row.assignedFlatCount,
    collectionPercentage: collectionPercentage(collected, expected),
    closedAt: row.closedAt?.toISOString(),
    cancelledAt: row.cancelledAt?.toISOString(),
    cancellationReason: row.cancellationReason,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

function serializeCharge(row: CollectionChargeDocument, now = new Date()) {
  const overdue =
    row.status !== 'PAID' &&
    row.status !== 'CANCELLED' &&
    row.dueDate.getTime() < now.getTime();
  return {
    id: String(row._id),
    collectionId: String(row.collectionId),
    flatId: String(row.flatId),
    ownerUserId: row.ownerUserId ? String(row.ownerUserId) : undefined,
    amountPaise: row.amountPaise,
    adjustmentsPaise: row.adjustmentsPaise,
    assignedAmountPaise: row.amountPaise + row.adjustmentsPaise,
    amountPaidPaise: row.amountPaidPaise,
    outstandingPaise: row.outstandingPaise,
    status: overdue && row.status !== 'PARTIALLY_PAID' ? 'OVERDUE' : row.status,
    paymentStatus: row.status,
    overdue,
    dueDate: row.dueDate.toISOString(),
    wingCodeSnapshot: row.wingCodeSnapshot,
    flatNumberSnapshot: row.flatNumberSnapshot,
    flatLabel: formatFlatLabel(row.wingCodeSnapshot, row.flatNumberSnapshot),
    occupancyStatusSnapshot: row.occupancyStatusSnapshot,
    ownerNameSnapshot: row.ownerNameSnapshot,
  };
}

async function nextCollectionNumber(
  societyId: string,
  session?: import('mongoose').ClientSession,
): Promise<string> {
  const year = new Date().getUTCFullYear();
  const seq = await nextSequence(societyId, `col-${year}`, session);
  return `COL-${year}-${seq.toString().padStart(6, '0')}`;
}

export async function previewCollection(societyId: string, input: CreateCollectionInput) {
  return resolveCollectionAssignments(societyId, input);
}

export async function createCollection(
  societyId: string,
  input: CreateCollectionInput,
  actor: Actor,
) {
  const preview = await resolveCollectionAssignments(societyId, input);
  const created = await withTransaction(async (session) => {
    const collectionNumber = await nextCollectionNumber(societyId, session);
    const [collection] = await CollectionModel.create(
      [
        {
          societyId,
          collectionNumber,
          title: input.title,
          description: input.description,
          amountMode: input.amountMode,
          assignmentType: input.assignmentType,
          amountPaise: input.amountPaise ?? 0,
          allowPartialPayment: input.allowPartialPayment ?? false,
          dueDate: input.dueDate,
          startDate: input.startDate,
          paymentInstructions: input.paymentInstructions,
          status: 'ACTIVE',
          expectedTotalPaise: preview.expectedTotalPaise,
          collectedPaise: 0,
          assignedFlatCount: preview.assignedFlatCount,
          createdBy: actor.userId,
        },
      ],
      { session },
    );

    await CollectionChargeModel.insertMany(
      preview.allocations.map((row) => ({
        societyId,
        collectionId: collection._id,
        flatId: row.flatId,
        ownerUserId: row.ownerUserId,
        amountPaise: row.amountPaise,
        adjustmentsPaise: 0,
        amountPaidPaise: 0,
        outstandingPaise: row.amountPaise,
        status: 'PENDING' as const,
        dueDate: input.dueDate,
        wingCodeSnapshot: row.wingCode,
        flatNumberSnapshot: row.flatNumber,
        occupancyStatusSnapshot: row.occupancyStatus,
        ownerNameSnapshot: row.ownerName,
      })),
      { session, ordered: true },
    );

    await writeAuditLog(
      {
        action: 'COLLECTION_CREATED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'SpecialCollection',
        targetId: String(collection._id),
        metadata: {
          collectionNumber,
          assignedFlatCount: preview.assignedFlatCount,
          expectedTotalPaise: preview.expectedTotalPaise,
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return collection;
  });

  return serializeCollection(created);
}

export async function listCollections(societyId: string, query: ListCollectionsQuery) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: FilterQuery<CollectionDocument> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.status) filter.status = query.status;
  if (query.search) {
    filter.$or = [
      { title: { $regex: query.search, $options: 'i' } },
      { collectionNumber: { $regex: query.search, $options: 'i' } },
    ];
  }
  const [total, rows] = await Promise.all([
    CollectionModel.countDocuments(filter),
    CollectionModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
  ]);
  return {
    items: rows.map((row) => serializeCollection(row)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getCollection(societyId: string, collectionId: string) {
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!collection) throw notFound('Collection not found');
  const summary = await getCollectionDashboard(societyId, collectionId);
  return { ...serializeCollection(collection), dashboard: summary };
}

export async function updateCollection(
  societyId: string,
  collectionId: string,
  input: UpdateCollectionInput,
  actor: Actor,
) {
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!collection) throw notFound('Collection not found');
  if (collection.status !== 'ACTIVE') {
    throw badRequest('Only active collections can be edited', 'COLLECTION_NOT_EDITABLE');
  }
  if (input.title !== undefined) collection.title = input.title;
  if (input.description !== undefined) collection.description = input.description;
  if (input.dueDate !== undefined) collection.dueDate = input.dueDate;
  if (input.startDate !== undefined) collection.startDate = input.startDate ?? undefined;
  if (input.paymentInstructions !== undefined) {
    collection.paymentInstructions = input.paymentInstructions ?? undefined;
  }
  if (input.allowPartialPayment !== undefined) {
    collection.allowPartialPayment = input.allowPartialPayment;
  }
  collection.updatedBy = parseObjectId(actor.userId, 'userId');
  await collection.save();

  if (input.dueDate) {
    await CollectionChargeModel.updateMany(
      { collectionId: collection._id, status: { $in: ['PENDING', 'PARTIALLY_PAID'] } },
      { $set: { dueDate: input.dueDate } },
    );
  }

  await writeAuditLog({
    action: 'COLLECTION_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'SpecialCollection',
    targetId: String(collection._id),
    metadata: { ...input, dueDate: input.dueDate?.toISOString() },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });
  return serializeCollection(collection);
}

async function resolveNewCollectionAllocations(
  societyId: string,
  collection: CollectionDocument,
  input: AddCollectionFlatsInput,
) {
  const existing = await CollectionChargeModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    collectionId: collection._id,
  })
    .select('flatId')
    .lean();
  const assigned = new Set(existing.map((row) => String(row.flatId)));

  const customAmounts = input.flatAmounts ?? [];
  const amountPaise =
    input.amountPaise ??
    (collection.amountMode === 'PER_FLAT' && collection.amountPaise > 0
      ? collection.amountPaise
      : undefined);
  const amountMode = customAmounts.length ? 'CUSTOM' : 'PER_FLAT';
  if (amountMode !== 'CUSTOM' && !(amountPaise && amountPaise > 0)) {
    throw badRequest(
      'Enter an amount for the flats you are adding',
      'MISSING_FLAT_AMOUNT',
    );
  }

  let assignmentType: CreateCollectionInput['assignmentType'] = 'SELECTED_FLATS';
  let flatIds = [
    ...new Set([...(input.flatIds ?? []), ...customAmounts.map((row) => row.flatId)]),
  ];
  if (input.includeRemaining) {
    assignmentType = 'ALL_FLATS';
    flatIds = [];
  } else if (input.wingIds?.length && flatIds.length === 0) {
    assignmentType = 'WINGS';
  } else if (input.wingIds?.length && flatIds.length > 0) {
    const wingPreview = await resolveCollectionAssignments(societyId, {
      title: collection.title,
      description: collection.description,
      amountMode: 'PER_FLAT',
      assignmentType: 'WINGS',
      amountPaise: amountPaise ?? 1,
      wingIds: input.wingIds,
      dueDate: collection.dueDate,
      allowPartialPayment: false,
    });
    flatIds = [...new Set([...flatIds, ...wingPreview.allocations.map((row) => row.flatId)])];
  }

  const preview = await resolveCollectionAssignments(societyId, {
    title: collection.title,
    description: collection.description,
    amountMode,
    assignmentType,
    amountPaise: amountMode === 'CUSTOM' ? undefined : amountPaise,
    wingIds: assignmentType === 'WINGS' ? input.wingIds : undefined,
    flatIds: assignmentType === 'SELECTED_FLATS' ? flatIds : undefined,
    flatAmounts: amountMode === 'CUSTOM' ? customAmounts : undefined,
    dueDate: collection.dueDate,
    allowPartialPayment: false,
  });

  const allocations = preview.allocations.filter((row) => !assigned.has(row.flatId));
  if (allocations.length === 0) {
    throw conflict(
      'Those flats are already assigned to this collection',
      'DUPLICATE_FLAT_ASSIGNMENT',
    );
  }

  const typicalAmount = allocations[0]?.amountPaise ?? 0;
  const uniform = allocations.every((row) => row.amountPaise === typicalAmount);
  return {
    assignedFlatCount: allocations.length,
    amountMode,
    assignmentType: assignmentType === 'ALL_FLATS' ? 'ALL_FLATS' : 'SELECTED_FLATS',
    defaultAmountPaise: uniform ? typicalAmount : 0,
    expectedTotalPaise: allocations.reduce((sum, row) => sum + row.amountPaise, 0),
    allocations,
    skippedAssignedCount: preview.allocations.length - allocations.length,
  };
}

export async function previewAddCollectionFlats(
  societyId: string,
  collectionId: string,
  input: AddCollectionFlatsInput,
) {
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!collection) throw notFound('Collection not found');
  if (collection.status !== 'ACTIVE') {
    throw badRequest('Only active collections can be edited', 'COLLECTION_NOT_EDITABLE');
  }
  return resolveNewCollectionAllocations(societyId, collection, input);
}

export async function addCollectionFlats(
  societyId: string,
  collectionId: string,
  input: AddCollectionFlatsInput,
  actor: Actor,
) {
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!collection) throw notFound('Collection not found');
  if (collection.status !== 'ACTIVE') {
    throw badRequest('Only active collections can be edited', 'COLLECTION_NOT_EDITABLE');
  }
  const preview = await resolveNewCollectionAllocations(societyId, collection, input);

  await withTransaction(async (session) => {
    await CollectionChargeModel.insertMany(
      preview.allocations.map((row) => ({
        societyId,
        collectionId: collection._id,
        flatId: row.flatId,
        ownerUserId: row.ownerUserId,
        amountPaise: row.amountPaise,
        adjustmentsPaise: 0,
        amountPaidPaise: 0,
        outstandingPaise: row.amountPaise,
        status: 'PENDING' as const,
        dueDate: collection.dueDate,
        wingCodeSnapshot: row.wingCode,
        flatNumberSnapshot: row.flatNumber,
        occupancyStatusSnapshot: row.occupancyStatus,
        ownerNameSnapshot: row.ownerName,
      })),
      { session, ordered: true },
    );

    collection.expectedTotalPaise += preview.expectedTotalPaise;
    collection.assignedFlatCount += preview.assignedFlatCount;
    collection.updatedBy = parseObjectId(actor.userId, 'userId');
    await collection.save({ session });

    await writeAuditLog(
      {
        action: 'COLLECTION_FLATS_ADDED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'SpecialCollection',
        targetId: String(collection._id),
        metadata: {
          addedFlatCount: preview.assignedFlatCount,
          addedTotalPaise: preview.expectedTotalPaise,
          flatIds: preview.allocations.map((row) => row.flatId),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
  });

  return serializeCollection(collection);
}

export async function closeCollection(societyId: string, collectionId: string, actor: Actor) {
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!collection) throw notFound('Collection not found');
  if (collection.status !== 'ACTIVE') {
    throw badRequest('Only active collections can be closed', 'COLLECTION_NOT_ACTIVE');
  }
  collection.status = 'CLOSED';
  collection.closedAt = new Date();
  collection.updatedBy = parseObjectId(actor.userId, 'userId');
  await collection.save();
  await writeAuditLog({
    action: 'COLLECTION_CLOSED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'SpecialCollection',
    targetId: String(collection._id),
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });
  return serializeCollection(collection);
}

export async function cancelCollection(
  societyId: string,
  collectionId: string,
  input: CancelCollectionInput,
  actor: Actor,
) {
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!collection) throw notFound('Collection not found');
  if (collection.status === 'CANCELLED') {
    throw conflict('Collection is already cancelled', 'COLLECTION_ALREADY_CANCELLED');
  }
  collection.status = 'CANCELLED';
  collection.cancelledAt = new Date();
  collection.cancellationReason = input.reason;
  collection.updatedBy = parseObjectId(actor.userId, 'userId');
  await collection.save();
  await CollectionChargeModel.updateMany(
    { collectionId: collection._id, status: { $in: ['PENDING', 'PARTIALLY_PAID'] } },
    { $set: { status: 'CANCELLED' } },
  );
  await writeAuditLog({
    action: 'COLLECTION_CANCELLED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'SpecialCollection',
    targetId: String(collection._id),
    metadata: { reason: input.reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });
  return serializeCollection(collection);
}

export async function getCollectionDashboard(societyId: string, collectionId: string) {
  const collectionObjectId = parseObjectId(collectionId, 'collectionId');
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const now = new Date();
  const [collection, counts] = await Promise.all([
    CollectionModel.findOne({ _id: collectionObjectId, societyId: societyObjectId }).lean(),
    CollectionChargeModel.aggregate<{
      assignedFlatCount: number;
      expectedTotalPaise: number;
      collectedPaise: number;
      outstandingPaise: number;
      paidFlats: number;
      partiallyPaidFlats: number;
      pendingFlats: number;
      overdueFlats: number;
    }>([
      { $match: { societyId: societyObjectId, collectionId: collectionObjectId } },
      {
        $group: {
          _id: null,
          assignedFlatCount: { $sum: 1 },
          expectedTotalPaise: { $sum: { $add: ['$amountPaise', '$adjustmentsPaise'] } },
          collectedPaise: { $sum: '$amountPaidPaise' },
          outstandingPaise: {
            $sum: {
              $cond: [{ $eq: ['$status', 'CANCELLED'] }, 0, '$outstandingPaise'],
            },
          },
          paidFlats: { $sum: { $cond: [{ $eq: ['$status', 'PAID'] }, 1, 0] } },
          partiallyPaidFlats: { $sum: { $cond: [{ $eq: ['$status', 'PARTIALLY_PAID'] }, 1, 0] } },
          pendingFlats: { $sum: { $cond: [{ $eq: ['$status', 'PENDING'] }, 1, 0] } },
          overdueFlats: {
            $sum: {
              $cond: [
                {
                  $and: [
                    { $not: { $in: ['$status', ['PAID', 'CANCELLED']] } },
                    { $lt: ['$dueDate', now] },
                  ],
                },
                1,
                0,
              ],
            },
          },
        },
      },
    ]),
  ]);
  if (!collection) throw notFound('Collection not found');
  const totals = counts[0] ?? {
    assignedFlatCount: 0,
    expectedTotalPaise: 0,
    collectedPaise: 0,
    outstandingPaise: 0,
    paidFlats: 0,
    partiallyPaidFlats: 0,
    pendingFlats: 0,
    overdueFlats: 0,
  };
  return {
    ...totals,
    collectionPercentage: collectionPercentage(totals.collectedPaise, totals.expectedTotalPaise),
  };
}

export async function listCollectionCharges(
  societyId: string,
  collectionId: string,
  query: ListChargesQuery,
) {
  const exists = await CollectionModel.exists({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!exists) throw notFound('Collection not found');
  const page = query.page ?? 1;
  const limit = query.limit ?? 50;
  const filter: FilterQuery<CollectionChargeDocument> = {
    societyId: parseObjectId(societyId, 'societyId'),
    collectionId: parseObjectId(collectionId, 'collectionId'),
  };
  if (query.wingCode) filter.wingCodeSnapshot = query.wingCode.toUpperCase();
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.search) {
    filter.$or = [
      { flatNumberSnapshot: { $regex: query.search, $options: 'i' } },
      { ownerNameSnapshot: { $regex: query.search, $options: 'i' } },
      { wingCodeSnapshot: { $regex: query.search, $options: 'i' } },
    ];
  }
  const now = new Date();
  if (query.status === 'OVERDUE') {
    filter.status = { $nin: ['PAID', 'CANCELLED'] };
    filter.dueDate = { $lt: now };
  } else if (query.status) {
    filter.status = query.status;
  }

  const [total, rows] = await Promise.all([
    CollectionChargeModel.countDocuments(filter),
    CollectionChargeModel.find(filter)
      .sort({ wingCodeSnapshot: 1, flatNumberSnapshot: 1 })
      .skip((page - 1) * limit)
      .limit(limit),
  ]);
  return {
    items: rows.map((row) => serializeCharge(row, now)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function adjustCollectionCharge(
  societyId: string,
  chargeId: string,
  input: AdjustChargeInput,
  actor: Actor,
) {
  const charge = await CollectionChargeModel.findOne({
    _id: parseObjectId(chargeId, 'chargeId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!charge) throw notFound('Collection charge not found');
  const collection = await CollectionModel.findById(charge.collectionId);
  if (!collection) throw notFound('Collection not found');
  if (collection.status !== 'ACTIVE') {
    throw badRequest('Only active collections can be adjusted', 'COLLECTION_NOT_ACTIVE');
  }
  if (charge.status === 'CANCELLED') {
    throw badRequest('Cancelled charges cannot be adjusted', 'CHARGE_CANCELLED');
  }

  const assignedBefore = charge.amountPaise + charge.adjustmentsPaise;
  const assignedAfter = assignedBefore + input.deltaPaise;
  if (assignedAfter < charge.amountPaidPaise) {
    throw badRequest(
      'Adjustment would drop the assigned amount below the amount already paid',
      'ADJUSTMENT_BELOW_PAID',
    );
  }
  if (assignedAfter <= 0) {
    throw badRequest('Assigned amount must stay positive', 'INVALID_ADJUSTMENT');
  }

  charge.adjustmentsPaise += input.deltaPaise;
  charge.outstandingPaise = Math.max(0, assignedAfter - charge.amountPaidPaise);
  charge.status = deriveChargeStatus(charge.outstandingPaise, charge.amountPaidPaise);
  await charge.save();

  collection.expectedTotalPaise = Math.max(0, collection.expectedTotalPaise + input.deltaPaise);
  await collection.save();

  await CollectionAdjustmentModel.create({
    societyId,
    collectionId: charge.collectionId,
    chargeId: charge._id,
    deltaPaise: input.deltaPaise,
    reason: input.reason,
    amountBeforePaise: assignedBefore,
    amountAfterPaise: assignedAfter,
    createdBy: actor.userId,
  });

  await writeAuditLog({
    action: 'COLLECTION_ADJUSTED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'SpecialCollectionCharge',
    targetId: String(charge._id),
    metadata: {
      deltaPaise: input.deltaPaise,
      reason: input.reason,
      amountBeforePaise: assignedBefore,
      amountAfterPaise: assignedAfter,
    },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeCharge(charge);
}

export async function listChargeAdjustments(societyId: string, chargeId: string) {
  const rows = await CollectionAdjustmentModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    chargeId: parseObjectId(chargeId, 'chargeId'),
  })
    .sort({ createdAt: -1 })
    .lean();
  return {
    items: rows.map((row) => ({
      id: String(row._id),
      deltaPaise: row.deltaPaise,
      reason: row.reason,
      amountBeforePaise: row.amountBeforePaise,
      amountAfterPaise: row.amountAfterPaise,
      createdAt: row.createdAt.toISOString(),
    })),
  };
}

export { serializeCharge, serializeCollection, deriveChargeStatus };

export async function listResidentCollectionCharges(societyId: string, ownerUserId: string) {
  const rows = await CollectionChargeModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    ownerUserId: parseObjectId(ownerUserId, 'ownerUserId'),
    status: { $ne: 'CANCELLED' },
  })
    .sort({ dueDate: 1, createdAt: -1 })
    .limit(200);
  const collectionIds = [...new Set(rows.map((row) => String(row.collectionId)))];
  const collections = await CollectionModel.find({
    _id: { $in: collectionIds },
  })
    .select('_id title collectionNumber status allowPartialPayment paymentInstructions description')
    .lean();
  const byId = new Map(collections.map((row) => [String(row._id), row]));
  return {
    items: rows.map((row) => {
      const collection = byId.get(String(row.collectionId));
      return {
        ...serializeCharge(row),
        collectionTitle: collection?.title,
        collectionNumber: collection?.collectionNumber,
        collectionStatus: collection?.status,
        collectionDescription: collection?.description,
        allowPartialPayment: collection?.allowPartialPayment ?? false,
        paymentInstructions: collection?.paymentInstructions,
      };
    }),
  };
}

export async function getResidentCollectionCharge(
  societyId: string,
  chargeId: string,
  ownerUserId: string,
) {
  const charge = await CollectionChargeModel.findOne({
    _id: parseObjectId(chargeId, 'chargeId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!charge) throw notFound('Collection charge not found');
  if (!charge.ownerUserId || String(charge.ownerUserId) !== ownerUserId) {
    throw forbidden('Only the flat owner may access this collection', 'NOT_CHARGE_OWNER');
  }
  const collection = await CollectionModel.findById(charge.collectionId);
  if (!collection) throw notFound('Collection not found');
  return {
    ...serializeCharge(charge),
    collection: serializeCollection(collection),
  };
}

export async function exportCollectionChargesCsv(societyId: string, collectionId: string) {
  const { csvRow, formatPaiseAsRupees, formatIsoDate } = await import(
    '../../reports/utils/csv'
  );
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!collection) throw notFound('Collection not found');
  const rows = await CollectionChargeModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    collectionId: collection._id,
  })
    .sort({ wingCodeSnapshot: 1, flatNumberSnapshot: 1 })
    .lean();
  let body = csvRow([
    'Wing',
    'Flat',
    'Owner',
    'Occupancy',
    'Assigned (INR)',
    'Paid (INR)',
    'Outstanding (INR)',
    'Status',
    'Due date',
  ]);
  for (const row of rows) {
    body += csvRow([
      row.wingCodeSnapshot,
      formatFlatLabel(row.wingCodeSnapshot, row.flatNumberSnapshot),
      row.ownerNameSnapshot,
      row.occupancyStatusSnapshot,
      formatPaiseAsRupees(row.amountPaise + row.adjustmentsPaise),
      formatPaiseAsRupees(row.amountPaidPaise),
      formatPaiseAsRupees(row.outstandingPaise),
      row.status,
      formatIsoDate(row.dueDate),
    ]);
  }
  return {
    filename: `${collection.collectionNumber}-charges.csv`,
    csv: body,
  };
}

export async function requireActiveCollection(societyId: string, collectionId: string) {
  const collection = await CollectionModel.findOne({
    _id: parseObjectId(collectionId, 'collectionId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!collection) throw notFound('Collection not found');
  if (collection.status !== 'ACTIVE') {
    throw forbidden('Collection is not open for payment', 'COLLECTION_NOT_ACTIVE');
  }
  return collection;
}
