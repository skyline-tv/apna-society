import { invalidateFacilityCaches } from '../../../cache/cache-invalidation';
import { CacheKeys, hashFilters } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { conflict, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FacilityModel, type FacilityCategory, type Weekday } from '../models/facility.model';
import { FacilityBookingModel } from '../models/facility-booking.model';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeFacility(
  doc: {
    _id: { toString(): string };
    societyId: { toString(): string };
    name: string;
    description?: string;
    category: string;
    location?: string;
    capacity: number;
    bookingRequired: boolean;
    requiresApproval: boolean;
    maxBookingDurationMinutes: number;
    openingTime: string;
    closingTime: string;
    availableDays: string[];
    isActive: boolean;
    bookingFeePaise: number;
    createdBy: { toString(): string };
    deactivatedAt?: Date;
    createdAt: Date;
    updatedAt: Date;
  },
  options: { includeAdmin?: boolean } = {},
) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    name: doc.name,
    description: doc.description,
    category: doc.category,
    location: doc.location,
    capacity: doc.capacity,
    bookingRequired: doc.bookingRequired,
    requiresApproval: doc.requiresApproval,
    maxBookingDurationMinutes: doc.maxBookingDurationMinutes,
    openingTime: doc.openingTime,
    closingTime: doc.closingTime,
    availableDays: doc.availableDays,
    isActive: doc.isActive,
    bookingFeePaise: doc.bookingFeePaise,
    feePaymentRequired: doc.bookingFeePaise > 0,
    createdBy: options.includeAdmin ? String(doc.createdBy) : undefined,
    deactivatedAt: doc.deactivatedAt?.toISOString(),
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export async function createFacility(
  societyId: string,
  input: {
    name: string;
    description?: string;
    category: FacilityCategory;
    location?: string;
    capacity: number;
    bookingRequired?: boolean;
    requiresApproval?: boolean;
    maxBookingDurationMinutes: number;
    openingTime: string;
    closingTime: string;
    availableDays: Weekday[];
    bookingFeePaise?: number;
  },
  actor: Actor,
) {
  try {
    const [doc] = await FacilityModel.create([
      {
        societyId,
        name: input.name.trim(),
        description: input.description?.trim(),
        category: input.category,
        location: input.location?.trim(),
        capacity: input.capacity,
        bookingRequired: input.bookingRequired ?? true,
        requiresApproval: input.requiresApproval ?? true,
        maxBookingDurationMinutes: input.maxBookingDurationMinutes,
        openingTime: input.openingTime,
        closingTime: input.closingTime,
        availableDays: input.availableDays,
        bookingFeePaise: input.bookingFeePaise ?? 0,
        isActive: true,
        createdBy: actor.userId,
      },
    ]);

    await writeAuditLog({
      action: 'FACILITY_CREATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'Facility',
      targetId: String(doc._id),
      metadata: { name: doc.name, category: doc.category },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });

    await invalidateFacilityCaches(societyId);
    return serializeFacility(doc, { includeAdmin: true });
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('A facility with this name already exists', 'DUPLICATE_FACILITY');
    }
    throw error;
  }
}

