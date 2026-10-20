import { invalidateWingCaches } from '../../../cache/cache-invalidation';
import { CacheKeys } from '../../../cache/cache-keys';
import { cacheAside } from '../../../cache/cache.service';
import { getEnv } from '../../../config/env';
import { conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../models/flat.model';
import { WingModel } from '../models/wing.model';
import type { WingSummary } from '../types/society.types';
import type { CreateWingInput, UpdateWingInput } from '../validators/admin.validators';
import { serializeWing } from './serializers';

function isDuplicateKeyError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { code: number }).code === 11000
  );
}

async function flatCountForWing(societyId: string, wingId: string): Promise<number> {
  return FlatModel.countDocuments({ societyId, wingId });
}

async function loadWingsList(societyId: string): Promise<WingSummary[]> {
  const wings = await WingModel.find({ societyId }).sort({ sortOrder: 1, code: 1 }).lean();
  const counts = await FlatModel.aggregate<{ _id: unknown; count: number }>([
    { $match: { societyId: parseObjectId(societyId, 'societyId') } },
    { $group: { _id: '$wingId', count: { $sum: 1 } } },
  ]);
  const countMap = new Map(counts.map((row) => [String(row._id), row.count]));
  return wings.map((wing) => serializeWing(wing, countMap.get(String(wing._id)) ?? 0));
}

export async function listWings(societyId: string): Promise<WingSummary[]> {
  return cacheAside(
    CacheKeys.wingsList(societyId),
    getEnv().CACHE_TTL_WINGS_SECONDS,
    () => loadWingsList(societyId),
  );
}

export async function getWing(societyId: string, wingId: string): Promise<WingSummary> {
  const wing = await WingModel.findOne({ _id: parseObjectId(wingId, 'wingId'), societyId }).lean();
  if (!wing) {
    throw notFound('Wing not found');
  }
  const flatCount = await flatCountForWing(societyId, wingId);
  return serializeWing(wing, flatCount);
}

export async function createWing(
  societyId: string,
  input: CreateWingInput,
  actor: { userId: string; ipAddress?: string; userAgent?: string },
): Promise<WingSummary> {
  try {
    const sortOrder =
      input.sortOrder ?? (await WingModel.countDocuments({ societyId })) + 1;

    const wing = await WingModel.create({
      societyId: parseObjectId(societyId, 'societyId'),
      name: input.name,
      code: input.code.toUpperCase(),
      floors: input.floors,
      flatsPerFloor: input.flatsPerFloor,
      sortOrder,
      isActive: input.isActive ?? true,
    });

    await writeAuditLog({
      action: 'WING_CREATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'Wing',
      targetId: String(wing._id),
      metadata: { code: wing.code, name: wing.name },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });

    await invalidateWingCaches(societyId);
    return serializeWing(wing.toObject(), 0);
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('Wing code already exists in this society', 'DUPLICATE_WING_CODE');
    }
    throw error;
  }
}

export async function updateWing(
  societyId: string,
  wingId: string,
  input: UpdateWingInput,
  actor: { userId: string; ipAddress?: string; userAgent?: string },
): Promise<WingSummary> {
  const wing = await WingModel.findOne({ _id: parseObjectId(wingId, 'wingId'), societyId });
  if (!wing) {
    throw notFound('Wing not found');
  }

  const flatCount = await flatCountForWing(societyId, wingId);

  if (input.floors !== undefined) {
    const maxFloor = await FlatModel.findOne({ societyId, wingId: wing._id })
      .sort({ floor: -1 })
      .select('floor')
      .lean();
    if (maxFloor && input.floors < maxFloor.floor) {
      throw forbidden(
        `Cannot set floors below existing flat floor ${maxFloor.floor}`,
        'WING_FLOOR_CONSTRAINT',
      );
    }
  }

  if (input.name !== undefined) wing.name = input.name;
  if (input.code !== undefined) wing.code = input.code.toUpperCase();
  if (input.floors !== undefined) wing.floors = input.floors;
  if (input.flatsPerFloor !== undefined) wing.flatsPerFloor = input.flatsPerFloor;
  if (input.sortOrder !== undefined) wing.sortOrder = input.sortOrder;
  if (input.isActive !== undefined) wing.isActive = input.isActive;

  try {
    await wing.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('Wing code already exists in this society', 'DUPLICATE_WING_CODE');
    }
    throw error;
  }

  await writeAuditLog({
    action: 'WING_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Wing',
    targetId: wingId,
    metadata: { changes: input, flatCount },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  await invalidateWingCaches(societyId);
  return serializeWing(wing.toObject(), flatCount);
}

/** Guard for any future hard-delete endpoint. */
export async function assertWingCanBeDeleted(societyId: string, wingId: string): Promise<void> {
  const flatCount = await flatCountForWing(societyId, wingId);
  if (flatCount > 0) {
    throw forbidden('Cannot delete a wing that contains flats', 'WING_HAS_FLATS');
  }
}
