import { Types, type ClientSession } from 'mongoose';
import { randomBytes } from 'crypto';
import { withTransaction } from '../../../database/connection';
import { getEnv } from '../../../config/env';
import { badRequest, conflict, forbidden, notFound } from '../../../shared/errors/app-error';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { FlatModel } from '../../society/models/flat.model';
import { MembershipModel } from '../../users/models/membership.model';
import { UserModel } from '../../users/models/user.model';
import {
  assertResidentialAccess,
  getFlatAccess,
} from '../../users/services/access-control.service';
import {
  ComplaintHistoryModel,
  type ComplaintHistoryAction,
} from '../models/complaint-history.model';
import {
  COMPLAINT_CATEGORIES,
  ComplaintModel,
  type ComplaintCategory,
  type ComplaintDocument,
  type ComplaintPriority,
  type ComplaintStatus,
} from '../models/complaint.model';
import { assertApprovedImageBuffer } from '../storage/image-validation';
import { getComplaintStorage } from '../storage/complaint-storage';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import {
  complaintEventPayloadFromDoc,
  emitComplaintEvent,
} from './complaint-events.service';
import { serializeComplaint, serializeHistory } from './complaint.serializers';
import { assertTransition } from './complaint-transitions';

type Actor = {
  userId: string;
  role: string;
  ipAddress?: string;
  userAgent?: string;
};

async function notifyRaisedByStatusChange(
  societyId: string,
  complaint: { _id: { toString(): string }; raisedByUserId: { toString(): string }; status: string; title?: string },
  suffix = '',
): Promise<void> {
  await notifyBusinessEvent({
    societyId,
    recipientUserId: String(complaint.raisedByUserId),
    type: 'COMPLAINT_STATUS_CHANGED',
    title: 'Complaint status updated',
    body: `Your complaint is now ${complaint.status}`,
    relatedEntityType: 'Complaint',
    relatedEntityId: String(complaint._id),
    idempotencyKey: `COMPLAINT_STATUS:${String(complaint._id)}:${complaint.status}${suffix}`,
  });
}

function generateComplaintNumber(): string {
  const d = new Date();
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  const suffix = randomBytes(3).toString('hex').toUpperCase();
  return `CMP-${y}${m}${day}-${suffix}`;
}

async function appendHistory(
  input: {
    complaintId: string;
    societyId: string;
    action: ComplaintHistoryAction;
    previousStatus?: ComplaintStatus;
    newStatus?: ComplaintStatus;
    previousPriority?: ComplaintPriority;
    newPriority?: ComplaintPriority;
    actor: Actor;
    notes?: string;
    publicNotes?: string;
    assignmentSnapshot?: Record<string, unknown>;
    metadata?: Record<string, unknown>;
  },
  session: ClientSession,
) {
  await ComplaintHistoryModel.create(
    [
      {
        complaintId: input.complaintId,
        societyId: input.societyId,
        action: input.action,
        previousStatus: input.previousStatus,
        newStatus: input.newStatus,
        previousPriority: input.previousPriority,
        newPriority: input.newPriority,
        actorUserId: input.actor.userId,
        actorRole: input.actor.role,
        notes: input.notes,
        publicNotes: input.publicNotes,
        assignmentSnapshot: input.assignmentSnapshot,
        metadata: input.metadata,
      },
    ],
    { session },
  );
}

