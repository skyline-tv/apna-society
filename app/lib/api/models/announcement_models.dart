import '../http/json_read.dart';

const kAnnouncementCategories = [
  'GENERAL',
  'MAINTENANCE',
  'WATER_SUPPLY',
  'ELECTRICITY',
  'SECURITY',
  'EVENT',
  'EMERGENCY',
  'MEETING',
  'PARKING',
  'OTHER',
];

const kAnnouncementPriorities = ['NORMAL', 'IMPORTANT', 'URGENT'];

const kAnnouncementStatuses = [
  'DRAFT',
  'SCHEDULED',
  'PUBLISHED',
  'ARCHIVED',
  'CANCELLED',
];

const kAudienceTypes = ['ALL_RESIDENTS', 'WING', 'SELECTED_FLATS'];
const kAudienceRoles = ['ALL', 'OWNERS', 'TENANTS'];

const kAnnouncementAttachmentMaxBytes = 5 * 1024 * 1024;
const kAnnouncementAttachmentMaxCount = 5;
const kAnnouncementAttachmentMimeTypes = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'application/pdf',
];

String announcementCategoryLabel(String v) {
  switch (v) {
    case 'GENERAL':
      return 'General';
    case 'MAINTENANCE':
      return 'Maintenance';
    case 'WATER_SUPPLY':
      return 'Water supply';
    case 'ELECTRICITY':
      return 'Electricity';
    case 'SECURITY':
      return 'Security';
    case 'EVENT':
      return 'Event';
    case 'EMERGENCY':
      return 'Emergency';
    case 'MEETING':
      return 'Meeting';
    case 'PARKING':
      return 'Parking';
    case 'OTHER':
      return 'Other';
    default:
      return v;
  }
}

String announcementStatusLabel(String v) {
  switch (v) {
    case 'DRAFT':
      return 'Draft';
    case 'SCHEDULED':
      return 'Scheduled';
    case 'PUBLISHED':
      return 'Published';
    case 'ARCHIVED':
      return 'Archived';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return v;
  }
}

String audienceTypeLabel(String v) {
  switch (v) {
    case 'ALL_RESIDENTS':
      return 'All residents';
    case 'WING':
      return 'Wing';
    case 'SELECTED_FLATS':
      return 'Selected flats';
    default:
      return v;
  }
}

String audienceRoleLabel(String v) {
  switch (v) {
    case 'OWNERS':
      return 'Owners only';
    case 'TENANTS':
      return 'Tenants only';
    case 'ALL':
      return 'Owners and tenants';
    default:
      return v;
  }
}

