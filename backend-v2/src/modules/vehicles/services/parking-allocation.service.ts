import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError, isTransientTransactionError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../../society/models/flat.model';
import { ParkingAllocationModel } from '../models/parking-allocation.model';
import { ParkingSlotModel } from '../models/parking-slot.model';
import { VehicleModel } from '../models/vehicle.model';
import { assertSlotVehicleCompatible } from './parking-slot.service';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeAllocation(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  vehicleId: { toString(): string };
  parkingSlotId: { toString(): string };
  startsAt: Date;
  endsAt?: Date;
  status: string;
  createdBy: { toString(): string };
  endedBy?: { toString(): string };
  endReason?: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    vehicleId: String(doc.vehicleId),
    parkingSlotId: String(doc.parkingSlotId),
    startsAt: doc.startsAt.toISOString(),
    endsAt: doc.endsAt?.toISOString(),
    status: doc.status,
    createdBy: String(doc.createdBy),
    endedBy: doc.endedBy ? String(doc.endedBy) : undefined,
    endReason: doc.endReason,
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export async function allocateParkingSlot(
  societyId: string,
  input: {
    flatId: string;
    vehicleId: string;
    parkingSlotId: string;
    startsAt?: Date;
  },
  actor: Actor,
) {
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const flat = await FlatModel.findOne({
    _id: parseObjectId(input.flatId, 'flatId'),
    societyId: societyObjectId,
    isActive: true,
  }).lean();
  if (!flat) throw notFound('Flat not found in this society');

  const vehicle = await VehicleModel.findOne({
    _id: parseObjectId(input.vehicleId, 'vehicleId'),
    societyId: societyObjectId,
  }).lean();
  if (!vehicle) throw notFound('Vehicle not found in this society');
  if (!vehicle.isActive) throw badRequest('Vehicle is inactive', 'VEHICLE_INACTIVE');
  if (String(vehicle.flatId) !== String(flat._id)) {
    throw badRequest('Vehicle does not belong to the specified flat', 'VEHICLE_FLAT_MISMATCH');
  }

  const slot = await ParkingSlotModel.findOne({
    _id: parseObjectId(input.parkingSlotId, 'parkingSlotId'),
    societyId: societyObjectId,
  }).lean();
  if (!slot) throw notFound('Parking slot not found in this society');
  if (!slot.isActive) throw badRequest('Parking slot is inactive', 'SLOT_INACTIVE');

  assertSlotVehicleCompatible(slot.parkingType, vehicle.vehicleType);

  try {
    const allocation = await withTransaction(async (session) => {
      const [doc] = await ParkingAllocationModel.create(
        [
          {
            societyId,
            flatId: flat._id,
            vehicleId: vehicle._id,
            parkingSlotId: slot._id,
            startsAt: input.startsAt ?? new Date(),
            status: 'ACTIVE',
            createdBy: actor.userId,
          },
        ],
        { session },
      );

      await writeAuditLog(
        {
          action: 'PARKING_ALLOCATED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'ParkingAllocation',
          targetId: String(doc._id),
          metadata: {
            flatId: String(flat._id),
            vehicleId: String(vehicle._id),
            parkingSlotId: String(slot._id),
            slotNumber: slot.slotNumber,
            registrationNumber: vehicle.registrationNumber,
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      return doc;
    });

    return serializeAllocation(allocation);
  } catch (error) {
    if (isDuplicateKeyError(error) || isTransientTransactionError(error)) {
      throw conflict(
        'Slot or vehicle already has an active parking allocation',
        'DUPLICATE_ALLOCATION',
      );
    }
    throw error;
  }
}

/** End every active allocation for a vehicle. Safe if none exist. */
export async function releaseActiveAllocationsForVehicle(
  societyId: string,
  vehicleId: string,
  actor: Actor,
  reason = 'Vehicle deactivated',
): Promise<number> {
  const active = await ParkingAllocationModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    vehicleId: parseObjectId(vehicleId, 'vehicleId'),
    status: 'ACTIVE',
  })
    .select('_id')
    .lean();
  for (const row of active) {
    await releaseParkingAllocation(societyId, String(row._id), reason, actor);
  }
  return active.length;
}

export async function releaseParkingAllocation(
  societyId: string,
  allocationId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const existing = await ParkingAllocationModel.findOne({
    _id: parseObjectId(allocationId, 'allocationId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!existing) throw notFound('Allocation not found');
  if (existing.status === 'ENDED') {
    return serializeAllocation(existing);
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await ParkingAllocationModel.findOneAndUpdate(
      { _id: existing._id, status: 'ACTIVE' },
      {
        $set: {
          status: 'ENDED',
          endsAt: new Date(),
          endedBy: actor.userId,
          endReason: reason,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      const current = await ParkingAllocationModel.findById(existing._id).session(session);
      if (current?.status === 'ENDED') return current;
      throw conflict('Allocation could not be released', 'ALLOCATION_CONFLICT');
    }

    await writeAuditLog(
      {
        action: 'PARKING_RELEASED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'ParkingAllocation',
        targetId: allocationId,
        metadata: {
          reason,
          parkingSlotId: String(claimed.parkingSlotId),
          vehicleId: String(claimed.vehicleId),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  return serializeAllocation(updated);
}

export async function listAllocations(
  societyId: string,
  query: {
    status?: string;
    flatId?: string;
    vehicleId?: string;
    parkingSlotId?: string;
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
  if (query.vehicleId) filter.vehicleId = parseObjectId(query.vehicleId, 'vehicleId');
  if (query.parkingSlotId) {
    filter.parkingSlotId = parseObjectId(query.parkingSlotId, 'parkingSlotId');
  }

  const [total, rows] = await Promise.all([
    ParkingAllocationModel.countDocuments(filter),
    ParkingAllocationModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeAllocation(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getAllocation(societyId: string, allocationId: string) {
  const doc = await ParkingAllocationModel.findOne({
    _id: parseObjectId(allocationId, 'allocationId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Allocation not found');
  return serializeAllocation(doc);
}

export async function listResidentParking(
  societyId: string,
  flatIds: string[],
  registeredUserId?: string,
) {
  if (flatIds.length === 0) return { items: [] };
  const rows = await ParkingAllocationModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    flatId: { $in: flatIds.map((id) => parseObjectId(id, 'flatId')) },
    status: 'ACTIVE',
  })
    .sort({ createdAt: -1 })
    .lean();

  const enriched = await Promise.all(
    rows.map(async (row) => {
      const [slot, vehicle] = await Promise.all([
        ParkingSlotModel.findById(row.parkingSlotId).lean(),
        VehicleModel.findById(row.vehicleId).lean(),
      ]);
      if (
        registeredUserId &&
        (!vehicle || String(vehicle.registeredUserId) !== registeredUserId)
      ) {
        return null;
      }
      return {
        ...serializeAllocation(row),
        slot: slot
          ? {
              id: String(slot._id),
              slotNumber: slot.slotNumber,
              parkingType: slot.parkingType,
              locationDescription: slot.locationDescription,
            }
          : undefined,
        vehicle: vehicle
          ? {
              id: String(vehicle._id),
              registrationNumber: vehicle.registrationNumber,
              vehicleType: vehicle.vehicleType,
            }
          : undefined,
      };
    }),
  );

  return { items: enriched.filter((item) => item !== null) };
}

export { serializeAllocation };
