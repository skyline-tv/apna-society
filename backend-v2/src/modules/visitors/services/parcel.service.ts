import type { ClientSession } from 'mongoose';
import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { formatFlatLabel } from '../../../utils/flat-label';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { getFlatAccess } from '../../users/services/access-control.service';
import { ParcelHandoverModel, type ParcelStatus } from '../models/parcel-handover.model';
import { emitVisitorEvent, visitorEventPayloadFromDoc } from './visitor-events.service';
import type { VisitorLogDocument } from '../models/visitor-log.model';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

export function serializeParcel(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  visitorLogId?: { toString(): string };
  recipientUserId: { toString(): string };
  courierName: string;
  courierPhone?: string;
  visitorType?: string;
  purpose?: string;
  requestedByGuardId: { toString(): string };
  authorizedByUserId: { toString(): string };
  receivedByGuardId?: { toString(): string };
  status: string;
  requestedAt: Date;
  authorizedAt: Date;
  receivedAt?: Date;
  deliveredAt?: Date;
  collectedAt?: Date;
  cancelledAt?: Date;
  cancellationReason?: string;
  notes?: string;
  flatNumberSnapshot: string;
  wingCodeSnapshot: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    visitorLogId: doc.visitorLogId ? String(doc.visitorLogId) : undefined,
    recipientUserId: String(doc.recipientUserId),
    courierName: doc.courierName,
    courierPhone: doc.courierPhone,
    visitorType: doc.visitorType,
    purpose: doc.purpose,
    requestedByGuardId: String(doc.requestedByGuardId),
    authorizedByUserId: String(doc.authorizedByUserId),
    receivedByGuardId: doc.receivedByGuardId ? String(doc.receivedByGuardId) : undefined,
    status: doc.status,
    requestedAt: new Date(doc.requestedAt).toISOString(),
    authorizedAt: new Date(doc.authorizedAt).toISOString(),
    receivedAt: doc.receivedAt?.toISOString(),
    deliveredAt: doc.deliveredAt?.toISOString(),
    collectedAt: doc.collectedAt?.toISOString(),
    cancelledAt: doc.cancelledAt?.toISOString(),
    cancellationReason: doc.cancellationReason,
    notes: doc.notes,
    flatNumberSnapshot: doc.flatNumberSnapshot,
    wingCodeSnapshot: doc.wingCodeSnapshot,
    flatLabel: formatFlatLabel(doc.wingCodeSnapshot, doc.flatNumberSnapshot),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export async function createParcelFromVisitor(
  visitor: VisitorLogDocument,
  actor: Actor,
  session?: ClientSession,
) {
  const now = new Date();
  const [parcel] = await ParcelHandoverModel.create([
    {
      societyId: visitor.societyId,
      flatId: visitor.flatId,
      wingId: visitor.wingId,
      visitorLogId: visitor._id,
      recipientUserId: visitor.assignedResidentUserId,
      courierName: visitor.visitorName,
      courierPhone: visitor.visitorPhone || undefined,
      visitorType: visitor.visitorType,
      purpose: visitor.purpose,
      requestedByGuardId: visitor.requestedByGuardId,
      authorizedByUserId: actor.userId,
      status: 'AWAITING_HANDOVER',
      requestedAt: visitor.createdAt,
      authorizedAt: now,
      notes: visitor.notes,
      flatNumberSnapshot: visitor.flatNumberSnapshot,
      wingCodeSnapshot: visitor.wingCodeSnapshot,
    },
  ],
    session ? { session } : undefined,
  );
  return parcel;
}

async function loadParcelForActor(
  societyId: string,
  parcelId: string,
  actorUserId: string,
  role: 'guard' | 'resident' | 'admin',
) {
  const parcel = await ParcelHandoverModel.findOne({
    _id: parseObjectId(parcelId, 'parcelId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!parcel) throw notFound('Parcel record not found');

  if (role === 'resident') {
    const access = await getFlatAccess({
      userId: actorUserId,
      societyId,
      flatId: String(parcel.flatId),
    });
    const isRecipient = String(parcel.recipientUserId) === actorUserId;
    if (!isRecipient && !access.residential) {
      throw forbidden('Parcel access denied', 'PARCEL_ACCESS_DENIED');
    }
  }
  return parcel;
}

export async function recordParcelReceived(
  societyId: string,
  parcelId: string,
  guardUserId: string,
  actor: Actor,
) {
  const parcel = await loadParcelForActor(societyId, parcelId, guardUserId, 'guard');
  if (parcel.status === 'RECEIVED_BY_GUARD') {
    return serializeParcel(parcel);
  }
  if (parcel.status !== 'AWAITING_HANDOVER') {
    throw conflict(`Cannot receive parcel in status ${parcel.status}`, 'INVALID_PARCEL_STATUS');
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await ParcelHandoverModel.findOneAndUpdate(
      { _id: parcel._id, status: 'AWAITING_HANDOVER' },
      {
        $set: {
          status: 'RECEIVED_BY_GUARD',
          receivedAt: new Date(),
          receivedByGuardId: guardUserId,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Parcel was already processed', 'ALREADY_PROCESSED');
    }
    await writeAuditLog(
      {
        action: 'PARCEL_RECEIVED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'ParcelHandover',
        targetId: parcelId,
        metadata: { flatId: String(claimed.flatId) },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    return claimed;
  });

  emitVisitorEvent(
    'parcel:received',
    visitorEventPayloadFromDoc({
      _id: updated.visitorLogId ?? updated._id,
      societyId: updated.societyId,
      flatId: updated.flatId,
      flatNumberSnapshot: updated.flatNumberSnapshot,
      wingCodeSnapshot: updated.wingCodeSnapshot,
      visitorName: updated.courierName,
      visitorType: updated.visitorType ?? 'DELIVERY',
      approvalStatus: 'CANCELLED',
      entryStatus: 'NOT_ENTERED',
      assignedResidentUserId: updated.recipientUserId,
      parcelId: String(updated._id),
    }),
  );

  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(updated.recipientUserId),
    type: 'PARCEL_RECEIVED',
    title: 'Parcel received at the gate',
    body: `A parcel for ${formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot)} has been received by security.`,
    relatedEntityType: 'ParcelHandover',
    relatedEntityId: String(updated._id),
    idempotencyKey: `PARCEL_RECEIVED:${String(updated._id)}`,
    metadata: {
      flatLabel: formatFlatLabel(updated.wingCodeSnapshot, updated.flatNumberSnapshot),
      visitorName: updated.courierName,
      visitorPhone: updated.courierPhone ?? '',
      parcelStatus: updated.status,
      parcelId: String(updated._id),
      deepLink: `apnasociety://parcel/${String(updated._id)}`,
    },
  });

  return serializeParcel(updated);
}

export async function markParcelDelivered(
  societyId: string,
  parcelId: string,
  guardUserId: string,
  actor: Actor,
) {
  const parcel = await loadParcelForActor(societyId, parcelId, guardUserId, 'guard');
  if (parcel.status === 'DELIVERED_TO_RESIDENT') return serializeParcel(parcel);
  if (parcel.status !== 'RECEIVED_BY_GUARD') {
    throw conflict(`Cannot deliver parcel in status ${parcel.status}`, 'INVALID_PARCEL_STATUS');
  }
  const claimed = await ParcelHandoverModel.findOneAndUpdate(
    { _id: parcel._id, status: 'RECEIVED_BY_GUARD' },
    { $set: { status: 'DELIVERED_TO_RESIDENT', deliveredAt: new Date() } },
    { new: true },
  );
  if (!claimed) throw conflict('Parcel was already processed', 'ALREADY_PROCESSED');
  await writeAuditLog({
    action: 'PARCEL_DELIVERED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'ParcelHandover',
    targetId: parcelId,
  });
  return serializeParcel(claimed);
}

export async function markParcelCollected(
  societyId: string,
  parcelId: string,
  residentUserId: string,
  actor: Actor,
) {
  const parcel = await loadParcelForActor(societyId, parcelId, residentUserId, 'resident');
  if (parcel.status === 'COLLECTED_BY_RESIDENT') return serializeParcel(parcel);
  if (!['RECEIVED_BY_GUARD', 'DELIVERED_TO_RESIDENT'].includes(parcel.status)) {
    throw conflict(`Cannot collect parcel in status ${parcel.status}`, 'INVALID_PARCEL_STATUS');
  }
  const claimed = await ParcelHandoverModel.findOneAndUpdate(
    {
      _id: parcel._id,
      status: { $in: ['RECEIVED_BY_GUARD', 'DELIVERED_TO_RESIDENT'] },
    },
    { $set: { status: 'COLLECTED_BY_RESIDENT', collectedAt: new Date() } },
    { new: true },
  );
  if (!claimed) throw conflict('Parcel was already processed', 'ALREADY_PROCESSED');
  await writeAuditLog({
    action: 'PARCEL_COLLECTED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'ParcelHandover',
    targetId: parcelId,
  });
  return serializeParcel(claimed);
}

export async function cancelParcel(
  societyId: string,
  parcelId: string,
  actorUserId: string,
  reason: string | undefined,
  actor: Actor,
  role: 'guard' | 'resident' | 'admin',
) {
  const parcel = await loadParcelForActor(societyId, parcelId, actorUserId, role);
  if (parcel.status === 'CANCELLED') return serializeParcel(parcel);
  if (parcel.status !== 'AWAITING_HANDOVER') {
    throw conflict(`Cannot cancel parcel in status ${parcel.status}`, 'INVALID_PARCEL_STATUS');
  }
  const claimed = await ParcelHandoverModel.findOneAndUpdate(
    { _id: parcel._id, status: 'AWAITING_HANDOVER' },
    {
      $set: {
        status: 'CANCELLED',
        cancelledAt: new Date(),
        cancellationReason: reason,
      },
    },
    { new: true },
  );
  if (!claimed) throw conflict('Parcel was already processed', 'ALREADY_PROCESSED');
  await writeAuditLog({
    action: 'PARCEL_CANCELLED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'ParcelHandover',
    targetId: parcelId,
    metadata: { reason },
  });
  return serializeParcel(claimed);
}

export async function listParcels(
  societyId: string,
  query: {
    status?: ParcelStatus;
    flatId?: string;
    recipientUserId?: string;
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
  if (query.recipientUserId) {
    filter.recipientUserId = parseObjectId(query.recipientUserId, 'userId');
  }

  const [total, rows] = await Promise.all([
    ParcelHandoverModel.countDocuments(filter),
    ParcelHandoverModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((row) => serializeParcel(row)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getParcel(
  societyId: string,
  parcelId: string,
  actorUserId: string,
  role: 'guard' | 'resident' | 'admin',
) {
  const parcel = await loadParcelForActor(societyId, parcelId, actorUserId, role);
  return serializeParcel(parcel);
}

export function assertParcelNotVisitorEntry(): void {
  throw badRequest('Parcel authorization cannot grant visitor entry', 'PARCEL_NOT_ENTRY');
}
