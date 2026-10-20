import { conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { UserModel } from '../../users/models/user.model';
import { FlatModel } from '../models/flat.model';
import { OccupancyRecordModel } from '../models/occupancy-record.model';
import { WingModel } from '../models/wing.model';
import type { FlatListResult, FlatSummary, ResidentSummary } from '../types/society.types';
import type {
  CreateFlatInput,
  ListFlatsQuery,
  UpdateFlatInput,
} from '../validators/admin.validators';
import { hasOutstandingFinancialRecords } from './financial-guards';
import { serializeFlat } from './serializers';

function isDuplicateKeyError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { code: number }).code === 11000
  );
}

async function loadResidentSummaries(
  ownerId?: string,
  tenantId?: string,
): Promise<{ owner?: ResidentSummary; tenant?: ResidentSummary }> {
  const ids = [ownerId, tenantId].filter(Boolean) as string[];
  if (ids.length === 0) {
    return {};
  }
  const users = await UserModel.find({ _id: { $in: ids } })
    .select('name email')
    .lean();
  const byId = new Map(users.map((user) => [String(user._id), user]));
  const owner = ownerId ? byId.get(ownerId) : undefined;
  const tenant = tenantId ? byId.get(tenantId) : undefined;
  return {
    owner: owner
      ? { id: String(owner._id), name: owner.name, email: owner.email, role: 'OWNER' }
      : undefined,
    tenant: tenant
      ? { id: String(tenant._id), name: tenant.name, email: tenant.email, role: 'TENANT' }
      : undefined,
  };
}

async function assertWingInSociety(societyId: string, wingId: string) {
  const wing = await WingModel.findOne({
    _id: parseObjectId(wingId, 'wingId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!wing) {
    throw notFound('Wing not found in this society', 'WING_NOT_FOUND');
  }
  return wing;
}

function validateFloorPosition(
  wing: { floors: number; flatsPerFloor: number; code: string },
  floor: number,
  position: number,
): void {
  if (floor > wing.floors) {
    throw forbidden(
      `Floor ${floor} exceeds wing ${wing.code} floor count (${wing.floors})`,
      'INVALID_FLOOR',
    );
  }
  if (position > wing.flatsPerFloor) {
    throw forbidden(
      `Position ${position} exceeds wing ${wing.code} flats per floor (${wing.flatsPerFloor})`,
      'INVALID_POSITION',
    );
  }
}

async function toFlatSummary(
  flat: {
    _id: { toString(): string };
    societyId: { toString(): string };
    wingId: { toString(): string };
    number: string;
    floor: number;
    position: number;
    flatType: FlatSummary['flatType'];
    maintenanceRate: number;
    isActive: boolean;
    occupancyStatus: FlatSummary['occupancyStatus'];
    parking?: { hasParking?: boolean; slotLabel?: string };
    notes?: string;
    activeOwnerUserId?: { toString(): string };
    activeTenantUserId?: { toString(): string };
    createdAt: Date;
    updatedAt: Date;
  },
  wing?: { code: string; name: string } | null,
): Promise<FlatSummary> {
  const residents = await loadResidentSummaries(
    flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : undefined,
    flat.activeTenantUserId ? String(flat.activeTenantUserId) : undefined,
  );
  return serializeFlat(flat, {
    wingCode: wing?.code,
    wingName: wing?.name,
    activeOwner: residents.owner,
    activeTenant: residents.tenant,
  });
}

export async function listFlats(societyId: string, query: ListFlatsQuery): Promise<FlatListResult> {
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };

  if (query.wingId) filter.wingId = parseObjectId(query.wingId, 'wingId');
  if (query.floor !== undefined) filter.floor = query.floor;
  if (query.flatType) filter.flatType = query.flatType;
  if (query.occupancyStatus) filter.occupancyStatus = query.occupancyStatus;
  if (query.isActive !== undefined) filter.isActive = query.isActive;
  if (query.search) {
    filter.number = { $regex: query.search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), $options: 'i' };
  }

  const sort: Record<string, 1 | -1> = {
    [query.sortBy]: query.sortOrder === 'asc' ? 1 : -1,
  };

  const skip = (query.page - 1) * query.limit;
  const [total, flats, wings] = await Promise.all([
    FlatModel.countDocuments(filter),
    FlatModel.find(filter).sort(sort).skip(skip).limit(query.limit).lean(),
    WingModel.find({ societyId }).select('code name').lean(),
  ]);

  const wingMap = new Map(wings.map((wing) => [String(wing._id), wing]));
  const items = await Promise.all(
    flats.map((flat) => toFlatSummary(flat, wingMap.get(String(flat.wingId)))),
  );

  return {
    items,
    pagination: {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / query.limit),
    },
  };
}

