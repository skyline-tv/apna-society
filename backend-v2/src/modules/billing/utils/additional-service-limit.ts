import type { Types } from 'mongoose';
import { conflict } from '../../../shared/errors/app-error';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { FlatAdditionalServiceModel } from '../models/additional-service.model';

export const MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT = 10;
export const ADDITIONAL_SERVICE_LIMIT_CODE = 'ADDITIONAL_SERVICE_LIMIT';
export const ADDITIONAL_SERVICE_LIMIT_MESSAGE =
  'Maximum 10 active services allowed per flat.';

type Id = Types.ObjectId | string;

export function additionalServiceLimitError() {
  return conflict(ADDITIONAL_SERVICE_LIMIT_MESSAGE, ADDITIONAL_SERVICE_LIMIT_CODE);
}

/** Lowest free slot in 1..MAX, or null when every slot is taken. */
export function pickNextActiveSlot(usedSlots: Iterable<number | undefined | null>): number | null {
  const used = new Set<number>();
  for (const slot of usedSlots) {
    if (typeof slot === 'number') used.add(slot);
  }
  for (let slot = 1; slot <= MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT; slot += 1) {
    if (!used.has(slot)) return slot;
  }
  return null;
}

export async function countActiveAdditionalServices(
  societyId: Id,
  flatId: Id,
  excludeServiceId?: Id,
): Promise<number> {
  const filter: Record<string, unknown> = {
    societyId,
    flatId,
    isActive: true,
  };
  if (excludeServiceId) filter._id = { $ne: excludeServiceId };
  return FlatAdditionalServiceModel.countDocuments(filter);
}

export async function nextActiveSlot(
  societyId: Id,
  flatId: Id,
  excludeServiceId?: Id,
): Promise<number> {
  const filter: Record<string, unknown> = {
    societyId,
    flatId,
    isActive: true,
  };
  if (excludeServiceId) filter._id = { $ne: excludeServiceId };
  const rows = await FlatAdditionalServiceModel.find(filter).select('activeSlot').lean();
  if (rows.length >= MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT) {
    throw additionalServiceLimitError();
  }
  const slot = pickNextActiveSlot(rows.map((row) => row.activeSlot));
  if (slot == null) throw additionalServiceLimitError();
  return slot;
}

/**
 * Insert an active service into the next free slot. Duplicate-key races retry
 * until a slot is claimed or the unique index proves the flat is at capacity.
 */
export async function insertWithActiveSlotLimit<T>(
  societyId: Id,
  flatId: Id,
  insert: (slot: number) => Promise<T>,
  excludeServiceId?: Id,
): Promise<T> {
  const maxAttempts = MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT + 3;
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const slot = await nextActiveSlot(societyId, flatId, excludeServiceId);
    try {
      return await insert(slot);
    } catch (error) {
      if (isDuplicateKeyError(error)) continue;
      throw error;
    }
  }
  throw additionalServiceLimitError();
}
