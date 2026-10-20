import { badRequest, conflict, notFound } from '../../../shared/errors/app-error';
import { isDuplicateKeyError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { MembershipModel } from '../../users/models/membership.model';
import { UserModel } from '../../users/models/user.model';
import {
  StaffModel,
  type EmploymentStatus,
  type EmploymentType,
  type StaffCategory,
} from '../models/staff.model';
import { normalizePhone } from '../utils/society-time';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function serializeStaff(doc: {
  _id: { toString(): string };
  societyId: { toString(): string };
  fullName: string;
  phone: string;
  email?: string;
  category: string;
  employmentType: string;
  joiningDate: string;
  employmentStatus: string;
  address?: string;
  emergencyContactName?: string;
  emergencyContactPhone?: string;
  notes?: string;
  linkedUserId?: { toString(): string };
  createdBy: { toString(): string };
  deactivatedAt?: Date;
  terminatedAt?: Date;
  statusReason?: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: String(doc._id),
    societyId: String(doc.societyId),
    fullName: doc.fullName,
    phone: doc.phone,
    email: doc.email,
    category: doc.category,
    employmentType: doc.employmentType,
    joiningDate: doc.joiningDate,
    employmentStatus: doc.employmentStatus,
    address: doc.address,
    emergencyContactName: doc.emergencyContactName,
    emergencyContactPhone: doc.emergencyContactPhone,
    notes: doc.notes,
    linkedUserId: doc.linkedUserId ? String(doc.linkedUserId) : undefined,
    createdBy: String(doc.createdBy),
    deactivatedAt: doc.deactivatedAt?.toISOString(),
    terminatedAt: doc.terminatedAt?.toISOString(),
    statusReason: doc.statusReason,
    createdAt: new Date(doc.createdAt).toISOString(),
    updatedAt: new Date(doc.updatedAt).toISOString(),
  };
}

async function validateLinkedUser(societyId: string, linkedUserId: string) {
  const user = await UserModel.findOne({
    _id: parseObjectId(linkedUserId, 'linkedUserId'),
    isActive: true,
  }).lean();
  if (!user) throw badRequest('Linked user not found or inactive', 'INVALID_LINKED_USER');

  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: user._id,
    isActive: true,
  }).lean();
  if (!membership) {
    throw badRequest(
      'Linked user must have an active membership in this society',
      'INVALID_LINKED_USER',
    );
  }
  // Do not auto-grant roles — link is employment record only.
  return user;
}

export async function createStaff(
  societyId: string,
  input: {
    fullName: string;
    phone: string;
    email?: string;
    category: StaffCategory;
    employmentType: EmploymentType;
    joiningDate: string;
    address?: string;
    emergencyContactName?: string;
    emergencyContactPhone?: string;
    notes?: string;
    linkedUserId?: string;
  },
  actor: Actor,
) {
  const phoneNormalized = normalizePhone(input.phone);
  if (input.linkedUserId) {
    await validateLinkedUser(societyId, input.linkedUserId);
  }

  try {
    const [doc] = await StaffModel.create([
      {
        societyId,
        fullName: input.fullName.trim(),
        phone: input.phone.trim(),
        phoneNormalized,
        email: input.email?.trim().toLowerCase(),
        category: input.category,
        employmentType: input.employmentType,
        joiningDate: input.joiningDate,
        employmentStatus: 'ACTIVE',
        address: input.address?.trim(),
        emergencyContactName: input.emergencyContactName?.trim(),
        emergencyContactPhone: input.emergencyContactPhone?.trim(),
        notes: input.notes?.trim(),
        linkedUserId: input.linkedUserId,
        createdBy: actor.userId,
      },
    ]);

    await writeAuditLog({
      action: 'STAFF_CREATED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'Staff',
      targetId: String(doc._id),
      metadata: {
        category: input.category,
        linkedUserId: input.linkedUserId,
        // Explicit: linking a GUARD user does not change roles.
        rolesUnchanged: true,
      },
      ipAddress: actor.ipAddress,
      userAgent: actor.userAgent,
    });

    return serializeStaff(doc);
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict(
        'An active staff member with this phone already exists in the society',
        'DUPLICATE_STAFF_PHONE',
      );
    }
    throw error;
  }
}