export async function getFlat(societyId: string, flatId: string): Promise<FlatSummary> {
  const flat = await FlatModel.findOne({
    _id: parseObjectId(flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!flat) {
    throw notFound('Flat not found');
  }
  const wing = await WingModel.findById(flat.wingId).select('code name').lean();
  return toFlatSummary(flat, wing);
}

export async function createFlat(
  societyId: string,
  input: CreateFlatInput,
  actor: { userId: string; ipAddress?: string; userAgent?: string },
): Promise<FlatSummary> {
  const wing = await assertWingInSociety(societyId, input.wingId);
  validateFloorPosition(wing, input.floor, input.position);

  try {
    const flat = await FlatModel.create({
      societyId: parseObjectId(societyId, 'societyId'),
      wingId: wing._id,
      number: input.number,
      floor: input.floor,
      position: input.position,
      flatType: input.flatType,
      maintenanceRate: input.maintenanceRate,
      isActive: input.isActive ?? true,
      occupancyStatus: 'VACANT',
      parking: input.parking,
      notes: input.notes,
    });

    await writeAuditLog({
      action: 'FLAT_CREATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'Flat',
      targetId: String(flat._id),
      metadata: {
        number: flat.number,
        wingId: String(wing._id),
        maintenanceRate: flat.maintenanceRate,
      },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });

    return toFlatSummary(flat.toObject(), wing);
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('Duplicate flat number or wing/floor/position', 'DUPLICATE_FLAT');
    }
    throw error;
  }
}

export async function updateFlat(
  societyId: string,
  flatId: string,
  input: UpdateFlatInput,
  actor: { userId: string; ipAddress?: string; userAgent?: string },
): Promise<FlatSummary> {
  const flat = await FlatModel.findOne({
    _id: parseObjectId(flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!flat) {
    throw notFound('Flat not found');
  }

  const previousRate = flat.maintenanceRate;
  const wingId = input.wingId ? parseObjectId(input.wingId, 'wingId') : flat.wingId;
  const wing = await assertWingInSociety(societyId, String(wingId));
  const nextFloor = input.floor ?? flat.floor;
  const nextPosition = input.position ?? flat.position;
  validateFloorPosition(wing, nextFloor, nextPosition);

  if (input.isActive === false && flat.isActive) {
    const hasActiveOccupancy =
      flat.occupancyStatus !== 'VACANT' ||
      Boolean(flat.activeOwnerUserId) ||
      Boolean(flat.activeTenantUserId);

    const outstanding = await hasOutstandingFinancialRecords(societyId, flatId);

    if ((hasActiveOccupancy || outstanding) && !input.forceDeactivate) {
      throw forbidden(
        'Cannot deactivate flat with active occupancy or outstanding financial records without forceDeactivate',
        'FLAT_DEACTIVATE_BLOCKED',
      );
    }

    if (input.forceDeactivate && !input.deactivationReason) {
      throw forbidden(
        'deactivationReason is required when forceDeactivate is true',
        'DEACTIVATION_REASON_REQUIRED',
      );
    }

    flat.isActive = false;
    flat.deactivatedAt = new Date();
    flat.deactivationReason = input.deactivationReason;

    await writeAuditLog({
      action: 'FLAT_DEACTIVATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'Flat',
      targetId: flatId,
      metadata: {
        forceDeactivate: Boolean(input.forceDeactivate),
        reason: input.deactivationReason,
        occupancyStatus: flat.occupancyStatus,
        outstandingFinancialRecords: outstanding,
      },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });
  } else if (input.isActive === true) {
    flat.isActive = true;
    flat.deactivatedAt = undefined;
    flat.deactivationReason = undefined;
  }

  if (input.wingId !== undefined) flat.wingId = wing._id;
  if (input.number !== undefined) flat.number = input.number;
  if (input.floor !== undefined) flat.floor = input.floor;
  if (input.position !== undefined) flat.position = input.position;
  if (input.flatType !== undefined) flat.flatType = input.flatType;
  if (input.maintenanceRate !== undefined) {
    // Changing maintenance rate does not mutate historical bills (billing module later).
    flat.maintenanceRate = input.maintenanceRate;
  }
  // occupancyStatus / activeOwnerUserId / activeTenantUserId are lifecycle-only.
  if (input.parking !== undefined) flat.parking = input.parking;
  if (input.notes !== undefined) flat.notes = input.notes;

  try {
    await flat.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('Duplicate flat number or wing/floor/position', 'DUPLICATE_FLAT');
    }
    throw error;
  }

  await writeAuditLog({
    action: 'FLAT_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Flat',
    targetId: flatId,
    metadata: {
      changes: {
        ...input,
        previousMaintenanceRate: previousRate,
        nextMaintenanceRate: flat.maintenanceRate,
        historicalBillsUnchanged: true,
      },
    },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return toFlatSummary(flat.toObject(), wing);
}

export async function listFlatResidents(
  societyId: string,
  flatId: string,
): Promise<{
  flatId: string;
  occupancyStatus: FlatSummary['occupancyStatus'];
  activeOwner?: ResidentSummary;
  activeTenant?: ResidentSummary;
  history: Array<{
    id: string;
    userId: string;
    role: 'OWNER' | 'TENANT';
    status: 'ACTIVE' | 'ENDED';
    startsAt: string;
    endsAt?: string;
  }>;
}> {
  const flat = await FlatModel.findOne({
    _id: parseObjectId(flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!flat) {
    throw notFound('Flat not found');
  }

  const residents = await loadResidentSummaries(
    flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : undefined,
    flat.activeTenantUserId ? String(flat.activeTenantUserId) : undefined,
  );

  const history = await OccupancyRecordModel.find({
    societyId: flat.societyId,
    flatId: flat._id,
  })
    .sort({ startsAt: -1 })
    .limit(50)
    .lean();

  return {
    flatId: String(flat._id),
    occupancyStatus: flat.occupancyStatus,
    activeOwner: residents.owner,
    activeTenant: residents.tenant,
    history: history.map((row) => ({
      id: String(row._id),
      userId: String(row.userId),
      role: row.role,
      status: row.status,
      startsAt: new Date(row.startsAt).toISOString(),
      endsAt: row.endsAt ? new Date(row.endsAt).toISOString() : undefined,
    })),
  };
}
