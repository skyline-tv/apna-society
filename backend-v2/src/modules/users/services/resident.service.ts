import { forbidden, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { FlatModel } from '../../society/models/flat.model';
import { OccupancyRecordModel } from '../../society/models/occupancy-record.model';
import { WingModel } from '../../society/models/wing.model';
import { serializeFlat } from '../../society/services/serializers';
import {
  canViewOccupancyHistory,
  getFlatAccess,
} from './access-control.service';
import { MembershipModel } from '../models/membership.model';
import { UserModel } from '../models/user.model';

export async function getResidentProfile(userId: string) {
  const user = await UserModel.findById(userId).lean();
  if (!user) {
    throw notFound('User not found');
  }

  const memberships = await MembershipModel.find({
    userId,
    isActive: true,
    role: { $in: ['OWNER', 'TENANT'] },
  }).lean();

  return {
    id: String(user._id),
    email: user.email,
    name: user.name,
    phone: user.phone,
    roles: user.roles.filter((role) => role === 'OWNER' || role === 'TENANT'),
    societyIds: [...new Set(memberships.map((m) => String(m.societyId)))],
    activeFlatIds: [
      ...new Set(
        memberships
          .filter((m) => m.flatId)
          .map((m) => String(m.flatId)),
      ),
    ],
  };
}

export async function listResidentFlats(userId: string) {
  const userObjectId = parseObjectId(userId, 'userId');
  const flats = await FlatModel.find({
    $or: [{ activeOwnerUserId: userObjectId }, { activeTenantUserId: userObjectId }],
    isActive: true,
  }).lean();

  const wings = await WingModel.find({
    _id: { $in: flats.map((flat) => flat.wingId) },
  })
    .select('code name')
    .lean();
  const wingMap = new Map(wings.map((wing) => [String(wing._id), wing]));

  const items = [];
  for (const flat of flats) {
    const access = await getFlatAccess({
      userId,
      societyId: String(flat.societyId),
      flatId: String(flat._id),
    });
    if (!access.financial && !access.residential) {
      continue;
    }
    const wing = wingMap.get(String(flat.wingId));
    items.push({
      ...serializeFlat(flat, { wingCode: wing?.code, wingName: wing?.name }),
      access: {
        financial: access.financial,
        residential: access.residential,
        role: access.role,
      },
    });
  }

  return items;
}

export async function getResidentFlat(userId: string, flatId: string) {
  const flat = await FlatModel.findById(parseObjectId(flatId, 'flatId')).lean();
  if (!flat) {
    throw notFound('Flat not found');
  }

  const access = await getFlatAccess({
    userId,
    societyId: String(flat.societyId),
    flatId: String(flat._id),
  });

  if (!access.financial && !access.residential) {
    throw forbidden('Access denied for this flat', 'FLAT_ACCESS_DENIED');
  }

  const wing = await WingModel.findById(flat.wingId).select('code name').lean();
  const summary = serializeFlat(flat, { wingCode: wing?.code, wingName: wing?.name });

  // Do not expose peer resident PII beyond what access allows.
  if (!access.residential) {
    summary.activeTenant = undefined;
  }
  if (access.role === 'TENANT') {
    // Tenants see owner name only as non-sensitive contact context? Spec: no financial data.
    // Keep owner summary minimal (id/name) — email already in ResidentSummary; strip email for tenant view.
    if (summary.activeOwner) {
      summary.activeOwner = {
        id: summary.activeOwner.id,
        name: summary.activeOwner.name,
        email: '',
        role: 'OWNER',
      };
    }
  }

  return {
    ...summary,
    access: {
      financial: access.financial,
      residential: access.residential,
      role: access.role,
    },
  };
}

export async function getResidentFlatOccupancy(userId: string, flatId: string) {
  const flat = await FlatModel.findById(parseObjectId(flatId, 'flatId')).lean();
  if (!flat) {
    throw notFound('Flat not found');
  }

  const allowed = await canViewOccupancyHistory({
    userId,
    societyId: String(flat.societyId),
    flatId: String(flat._id),
  });
  if (!allowed) {
    throw forbidden('Occupancy history access denied', 'OCCUPANCY_ACCESS_DENIED');
  }

  const access = await getFlatAccess({
    userId,
    societyId: String(flat.societyId),
    flatId: String(flat._id),
  });

  const filter: Record<string, unknown> = {
    societyId: flat.societyId,
    flatId: flat._id,
  };

  // Previous tenants only see their own history rows.
  if (access.role === 'NONE' || (access.role === 'TENANT' && !access.residential)) {
    filter.userId = parseObjectId(userId, 'userId');
  } else if (access.role === 'TENANT') {
    // Active tenant: see current occupancy context + own history, not prior tenant PII beyond own rows.
    filter.$or = [
      { status: 'ACTIVE' },
      { userId: parseObjectId(userId, 'userId') },
    ];
  }

  const rows = await OccupancyRecordModel.find(filter).sort({ startsAt: -1 }).limit(50).lean();

  return {
    flatId: String(flat._id),
    occupancyStatus: flat.occupancyStatus,
    access: {
      financial: access.financial,
      residential: access.residential,
      role: access.role,
    },
    items: rows.map((row) => ({
      id: String(row._id),
      userId: String(row.userId),
      role: row.role,
      status: row.status,
      startsAt: new Date(row.startsAt).toISOString(),
      endsAt: row.endsAt ? new Date(row.endsAt).toISOString() : undefined,
      // Hide other residents' notes from tenants without residential/admin rights.
      notes:
        access.role === 'ADMIN' ||
        access.role === 'OWNER' ||
        String(row.userId) === userId
          ? row.notes
          : undefined,
      endReason:
        access.role === 'ADMIN' ||
        access.role === 'OWNER' ||
        String(row.userId) === userId
          ? row.endReason
          : undefined,
    })),
  };
}
