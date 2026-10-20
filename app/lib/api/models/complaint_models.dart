import '../http/json_read.dart';

const kComplaintCategories = [
  'PLUMBING',
  'ELECTRICAL',
  'LIFT',
  'CLEANING',
  'SECURITY',
  'PARKING',
  'WATER_SUPPLY',
  'STRUCTURAL',
  'OTHER',
];

const kComplaintPriorities = ['LOW', 'MEDIUM', 'HIGH', 'URGENT'];

const kComplaintStatuses = [
  'OPEN',
  'ASSIGNED',
  'IN_PROGRESS',
  'RESOLVED',
  'CLOSED',
  'CANCELLED',
];

const kComplaintHistoryActions = [
  'CREATED',
  'PRIORITY_CHANGED',
  'ASSIGNED',
  'REASSIGNED',
  'UNASSIGNED',
  'STARTED',
  'RESOLVED',
  'CLOSED',
  'CANCELLED',
  'ATTACHMENT_ADDED',
];

/// Backend default attachment limits.
const kComplaintAttachmentMaxBytes = 5 * 1024 * 1024;
const kComplaintAttachmentMaxCount = 5;
const kComplaintAttachmentMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
};

const kComplaintSocketEvents = [
  'complaint:assigned',
  'complaint:reassigned',
  'complaint:status_changed',
];

String complaintCategoryLabel(String category) {
  switch (category) {
    case 'PLUMBING':
      return 'Plumbing';
    case 'ELECTRICAL':
      return 'Electrical';
    case 'LIFT':
      return 'Lift';
    case 'CLEANING':
      return 'Cleaning';
    case 'SECURITY':
      return 'Security';
    case 'PARKING':
      return 'Parking';
    case 'WATER_SUPPLY':
      return 'Water supply';
    case 'STRUCTURAL':
      return 'Structural';
    case 'OTHER':
      return 'Other';
    default:
      return category;
  }
}

String complaintStatusLabel(String status) {
  switch (status) {
    case 'OPEN':
      return 'Open';
    case 'ASSIGNED':
      return 'Assigned';
    case 'IN_PROGRESS':
      return 'In progress';
    case 'RESOLVED':
      return 'Resolved';
    case 'CLOSED':
      return 'Closed';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return status;
  }
}

String complaintPriorityLabel(String priority) {
  switch (priority) {
    case 'LOW':
      return 'Low';
    case 'MEDIUM':
      return 'Medium';
    case 'HIGH':
      return 'High';
    case 'URGENT':
      return 'Urgent';
    default:
      return priority;
  }
}

class ComplaintAttachment {
  const ComplaintAttachment({
    required this.id,
    required this.mimeType,
    required this.sizeBytes,
    required this.originalFilename,
    required this.uploadedByUserId,
    required this.createdAt,
  });

  final String id;
  final String mimeType;
  final int sizeBytes;
  final String originalFilename;
  final String uploadedByUserId;
  final String createdAt;

  factory ComplaintAttachment.fromJson(JsonMap json) {
    return ComplaintAttachment(
      id: requireString(json, 'id'),
      mimeType: requireString(json, 'mimeType'),
      sizeBytes: requireInt(json, 'sizeBytes'),
      originalFilename: requireString(json, 'originalFilename'),
      uploadedByUserId: requireString(json, 'uploadedByUserId'),
      createdAt: requireString(json, 'createdAt'),
    );
  }
}

class ExternalAssignee {
  const ExternalAssignee({
    required this.name,
    this.phone,
    this.company,
  });

  final String name;
  final String? phone;
  final String? company;

  factory ExternalAssignee.fromJson(JsonMap json) {
    return ExternalAssignee(
      name: requireString(json, 'name'),
      phone: optionalString(json, 'phone'),
      company: optionalString(json, 'company'),
    );
  }

  Map<String, Object?> toJson() => omitNulls({
        'name': name,
        'phone': phone,
        'company': company,
      });
}

