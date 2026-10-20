import { DEFAULT_TIMEZONE } from '../../../config/constants';
import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { SocietyModel } from '../../society/models/society.model';
import { StaffShiftModel } from '../models/staff-shift.model';
import {
  addCivilDays,
  localDateString,
  rangesOverlap,
  zonedDateTime,
} from '../utils/society-time';
import { assertActiveStaff } from './staff.service';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import {
  emitStaffShiftEvent,
  staffShiftPayload,
} from './staff-events.service';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

async function societyTimeZone(societyId: string): Promise<string> {
  const society = await SocietyModel.findById(societyId).select('config.timezone').lean();
  return society?.config?.timezone ?? DEFAULT_TIMEZONE;
}

function serializeShift(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  staffId: { toString(): string };
  shiftDate: string;
  startTime: string;
  endTime: string;
  startAt: Date;
  endAt: Date;
  dutyLocation?: string;
  notes?: string;
  status: string;
  createdBy: { toString(): string };
  cancelledAt?: Date;
  cancelReason?: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    staffId: String(doc.staffId),
    shiftDate: doc.shiftDate,
    startTime: doc.startTime,
    endTime: doc.endTime,
    startAt: doc.startAt.toISOString(),
    endAt: doc.endAt.toISOString(),
    dutyLocation: doc.dutyLocation,
    notes: doc.notes,
    status: doc.status,
    createdBy: String(doc.createdBy),
    cancelledAt: doc.cancelledAt?.toISOString(),
    cancelReason: doc.cancelReason,
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

function resolveShiftBounds(
  shiftDate: string,
  startTime: string,
  endTime: string,
  timeZone: string,
) {
  const startAt = zonedDateTime(shiftDate, startTime, timeZone);
  let endAt = zonedDateTime(shiftDate, endTime, timeZone);
  if (endAt.getTime() <= startAt.getTime()) {
    // Overnight shift → end on next local calendar day.
    endAt = zonedDateTime(addCivilDays(shiftDate, 1), endTime, timeZone);
  }
  if (endAt.getTime() <= startAt.getTime()) {
    throw badRequest('Invalid shift start/end times', 'INVALID_SHIFT_TIMES');
  }
  return { startAt, endAt };
}

async function assertNoOverlap(
  societyId: string,
  staffId: string,
  startAt: Date,
  endAt: Date,
  excludeId?: string,
) {
  const candidates = await StaffShiftModel.find({
    societyId,
    staffId,
    status: 'SCHEDULED',
    startAt: { $lt: endAt },
    endAt: { $gt: startAt },
    ...(excludeId ? { _id: { $ne: parseObjectId(excludeId, 'shiftId') } } : {}),
  }).lean();

  for (const c of candidates) {
    if (rangesOverlap(startAt, endAt, c.startAt, c.endAt)) {
      throw conflict('Shift overlaps an existing scheduled shift', 'SHIFT_OVERLAP');
    }
  }
}

export async function createShift(
  societyId: string,
  input: {
    staffId: string;
    shiftDate: string;
    startTime: string;
    endTime: string;
    dutyLocation?: string;
    notes?: string;
  },
  actor: Actor,
) {
  const staff = await assertActiveStaff(societyId, input.staffId);
  const tz = await societyTimeZone(societyId);
  const { startAt, endAt } = resolveShiftBounds(
    input.shiftDate,
    input.startTime,
    input.endTime,
    tz,
  );

  const shift = await withTransaction(async (session) => {
    const { StaffModel } = await import('../models/staff.model');
    await StaffModel.updateOne(
      { _id: input.staffId, societyId },
      { $inc: { __shiftLock: 1 } },
      { session },
    );

    const overlapping = await StaffShiftModel.findOne({
      societyId,
      staffId: input.staffId,
      status: 'SCHEDULED',
      startAt: { $lt: endAt },
      endAt: { $gt: startAt },
    }).session(session);
    if (overlapping) {
      throw conflict('Shift overlaps an existing scheduled shift', 'SHIFT_OVERLAP');
    }

    const [doc] = await StaffShiftModel.create(
      [
        {
          societyId,
          staffId: input.staffId,
          shiftDate: input.shiftDate,
          startTime: input.startTime,
          endTime: input.endTime,
          startAt,
          endAt,
          dutyLocation: input.dutyLocation?.trim(),
          notes: input.notes?.trim(),
          status: 'SCHEDULED',
          createdBy: actor.userId,
        },
      ],
      { session },
    );

    await writeAuditLog(
      {
        action: 'STAFF_SHIFT_CREATED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'StaffShift',
        targetId: String(doc._id),
        metadata: { staffId: input.staffId, shiftDate: input.shiftDate },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return doc;
  });

  if (staff.linkedUserId) {
    const linkedUserId = String(staff.linkedUserId);
    emitStaffShiftEvent('staff:shift_assigned', staffShiftPayload(shift, linkedUserId));
    await notifyBusinessEvent({
      societyId,
      recipientUserId: linkedUserId,
      type: 'STAFF_SHIFT_ASSIGNED',
      title: 'Shift assigned',
      body: `You have a shift on ${input.shiftDate}`,
      relatedEntityType: 'StaffShift',
      relatedEntityId: String(shift._id),
      idempotencyKey: `STAFF_SHIFT_ASSIGNED:${String(shift._id)}`,
    });
  }

  return serializeShift(shift);
}

export async function listShifts(
  societyId: string,
  query: {
    staffId?: string;
    from?: string;
    to?: string;
    status?: string;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 50;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.staffId) filter.staffId = parseObjectId(query.staffId, 'staffId');
  if (query.status) filter.status = query.status;
  if (query.from || query.to) {
    filter.shiftDate = {};
    if (query.from) (filter.shiftDate as Record<string, string>).$gte = query.from;
    if (query.to) (filter.shiftDate as Record<string, string>).$lte = query.to;
  }

  const [total, rows] = await Promise.all([
    StaffShiftModel.countDocuments(filter),
    StaffShiftModel.find(filter)
      .sort({ startAt: 1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeShift(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getShift(societyId: string, shiftId: string) {
  const doc = await StaffShiftModel.findOne({
    _id: parseObjectId(shiftId, 'shiftId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Shift not found');
  return serializeShift(doc);
}

export async function updateFutureShift(
  societyId: string,
  shiftId: string,
  input: {
    shiftDate?: string;
    startTime?: string;
    endTime?: string;
    dutyLocation?: string;
    notes?: string;
  },
  actor: Actor,
) {
  const doc = await StaffShiftModel.findOne({
    _id: parseObjectId(shiftId, 'shiftId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Shift not found');
  if (doc.status !== 'SCHEDULED') {
    throw badRequest('Only scheduled shifts can be updated', 'SHIFT_NOT_EDITABLE');
  }

  const tz = await societyTimeZone(societyId);
  const nowLocal = localDateString(new Date(), tz);
  if (doc.shiftDate < nowLocal) {
    throw badRequest('Past shifts cannot be casually modified', 'SHIFT_IN_PAST');
  }

  const shiftDate = input.shiftDate ?? doc.shiftDate;
  const startTime = input.startTime ?? doc.startTime;
  const endTime = input.endTime ?? doc.endTime;
  const { startAt, endAt } = resolveShiftBounds(shiftDate, startTime, endTime, tz);

  await assertNoOverlap(societyId, String(doc.staffId), startAt, endAt, shiftId);

  doc.shiftDate = shiftDate;
  doc.startTime = startTime;
  doc.endTime = endTime;
  doc.startAt = startAt;
  doc.endAt = endAt;
  if (input.dutyLocation !== undefined) doc.dutyLocation = input.dutyLocation.trim();
  if (input.notes !== undefined) doc.notes = input.notes.trim();
  await doc.save();

  await writeAuditLog({
    action: 'STAFF_SHIFT_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'StaffShift',
    targetId: shiftId,
    metadata: { ...input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeShift(doc);
}

export async function cancelFutureShift(
  societyId: string,
  shiftId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const doc = await StaffShiftModel.findOne({
    _id: parseObjectId(shiftId, 'shiftId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Shift not found');
  if (doc.status === 'CANCELLED') return serializeShift(doc);

  const tz = await societyTimeZone(societyId);
  const nowLocal = localDateString(new Date(), tz);
  if (doc.shiftDate < nowLocal) {
    throw badRequest('Past shifts cannot be cancelled casually', 'SHIFT_IN_PAST');
  }

  doc.status = 'CANCELLED';
  doc.cancelledAt = new Date();
  doc.cancelReason = reason;
  await doc.save();

  await writeAuditLog({
    action: 'STAFF_SHIFT_CANCELLED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'StaffShift',
    targetId: shiftId,
    metadata: { reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeShift(doc);
}

export async function scheduleView(
  societyId: string,
  query: { from: string; to: string },
) {
  return listShifts(societyId, {
    from: query.from,
    to: query.to,
    status: 'SCHEDULED',
    page: 1,
    limit: 500,
  });
}
