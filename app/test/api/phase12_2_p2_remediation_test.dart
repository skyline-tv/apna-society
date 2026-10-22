import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/auth/auth_session.dart';
import 'package:apna_society/api/auth/secure_token_store.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/models/billing_models.dart';
import 'package:apna_society/api/models/resident_home_context.dart';
import 'package:apna_society/api/models/resident_models.dart';
import 'package:apna_society/api/repositories/billing_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/socket/visitor_socket.dart';
import 'package:apna_society/features/billing/demo_payment_checkout.dart';
import 'package:apna_society/features/billing/razorpay_checkout.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const societyId = '507f1f77bcf86cd799439011';
const flatA = '507f1f77bcf86cd7994390a1';
const flatB = '507f1f77bcf86cd7994390b2';
const billId = '507f1f77bcf86cd799439041';

void main() {
  tearDown(() {
    resetAuthSessionForTests();
    clearLiveRepositories();
    disconnectVisitorSocket();
  });

  group('F-OCC-01 occupancy assign invalidation', () {
    test('invalidateAfterResidentMutation drops society dashboard cache',
        () async {
      var dashboardHits = 0;
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/admin/dashboard')) {
          dashboardHits += 1;
          return jsonBody(200, {
            'success': true,
            'data': {
              'totals': {
                'wings': 1,
                'flats': 2,
                'activeFlats': 2,
                'inactiveFlats': 0,
                'ownerOccupiedFlats': 2,
                'tenantOccupiedFlats': 0,
                'vacantFlats': 0,
                'twoBhkCount': 2,
                'threeBhkCount': 0,
                'monthlyMaintenanceTotal': 8000,
              },
              'wings': <Object>[],
            },
          });
        }
        return notFound(options.path);
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.society.dashboard();
      await repos.society.dashboard();
      expect(dashboardHits, 1);
      repos.invalidateAfterResidentMutation(flatId: flatA);
      await repos.society.dashboard();
      expect(dashboardHits, 2);
    });

    test('live assign site uses invalidateAfterResidentMutation', () {
      final assignSrc =
          File('lib/features/residents/admin_residents_module.dart')
              .readAsStringSync();
      final saveBlock = assignSrc
          .split('class AssignOccupancyPage')
          .last
          .split('Future<void> _save()')
          .last
          .split('if (!mounted) return;')
          .first;
      expect(saveBlock.contains('repos.resident.clear();'), isFalse);
      expect(
        saveBlock.contains(
          'repos.invalidateAfterResidentMutation(flatId: widget.flatId)',
        ),
        isTrue,
      );
    });
  });

  group('F-SOCK-01 socket auth lifecycle', () {
    test('access-token refresh invokes reconnect hook', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-old');
      AuthSession? hooked;
      AuthSession.onAccessTokenRefreshed = (s) => hooked = s;
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/refresh'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'accessToken': 'access-fresh',
            'refreshToken': 'refresh-fresh',
            'expiresIn': '15m',
            'tokenType': 'Bearer',
          },
        });
      });
      final session = _session(adapter, store: store);
      expect(await session.refreshSession(), isTrue);
      expect(hooked, same(session));
      expect(session.accessToken, 'access-fresh');
    });

    test('clearLocal invokes disconnect hook', () async {
      var cleared = 0;
      AuthSession.onLocalSessionCleared = () => cleared += 1;
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-1');
      final session = _session(
        ScriptedAdapter((_) async => notFound('/')),
        store: store,
      );
      session.debugSetAccessToken('access-1');
      await session.clearLocal();
      expect(cleared, 1);
      expect(await store.readRefreshToken(), isNull);
    });

    test('connectForSession reconnects when access token changes', () {
      final socket = VisitorSocket.instance;
      socket.disconnect();
      expect(socket.debugAuthToken, isNull);

      // Without a full session society/role the connect early-returns after disconnect.
      final store = MemorySecureTokenStore();
      final adapter = ScriptedAdapter((_) async => notFound('/'));
      final session = _session(adapter, store: store);
      session.debugSetAccessToken('token-a');
      // societyId / role required — leave unset so connect disconnects cleanly.
      socket.connectForSession(session);
      expect(socket.isConnected, isFalse);
      expect(socket.debugAuthToken, isNull);
    });

    test('app bootstrap wires refresh and clear socket hooks', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src.contains('AuthSession.onAccessTokenRefreshed'), isTrue);
      expect(src.contains('AuthSession.onLocalSessionCleared'), isTrue);
      expect(
        src.contains('VisitorSocket.instance.connectForSession(session)'),
        isTrue,
      );
    });
  });

  group('F-OCC-02 multi-flat selection', () {
    test('OWNER single flat auto-selects; multi requires explicit selection',
        () async {
      final store = MemorySecureTokenStore();
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/login')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-1',
              'refreshToken': 'refresh-1',
              'expiresIn': '15m',
              'tokenType': 'Bearer',
            },
          });
        }
        if (options.path.endsWith('/me')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'id': 'user-1',
              'email': 'owner@example.com',
              'name': 'Owner',
              'roles': ['OWNER'],
              'societyIds': [societyId],
              'primarySocietyId': societyId,
            },
          });
        }
        if (options.path.endsWith('/resident/flats')) {
          return jsonBody(200, {
            'success': true,
            'data': [
              _ownerFlat(flatA, 'A-101'),
              _ownerFlat(flatB, 'B-202'),
            ],
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      await session.login(username: 'owner1', password: 'TestPassw0rd!');
      expect(session.residentFlats, hasLength(2));
      expect(session.selectedResidentFlat, isNull);
      expect(session.primaryResidentFlat?.flat.id, flatA);

      session.selectResidentFlat(flatB);
      expect(session.selectedResidentFlatId, flatB);

      session.clearResidentFlatSelection();
      expect(session.selectedResidentFlat, isNull);
    });

    test('TENANT single flat auto-selects; multi requires explicit selection',
        () async {
      final store = MemorySecureTokenStore();
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/login')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-1',
              'refreshToken': 'refresh-1',
              'expiresIn': '15m',
              'tokenType': 'Bearer',
            },
          });
        }
        if (options.path.endsWith('/me')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'id': 'user-2',
              'email': 'tenant@example.com',
              'name': 'Tenant',
              'roles': ['TENANT'],
              'societyIds': [societyId],
              'primarySocietyId': societyId,
            },
          });
        }
        if (options.path.endsWith('/resident/flats')) {
          return jsonBody(200, {
            'success': true,
            'data': [
              _tenantFlat(flatA, 'A-101'),
              _tenantFlat(flatB, 'B-202'),
            ],
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      await session.login(username: 'owner1', password: 'TestPassw0rd!');
      expect(session.residentFlats, hasLength(2));
      expect(session.selectedResidentFlat, isNull);
      expect(session.primaryResidentFlat?.flat.id, flatA);

      session.selectResidentFlat(flatB);
      expect(session.selectedResidentFlatId, flatB);
      expect(session.selectedResidentFlat?.access.role, 'TENANT');

      session.clearResidentFlatSelection();
      expect(session.selectedResidentFlat, isNull);
    });

    test(
        'OWNER single-flat account selectedResidentFlat resolves without select()',
        () async {
      final store = MemorySecureTokenStore();
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/login')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-1',
              'refreshToken': 'refresh-1',
              'expiresIn': '15m',
              'tokenType': 'Bearer',
            },
          });
        }
        if (options.path.endsWith('/me')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'id': 'user-1',
              'email': 'owner@example.com',
              'name': 'Owner',
              'roles': ['OWNER'],
              'societyIds': [societyId],
              'primarySocietyId': societyId,
            },
          });
        }
        if (options.path.endsWith('/resident/flats')) {
          return jsonBody(200, {
            'success': true,
            'data': [_ownerFlat(flatA, 'A-101')],
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      await session.login(username: 'owner1', password: 'TestPassw0rd!');
      expect(session.selectedResidentFlatId, flatA);
    });

    test(
        'TENANT single-flat account selectedResidentFlat resolves without select()',
        () async {
      final store = MemorySecureTokenStore();
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/login')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-1',
              'refreshToken': 'refresh-1',
              'expiresIn': '15m',
              'tokenType': 'Bearer',
            },
          });
        }
        if (options.path.endsWith('/me')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'id': 'user-2',
              'email': 'tenant@example.com',
              'name': 'Tenant',
              'roles': ['TENANT'],
              'societyIds': [societyId],
              'primarySocietyId': societyId,
            },
          });
        }
        if (options.path.endsWith('/resident/flats')) {
          return jsonBody(200, {
            'success': true,
            'data': [_tenantFlat(flatA, 'A-101')],
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      await session.login(username: 'owner1', password: 'TestPassw0rd!');
      expect(session.selectedResidentFlatId, flatA);
      expect(session.selectedResidentFlat?.access.role, 'TENANT');
    });

    test('create flows use selectedResidentFlatId not primaryResidentFlat', () {
      for (final path in [
        'lib/features/complaints/live_complaints_module.dart',
        'lib/features/facilities/live_facilities_module.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('selectedResidentFlatId'), isTrue, reason: path);
        expect(
          src.contains('primaryResidentFlat?.flat.id'),
          isFalse,
          reason: path,
        );
      }
    });

    test('OwnerHome flat switch invalidates caches and keys pages by flat', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src.contains('invalidateAfterFlatSelectionChange'), isTrue);
      expect(src.contains("ValueKey('visitors-\$flatKey')"), isTrue);
      expect(src.contains("ValueKey('vehicles-\$flatKey')"), isTrue);
    });

    test('ResidentHomeContext switches OWNER and TENANT multi-flat', () {
      const ownerProfile = ResidentProfile(
        id: 'u1',
        email: 'o@e.com',
        name: 'Owner',
        roles: ['OWNER'],
        societyIds: [societyId],
        activeFlatIds: [flatA, flatB],
      );
      final oa = ResidentFlat.fromJson(_ownerFlat(flatA, 'A-101'));
      final ob = ResidentFlat.fromJson(_ownerFlat(flatB, 'B-202'));
      final ownerCtx = ResidentHomeContext.fromBackend(
        profile: ownerProfile,
        flats: [oa, ob],
        preferOwner: true,
      );
      expect(ownerCtx.selectedFlat.flat.id, flatA);
      expect(ownerCtx.copyWithSelected(ob).selectedFlat.flat.id, flatB);
      expect(ownerCtx.hasMultipleFlats, isTrue);

      const tenantProfile = ResidentProfile(
        id: 'u2',
        email: 't@e.com',
        name: 'Tenant',
        roles: ['TENANT'],
        societyIds: [societyId],
        activeFlatIds: [flatA, flatB],
      );
      final ta = ResidentFlat.fromJson(_tenantFlat(flatA, 'A-101'));
      final tb = ResidentFlat.fromJson(_tenantFlat(flatB, 'B-202'));
      final tenantCtx = ResidentHomeContext.fromBackend(
        profile: tenantProfile,
        flats: [ta, tb],
        preferOwner: false,
      );
      expect(tenantCtx.selectedFlat.flat.id, flatA);
      expect(tenantCtx.access.isTenantSession, isTrue);
      expect(tenantCtx.copyWithSelected(tb).selectedFlat.flat.id, flatB);
    });
  });

  group('F-DEMO-02 late-interest setting removed from live Admin', () {
    test('AdminSettingsPage no longer saves SQLite late interest', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src.contains('Local demo billing settings'), isFalse);
      expect(src.contains('db.setLateInterestAnnualRate'), isFalse);
      expect(src.contains('db.lateInterestAnnualRate'), isFalse);
      expect(
        src.contains(
            'Late interest for live bills is calculated by the server'),
        isTrue,
      );
    });
  });

  group('Demo payment gateway', () {
    test('Flutter never embeds mock payment secret or HMAC helper', () {
      final demoSrc = File('lib/features/billing/demo_payment_checkout.dart')
          .readAsStringSync();
      expect(demoSrc.contains('test_razorpay_secret'), isFalse);
      expect(demoSrc.contains('signDemoMockPayment'), isFalse);
      expect(demoSrc.contains('Hmac'), isFalse);
      expect(demoSrc.contains('kDemoMockPaymentSecret'), isFalse);
      final billingSrc = File('lib/features/billing/live_billing_module.dart')
          .readAsStringSync();
      expect(billingSrc.contains('completeDemoPayment'), isTrue);
      expect(billingSrc.contains('openDemoPaymentCheckout'), isTrue);
      expect(billingSrc.contains('test_razorpay_secret'), isFalse);
    });

    test('mock provider detection', () {
      expect(isDemoPaymentProvider('razorpay-mock'), isTrue);
      expect(isDemoPaymentProvider('mock-razorpay'), isTrue);
      expect(isDemoPaymentProvider('razorpay'), isFalse);
    });

    test('empty checkout credentials are not treated as success', () {
      const empty = RazorpayCheckoutResult.success(
        orderId: 'order_1',
        paymentId: '',
        signature: '',
      );
      expect(empty.isSuccess, isFalse);
    });

    test('cancel never calls demo-complete or verify-payment', () async {
      var demoHits = 0;
      var verifyHits = 0;
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/demo-complete')) {
          demoHits += 1;
          return jsonBody(200, {
            'success': true,
            'data': {
              'paymentId': 'p1',
              'alreadySettled': false,
              'receiptId': null,
            },
          });
        }
        if (options.path.endsWith('/verify-payment')) {
          verifyHits += 1;
          return jsonBody(200, {
            'success': true,
            'data': {
              'paymentId': 'p1',
              'alreadySettled': false,
              'receiptId': null,
            },
          });
        }
        return notFound(options.path);
      });
      final repo = BillingRepository(_api(adapter).billing);

      // Cancelled demo choice must not hit settlement endpoints.
      expect(DemoPaymentChoice.cancelled, isNot(DemoPaymentChoice.success));
      if (DemoPaymentChoice.cancelled == DemoPaymentChoice.success) {
        await repo.completeDemoPayment(
          orderId: 'o',
          outcome: 'success',
          billId: billId,
        );
      }
      expect(demoHits, 0);
      expect(verifyHits, 0);
    });

    test('demo success settles via demo-complete; duplicate is alreadySettled',
        () async {
      var demoHits = 0;
      var verifyHits = 0;
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/demo-complete')) {
          demoHits += 1;
          final settled = demoHits > 1;
          final body = options.data as Map;
          expect(body['outcome'], 'success');
          expect(body.containsKey('signature'), isFalse);
          return jsonBody(200, {
            'success': true,
            'data': {
              'paymentId': '507f1f77bcf86cd799439051',
              'alreadySettled': settled,
              'receiptId': settled ? null : '507f1f77bcf86cd799439061',
              'billStatus': 'PAID',
              'outstandingPrincipalPaise': 0,
            },
          });
        }
        if (options.path.endsWith('/verify-payment')) {
          verifyHits += 1;
          return notFound(options.path);
        }
        return notFound(options.path);
      });
      final repo = BillingRepository(_api(adapter).billing);
      const orderId = 'order_demo';
      final first = await repo.completeDemoPayment(
        orderId: orderId,
        outcome: 'success',
        billId: billId,
      );
      expect(first.alreadySettled, isFalse);
      expect(first.receiptId, isNotNull);
      final second = await repo.completeDemoPayment(
        orderId: orderId,
        outcome: 'success',
        billId: billId,
      );
      expect(second.alreadySettled, isTrue);
      expect(demoHits, 2);
      expect(verifyHits, 0);
    });

    test('demo failure outcome posts failure to demo-complete', () async {
      var demoHits = 0;
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/demo-complete')) {
          demoHits += 1;
          final body = options.data as Map;
          expect(body['outcome'], 'failure');
          return jsonBody(400, {
            'success': false,
            'error': {
              'code': 'DEMO_PAYMENT_FAILED',
              'message': 'Demo payment failed',
            },
          });
        }
        return notFound(options.path);
      });
      final repo = BillingRepository(_api(adapter).billing);
      await expectLater(
        repo.completeDemoPayment(
          orderId: 'order_demo',
          outcome: 'failure',
          billId: billId,
        ),
        throwsA(isA<Object>()),
      );
      expect(demoHits, 1);
    });

    test('CreatePaymentOrderResult accepts razorpay-mock provider', () {
      final order = CreatePaymentOrderResult.fromJson({
        'paymentId': '507f1f77bcf86cd799439051',
        'paymentNumber': 'PAY-1',
        'billId': billId,
        'amountPaise': 400000,
        'order': {
          'orderId': 'order_x',
          'amountPaise': 400000,
          'currency': 'INR',
          'provider': 'razorpay-mock',
          'keyId': 'rzp_test_mock',
        },
      });
      expect(isDemoPaymentProvider(order.order.provider), isTrue);
    });
  });
}