class Complaint {
  const Complaint({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.complaintNumber,
    required this.raisedByUserId,
    required this.raisedByRole,
    required this.category,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.attachments,
    required this.createdAt,
    required this.updatedAt,
    this.assignmentType,
    this.assignedToUserId,
    this.assignedToNameSnapshot,
    this.externalAssignee,
    this.resolutionNotes,
    this.internalNotes,
    this.cancellationReason,
    this.resolvedAt,
    this.closedAt,
    this.cancelledAt,
    this.history = const [],
  });

  final String id;
  final String societyId;
  final String flatId;
  final String complaintNumber;
  final String raisedByUserId;
  final String raisedByRole;
  final String category;
  final String title;
  final String description;
  final String priority;
  final String status;
  final String? assignmentType;
  final String? assignedToUserId;
  final String? assignedToNameSnapshot;
  final ExternalAssignee? externalAssignee;
  final String? resolutionNotes;
  final String? internalNotes;
  final String? cancellationReason;
  final String? resolvedAt;
  final String? closedAt;
  final String? cancelledAt;
  final List<ComplaintAttachment> attachments;
  final String createdAt;
  final String updatedAt;
  final List<ComplaintHistoryItem> history;

  factory Complaint.fromJson(Object? data) {
    final json = requireMap(data, 'complaint');
    final external = json['externalAssignee'];
    final historyRaw = json['history'];
    return Complaint(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      complaintNumber: requireString(json, 'complaintNumber'),
      raisedByUserId: requireString(json, 'raisedByUserId'),
      raisedByRole: requireString(json, 'raisedByRole'),
      category: requireString(json, 'category'),
      title: requireString(json, 'title'),
      description: requireString(json, 'description'),
      priority: requireString(json, 'priority'),
      status: requireString(json, 'status'),
      assignmentType: optionalString(json, 'assignmentType'),
      assignedToUserId: optionalString(json, 'assignedToUserId'),
      assignedToNameSnapshot: optionalString(json, 'assignedToNameSnapshot'),
      externalAssignee: external == null
          ? null
          : ExternalAssignee.fromJson(requireMap(external, 'externalAssignee')),
      resolutionNotes: optionalString(json, 'resolutionNotes'),
      internalNotes: optionalString(json, 'internalNotes'),
      cancellationReason: optionalString(json, 'cancellationReason'),
      resolvedAt: optionalString(json, 'resolvedAt'),
      closedAt: optionalString(json, 'closedAt'),
      cancelledAt: optionalString(json, 'cancelledAt'),
      attachments: requireMapList(json, 'attachments')
          .map(ComplaintAttachment.fromJson)
          .toList(),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
      history: historyRaw is List
          ? historyRaw
              .map(
                (item) => ComplaintHistoryItem.fromJson(
                  requireMap(item, 'history item'),
                ),
              )
              .toList()
          : const [],
    );
  }
}

class ComplaintHistoryItem {
  const ComplaintHistoryItem({
    required this.id,
    required this.complaintId,
    required this.societyId,
    required this.action,
    required this.actorUserId,
    required this.actorRole,
    required this.createdAt,
    this.previousStatus,
    this.newStatus,
    this.previousPriority,
    this.newPriority,
    this.notes,
    this.publicNotes,
    this.assignmentSnapshot,
  });

  final String id;
  final String complaintId;
  final String societyId;
  final String action;
  final String? previousStatus;
  final String? newStatus;
  final String? previousPriority;
  final String? newPriority;
  final String actorUserId;
  final String actorRole;
  final String? notes;
  final String? publicNotes;
  final Map<String, Object?>? assignmentSnapshot;
  final String createdAt;

  factory ComplaintHistoryItem.fromJson(JsonMap json) {
    final snap = json['assignmentSnapshot'];
    return ComplaintHistoryItem(
      id: requireString(json, 'id'),
      complaintId: requireString(json, 'complaintId'),
      societyId: requireString(json, 'societyId'),
      action: requireString(json, 'action'),
      previousStatus: optionalString(json, 'previousStatus'),
      newStatus: optionalString(json, 'newStatus'),
      previousPriority: optionalString(json, 'previousPriority'),
      newPriority: optionalString(json, 'newPriority'),
      actorUserId: requireString(json, 'actorUserId'),
      actorRole: requireString(json, 'actorRole'),
      notes: optionalString(json, 'notes'),
      publicNotes: optionalString(json, 'publicNotes'),
      assignmentSnapshot: snap is Map
          ? snap.map((k, v) => MapEntry(k.toString(), v))
          : null,
      createdAt: requireString(json, 'createdAt'),
    );
  }
}