async function loadComplaint(societyId: string, complaintId: string) {
  const doc = await ComplaintModel.findOne({
    _id: parseObjectId(complaintId, 'complaintId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!doc) throw notFound('Complaint not found');
  return doc;
}

async function assertResidentCanView(
  societyId: string,
  userId: string,
  complaint: ComplaintDocument,
): Promise<void> {
  if (String(complaint.raisedByUserId) === userId) {
    // Raiser can always view their own historical complaint.
    return;
  }
  const access = await getFlatAccess({
    userId,
    societyId,
    flatId: String(complaint.flatId),
  });
  if (!access.residential) {
    throw forbidden('Complaint access denied', 'COMPLAINT_ACCESS_DENIED');
  }
}

export function listComplaintCategories() {
  return { items: [...COMPLAINT_CATEGORIES] };
}

export async function createComplaint(
  societyId: string,
  userId: string,
  input: {
    flatId: string;
    category: ComplaintCategory;
    title: string;
    description: string;
    priority?: ComplaintPriority;
  },
  actor: Actor,
) {
  const access = await assertResidentialAccess({
    userId,
    societyId,
    flatId: input.flatId,
  });

  const flat = await FlatModel.findOne({
    _id: parseObjectId(input.flatId, 'flatId'),
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
  }).lean();
  if (!flat) throw notFound('Flat not found');

  const raisedByRole =
    access.role === 'ADMIN' ? 'ADMIN' : access.role === 'TENANT' ? 'TENANT' : 'OWNER';

  // Residents cannot set priority other than default; admin creating on behalf may set it.
  const priority =
    access.role === 'ADMIN' && input.priority ? input.priority : 'MEDIUM';

  const complaint = await withTransaction(async (session) => {
    const [doc] = await ComplaintModel.create(
      [
        {
          societyId,
          flatId: flat._id,
          complaintNumber: generateComplaintNumber(),
          raisedByUserId: userId,
          raisedByRole,
          category: input.category,
          title: input.title.trim(),
          description: input.description.trim(),
          priority,
          status: 'OPEN',
          attachments: [],
        },
      ],
      { session },
    );

    await appendHistory(
      {
        complaintId: String(doc._id),
        societyId,
        action: 'CREATED',
        newStatus: 'OPEN',
        newPriority: priority,
        actor,
        publicNotes: 'Complaint created',
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_CREATED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: String(doc._id),
        metadata: {
          flatId: String(flat._id),
          category: input.category,
          complaintNumber: doc.complaintNumber,
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return doc;
  });

  return serializeComplaint(complaint, { includeInternalNotes: false });
}

export async function listResidentComplaints(
  societyId: string,
  userId: string,
  query: {
    status?: ComplaintStatus;
    category?: ComplaintCategory;
    priority?: ComplaintPriority;
    from?: Date;
    to?: Date;
    page?: number;
    limit?: number;
  },
) {
  const flats = await FlatModel.find({
    societyId: parseObjectId(societyId, 'societyId'),
    isActive: true,
    $or: [{ activeOwnerUserId: userId }, { activeTenantUserId: userId }],
  })
    .select('_id')
    .lean();

  const residentialFlatIds: Types.ObjectId[] = [];
  for (const flat of flats) {
    const access = await getFlatAccess({
      userId,
      societyId,
      flatId: String(flat._id),
    });
    if (access.residential) residentialFlatIds.push(flat._id as Types.ObjectId);
  }

  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
    $or: [
      { raisedByUserId: userId },
      ...(residentialFlatIds.length > 0 ? [{ flatId: { $in: residentialFlatIds } }] : []),
    ],
  };
  if (query.status) filter.status = query.status;
  if (query.category) filter.category = query.category;
  if (query.priority) filter.priority = query.priority;
  if (query.from || query.to) {
    filter.createdAt = {};
    if (query.from) (filter.createdAt as Record<string, Date>).$gte = query.from;
    if (query.to) (filter.createdAt as Record<string, Date>).$lte = query.to;
  }

  const [total, rows] = await Promise.all([
    ComplaintModel.countDocuments(filter),
    ComplaintModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeComplaint(r, { includeInternalNotes: false })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getResidentComplaint(
  societyId: string,
  userId: string,
  complaintId: string,
) {
  const complaint = await loadComplaint(societyId, complaintId);
  await assertResidentCanView(societyId, userId, complaint);

  const history = await ComplaintHistoryModel.find({
    complaintId: complaint._id,
    societyId: parseObjectId(societyId, 'societyId'),
  })
    .sort({ createdAt: 1 })
    .lean();

  return {
    ...serializeComplaint(complaint, { includeInternalNotes: false }),
    history: history.map((h) => serializeHistory(h, { includeAdminNotes: false })),
  };
}

export async function cancelResidentComplaint(
  societyId: string,
  userId: string,
  complaintId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const complaint = await loadComplaint(societyId, complaintId);
  if (String(complaint.raisedByUserId) !== userId) {
    throw forbidden('Only the raiser may cancel this complaint', 'COMPLAINT_CANCEL_FORBIDDEN');
  }
  if (complaint.status !== 'OPEN') {
    throw conflict('Residents may cancel only OPEN complaints', 'INVALID_STATUS_TRANSITION');
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await ComplaintModel.findOneAndUpdate(
      { _id: complaint._id, status: 'OPEN' },
      {
        $set: {
          status: 'CANCELLED',
          cancelledAt: new Date(),
          cancellationReason: reason,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Complaint could not be cancelled', 'INVALID_STATUS_TRANSITION');
    }

    await appendHistory(
      {
        complaintId,
        societyId,
        action: 'CANCELLED',
        previousStatus: 'OPEN',
        newStatus: 'CANCELLED',
        actor,
        notes: reason,
        publicNotes: reason ?? 'Cancelled by resident',
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_CANCELLED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: { reason, by: 'resident' },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitComplaintEvent('complaint:status_changed', complaintEventPayloadFromDoc(updated), {
    notifyAssignee: false,
  });

  return serializeComplaint(updated, { includeInternalNotes: false });
}

export async function listAdminComplaints(
  societyId: string,
  query: {
    status?: ComplaintStatus;
    category?: ComplaintCategory;
    priority?: ComplaintPriority;
    flatId?: string;
    assignedToUserId?: string;
    from?: Date;
    to?: Date;
    sort?: 'createdAt' | '-createdAt' | 'priority' | '-priority';
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.status) filter.status = query.status;
  if (query.category) filter.category = query.category;
  if (query.priority) filter.priority = query.priority;
  if (query.flatId) filter.flatId = parseObjectId(query.flatId, 'flatId');
  if (query.assignedToUserId) {
    filter.assignedToUserId = parseObjectId(query.assignedToUserId, 'assignedToUserId');
  }
  if (query.from || query.to) {
    filter.createdAt = {};
    if (query.from) (filter.createdAt as Record<string, Date>).$gte = query.from;
    if (query.to) (filter.createdAt as Record<string, Date>).$lte = query.to;
  }

  const sortKey = query.sort ?? '-createdAt';
  const sort: Record<string, 1 | -1> =
    sortKey === 'createdAt'
      ? { createdAt: 1 }
      : sortKey === 'priority'
        ? { priority: 1 }
        : sortKey === '-priority'
          ? { priority: -1 }
          : { createdAt: -1 };

  const [total, rows] = await Promise.all([
    ComplaintModel.countDocuments(filter),
    ComplaintModel.find(filter)
      .sort(sort)
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((r) => serializeComplaint(r, { includeInternalNotes: true })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getAdminComplaint(societyId: string, complaintId: string) {
  const complaint = await loadComplaint(societyId, complaintId);
  const history = await ComplaintHistoryModel.find({
    complaintId: complaint._id,
    societyId: parseObjectId(societyId, 'societyId'),
  })
    .sort({ createdAt: 1 })
    .lean();

  return {
    ...serializeComplaint(complaint, { includeInternalNotes: true }),
    history: history.map((h) => serializeHistory(h, { includeAdminNotes: true })),
  };
}

export async function updateComplaintPriority(
  societyId: string,
  complaintId: string,
  priority: ComplaintPriority,
  actor: Actor,
) {
  const complaint = await loadComplaint(societyId, complaintId);
  if (complaint.status === 'CLOSED' || complaint.status === 'CANCELLED') {
    throw conflict('Cannot change priority of a terminal complaint', 'INVALID_STATUS_TRANSITION');
  }
  if (complaint.priority === priority) {
    return serializeComplaint(complaint, { includeInternalNotes: true });
  }

  const previousPriority = complaint.priority;
  const updated = await withTransaction(async (session) => {
    complaint.priority = priority;
    await complaint.save({ session });

    await appendHistory(
      {
        complaintId,
        societyId,
        action: 'PRIORITY_CHANGED',
        previousStatus: complaint.status,
        newStatus: complaint.status,
        previousPriority,
        newPriority: priority,
        actor,
        publicNotes: `Priority changed to ${priority}`,
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_PRIORITY_CHANGED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: { previousPriority, priority },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return complaint;
  });

  emitComplaintEvent('complaint:status_changed', complaintEventPayloadFromDoc(updated));
  return serializeComplaint(updated, { includeInternalNotes: true });
}

async function resolveInternalAssignee(societyId: string, userId: string) {
  const membership = await MembershipModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    userId: parseObjectId(userId, 'assignedToUserId'),
    isActive: true,
    role: { $in: ['ADMIN', 'OWNER'] },
  }).lean();
  if (!membership) {
    throw badRequest(
      'Assignee must be an active ADMIN or OWNER in this society',
      'INVALID_ASSIGNEE',
    );
  }
  const user = await UserModel.findOne({
    _id: userId,
    isActive: true,
  })
    .select('name')
    .lean();
  if (!user) throw badRequest('Assignee user not found or inactive', 'INVALID_ASSIGNEE');
  return { userId: String(user._id), name: user.name };
}

export async function assignComplaint(
  societyId: string,
  complaintId: string,
  input: {
    assignmentType: 'INTERNAL' | 'EXTERNAL';
    assignedToUserId?: string;
    externalAssignee?: { name: string; phone?: string; company?: string };
    notes?: string;
  },
  actor: Actor,
) {
  const complaint = await loadComplaint(societyId, complaintId);
  if (complaint.status === 'CLOSED' || complaint.status === 'CANCELLED') {
    throw conflict('Cannot assign a terminal complaint', 'INVALID_STATUS_TRANSITION');
  }
  if (complaint.status === 'RESOLVED') {
    throw conflict('Cannot assign a resolved complaint', 'INVALID_STATUS_TRANSITION');
  }

  const previousStatus = complaint.status;
  const isReassign = previousStatus === 'ASSIGNED' || previousStatus === 'IN_PROGRESS';
  const nextStatus: ComplaintStatus = 'ASSIGNED';
  assertTransition(previousStatus === 'OPEN' ? 'OPEN' : previousStatus, nextStatus);

  let assignedToUserId: string | undefined;
  let assignedToNameSnapshot: string | undefined;
  let externalAssignee: { name: string; phone?: string; company?: string } | undefined;

  if (input.assignmentType === 'INTERNAL') {
    if (!input.assignedToUserId) {
      throw badRequest('assignedToUserId is required for INTERNAL assignment', 'VALIDATION_ERROR');
    }
    const assignee = await resolveInternalAssignee(societyId, input.assignedToUserId);
    assignedToUserId = assignee.userId;
    assignedToNameSnapshot = assignee.name;
  } else {
    if (!input.externalAssignee?.name) {
      throw badRequest('externalAssignee.name is required', 'VALIDATION_ERROR');
    }
    externalAssignee = {
      name: input.externalAssignee.name.trim(),
      phone: input.externalAssignee.phone?.trim(),
      company: input.externalAssignee.company?.trim(),
    };
    assignedToNameSnapshot = externalAssignee.name;
  }

  const updated = await withTransaction(async (session) => {
    const setFields: Record<string, unknown> = {
      status: nextStatus,
      assignmentType: input.assignmentType,
      assignedToNameSnapshot,
    };
    const unsetFields: Record<string, 1> = {};
    if (input.assignmentType === 'INTERNAL') {
      setFields.assignedToUserId = assignedToUserId;
      unsetFields.externalAssignee = 1;
    } else {
      setFields.externalAssignee = externalAssignee;
      unsetFields.assignedToUserId = 1;
    }

    const claimed = await ComplaintModel.findOneAndUpdate(
      {
        _id: complaint._id,
        status: { $in: ['OPEN', 'ASSIGNED', 'IN_PROGRESS'] },
      },
      { $set: setFields, $unset: unsetFields },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Complaint assignment conflict', 'INVALID_STATUS_TRANSITION');
    }

    const assignmentSnapshot = {
      assignmentType: input.assignmentType,
      assignedToUserId,
      assignedToNameSnapshot,
      externalAssigneeName: externalAssignee?.name,
    };

    await appendHistory(
      {
        complaintId,
        societyId,
        action: isReassign ? 'REASSIGNED' : 'ASSIGNED',
        previousStatus,
        newStatus: nextStatus,
        actor,
        notes: input.notes,
        publicNotes: isReassign
          ? `Reassigned to ${assignedToNameSnapshot}`
          : `Assigned to ${assignedToNameSnapshot}`,
        assignmentSnapshot,
      },
      session,
    );

    await writeAuditLog(
      {
        action: isReassign ? 'COMPLAINT_REASSIGNED' : 'COMPLAINT_ASSIGNED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: assignmentSnapshot,
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitComplaintEvent(
    isReassign ? 'complaint:reassigned' : 'complaint:assigned',
    complaintEventPayloadFromDoc(updated),
  );

  if (updated.assignedToUserId) {
    await notifyBusinessEvent({
      societyId,
      recipientUserId: String(updated.assignedToUserId),
      type: 'COMPLAINT_ASSIGNED',
      title: isReassign ? 'Complaint reassigned to you' : 'Complaint assigned to you',
      body: updated.title,
      relatedEntityType: 'Complaint',
      relatedEntityId: String(updated._id),
      idempotencyKey: `COMPLAINT_ASSIGNED:${String(updated._id)}:${String(updated.assignedToUserId)}:${updated.status}`,
    });
  }

  await notifyRaisedByStatusChange(societyId, updated, ':assign');

  return serializeComplaint(updated, { includeInternalNotes: true });
}

export async function unassignComplaint(
  societyId: string,
  complaintId: string,
  reason: string | undefined,
  actor: Actor,
) {
  const complaint = await loadComplaint(societyId, complaintId);
  assertTransition(complaint.status, 'OPEN');
  if (complaint.status !== 'ASSIGNED') {
    throw conflict('Only ASSIGNED complaints can be unassigned', 'INVALID_STATUS_TRANSITION');
  }

  const updated = await withTransaction(async (session) => {
    const claimed = await ComplaintModel.findOneAndUpdate(
      { _id: complaint._id, status: 'ASSIGNED' },
      {
        $set: { status: 'OPEN' },
        $unset: {
          assignmentType: 1,
          assignedToUserId: 1,
          assignedToNameSnapshot: 1,
          externalAssignee: 1,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Unassign conflict', 'INVALID_STATUS_TRANSITION');
    }

    await appendHistory(
      {
        complaintId,
        societyId,
        action: 'UNASSIGNED',
        previousStatus: 'ASSIGNED',
        newStatus: 'OPEN',
        actor,
        notes: reason,
        publicNotes: 'Assignment cleared',
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_UNASSIGNED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: { reason },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitComplaintEvent('complaint:status_changed', complaintEventPayloadFromDoc(updated), {
    notifyAssignee: false,
  });

  return serializeComplaint(updated, { includeInternalNotes: true });
}

export async function startComplaint(
  societyId: string,
  complaintId: string,
  actor: Actor,
) {
  const complaint = await loadComplaint(societyId, complaintId);
  assertTransition(complaint.status, 'IN_PROGRESS');

  const updated = await withTransaction(async (session) => {
    const claimed = await ComplaintModel.findOneAndUpdate(
      { _id: complaint._id, status: 'ASSIGNED' },
      { $set: { status: 'IN_PROGRESS' } },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Complaint must be ASSIGNED to start', 'INVALID_STATUS_TRANSITION');
    }

    await appendHistory(
      {
        complaintId,
        societyId,
        action: 'STARTED',
        previousStatus: 'ASSIGNED',
        newStatus: 'IN_PROGRESS',
        actor,
        publicNotes: 'Work started',
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_STARTED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: {},
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitComplaintEvent('complaint:status_changed', complaintEventPayloadFromDoc(updated));
  await notifyRaisedByStatusChange(societyId, updated);
  return serializeComplaint(updated, { includeInternalNotes: true });
}

export async function resolveComplaint(
  societyId: string,
  complaintId: string,
  resolutionNotes: string,
  internalNotes: string | undefined,
  actor: Actor,
) {
  if (!resolutionNotes?.trim()) {
    throw badRequest('Resolution notes are required', 'RESOLUTION_NOTES_REQUIRED');
  }
  const complaint = await loadComplaint(societyId, complaintId);
  assertTransition(complaint.status, 'RESOLVED');

  const updated = await withTransaction(async (session) => {
    const claimed = await ComplaintModel.findOneAndUpdate(
      { _id: complaint._id, status: 'IN_PROGRESS' },
      {
        $set: {
          status: 'RESOLVED',
          resolutionNotes: resolutionNotes.trim(),
          internalNotes: internalNotes?.trim(),
          resolvedAt: new Date(),
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Complaint must be IN_PROGRESS to resolve', 'INVALID_STATUS_TRANSITION');
    }

    await appendHistory(
      {
        complaintId,
        societyId,
        action: 'RESOLVED',
        previousStatus: 'IN_PROGRESS',
        newStatus: 'RESOLVED',
        actor,
        notes: internalNotes,
        publicNotes: resolutionNotes.trim(),
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_RESOLVED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: {},
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitComplaintEvent('complaint:status_changed', complaintEventPayloadFromDoc(updated));
  await notifyRaisedByStatusChange(societyId, updated);
  const { invalidateComplaintCaches } = await import('../../../cache/cache-invalidation');
  await invalidateComplaintCaches(societyId);
  return serializeComplaint(updated, { includeInternalNotes: true });
}

export async function closeComplaint(
  societyId: string,
  complaintId: string,
  actor: Actor,
) {
  const complaint = await loadComplaint(societyId, complaintId);
  assertTransition(complaint.status, 'CLOSED');

  const updated = await withTransaction(async (session) => {
    const claimed = await ComplaintModel.findOneAndUpdate(
      { _id: complaint._id, status: 'RESOLVED' },
      {
        $set: {
          status: 'CLOSED',
          closedAt: new Date(),
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Complaint must be RESOLVED to close', 'INVALID_STATUS_TRANSITION');
    }

    await appendHistory(
      {
        complaintId,
        societyId,
        action: 'CLOSED',
        previousStatus: 'RESOLVED',
        newStatus: 'CLOSED',
        actor,
        publicNotes: 'Complaint closed',
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_CLOSED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: {
          resolutionNotesPreserved: Boolean(claimed.resolutionNotes),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitComplaintEvent('complaint:status_changed', complaintEventPayloadFromDoc(updated));
  await notifyRaisedByStatusChange(societyId, updated);
  const { invalidateComplaintCaches } = await import('../../../cache/cache-invalidation');
  await invalidateComplaintCaches(societyId);
  return serializeComplaint(updated, { includeInternalNotes: true });
}

export async function cancelAdminComplaint(
  societyId: string,
  complaintId: string,
  reason: string,
  actor: Actor,
) {
  if (!reason?.trim()) {
    throw badRequest('Cancellation reason is required', 'CANCELLATION_REASON_REQUIRED');
  }
  const complaint = await loadComplaint(societyId, complaintId);
  if (complaint.status === 'CLOSED' || complaint.status === 'CANCELLED') {
    throw conflict('Complaint is already terminal', 'INVALID_STATUS_TRANSITION');
  }
  if (complaint.status === 'RESOLVED') {
    throw conflict('Resolved complaints cannot be cancelled; close them instead', 'INVALID_STATUS_TRANSITION');
  }
  assertTransition(complaint.status, 'CANCELLED');
  const previousStatus = complaint.status;

  const updated = await withTransaction(async (session) => {
    const claimed = await ComplaintModel.findOneAndUpdate(
      {
        _id: complaint._id,
        status: { $in: ['OPEN', 'ASSIGNED', 'IN_PROGRESS'] },
      },
      {
        $set: {
          status: 'CANCELLED',
          cancelledAt: new Date(),
          cancellationReason: reason.trim(),
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Cancellation conflict', 'INVALID_STATUS_TRANSITION');
    }

    await appendHistory(
      {
        complaintId,
        societyId,
        action: 'CANCELLED',
        previousStatus,
        newStatus: 'CANCELLED',
        actor,
        notes: reason.trim(),
        publicNotes: reason.trim(),
      },
      session,
    );

    await writeAuditLog(
      {
        action: 'COMPLAINT_CANCELLED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Complaint',
        targetId: complaintId,
        metadata: { reason: reason.trim(), by: 'admin' },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );

    return claimed;
  });

  emitComplaintEvent('complaint:status_changed', complaintEventPayloadFromDoc(updated));
  await notifyRaisedByStatusChange(societyId, updated);
  return serializeComplaint(updated, { includeInternalNotes: true });
}

export async function getComplaintSummary(
  societyId: string,
  query: { from?: Date; to?: Date } = {},
) {
  const match: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.from || query.to) {
    match.createdAt = {};
    if (query.from) (match.createdAt as Record<string, Date>).$gte = query.from;
    if (query.to) (match.createdAt as Record<string, Date>).$lte = query.to;
  }

  const [byStatus, highUrgent, byCategory, total] = await Promise.all([
    ComplaintModel.aggregate<{ _id: string; count: number }>([
      { $match: match },
      { $group: { _id: '$status', count: { $sum: 1 } } },
    ]),
    ComplaintModel.countDocuments({
      ...match,
      priority: { $in: ['HIGH', 'URGENT'] },
      status: { $nin: ['CLOSED', 'CANCELLED'] },
    }),
    ComplaintModel.aggregate<{ _id: string; count: number }>([
      { $match: match },
      { $group: { _id: '$category', count: { $sum: 1 } } },
    ]),
    ComplaintModel.countDocuments(match),
  ]);

  const statusCounts = Object.fromEntries(byStatus.map((r) => [r._id, r.count]));
  return {
    total,
    open: statusCounts.OPEN ?? 0,
    assigned: statusCounts.ASSIGNED ?? 0,
    inProgress: statusCounts.IN_PROGRESS ?? 0,
    resolved: statusCounts.RESOLVED ?? 0,
    closed: statusCounts.CLOSED ?? 0,
    cancelled: statusCounts.CANCELLED ?? 0,
    highAndUrgentOpen: highUrgent,
    byCategory: Object.fromEntries(byCategory.map((r) => [r._id, r.count])),
  };
}

export async function addComplaintAttachment(
  societyId: string,
  complaintId: string,
  userId: string,
  file: { buffer: Buffer; originalname: string },
  actor: Actor,
  options: { asAdmin?: boolean } = {},
) {
  const env = getEnv();
  const complaint = await loadComplaint(societyId, complaintId);

  if (!options.asAdmin) {
    await assertResidentCanView(societyId, userId, complaint);
    if (String(complaint.raisedByUserId) !== userId) {
      throw forbidden('Only the raiser may add attachments', 'ATTACHMENT_FORBIDDEN');
    }
    if (complaint.status !== 'OPEN') {
      throw conflict('Attachments can only be added while OPEN', 'INVALID_STATUS_TRANSITION');
    }
  } else if (complaint.status === 'CLOSED' || complaint.status === 'CANCELLED') {
    throw conflict('Cannot attach files to a terminal complaint', 'INVALID_STATUS_TRANSITION');
  }

  if (complaint.attachments.length >= env.COMPLAINT_ATTACHMENT_MAX_COUNT) {
    throw badRequest(
      `Maximum of ${env.COMPLAINT_ATTACHMENT_MAX_COUNT} attachments allowed`,
      'ATTACHMENT_LIMIT',
    );
  }
  if (file.buffer.length > env.COMPLAINT_ATTACHMENT_MAX_BYTES) {
    throw badRequest(
      `Attachment exceeds maximum size of ${env.COMPLAINT_ATTACHMENT_MAX_BYTES} bytes`,
      'ATTACHMENT_TOO_LARGE',
    );
  }

  const mimeType = assertApprovedImageBuffer(
    file.buffer,
    env.COMPLAINT_ALLOWED_MIME_TYPES.split(',').map((s) => s.trim()),
  );

  const storage = getComplaintStorage();
  const stored = await storage.put({
    societyId,
    complaintId,
    buffer: file.buffer,
    mimeType,
  });

  const attachmentId = new Types.ObjectId();
  let updated;
  try {
    updated = await withTransaction(async (session) => {
      const claimed = await ComplaintModel.findOneAndUpdate(
        {
          _id: complaint._id,
          [`attachments.${env.COMPLAINT_ATTACHMENT_MAX_COUNT - 1}`]: { $exists: false },
        },
        {
          $push: {
            attachments: {
              _id: attachmentId,
              storageKey: stored.storageKey,
              mimeType,
              sizeBytes: stored.sizeBytes,
              originalFilename: file.originalname.slice(0, 255),
              uploadedByUserId: userId,
              createdAt: new Date(),
            },
          },
        },
        { session, new: true },
      );
      if (!claimed) {
        throw conflict('Attachment could not be added', 'ATTACHMENT_CONFLICT');
      }

      await appendHistory(
        {
          complaintId,
          societyId,
          action: 'ATTACHMENT_ADDED',
          previousStatus: claimed.status,
          newStatus: claimed.status,
          actor,
          publicNotes: 'Attachment added',
          metadata: { attachmentId: String(attachmentId), mimeType },
        },
        session,
      );

      await writeAuditLog(
        {
          action: 'COMPLAINT_ATTACHMENT_ADDED',
          actorUserId: actor.userId,
          societyId,
          targetType: 'Complaint',
          targetId: complaintId,
          metadata: { attachmentId: String(attachmentId), mimeType, sizeBytes: stored.sizeBytes },
          ipAddress: actor.ipAddress,
          userAgent: actor.userAgent,
        },
        session,
      );

      return claimed;
    });
  } catch (error) {
    await storage.delete(stored.storageKey).catch(() => undefined);
    throw error;
  }

  const att = updated.attachments.find((a) => String(a._id) === String(attachmentId));
  return {
    complaint: serializeComplaint(updated, { includeInternalNotes: Boolean(options.asAdmin) }),
    attachment: att
      ? {
          id: String(att._id),
          mimeType: att.mimeType,
          sizeBytes: att.sizeBytes,
          originalFilename: att.originalFilename,
        }
      : undefined,
  };
}

export async function getComplaintAttachmentFile(
  societyId: string,
  complaintId: string,
  attachmentId: string,
  userId: string,
  options: { asAdmin?: boolean } = {},
) {
  const complaint = await loadComplaint(societyId, complaintId);
  if (!options.asAdmin) {
    await assertResidentCanView(societyId, userId, complaint);
  }

  const att = complaint.attachments.find((a) => String(a._id) === attachmentId);
  if (!att) throw notFound('Attachment not found');

  const buffer = await getComplaintStorage().get(att.storageKey);
  return {
    buffer,
    mimeType: att.mimeType,
    originalFilename: att.originalFilename,
  };
}
