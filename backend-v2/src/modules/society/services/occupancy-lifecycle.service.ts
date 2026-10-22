import type { ClientSession } from 'mongoose';
import type { OccupancyStatus } from '../../../config/constants';
import { withTransaction } from '../../../database/connection';
import { AppError, badRequest, conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError, mapMongoWriteError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { MembershipModel } from '../../users/models/membership.model';
import { UserModel } from '../../users/models/user.model';
import { FlatModel } from '../models/flat.model';
import { OccupancyRecordModel } from '../models/occupancy-record.model';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

/** Test-only hooks. Cleared automatically; never enable outside NODE_ENV=test. */
export const occupancyTestHooks: {
  failAfter?: 'occupancy_created' | 'membership_upserted' | null;
} = {
  failAfter: null,
};

export function resetOccupancyTestHooks(): void {
  occupancyTestHooks.failAfter = null;
}

function maybeFailTestHook(step: 'occupancy_created' | 'membership_upserted'): void {
  if (process.env.NODE_ENV === 'test' && occupancyTestHooks.failAfter === step) {
    throw new Error(`TEST_FORCED_TRANSACTION_FAILURE:${step}`);
  }
}

export interface AssignOccupancyInput {
  userId: string;
  effectiveFrom: string | Date;
  notes?: string;
  vehicles?: Array<{
    vehicleType: 'TWO_WHEELER' | 'FOUR_WHEELER' | 'OTHER';
    registrationNumber: string;
    make?: string;
    model?: string;
    colour?: string;
  }>;
}

export interface EndOccupancyInput {
  effectiveTo: string | Date;
  reason: string;
  notes?: string;
}

function parseDate(value: string | Date, field: string): Date {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw badRequest(`Invalid ${field}`, 'INVALID_DATE');
  }
  return date;
}

function deriveStatus(ownerId?: string | null, tenantId?: string | null): OccupancyStatus {
  if (ownerId && tenantId) return 'TENANT_OCCUPIED';
  if (ownerId) return 'OWNER_OCCUPIED';
  return 'VACANT';
}

function rethrowOccupancyError(error: unknown, duplicateMessage: string): never {
  if (error instanceof AppError) {
    throw error;
  }
  // Preserve intentional test-only failures for rollback assertions.
  if (error instanceof Error && error.message.startsWith('TEST_FORCED_TRANSACTION_FAILURE')) {
    throw error;
  }
  if (isDuplicateKeyError(error)) {
    throw conflict(duplicateMessage, 'DUPLICATE_ACTIVE_ASSIGNMENT');
  }
  mapMongoWriteError(error, duplicateMessage);
}

async function loadActiveFlat(societyId: string, flatId: string, session: ClientSession) {
  const flat = await FlatModel.findOne({
    _id: parseObjectId(flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).session(session);

  if (!flat) {
    throw notFound('Flat not found');
  }
  if (!flat.isActive) {
    throw forbidden('Flat is inactive', 'FLAT_INACTIVE');
  }
  return flat;
}

async function loadActiveResident(
  societyId: string,
  userId: string,
  role: 'OWNER' | 'TENANT',
  session: ClientSession,
) {
  const user = await UserModel.findById(parseObjectId(userId, 'userId')).session(session);
  if (!user) {
    throw notFound('User not found');
  }
  if (!user.isActive || !user.canLogin) {
    throw forbidden('User is inactive', 'USER_INACTIVE');
  }
  if (!user.roles.includes(role)) {
    throw forbidden(`User does not have the ${role} role`, 'INVALID_RESIDENT_ROLE');
  }

  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: user._id,
    isActive: true,
  })
    .session(session)
    .select('_id')
    .lean();

  if (!membership) {
    throw forbidden('User is not a member of this society', 'SOCIETY_MISMATCH');
  }

  return user;
}

async function assertNoActiveUserAssignment(
  societyId: string,
  userId: string,
  role: 'OWNER' | 'TENANT',
  session: ClientSession,
): Promise<void> {
  const existing = await OccupancyRecordModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(userId, 'userId'),
    role,
    status: 'ACTIVE',
  }).session(session);

  if (existing) {
    throw conflict(
      `User already has an active ${role.toLowerCase()} assignment in this society`,
      'DUPLICATE_ACTIVE_ASSIGNMENT',
    );
  }
}

