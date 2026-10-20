import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/auth/app_role.dart';
import 'package:apna_society/api/auth/auth_session.dart';
import 'package:apna_society/api/auth/secure_token_store.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/auth_models.dart';
import 'package:apna_society/services/occupancy_access.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const societyId = '507f1f77bcf86cd799439011';

  tearDown(resetAuthSessionForTests);

  test('request OTP posts email without account enumeration', () async {
    final adapter = ScriptedAdapter((options) async {
      expect(options.path, '/api/v1/auth/request-otp');
      expect(options.data['email'], 'owner@example.com');
      return jsonBody(200, {
        'success': true,
        'data': {
          'message':
              'If an account exists for this email, a one-time code has been sent.',
        },
      });
    });
    final session = _session(adapter);
    await session.requestOtp('owner@example.com');
    expect(adapter.calls, 1);
  });

  test('verify OTP stores refresh token and loads owner context', () async {
    final store = MemorySecureTokenStore();
    final adapter = ScriptedAdapter((options) async {
      if (options.path.endsWith('/verify-otp')) {
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
        expect(options.headers['Authorization'], 'Bearer access-1');
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
          'data': [_ownerFlat(societyId)],
        });
      }
      return notFound(options.path);
    });
    final session = _session(adapter, store: store);
    final profile = await session.verifyOtp(
      email: 'owner@example.com',
      otp: '123456',
    );
    expect(profile.email, 'owner@example.com');
    expect(session.appRole, AppRole.owner);
    expect(session.primaryResidentFlat?.flat.number, 'A-101');
    expect(session.primaryResidentFlat?.access.financial, isTrue);
    expect(await store.readRefreshToken(), 'refresh-1');
    expect(session.accessToken, 'access-1');
  });

  test('invalid OTP surfaces INVALID_OTP', () async {
    final adapter = ScriptedAdapter((options) async {
      return jsonBody(401, {
        'success': false,
        'error': {
          'code': 'INVALID_OTP',
          'message': 'Invalid or expired code',
          'requestId': 'r1',
        },
      });
    });
    final session = _session(adapter);
    expect(
      () => session.verifyOtp(email: 'owner@example.com', otp: '000000'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'INVALID_OTP'),
      ),
    );
  });

  test('secure token store persists and clears the refresh token', () async {
    final store = MemorySecureTokenStore();
    await store.writeRefreshToken('refresh-secret');
    await store.writeUserId('user-1');
    expect(await store.readRefreshToken(), 'refresh-secret');
    expect(await store.readUserId(), 'user-1');
    await store.clear();
    expect(await store.readRefreshToken(), isNull);
    expect(await store.readUserId(), isNull);
  });

  test('session restoration refreshes then loads /me', () async {
    final store = MemorySecureTokenStore();
    await store.writeRefreshToken('refresh-old');
    final adapter = ScriptedAdapter((options) async {
      if (options.path.endsWith('/refresh')) {
        expect(options.data['refreshToken'], 'refresh-old');
        expect(options.headers.containsKey('Authorization'), isFalse);
        return jsonBody(200, {
          'success': true,
          'data': {
            'accessToken': 'access-2',
            'refreshToken': 'refresh-new',
            'expiresIn': '15m',
            'tokenType': 'Bearer',
          },
        });
      }
      if (options.path.endsWith('/me')) {
        expect(options.headers['Authorization'], 'Bearer access-2');
        return jsonBody(200, {
          'success': true,
          'data': {
            'id': 'user-1',
            'email': 'admin@example.com',
            'name': 'Admin',
            'roles': ['ADMIN'],
            'societyIds': [societyId],
            'primarySocietyId': societyId,
          },
        });
      }
      return notFound(options.path);
    });
    final session = _session(adapter, store: store);
    final profile = await session.restore();
    expect(profile?.roles, ['ADMIN']);
    expect(session.appRole, AppRole.admin);
    expect(await store.readRefreshToken(), 'refresh-new');
  });

  test('successful token refresh rotates both tokens', () async {
    final store = MemorySecureTokenStore();
    await store.writeRefreshToken('refresh-old');
    final adapter = ScriptedAdapter((options) async {
      expect(options.path.endsWith('/refresh'), isTrue);
      return jsonBody(200, {
        'success': true,
        'data': {
          'accessToken': 'access-next',
          'refreshToken': 'refresh-next',
          'expiresIn': '15m',
          'tokenType': 'Bearer',
        },
      });
    });
    final session = _session(adapter, store: store);
    expect(await session.refreshSession(), isTrue);
    expect(session.accessToken, 'access-next');
    expect(await store.readRefreshToken(), 'refresh-next');
  });

  test('concurrent refresh calls share one in-flight request', () async {
    final store = MemorySecureTokenStore();
    await store.writeRefreshToken('refresh-old');
    var refreshCalls = 0;
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    final adapter = ScriptedAdapter((options) async {
      expect(options.path.endsWith('/refresh'), isTrue);
      refreshCalls += 1;
      if (!refreshStarted.isCompleted) refreshStarted.complete();
      await releaseRefresh.future;
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
    final first = session.refreshSession();
    await refreshStarted.future;
    final second = session.refreshSession();
    releaseRefresh.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(refreshCalls, 1);
  });

  test('authenticated 401 retries once after a shared refresh', () async {
    final store = MemorySecureTokenStore();
    await store.writeRefreshToken('refresh-old');
    var refreshCalls = 0;
    var meCalls = 0;
    final adapter = ScriptedAdapter((options) async {
      if (options.path.endsWith('/refresh')) {
        refreshCalls += 1;
        return jsonBody(200, {
          'success': true,
          'data': {
            'accessToken': 'access-fresh',
            'refreshToken': 'refresh-fresh',
            'expiresIn': '15m',
            'tokenType': 'Bearer',
          },
        });
      }
      if (options.path.endsWith('/me')) {
        meCalls += 1;
        final auth = options.headers['Authorization'];
        if (auth == 'Bearer access-stale') {
          return jsonBody(401, {
            'success': false,
            'error': {'code': 'INVALID_TOKEN', 'message': 'Unauthorized'},
          });
        }
        expect(auth, 'Bearer access-fresh');
        return jsonBody(200, {
          'success': true,
          'data': {
            'id': 'user-1',
            'email': 'admin@example.com',
            'name': 'Admin',
            'roles': ['ADMIN'],
            'societyIds': [societyId],
          },
        });
      }
      return notFound(options.path);
    });
    final session = _session(adapter, store: store);
    session.debugSetAccessToken('access-stale');
    final profile = await session.api.auth.me();
    expect(profile.roles, ['ADMIN']);
    expect(refreshCalls, 1);
    expect(meCalls, 2);
    expect(session.accessToken, 'access-fresh');
  });

  test('refresh reuse clears the session', () async {
    final store = MemorySecureTokenStore();
    await store.writeRefreshToken('stolen-refresh');
    final adapter = ScriptedAdapter((options) async {
      return jsonBody(401, {
        'success': false,
        'error': {
          'code': 'REFRESH_REUSE',
          'message': 'Refresh token reuse detected. Please sign in again.',
        },
      });
    });
    final session = _session(adapter, store: store);
    expect(await session.refreshSession(), isFalse);
    expect(session.isAuthenticated, isFalse);
    expect(await store.readRefreshToken(), isNull);
  });

  test('logout clears secure storage when the API call fails', () async {
    final store = MemorySecureTokenStore();
    await store.writeRefreshToken('refresh-1');
    final adapter = ScriptedAdapter((options) async {
      return jsonBody(500, {
        'success': false,
        'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
      });
    });
    final session = _session(adapter, store: store);
    await session.logout();
    expect(await store.readRefreshToken(), isNull);
    expect(session.accessToken, isNull);
  });

  test('backend role routing prefers ADMIN and ignores dropdown tenant', () {
    final profile = AuthProfile(
      id: '1',
      email: 'a@b.c',
      name: 'A',
      roles: const ['OWNER', 'ADMIN'],
      societyIds: const [societyId],
    );
    expect(resolveAppRole(profile), AppRole.admin);
    expect(tryParseDropdownRole('tenant'), AppRole.tenant);
    expect(tryParseDropdownRole('tenant'), isNot(resolveAppRole(profile)));
  });

  test('tenant financial access follows backend flags', () {
    final access = OccupancyAccess.fromBackend(
      financial: false,
      residential: true,
      backendRole: 'TENANT',
      occupancyStatus: 'TENANT_OCCUPIED',
      displayName: 'Tenant',
    );
    expect(access.canFinance, isFalse);
    expect(access.canResidential, isTrue);
    expect(access.isTenantSession, isTrue);
    expect(() => access.assertFinance(), throwsA(isA<StateError>()));
  });

  test('owner of tenant-occupied flat keeps finance without residential', () {
    final access = OccupancyAccess.fromBackend(
      financial: true,
      residential: false,
      backendRole: 'OWNER',
      occupancyStatus: 'TENANT_OCCUPIED',
      displayName: 'Owner',
    );
    expect(access.canFinance, isTrue);
    expect(access.canResidential, isFalse);
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

Map<String, Object?> _ownerFlat(String societyId) => {
      'id': 'flat-1',
      'societyId': societyId,
      'wingId': 'wing-1',
      'number': 'A-101',
      'floor': 1,
      'position': 1,
      'flatType': '2BHK',
      'maintenanceRate': 4000,
      'isActive': true,
      'occupancyStatus': 'OWNER_OCCUPIED',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'access': {
        'financial': true,
        'residential': true,
        'role': 'OWNER',
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
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls += 1;
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
