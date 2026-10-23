import '../http/json_read.dart';

const kNotificationTypes = [
  'ANNOUNCEMENT',
  'BILL_GENERATED',
  'BILL_OVERDUE',
  'PAYMENT_SUCCESS',
  'PAYMENT_FAILED',
  'VISITOR_REQUEST',
  'VISITOR_APPROVED',
  'VISITOR_REJECTED',
  'VISITOR_ENTERED',
  'VISITOR_EXPIRED',
  'PARCEL_AWAITING_HANDOVER',
  'PARCEL_RECEIVED',
  'COMPLAINT_ASSIGNED',
  'COMPLAINT_STATUS_CHANGED',
  'FACILITY_BOOKING_APPROVED',
  'FACILITY_BOOKING_REJECTED',
  'FACILITY_BOOKING_CANCELLED',
  'STAFF_SHIFT_ASSIGNED',
  'SYSTEM',
];

String notificationTypeLabel(String type) {
  switch (type) {
    case 'ANNOUNCEMENT':
      return 'Announcement';
    case 'BILL_GENERATED':
      return 'Bill';
    case 'BILL_OVERDUE':
      return 'Overdue bill';
    case 'PAYMENT_SUCCESS':
      return 'Payment success';
    case 'PAYMENT_FAILED':
      return 'Payment failed';
    case 'VISITOR_REQUEST':
      return 'Visitor request';
    case 'VISITOR_APPROVED':
      return 'Visitor approved';
    case 'VISITOR_REJECTED':
      return 'Visitor rejected';
    case 'VISITOR_ENTERED':
      return 'Visitor entered';
    case 'VISITOR_EXPIRED':
      return 'Visitor expired';
    case 'PARCEL_AWAITING_HANDOVER':
      return 'Parcel awaiting handover';
    case 'PARCEL_RECEIVED':
      return 'Parcel received';
    case 'COMPLAINT_ASSIGNED':
      return 'Complaint assigned';
    case 'COMPLAINT_STATUS_CHANGED':
      return 'Complaint update';
    case 'FACILITY_BOOKING_APPROVED':
      return 'Booking approved';
    case 'FACILITY_BOOKING_REJECTED':
      return 'Booking rejected';
    case 'FACILITY_BOOKING_CANCELLED':
      return 'Booking cancelled';
    case 'STAFF_SHIFT_ASSIGNED':
      return 'Shift assigned';
    case 'SYSTEM':
      return 'System';
    default:
      return 'Notification';
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.societyId,
    required this.recipientUserId,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    required this.updatedAt,
    this.relatedEntityType,
    this.relatedEntityId,
    this.readAt,
    this.metadata,
  });

  final String id;
  final String societyId;
  final String recipientUserId;
  final String type;
  final String title;
  final String body;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final bool isRead;
  final String? readAt;
  final String createdAt;
  final String updatedAt;
  final Map<String, Object?>? metadata;

  String? metadataString(String key) {
    final value = metadata?[key];
    return value is String ? value : value?.toString();
  }

  bool get isKnownType => kNotificationTypes.contains(type);

  factory AppNotification.fromJson(Object? data) {
    final json = requireMap(data, 'notification');
    return AppNotification(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      recipientUserId: requireString(json, 'recipientUserId'),
      type: requireString(json, 'type'),
      title: requireString(json, 'title'),
      body: requireString(json, 'body'),
      relatedEntityType: optionalString(json, 'relatedEntityType'),
      relatedEntityId: optionalString(json, 'relatedEntityId'),
      isRead: requireBool(json, 'isRead'),
      readAt: optionalString(json, 'readAt'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
      metadata: optionalJsonMap(json, 'metadata'),
    );
  }
}

class UnreadCount {
  const UnreadCount({required this.unreadCount});
  final int unreadCount;

  factory UnreadCount.fromJson(Object? data) {
    final json = requireMap(data, 'unread count');
    return UnreadCount(unreadCount: requireInt(json, 'unreadCount'));
  }
}

class MarkAllReadResult {
  const MarkAllReadResult({required this.updated});
  final int updated;

  factory MarkAllReadResult.fromJson(Object? data) {
    final json = requireMap(data, 'mark all read');
    return MarkAllReadResult(updated: requireInt(json, 'updated'));
  }
}

class ListNotificationsQuery {
  const ListNotificationsQuery({
    this.isRead,
    this.type,
    this.page,
    this.limit,
  });

  final bool? isRead;
  final String? type;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'isRead': isRead == null ? null : (isRead! ? 'true' : 'false'),
        'type': type,
        'page': page,
        'limit': limit,
      };
}

class NotificationEventPayload {
  const NotificationEventPayload({
    required this.id,
    required this.societyId,
    required this.recipientUserId,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.relatedEntityType,
    this.relatedEntityId,
    this.metadata,
  });

  final String id;
  final String societyId;
  final String recipientUserId;
  final String type;
  final String title;
  final String body;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final bool isRead;
  final String createdAt;
  final Map<String, Object?>? metadata;

  factory NotificationEventPayload.fromJson(Object? data) {
    final json = requireMap(data, 'notification event');
    return NotificationEventPayload(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      recipientUserId: requireString(json, 'recipientUserId'),
      type: requireString(json, 'type'),
      title: requireString(json, 'title'),
      body: requireString(json, 'body'),
      relatedEntityType: optionalString(json, 'relatedEntityType'),
      relatedEntityId: optionalString(json, 'relatedEntityId'),
      isRead: requireBool(json, 'isRead'),
      createdAt: requireString(json, 'createdAt'),
      metadata: optionalJsonMap(json, 'metadata'),
    );
  }
}

const kNotificationSocketEvents = ['notification:created'];
