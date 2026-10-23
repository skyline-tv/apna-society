import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/models/notification_models.dart';
import 'package:apna_society/api/models/visitor_models.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/visitor_repository.dart';
import 'package:apna_society/services/notification_deep_link.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Notification deep links', () {
    test('parses apnasociety URIs without treating missing ids as valid pages', () {
      expect(
        NotificationDeepLink.parse('apnasociety://visitor-approval/$visitorId')
            ?.kind,
        NotificationLinkKind.visitorApproval,
      );
      expect(
        NotificationDeepLink.parse('apnasociety://visitor/$visitorId')?.id,
        visitorId,
      );
      expect(
        NotificationDeepLink.parse('apnasociety://bill/$billId')?.kind,
        NotificationLinkKind.bill,
      );
      expect(
        NotificationDeepLink.parse('apnasociety://notice/$noticeId')?.kind,
        NotificationLinkKind.notice,
      );
      expect(
        NotificationDeepLink.parse('apnasociety://parcel/$parcelId')?.kind,
        NotificationLinkKind.parcel,
      );
      expect(NotificationDeepLink.parse('https://example.com'), isNull);
    });

    test('incoming visitor call screen copy is call-style', () {
      final src =
          File('lib/features/visitors/incoming_visitor_page.dart').readAsStringSync();
      expect(src.contains('VISITOR AT MAIN GATE'), isTrue);
      expect(src.contains("'APPROVE'"), isTrue);
      expect(src.contains("'REJECT'"), isTrue);
      expect(src.contains('Leave parcel'), isFalse);
    });

    test('socket visitor events carry walk-in entryMode', () {
      final event = VisitorEventPayload.fromJson({
        'visitorId': visitorId,
        'societyId': societyId,
        'flatId': flatId,
        'flatNumberSnapshot': '101',
        'wingCodeSnapshot': 'A',
        'visitorName': 'Guest',
        'visitorType': 'GUEST',
        'approvalStatus': 'PENDING',
        'entryStatus': 'NOT_ENTERED',
        'entryMode': 'WALK_IN',
      });
      expect(event.entryMode, 'WALK_IN');
      expect(event.flatLabel, 'A-101');
    });

    test('maps FCM data to the walk-in approval screen', () {
      final link = NotificationDeepLink.fromFcmData({
        'type': 'VISITOR_REQUEST',
        'entryMode': 'WALK_IN',
        'relatedEntityId': visitorId,
      });
      expect(link?.kind, NotificationLinkKind.visitorApproval);
      expect(link?.id, visitorId);
    });

    test('inbox metadata never includes OTP or token secrets', () {
      final n = AppNotification.fromJson({
        'id': notificationId,
        'societyId': societyId,
        'recipientUserId': userId,
        'type': 'VISITOR_ENTERED',
        'title': 'Visitor Entered Society',
        'body': 'Your visitor has entered the society.',
        'isRead': false,
        'createdAt': '2026-10-20T10:00:00.000Z',
        'updatedAt': '2026-10-20T10:00:00.000Z',
        'relatedEntityType': 'VisitorLog',
        'relatedEntityId': visitorId,
        'metadata': {
          'visitorName': 'Guest',
          'visitorPhone': '9876543210',
          'deepLink': 'apnasociety://visitor/$visitorId',
        },
      });
      expect(n.metadataString('otp'), isNull);
      expect(n.metadataString('token'), isNull);
      expect(n.metadataString('deepLink'), contains('visitor/'));
      expect(
        NotificationDeepLink.fromNotification(n).kind,
        NotificationLinkKind.visitor,
      );
    });
  });

  group('Walk-in visitor API', () {
    test('creates a WALK_IN request without requiring phone', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/guard/visitors'), isTrue);
        expect(options.data['entryMode'], 'WALK_IN');
        expect(options.data.containsKey('visitorPhone'), isFalse);
        expect(options.data.containsKey('otp'), isFalse);
        return jsonBody(201, {
          'success': true,
          'data': _visitor(entryMode: 'WALK_IN'),
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final created = await repo.createVisitor(
        const CreateVisitorRequest(
          flatId: flatId,
          visitorName: 'Walk-in guest',
          visitorPhone: '',
          visitorType: 'GUEST',
          purpose: 'Visit',
          entryMode: 'WALK_IN',
        ),
      );
      expect(created.isWalkIn, isTrue);
      expect(created.isPendingWalkIn, isTrue);
      expect(created.requestState, 'PENDING');
    });

    test('leave-parcel returns a handover, not visitor entry', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/leave-parcel'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'visitor': {
              'id': visitorId,
              'approvalStatus': 'CANCELLED',
              'resolution': 'PARCEL',
              'entryStatus': 'NOT_ENTERED',
            },
            'parcel': _parcel(),
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final result = await repo.leaveParcel(visitorId);
      expect(result.visitor.approvalStatus, 'CANCELLED');
      expect(result.visitor.resolution, 'PARCEL');
      expect(result.parcel.status, 'AWAITING_HANDOVER');
      expect(result.parcel.id, parcelId);
    });

    test('guard receive parcel records handover only', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/parcels/$parcelId/receive'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': _parcel(status: 'RECEIVED_BY_GUARD'),
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final parcel = await repo.receiveParcel(parcelId);
      expect(parcel.status, 'RECEIVED_BY_GUARD');
    });
  });

  group('Device tokens', () {
    test('registers and unregisters against /me/device-tokens', () async {
      final paths = <String>[];
      final adapter = ScriptedAdapter((options) async {
        paths.add('${options.method} ${options.path}');
        if (options.method == 'POST') {
          expect(options.data['token'], 'fcm-token-value-123456');
          expect(options.data['platform'], 'android');
          return jsonBody(201, {
            'success': true,
            'data': {'id': 'tok1'},
          });
        }
        expect(options.data['token'], 'fcm-token-value-123456');
        return jsonBody(200, {'success': true, 'data': {'removed': true}});
      });
      final api = _api(adapter);
      await api.deviceTokens.register(
        token: 'fcm-token-value-123456',
        platform: 'android',
      );
      await api.deviceTokens.unregister(token: 'fcm-token-value-123456');
      expect(paths.any((p) => p.contains('/me/device-tokens')), isTrue);
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const flatId = '507f1f77bcf86cd799439013';
const visitorId = '507f1f77bcf86cd799439071';
const parcelId = '507f1f77bcf86cd7994390d1';
const billId = '507f1f77bcf86cd7994390b1';
const noticeId = '507f1f77bcf86cd7994390c1';
const notificationId = '507f1f77bcf86cd7994390c3';
const userId = '507f1f77bcf86cd799439021';

ApnaApi _api(ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  client.societyId = societyId;
  return ApnaApi(client: client);
}

Map<String, Object?> _visitor({String entryMode = 'OTP'}) => {
      'id': visitorId,
      'societyId': societyId,
      'flatId': flatId,
      'visitorName': 'Walk-in guest',
      'visitorPhone': '',
      'visitorType': 'GUEST',
      'purpose': 'Visit',
      'numberOfVisitors': 1,
      'requestedByGuardId': '507f1f77bcf86cd799439081',
      'assignedResidentUserId': userId,
      'assignedResidentRole': 'OWNER',
      'approvalStatus': 'PENDING',
      'entryStatus': 'NOT_ENTERED',
      'hasActiveOtp': false,
      'otpVerified': false,
      'flatNumberSnapshot': '101',
      'wingCodeSnapshot': 'A',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
      'entryMode': entryMode,
      'requestState': 'PENDING',
      'pendingExpiresAt': '2026-10-20T10:02:00.000Z',
    };

Map<String, Object?> _parcel({String status = 'AWAITING_HANDOVER'}) => {
      'id': parcelId,
      'societyId': societyId,
      'flatId': flatId,
      'recipientUserId': userId,
      'courierName': 'Walk-in guest',
      'requestedByGuardId': '507f1f77bcf86cd799439081',
      'authorizedByUserId': userId,
      'status': status,
      'requestedAt': '2026-10-20T10:00:00.000Z',
      'authorizedAt': '2026-10-20T10:01:00.000Z',
      'flatNumberSnapshot': '101',
      'wingCodeSnapshot': 'A',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:01:00.000Z',
    };

ResponseBody jsonBody(int status, Object payload) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
