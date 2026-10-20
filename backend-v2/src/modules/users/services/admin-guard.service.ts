import { conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { normalizeEmail } from '../../../utils/crypto';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { MembershipModel } from '../models/membership.model';
import { UserModel } from '../models/user.model';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeGuard(user: {
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
}, membership?: { isActive: boolean; startsAt: Date; endsAt?: Date }) {
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
    membershipActive: membership?.isActive ?? false,
    membershipStartsAt: membership?.startsAt?.toISOString(),
    membershipEndsAt: membership?.endsAt?.toISOString(),
    createdAt: new Date(user.createdAt).toISOString(),
    updatedAt: new Date(user.updatedAt).toISOString(),
  };
}

export async function provisionGuard(
  societyId: string,
  input: { name: string; email: string; phone?: string },
  actor: Actor,
) {
  const email = normalizeEmail(input.email);
  let user = await UserModel.findOne({ email });
  let created = false;

  if (!user) {
    try {
      user = await UserModel.create({
        email,
        name: input.name.trim(),
        phone: input.phone,
        roles: ['GUARD'],
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
    if (user.roles.includes('ADMIN')) {
      throw forbidden('Cannot convert ADMIN accounts into guards', 'PROTECTED_ROLE');
    }
    if (!user.roles.includes('GUARD')) {
      user.roles = [...user.roles, 'GUARD'];
    }
    if (input.name) user.name = input.name.trim();
    if (input.phone !== undefined) user.phone = input.phone;
    if (!user.primarySocietyId) user.primarySocietyId = parseObjectId(societyId, 'societyId');
    user.isActive = true;
    user.canLogin = true;
    await user.save();
  }

  const existing = await MembershipModel.findOne({
    societyId,
    userId: user._id,
    role: 'GUARD',
    isActive: true,
    flatId: null,
  });
  if (existing) {
    throw conflict('User already has an active guard membership in this society', 'DUPLICATE_GUARD');
  }

  try {
    await MembershipModel.create({
      societyId,
      userId: user._id,
      role: 'GUARD',
      flatId: null,
      wingId: null,
      isActive: true,
      startsAt: new Date(),
    });
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('User already has an active guard membership in this society', 'DUPLICATE_GUARD');
    }
    throw error;
  }

  await writeAuditLog({
    action: 'GUARD_CREATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: String(user._id),
    metadata: { email, reusedExisting: !created },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  const membership = await MembershipModel.findOne({
    societyId,
    userId: user._id,
    role: 'GUARD',
    isActive: true,
  }).lean();

  return {
    guard: serializeGuard(user.toObject(), membership ?? undefined),
    reusedExisting: !created,
  };
}

export async function listGuards(
  societyId: string,
  query: { search?: string; isActive?: boolean; page?: number; limit?: number },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const membershipFilter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
    role: 'GUARD',
  };
  if (query.isActive !== undefined) membershipFilter.isActive = query.isActive;

  const memberships = await MembershipModel.find(membershipFilter).lean();
  const userIds = memberships.map((m) => m.userId);
  const membershipByUser = new Map(memberships.map((m) => [String(m.userId), m]));

  const filter: Record<string, unknown> = { _id: { $in: userIds } };
  if (query.search) {
    const escaped = query.search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    filter.$or = [
      { name: { $regex: escaped, $options: 'i' } },
      { email: { $regex: escaped, $options: 'i' } },
      { phone: { $regex: escaped, $options: 'i' } },
    ];
  }

  const [total, users] = await Promise.all([
    UserModel.countDocuments(filter),
    UserModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: users.map((user) =>
      serializeGuard(user, membershipByUser.get(String(user._id))),
    ),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getGuard(societyId: string, guardId: string) {
  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(guardId, 'guardId'),
    role: 'GUARD',
  }).lean();
  if (!membership) throw notFound('Guard not found in this society');

  const user = await UserModel.findById(guardId).lean();
  if (!user) throw notFound('Guard not found');
  return serializeGuard(user, membership);
}

export async function updateGuard(
  societyId: string,
  guardId: string,
  input: { name?: string; phone?: string; canLogin?: boolean },
  actor: Actor,
) {
  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(guardId, 'guardId'),
    role: 'GUARD',
  });
  if (!membership) throw notFound('Guard not found in this society');

  const user = await UserModel.findById(guardId);
  if (!user) throw notFound('Guard not found');
  if (!user.roles.includes('GUARD')) {
    throw forbidden('User is not a guard', 'NOT_A_GUARD');
  }

  if (input.name !== undefined) user.name = input.name.trim();
  if (input.phone !== undefined) user.phone = input.phone;
  if (input.canLogin !== undefined) user.canLogin = input.canLogin;
  await user.save();

  await writeAuditLog({
    action: 'GUARD_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: guardId,
    metadata: { ...input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeGuard(user.toObject(), membership.toObject());
}

export async function deactivateGuard(
  societyId: string,
  guardId: string,
  reason: string | undefined,
  actor: Actor,
) {
  if (actor.userId === guardId) {
    throw forbidden('Admins cannot deactivate themselves through guard endpoints', 'SELF_DEACTIVATE');
  }

  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(guardId, 'guardId'),
    role: 'GUARD',
    isActive: true,
  });
  if (!membership) throw notFound('Active guard membership not found');

  const user = await UserModel.findById(guardId);
  if (!user) throw notFound('Guard not found');

  membership.isActive = false;
  membership.endsAt = new Date();
  await membership.save();

  // Guard endpoint access is gated by active GUARD membership; keep role history on the user.
  const otherActiveMembership = await MembershipModel.findOne({
    userId: user._id,
    isActive: true,
  });
  if (!otherActiveMembership) {
    user.canLogin = false;
  }
  await user.save();

  await writeAuditLog({
    action: 'GUARD_DEACTIVATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: guardId,
    metadata: { reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeGuard(user.toObject(), membership.toObject());
}
