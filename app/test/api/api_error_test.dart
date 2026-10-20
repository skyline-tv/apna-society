import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/http/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the backend error envelope', () {
    final error = ApiException.fromEnvelope(
      {
        'success': false,
        'error': {
          'code': 'INVALID_OTP',
          'message': 'Invalid or expired code',
          'requestId': 'req-1',
        },
      },
      statusCode: 401,
    );
    expect(error.code, 'INVALID_OTP');
    expect(error.message, 'Invalid or expired code');
    expect(error.requestId, 'req-1');
    expect(error.statusCode, 401);
    expect(error.isUnauthorized, isTrue);
    expect(error.toString(), 'INVALID_OTP: Invalid or expired code (req-1)');
  });

  test('requestId is optional and validation details are kept', () {
    final error = ApiException.fromEnvelope({
      'success': false,
      'error': {
        'code': 'VALIDATION_ERROR',
        'message': 'Validation failed',
        'details': {
          'fieldErrors': {
            'email': ['Valid email is required'],
          },
        },
      },
    });
    expect(error.requestId, isNull);
    expect(error.details, isA<Map>());
  });

  test('a body without an error object does not throw', () {
    final error = ApiException.fromEnvelope({'success': false});
    expect(error.code, 'RESPONSE_PARSE_ERROR');
  });

  test('redact removes tokens, otp, and signatures', () {
    final safe = redact({
      'email': 'owner@example.com',
      'otp': '123456',
      'refreshToken': 'refresh-secret',
      'nested': {
        'Authorization': 'Bearer access-secret',
        'signature': 'sig-secret',
      },
      'x-society-id': '507f1f77bcf86cd799439011',
    });
    final encoded = safe.toString();
    expect(encoded, contains('owner@example.com'));
    expect(encoded, contains('507f1f77bcf86cd799439011'));
    expect(encoded, isNot(contains('123456')));
    expect(encoded, isNot(contains('refresh-secret')));
    expect(encoded, isNot(contains('access-secret')));
    expect(encoded, isNot(contains('sig-secret')));
    expect(encoded, contains('[redacted]'));
  });

  test('traffic lines omit query strings', () {
    expect(
      trafficLine(method: 'POST', path: '/api/v1/auth/verify-otp', statusCode: 200),
      'POST /api/v1/auth/verify-otp 200',
    );
  });
}
