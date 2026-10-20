import { forbidden, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { FlatModel } from '../../society/models/flat.model';
import { OccupancyRecordModel } from '../../society/models/occupancy-record.model';
import { MembershipModel } from '../models/membership.model';

export interface FlatAccess {
  financial: boolean;
  residential: boolean;
  role: 'ADMIN' | 'OWNER' | 'TENANT' | 'GUARD' | 'NONE';
  occupancyStatus?: string;
}

/**
 * Server-side access matrix for a flat.
 *
 * Owner + OWNER_OCCUPIED → financial + residential
 * Owner + TENANT_OCCUPIED → financial only
 * Active tenant → residential only
 * Previous tenant → neither (history gated separately)
 * Guard → neither financial nor residential (visitor APIs later)
 * Admin → full access within society
 */
export async function getFlatAccess(input: {
  userId: string;
  societyId: string;
  flatId: string;
}): Promise<FlatAccess> {
  const societyId = parseObjectId(input.societyId, 'societyId');
  const flatId = parseObjectId(input.flatId, 'flatId');
  const userId = parseObjectId(input.userId, 'userId');

  const adminMembership = await MembershipModel.findOne({
    societyId,
    userId,
    role: 'ADMIN',
    isActive: true,
  })
    .select('_id')
    .lean();

  const flat = await FlatModel.findOne({ _id: flatId, societyId }).lean();
  if (!flat) {
    throw notFound('Flat not found');
  }

  if (adminMembership) {
    return {
      financial: true,
      residential: true,
      role: 'ADMIN',
      occupancyStatus: flat.occupancyStatus,
    };
  }

  const isActiveOwner =
    flat.activeOwnerUserId && String(flat.activeOwnerUserId) === String(userId);
  const isActiveTenant =
    flat.activeTenantUserId && String(flat.activeTenantUserId) === String(userId);

  if (isActiveOwner) {
    if (flat.occupancyStatus === 'TENANT_OCCUPIED') {
      return {
        financial: true,
        residential: false,
        role: 'OWNER',
        occupancyStatus: flat.occupancyStatus,
      };
    }
    return {
      financial: true,
      residential: true,
      role: 'OWNER',
      occupancyStatus: flat.occupancyStatus,
    };
  }

  if (isActiveTenant) {
    return {
      financial: false,
      residential: true,
      role: 'TENANT',
      occupancyStatus: flat.occupancyStatus,
    };
  }

  const guardMembership = await MembershipModel.findOne({
    societyId,
    userId,
    role: 'GUARD',
    isActive: true,
  })
    .select('_id')
    .lean();

  if (guardMembership) {
    return {
      financial: false,
      residential: false,
      role: 'GUARD',
      occupancyStatus: flat.occupancyStatus,
    };
  }

  return {
    financial: false,
    residential: false,
    role: 'NONE',
    occupancyStatus: flat.occupancyStatus,
  };
}

export async function assertFinancialAccess(input: {
  userId: string;
  societyId: string;
  flatId: string;
}): Promise<FlatAccess> {
  const access = await getFlatAccess(input);
  if (!access.financial) {
    throw forbidden('Financial access denied for this flat', 'FINANCIAL_ACCESS_DENIED');
  }
  return access;
}

export async function assertResidentialAccess(input: {
  userId: string;
  societyId: string;
  flatId: string;
}): Promise<FlatAccess> {
  const access = await getFlatAccess(input);
  if (!access.residential) {
    throw forbidden('Residential access denied for this flat', 'RESIDENTIAL_ACCESS_DENIED');
  }
  return access;
}

export async function canViewOccupancyHistory(input: {
  userId: string;
  societyId: string;
  flatId: string;
}): Promise<boolean> {
  const access = await getFlatAccess(input);
  if (access.role === 'ADMIN' || access.role === 'OWNER') {
    return true;
  }
  if (access.role === 'TENANT' && access.residential) {
    return true;
  }

  // Previous tenants may view their own ended occupancy rows only (enforced in query).
  const ownHistory = await OccupancyRecordModel.exists({
    societyId: parseObjectId(input.societyId, 'societyId'),
    flatId: parseObjectId(input.flatId, 'flatId'),
    userId: parseObjectId(input.userId, 'userId'),
  });
  return Boolean(ownHistory);
}
