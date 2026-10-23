import 'package:flutter/material.dart';

import '../api/auth/app_role.dart';
import '../api/auth/auth_session.dart';
import '../api/models/notification_models.dart';
import '../features/announcements/live_announcements_module.dart';
import '../features/billing/live_billing_module.dart';
import '../features/parcels/live_parcels_module.dart';
import '../features/security/guard_desk.dart';
import '../features/visitors/incoming_visitor_page.dart';
import '../features/visitors/live_visitors_module.dart';

/// Supported in-app destinations for FCM / inbox taps.
///
/// URIs use `apnasociety://{kind}/{id}` and never carry secrets.
enum NotificationLinkKind {
  visitor,
  visitorApproval,
  bill,
  notice,
  parcel,
  inbox,
}

class NotificationDeepLink {
  const NotificationDeepLink({required this.kind, this.id});

  final NotificationLinkKind kind;
  final String? id;

  static NotificationDeepLink? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.scheme != 'apnasociety') return null;
    final host = uri.host;
    final pathId = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    switch (host) {
      case 'visitor-approval':
        return NotificationDeepLink(
          kind: NotificationLinkKind.visitorApproval,
          id: pathId,
        );
      case 'visitor':
        return NotificationDeepLink(
          kind: NotificationLinkKind.visitor,
          id: pathId,
        );
      case 'bill':
        return NotificationDeepLink(
          kind: NotificationLinkKind.bill,
          id: pathId,
        );
      case 'notice':
        return NotificationDeepLink(
          kind: NotificationLinkKind.notice,
          id: pathId,
        );
      case 'parcel':
        return NotificationDeepLink(
          kind: NotificationLinkKind.parcel,
          id: pathId,
        );
      default:
        return const NotificationDeepLink(kind: NotificationLinkKind.inbox);
    }
  }

  static NotificationDeepLink? fromFcmData(Map<String, String> data) {
    final fromUri = parse(data['deepLink']);
    if (fromUri != null) return fromUri;
    final type = data['type'] ?? '';
    final entityId = (data['relatedEntityId'] ?? '').trim();
    final id = entityId.isEmpty ? null : entityId;
    switch (type) {
      case 'VISITOR_REQUEST':
        return NotificationDeepLink(
          kind: data['entryMode'] == 'WALK_IN'
              ? NotificationLinkKind.visitorApproval
              : NotificationLinkKind.visitor,
          id: id,
        );
      case 'VISITOR_APPROVED':
      case 'VISITOR_REJECTED':
      case 'VISITOR_ENTERED':
      case 'VISITOR_EXPIRED':
        return NotificationDeepLink(
          kind: NotificationLinkKind.visitor,
          id: id,
        );
      case 'BILL_GENERATED':
      case 'BILL_OVERDUE':
        return NotificationDeepLink(kind: NotificationLinkKind.bill, id: id);
      case 'ANNOUNCEMENT':
        return NotificationDeepLink(kind: NotificationLinkKind.notice, id: id);
      case 'PARCEL_AWAITING_HANDOVER':
      case 'PARCEL_RECEIVED':
        return NotificationDeepLink(kind: NotificationLinkKind.parcel, id: id);
      default:
        return const NotificationDeepLink(kind: NotificationLinkKind.inbox);
    }
  }

  static NotificationDeepLink fromNotification(AppNotification n) {
    final fromMeta = parse(n.metadataString('deepLink'));
    if (fromMeta != null) return fromMeta;
    return fromFcmData({
      'type': n.type,
      'relatedEntityId': n.relatedEntityId ?? '',
      'entryMode': n.metadataString('entryMode') ?? '',
    })!;
  }
}

/// Builds the screen for a notification tap. Returns null when the current
/// role has no safe destination (backend remains authoritative).
Widget? widgetForNotificationDeepLink(NotificationDeepLink link) {
  final role = authSession?.appRole;
  if (role == null) return null;
  final id = link.id;
  switch (link.kind) {
    case NotificationLinkKind.visitorApproval:
      if (id == null) return null;
      if (role == AppRole.owner || role == AppRole.tenant) {
        return IncomingVisitorPage(visitorId: id);
      }
      return null;
    case NotificationLinkKind.visitor:
      if (id == null) return null;
      switch (role) {
        case AppRole.owner:
        case AppRole.tenant:
          return LiveResidentVisitorDetailPage(visitorId: id);
        case AppRole.guard:
          return GuardVisitorStatusPage(visitorId: id);
        case AppRole.admin:
          return LiveAdminVisitorDetailPage(visitorId: id);
      }
    case NotificationLinkKind.bill:
      if (id == null || role != AppRole.owner) return null;
      return LiveOwnerBillDetailPage(billId: id);
    case NotificationLinkKind.notice:
      if (id == null) return null;
      if (role == AppRole.owner || role == AppRole.tenant) {
        return LiveResidentAnnouncementDetailPage(announcementId: id);
      }
      return null;
    case NotificationLinkKind.parcel:
      if (id == null) return null;
      switch (role) {
        case AppRole.owner:
        case AppRole.tenant:
          return LiveResidentParcelDetailPage(parcelId: id);
        case AppRole.guard:
          return null;
        case AppRole.admin:
          return LiveResidentParcelDetailPage(parcelId: id);
      }
    case NotificationLinkKind.inbox:
      return null;
  }
}
