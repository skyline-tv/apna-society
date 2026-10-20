import { withTransaction } from '../../../database/connection';
import { badRequest, conflict, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError, isTransientTransactionError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { VehicleLogModel } from '../models/vehicle-log.model';
import { VehicleModel, type VehicleType } from '../models/vehicle.model';
import {
  assertValidRegistrationNumber,
  normalizeRegistrationNumber,
} from '../utils/registration-number';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeLog(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  vehicleId?: { toString(): string };
  flatId?: { toString(): string };
  registrationNumber: string;
  vehicleType: string;
  status: string;
  entryAt: Date;
  exitAt?: Date;
  guardUserId: { toString(): string };
  checkedOutBy?: { toString(): string };
  notes?: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    vehicleId: doc.vehicleId ? String(doc.vehicleId) : undefined,
    flatId: doc.flatId ? String(doc.flatId) : undefined,
    registrationNumber: doc.registrationNumber,
    vehicleType: doc.vehicleType,
    status: doc.status,
    entryAt: doc.entryAt.toISOString(),
    exitAt: doc.exitAt?.toISOString(),
    guardUserId: String(doc.guardUserId),
    checkedOutBy: doc.checkedOutBy ? String(doc.checkedOutBy) : undefined,
    notes: doc.notes,
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
    /** Explicitly not a resident vehicle registration when vehicleId is absent. */
    isRegisteredResidentVehicle: Boolean(doc.vehicleId),
  };
}

export async function recordVehicleEntry(
  societyId: string,
  guardUserId: string,
  input: {
    registrationNumber: string;
    vehicleType?: VehicleType;
    vehicleId?: string;
    notes?: string;
  },
  actor: Actor,
) {
  let registrationNumber: string;
  try {
    registrationNumber = assertValidRegistrationNumber(input.registrationNumber);
  } catch {
    throw badRequest('Invalid Indian vehicle registration number', 'INVALID_REGISTRATION_NUMBER');
  }

  let vehicleId: string | undefined;
  let flatId: string | undefined;
  let vehicleType: VehicleType = input.vehicleType ?? 'OTHER';

  if (input.vehicleId) {
    const vehicle = await VehicleModel.findOne({
      _id: parseObjectId(input.vehicleId, 'vehicleId'),
      societyId: parseObjectId(societyId, 'societyId'),
      isActive: true,
    }).lean();
    if (!vehicle) throw notFound('Registered vehicle not found in this society');
    if (vehicle.registrationNumber !== registrationNumber) {
      throw badRequest(
        'Registration number does not match the selected vehicle',
        'REGISTRATION_MISMATCH',
      );
    }
    vehicleId = String(vehicle._id);
    flatId = String(vehicle.flatId);
    vehicleType = vehicle.vehicleType;
  } else {
    // Optional lookup — never auto-creates a resident vehicle from a visitor/unregistered plate.
    const registered = await VehicleModel.findOne({
      societyId,
      registrationNumber,
      isActive: true,
    }).lean();
    if (registered) {
      vehicleId = String(registered._id);
      flatId = String(registered.flatId);
      vehicleType = registered.vehicleType;
    } else if (!input.vehicleType) {
      throw badRequest(
        'vehicleType is required for unregistered vehicles',
        'VEHICLE_TYPE_REQUIRED',
      );
    }
  }

  try {
    const log = await withTransaction(async (session) => {
      const [doc] = await VehicleLogModel.create(
        [
          {
            societyId,
            vehicleId,
            flatId,
            registrationNumber,
            vehicleType,
            status: 'INSIDE',
            entryAt: new Date(),
            guardUserId,
            notes: input.notes,
          },
        ],
        { session },
      );

      await writeAuditLog(
        {
          action: 'VEHICLE_ENTRY',
          actorUserId: actor.userId,
          societyId,
          targetType: 'VehicleLog',
          targetId: String(doc._id),
          metadata: {
            registrationNumber,
            vehicleId,
            flatId,
            isRegisteredResidentVehicle: Boolean(vehicleId),
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      return doc;
    });

    return serializeLog(log);
  } catch (error) {
    if (isDuplicateKeyError(error) || isTransientTransactionError(error)) {
      throw conflict(
        'This registration already has an active entry in the society',
        'DUPLICATE_ACTIVE_ENTRY',
      );
    }
    throw error;
  }
}

export async function recordVehicleExit(
  societyId: string,
  guardUserId: string,
  input: { logId?: string; registrationNumber?: string },
  actor: Actor,
) {
  let log;
  if (input.logId) {
    log = await VehicleLogModel.findOne({
      _id: parseObjectId(input.logId, 'logId'),
      societyId: parseObjectId(societyId, 'societyId'),
    });
  } else if (input.registrationNumber) {
    const registrationNumber = normalizeRegistrationNumber(input.registrationNumber);
    log = await VehicleLogModel.findOne({
      societyId,
      registrationNumber,
      status: 'INSIDE',
    });
  } else {
    throw badRequest('logId or registrationNumber is required', 'VALIDATION_ERROR');
  }

  if (!log) throw notFound('Active vehicle entry not found');
  if (log.status === 'EXITED') {
    return serializeLog(log);
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await VehicleLogModel.findOneAndUpdate(
      { _id: log!._id, status: 'INSIDE' },
      {
        $set: {
          status: 'EXITED',
          exitAt: new Date(),
          checkedOutBy: guardUserId,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      const current = await VehicleLogModel.findById(log!._id).session(session);
      if (current?.status === 'EXITED') return current;
      throw conflict('Vehicle exit conflict', 'EXIT_CONFLICT');
    }

    await writeAuditLog(
      {
        action: 'VEHICLE_EXIT',
        actorUserId: actor.userId,
        societyId,
        targetType: 'VehicleLog',
        targetId: String(claimed._id),
        metadata: {
          registrationNumber: claimed.registrationNumber,
          exitAt: claimed.exitAt?.toISOString(),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  return serializeLog(updated);
}

export async function listVehicleLogs(
  societyId: string,
  query: {
    status?: string;
    registrationNumber?: string;
    vehicleId?: string;
    from?: Date;
    to?: Date;
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
  if (query.vehicleId) filter.vehicleId = parseObjectId(query.vehicleId, 'vehicleId');
  if (query.registrationNumber) {
    filter.registrationNumber = normalizeRegistrationNumber(query.registrationNumber);
  }
  if (query.from || query.to) {
    filter.entryAt = {};
    if (query.from) (filter.entryAt as Record<string, Date>).$gte = query.from;
    if (query.to) (filter.entryAt as Record<string, Date>).$lte = query.to;
  }

  const [total, rows] = await Promise.all([
    VehicleLogModel.countDocuments(filter),
    VehicleLogModel.find(filter)
      .sort({ entryAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeLog(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}
