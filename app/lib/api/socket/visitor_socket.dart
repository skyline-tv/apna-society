import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/app_role.dart';
import '../auth/auth_session.dart';
import '../models/announcement_models.dart';
import '../models/complaint_models.dart';
import '../models/facility_models.dart';
import '../models/notification_models.dart';
import '../models/visitor_models.dart';
import '../repositories/live_repositories.dart';

/// Authenticated Socket.IO client for live society events.
///
/// Visitor: `visitor:approval_requested|approved|rejected|entered|exited`.
/// Complaint: `complaint:assigned|reassigned|status_changed`.
/// Facility: `facility:booking_approved|rejected|cancelled`.
/// Announcement: `announcement:published`.
/// Notification: `notification:created`.
/// REST remains authoritative; this layer only invalidates caches and notifies UI.
class VisitorSocket {
  VisitorSocket._();

  static VisitorSocket? _instance;
  static VisitorSocket get instance => _instance ??= VisitorSocket._();

  io.Socket? _socket;
  String? _joinedSocietyId;
  String? _joinMode;
  String? _authToken;
  final _visitorController = StreamController<VisitorEventPayload>.broadcast();
  final _complaintController =
      StreamController<ComplaintEventPayload>.broadcast();
  final _facilityController =
      StreamController<FacilityBookingEventPayload>.broadcast();
  final _announcementController =
      StreamController<AnnouncementEventPayload>.broadcast();
  final _notificationController =
      StreamController<NotificationEventPayload>.broadcast();

  Stream<VisitorEventPayload> get events => _visitorController.stream;
  Stream<ComplaintEventPayload> get complaintEvents =>
      _complaintController.stream;
  Stream<FacilityBookingEventPayload> get facilityBookingEvents =>
      _facilityController.stream;
  Stream<AnnouncementEventPayload> get announcementEvents =>
      _announcementController.stream;
  Stream<NotificationEventPayload> get notificationEvents =>
      _notificationController.stream;
  bool get isConnected => _socket?.connected == true;

  /// Connects (or reconnects) using the current session access token.
  ///
  /// When the access token rotates, forces a full reconnect so the handshake
  /// carries the new JWT. Same society/mode with the same token is a no-op.
  void connectForSession(AuthSession session) {
    final token = session.accessToken;
    final societyId = session.client.societyId;
    final role = session.appRole;
    if (token == null ||
        token.isEmpty ||
        societyId == null ||
        societyId.isEmpty ||
        role == null) {
      disconnect();
      return;
    }

    final mode = switch (role) {
      AppRole.guard => 'guards',
      AppRole.admin => 'admin',
      AppRole.owner || AppRole.tenant => 'resident',
    };

    final tokenUnchanged = _authToken == token;
    if (_socket != null &&
        _socket!.connected &&
        _joinedSocietyId == societyId &&
        _joinMode == mode &&
        tokenUnchanged) {
      return;
    }

    disconnect();

    final baseUrl = session.client.config.baseUrl;
    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );
    _authToken = token;

    void joinRooms() {
      final payload = {'societyId': societyId};
      if (mode == 'guards') {
        socket.emitWithAck('join:guards', payload, ack: (_) {});
      } else if (mode == 'admin') {
        // Visitors emit to guards; complaints emit to resident rooms.
        socket.emitWithAck('join:guards', payload, ack: (_) {});
        socket.emitWithAck('join:resident', payload, ack: (_) {});
      } else {
        socket.emitWithAck('join:resident', payload, ack: (_) {});
      }
      _joinedSocietyId = societyId;
      _joinMode = mode;
    }

    void onVisitorEvent(dynamic raw) {
      try {
        final event = VisitorEventPayload.fromJson(raw);
        liveRepositories?.invalidateAfterVisitorMutation(
          visitorId: event.visitorId,
        );
        if (!_visitorController.isClosed) {
          _visitorController.add(event);
        }
      } catch (_) {}
    }

    void onComplaintEvent(dynamic raw) {
      try {
        final event = ComplaintEventPayload.fromJson(raw);
        liveRepositories?.invalidateAfterComplaintMutation(
          complaintId: event.complaintId,
        );
        if (!_complaintController.isClosed) {
          _complaintController.add(event);
        }
      } catch (_) {}
    }

    void onFacilityEvent(dynamic raw) {
      try {
        final event = FacilityBookingEventPayload.fromJson(raw);
        liveRepositories?.invalidateAfterFacilityMutation(
          facilityId: event.facilityId,
          bookingId: event.bookingId,
        );
        if (!_facilityController.isClosed) {
          _facilityController.add(event);
        }
      } catch (_) {}
    }

    void onAnnouncementEvent(dynamic raw) {
      try {
        final event = AnnouncementEventPayload.fromJson(raw);
        liveRepositories?.invalidateAfterAnnouncementMutation(
          announcementId: event.announcementId,
        );
        if (!_announcementController.isClosed) {
          _announcementController.add(event);
        }
      } catch (_) {}
    }

    void onNotificationEvent(dynamic raw) {
      try {
        final event = NotificationEventPayload.fromJson(raw);
        liveRepositories?.invalidateAfterNotificationMutation(
          notificationId: event.id,
        );
        if (!_notificationController.isClosed) {
          _notificationController.add(event);
        }
      } catch (_) {}
    }

    for (final name in kVisitorSocketEvents) {
      socket.on(name, onVisitorEvent);
    }
    for (final name in kComplaintSocketEvents) {
      socket.on(name, onComplaintEvent);
    }
    for (final name in kFacilitySocketEvents) {
      socket.on(name, onFacilityEvent);
    }
    for (final name in kAnnouncementSocketEvents) {
      socket.on(name, onAnnouncementEvent);
    }
    for (final name in kNotificationSocketEvents) {
      socket.on(name, onNotificationEvent);
    }

    socket.onConnect((_) => joinRooms());
    socket.onReconnect((_) => joinRooms());
    socket.connect();
    _socket = socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _joinedSocietyId = null;
    _joinMode = null;
    _authToken = null;
  }

  /// Test helper: last handshake token retained by the socket layer.
  String? get debugAuthToken => _authToken;

  void dispose() {
    disconnect();
  }
}

/// Process helper used from logout / account change.
void disconnectVisitorSocket() {
  VisitorSocket.instance.disconnect();
}
