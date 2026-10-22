import { badRequest, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../../society/models/flat.model';
import { WingModel } from '../../society/models/wing.model';
import { FlatAdditionalServiceModel } from '../models/additional-service.model';
import {
  MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT,
  countActiveAdditionalServices,
  insertWithActiveSlotLimit,
} from '../utils/additional-service-limit';
import type {
  CreateAdditionalServiceInput,
  DeactivateAdditionalServiceInput,
  ListAdditionalServicesQuery,
  UpdateAdditionalServiceInput,
} from '../validators/additional-service.validators';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeService(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  flatId: { toString(): string };
  name: string;
  description?: string;
  monthlyChargePaise: number;
  quantity: number;
  effectiveFrom: Date;
  effectiveTo?: Date;
  isActive: boolean;
  createdBy: { toString(): string };
  updatedBy?: { toString(): string };
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}, extras?: { flatNumber?: string; wingCode?: string; floor?: number }) {
  const monthlyTotalPaise = doc.monthlyChargePaise * doc.quantity;
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    flatId: String(doc.flatId),
    name: doc.name,
    description: doc.description,
    monthlyChargePaise: doc.monthlyChargePaise,
    quantity: doc.quantity,
    monthlyTotalPaise,
    effectiveFrom: doc.effectiveFrom.toISOString(),
    effectiveTo: doc.effectiveTo?.toISOString(),
    isActive: doc.isActive,
    createdBy: String(doc.createdBy),
    updatedBy: doc.updatedBy ? String(doc.updatedBy) : undefined,
    deactivatedAt: doc.deactivatedAt?.toISOString(),
    deactivationReason: doc.deactivationReason,
    createdAt: doc.createdAt.toISOString(),
    updatedAt: doc.updatedAt.toISOString(),
    flatNumber: extras?.flatNumber,
    wingCode: extras?.wingCode,
    floor: extras?.floor,
  };
}

