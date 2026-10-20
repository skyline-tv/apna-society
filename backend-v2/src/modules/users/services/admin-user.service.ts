import { conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { normalizeEmail } from '../../../utils/crypto';
import { parseObjectId } from '../../../utils/object-id';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { writeAuditLog } from '../../auth/services/audit.service';
import { OccupancyRecordModel } from '../../society/models/occupancy-record.model';
import { MembershipModel } from '../models/membership.model';
import { UserModel } from '../models/user.model';
import type {
  ListUsersQuery,
  ProvisionUserInput,
  UpdateUserInput,
} from '../validators/admin-user.validators';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeUser(user: {
  _id: { toString(): string };
  email: string;
  name: string;
  phone?: string;
  roles: string[];
  isActive: boolean;
  canLogin: boolean;
  primarySocietyId?: { toString(): string };
  lastLoginAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(user._id),
    email: user.email,
    name: user.name,
    phone: user.phone,
    roles: user.roles,
    isActive: user.isActive,
    canLogin: user.canLogin,
    primarySocietyId: user.primarySocietyId ? String(user.primarySocietyId) : undefined,
    lastLoginAt: user.lastLoginAt?.toISOString(),
    createdAt: new Date(user.createdAt).toISOString(),
    updatedAt: new Date(user.updatedAt).toISOString(),
  };
}

export async function provisionResident(
  societyId: string,
  input: ProvisionUserInput,
  actor: Actor,
) {
  const email = normalizeEmail(input.email);
  const role = input.role;

  let user = await UserModel.findOne({ email });
  let created = false;

  if (!user) {
    try {
      user = await UserModel.create({
        email,
        name: input.name.trim(),
        phone: input.phone,
        roles: [role],
        isActive: true,
        canLogin: true,
        primarySocietyId: societyId,
        provisionedBy: actor.userId,
      });
      created = true;
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        throw conflict('A user with this email already exists', 'DUPLICATE_EMAIL');
      }
      throw error;
    }
  } else {
    if (user.roles.includes('ADMIN') || user.roles.includes('GUARD')) {
      throw forbidden(
        'Cannot provision ADMIN or GUARD accounts through resident provisioning',
        'PROTECTED_ROLE',
      );
    }
    if (!user.roles.includes(role)) {
      user.roles = [...user.roles, role];
    }
    if (input.name) user.name = input.name.trim();
    if (input.phone !== undefined) user.phone = input.phone;
    if (!user.primarySocietyId) user.primarySocietyId = parseObjectId(societyId, 'societyId');
    user.isActive = true;
    user.canLogin = true;
    await user.save();
  }

  // Society membership with flatId:null — does not grant flat access.
  const existingMembership = await MembershipModel.findOne({
    societyId,
    userId: user._id,
    role,
    isActive: true,
    flatId: null,
  });

  if (!existingMembership) {
    const activeFlatMembership = await MembershipModel.findOne({
      societyId,
      userId: user._id,
      role,
      isActive: true,
      flatId: { $type: 'objectId' },
    });
    if (!activeFlatMembership) {
      await MembershipModel.create({
        societyId,
        userId: user._id,
        role,
        flatId: null,
        wingId: null,
        isActive: true,
        startsAt: new Date(),
      });
    }
  }

  await writeAuditLog({
    action: created ? 'USER_CREATED' : 'USER_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: String(user._id),
    metadata: {
      email,
      role,
      reusedExisting: !created,
      flatAssigned: false,
    },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return {
    user: serializeUser(user.toObject()),
    reusedExisting: !created,
    flatAssigned: false,
  };
}

export async function listAdminUsers(societyId: string, query: ListUsersQuery) {
  const membershipFilter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
  };
  if (query.role) {
    membershipFilter.role = query.role;
  }

  const memberships = await MembershipModel.find(membershipFilter).select('userId role').lean();
  const userIds = [...new Set(memberships.map((m) => String(m.userId)))];

  const filter: Record<string, unknown> = {
    _id: { $in: userIds },
  };
  if (query.isActive !== undefined) filter.isActive = query.isActive;
  if (query.search) {
    const escaped = query.search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    filter.$or = [
      { name: { $regex: escaped, $options: 'i' } },
      { email: { $regex: escaped, $options: 'i' } },
      { phone: { $regex: escaped, $options: 'i' } },
    ];
  }

  const page = query.page;
  const limit = query.limit;
  const [total, users] = await Promise.all([
    UserModel.countDocuments(filter),
    UserModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  const rolesByUser = new Map<string, string[]>();
  for (const membership of memberships) {
    const key = String(membership.userId);
    const current = rolesByUser.get(key) ?? [];
    if (!current.includes(membership.role)) current.push(membership.role);
    rolesByUser.set(key, current);
  }

  return {
    items: users.map((user) => ({
      ...serializeUser(user),
      societyRoles: rolesByUser.get(String(user._id)) ?? [],
    })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getAdminUser(societyId: string, userId: string) {
  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(userId, 'userId'),
  }).lean();
  if (!membership) {
    throw notFound('User not found in this society');
  }

  const user = await UserModel.findById(userId).lean();
  if (!user) {
    throw notFound('User not found');
  }

  const activeOccupancies = await OccupancyRecordModel.find({
    societyId,
    userId,
    status: 'ACTIVE',
  }).lean();

  return {
    ...serializeUser(user),
    activeOccupancies: activeOccupancies.map((row) => ({
      id: String(row._id),
      flatId: String(row.flatId),
      role: row.role,
      startsAt: new Date(row.startsAt).toISOString(),
    })),
  };
}

export async function updateAdminUser(
  societyId: string,
  userId: string,
  input: UpdateUserInput,
  actor: Actor,
) {
  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(userId, 'userId'),
  });
  if (!membership) {
    throw notFound('User not found in this society');
  }

  const user = await UserModel.findById(userId);
  if (!user) {
    throw notFound('User not found');
  }

  if (user.roles.includes('ADMIN') || user.roles.includes('GUARD')) {
    // Allow reading ADMIN/GUARD in society lists, but block privilege mutation via this API.
    if (input.isActive !== undefined || input.canLogin !== undefined) {
      // Still allow name/phone updates for non-privilege fields on protected roles? Spec:
      // "Do not allow these endpoints to modify ADMIN or GUARD privileges."
      // Name/phone updates are OK; role/activation of admins via this endpoint should be blocked for safety.
    }
  }

  // Never escalate/de-escalate ADMIN/GUARD through this endpoint.
  const before = {
    name: user.name,
    phone: user.phone,
    isActive: user.isActive,
    canLogin: user.canLogin,
    roles: [...user.roles],
  };

  if (input.name !== undefined) user.name = input.name;
  if (input.phone !== undefined) user.phone = input.phone;

  if (input.isActive !== undefined || input.canLogin !== undefined) {
    if (user.roles.includes('ADMIN') || user.roles.includes('GUARD')) {
      throw forbidden(
        'Cannot change activation for ADMIN or GUARD through resident user APIs',
        'PROTECTED_ROLE',
      );
    }
    if (input.isActive !== undefined) user.isActive = input.isActive;
    if (input.canLogin !== undefined) user.canLogin = input.canLogin;
  }

  await user.save();

  await writeAuditLog({
    action: 'USER_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: userId,
    metadata: { before, after: input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeUser(user.toObject());
}

export async function deactivateAdminUser(
  societyId: string,
  userId: string,
  actor: Actor,
  reason?: string,
) {
  if (userId === actor.userId) {
    throw forbidden('Admins cannot deactivate their own account', 'SELF_DEACTIVATION');
  }

  const user = await UserModel.findById(parseObjectId(userId, 'userId'));
  if (!user) {
    throw notFound('User not found');
  }

  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: user._id,
  });
  if (!membership) {
    throw notFound('User not found in this society');
  }

  if (user.roles.includes('ADMIN') || user.roles.includes('GUARD')) {
    throw forbidden(
      'Cannot deactivate ADMIN or GUARD through this endpoint',
      'PROTECTED_ROLE',
    );
  }

  const activeOccupancy = await OccupancyRecordModel.findOne({
    societyId,
    userId: user._id,
    status: 'ACTIVE',
  }).lean();
  if (activeOccupancy) {
    throw forbidden(
      'End active occupancy assignments before deactivating the user',
      'ACTIVE_OCCUPANCY_EXISTS',
    );
  }

  user.isActive = false;
  user.canLogin = false;
  await user.save();

  await MembershipModel.updateMany(
    {
      societyId,
      userId: user._id,
      isActive: true,
      role: { $in: ['OWNER', 'TENANT'] },
    },
    { $set: { isActive: false, endsAt: new Date() } },
  );

  await writeAuditLog({
    action: 'USER_DEACTIVATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: userId,
    metadata: { reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeUser(user.toObject());
}
