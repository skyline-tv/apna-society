import { DEFAULT_TIMEZONE } from '../../../config/constants';
import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { SocietyModel } from '../../society/models/society.model';
import { StaffAttendanceModel, type AttendanceStatus } from '../models/staff-attendance.model';
import { StaffModel } from '../models/staff.model';
import { localDateString } from '../utils/society-time';
import { assertActiveStaff } from './staff.service';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

async function societyTimeZone(societyId: string): Promise<string> {
  const society = await SocietyModel.findById(societyId).select('config.timezone').lean();
  return society?.config?.timezone ?? DEFAULT_TIMEZONE;
}

function serializeAttendance(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  staffId: { toString(): string };
  localDate: string;
  checkInAt?: Date;
  checkOutAt?: Date;
  status: string;
  recordedByUserId: { toString(): string };
  notes?: string;
  correctionHistory?: Array<{
    correctedByUserId: { toString(): string };
    correctedAt: Date;
    previous: Record<string, unknown>;
    reason: string;
  }>;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    staffId: String(doc.staffId),
    localDate: doc.localDate,
    checkInAt: doc.checkInAt?.toISOString(),
    checkOutAt: doc.checkOutAt?.toISOString(),
    status: doc.status,
    recordedByUserId: String(doc.recordedByUserId),
    notes: doc.notes,
    correctionHistory: (doc.correctionHistory ?? []).map((c) => ({
      correctedByUserId: String(c.correctedByUserId),
      correctedAt: c.correctedAt.toISOString(),
      previous: c.previous,
      reason: c.reason,
    })),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export async function markAttendance(
  societyId: string,
  input: {
    staffId: string;
    localDate?: string;
    status: AttendanceStatus;
    checkInAt?: Date;
    notes?: string;
  },
  actor: Actor,
) {
  await assertActiveStaff(societyId, input.staffId);
  const tz = await societyTimeZone(societyId);
  const localDate = input.localDate ?? localDateString(new Date(), tz);

  // Server clock for check-in unless admin supplies a validated timestamp in the same local day.
  let checkInAt: Date | undefined;
  if (input.status === 'PRESENT' || input.status === 'HALF_DAY') {
    checkInAt = input.checkInAt ?? new Date();
    if (localDateString(checkInAt, tz) !== localDate) {
      throw badRequest(
        'Check-in timestamp must fall on the attendance local date',
        'INVALID_CHECK_IN_DATE',
      );
    }
  }

  try {
    const doc = await withTransaction(async (session) => {
      const [created] = await StaffAttendanceModel.create(
        [
          {
            societyId,
            staffId: input.staffId,
            localDate,
            status: input.status,
            checkInAt,
            recordedByUserId: actor.userId,
            notes: input.notes?.trim(),
            correctionHistory: [],
          },
        ],
        { session },
      );

      await writeAuditLog(
        {
          action: 'STAFF_ATTENDANCE_MARKED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'StaffAttendance',
          targetId: String(created._id),
          metadata: { staffId: input.staffId, localDate, status: input.status },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      return created;
    });
    return serializeAttendance(doc);
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict(
        'Attendance already recorded for this staff member on this date',
        'DUPLICATE_ATTENDANCE',
      );
    }
    throw error;
  }
}

export async function checkOutAttendance(
  societyId: string,
  attendanceId: string,
  actor: Actor,
) {
  const doc = await StaffAttendanceModel.findOne({
    _id: parseObjectId(attendanceId, 'attendanceId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Attendance not found');
  if (!doc.checkInAt) {
    throw badRequest('Check-out requires a prior check-in', 'CHECK_IN_REQUIRED');
  }
  if (doc.checkOutAt) {
    throw conflict('Attendance already checked out', 'ALREADY_CHECKED_OUT');
  }

  const checkOutAt = new Date();
  if (checkOutAt.getTime() < doc.checkInAt.getTime()) {
    throw badRequest('Check-out cannot be before check-in', 'INVALID_CHECK_OUT');
  }

  doc.checkOutAt = checkOutAt;
  await doc.save();

  await writeAuditLog({
    action: 'STAFF_ATTENDANCE_CHECKED_OUT',
    actorUserId: actor.userId,
    societyId,
    targetType: 'StaffAttendance',
    targetId: attendanceId,
    metadata: { checkOutAt: checkOutAt.toISOString() },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAttendance(doc);
}

export async function correctAttendance(
  societyId: string,
  attendanceId: string,
  input: {
    status?: AttendanceStatus;
    checkInAt?: Date | null;
    checkOutAt?: Date | null;
    notes?: string;
    reason: string;
  },
  actor: Actor,
) {
  const doc = await StaffAttendanceModel.findOne({
    _id: parseObjectId(attendanceId, 'attendanceId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Attendance not found');

  const previous = {
    status: doc.status,
    checkInAt: doc.checkInAt?.toISOString(),
    checkOutAt: doc.checkOutAt?.toISOString(),
    notes: doc.notes,
  };

  if (input.status !== undefined) doc.status = input.status;
  if (input.checkInAt !== undefined) {
    doc.checkInAt = input.checkInAt ?? undefined;
  }
  if (input.checkOutAt !== undefined) {
    doc.checkOutAt = input.checkOutAt ?? undefined;
  }
  if (input.notes !== undefined) doc.notes = input.notes.trim();

  if (doc.checkInAt && doc.checkOutAt && doc.checkOutAt.getTime() < doc.checkInAt.getTime()) {
    throw badRequest('Check-out cannot be before check-in', 'INVALID_CHECK_OUT');
  }

  doc.correctionHistory.push({
    correctedByUserId: parseObjectId(actor.userId, 'userId'),
    correctedAt: new Date(),
    previous,
    reason: input.reason.trim(),
  });
  await doc.save();

  await writeAuditLog({
    action: 'STAFF_ATTENDANCE_CORRECTED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'StaffAttendance',
    targetId: attendanceId,
    metadata: { reason: input.reason, previous },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeAttendance(doc);
}

export async function listAttendance(
  societyId: string,
  query: {
    staffId?: string;
    localDate?: string;
    from?: string;
    to?: string;
    status?: AttendanceStatus;
    category?: string;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.staffId) filter.staffId = parseObjectId(query.staffId, 'staffId');
  if (query.status) filter.status = query.status;
  if (query.localDate) filter.localDate = query.localDate;
  if (query.from || query.to) {
    filter.localDate = filter.localDate ?? {};
    if (typeof filter.localDate === 'string') {
      filter.localDate = { $eq: filter.localDate };
    }
    if (query.from) (filter.localDate as Record<string, string>).$gte = query.from;
    if (query.to) (filter.localDate as Record<string, string>).$lte = query.to;
  }

  if (query.category) {
    const staffIds = await StaffModel.find({
      societyId,
      category: query.category,
    })
      .select('_id')
      .lean();
    filter.staffId = { $in: staffIds.map((s) => s._id) };
  }

  const [total, rows] = await Promise.all([
    StaffAttendanceModel.countDocuments(filter),
    StaffAttendanceModel.find(filter)
      .sort({ localDate: -1, createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeAttendance(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function attendanceSummary(
  societyId: string,
  query: { from?: string; to?: string },
) {
  const match: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.from || query.to) {
    match.localDate = {};
    if (query.from) (match.localDate as Record<string, string>).$gte = query.from;
    if (query.to) (match.localDate as Record<string, string>).$lte = query.to;
  }

  const byStatus = await StaffAttendanceModel.aggregate<{ _id: string; count: number }>([
    { $match: match },
    { $group: { _id: '$status', count: { $sum: 1 } } },
  ]);

  return {
    total: byStatus.reduce((n, r) => n + r.count, 0),
    byStatus: Object.fromEntries(byStatus.map((r) => [r._id, r.count])),
  };
}
