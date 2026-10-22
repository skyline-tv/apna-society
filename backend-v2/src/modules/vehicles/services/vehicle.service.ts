import type { ClientSession } from 'mongoose';
import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../../society/models/flat.model';
import { SocietyModel } from '../../society/models/society.model';
import { WingModel } from '../../society/models/wing.model';
import { UserModel } from '../../users/models/user.model';
import { assertResidentialAccess } from '../../users/services/access-control.service';
import { VehicleModel, type VehicleType } from '../models/vehicle.model';
import { ParkingAllocationModel } from '../models/parking-allocation.model';
import {
  assertValidRegistrationNumber,
  normalizeRegistrationNumber,
} from '../utils/registration-number';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

export type VehicleDraftInput = {
  vehicleType: VehicleType;
  registrationNumber: string;
  make?: string;
  model?: string;
  colour?: string;
};

export type PreparedVehicleDraft = VehicleDraftInput & { registrationNumber: string };

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

export function prepareVehicleDrafts(drafts: VehicleDraftInput[]): PreparedVehicleDraft[] {
  const seen = new Set<string>();
  const prepared: PreparedVehicleDraft[] = [];
  for (const draft of drafts) {
    let registrationNumber: string;
    try {
      registrationNumber = assertValidRegistrationNumber(draft.registrationNumber);
    } catch {
      throw badRequest(
        'Invalid Indian vehicle registration number',
        'INVALID_REGISTRATION_NUMBER',
      );
    }
    if (seen.has(registrationNumber)) {
      throw conflict(
        'An active vehicle with this registration already exists in the society',
        'DUPLICATE_VEHICLE',
      );
    }
    seen.add(registrationNumber);
    prepared.push({
      vehicleType: draft.vehicleType,
      registrationNumber,
      make: draft.make?.trim() || undefined,
      model: draft.model?.trim() || undefined,
      colour: draft.colour?.trim() || undefined,
    });
  }
  return prepared;
}

export async function assertNoActiveDuplicatePlates(
  societyId: string,
  registrationNumbers: string[],
  session?: ClientSession,
) {
  if (registrationNumbers.length === 0) return;
  const existing = await VehicleModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
    registrationNumber: { $in: registrationNumbers },
  })
    .select('registrationNumber')
    .session(session ?? null)
    .lean();
  if (existing.length > 0) {
    throw conflict(
      'An active vehicle with this registration already exists in the society',
      'DUPLICATE_VEHICLE',
    );
  }
}

function assertUserOccupiesFlat(
  flat: { activeOwnerUserId?: { toString(): string }; activeTenantUserId?: { toString(): string } },
  userId: string,
) {
  const ownerId = flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : '';
  const tenantId = flat.activeTenantUserId ? String(flat.activeTenantUserId) : '';
  if (ownerId !== userId && tenantId !== userId) {
    throw forbidden(
      'User is not the active owner or tenant of this flat',
      'NOT_FLAT_OCCUPANT',
    );
  }
}

/**
 * Creates Vehicle documents on the existing collection, linked to society, flat, and resident.
 * When `session` is provided, writes join that transaction so occupancy can roll back with them.
 */
