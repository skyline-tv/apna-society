import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/auth/app_role.dart';
import 'package:apna_society/api/auth/auth_session.dart';
import 'package:apna_society/api/auth/secure_token_store.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/app_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const societyId = '507f1f77bcf86cd799439011';

  tearDown(resetAuthSessionForTests);

  group('F-AUTH-01 recoverable restore', () {
    test('terminal refresh failure clears credentials', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('dead-refresh');
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(401, {
          'success': false,
          'error': {
            'code': 'REFRESH_EXPIRED',
            'message': 'Refresh expired',
          },
        });
      });
      final session = _session(adapter, store: store);
      final profile = await session.restore();
      expect(profile, isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(session.accessToken, isNull);
    });

    test('network failure during restore preserves refresh token', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-keep');
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(503, {
          'success': false,
          'error': {
            'code': 'NETWORK_UNAVAILABLE',
            'message': 'offline',
          },
        });
      });
      final session = _session(adapter, store: store);
      await expectLater(
        session.restore(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'NETWORK_UNAVAILABLE',
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'refresh-keep');
      expect(isTerminalSessionError(ApiException(
        code: 'NETWORK_UNAVAILABLE',
        message: 'offline',
      )), isFalse);
    });

    test('backend unavailable during restore preserves credentials', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-keep');
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(502, {
          'success': false,
          'error': {
            'code': 'NETWORK_ERROR',
            'message': 'bad gateway',
          },
        });
      });
      final session = _session(adapter, store: store);
      await expectLater(session.restore(), throwsA(isA<ApiException>()));
      expect(await store.readRefreshToken(), 'refresh-keep');
    });

    test('context loading failure after refresh preserves tokens', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-old');
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/refresh')) {
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
          return jsonBody(503, {
            'success': false,
            'error': {
              'code': 'NETWORK_TIMEOUT',
              'message': 'timeout',
            },
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      await expectLater(
        session.restore(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'NETWORK_TIMEOUT',
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'refresh-new');
      expect(session.accessToken, 'access-2');
    });

    test('successful retry after recoverable failure', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-old');
      var meAttempts = 0;
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/refresh')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-ok',
              'refreshToken': 'refresh-ok',
              'expiresIn': '15m',
              'tokenType': 'Bearer',
            },
          });
        }
        if (options.path.endsWith('/me')) {
          meAttempts += 1;
          if (meAttempts == 1) {
            return jsonBody(503, {
              'success': false,
              'error': {
                'code': 'NETWORK_UNAVAILABLE',
                'message': 'offline',
              },
            });
          }
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
      await expectLater(session.restore(), throwsA(isA<ApiException>()));
      expect(await store.readRefreshToken(), 'refresh-ok');

      final profile = await session.restore();
      expect(profile?.email, 'admin@example.com');
      expect(session.appRole, AppRole.admin);
      expect(meAttempts, 2);
    });

    test('AuthGate policy: terminal errors clear, network does not', () {
      expect(
        isTerminalSessionError(ApiException(
          code: 'REFRESH_REUSE',
          message: 'reuse',
          statusCode: 401,
        )),
        isTrue,
      );
      expect(
        isTerminalSessionError(ApiException(
          code: 'NETWORK_TIMEOUT',
          message: 'timeout',
        )),
        isFalse,
      );
      expect(isTerminalSessionError(StateError('no flats')), isFalse);
    });
  });

  group('F-AUTH-02 OTP context rollback', () {
    test('profile failure after OTP clears tokens', () async {
      final store = MemorySecureTokenStore();
      var clearedHook = 0;
      AuthSession.onLocalSessionCleared = () => clearedHook += 1;
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
          return jsonBody(500, {
            'success': false,
            'error': {'code': 'INTERNAL_ERROR', 'message': 'me failed'},
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      await expectLater(
        session.login(username: 'owner1', password: 'TestPassw0rd!'),
        throwsA(isA<ApiException>()),
      );
      expect(await store.readRefreshToken(), isNull);
      expect(session.accessToken, isNull);
      expect(session.profile, isNull);
      expect(session.isAuthenticated, isFalse);
      expect(clearedHook, 1);
    });

    test('empty flats context failure rolls back session', () async {
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
          return jsonBody(200, {'success': true, 'data': <Object>[]});
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      await expectLater(
        session.login(username: 'owner1', password: 'TestPassw0rd!'),
        throwsA(isA<StateError>()),
      );
      expect(await store.readRefreshToken(), isNull);
      expect(session.accessToken, isNull);
      expect(session.residentFlats, isEmpty);
    });

    test('successful login keeps tokens and profile', () async {
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
      final profile = await session.login(username: 'owner1', password: 'TestPassw0rd!');
      expect(profile.roles, ['ADMIN']);
      expect(await store.readRefreshToken(), 'refresh-1');
      expect(session.isAuthenticated, isTrue);
    });
  });

  group('F-AUTH-03 logout vs in-flight refresh', () {
    test('logout while refresh in flight discards late tokens', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-old');
      final refreshStarted = Completer<void>();
      final releaseRefresh = Completer<void>();
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/refresh')) {
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          await releaseRefresh.future;
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-stale',
              'refreshToken': 'refresh-stale',
              'expiresIn': '15m',
              'tokenType': 'Bearer',
            },
          });
        }
        if (options.path.endsWith('/logout')) {
          return jsonBody(200, {
            'success': true,
            'data': {'message': 'ok'},
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      final refreshFuture = session.refreshSession();
      await refreshStarted.future;
      await session.logout();
      expect(await store.readRefreshToken(), isNull);
      expect(session.accessToken, isNull);
      releaseRefresh.complete();
      expect(await refreshFuture, isFalse);
      expect(await store.readRefreshToken(), isNull);
      expect(session.accessToken, isNull);
    });

    test('refresh completing before logout keeps rotated tokens until logout',
        () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-old');
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/refresh')) {
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
        if (options.path.endsWith('/logout')) {
          expect(options.data['refreshToken'], 'refresh-fresh');
          return jsonBody(200, {
            'success': true,
            'data': {'message': 'ok'},
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      expect(await session.refreshSession(), isTrue);
      expect(await store.readRefreshToken(), 'refresh-fresh');
      await session.logout();
      expect(await store.readRefreshToken(), isNull);
    });

    test('new login after logout applies a fresh generation', () async {
      final store = MemorySecureTokenStore();
      await store.writeRefreshToken('refresh-old');
      final refreshStarted = Completer<void>();
      final releaseRefresh = Completer<void>();
      var phase = 'refresh';
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/refresh') && phase == 'refresh') {
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          await releaseRefresh.future;
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-stale',
              'refreshToken': 'refresh-stale',
              'expiresIn': '15m',
              'tokenType': 'Bearer',
            },
          });
        }
        if (options.path.endsWith('/logout')) {
          return jsonBody(200, {
            'success': true,
            'data': {'message': 'ok'},
          });
        }
        if (options.path.endsWith('/login')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'accessToken': 'access-new',
              'refreshToken': 'refresh-new',
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
              'email': 'admin2@example.com',
              'name': 'Admin2',
              'roles': ['ADMIN'],
              'societyIds': [societyId],
              'primarySocietyId': societyId,
            },
          });
        }
        return notFound(options.path);
      });
      final session = _session(adapter, store: store);
      final refreshFuture = session.refreshSession();
      await refreshStarted.future;
      await session.logout();
      phase = 'login';
      final profile = await session.login(username: 'owner1', password: 'TestPassw0rd!');
      releaseRefresh.complete();
      await refreshFuture;
      expect(profile.email, 'admin2@example.com');
      expect(await store.readRefreshToken(), 'refresh-new');
      expect(session.accessToken, 'access-new');
    });

    test('concurrent refresh calls still share one in-flight request', () async {
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
  });

  group('F-RPT-01 society rate sum formatter', () {
    test('monthly maintenance total of 588000 rupees uses money not moneyPaise',
        () {
      // Matches Admin dashboard / society inventory (whole rupees, Indian grouping).
      expect(money(588000), '₹5,88,000');
      // moneyPaise would incorrectly show one-hundredth of the rate sum.
      expect(moneyPaise(588000), '₹5,880.00');
      expect(money(588000), isNot(moneyPaise(588000)));
    });
  });

  group('F-DEMO-01 Security Staff nav removed', () {
    test('live Admin navigation no longer routes to SQLite Security Staff', () {
      final mainSrc = File('lib/main.dart').readAsStringSync();
      expect(mainSrc.contains("case 'security':"), isFalse);
      expect(mainSrc.contains('AdminSecurityStaffPage'), isFalse);
      expect(mainSrc.contains("label: 'Security Staff'"), isFalse);

      final moreSrc =
          File('lib/features/security/security_module.dart').readAsStringSync();
      expect(moreSrc.contains("onOpen('security')"), isFalse);
      expect(moreSrc.contains("label: 'Security Staff'"), isFalse);
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