class AnnouncementAttachment {
  const AnnouncementAttachment({
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

  factory AnnouncementAttachment.fromJson(JsonMap json) {
    return AnnouncementAttachment(
      id: requireString(json, 'id'),
      mimeType: requireString(json, 'mimeType'),
      sizeBytes: requireInt(json, 'sizeBytes'),
      originalFilename: requireString(json, 'originalFilename'),
      uploadedByUserId: requireString(json, 'uploadedByUserId'),
      createdAt: requireString(json, 'createdAt'),
    );
  }
}

class Announcement {
  const Announcement({
    required this.id,
    required this.societyId,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.audienceType,
    this.audienceRole = 'ALL',
    required this.attachments,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.targetWingIds,
    this.targetFlatIds,
    this.publishedByUserId,
    this.publishedAt,
    this.scheduledAt,
    this.expiresAt,
    this.deliveryState,
    this.eligibleRecipientCount,
    this.notificationCreatedCount,
    this.createdBy,
    this.adminNotes,
    this.isRead,
  });

  final String id;
  final String societyId;
  final String title;
  final String body;
  final String category;
  final String priority;
  final String audienceType;
  final String audienceRole;
  final List<String>? targetWingIds;
  final List<String>? targetFlatIds;
  final List<AnnouncementAttachment> attachments;
  final String status;
  final String? publishedByUserId;
  final String? publishedAt;
  final String? scheduledAt;
  final String? expiresAt;
  final String? deliveryState;
  final int? eligibleRecipientCount;
  final int? notificationCreatedCount;
  final String? createdBy;
  final String? adminNotes;
  final bool? isRead;
  final String createdAt;
  final String updatedAt;

  factory Announcement.fromJson(Object? data) {
    final json = requireMap(data, 'announcement');
    final wings = json['targetWingIds'];
    final flats = json['targetFlatIds'];
    return Announcement(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      title: requireString(json, 'title'),
      body: requireString(json, 'body'),
      category: requireString(json, 'category'),
      priority: requireString(json, 'priority'),
      audienceType: requireString(json, 'audienceType'),
      audienceRole: optionalString(json, 'audienceRole') ?? 'ALL',
      targetWingIds: wings is List
          ? wings.map((e) => e.toString()).toList()
          : null,
      targetFlatIds: flats is List
          ? flats.map((e) => e.toString()).toList()
          : null,
      attachments: requireMapList(json, 'attachments')
          .map(AnnouncementAttachment.fromJson)
          .toList(),
      status: requireString(json, 'status'),
      publishedByUserId: optionalString(json, 'publishedByUserId'),
      publishedAt: optionalString(json, 'publishedAt'),
      scheduledAt: optionalString(json, 'scheduledAt'),
      expiresAt: optionalString(json, 'expiresAt'),
      deliveryState: optionalString(json, 'deliveryState'),
      eligibleRecipientCount: optionalInt(json, 'eligibleRecipientCount'),
      notificationCreatedCount: optionalInt(json, 'notificationCreatedCount'),
      createdBy: optionalString(json, 'createdBy'),
      adminNotes: optionalString(json, 'adminNotes'),
      isRead: optionalBool(json, 'isRead'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class CreateAnnouncementRequest {
  const CreateAnnouncementRequest({
    required this.title,
    required this.body,
    required this.category,
    required this.audienceType,
    this.audienceRole,
    this.priority,
    this.targetWingIds,
    this.targetFlatIds,
    this.expiresAt,
    this.adminNotes,
  });

  final String title;
  final String body;
  final String category;
  final String? priority;
  final String audienceType;
  final String? audienceRole;
  final List<String>? targetWingIds;
  final List<String>? targetFlatIds;
  final String? expiresAt;
  final String? adminNotes;

  Map<String, Object?> toJson() => omitNulls({
        'title': title,
        'body': body,
        'category': category,
        'priority': priority,
        'audienceType': audienceType,
        'audienceRole': audienceRole,
        'targetWingIds': targetWingIds,
        'targetFlatIds': targetFlatIds,
        'expiresAt': expiresAt,
        'adminNotes': adminNotes,
      });
}

class UpdateAnnouncementRequest {
  const UpdateAnnouncementRequest({
    this.title,
    this.body,
    this.category,
    this.priority,
    this.audienceType,
    this.audienceRole,
    this.targetWingIds,
    this.targetFlatIds,
    this.expiresAt,
    this.clearExpiresAt = false,
    this.adminNotes,
  });

  final String? title;
  final String? body;
  final String? category;
  final String? priority;
  final String? audienceType;
  final String? audienceRole;
  final List<String>? targetWingIds;
  final List<String>? targetFlatIds;
  final String? expiresAt;
  final bool clearExpiresAt;
  final String? adminNotes;

  Map<String, Object?> toJson() {
    final map = omitNulls({
      'title': title,
      'body': body,
      'category': category,
      'priority': priority,
      'audienceType': audienceType,
      'audienceRole': audienceRole,
      'targetWingIds': targetWingIds,
      'targetFlatIds': targetFlatIds,
      'adminNotes': adminNotes,
    });
    if (clearExpiresAt) {
      map['expiresAt'] = null;
    } else if (expiresAt != null) {
      map['expiresAt'] = expiresAt;
    }
    return map;
  }
}

class ListAdminAnnouncementsQuery {
  const ListAdminAnnouncementsQuery({
    this.status,
    this.category,
    this.priority,
    this.audienceType,
    this.page,
    this.limit,
  });

  final String? status;
  final String? category;
  final String? priority;
  final String? audienceType;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'status': status,
        'category': category,
        'priority': priority,
        'audienceType': audienceType,
        'page': page,
        'limit': limit,
      };
}

class ListResidentAnnouncementsQuery {
  const ListResidentAnnouncementsQuery({
    this.category,
    this.page,
    this.limit,
  });

  final String? category;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'category': category,
        'page': page,
        'limit': limit,
      };
}

class AnnouncementSummary {
  const AnnouncementSummary({
    required this.total,
    required this.byStatus,
  });

  final int total;
  final Map<String, int> byStatus;

  factory AnnouncementSummary.fromJson(Object? data) {
    final json = requireMap(data, 'announcement summary');
    final raw = json['byStatus'];
    final byStatus = <String, int>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is num) {
          byStatus[e.key.toString()] = (e.value as num).toInt();
        }
      }
    }
    return AnnouncementSummary(
      total: requireInt(json, 'total'),
      byStatus: byStatus,
    );
  }
}

class AnnouncementRecipientSummary {
  const AnnouncementRecipientSummary({
    required this.announcementId,
    required this.status,
    required this.deliveryState,
    required this.eligibleRecipientCount,
    required this.notificationCreatedCount,
    required this.readCount,
    this.note,
  });