async function upsertActiveMembership(
  input: {
    societyId: string;
    userId: string;
    role: 'OWNER' | 'TENANT';
    flatId: string;
    wingId: string;
    startsAt: Date;
  },
  session: ClientSession,
): Promise<void> {
  const existing = await MembershipModel.findOne({
    societyId: input.societyId,
    userId: input.userId,
    role: input.role,
    flatId: input.flatId,
    isActive: true,
  }).session(session);

  if (existing) {
    return;
  }

  await MembershipModel.create(
    [
      {
        societyId: input.societyId,
        userId: input.userId,
        role: input.role,
        flatId: input.flatId,
        wingId: input.wingId,
        isActive: true,
        startsAt: input.startsAt,
      },
    ],
    { session },
  );
}

async function endActiveMembership(
  input: {
    societyId: string;
    userId: string;
    role: 'OWNER' | 'TENANT';
    flatId: string;
    endsAt: Date;
  },
  session: ClientSession,
): Promise<void> {
  await MembershipModel.updateMany(
    {
      societyId: input.societyId,
      userId: input.userId,
      role: input.role,
      flatId: input.flatId,
      isActive: true,
    },
    { $set: { isActive: false, endsAt: input.endsAt } },
    { session },
  );
}

function assertTransitionAllowed(from: OccupancyStatus, to: OccupancyStatus, action: string): void {
  const allowed: Record<OccupancyStatus, OccupancyStatus[]> = {
    VACANT: ['OWNER_OCCUPIED'],
    OWNER_OCCUPIED: ['TENANT_OCCUPIED', 'VACANT'],
    TENANT_OCCUPIED: ['OWNER_OCCUPIED', 'VACANT'],
  };

  if (from === to) {
    return;
  }
  if (!allowed[from].includes(to)) {
    throw forbidden(
      `Unsupported occupancy transition ${from} → ${to} for ${action}`,
      'INVALID_OCCUPANCY_TRANSITION',
    );
  }
}

async function afterOccupancyCommit(societyId: string): Promise<void> {
  const { invalidateOccupancyCaches, invalidateFinancialCaches } = await import(
    '../../../cache/cache-invalidation'
  );
  await Promise.all([
    invalidateOccupancyCaches(societyId),
    invalidateFinancialCaches(societyId),
  ]);
}