async function loadFlat(societyId: string, flatId: string) {
  const flat = await FlatModel.findOne({
    _id: parseObjectId(flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!flat) throw notFound('Flat not found');
  return flat;
}

async function wingCodeFor(flat: { societyId: unknown; wingId: unknown }) {
  const wing = await WingModel.findOne({
    _id: flat.wingId,
    societyId: flat.societyId,
  })
    .select('code')
    .lean();
  return wing?.code ?? '';
}

export async function createAdditionalService(
  societyId: string,
  input: CreateAdditionalServiceInput,
  actor: Actor,
) {
  const flat = await loadFlat(societyId, input.flatId);
  if (input.effectiveTo && input.effectiveTo.getTime() < input.effectiveFrom.getTime()) {
    throw badRequest('effectiveTo must be on or after effectiveFrom', 'INVALID_SERVICE_DATES');
  }

  const isActive = input.isActive ?? true;
  const payload = {
    societyId,
    flatId: flat._id,
    name: input.name.trim(),
    description: input.description?.trim(),
    monthlyChargePaise: input.monthlyChargePaise,
    quantity: input.quantity,
    effectiveFrom: input.effectiveFrom,
    effectiveTo: input.effectiveTo,
    isActive,
    createdBy: actor.userId,
  };

  const doc = isActive
    ? await insertWithActiveSlotLimit(societyId, flat._id, async (activeSlot) => {
        const [created] = await FlatAdditionalServiceModel.create([
          { ...payload, activeSlot },
        ]);
        return created;
      })
    : (await FlatAdditionalServiceModel.create([payload]))[0];

  await writeAuditLog({
    action: 'ADDITIONAL_SERVICE_CREATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'FlatAdditionalService',
    targetId: String(doc._id),
    metadata: {
      flatId: String(flat._id),
      name: doc.name,
      monthlyChargePaise: doc.monthlyChargePaise,
      quantity: doc.quantity,
    },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  const { invalidateFinancialCaches } = await import('../../../cache/cache-invalidation');
  await invalidateFinancialCaches(societyId);

  return serializeService(doc, {
    flatNumber: flat.number,
    wingCode: await wingCodeFor(flat),
    floor: flat.floor,
  });
}

export async function listAdditionalServices(
  societyId: string,
  query: ListAdditionalServicesQuery,
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 50;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.isActive !== undefined) filter.isActive = query.isActive;
  if (query.wingId) {
    const flats = await FlatModel.find({
      societyId,
      wingId: parseObjectId(query.wingId, 'wingId'),
    })
      .select('_id')
      .lean();
    filter.flatId = { $in: flats.map((f) => f._id) };
  }

  const [total, rows, activeCount] = await Promise.all([
    FlatAdditionalServiceModel.countDocuments(filter),
    FlatAdditionalServiceModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
    query.flatId
      ? countActiveAdditionalServices(societyId, query.flatId)
      : Promise.resolve(undefined),
  ]);

  const flatIds = [...new Set(rows.map((row) => String(row.flatId)))];
  const flats = await FlatModel.find({ _id: { $in: flatIds } })
    .select('number wingId floor')
    .lean();
  const wingIds = [...new Set(flats.map((f) => String(f.wingId)))];
  const wings = await WingModel.find({ _id: { $in: wingIds } }).select('code').lean();
  const wingMap = new Map(wings.map((w) => [String(w._id), w.code]));
  const flatMap = new Map(
    flats.map((f) => [
      String(f._id),
      { number: f.number, wingCode: wingMap.get(String(f.wingId)) ?? '', floor: f.floor },
    ]),
  );

  return {
    items: rows.map((row) =>
      serializeService(row, flatMap.get(String(row.flatId))),
    ),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
    maxActive: MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT,
    activeCount,
  };
}

export async function getAdditionalService(societyId: string, serviceId: string) {
  const doc = await FlatAdditionalServiceModel.findOne({
    _id: parseObjectId(serviceId, 'serviceId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Additional service not found');
  const flat = await loadFlat(societyId, String(doc.flatId));
  return serializeService(doc, {
    flatNumber: flat.number,
    wingCode: await wingCodeFor(flat),
    floor: flat.floor,
  });
}

export async function updateAdditionalService(
  societyId: string,
  serviceId: string,
  input: UpdateAdditionalServiceInput,
  actor: Actor,
) {
  const doc = await FlatAdditionalServiceModel.findOne({
    _id: parseObjectId(serviceId, 'serviceId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Additional service not found');

  const nextFrom = input.effectiveFrom ?? doc.effectiveFrom;
  const nextTo =
    input.effectiveTo === undefined ? doc.effectiveTo : input.effectiveTo ?? undefined;
  if (nextTo && nextTo.getTime() < nextFrom.getTime()) {
    throw badRequest('effectiveTo must be on or after effectiveFrom', 'INVALID_SERVICE_DATES');
  }

  if (input.name !== undefined) doc.name = input.name.trim();
  if (input.description !== undefined) doc.description = input.description.trim();
  if (input.monthlyChargePaise !== undefined) doc.monthlyChargePaise = input.monthlyChargePaise;
  if (input.quantity !== undefined) doc.quantity = input.quantity;
  if (input.effectiveFrom !== undefined) doc.effectiveFrom = input.effectiveFrom;
  if (input.effectiveTo !== undefined) {
    doc.effectiveTo = input.effectiveTo ?? undefined;
    if (input.effectiveTo === null) doc.set('effectiveTo', undefined);
  }
  const becomingActive = input.isActive === true && !doc.isActive;
  const becomingInactive = input.isActive === false && doc.isActive;
  if (input.isActive !== undefined) {
    doc.isActive = input.isActive;
    if (becomingInactive) {
      if (!doc.deactivatedAt) doc.deactivatedAt = new Date();
      doc.set('activeSlot', undefined);
    }
    if (input.isActive) {
      doc.set('deactivatedAt', undefined);
      doc.set('deactivationReason', undefined);
    }
  }
  doc.updatedBy = parseObjectId(actor.userId, 'userId');

  if (becomingActive) {
    await insertWithActiveSlotLimit(
      societyId,
      doc.flatId,
      async (activeSlot) => {
        doc.activeSlot = activeSlot;
        await doc.save();
        return doc;
      },
      doc._id,
    );
  } else {
    await doc.save();
  }

  await writeAuditLog({
    action: 'ADDITIONAL_SERVICE_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'FlatAdditionalService',
    targetId: serviceId,
    metadata: { ...input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  const { invalidateFinancialCaches } = await import('../../../cache/cache-invalidation');
  await invalidateFinancialCaches(societyId);

  const flat = await loadFlat(societyId, String(doc.flatId));
  return serializeService(doc, {
    flatNumber: flat.number,
    wingCode: await wingCodeFor(flat),
    floor: flat.floor,
  });
}

export async function deactivateAdditionalService(
  societyId: string,
  serviceId: string,
  input: DeactivateAdditionalServiceInput,
  actor: Actor,
) {
  const doc = await FlatAdditionalServiceModel.findOne({
    _id: parseObjectId(serviceId, 'serviceId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Additional service not found');
  if (!doc.isActive) {
    const flat = await loadFlat(societyId, String(doc.flatId));
    return serializeService(doc, {
      flatNumber: flat.number,
      wingCode: await wingCodeFor(flat),
      floor: flat.floor,
    });
  }

  doc.isActive = false;
  doc.deactivatedAt = new Date();
  doc.deactivationReason = input.reason;
  doc.set('activeSlot', undefined);
  if (input.effectiveTo) doc.effectiveTo = input.effectiveTo;
  doc.updatedBy = parseObjectId(actor.userId, 'userId');
  await doc.save();

  await writeAuditLog({
    action: 'ADDITIONAL_SERVICE_DEACTIVATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'FlatAdditionalService',
    targetId: serviceId,
    metadata: { reason: input.reason, effectiveTo: input.effectiveTo?.toISOString() },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  const { invalidateFinancialCaches } = await import('../../../cache/cache-invalidation');
  await invalidateFinancialCaches(societyId);

  const flat = await loadFlat(societyId, String(doc.flatId));
  return serializeService(doc, {
    flatNumber: flat.number,
    wingCode: await wingCodeFor(flat),
    floor: flat.floor,
  });
}

export { serializeService };
