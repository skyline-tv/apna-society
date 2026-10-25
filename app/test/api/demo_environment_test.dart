import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/config/demo_environment.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reviewer accounts are fictional and distinct by role', () {
    expect(DemoEnvironment.label, 'DEMO MODE — SAMPLE DATA');
    expect(DemoEnvironment.visitorOtp, '246810');
    expect(DemoEnvironment.loginOtp, '123456');
    expect(DemoEnvironment.accounts, hasLength(4));
    expect(
      DemoEnvironment.accounts.map((a) => a.username).toSet(),
      {'demo_admin', 'demo_owner', 'demo_tenant', 'demo_guard'},
    );
    for (final account in DemoEnvironment.accounts) {
      expect(account.password.contains('Reviewer-'), isTrue);
      expect(account.username.contains('.'), isFalse);
    }
  });

  test('public environment refuses to treat a production API as demo', () async {
    final adapter = _ScriptedAdapter((options) async {
      expect(options.path.endsWith('/public/environment'), isTrue);
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': {'demoMode': false, 'simulatedPayments': false},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
    dio.httpClientAdapter = adapter;
    final api = ApnaApi(
      client: ApiClient(
        config: ApiConfig.resolve(flavorName: 'development'),
        dio: dio,
      ),
    );
    final env = await api.auth.publicEnvironment();
    expect(env.demoMode, isFalse);
    expect(env.simulatedPayments, isFalse);
  });

  test('demo config never uses the production API host', () {
    final config = DemoEnvironment.config(
      demoBaseUrl: 'https://demo-apiapnasociety.skylinetv.in',
    );
    expect(config.flavor, ApiFlavor.demo);
    expect(config.baseUrl, isNot(ApiConfig.productionBaseUrl));
  });

  test('production login errors stay generic', () {
    final error = ApiException(
      code: 'INVALID_CREDENTIALS',
      message: 'Invalid username or password',
      statusCode: 401,
    );
    expect(error.code, 'INVALID_CREDENTIALS');
  });
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._handler);
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
