import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../../society/models/flat.model';
import {
  assertResidentialAccess,
  getFlatAccess,
} from '../../users/services/access-control.service';
import { VehicleModel, type VehicleType } from '../models/vehicle.model';
import { ParkingAllocationModel } from '../models/parking-allocation.model';
import {
  assertValidRegistrationNumber,
  normalizeRegistrationNumber,
} from '../utils/registration-number';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeVehicle(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  registeredUserId: { toString(): string };
  vehicleType: string;
  registrationNumber: string;
  make?: string;
  vehicleModel?: string;
  colour?: string;
  isActive: boolean;
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    registeredUserId: String(doc.registeredUserId),
    vehicleType: doc.vehicleType,
    registrationNumber: doc.registrationNumber,
    make: doc.make,
    model: doc.vehicleModel,
    colour: doc.colour,
    isActive: doc.isActive,
    deactivatedAt: doc.deactivatedAt?.toISOString(),
    deactivationReason: doc.deactivationReason,
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

export async function registerVehicle(
  societyId: string,
  userId: string,
  input: {
    flatId: string;
    vehicleType: VehicleType;
    registrationNumber: string;
    make?: string;
    model?: string;
    colour?: string;
  },
  actor: Actor,
) {
  let registrationNumber: string;
  try {
    registrationNumber = assertValidRegistrationNumber(input.registrationNumber);
  } catch {
    throw badRequest('Invalid Indian vehicle registration number', 'INVALID_REGISTRATION_NUMBER');
  }

  await assertResidentialAccess({ userId, societyId, flatId: input.flatId });

  const flat = await FlatModel.findOne({
    _id: parseObjectId(input.flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
  }).lean();
  if (!flat) throw notFound('Flat not found');

  try {
    const vehicle = await withTransaction(async (session) => {
      const [doc] = await VehicleModel.create(
        [
          {
            societyId,
            flatId: flat._id,
            registeredUserId: userId,
            vehicleType: input.vehicleType,
            registrationNumber,
            make: input.make?.trim(),
            vehicleModel: input.model?.trim(),
            colour: input.colour?.trim(),
            isActive: true,
          },
        ],
        { session },
      );

      await writeAuditLog(
        {
          action: 'VEHICLE_REGISTERED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'Vehicle',
          targetId: String(doc._id),
          metadata: {
            flatId: String(flat._id),
            registrationNumber,
            vehicleType: input.vehicleType,
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );
      return doc;
    });
    return serializeVehicle(vehicle);
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict(
        'An active vehicle with this registration already exists in the society',
        'DUPLICATE_VEHICLE',
      );
    }
    throw error;
  }
}

export async function listResidentVehicles(societyId: string, userId: string) {
  const flats = await FlatModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
    $or: [{ activeOwnerUserId: userId }, { activeTenantUserId: userId }],
  })
    .select('_id occupancyStatus activeOwnerUserId activeTenantUserId')
    .lean();

  const accessibleFlatIds: string[] = [];
  for (const flat of flats) {
    const access = await getFlatAccess({
      userId,
      societyId,
      flatId: String(flat._id),
    });
    if (access.residential) accessibleFlatIds.push(String(flat._id));
  }

  if (accessibleFlatIds.length === 0) {
    return { items: [] };
  }

  const vehicles = await VehicleModel.find({
    societyId,
    flatId: { $in: accessibleFlatIds },
  })
    .sort({ createdAt: -1 })
    .lean();

  const withParking = await Promise.all(
    vehicles.map(async (v) => {
      const allocation = await ParkingAllocationModel.findOne({
        societyId,
        vehicleId: v._id,
        status: 'ACTIVE',
      }).lean();
      return {
        ...serializeVehicle(v),
        activeAllocationId: allocation ? String(allocation._id) : undefined,
        parkingSlotId: allocation ? String(allocation.parkingSlotId) : undefined,
      };
    }),
  );

  return { items: withParking };
}

export async function getResidentVehicle(
  societyId: string,
  userId: string,
  vehicleId: string,
) {
  const vehicle = await VehicleModel.findOne({
    _id: parseObjectId(vehicleId, 'vehicleId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!vehicle) throw notFound('Vehicle not found');

  await assertResidentialAccess({
    userId,
    societyId,
    flatId: String(vehicle.flatId),
  });

  const allocation = await ParkingAllocationModel.findOne({
    societyId,
    vehicleId: vehicle._id,
    status: 'ACTIVE',
  }).lean();

  return {
    ...serializeVehicle(vehicle),
    activeAllocationId: allocation ? String(allocation._id) : undefined,
    parkingSlotId: allocation ? String(allocation.parkingSlotId) : undefined,
  };
}

export async function updateResidentVehicle(
  societyId: string,
  userId: string,
  vehicleId: string,
  input: { make?: string; model?: string; colour?: string; vehicleType?: VehicleType },
  actor: Actor,
) {
  const vehicle = await VehicleModel.findOne({
    _id: parseObjectId(vehicleId, 'vehicleId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!vehicle) throw notFound('Vehicle not found');
  if (!vehicle.isActive) throw badRequest('Vehicle is deactivated', 'VEHICLE_INACTIVE');

  await assertResidentialAccess({
    userId,
    societyId,
    flatId: String(vehicle.flatId),
  });

  if (input.make !== undefined) vehicle.make = input.make.trim();
  if (input.model !== undefined) vehicle.vehicleModel = input.model.trim();
  if (input.colour !== undefined) vehicle.colour = input.colour.trim();
  if (input.vehicleType !== undefined) vehicle.vehicleType = input.vehicleType;
  await vehicle.save();

  await writeAuditLog({
    action: 'VEHICLE_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Vehicle',
    targetId: vehicleId,
    metadata: { ...input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeVehicle(vehicle);
}

export async function deactivateResidentVehicle(
  societyId: string,
  userId: string,
  vehicleId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const vehicle = await VehicleModel.findOne({
    _id: parseObjectId(vehicleId, 'vehicleId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!vehicle) throw notFound('Vehicle not found');

  await assertResidentialAccess({
    userId,
    societyId,
    flatId: String(vehicle.flatId),
  });

  if (!vehicle.isActive) {
    return serializeVehicle(vehicle);
  }

  const activeAllocation = await ParkingAllocationModel.findOne({
    societyId,
    vehicleId: vehicle._id,
    status: 'ACTIVE',
  }).lean();
  if (activeAllocation) {
    throw conflict(
      'Release the active parking allocation before deactivating the vehicle',
      'VEHICLE_HAS_ALLOCATION',
    );
  }

  vehicle.isActive = false;
  vehicle.deactivatedAt = new Date();
  vehicle.deactivationReason = reason;
  await vehicle.save();

  await writeAuditLog({
    action: 'VEHICLE_DEACTIVATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Vehicle',
    targetId: vehicleId,
    metadata: { reason, registrationNumber: vehicle.registrationNumber },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeVehicle(vehicle);
}

export async function listAdminVehicles(
  societyId: string,
  query: {
    flatId?: string;
    isActive?: boolean;
    registrationNumber?: string;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.isActive !== undefined) filter.isActive = query.isActive;
  if (query.registrationNumber) {
    filter.registrationNumber = normalizeRegistrationNumber(query.registrationNumber);
  }

  const [total, rows] = await Promise.all([
    VehicleModel.countDocuments(filter),
    VehicleModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeVehicle(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export { serializeVehicle, normalizeRegistrationNumber };
