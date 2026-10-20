import { getEnv } from '../../../config/env';
import { DEFAULT_TIMEZONE } from '../../../config/constants';
import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { SocietyModel } from '../../society/models/society.model';
import {
  assertResidentialAccess,
  getFlatAccess,
} from '../../users/services/access-control.service';
import {
  addCivilDays,
  localDateString,
  minutesBetween,
  rangesOverlap,
  zonedDateTime,
} from '../../staff/utils/society-time';
import { FacilityBookingModel, type BookingStatus } from '../models/facility-booking.model';
import { FacilityModel, WEEKDAYS, type Weekday } from '../models/facility.model';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import {
  bookingEventPayload,
  emitFacilityBookingEvent,
} from './facility-events.service';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

async function societyTimeZone(societyId: string): Promise<string> {
  const society = await SocietyModel.findById(societyId).select('config.timezone').lean();
  return society?.config?.timezone ?? DEFAULT_TIMEZONE;
}

function weekdayFromLocalDate(localDate: string, timeZone: string): Weekday {
  const noon = zonedDateTime(localDate, '12:00', timeZone);
  const name = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'long' })
    .format(noon)
    .toUpperCase();
  if (!(WEEKDAYS as readonly string[]).includes(name)) {
    throw badRequest('Unable to resolve weekday', 'INVALID_BOOKING_DATE');
  }
  return name as Weekday;
}

function serializeBooking(
  doc: {
    _id: { toString(): string };
    societyId: { toString(): string };
    facilityId: { toString(): string };
    flatId: { toString(): string };
    bookedByUserId: { toString(): string };
    bookingDate: string;
    startTime: string;
    endTime: string;
    startAt: Date;
    endAt: Date;
    status: string;
    feePaiseSnapshot: number;
    feePaid: boolean;
    paymentReference?: string;
    adminNotes?: string;
    rejectionReason?: string;
    cancellationReason?: string;
    expiresAt?: Date;
    createdAt: Date;
    updatedAt: Date;
  },
  options: { includeAdminNotes?: boolean } = {},
) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    facilityId: String(doc.facilityId),
    flatId: String(doc.flatId),
    bookedByUserId: String(doc.bookedByUserId),
    bookingDate: doc.bookingDate,
    startTime: doc.startTime,
    endTime: doc.endTime,
    startAt: doc.startAt.toISOString(),
    endAt: doc.endAt.toISOString(),
    status: doc.status,
    feePaiseSnapshot: doc.feePaiseSnapshot,
    feePaid: doc.feePaid,
    feePaymentRequired: doc.feePaiseSnapshot > 0 && !doc.feePaid,
    paymentReference: options.includeAdminNotes ? doc.paymentReference : undefined,
    adminNotes: options.includeAdminNotes ? doc.adminNotes : undefined,
    rejectionReason: doc.rejectionReason,
    cancellationReason: doc.cancellationReason,
    expiresAt: doc.expiresAt?.toISOString(),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

/**
 * Expire PENDING bookings past expiresAt. Expired pendings do not count toward capacity.
 */
export async function expirePendingBookings(societyId: string, facilityId?: string) {
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
    status: 'PENDING',
    expiresAt: { $lte: new Date() },
  };
  if (facilityId) filter.facilityId = parseObjectId(facilityId, 'facilityId');
  await FacilityBookingModel.updateMany(filter, {
    $set: { status: 'CANCELLED', cancellationReason: 'Pending booking expired' },
  });
}

async function countConfirmedOverlapping(
  societyId: string,
  facilityId: string,
  startAt: Date,
  endAt: Date,
  session?: import('mongoose').ClientSession,
  excludeId?: string,
): Promise<number> {
  const filter: Record<string, unknown> = {
    societyId,
    facilityId,
    status: 'CONFIRMED',
    startAt: { $lt: endAt },
    endAt: { $gt: startAt },
  };
  if (excludeId) filter._id = { $ne: parseObjectId(excludeId, 'bookingId') };
  const q = FacilityBookingModel.find(filter).select('_id startAt endAt');
  if (session) q.session(session);
  const rows = await q.lean();
  return rows.filter((r) => rangesOverlap(startAt, endAt, r.startAt, r.endAt)).length;
}