class CreateComplaintRequest {
  const CreateComplaintRequest({
    required this.flatId,
    required this.category,
    required this.title,
    required this.description,
  });

  final String flatId;
  final String category;
  final String title;
  final String description;

  Map<String, Object?> toJson() => {
        'flatId': flatId,
        'category': category,
        'title': title,
        'description': description,
      };
}

class ListComplaintsQuery {
  const ListComplaintsQuery({
    this.status,
    this.category,
    this.priority,
    this.flatId,
    this.assignedToUserId,
    this.from,
    this.to,
    this.page,
    this.limit,
  });

  final String? status;
  final String? category;
  final String? priority;
  final String? flatId;
  final String? assignedToUserId;
  final String? from;
  final String? to;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'status': status,
        'category': category,
        'priority': priority,
        'flatId': flatId,
        'assignedToUserId': assignedToUserId,
        'from': from,
        'to': to,
        'page': page,
        'limit': limit,
      };
}

class ComplaintSummary {
  const ComplaintSummary({
    required this.total,
    required this.open,
    required this.assigned,
    required this.inProgress,
    required this.resolved,
    required this.closed,
    required this.cancelled,
    required this.highAndUrgentOpen,
    required this.byCategory,
  });

  final int total;
  final int open;
  final int assigned;
  final int inProgress;
  final int resolved;
  final int closed;
  final int cancelled;
  final int highAndUrgentOpen;
  final Map<String, int> byCategory;

  factory ComplaintSummary.fromJson(Object? data) {
    final json = requireMap(data, 'complaint summary');
    final raw = json['byCategory'];
    final byCategory = <String, int>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is num) {
          byCategory[e.key as String] = (e.value as num).toInt();
        }
      }
    }
    return ComplaintSummary(
      total: requireInt(json, 'total'),
      open: requireInt(json, 'open'),
      assigned: requireInt(json, 'assigned'),
      inProgress: requireInt(json, 'inProgress'),
      resolved: requireInt(json, 'resolved'),
      closed: requireInt(json, 'closed'),
      cancelled: requireInt(json, 'cancelled'),
      highAndUrgentOpen: requireInt(json, 'highAndUrgentOpen'),
      byCategory: byCategory,
    );
  }
}

class ComplaintAttachmentUploadResult {
  const ComplaintAttachmentUploadResult({
    required this.complaint,
    this.attachment,
  });

  final Complaint complaint;
  final ComplaintAttachment? attachment;

  factory ComplaintAttachmentUploadResult.fromJson(Object? data) {
    final json = requireMap(data, 'attachment upload');
    final attachment = json['attachment'];
    return ComplaintAttachmentUploadResult(
      complaint: Complaint.fromJson(json['complaint']),
      attachment: attachment == null
          ? null
          : ComplaintAttachment.fromJson(
              requireMap(attachment, 'attachment'),
            ),
    );
  }
}

class ComplaintEventPayload {
  const ComplaintEventPayload({
    required this.complaintId,
    required this.societyId,
    required this.flatId,
    required this.complaintNumber,
    required this.status,
    required this.priority,
    required this.category,
    required this.title,
    required this.raisedByUserId,
    this.assignedToUserId,
  });

  final String complaintId;
  final String societyId;
  final String flatId;
  final String complaintNumber;
  final String status;
  final String priority;
  final String category;
  final String title;
  final String raisedByUserId;
  final String? assignedToUserId;

  factory ComplaintEventPayload.fromJson(Object? data) {
    final json = requireMap(data, 'complaint event');
    return ComplaintEventPayload(
      complaintId: requireString(json, 'complaintId'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      complaintNumber: requireString(json, 'complaintNumber'),
      status: requireString(json, 'status'),
      priority: requireString(json, 'priority'),
      category: requireString(json, 'category'),
      title: requireString(json, 'title'),
      raisedByUserId: requireString(json, 'raisedByUserId'),
      assignedToUserId: optionalString(json, 'assignedToUserId'),
    );
  }
}
