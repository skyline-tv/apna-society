import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/auth/app_role.dart';
import '../api/auth/auth_session.dart';
import '../api/models/visitor_models.dart';
import '../api/socket/visitor_socket.dart';
import 'notification_deep_link.dart';

/// Coordinates Android incoming-call alerts for walk-in visitor requests.
///
/// Native code owns ringtone / CallStyle / full-screen intent. This layer
/// opens [IncomingVisitorPage], dedupes alerts, and stops ringing when the
/// request is approved, rejected, or expired — including from another device.
class IncomingVisitorCallCoordinator {
  IncomingVisitorCallCoordinator._();

  static final IncomingVisitorCallCoordinator instance =
      IncomingVisitorCallCoordinator._();

  static const _methods =
      MethodChannel('com.skylinetv.apnasociety/incoming_visitor_call');
  static const _events =
      EventChannel('com.skylinetv.apnasociety/incoming_visitor_call_events');

  StreamSubscription<dynamic>? _nativeSub;
  StreamSubscription<VisitorEventPayload>? _socketSub;
  String? _openVisitorId;
  bool _bound = false;
  void Function(NotificationDeepLink link)? onOpenLink;
  void Function(String visitorId)? onIncomingClosed;

  bool get isBound => _bound;
  String? get openVisitorId => _openVisitorId;

  Future<void> bind() async {
    if (_bound) return;
    final role = authSession?.appRole;
    if (role != AppRole.owner && role != AppRole.tenant) return;
    _bound = true;
    _socketSub = VisitorSocket.instance.events.listen(_onSocket);
    if (Platform.isAndroid) {
      _nativeSub = _events.receiveBroadcastStream().listen(_onNativeEvent);
      try {
        final launched =
            await _methods.invokeMethod<String>('consumeLaunchVisitorId');
        if (launched != null && launched.isNotEmpty) {
          openIncoming(launched);
        }
      } catch (error) {
        debugPrint('Incoming visitor launch id unavailable: $error');
      }
    }
  }

  Future<void> unbind() async {
    final wasBound = _bound;
    await _nativeSub?.cancel();
    await _socketSub?.cancel();
    _nativeSub = null;
    _socketSub = null;
    _openVisitorId = null;
    _bound = false;
    if (wasBound) await stopAll();
  }

  /// FCM / local-notification data for a walk-in request or a stop signal.
  void handleFcmData(Map<String, String> data) {
    final type = data['type'] ?? '';
    final entryMode = data['entryMode'] ?? '';
    final visitorId =
        (data['relatedEntityId'] ?? data['requestId'] ?? '').trim();
    if (visitorId.isEmpty) return;
    if (type == 'VISITOR_REQUEST' && entryMode == 'WALK_IN') {
      unawaited(
        startIncoming(
          visitorId: visitorId,
          visitorName: data['visitorName'] ?? 'Visitor',
          flatLabel: data['flatLabel'] ?? '',
          purpose: data['purpose'] ?? '',
          expiresAt: data['expiresAt'] ?? '',
        ),
      );
      return;
    }
    final stop = data['callAction'] == 'stop' ||
        (entryMode == 'WALK_IN' &&
            (type == 'VISITOR_APPROVED' ||
                type == 'VISITOR_REJECTED' ||
                type == 'VISITOR_EXPIRED'));
    if (stop) {
      unawaited(stopIncoming(visitorId));
    }
  }

  Future<void> startIncoming({
    required String visitorId,
    String visitorName = 'Visitor',
    String flatLabel = '',
    String purpose = '',
    String expiresAt = '',
  }) async {
    if (!_isResident) return;
    if (Platform.isAndroid) {
      try {
        await _methods.invokeMethod<void>('startIncoming', {
          'visitorId': visitorId,
          'visitorName': visitorName,
          'flatLabel': flatLabel,
          'purpose': purpose,
          'expiresAt': expiresAt,
        });
      } catch (error) {
        debugPrint('Native incoming call start skipped: $error');
      }
    }
    openIncoming(visitorId);
  }

  Future<void> stopIncoming(String visitorId) async {
    if (_openVisitorId == visitorId) {
      _openVisitorId = null;
    }
    if (Platform.isAndroid) {
      try {
        await _methods.invokeMethod<void>('stopIncoming', {
          'visitorId': visitorId,
        });
      } catch (error) {
        debugPrint('Native incoming call stop skipped: $error');
      }
    }
  }

  Future<void> stopAll() async {
    _openVisitorId = null;
    if (!Platform.isAndroid) return;
    try {
      await _methods.invokeMethod<void>('stopAll');
    } catch (_) {}
  }

  void openIncoming(String visitorId) {
    if (!_isResident || visitorId.isEmpty) return;
    if (_openVisitorId == visitorId) return;
    _openVisitorId = visitorId;
    onOpenLink?.call(
      NotificationDeepLink(
        kind: NotificationLinkKind.visitorApproval,
        id: visitorId,
      ),
    );
  }

  void noteClosed(String visitorId) {
    if (_openVisitorId == visitorId) {
      _openVisitorId = null;
    }
    onIncomingClosed?.call(visitorId);
  }

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type']?.toString() ?? '';
    final visitorId = raw['visitorId']?.toString() ?? '';
    if (visitorId.isEmpty) return;
    if (type == 'incoming') {
      openIncoming(visitorId);
    } else if (type == 'stopped' && _openVisitorId == visitorId) {
      _openVisitorId = null;
    }
  }

  void _onSocket(VisitorEventPayload event) {
    if (event.entryMode != 'WALK_IN') return;
    if (event.approvalStatus == 'PENDING' &&
        event.entryStatus == 'NOT_ENTERED') {
      unawaited(
        startIncoming(
          visitorId: event.visitorId,
          visitorName: event.visitorName,
          flatLabel: event.flatLabel,
        ),
      );
      return;
    }
    if (event.approvalStatus == 'APPROVED' ||
        event.approvalStatus == 'REJECTED' ||
        event.approvalStatus == 'EXPIRED') {
      unawaited(stopIncoming(event.visitorId));
    }
  }

  bool get _isResident {
    final role = authSession?.appRole;
    return role == AppRole.owner || role == AppRole.tenant;
  }
}
