import { conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { normalizeEmail } from '../../../utils/crypto';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import {
  generateTemporaryPassword,
  hashPassword,
} from '../../../utils/password';
import { normalizeMobileE164 } from '../../../utils/phone';
import { assertValidUsername, usernameFromEmail } from '../../../utils/username';
import { writeAuditLog } from '../../auth/services/audit.service';
import { RefreshSessionModel } from '../../auth/models/refresh-session.model';
import { OccupancyRecordModel } from '../../society/models/occupancy-record.model';
import { MembershipModel } from '../models/membership.model';
import { UserModel } from '../models/user.model';
import type {
  AdminSetPasswordInput,
  ListUsersQuery,
  ProvisionUserInput,
  UpdateUserInput,
} from '../validators/admin-user.validators';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeUser(user: {
  _id: { toString(): string };
  email: string;
  username?: string;
  name: string;
  phone?: string;
  mobileE164?: string;
  mobileVerifiedAt?: Date;
  roles: string[];
  isActive: boolean;
  canLogin: boolean;
  mustChangePassword?: boolean;
  passwordChangedAt?: Date;
  hasPassword?: boolean;
  primarySocietyId?: { toString(): string };
  lastLoginAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(user._id),
    email: user.email,
    username: user.username,
    name: user.name,
    phone: user.phone,
    mobileE164: user.mobileE164,
    mobileVerified: Boolean(user.mobileVerifiedAt),
    mobileVerifiedAt: user.mobileVerifiedAt?.toISOString(),
    roles: user.roles,
    isActive: user.isActive,
    canLogin: user.canLogin,
    mustChangePassword: Boolean(user.mustChangePassword),
    hasPassword: user.hasPassword ?? false,
    passwordChangedAt: user.passwordChangedAt?.toISOString(),
    primarySocietyId: user.primarySocietyId ? String(user.primarySocietyId) : undefined,
    lastLoginAt: user.lastLoginAt?.toISOString(),
    createdAt: new Date(user.createdAt).toISOString(),
    updatedAt: new Date(user.updatedAt).toISOString(),
  };
}

async function withPasswordFlag<T extends { _id: { toString(): string } }>(
  user: T,
): Promise<T & { hasPassword: boolean }> {
  const row = await UserModel.findById(user._id).select('+passwordHash').lean();
  return { ...user, hasPassword: Boolean(row?.passwordHash) };
}

export async function provisionResident(
  societyId: string,
  input: ProvisionUserInput,
  actor: Actor,
) {
  if (input.vehicles?.length) {
    const { assertNoActiveDuplicatePlates, prepareVehicleDrafts } = await import(
      '../../vehicles/services/vehicle.service'
    );
    const drafts = prepareVehicleDrafts(input.vehicles);
    await assertNoActiveDuplicatePlates(
      societyId,
      drafts.map((draft) => draft.registrationNumber),
    );
  }

  const email = normalizeEmail(input.email);
  const role = input.role;
  const username = assertValidUsername(input.username ?? usernameFromEmail(email));
  const temporaryPassword = input.password ?? generateTemporaryPassword();
  const passwordHash = await hashPassword(temporaryPassword);
  const passwordWasGenerated = !input.password;

  let user = await UserModel.findOne({ email }).select('+passwordHash');
  let created = false;
  let credentialsIssued = false;

  if (!user) {
    try {
      user = await UserModel.create({
        email,
        username,
        passwordHash,
        mustChangePassword: true,
        passwordChangedAt: new Date(),
        name: input.name.trim(),
        phone: input.phone,
        roles: [role],
        isActive: true,
        canLogin: true,
        primarySocietyId: societyId,
        provisionedBy: actor.userId,
      });
      created = true;
      credentialsIssued = true;
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        const msg = String((error as { message?: string }).message ?? '');
        if (msg.includes('username')) {
          throw conflict('A user with this username already exists', 'DUPLICATE_USERNAME');
        }
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
    if (!user.username) {
      user.username = username;
    } else if (user.username !== username) {
      throw conflict('User already has a different username', 'USERNAME_MISMATCH');
    }
    // Re-provisioning an existing account without a password sets credentials once.
    if (!user.passwordHash) {
      user.passwordHash = passwordHash;
      user.mustChangePassword = true;
      user.passwordChangedAt = new Date();
      credentialsIssued = true;
    }
    user.isActive = true;
    user.canLogin = true;
    try {
      await user.save();
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        throw conflict('A user with this username already exists', 'DUPLICATE_USERNAME');
      }
      throw error;
    }
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

  let flatAssigned = false;
  let vehicles: Array<Record<string, unknown>> | undefined;
  if (input.flatId) {
    const { assignOwner, assignTenant } = await import(
      '../../society/services/occupancy-lifecycle.service'
    );
    const occupancyInput = {
      userId: String(user._id),
      effectiveFrom: new Date(),
      vehicles: input.vehicles,
    };
    const assigned =
      role === 'OWNER'
        ? await assignOwner(societyId, input.flatId, occupancyInput, actor)
        : await assignTenant(societyId, input.flatId, occupancyInput, actor);
    flatAssigned = true;
    vehicles = assigned.vehicles as Array<Record<string, unknown>> | undefined;
  }

  await writeAuditLog({
    action: created ? 'USER_CREATED' : 'USER_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: String(user._id),
    metadata: {
      email,
      username,
      role,
      reusedExisting: !created,
      flatAssigned,
      vehicleCount: vehicles?.length ?? 0,
      passwordGenerated: passwordWasGenerated,
      // Never include the password or hash in audit metadata.
    },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  const serialized = serializeUser({
    ...(await withPasswordFlag(user.toObject())),
  });

  return {
    user: serialized,
    reusedExisting: !created,
    flatAssigned,
    ...(vehicles?.length ? { vehicles } : {}),
    /** Returned once — admin must deliver out-of-band. Never logged. */
    temporaryPassword: credentialsIssued ? temporaryPassword : undefined,
    mustChangePassword: Boolean(user.mustChangePassword),
    passwordGenerated: credentialsIssued ? passwordWasGenerated : undefined,
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

  const items = await Promise.all(
    users.map(async (user) => ({
      ...serializeUser(await withPasswordFlag(user)),
      societyRoles: rolesByUser.get(String(user._id)) ?? [],
    })),
  );

  return {
    items,
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
    ...serializeUser(await withPasswordFlag(user)),
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
  if (input.username !== undefined) {
    const nextUsername = assertValidUsername(input.username);
    if (user.username && user.username !== nextUsername) {
      user.username = nextUsername;
    } else if (!user.username) {
      user.username = nextUsername;
    }
  }

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

  try {
    await user.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('A user with this username already exists', 'DUPLICATE_USERNAME');
    }
    throw error;
  }

  await writeAuditLog({
    action: 'USER_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: userId,
    metadata: { before, after: { ...input, password: undefined } },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeUser(await withPasswordFlag(user.toObject()));
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

/**
 * Assign or replace a login mobile number. Clears verification until confirmed.
 * Does not auto-verify migrated numbers.
 */
export async function setUserMobile(
  societyId: string,
  userId: string,
  mobileRaw: string,
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

  const mobileE164 = normalizeMobileE164(mobileRaw);
  const duplicate = await UserModel.findOne({
    mobileE164,
    _id: { $ne: user._id },
  }).lean();
  if (duplicate) {
    throw conflict('This mobile number is already assigned to another user', 'DUPLICATE_MOBILE');
  }

  const before = { mobileE164: user.mobileE164, mobileVerifiedAt: user.mobileVerifiedAt };
  user.mobileE164 = mobileE164;
  user.mobileVerifiedAt = undefined;
  user.phone = user.phone ?? `+${mobileE164}`;
  try {
    await user.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict('This mobile number is already assigned to another user', 'DUPLICATE_MOBILE');
    }
    throw error;
  }

  await writeAuditLog({
    action: 'USER_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: userId,
    metadata: { field: 'mobileE164', before, after: { mobileE164, mobileVerified: false } },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeUser(user.toObject());
}

/**
 * Admin attestation that mobile ownership was verified offline/in-person.
 * Required before SMS OTP login is allowed.
 */
export async function confirmUserMobileVerified(
  societyId: string,
  userId: string,
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
  if (!user.mobileE164) {
    throw conflict('Set a mobile number before confirming verification', 'MOBILE_REQUIRED');
  }

  user.mobileVerifiedAt = new Date();
  await user.save();

  await writeAuditLog({
    action: 'USER_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: userId,
    metadata: {
      field: 'mobileVerifiedAt',
      mobileSuffix: user.mobileE164.slice(-4),
      verified: true,
    },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeUser(await withPasswordFlag(user.toObject()));
}

/**
 * Admin-assisted password set/reset. Returns a one-time temporary password when
 * none was supplied. Revokes all refresh sessions. Never logs the password.
 */
export async function adminSetUserPassword(
  societyId: string,
  userId: string,
  input: AdminSetPasswordInput,
  actor: Actor,
) {
  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(userId, 'userId'),
  });
  if (!membership) {
    throw notFound('User not found in this society');
  }

  const user = await UserModel.findById(userId).select('+passwordHash');
  if (!user) {
    throw notFound('User not found');
  }
  if (!user.username) {
    throw conflict(
      'Assign a username before setting a password',
      'USERNAME_REQUIRED',
    );
  }

  const temporaryPassword = input.password ?? generateTemporaryPassword();
  const passwordWasGenerated = !input.password;
  user.passwordHash = await hashPassword(temporaryPassword);
  user.mustChangePassword = input.mustChangePassword ?? true;
  user.passwordChangedAt = new Date();
  user.failedLoginAttempts = 0;
  user.lockUntil = undefined;
  await user.save();

  await RefreshSessionModel.updateMany(
    { userId: user._id, revokedAt: { $exists: false } },
    { $set: { revokedAt: new Date() } },
  );

  await writeAuditLog({
    action: 'AUTH_PASSWORD_RESET',
    actorUserId: actor.userId,
    societyId,
    targetType: 'User',
    targetId: userId,
    metadata: {
      passwordGenerated: passwordWasGenerated,
      mustChangePassword: user.mustChangePassword,
      // Never include password or hash.
    },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return {
    user: serializeUser(await withPasswordFlag(user.toObject())),
    temporaryPassword,
    passwordGenerated: passwordWasGenerated,
    mustChangePassword: user.mustChangePassword,
  };
}