export async function assignOwner(
  societyId: string,
  flatId: string,
  input: AssignOccupancyInput,
  actor: Actor,
) {
  const effectiveFrom = parseDate(input.effectiveFrom, 'effectiveFrom');

  try {
    const result = await withTransaction(async (session) => {
      const flat = await loadActiveFlat(societyId, flatId, session);
      const user = await loadActiveResident(societyId, input.userId, 'OWNER', session);

      if (flat.occupancyStatus !== 'VACANT' || flat.activeOwnerUserId) {
        throw conflict(
          'Flat already has an active owner. End the current owner occupancy first.',
          'ACTIVE_OWNER_EXISTS',
        );
      }
      if (flat.activeTenantUserId) {
        throw conflict('Vacant flat cannot have an active tenant', 'INCONSISTENT_FLAT_STATE');
      }

      await assertNoActiveUserAssignment(societyId, String(user._id), 'OWNER', session);
      assertTransitionAllowed(flat.occupancyStatus, 'OWNER_OCCUPIED', 'assign-owner');

      await OccupancyRecordModel.create(
        [
          {
            societyId: flat.societyId,
            flatId: flat._id,
            userId: user._id,
            role: 'OWNER',
            status: 'ACTIVE',
            startsAt: effectiveFrom,
            notes: input.notes,
          },
        ],
        { session },
      );
      maybeFailTestHook('occupancy_created');

      await upsertActiveMembership(
        {
          societyId,
          userId: String(user._id),
          role: 'OWNER',
          flatId,
          wingId: String(flat.wingId),
          startsAt: effectiveFrom,
        },
        session,
      );
      maybeFailTestHook('membership_upserted');

      if (!user.primarySocietyId) {
        user.primarySocietyId = flat.societyId;
        await user.save({ session });
      }

      flat.activeOwnerUserId = user._id;
      flat.set('activeTenantUserId', undefined);
      flat.occupancyStatus = 'OWNER_OCCUPIED';
      await flat.save({ session });

      const { attachUnassignedBillsToOwner } = await import(
        '../../billing/services/bill-generation.service'
      );
      await attachUnassignedBillsToOwner(
        societyId,
        flatId,
        { _id: user._id, name: user.name, email: user.email },
        actor,
        session,
      );

      await writeAuditLog(
        {
          action: 'OWNER_ASSIGNED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'Flat',
          targetId: flatId,
          metadata: {
            userId: String(user._id),
            effectiveFrom: effectiveFrom.toISOString(),
            notes: input.notes,
            vehicleCount: input.vehicles?.length ?? 0,
            before: { occupancyStatus: 'VACANT' },
            after: { occupancyStatus: 'OWNER_OCCUPIED' },
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      let vehicles: Array<Record<string, unknown>> = [];
      if (input.vehicles?.length) {
        const { insertResidentVehicles } = await import(
          '../../vehicles/services/vehicle.service'
        );
        vehicles = await insertResidentVehicles(
          societyId,
          {
            flatId,
            registeredUserId: String(user._id),
            vehicles: input.vehicles,
          },
          actor,
          { session, occupantConfirmed: true },
        );
      }

      return {
        flatId,
        occupancyStatus: 'OWNER_OCCUPIED' as OccupancyStatus,
        activeOwnerUserId: String(user._id),
        activeTenantUserId: null as string | null,
        ...(vehicles.length ? { vehicles } : {}),
      };
    });
    await afterOccupancyCommit(societyId);
    return result;
  } catch (error) {
    rethrowOccupancyError(error, 'Active owner assignment already exists');
  }
}

export async function assignTenant(
  societyId: string,
  flatId: string,
  input: AssignOccupancyInput,
  actor: Actor,
) {
  const effectiveFrom = parseDate(input.effectiveFrom, 'effectiveFrom');

  try {
    const result = await withTransaction(async (session) => {
      const flat = await loadActiveFlat(societyId, flatId, session);
      const user = await loadActiveResident(societyId, input.userId, 'TENANT', session);

      if (flat.activeTenantUserId || flat.occupancyStatus === 'TENANT_OCCUPIED') {
        throw conflict(
          'Flat already has an active tenant. End the current tenant occupancy first.',
          'ACTIVE_TENANT_EXISTS',
        );
      }
      if (flat.occupancyStatus !== 'OWNER_OCCUPIED' || !flat.activeOwnerUserId) {
        throw forbidden(
          'Tenant can only be assigned to an owner-occupied flat',
          'INVALID_OCCUPANCY_TRANSITION',
        );
      }
      if (String(flat.activeOwnerUserId) === String(user._id)) {
        throw badRequest('Owner cannot be assigned as tenant of the same flat', 'OWNER_TENANT_SAME');
      }

      await assertNoActiveUserAssignment(societyId, String(user._id), 'TENANT', session);
      assertTransitionAllowed(flat.occupancyStatus, 'TENANT_OCCUPIED', 'assign-tenant');

      await OccupancyRecordModel.create(
        [
          {
            societyId: flat.societyId,
            flatId: flat._id,
            userId: user._id,
            role: 'TENANT',
            status: 'ACTIVE',
            startsAt: effectiveFrom,
            notes: input.notes,
          },
        ],
        { session },
      );
      maybeFailTestHook('occupancy_created');

      await upsertActiveMembership(
        {
          societyId,
          userId: String(user._id),
          role: 'TENANT',
          flatId,
          wingId: String(flat.wingId),
          startsAt: effectiveFrom,
        },
        session,
      );
      maybeFailTestHook('membership_upserted');

      if (!user.primarySocietyId) {
        user.primarySocietyId = flat.societyId;
        await user.save({ session });
      }

      const before = flat.occupancyStatus;
      flat.activeTenantUserId = user._id;
      flat.occupancyStatus = 'TENANT_OCCUPIED';
      await flat.save({ session });

      await writeAuditLog(
        {
          action: 'TENANT_ASSIGNED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'Flat',
          targetId: flatId,
          metadata: {
            userId: String(user._id),
            ownerUserId: String(flat.activeOwnerUserId),
            effectiveFrom: effectiveFrom.toISOString(),
            notes: input.notes,
            vehicleCount: input.vehicles?.length ?? 0,
            before: { occupancyStatus: before },
            after: { occupancyStatus: 'TENANT_OCCUPIED' },
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      let vehicles: Array<Record<string, unknown>> = [];
      if (input.vehicles?.length) {
        const { insertResidentVehicles } = await import(
          '../../vehicles/services/vehicle.service'
        );
        vehicles = await insertResidentVehicles(
          societyId,
          {
            flatId,
            registeredUserId: String(user._id),
            vehicles: input.vehicles,
          },
          actor,
          { session, occupantConfirmed: true },
        );
      }

      return {
        flatId,
        occupancyStatus: 'TENANT_OCCUPIED' as OccupancyStatus,
        activeOwnerUserId: String(flat.activeOwnerUserId),
        activeTenantUserId: String(user._id),
        ...(vehicles.length ? { vehicles } : {}),
      };
    });
    await afterOccupancyCommit(societyId);
    return result;
  } catch (error) {
    rethrowOccupancyError(error, 'Active tenant assignment already exists');
  }
}

export async function endTenantOccupancy(
  societyId: string,
  flatId: string,
  input: EndOccupancyInput,
  actor: Actor,
) {
  const effectiveTo = parseDate(input.effectiveTo, 'effectiveTo');

  try {
    const result = await withTransaction(async (session) => {
      const flat = await loadActiveFlat(societyId, flatId, session);

      if (flat.occupancyStatus !== 'TENANT_OCCUPIED' || !flat.activeTenantUserId) {
        throw conflict('Flat does not have an active tenant occupancy', 'NO_ACTIVE_TENANT');
      }

      const record = await OccupancyRecordModel.findOne({
        societyId: flat.societyId,
        flatId: flat._id,
        role: 'TENANT',
        status: 'ACTIVE',
      }).session(session);

      if (!record) {
        throw conflict('Active tenant occupancy record not found', 'NO_ACTIVE_TENANT');
      }
      if (effectiveTo.getTime() < record.startsAt.getTime()) {
        throw badRequest('effectiveTo cannot be earlier than occupancy start', 'INVALID_DATE_RANGE');
      }

      record.status = 'ENDED';
      record.endsAt = effectiveTo;
      record.endReason = input.reason;
      if (input.notes) record.notes = input.notes;
      await record.save({ session });

      await endActiveMembership(
        {
          societyId,
          userId: String(record.userId),
          role: 'TENANT',
          flatId,
          endsAt: effectiveTo,
        },
        session,
      );

      const before = flat.occupancyStatus;
      flat.set('activeTenantUserId', undefined);
      flat.occupancyStatus = deriveStatus(
        flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : null,
        null,
      );
      await flat.save({ session });

      assertTransitionAllowed(before, flat.occupancyStatus, 'end-tenant-occupancy');

      await writeAuditLog(
        {
          action: 'TENANT_OCCUPANCY_ENDED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'Flat',
          targetId: flatId,
          metadata: {
            userId: String(record.userId),
            effectiveTo: effectiveTo.toISOString(),
            reason: input.reason,
            notes: input.notes,
            before: { occupancyStatus: before },
            after: { occupancyStatus: flat.occupancyStatus },
            ownerPreserved: Boolean(flat.activeOwnerUserId),
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      return {
        flatId,
        occupancyStatus: flat.occupancyStatus as OccupancyStatus,
        activeOwnerUserId: flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : null,
        activeTenantUserId: null as string | null,
      };
    });
    await afterOccupancyCommit(societyId);
    return result;
  } catch (error) {
    rethrowOccupancyError(error, 'Failed to end tenant occupancy');
  }
}

export async function endOwnerOccupancy(
  societyId: string,
  flatId: string,
  input: EndOccupancyInput,
  actor: Actor,
) {
  const effectiveTo = parseDate(input.effectiveTo, 'effectiveTo');

  try {
    const result = await withTransaction(async (session) => {
      const flat = await loadActiveFlat(societyId, flatId, session);

      if (!flat.activeOwnerUserId) {
        throw conflict('Flat does not have an active owner occupancy', 'NO_ACTIVE_OWNER');
      }
      if (flat.activeTenantUserId || flat.occupancyStatus === 'TENANT_OCCUPIED') {
        throw forbidden(
          'End tenant occupancy before ending owner occupancy',
          'TENANT_STILL_ACTIVE',
        );
      }

      const record = await OccupancyRecordModel.findOne({
        societyId: flat.societyId,
        flatId: flat._id,
        role: 'OWNER',
        status: 'ACTIVE',
      }).session(session);

      if (!record) {
        throw conflict('Active owner occupancy record not found', 'NO_ACTIVE_OWNER');
      }
      if (effectiveTo.getTime() < record.startsAt.getTime()) {
        throw badRequest('effectiveTo cannot be earlier than occupancy start', 'INVALID_DATE_RANGE');
      }

      record.status = 'ENDED';
      record.endsAt = effectiveTo;
      record.endReason = input.reason;
      if (input.notes) record.notes = input.notes;
      await record.save({ session });

      await endActiveMembership(
        {
          societyId,
          userId: String(record.userId),
          role: 'OWNER',
          flatId,
          endsAt: effectiveTo,
        },
        session,
      );

      const before = flat.occupancyStatus;
      flat.set('activeOwnerUserId', undefined);
      flat.set('activeTenantUserId', undefined);
      flat.occupancyStatus = 'VACANT';
      await flat.save({ session });

      assertTransitionAllowed(before, 'VACANT', 'end-owner-occupancy');

      await writeAuditLog(
        {
          action: 'OWNER_OCCUPANCY_ENDED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'Flat',
          targetId: flatId,
          metadata: {
            userId: String(record.userId),
            effectiveTo: effectiveTo.toISOString(),
            reason: input.reason,
            notes: input.notes,
            before: { occupancyStatus: before },
            after: { occupancyStatus: 'VACANT' },
          },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      return {
        flatId,
        occupancyStatus: 'VACANT' as OccupancyStatus,
        activeOwnerUserId: null as string | null,
        activeTenantUserId: null as string | null,
      };
    });
    await afterOccupancyCommit(societyId);
    return result;
  } catch (error) {
    rethrowOccupancyError(error, 'Failed to end owner occupancy');
  }
}

export async function getOccupancyHistory(
  societyId: string,
  flatId: string,
  options: { page?: number; limit?: number } = {},
) {
  const page = options.page ?? 1;
  const limit = options.limit ?? 50;
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const flatObjectId = parseObjectId(flatId, 'flatId');

  const flat = await FlatModel.findOne({ _id: flatObjectId, societyId: societyObjectId })
    .select('_id occupancyStatus activeOwnerUserId activeTenantUserId')
    .lean();
  if (!flat) {
    throw notFound('Flat not found');
  }

  const filter = { societyId: societyObjectId, flatId: flatObjectId };
  const [total, rows] = await Promise.all([
    OccupancyRecordModel.countDocuments(filter),
    OccupancyRecordModel.find(filter)
      .sort({ startsAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  const userIds = [...new Set(rows.map((row) => String(row.userId)))];
  const users = await UserModel.find({ _id: { $in: userIds } }).select('name email').lean();
  const userMap = new Map(users.map((user) => [String(user._id), user]));

  return {
    flatId: String(flat._id),
    occupancyStatus: flat.occupancyStatus,
    activeOwnerUserId: flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : null,
    activeTenantUserId: flat.activeTenantUserId ? String(flat.activeTenantUserId) : null,
    items: rows.map((row) => {
      const user = userMap.get(String(row.userId));
      return {
        id: String(row._id),
        userId: String(row.userId),
        userName: user?.name,
        userEmail: user?.email,
        role: row.role,
        status: row.status,
        startsAt: new Date(row.startsAt).toISOString(),
        endsAt: row.endsAt ? new Date(row.endsAt).toISOString() : undefined,
        endReason: row.endReason,
        notes: row.notes,
      };
    }),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function listOccupancies(
  societyId: string,
  query: {
    status?: 'ACTIVE' | 'ENDED';
    role?: 'OWNER' | 'TENANT';
    flatId?: string;
    userId?: string;
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
  if (query.role) filter.role = query.role;
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.userId) filter.userId = parseObjectId(query.userId, 'userId');

  const [total, rows] = await Promise.all([
    OccupancyRecordModel.countDocuments(filter),
    OccupancyRecordModel.find(filter)
      .sort({ startsAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((row) => ({
      id: String(row._id),
      societyId: String(row.societyId),
      flatId: String(row.flatId),
      userId: String(row.userId),
      role: row.role,
      status: row.status,
      startsAt: new Date(row.startsAt).toISOString(),
      endsAt: row.endsAt ? new Date(row.endsAt).toISOString() : undefined,
      endReason: row.endReason,
      notes: row.notes,
    })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}
