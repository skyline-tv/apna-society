import { badRequest, conflict, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { ParkingAllocationModel } from '../models/parking-allocation.model';
import { ParkingSlotModel } from '../models/parking-slot.model';
import type { VehicleType } from '../models/vehicle.model';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeSlot(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  slotNumber: string;
  parkingType: string;
  locationDescription?: string;
  isActive: boolean;
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    slotNumber: doc.slotNumber,
    parkingType: doc.parkingType,
    locationDescription: doc.locationDescription,
    isActive: doc.isActive,
    deactivatedAt: doc.deactivatedAt?.toISOString(),
    deactivationReason: doc.deactivationReason,
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export async function createParkingSlot(
  societyId: string,
  input: {
    slotNumber: string;
    parkingType: VehicleType;
    locationDescription?: string;
  },
  actor: Actor,
) {
  const slotNumber = input.slotNumber.trim().toUpperCase();
  try {
    const [slot] = await ParkingSlotModel.create([
      {
        societyId,
        slotNumber,
        parkingType: input.parkingType,
        locationDescription: input.locationDescription?.trim(),
        isActive: true,
      },
    ]);

    await writeAuditLog({
      action: 'PARKING_SLOT_CREATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'ParkingSlot',
      targetId: String(slot._id),
      metadata: { slotNumber, parkingType: input.parkingType },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });

    return serializeSlot(slot);
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('An active parking slot with this number already exists', 'DUPLICATE_SLOT');
    }
    throw error;
  }
}

export async function listParkingSlots(
  societyId: string,
  query: {
    parkingType?: VehicleType;
    isActive?: boolean;
    availability?: 'available' | 'occupied' | 'all';
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.parkingType) filter.parkingType = query.parkingType;
  if (query.isActive !== undefined) filter.isActive = query.isActive;

  const occupiedSlotIds = await ParkingAllocationModel.find({
    societyId,
    status: 'ACTIVE',
  })
    .select('parkingSlotId')
    .lean();
  const occupiedSet = new Set(occupiedSlotIds.map((a) => String(a.parkingSlotId)));

  if (query.availability === 'available') {
    filter._id = { $nin: [...occupiedSet] };
    filter.isActive = true;
  } else if (query.availability === 'occupied') {
    filter._id = { $in: [...occupiedSet] };
  }

  const [total, rows] = await Promise.all([
    ParkingSlotModel.countDocuments(filter),
    ParkingSlotModel.find(filter)
      .sort({ slotNumber: 1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((row) => ({
      ...serializeSlot(row),
      isOccupied: occupiedSet.has(String(row._id)),
    })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getParkingSlot(societyId: string, slotId: string) {
  const slot = await ParkingSlotModel.findOne({
    _id: parseObjectId(slotId, 'slotId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!slot) throw notFound('Parking slot not found');

  const allocation = await ParkingAllocationModel.findOne({
    societyId,
    parkingSlotId: slot._id,
    status: 'ACTIVE',
  }).lean();

  return {
    ...serializeSlot(slot),
    isOccupied: Boolean(allocation),
    activeAllocationId: allocation ? String(allocation._id) : undefined,
  };
}

export async function updateParkingSlot(
  societyId: string,
  slotId: string,
  input: { locationDescription?: string; parkingType?: VehicleType },
  actor: Actor,
) {
  const slot = await ParkingSlotModel.findOne({
    _id: parseObjectId(slotId, 'slotId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!slot) throw notFound('Parking slot not found');

  if (input.locationDescription !== undefined) {
    slot.locationDescription = input.locationDescription.trim();
  }
  if (input.parkingType !== undefined) slot.parkingType = input.parkingType;
  await slot.save();

  await writeAuditLog({
    action: 'PARKING_SLOT_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'ParkingSlot',
    targetId: slotId,
    metadata: { ...input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeSlot(slot);
}

export async function setParkingSlotActive(
  societyId: string,
  slotId: string,
  isActive: boolean,
  reason: string | undefined,
  actor: Actor,
) {
  const slot = await ParkingSlotModel.findOne({
    _id: parseObjectId(slotId, 'slotId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!slot) throw notFound('Parking slot not found');

  if (!isActive) {
    const occupied = await ParkingAllocationModel.findOne({
      societyId,
      parkingSlotId: slot._id,
      status: 'ACTIVE',
    }).lean();
    if (occupied) {
      throw conflict(
        'Cannot deactivate an occupied parking slot; release the allocation first',
        'SLOT_OCCUPIED',
      );
    }
    if (!slot.isActive) return serializeSlot(slot);
    slot.isActive = false;
    slot.deactivatedAt = new Date();
    slot.deactivationReason = reason;
    await slot.save();
    await writeAuditLog({
      action: 'PARKING_SLOT_DEACTIVATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'ParkingSlot',
      targetId: slotId,
      metadata: { reason },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });
  } else {
    if (slot.isActive) return serializeSlot(slot);
    try {
      slot.isActive = true;
      slot.deactivatedAt = undefined;
      slot.deactivationReason = undefined;
      await slot.save();
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        throw conflict('An active parking slot with this number already exists', 'DUPLICATE_SLOT');
      }
      throw error;
    }
    await writeAuditLog({
      action: 'PARKING_SLOT_ACTIVATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'ParkingSlot',
      targetId: slotId,
      metadata: {},
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });
  }

  return serializeSlot(slot);
}

export async function getParkingAvailabilitySummary(societyId: string) {
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const [totalActive, occupied] = await Promise.all([
    ParkingSlotModel.countDocuments({ societyId: societyObjectId, isActive: true }),
    ParkingAllocationModel.countDocuments({ societyId: societyObjectId, status: 'ACTIVE' }),
  ]);
  const byType = await ParkingSlotModel.aggregate<{
    _id: string;
    total: number;
  }>([
    { $match: { societyId: societyObjectId, isActive: true } },
    { $group: { _id: '$parkingType', total: { $sum: 1 } } },
  ]);

  return {
    totalActiveSlots: totalActive,
    occupiedSlots: occupied,
    availableSlots: Math.max(0, totalActive - occupied),
    byParkingType: Object.fromEntries(byType.map((r) => [r._id, r.total])),
  };
}

export function assertSlotVehicleCompatible(slotType: string, vehicleType: string): void {
  if (slotType !== vehicleType) {
    throw badRequest(
      `Parking slot type ${slotType} is incompatible with vehicle type ${vehicleType}`,
      'INCOMPATIBLE_SLOT_TYPE',
    );
  }
}

export { serializeSlot };
