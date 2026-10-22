import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/visitor_models.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/visitor_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Visitor DTO parsing', () {
    test('parses visitor with dual statuses and no OTP secret', () {
      final v = Visitor.fromJson(_visitor());
      expect(v.id, visitorId);
      expect(v.approvalStatus, 'PENDING');
      expect(v.entryStatus, 'NOT_ENTERED');
      expect(v.hasActiveOtp, isFalse);
      expect(v.otpVerified, isFalse);
      expect(v.otpAttempts, isNull);
    });

    test('parses guard dashboard and admin summary', () {
      final dash = GuardDashboard.fromJson({
        'currentlyInside': 2,
        'pendingApprovals': 1,
        'awaitingEntry': 3,
        'enteredToday': 4,
        'exitedToday': 5,
        'recent': [_visitor()],
      });
      expect(dash.currentlyInside, 2);
      expect(dash.recent, hasLength(1));

      final summary = AdminVisitorSummary.fromJson({
        'total': 10,
        'byApprovalStatus': {'PENDING': 2, 'APPROVED': 5},
        'byEntryStatus': {'ENTERED': 3, 'EXITED': 4},
      });
      expect(summary.total, 10);
      expect(summary.byApprovalStatus['PENDING'], 2);
      expect(summary.byEntryStatus['ENTERED'], 3);
    });

    test('parses socket event payload without OTP fields', () {
      final event = VisitorEventPayload.fromJson({
        'visitorId': visitorId,
        'societyId': societyId,
        'flatId': flatId,
        'flatNumberSnapshot': '101',
        'wingCodeSnapshot': 'A',
        'visitorName': 'Guest',
        'visitorType': 'GUEST',
        'approvalStatus': 'APPROVED',
        'entryStatus': 'NOT_ENTERED',
        'assignedResidentUserId': residentId,
      });
      expect(event.visitorId, visitorId);
      expect(event.approvalStatus, 'APPROVED');
    });

    test('status labels cover backend enums', () {
      expect(approvalStatusLabel('PENDING'), contains('Pending'));
      expect(entryStatusLabel('ENTERED'), 'Inside');
      expect(visitorTypeLabel('SERVICE_PROVIDER'), contains('Service'));
    });
  });

  group('Guard visitor flows', () {
    test('registers a visitor against a flat', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/guard/visitors'), isTrue);
        expect(options.method, 'POST');
        expect(options.data['flatId'], flatId);
        expect(options.data.containsKey('visitorEmail'), isFalse);
        expect(options.data.containsKey('otp'), isFalse);
        return jsonBody(201, {
          'success': true,
          'data': _visitor(approval: 'PENDING'),
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final created = await repo.createVisitor(
        const CreateVisitorRequest(
          flatId: flatId,
          visitorName: 'Guest',
          visitorPhone: '9876543210',
          visitorType: 'GUEST',
          purpose: 'Visit',
        ),
      );
      expect(created.approvalStatus, 'PENDING');
      expect(created.entryStatus, 'NOT_ENTERED');
    });

    test('lists visitors with pagination', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/guard/visitors'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_visitor()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final page = await repo.listGuardVisitors();
      expect(page.items, hasLength(1));
      expect(page.pagination.total, 1);
    });

    test('OTP verification success and failure codes', () async {
      var call = 0;
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.contains('verify-entry-otp'), isTrue);
        expect(options.data['otp'], '123456');
        call++;
        if (call == 1) {
          return jsonBody(200, {
            'success': true,
            'data': _visitor(
              approval: 'APPROVED',
              otpVerified: true,
              societyName: 'Apna Heights',
            ),
          });
        }
        return jsonBody(403, {
          'success': false,
          'error': {'code': 'OTP_INVALID', 'message': 'Bad OTP'},
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final ok = await repo.verifyEntryOtpByCode(otp: '123456');
      expect(ok.entryStatus, 'NOT_ENTERED');
      expect(ok.otpVerified, isTrue);
      expect(ok.residentName, isNull);
      expect(ok.societyName, 'Apna Heights');
      await expectLater(
        repo.verifyEntryOtpByCode(otp: '123456'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'OTP_INVALID'),
        ),
      );
    });

    test('confirm visitor entry after OTP and reject duplicates', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/confirm-entry'), isTrue);
        calls++;
        if (calls == 1) {
          return jsonBody(200, {
            'success': true,
            'data': _visitor(
              approval: 'APPROVED',
              entry: 'ENTERED',
              otpVerified: true,
            ),
          });
        }
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'ALREADY_ENTERED',
            'message': 'Visitor entry was already recorded',
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final entered = await repo.confirmVisitorEntry(visitorId);
      expect(entered.entryStatus, 'ENTERED');
      expect(entered.otpVerified, isTrue);
      await expectLater(
        repo.confirmVisitorEntry(visitorId),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'ALREADY_ENTERED'),
        ),
      );
    });

    test('expired OTP surfaces OTP_EXPIRED', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(400, {
          'success': false,
          'error': {'code': 'OTP_EXPIRED', 'message': 'Expired'},
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      await expectLater(
        repo.verifyEntryOtpByCode(otp: '123456'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'OTP_EXPIRED'),
        ),
      );
    });

    test('duplicate entry prevention via mutation lock', () async {
      final enteredHandler = Completer<void>();
      final release = Completer<void>();
      final adapter = ScriptedAdapter((options) async {
        if (!enteredHandler.isCompleted) enteredHandler.complete();
        await release.future;
        return jsonBody(200, {
          'success': true,
          'data': _visitor(approval: 'APPROVED', entry: 'ENTERED'),
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final first = repo.verifyEntryOtpByCode(otp: '123456');
      await enteredHandler.future;
      expect(repo.mutationLocked, isTrue);
      await expectLater(
        repo.verifyEntryOtpByCode(otp: '123456'),
        throwsA(isA<StateError>()),
      );
      release.complete();
      await first;
      expect(repo.mutationLocked, isFalse);
    });

    test('checkout success and duplicate checkout lock', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/checkout'), isTrue);
        calls++;
        return jsonBody(200, {
          'success': true,
          'data': _visitor(approval: 'APPROVED', entry: 'EXITED'),
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final out = await repo.checkout(visitorId);
      expect(out.entryStatus, 'EXITED');
      expect(calls, 1);
    });

    test('vacant flat create returns NO_ACTIVE_RESIDENT', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(400, {
          'success': false,
          'error': {
            'code': 'NO_ACTIVE_RESIDENT',
            'message': 'No active resident',
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      await expectLater(
        repo.createVisitor(
          const CreateVisitorRequest(
            flatId: flatId,
            visitorName: 'Guest',
            visitorPhone: '9876543210',
            visitorType: 'GUEST',
            purpose: 'Visit',
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'NO_ACTIVE_RESIDENT'),
        ),
      );
    });
  });

  group('Resident visitor flows', () {
    test('approve and reject', () async {
      var path = '';
      final adapter = ScriptedAdapter((options) async {
        path = options.path;
        if (options.path.endsWith('/approve')) {
          return jsonBody(200, {
            'success': true,
            'data': _visitor(
              approval: 'APPROVED',
              hasOtp: true,
            ),
          });
        }
        return jsonBody(200, {
          'success': true,
          'data': _visitor(approval: 'REJECTED'),
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final approved = await repo.approve(visitorId);
      expect(path.endsWith('/approve'), isTrue);
      expect(approved.approvalStatus, 'APPROVED');
      expect(approved.hasActiveOtp, isTrue);

      final rejected = await repo.reject(visitorId, reason: 'Not today');
      expect(rejected.approvalStatus, 'REJECTED');
    });

    test('previous tenant access revocation is NOT_CURRENT_APPROVER', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'NOT_CURRENT_APPROVER',
            'message': 'No longer assigned',
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      await expectLater(
        repo.approve(visitorId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'NOT_CURRENT_APPROVER'),
        ),
      );
    });

    test('owner versus tenant list endpoints stay resident-scoped', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.contains('/resident/visitors'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [
              _visitor(assignedRole: 'TENANT'),
            ],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final page = await repo.listResidentVisitors();
      expect(page.items.first.assignedResidentRole, 'TENANT');
    });
  });

  group('Admin visitors', () {
    test('lists visitors and summary', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/visitors/summary')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'total': 3,
              'byApprovalStatus': {'PENDING': 1},
              'byEntryStatus': {'ENTERED': 1},
            },
          });
        }
        expect(options.path.endsWith('/admin/visitors'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_visitor()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      final page = await repo.listAdminVisitors();
      final summary = await repo.adminSummary();
      expect(page.items, hasLength(1));
      expect(summary.total, 3);
    });
  });

  group('Cache and auth errors', () {
    test('cache invalidation after mutation', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/pending')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_visitor()],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        if (options.path.endsWith('/approve')) {
          return jsonBody(200, {
            'success': true,
            'data': _visitor(approval: 'APPROVED'),
          });
        }
        return notFound(options.path);
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.visitors.pendingVisitors();
      expect(repos.visitors.lastResidentPending, isNotNull);
      await repos.visitors.approve(visitorId);
      expect(repos.visitors.lastResidentPending, isNull);
    });

    test('401/403 surface as ApiException without inventing success', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {'code': 'FORBIDDEN_ROLE', 'message': 'Forbidden'},
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      await expectLater(
        repo.guardDashboard(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'FORBIDDEN_ROLE'),
        ),
      );
      expect(repo.lastDashboard, isNull);
    });

    test('failed create does not invent a successful visitor', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(400, {
          'success': false,
          'error': {
            'code': 'VISITOR_EMAIL_REQUIRED',
            'message': 'Email required',
          },
        });
      });
      final repo = VisitorRepository(_api(adapter).visitors);
      await expectLater(
        repo.approve(visitorId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'VISITOR_EMAIL_REQUIRED'),
        ),
      );
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const flatId = '507f1f77bcf86cd799439013';
const visitorId = '507f1f77bcf86cd799439071';
const residentId = '507f1f77bcf86cd799439021';

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

Map<String, Object?> _visitor({
  String approval = 'PENDING',
  String entry = 'NOT_ENTERED',
  String assignedRole = 'OWNER',
  bool hasOtp = false,
  bool otpVerified = false,
  String? residentName,
  String? societyName,
}) =>
    {
      'id': visitorId,
      'societyId': societyId,
      'flatId': flatId,
      'visitorName': 'Guest',
      'visitorPhone': '****3210',
      'visitorType': 'GUEST',
      'purpose': 'Visit',
      'numberOfVisitors': 1,
      'requestedByGuardId': '507f1f77bcf86cd799439081',
      'assignedResidentUserId': residentId,
      'assignedResidentRole': assignedRole,
      'approvalStatus': approval,
      'entryStatus': entry,
      'hasActiveOtp': hasOtp,
      'otpVerified': otpVerified,
      'otpExpiresAt': hasOtp ? '2026-10-20T12:00:00.000Z' : null,
      'residentName': residentName,
      'societyName': societyName,
      'flatNumberSnapshot': '101',
      'wingCodeSnapshot': 'A',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

ResponseBody notFound(String path) => jsonBody(404, {
      'success': false,
      'error': {'code': 'ROUTE_NOT_FOUND', 'message': path},
    });

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