async function loadFacilitiesList(
  societyId: string,
  query: { isActive?: boolean; category?: FacilityCategory; page?: number; limit?: number },
  options: { includeAdmin?: boolean } = {},
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.isActive !== undefined) filter.isActive = query.isActive;
  if (query.category) filter.category = query.category;
  // Residents only see active bookable facilities.
  if (!options.includeAdmin) filter.isActive = true;

  const [total, rows] = await Promise.all([
    FacilityModel.countDocuments(filter),
    FacilityModel.find(filter)
      .sort({ name: 1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeFacility(r, options)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function listFacilities(
  societyId: string,
  query: { isActive?: boolean; category?: FacilityCategory; page?: number; limit?: number },
  options: { includeAdmin?: boolean } = {},
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filtersHash = hashFilters({
    isActive: query.isActive ?? null,
    category: query.category ?? null,
    page,
    limit,
    includeAdmin: Boolean(options.includeAdmin),
  });
  return cacheAside(
    CacheKeys.facilitiesList(societyId, filtersHash),
    getEnv().CACHE_TTL_FACILITIES_SECONDS,
    () => loadFacilitiesList(societyId, query, options),
  );
}

export async function getFacility(
  societyId: string,
  facilityId: string,
  options: { includeAdmin?: boolean } = {},
) {
  const filter: Record<string, unknown> = {
    _id: parseObjectId(facilityId, 'facilityId'),
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (!options.includeAdmin) filter.isActive = true;

  const doc = await FacilityModel.findOne(filter).lean();
  if (!doc) throw notFound('Facility not found');
  return serializeFacility(doc, options);
}

export async function updateFacility(
  societyId: string,
  facilityId: string,
  input: Partial<{
    name: string;
    description: string;
    category: FacilityCategory;
    location: string;
    capacity: number;
    bookingRequired: boolean;
    requiresApproval: boolean;
    maxBookingDurationMinutes: number;
    openingTime: string;
    closingTime: string;
    availableDays: Weekday[];
    bookingFeePaise: number;
  }>,
  actor: Actor,
) {
  const doc = await FacilityModel.findOne({
    _id: parseObjectId(facilityId, 'facilityId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Facility not found');

  Object.assign(doc, {
    ...(input.name !== undefined ? { name: input.name.trim() } : {}),
    ...(input.description !== undefined ? { description: input.description.trim() } : {}),
    ...(input.category !== undefined ? { category: input.category } : {}),
    ...(input.location !== undefined ? { location: input.location.trim() } : {}),
    ...(input.capacity !== undefined ? { capacity: input.capacity } : {}),
    ...(input.bookingRequired !== undefined ? { bookingRequired: input.bookingRequired } : {}),
    ...(input.requiresApproval !== undefined ? { requiresApproval: input.requiresApproval } : {}),
    ...(input.maxBookingDurationMinutes !== undefined
      ? { maxBookingDurationMinutes: input.maxBookingDurationMinutes }
      : {}),
    ...(input.openingTime !== undefined ? { openingTime: input.openingTime } : {}),
    ...(input.closingTime !== undefined ? { closingTime: input.closingTime } : {}),
    ...(input.availableDays !== undefined ? { availableDays: input.availableDays } : {}),
    ...(input.bookingFeePaise !== undefined ? { bookingFeePaise: input.bookingFeePaise } : {}),
  });

  try {
    await doc.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('A facility with this name already exists', 'DUPLICATE_FACILITY');
    }
    throw error;
  }

  await writeAuditLog({
    action: 'FACILITY_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Facility',
    targetId: facilityId,
    metadata: { ...input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  await invalidateFacilityCaches(societyId);
  return serializeFacility(doc, { includeAdmin: true });
}

export async function setFacilityActive(
  societyId: string,
  facilityId: string,
  isActive: boolean,
  actor: Actor,
) {
  const doc = await FacilityModel.findOne({
    _id: parseObjectId(facilityId, 'facilityId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Facility not found');

  if (isActive) {
    if (doc.isActive) return serializeFacility(doc, { includeAdmin: true });
    doc.isActive = true;
    doc.deactivatedAt = undefined;
  } else {
    if (!doc.isActive) return serializeFacility(doc, { includeAdmin: true });
    doc.isActive = false;
    doc.deactivatedAt = new Date();
  }
  await doc.save();

  await invalidateFacilityCaches(societyId);

  await writeAuditLog({
    action: isActive ? 'FACILITY_ACTIVATED' : 'FACILITY_DEACTIVATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Facility',
    targetId: facilityId,
    metadata: {},
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeFacility(doc, { includeAdmin: true });
}

export async function facilityBookingSummary(societyId: string) {
  const match = { societyId: parseObjectId(societyId, 'societyId') };
  const byStatus = await FacilityBookingModel.aggregate<{ _id: string; count: number }>([
    { $match: match },
    { $group: { _id: '$status', count: { $sum: 1 } } },
  ]);
  const totalFacilities = await FacilityModel.countDocuments({
    ...match,
    isActive: true,
  });
  return {
    activeFacilities: totalFacilities,
    byStatus: Object.fromEntries(byStatus.map((r) => [r._id, r.count])),
    totalBookings: byStatus.reduce((n, r) => n + r.count, 0),
  };
}

export { serializeFacility };