function resolveBookingBounds(
  bookingDate: string,
  startTime: string,
  endTime: string,
  timeZone: string,
) {
  const startAt = zonedDateTime(bookingDate, startTime, timeZone);
  let endAt = zonedDateTime(bookingDate, endTime, timeZone);
  if (endAt.getTime() <= startAt.getTime()) {
    endAt = zonedDateTime(addCivilDays(bookingDate, 1), endTime, timeZone);
  }
  return { startAt, endAt };
}

function assertWithinFacilityHours(
  facility: {
    openingTime: string;
    closingTime: string;
    maxBookingDurationMinutes: number;
    availableDays: Weekday[];
  },
  bookingDate: string,
  startTime: string,
  endTime: string,
  timeZone: string,
) {
  const weekday = weekdayFromLocalDate(bookingDate, timeZone);
  if (!facility.availableDays.includes(weekday)) {
    throw badRequest('Facility is not available on this day', 'FACILITY_DAY_UNAVAILABLE');
  }

  const duration = minutesBetween(startTime, endTime, endTime <= startTime);
  if (duration > facility.maxBookingDurationMinutes) {
    throw badRequest(
      `Booking exceeds maximum duration of ${facility.maxBookingDurationMinutes} minutes`,
      'BOOKING_DURATION_EXCEEDED',
    );
  }

  const { startAt, endAt } = resolveBookingBounds(bookingDate, startTime, endTime, timeZone);
  const openAt = zonedDateTime(bookingDate, facility.openingTime, timeZone);
  let closeAt = zonedDateTime(bookingDate, facility.closingTime, timeZone);
  if (facility.closingTime <= facility.openingTime) {
    closeAt = zonedDateTime(addCivilDays(bookingDate, 1), facility.closingTime, timeZone);
  }
  if (startAt.getTime() < openAt.getTime() || endAt.getTime() > closeAt.getTime()) {
    throw badRequest('Booking is outside facility opening hours', 'OUTSIDE_OPENING_HOURS');
  }
}

export async function getFacilityAvailability(
  societyId: string,
  facilityId: string,
  bookingDate: string,
) {
  await expirePendingBookings(societyId, facilityId);
  const facility = await FacilityModel.findOne({
    _id: parseObjectId(facilityId, 'facilityId'),
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
  }).lean();
  if (!facility) throw notFound('Facility not found');

  const tz = await societyTimeZone(societyId);
  const dayStart = zonedDateTime(bookingDate, '00:00', tz);
  const dayEnd = zonedDateTime(addCivilDays(bookingDate, 1), '00:00', tz);

  const confirmed = await FacilityBookingModel.find({
    societyId,
    facilityId,
    status: 'CONFIRMED',
    startAt: { $lt: dayEnd },
    endAt: { $gt: dayStart },
  })
    .select('startAt endAt startTime endTime bookedByUserId')
    .lean();

  return {
    facilityId,
    bookingDate,
    capacity: facility.capacity,
    openingTime: facility.openingTime,
    closingTime: facility.closingTime,
    confirmedCount: confirmed.length,
    remainingCapacityHint: Math.max(0, facility.capacity - confirmed.length),
    confirmedSlots: confirmed.map((c) => ({
      startAt: c.startAt.toISOString(),
      endAt: c.endAt.toISOString(),
      startTime: c.startTime,
      endTime: c.endTime,
    })),
    pendingPolicy: {
      requiresApproval: facility.requiresApproval,
      pendingTtlMs: getEnv().FACILITY_PENDING_BOOKING_TTL_MS,
      pendingDoesNotConsumeCapacity: true,
      onlyConfirmedCountsTowardCapacity: true,
    },
  };
}

