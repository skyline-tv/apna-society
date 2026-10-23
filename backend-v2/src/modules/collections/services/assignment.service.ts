import { badRequest, notFound } from '../../../shared/errors/app-error';
import { formatFlatLabel } from '../../../utils/flat-label';
import { parseObjectId } from '../../../utils/object-id';
import { FlatModel } from '../../society/models/flat.model';
import { WingModel } from '../../society/models/wing.model';
import { UserModel } from '../../users/models/user.model';
import type { CreateCollectionInput } from '../validators/collection.validators';

export type AssignmentRow = {
  flatId: string;
  wingId: string;
  wingCode: string;
  flatNumber: string;
  flatLabel: string;
  occupancyStatus: string;
  ownerUserId?: string;
  ownerName: string;
  amountPaise: number;
};

export type AssignmentPreview = {
  assignedFlatCount: number;
  amountMode: CreateCollectionInput['amountMode'];
  assignmentType: CreateCollectionInput['assignmentType'];
  defaultAmountPaise: number;
  expectedTotalPaise: number;
  uniqueFlatCount: number;
  allocations: AssignmentRow[];
};

function splitTotal(totalPaise: number, count: number): number[] {
  if (count <= 0) return [];
  const base = Math.floor(totalPaise / count);
  const remainder = totalPaise - base * count;
  return Array.from({ length: count }, (_, index) => base + (index < remainder ? 1 : 0));
}

export async function resolveCollectionAssignments(
  societyId: string,
  input: CreateCollectionInput,
): Promise<AssignmentPreview> {
  const societyObjectId = parseObjectId(societyId, 'societyId');
  const customAmounts = new Map(
    (input.flatAmounts ?? []).map((row) => [row.flatId, row.amountPaise]),
  );
  if ((input.flatAmounts ?? []).length !== customAmounts.size) {
    throw badRequest('Duplicate flats in assignment', 'DUPLICATE_FLAT_ASSIGNMENT');
  }
  const requestedFlatIds = [...(input.flatIds ?? []), ...(input.flatAmounts ?? []).map((row) => row.flatId)];
  if (requestedFlatIds.length !== new Set(requestedFlatIds).size && input.amountMode !== 'CUSTOM') {
    throw badRequest('Duplicate flats in assignment', 'DUPLICATE_FLAT_ASSIGNMENT');
  }

  const filter: Record<string, unknown> = { societyId: societyObjectId, isActive: true };
  if (input.assignmentType === 'WINGS') {
    filter.wingId = { $in: (input.wingIds ?? []).map((id) => parseObjectId(id, 'wingId')) };
  } else if (input.assignmentType === 'SELECTED_FLATS') {
    const ids = [
      ...new Set([...(input.flatIds ?? []), ...(input.flatAmounts ?? []).map((row) => row.flatId)]),
    ];
    filter._id = { $in: ids.map((id) => parseObjectId(id, 'flatId')) };
  }

  const flats = await FlatModel.find(filter).sort({ number: 1 }).lean();
  if (flats.length === 0) {
    throw badRequest('No configured flats matched the assignment', 'NO_FLATS_ASSIGNED');
  }

  const requestedIds = new Set([
    ...(input.flatIds ?? []),
    ...(input.flatAmounts ?? []).map((row) => row.flatId),
  ]);
  if (input.assignmentType === 'SELECTED_FLATS') {
    const found = new Set(flats.map((flat) => String(flat._id)));
    const missing = [...requestedIds].filter((id) => !found.has(id));
    if (missing.length) {
      throw notFound('One or more selected flats were not found or are inactive');
    }
  }
  if (input.assignmentType === 'WINGS') {
    const wings = await WingModel.find({
      societyId: societyObjectId,
      _id: { $in: (input.wingIds ?? []).map((id) => parseObjectId(id, 'wingId')) },
    })
      .select('_id')
      .lean();
    if (wings.length !== (input.wingIds ?? []).length) {
      throw notFound('One or more wings were not found');
    }
  }

  const uniqueFlatIds = [...new Set(flats.map((flat) => String(flat._id)))];
  if (uniqueFlatIds.length !== flats.length) {
    throw badRequest('Duplicate flats in assignment', 'DUPLICATE_FLAT_ASSIGNMENT');
  }

  const wingIds = [...new Set(flats.map((flat) => String(flat.wingId)))];
  const [wings, owners] = await Promise.all([
    WingModel.find({ _id: { $in: wingIds } }).select('_id code').lean(),
    UserModel.find({
      _id: { $in: flats.map((flat) => flat.activeOwnerUserId).filter(Boolean) },
    })
      .select('_id name')
      .lean(),
  ]);
  const wingCodeById = new Map(wings.map((wing) => [String(wing._id), wing.code]));
  const ownerNameById = new Map(owners.map((user) => [String(user._id), user.name]));

  const defaultAmount = input.amountPaise ?? 0;
  const splitAmounts =
    input.amountMode === 'TOTAL_SPLIT' ? splitTotal(defaultAmount, flats.length) : [];

  const allocations: AssignmentRow[] = flats.map((flat, index) => {
    const flatId = String(flat._id);
    let amountPaise = defaultAmount;
    if (input.amountMode === 'CUSTOM') {
      const custom = customAmounts.get(flatId);
      if (!custom) {
        throw badRequest(`Missing custom amount for flat ${flat.number}`, 'MISSING_FLAT_AMOUNT');
      }
      amountPaise = custom;
    } else if (input.amountMode === 'TOTAL_SPLIT') {
      amountPaise = splitAmounts[index] ?? 0;
    }
    if (amountPaise <= 0) {
      throw badRequest(`Assigned amount must be positive for ${flat.number}`, 'INVALID_FLAT_AMOUNT');
    }
    const wingCode = wingCodeById.get(String(flat.wingId)) ?? '';
    const ownerUserId = flat.activeOwnerUserId ? String(flat.activeOwnerUserId) : undefined;
    return {
      flatId,
      wingId: String(flat.wingId),
      wingCode,
      flatNumber: flat.number,
      flatLabel: formatFlatLabel(wingCode, flat.number),
      occupancyStatus: flat.occupancyStatus,
      ownerUserId,
      ownerName: ownerUserId ? (ownerNameById.get(ownerUserId) ?? 'Unassigned') : 'Unassigned',
      amountPaise,
    };
  });

  const expectedTotalPaise = allocations.reduce((sum, row) => sum + row.amountPaise, 0);
  const typicalAmount = allocations[0]?.amountPaise ?? 0;
  const uniform = allocations.every((row) => row.amountPaise === typicalAmount);

  return {
    assignedFlatCount: allocations.length,
    amountMode: input.amountMode,
    assignmentType: input.assignmentType,
    defaultAmountPaise: uniform ? typicalAmount : 0,
    expectedTotalPaise,
    uniqueFlatCount: allocations.length,
    allocations,
  };
}
