import { badRequest } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { FlatModel } from '../../society/models/flat.model';
import { WingModel } from '../../society/models/wing.model';
import { MembershipModel } from '../../users/models/membership.model';
import type { AudienceRole, AudienceType } from '../models/announcement.model';

async function validateTargets(input: {
  societyId: string;
  audienceType: AudienceType;
  targetWingIds: string[];
  targetFlatIds: string[];
}): Promise<{ wingObjectIds: ReturnType<typeof parseObjectId>[]; flatObjectIds: ReturnType<typeof parseObjectId>[] }> {
  const societyId = parseObjectId(input.societyId, 'societyId');

  if (input.audienceType === 'WING') {
    const wingIds = [...new Set(input.targetWingIds)];
    if (wingIds.length === 0) {
      throw badRequest('targetWingIds required for WING audience', 'VALIDATION_ERROR');
    }
    const wings = await WingModel.find({
      _id: { $in: wingIds.map((id) => parseObjectId(id, 'wingId')) },
      societyId,
      isActive: true,
    })
      .select('_id')
      .lean();
    if (wings.length !== wingIds.length) {
      throw badRequest('One or more wings are invalid for this society', 'INVALID_WING_TARGET');
    }
    return { wingObjectIds: wings.map((w) => w._id as never), flatObjectIds: [] };
  }

  if (input.audienceType === 'SELECTED_FLATS') {
    const flatIds = [...new Set(input.targetFlatIds)];
    if (flatIds.length === 0) {
      throw badRequest('targetFlatIds required for SELECTED_FLATS audience', 'VALIDATION_ERROR');
    }
    const flats = await FlatModel.find({
      _id: { $in: flatIds.map((id) => parseObjectId(id, 'flatId')) },
      societyId,
      isActive: true,
    })
      .select('_id')
      .lean();
    if (flats.length !== flatIds.length) {
      throw badRequest('One or more flats are invalid for this society', 'INVALID_FLAT_TARGET');
    }
    return { wingObjectIds: [], flatObjectIds: flats.map((f) => f._id as never) };
  }

  return { wingObjectIds: [], flatObjectIds: [] };
}

/**
 * Resolve current residential recipients from audience criteria + live occupancy.
 * Audience criteria on the announcement are the source of truth (not a stored recipient list).
 */
export async function resolveAnnouncementRecipients(input: {
  societyId: string;
  audienceType: AudienceType;
  audienceRole?: AudienceRole;
  targetWingIds: string[];
  targetFlatIds: string[];
}): Promise<string[]> {
  const societyId = parseObjectId(input.societyId, 'societyId');
  const { wingObjectIds, flatObjectIds } = await validateTargets(input);

  const flatFilter: Record<string, unknown> = {
    societyId,
    isActive: true,
    occupancyStatus: { $in: ['OWNER_OCCUPIED', 'TENANT_OCCUPIED'] },
  };

  if (input.audienceType === 'WING') {
    flatFilter.wingId = { $in: wingObjectIds };
  } else if (input.audienceType === 'SELECTED_FLATS') {
    flatFilter._id = { $in: flatObjectIds };
  }

  const flats = await FlatModel.find(flatFilter)
    .select('_id occupancyStatus activeOwnerUserId activeTenantUserId')
    .lean();

  const role = input.audienceRole ?? 'ALL';
  const candidateUserIds = new Set<string>();
  for (const flat of flats) {
    if (role === 'OWNERS') {
      if (flat.activeOwnerUserId) candidateUserIds.add(String(flat.activeOwnerUserId));
      continue;
    }
    if (role === 'TENANTS') {
      if (flat.occupancyStatus === 'TENANT_OCCUPIED' && flat.activeTenantUserId) {
        candidateUserIds.add(String(flat.activeTenantUserId));
      }
      continue;
    }
    if (flat.occupancyStatus === 'OWNER_OCCUPIED' && flat.activeOwnerUserId) {
      candidateUserIds.add(String(flat.activeOwnerUserId));
    } else if (flat.occupancyStatus === 'TENANT_OCCUPIED' && flat.activeTenantUserId) {
      candidateUserIds.add(String(flat.activeTenantUserId));
    }
  }

  if (candidateUserIds.size === 0) return [];

  const activeMembers = await MembershipModel.find({
    societyId,
    userId: { $in: [...candidateUserIds] },
    isActive: true,
    role: { $in: ['OWNER', 'TENANT', 'ADMIN'] },
  })
    .select('userId')
    .lean();

  return [...new Set(activeMembers.map((m) => String(m.userId)))];
}

export async function userCanViewAnnouncement(input: {
  societyId: string;
  userId: string;
  audienceType: AudienceType;
  audienceRole?: AudienceRole;
  targetWingIds: string[];
  targetFlatIds: string[];
}): Promise<boolean> {
  const recipients = await resolveAnnouncementRecipients({
    societyId: input.societyId,
    audienceType: input.audienceType,
    audienceRole: input.audienceRole,
    targetWingIds: input.targetWingIds.map(String),
    targetFlatIds: input.targetFlatIds.map(String),
  });
  return recipients.includes(input.userId);
}