export async function createBooking(
  societyId: string,
  userId: string,
  facilityId: string,
  input: {
    flatId: string;
    bookingDate: string;
    startTime: string;
    endTime: string;
  },
  actor: Actor,
) {
  await expirePendingBookings(societyId, facilityId);
  await assertResidentialAccess({ userId, societyId, flatId: input.flatId });

  const facility = await FacilityModel.findOne({
    _id: parseObjectId(facilityId, 'facilityId'),
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
  }).lean();
  if (!facility) throw notFound('Facility not found');
  if (!facility.bookingRequired) {
    throw badRequest('This facility does not accept bookings', 'BOOKING_NOT_REQUIRED');
  }

  const tz = await societyTimeZone(societyId);
  assertWithinFacilityHours(facility, input.bookingDate, input.startTime, input.endTime, tz);
  const { startAt, endAt } = resolveBookingBounds(
    input.bookingDate,
    input.startTime,
    input.endTime,
    tz,
  );

  const initialStatus: BookingStatus = facility.requiresApproval ? 'PENDING' : 'CONFIRMED';
  const expiresAt =
    initialStatus === 'PENDING'
      ? new Date(Date.now() + getEnv().FACILITY_PENDING_BOOKING_TTL_MS)
      : undefined;

  const booking = await withTransaction(async (session) => {
    // Serialize capacity decisions per facility (concurrent txn write lock).
    await FacilityModel.updateOne(
      { _id: facility._id },
      { $inc: { __bookingLock: 1 } },
      { session },
    );

    if (initialStatus === 'CONFIRMED') {
      const used = await countConfirmedOverlapping(
        societyId,
        facilityId,
        startAt,
        endAt,
        session,
      );
      if (used >= facility.capacity) {
        throw conflict('Facility capacity is full for this time slot', 'FACILITY_CAPACITY_FULL');
      }
    }

    const [doc] = await FacilityBookingModel.create(
      [
        {
          societyId,
          facilityId,
          flatId: input.flatId,
          bookedByUserId: userId,
          bookingDate: input.bookingDate,
          startTime: input.startTime,
          endTime: input.endTime,
          startAt,
          endAt,
          status: initialStatus,
          feePaiseSnapshot: facility.bookingFeePaise,
          feePaid: false,
          expiresAt,
        },
      ],
      { session },
    );

    if (initialStatus === 'CONFIRMED') {
      const usedAfter = await countConfirmedOverlapping(
        societyId,
        facilityId,
        startAt,
        endAt,
        session,
      );
      if (usedAfter > facility.capacity) {
        throw conflict('Facility capacity is full for this time slot', 'FACILITY_CAPACITY_FULL');
      }
    }

    await writeAuditLog(
      {
        action: 'FACILITY_BOOKING_CREATED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'FacilityBooking',
        targetId: String(doc._id),
        metadata: {
          status: initialStatus,
          feePaiseSnapshot: facility.bookingFeePaise,
          feePaid: false,
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return doc;
  });

  return serializeBooking(booking);
}

export async function listResidentBookings(
  societyId: string,
  userId: string,
  query: { status?: BookingStatus; page?: number; limit?: number },
) {
  await expirePendingBookings(societyId);
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;

  // Own bookings + bookings on currently residentially accessible flats.
  const { FlatModel } = await import('../../society/models/flat.model');
  const flats = await FlatModel.find({
    societyId,
    isActive: true,
    $or: [{ activeOwnerUserId: userId }, { activeTenantUserId: userId }],
  })
    .select('_id')
    .lean();
  const residentialFlatIds: string[] = [];
  for (const flat of flats) {
    const access = await getFlatAccess({ userId, societyId, flatId: String(flat._id) });
    if (access.residential) residentialFlatIds.push(String(flat._id));
  }

  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
    $or: [
      { bookedByUserId: userId },
      ...(residentialFlatIds.length
        ? [{ flatId: { $in: residentialFlatIds.map((id) => parseObjectId(id, 'flatId')) } }]
        : []),
    ],
  };
  if (query.status) filter.status = query.status;

  const [total, rows] = await Promise.all([
    FacilityBookingModel.countDocuments(filter),
    FacilityBookingModel.find(filter)
      .sort({ startAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeBooking(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getResidentBooking(
  societyId: string,
  userId: string,
  bookingId: string,
) {
  const doc = await FacilityBookingModel.findOne({
    _id: parseObjectId(bookingId, 'bookingId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Booking not found');

  // Previous tenants lose access to flat bookings (including ones they raised).
  const access = await getFlatAccess({
    userId,
    societyId,
    flatId: String(doc.flatId),
  });
  if (!access.residential) {
    throw forbidden('Booking access denied', 'BOOKING_ACCESS_DENIED');
  }

  return serializeBooking(doc);
}

export async function cancelResidentBooking(
  societyId: string,
  userId: string,
  bookingId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const doc = await FacilityBookingModel.findOne({
    _id: parseObjectId(bookingId, 'bookingId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Booking not found');
  if (String(doc.bookedByUserId) !== userId) {
    throw forbidden('Only the booker may cancel this booking', 'BOOKING_CANCEL_FORBIDDEN');
  }
  if (!['PENDING', 'CONFIRMED'].includes(doc.status)) {
    throw conflict('Booking cannot be cancelled in its current status', 'INVALID_BOOKING_STATUS');
  }

  const previous = doc.status;
  doc.status = 'CANCELLED';
  doc.cancellationReason = reason;
  await doc.save();

  await writeAuditLog({
    action: 'FACILITY_BOOKING_CANCELLED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'FacilityBooking',
    targetId: bookingId,
    metadata: { by: 'resident', previous },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  emitFacilityBookingEvent('facility:booking_cancelled', bookingEventPayload(doc));
  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(doc.bookedByUserId),
    type: 'FACILITY_BOOKING_CANCELLED',
    title: 'Facility booking cancelled',
    body: 'Your facility booking was cancelled',
    relatedEntityType: 'FacilityBooking',
    relatedEntityId: String(doc._id),
    idempotencyKey: `FACILITY_BOOKING_CANCELLED:${String(doc._id)}:resident`,
  });
  return serializeBooking(doc);
}

export async function listAdminBookings(
  societyId: string,
  query: {
    status?: BookingStatus;
    facilityId?: string;
    flatId?: string;
    from?: string;
    to?: string;
    page?: number;
    limit?: number;
  },
) {
  await expirePendingBookings(societyId);
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.status) filter.status = query.status;
  if (query.facilityId) filter.facilityId = parseObjectId(query.facilityId, 'facilityId');
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.from || query.to) {
    filter.bookingDate = {};
    if (query.from) (filter.bookingDate as Record<string, string>).$gte = query.from;
    if (query.to) (filter.bookingDate as Record<string, string>).$lte = query.to;
  }

  const [total, rows] = await Promise.all([
    FacilityBookingModel.countDocuments(filter),
    FacilityBookingModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeBooking(r, { includeAdminNotes: true })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getAdminBooking(societyId: string, bookingId: string) {
  const doc = await FacilityBookingModel.findOne({
    _id: parseObjectId(bookingId, 'bookingId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Booking not found');
  return serializeBooking(doc, { includeAdminNotes: true });
}

export async function approveBooking(
  societyId: string,
  bookingId: string,
  adminNotes: string | undefined,
  actor: Actor,
) {
  await expirePendingBookings(societyId);

  const updated = await withTransaction(async (session) => {
    const existing = await FacilityBookingModel.findOne({
      _id: parseObjectId(bookingId, 'bookingId'),
      societyId: parseObjectId(societyId, 'societyId'),
    }).session(session);
    if (!existing) throw notFound('Booking not found');
    if (existing.status !== 'PENDING') {
      throw conflict('Only PENDING bookings can be approved', 'INVALID_BOOKING_STATUS');
    }
    if (existing.expiresAt && existing.expiresAt.getTime() <= Date.now()) {
      existing.status = 'CANCELLED';
      existing.cancellationReason = 'Pending booking expired';
      await existing.save({ session });
      throw conflict('Pending booking has expired', 'BOOKING_EXPIRED');
    }

    // Serialize capacity decisions per facility.
    await FacilityModel.updateOne(
      { _id: existing.facilityId },
      { $inc: { __bookingLock: 1 } },
      { session },
    );

    const facility = await FacilityModel.findById(existing.facilityId).session(session).lean();
    if (!facility || !facility.isActive) throw notFound('Facility not found');

    const used = await countConfirmedOverlapping(
      societyId,
      String(existing.facilityId),
      existing.startAt,
      existing.endAt,
      session,
      bookingId,
    );
    if (used >= facility.capacity) {
      throw conflict('Facility capacity is full for this time slot', 'FACILITY_CAPACITY_FULL');
    }

    const claimed = await FacilityBookingModel.findOneAndUpdate(
      { _id: existing._id, status: 'PENDING' },
      {
        $set: {
          status: 'CONFIRMED',
          adminNotes: adminNotes?.trim(),
        },
        $unset: { expiresAt: 1 },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Booking approval conflict', 'BOOKING_CONFLICT');
    }

    await writeAuditLog(
      {
        action: 'FACILITY_BOOKING_APPROVED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'FacilityBooking',
        targetId: bookingId,
        metadata: { feePaid: claimed.feePaid },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitFacilityBookingEvent('facility:booking_approved', bookingEventPayload(updated));
  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(updated.bookedByUserId),
    type: 'FACILITY_BOOKING_APPROVED',
    title: 'Facility booking approved',
    body: 'Your facility booking was approved',
    relatedEntityType: 'FacilityBooking',
    relatedEntityId: String(updated._id),
    idempotencyKey: `FACILITY_BOOKING_APPROVED:${String(updated._id)}`,
  });
  return serializeBooking(updated, { includeAdminNotes: true });
}

export async function rejectBooking(
  societyId: string,
  bookingId: string,
  reason: string,
  actor: Actor,
) {
  const doc = await FacilityBookingModel.findOne({
    _id: parseObjectId(bookingId, 'bookingId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Booking not found');
  if (doc.status !== 'PENDING') {
    throw conflict('Only PENDING bookings can be rejected', 'INVALID_BOOKING_STATUS');
  }

  doc.status = 'REJECTED';
  doc.rejectionReason = reason.trim();
  await doc.save();

  await writeAuditLog({
    action: 'FACILITY_BOOKING_REJECTED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'FacilityBooking',
    targetId: bookingId,
    metadata: { reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  emitFacilityBookingEvent('facility:booking_rejected', bookingEventPayload(doc));
  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(doc.bookedByUserId),
    type: 'FACILITY_BOOKING_REJECTED',
    title: 'Facility booking rejected',
    body: 'Your facility booking was rejected',
    relatedEntityType: 'FacilityBooking',
    relatedEntityId: String(doc._id),
    idempotencyKey: `FACILITY_BOOKING_REJECTED:${String(doc._id)}`,
  });
  return serializeBooking(doc, { includeAdminNotes: true });
}

export async function cancelAdminBooking(
  societyId: string,
  bookingId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const doc = await FacilityBookingModel.findOne({
    _id: parseObjectId(bookingId, 'bookingId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Booking not found');
  if (!['PENDING', 'CONFIRMED'].includes(doc.status)) {
    throw conflict('Booking cannot be cancelled', 'INVALID_BOOKING_STATUS');
  }

  doc.status = 'CANCELLED';
  doc.cancellationReason = reason;
  await doc.save();

  await writeAuditLog({
    action: 'FACILITY_BOOKING_CANCELLED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'FacilityBooking',
    targetId: bookingId,
    metadata: { by: 'admin', reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  emitFacilityBookingEvent('facility:booking_cancelled', bookingEventPayload(doc));
  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(doc.bookedByUserId),
    type: 'FACILITY_BOOKING_CANCELLED',
    title: 'Facility booking cancelled',
    body: 'Your facility booking was cancelled',
    relatedEntityType: 'FacilityBooking',
    relatedEntityId: String(doc._id),
    idempotencyKey: `FACILITY_BOOKING_CANCELLED:${String(doc._id)}:admin`,
  });
  return serializeBooking(doc, { includeAdminNotes: true });
}

export { serializeBooking, localDateString };