export async function insertResidentVehicles(
  societyId: string,
  input: {
    flatId: string;
    registeredUserId: string;
    vehicles: VehicleDraftInput[];
  },
  actor: Actor,
  options?: {
    session?: ClientSession;
    occupantConfirmed?: boolean;
  },
) {
  if (input.vehicles.length === 0) return [];
  const drafts = prepareVehicleDrafts(input.vehicles);

  const run = async (session: ClientSession) => {
    const flat = await FlatModel.findOne({
      _id: parseObjectId(input.flatId, 'flatId'),
      societyId: parseObjectId(societyId, 'societyId'),
      isActive: true,
    }).session(session);
    if (!flat) throw notFound('Flat not found');

    if (!options?.occupantConfirmed) {
      assertUserOccupiesFlat(flat, input.registeredUserId);
    }

    await assertNoActiveDuplicatePlates(
      societyId,
      drafts.map((d) => d.registrationNumber),
      session,
    );

    const created = [];
    for (const draft of drafts) {
      const [doc] = await VehicleModel.create(
        [
          {
            societyId,
            flatId: flat._id,
            registeredUserId: input.registeredUserId,
            vehicleType: draft.vehicleType,
            registrationNumber: draft.registrationNumber,
            make: draft.make,
            vehicleModel: draft.model,
            colour: draft.colour,
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
            registeredUserId: input.registeredUserId,
            registrationNumber: doc.registrationNumber,
            vehicleType: doc.vehicleType,
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );
      created.push(serializeVehicle(doc));
    }
    return created;
  };

  try {
    if (options?.session) {
      return await run(options.session);
    }
    return await withTransaction(async (session) => run(session));
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
  await assertResidentialAccess({ userId, societyId, flatId: input.flatId });
  const [vehicle] = await insertResidentVehicles(
    societyId,
    {
      flatId: input.flatId,
      registeredUserId: userId,
      vehicles: [input],
    },
    actor,
    { occupantConfirmed: true },
  );
  return vehicle;
}

export async function adminRegisterVehicle(
  societyId: string,
  input: {
    flatId: string;
    registeredUserId: string;
    vehicleType: VehicleType;
    registrationNumber: string;
    make?: string;
    model?: string;
    colour?: string;
  },
  actor: Actor,
) {
  const [vehicle] = await insertResidentVehicles(
    societyId,
    {
      flatId: input.flatId,
      registeredUserId: input.registeredUserId,
      vehicles: [input],
    },
    actor,
  );
  return vehicle;
}

export function assertResidentVehicleReadOnly(): never {
  throw forbidden(
    'Residents can only view registered vehicles. Ask the society admin to add or change vehicle details.',
    'RESIDENT_VEHICLE_READ_ONLY',
  );
}

export async function listResidentVehicles(societyId: string, userId: string) {
  const vehicles = await VehicleModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    registeredUserId: parseObjectId(userId, 'userId'),
  })
    .sort({ createdAt: -1 })
    .lean();

  const labeled = await enrichAdminVehicles(societyId, vehicles);

  const withParking = await Promise.all(
    labeled.map(async (item, index) => {
      const allocation = await ParkingAllocationModel.findOne({
        societyId,
        vehicleId: vehicles[index]._id,
        status: 'ACTIVE',
      }).lean();
      return {
        ...item,
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
    registeredUserId: parseObjectId(userId, 'userId'),
  }).lean();
  if (!vehicle) throw notFound('Vehicle not found');

  const [labeled] = await enrichAdminVehicles(societyId, [vehicle]);
  const allocation = await ParkingAllocationModel.findOne({
    societyId,
    vehicleId: vehicle._id,
    status: 'ACTIVE',
  }).lean();

  return {
    ...labeled,
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

export async function adminUpdateVehicle(
  societyId: string,
  vehicleId: string,
  input: {
    make?: string;
    model?: string;
    colour?: string;
    vehicleType?: VehicleType;
    registrationNumber?: string;
  },
  actor: Actor,
) {
  const vehicle = await VehicleModel.findOne({
    _id: parseObjectId(vehicleId, 'vehicleId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!vehicle) throw notFound('Vehicle not found');
  if (!vehicle.isActive) throw badRequest('Vehicle is deactivated', 'VEHICLE_INACTIVE');

  if (input.make !== undefined) vehicle.make = input.make.trim();
  if (input.model !== undefined) vehicle.vehicleModel = input.model.trim();
  if (input.colour !== undefined) vehicle.colour = input.colour.trim();
  if (input.vehicleType !== undefined) vehicle.vehicleType = input.vehicleType;
  if (input.registrationNumber !== undefined) {
    try {
      vehicle.registrationNumber = assertValidRegistrationNumber(input.registrationNumber);
    } catch {
      throw badRequest(
        'Invalid Indian vehicle registration number',
        'INVALID_REGISTRATION_NUMBER',
      );
    }
  }

  try {
    await vehicle.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict(
        'An active vehicle with this registration already exists in the society',
        'DUPLICATE_VEHICLE',
      );
    }
    throw error;
  }

  await writeAuditLog({
    action: 'VEHICLE_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Vehicle',
    targetId: vehicleId,
    metadata: { ...input, registeredUserId: String(vehicle.registeredUserId) },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeVehicle(vehicle);
}

export async function adminDeactivateVehicle(
  societyId: string,
  vehicleId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const vehicle = await VehicleModel.findOne({
    _id: parseObjectId(vehicleId, 'vehicleId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!vehicle) throw notFound('Vehicle not found');

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
    registeredUserId?: string;
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
  if (query.registeredUserId) {
    filter.registeredUserId = parseObjectId(query.registeredUserId, 'registeredUserId');
  }
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

  const items = await enrichAdminVehicles(societyId, rows);

  return {
    items,
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

async function enrichAdminVehicles(
  societyId: string,
  rows: Array<{
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
  }>,
) {
  if (rows.length === 0) return [];

  const userIds = [...new Set(rows.map((r) => String(r.registeredUserId)))];
  const flatIds = [...new Set(rows.map((r) => String(r.flatId)))];

  const [society, users, flats] = await Promise.all([
    SocietyModel.findById(societyId).select('name code').lean(),
    UserModel.find({ _id: { $in: userIds } }).select('name').lean(),
    FlatModel.find({ _id: { $in: flatIds } }).select('number wingId').lean(),
  ]);

  const wingIds = [...new Set(flats.map((f) => String(f.wingId)))];
  const wings = wingIds.length
    ? await WingModel.find({ _id: { $in: wingIds } }).select('code').lean()
    : [];

  const userName = new Map(users.map((u) => [String(u._id), u.name]));
  const wingCode = new Map(wings.map((w) => [String(w._id), w.code]));
  const flatInfo = new Map(
    flats.map((f) => [
      String(f._id),
      { number: f.number, wingCode: wingCode.get(String(f.wingId)) },
    ]),
  );

  return rows.map((row) => {
    const flat = flatInfo.get(String(row.flatId));
    return {
      ...serializeVehicle(row),
      residentName: userName.get(String(row.registeredUserId)),
      flatNumber: flat?.number,
      wingCode: flat?.wingCode,
      societyName: society?.name,
      societyCode: society?.code,
    };
  });
}

export { serializeVehicle, normalizeRegistrationNumber };
