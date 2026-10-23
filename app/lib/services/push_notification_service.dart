import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/auth/app_role.dart';
import '../api/auth/auth_session.dart';
import 'incoming_visitor_call.dart';
import 'notification_deep_link.dart';

/// Global navigator used for notification deep links across app states.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

const _incomingChannelId = 'incoming_visitor_call';
const _visitorsChannelId = 'visitors';
const _billingChannelId = 'billing';
const _noticesChannelId = 'notices';
const _generalChannelId = 'general';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolates cannot touch UI, sockets, or auth. Initialize Firebase
  // only so the message is acknowledged; the OS still displays notification
  // payloads, and data-only taps are handled when the app is opened.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

/// Optional FCM + local-notification layer.
///
/// Firebase is initialized from [bootstrap] before [runApp]. Missing
/// `google-services.json`, denied permission, or plugin errors never block
/// login, Socket.IO, or in-app inbox flows.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _firebaseReady = false;
  bool _backgroundHandlerRegistered = false;
  bool _handlersBound = false;
  String? _registeredToken;
  NotificationDeepLink? _pendingLink;
  String? _lastOpenedVisitorApprovalId;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// Must run after [WidgetsFlutterBinding.ensureInitialized] and before
  /// [runApp] so background FCM handlers are registered in time.
  static Future<void> bootstrap() async {
    await instance._ensureFirebase(registerBackgroundHandler: true);
    if (!instance._firebaseReady) return;
    await instance._ensureHandlers();
    await instance._consumeLaunchMessage();
  }

  Future<void> start(AuthSession session) async {
    if (!session.isAuthenticated) return;
    await _ensureFirebase();
    if (!_firebaseReady) return;
    if (session.appRole == AppRole.owner || session.appRole == AppRole.tenant) {
      IncomingVisitorCallCoordinator.instance.onOpenLink = openDeepLink;
      IncomingVisitorCallCoordinator.instance.onIncomingClosed =
          clearOpenedVisitorApproval;
    }
    await _ensureHandlers();
    await _requestPermissionAndRegister(session);
    await _consumeLaunchMessage();
    if (session.appRole == AppRole.owner || session.appRole == AppRole.tenant) {
      await IncomingVisitorCallCoordinator.instance.bind();
    }
    flushPending();
  }

  Future<void> stop() async {
    IncomingVisitorCallCoordinator.instance.onOpenLink = null;
    IncomingVisitorCallCoordinator.instance.onIncomingClosed = null;
    await IncomingVisitorCallCoordinator.instance.unbind();
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _tokenSub = null;
    _foregroundSub = null;
    _openedSub = null;
    _handlersBound = false;
    final token = _registeredToken;
    _registeredToken = null;
    final session = authSession;
    if (token != null &&
        token.isNotEmpty &&
        session != null &&
        session.isAuthenticated) {
      try {
        await session.api.deviceTokens.unregister(token: token);
      } catch (_) {}
    }
  }

  void enqueuePending(NotificationDeepLink? link) {
    if (link == null) return;
    _pendingLink = link;
  }

  void flushPending() {
    final link = _pendingLink;
    if (link == null) return;
    if (authSession?.isAuthenticated != true) return;
    _pendingLink = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      openDeepLink(link);
    });
  }

  void clearOpenedVisitorApproval(String visitorId) {
    if (_lastOpenedVisitorApprovalId == visitorId) {
      _lastOpenedVisitorApprovalId = null;
    }
  }

  bool openDeepLink(NotificationDeepLink link) {
    if (link.kind == NotificationLinkKind.visitorApproval &&
        link.id != null &&
        link.id == _lastOpenedVisitorApprovalId) {
      return true;
    }
    final page = widgetForNotificationDeepLink(link);
    final nav = appNavigatorKey.currentState;
    if (page == null || nav == null) {
      enqueuePending(link);
      return false;
    }
    if (link.kind == NotificationLinkKind.visitorApproval) {
      _lastOpenedVisitorApprovalId = link.id;
    }
    nav.push(MaterialPageRoute<void>(builder: (_) => page));
    return true;
  }

  Future<void> _ensureFirebase({bool registerBackgroundHandler = false}) async {
    if (_firebaseReady) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      if (registerBackgroundHandler && !_backgroundHandlerRegistered) {
        try {
          FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler,
          );
          _backgroundHandlerRegistered = true;
        } catch (error) {
          debugPrint('FCM background handler already registered: $error');
        }
      }
      _firebaseReady = true;
    } catch (error, stack) {
      debugPrint('Push notifications unavailable: $error\n$stack');
      _firebaseReady = false;
    }
  }

  Future<void> _ensureHandlers() async {
    if (_handlersBound) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (response) {
          final link = NotificationDeepLink.parse(response.payload);
          if (link != null) openDeepLink(link);
        },
      );
      await _createChannels();

      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForeground);
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final link = NotificationDeepLink.fromFcmData(_stringData(message.data));
        if (link != null) openDeepLink(link);
      });
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });
      _handlersBound = true;
    } catch (error, stack) {
      debugPrint('Notification handlers unavailable: $error\n$stack');
    }
  }

  Future<void> _createChannels() async {
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _incomingChannelId,
        'Incoming visitors',
        description: 'Call-style visitor approval requests',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: const RawResourceAndroidNotificationSound('incoming_visitor'),
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        vibrationPattern: Int64List.fromList([0, 500, 400, 500]),
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _visitorsChannelId,
        'Visitors',
        description: 'Visitor entry and gate updates',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _billingChannelId,
        'Billing',
        description: 'Maintenance bills and overdue reminders',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _noticesChannelId,
        'Notices',
        description: 'Society announcements',
        importance: Importance.defaultImportance,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _generalChannelId,
        'General',
        description: 'Other Apna Society notifications',
        importance: Importance.defaultImportance,
      ),
    );
  }

  Future<void> _requestPermissionAndRegister(AuthSession session) async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: true,
      );
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestFullScreenIntentPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Notification permission denied; FCM token not requested.');
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('FCM token: $token');
        await _registerToken(token, session: session);
      } else {
        debugPrint('FCM token was empty after permission was granted.');
      }
    } catch (error) {
      debugPrint('Notification permission or token registration skipped: $error');
    }
  }

  Future<void> _registerToken(String token, {AuthSession? session}) async {
    final active = session ?? authSession;
    if (active == null || !active.isAuthenticated) return;
    if (token.length < 16) return;
    try {
      await active.api.deviceTokens.register(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      _registeredToken = token;
    } catch (error) {
      debugPrint('Device token registration skipped: $error');
    }
  }

  Future<void> _consumeLaunchMessage() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        enqueuePending(
          NotificationDeepLink.fromFcmData(_stringData(initial.data)),
        );
      }
      final launch = await _local.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true) {
        enqueuePending(NotificationDeepLink.parse(payload));
      }
    } catch (_) {}
  }

  Future<void> _onForeground(RemoteMessage message) async {
    debugPrint(
      'FCM foreground message id=${message.messageId} type=${message.data['type']}',
    );
    final data = _stringData(message.data);
    IncomingVisitorCallCoordinator.instance.handleFcmData(data);
    final link = NotificationDeepLink.fromFcmData(data);
    final incoming = link?.kind == NotificationLinkKind.visitorApproval;
    if (incoming || data['callAction'] == 'stop') return;
    await _showLocal(message, data, incoming: false);
  }

  Future<void> _showLocal(
    RemoteMessage message,
    Map<String, String> data, {
    required bool incoming,
  }) async {
    final title = message.notification?.title ?? data['title'] ?? 'Apna Society';
    final body = message.notification?.body ?? data['body'] ?? '';
    final channel = data['channel'] ??
        (incoming
            ? _incomingChannelId
            : channelForType(data['type'] ?? ''));
    final android = AndroidNotificationDetails(
      channel,
      channel,
      importance: incoming ? Importance.max : Importance.high,
      priority: incoming ? Priority.max : Priority.high,
      category: incoming
          ? AndroidNotificationCategory.call
          : AndroidNotificationCategory.message,
      fullScreenIntent: incoming,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(android: android),
      payload: data['deepLink'],
    );
  }
}

String channelForType(String type) {
  switch (type) {
    case 'BILL_GENERATED':
    case 'BILL_OVERDUE':
    case 'PAYMENT_SUCCESS':
    case 'PAYMENT_FAILED':
      return _billingChannelId;
    case 'ANNOUNCEMENT':
      return _noticesChannelId;
    case 'VISITOR_REQUEST':
    case 'VISITOR_APPROVED':
    case 'VISITOR_REJECTED':
    case 'VISITOR_ENTERED':
    case 'VISITOR_EXPIRED':
    case 'PARCEL_AWAITING_HANDOVER':
    case 'PARCEL_RECEIVED':
      return _visitorsChannelId;
    default:
      return _generalChannelId;
  }
}

Map<String, String> _stringData(Map<String, dynamic> data) {
  return {
    for (final entry in data.entries)
      entry.key: entry.value?.toString() ?? '',
  };
}

@visibleForTesting
NotificationDeepLink? debugParseNotificationLink(String? raw) =>
    NotificationDeepLink.parse(raw);
