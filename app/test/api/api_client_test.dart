import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const societyId = '507f1f77bcf86cd799439011';

  test('unwraps success data and sends a valid x-society-id', () async {
    final adapter = ScriptedAdapter((options) async {
      expect(options.headers['x-society-id'], societyId);
      expect(options.headers['authorization'], 'Bearer access-secret');
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
    });
    final api = _api(adapter, token: 'access-secret', societyId: societyId);
    final profile = await api.auth.me();
    expect(profile.email, 'owner@example.com');
    expect(profile.roles, ['OWNER']);
    expect(api.client.trafficLog.single.line, 'GET /api/v1/auth/me 200');
    expect(api.client.trafficLog.single.line, isNot(contains('access-secret')));
  });

  test('maps an error envelope without copying secrets into the message', () async {
    final adapter = ScriptedAdapter((options) async {
      return jsonBody(401, {
        'success': false,
        'error': {
          'code': 'INVALID_CREDENTIALS',
          'message': 'Invalid username or password',
          'requestId': 'req-9',
        },
      });
    });
    final api = _api(adapter);
    expect(
      () => api.auth.login(username: 'owner1', password: 'wrong'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'INVALID_CREDENTIALS')
            .having((error) => error.requestId, 'requestId', 'req-9')
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.toString(), 'string', isNot(contains('wrong'))),
      ),
    );
  });

  test('timeouts become NETWORK_TIMEOUT', () async {
    final adapter = ScriptedAdapter((options) async {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    });
    final api = _api(adapter);
    expect(
      () => api.auth.me(),
      throwsA(
        isA<ApiException>().having((error) => error.code, 'code', 'NETWORK_TIMEOUT'),
      ),
    );
  });

  test('connection failures become NETWORK_UNAVAILABLE', () async {
    final adapter = ScriptedAdapter((options) async {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    });
    final api = _api(adapter);
    expect(
      () => api.auth.me(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'NETWORK_UNAVAILABLE',
        ),
      ),
    );
  });

  test('omits x-society-id when no society is set', () async {
    final adapter = ScriptedAdapter((options) async {
      expect(options.headers.containsKey('x-society-id'), isFalse);
      expect(options.headers.containsKey('authorization'), isFalse);
      expect(options.path, '/api/v1/auth/login');
      return jsonBody(200, {
        'success': true,
        'data': {
          'accessToken': 'a',
          'refreshToken': 'r-token-at-least-20-chars',
          'expiresIn': '15m',
          'tokenType': 'Bearer',
        },
      });
    });
    final api = _api(adapter);
    final result =
        await api.auth.login(username: 'owner1', password: 'TestPassw0rd!');
    expect(result.accessToken, 'a');
  });

  test('rejects an invalid society id before the request is sent', () async {
    final adapter = ScriptedAdapter((options) async {
      return jsonBody(200, {'success': true, 'data': {}});
    });
    final api = _api(adapter);
    expect(
      () => api.society.getSociety(societyId: 'not-an-id'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'INVALID_SOCIETY_CONTEXT',
        ),
      ),
    );
    expect(adapter.calls, 0);
  });

  test('a per-call society id overrides the client default', () async {
    const other = '507f1f77bcf86cd799439012';
    final adapter = ScriptedAdapter((options) async {
      expect(options.headers['x-society-id'], other);
      return jsonBody(200, {
        'success': true,
        'data': {'unreadCount': 2},
      });
    });
    final api = _api(adapter, societyId: societyId);
    final count = await api.notifications.unreadCount(societyId: other);
    expect(count.unreadCount, 2);
  });
}

ApnaApi _api(
  ScriptedAdapter adapter, {
  String? token,
  String? societyId,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  return ApnaApi(
    client: ApiClient(
      config: ApiConfig.resolve(
        flavorName: 'development',
        captureTrafficLog: true,
      ),
      dio: dio,
      accessToken: token == null ? null : () => token,
      societyId: societyId,
    ),
  );
}

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
