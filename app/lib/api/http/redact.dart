/// Keys whose values must never appear in logs.
const _secretKeys = {
  'authorization',
  'accesstoken',
  'access_token',
  'refreshtoken',
  'refresh_token',
  'otp',
  'signature',
  'password',
  'token',
  'keyid',
  'key_id',
  'secret',
  'x-razorpay-signature',
};

/// Returns a copy safe to log. Nested maps and lists are walked.
/// Non-map values are returned unchanged.
Object? redact(Object? value) {
  if (value is Map) {
    return value.map((key, nested) {
      final name = key.toString().toLowerCase().replaceAll('-', '');
      final normalized = name.replaceAll('_', '');
      if (_secretKeys.contains(key.toString().toLowerCase()) ||
          _secretKeys.contains(normalized)) {
        return MapEntry(key.toString(), '[redacted]');
      }
      return MapEntry(key.toString(), redact(nested));
    });
  }
  if (value is List) {
    return value.map(redact).toList();
  }
  return value;
}

/// Traffic line: method, path, status. No query string, headers, or body.
String trafficLine({
  required String method,
  required String path,
  int? statusCode,
}) {
  final status = statusCode == null ? '' : ' $statusCode';
  return '$method $path$status';
}
