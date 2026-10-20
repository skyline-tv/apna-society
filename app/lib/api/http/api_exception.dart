/// Error body from backend-v2 `errorHandler`:
/// `{ success: false, error: { code, message, details?, requestId? } }`.
///
/// `requestId` is omitted by a few handlers (for example an unknown report
/// export type). `details` is present for Zod validation failures.
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    this.requestId,
    this.details,
    this.statusCode,
  });

  final String code;
  final String message;
  final String? requestId;
  final Object? details;
  final int? statusCode;

  bool get isUnauthorized =>
      statusCode == 401 ||
      code == 'AUTH_REQUIRED' ||
      code == 'UNAUTHORIZED' ||
      code == 'INVALID_TOKEN' ||
      code == 'TOKEN_EXPIRED';

  factory ApiException.fromEnvelope(
    Map<dynamic, dynamic> body, {
    int? statusCode,
  }) {
    final error = body['error'];
    if (error is! Map) {
      return ApiException(
        code: 'RESPONSE_PARSE_ERROR',
        message: 'Error response is missing the error object',
        statusCode: statusCode,
      );
    }
    final code = error['code'];
    final message = error['message'];
    final requestId = error['requestId'];
    return ApiException(
      code: code is String && code.isNotEmpty ? code : 'UNKNOWN_ERROR',
      message: message is String && message.isNotEmpty
          ? message
          : 'Request failed',
      requestId: requestId is String && requestId.isNotEmpty ? requestId : null,
      details: error.containsKey('details') ? error['details'] : null,
      statusCode: statusCode,
    );
  }

  @override
  String toString() {
    final id = requestId == null ? '' : ' ($requestId)';
    return '$code: $message$id';
  }
}

class ApiParseException extends ApiException {
  ApiParseException(String message)
      : super(code: 'RESPONSE_PARSE_ERROR', message: message);
}