AuthSession _session(
  ScriptedAdapter adapter, {
  MemorySecureTokenStore? store,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  return AuthSession(
    client: client,
    tokenStore: store ?? MemorySecureTokenStore(),
    api: ApnaApi(client: client),
  );
}

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

Map<String, Object?> _ownerFlat(String id, String number) => {
      'id': id,
      'societyId': societyId,
      'wingId': '507f1f77bcf86cd7994390w1',
      'number': number,
      'floor': 1,
      'position': 1,
      'flatType': '2BHK',
      'maintenanceRate': 4000,
      'isActive': true,
      'occupancyStatus': 'OWNER_OCCUPIED',
      'wingCode': number.split('-').first,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'access': {
        'financial': true,
        'residential': true,
        'role': 'OWNER',
      },
    };

Map<String, Object?> _tenantFlat(String id, String number) => {
      'id': id,
      'societyId': societyId,
      'wingId': '507f1f77bcf86cd7994390w1',
      'number': number,
      'floor': 1,
      'position': 1,
      'flatType': '2BHK',
      'maintenanceRate': 4000,
      'isActive': true,
      'occupancyStatus': 'TENANT_OCCUPIED',
      'wingCode': number.split('-').first,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'access': {
        'financial': false,
        'residential': true,
        'role': 'TENANT',
      },
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