export async function listStaff(
  societyId: string,
  query: {
    category?: StaffCategory;
    employmentType?: EmploymentType;
    employmentStatus?: EmploymentStatus;
    joiningFrom?: string;
    joiningTo?: string;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.category) filter.category = query.category;
  if (query.employmentType) filter.employmentType = query.employmentType;
  if (query.employmentStatus) filter.employmentStatus = query.employmentStatus;
  if (query.joiningFrom || query.joiningTo) {
    filter.joiningDate = {};
    if (query.joiningFrom) (filter.joiningDate as Record<string, string>).$gte = query.joiningFrom;
    if (query.joiningTo) (filter.joiningDate as Record<string, string>).$lte = query.joiningTo;
  }

  const [total, rows] = await Promise.all([
    StaffModel.countDocuments(filter),
    StaffModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeStaff(r)),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getStaff(societyId: string, staffId: string) {
  const doc = await StaffModel.findOne({
    _id: parseObjectId(staffId, 'staffId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Staff not found');
  return serializeStaff(doc);
}

export async function updateStaff(
  societyId: string,
  staffId: string,
  input: {
    fullName?: string;
    phone?: string;
    email?: string;
    category?: StaffCategory;
    employmentType?: EmploymentType;
    address?: string;
    emergencyContactName?: string;
    emergencyContactPhone?: string;
    notes?: string;
    linkedUserId?: string | null;
  },
  actor: Actor,
) {
  const doc = await StaffModel.findOne({
    _id: parseObjectId(staffId, 'staffId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Staff not found');
  if (doc.employmentStatus === 'TERMINATED') {
    throw badRequest('Terminated staff cannot be updated', 'STAFF_TERMINATED');
  }

  if (input.fullName !== undefined) doc.fullName = input.fullName.trim();
  if (input.phone !== undefined) {
    doc.phone = input.phone.trim();
    doc.phoneNormalized = normalizePhone(input.phone);
  }
  if (input.email !== undefined) doc.email = input.email.trim().toLowerCase();
  if (input.category !== undefined) doc.category = input.category;
  if (input.employmentType !== undefined) doc.employmentType = input.employmentType;
  if (input.address !== undefined) doc.address = input.address.trim();
  if (input.emergencyContactName !== undefined) {
    doc.emergencyContactName = input.emergencyContactName.trim();
  }
  if (input.emergencyContactPhone !== undefined) {
    doc.emergencyContactPhone = input.emergencyContactPhone.trim();
  }
  if (input.notes !== undefined) doc.notes = input.notes.trim();
  if (input.linkedUserId !== undefined) {
    if (input.linkedUserId === null) {
      doc.linkedUserId = undefined;
    } else {
      await validateLinkedUser(societyId, input.linkedUserId);
      doc.linkedUserId = parseObjectId(input.linkedUserId, 'linkedUserId');
    }
  }

  try {
    await doc.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict(
        'An active staff member with this phone already exists in the society',
        'DUPLICATE_STAFF_PHONE',
      );
    }
    throw error;
  }

  await writeAuditLog({
    action: 'STAFF_UPDATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Staff',
    targetId: staffId,
    metadata: { ...input },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeStaff(doc);
}

export async function deactivateStaff(
  societyId: string,
  staffId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const doc = await StaffModel.findOne({
    _id: parseObjectId(staffId, 'staffId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Staff not found');
  if (doc.employmentStatus === 'TERMINATED') {
    throw badRequest('Staff is terminated', 'STAFF_TERMINATED');
  }
  if (doc.employmentStatus === 'INACTIVE') return serializeStaff(doc);

  doc.employmentStatus = 'INACTIVE';
  doc.deactivatedAt = new Date();
  doc.statusReason = reason;
  await doc.save();

  await writeAuditLog({
    action: 'STAFF_DEACTIVATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Staff',
    targetId: staffId,
    metadata: { reason },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeStaff(doc);
}

export async function terminateStaff(
  societyId: string,
  staffId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const doc = await StaffModel.findOne({
    _id: parseObjectId(staffId, 'staffId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Staff not found');
  if (doc.employmentStatus === 'TERMINATED') return serializeStaff(doc);

  doc.employmentStatus = 'TERMINATED';
  doc.terminatedAt = new Date();
  doc.statusReason = reason;
  await doc.save();

  await writeAuditLog({
    action: 'STAFF_TERMINATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Staff',
    targetId: staffId,
    metadata: { reason, linkedUserId: doc.linkedUserId ? String(doc.linkedUserId) : undefined },
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeStaff(doc);
}

export async function reactivateStaff(
  societyId: string,
  staffId: string,
  actor: Actor,
) {
  const doc = await StaffModel.findOne({
    _id: parseObjectId(staffId, 'staffId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Staff not found');
  if (doc.employmentStatus === 'TERMINATED') {
    throw badRequest('Terminated staff cannot be reactivated', 'STAFF_TERMINATED');
  }
  if (doc.employmentStatus === 'ACTIVE') return serializeStaff(doc);

  try {
    doc.employmentStatus = 'ACTIVE';
    doc.deactivatedAt = undefined;
    doc.statusReason = undefined;
    await doc.save();
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      throw conflict(
        'An active staff member with this phone already exists in the society',
        'DUPLICATE_STAFF_PHONE',
      );
    }
    throw error;
  }

  await writeAuditLog({
    action: 'STAFF_REACTIVATED',
    actorUserId: actor.userId,
    societyId,
    targetType: 'Staff',
    targetId: staffId,
    metadata: {},
    ipAddress: actor.ipAddress,
    userAgent: actor.userAgent,
  });

  return serializeStaff(doc);
}

export async function assertActiveStaff(societyId: string, staffId: string) {
  const doc = await StaffModel.findOne({
    _id: parseObjectId(staffId, 'staffId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!doc) throw notFound('Staff not found');
  if (doc.employmentStatus !== 'ACTIVE') {
    throw badRequest('Staff must be ACTIVE', 'STAFF_NOT_ACTIVE');
  }
  return doc;
}

export { serializeStaff };