  final String announcementId;
  final String status;
  final String deliveryState;
  final int eligibleRecipientCount;
  final int notificationCreatedCount;
  final int readCount;
  final String? note;

  factory AnnouncementRecipientSummary.fromJson(Object? data) {
    final json = requireMap(data, 'recipient summary');
    return AnnouncementRecipientSummary(
      announcementId: requireString(json, 'announcementId'),
      status: requireString(json, 'status'),
      deliveryState: requireString(json, 'deliveryState'),
      eligibleRecipientCount: requireInt(json, 'eligibleRecipientCount'),
      notificationCreatedCount: requireInt(json, 'notificationCreatedCount'),
      readCount: requireInt(json, 'readCount'),
      note: optionalString(json, 'note'),
    );
  }
}

class AnnouncementReadState {
  const AnnouncementReadState({required this.isRead});
  final bool isRead;

  factory AnnouncementReadState.fromJson(Object? data) {
    final json = requireMap(data, 'read state');
    return AnnouncementReadState(isRead: requireBool(json, 'isRead'));
  }
}

class AnnouncementAttachmentUploadResult {
  const AnnouncementAttachmentUploadResult({
    required this.announcement,
    required this.attachmentId,
    required this.mimeType,
    required this.sizeBytes,
  });

  final Announcement announcement;
  final String attachmentId;
  final String mimeType;
  final int sizeBytes;

  factory AnnouncementAttachmentUploadResult.fromJson(Object? data) {
    final json = requireMap(data, 'attachment upload');
    final att = requireMap(json['attachment'], 'attachment');
    return AnnouncementAttachmentUploadResult(
      announcement: Announcement.fromJson(json['announcement']),
      attachmentId: requireString(att, 'id'),
      mimeType: requireString(att, 'mimeType'),
      sizeBytes: requireInt(att, 'sizeBytes'),
    );
  }
}

class AnnouncementEventPayload {
  const AnnouncementEventPayload({
    required this.announcementId,
    required this.societyId,
    required this.title,
    required this.category,
    required this.priority,
    required this.publishedAt,
  });

  final String announcementId;
  final String societyId;
  final String title;
  final String category;
  final String priority;
  final String publishedAt;

  factory AnnouncementEventPayload.fromJson(Object? data) {
    final json = requireMap(data, 'announcement event');
    return AnnouncementEventPayload(
      announcementId: requireString(json, 'announcementId'),
      societyId: requireString(json, 'societyId'),
      title: requireString(json, 'title'),
      category: requireString(json, 'category'),
      priority: requireString(json, 'priority'),
      publishedAt: requireString(json, 'publishedAt'),
    );
  }
}

const kAnnouncementSocketEvents = ['announcement:published'];
