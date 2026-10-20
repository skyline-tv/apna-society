import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/common.dart';
import 'api_exception.dart';
import 'redact.dart';

/// Supplies an access token for the next request.
///
/// A null or empty value omits the Authorization header.
typedef AccessTokenReader = String? Function();

/// Called once when an authenticated request receives 401.
/// Return true after a successful token refresh so the client can retry.
typedef UnauthorizedHandler = Future<bool> Function();

class ApiTrafficEvent {
  const ApiTrafficEvent({
    required this.method,
    required this.path,
    this.statusCode,
  });

  final String method;
  final String path;
  final int? statusCode;

  String get line => trafficLine(
        method: method,
        path: path,
        statusCode: statusCode,
      );
}

/// Central Dio client for backend-v2.
///
/// Successful JSON is `{ success: true, data }`. Failures are
/// `{ success: false, error: { code, message, requestId } }`.
/// `x-society-id` is sent only when a 24-hex ObjectId is supplied.
class ApiClient {
  ApiClient({
    required this.config,
    Dio? dio,
    this.accessToken,
    this.onUnauthorized,
    String? societyId,
  })  : _societyId = societyId,
        dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.baseUrl,
                connectTimeout: config.connectTimeout,
                sendTimeout: config.sendTimeout,
                receiveTimeout: config.receiveTimeout,
                responseType: ResponseType.json,
                headers: const {
                  Headers.acceptHeader: Headers.jsonContentType,
                  Headers.contentTypeHeader: Headers.jsonContentType,
                },
              ),
            );

  final ApiConfig config;
  final Dio dio;
  AccessTokenReader? accessToken;
  UnauthorizedHandler? onUnauthorized;
  String? _societyId;

  /// Active society for subsequent calls. Empty clears the header.
  String? get societyId => _societyId;

  set societyId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _societyId = null;
      return;
    }
    _assertObjectId(trimmed);
    _societyId = trimmed;
  }

  final List<ApiTrafficEvent> trafficLog = [];

  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    String? societyId,
    bool authenticate = true,
    required T Function(Object? data) decode,
  }) {
    return _send(
      method: 'GET',
      path: path,
      query: query,
      societyId: societyId,
      authenticate: authenticate,
      decode: decode,
    );
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    String? societyId,
    bool authenticate = true,
    required T Function(Object? data) decode,
  }) {
    return _send(
      method: 'POST',
      path: path,
      body: body,
      query: query,
      societyId: societyId,
      authenticate: authenticate,
      decode: decode,
    );
  }

  Future<T> patch<T>(
    String path, {
    Object? body,
    String? societyId,
    bool authenticate = true,
    required T Function(Object? data) decode,
  }) {
    return _send(
      method: 'PATCH',
      path: path,
      body: body,
      societyId: societyId,
      authenticate: authenticate,
      decode: decode,
    );
  }

  Future<T> delete<T>(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    String? societyId,
    bool authenticate = true,
    required T Function(Object? data) decode,
  }) {
    return _send(
      method: 'DELETE',
      path: path,
      body: body,
      query: query,
      societyId: societyId,
      authenticate: authenticate,
      decode: decode,
    );
  }

  /// Multipart POST (e.g. complaint attachment field `file`).
  Future<T> postMultipart<T>(
    String path, {
    required FormData formData,
    Map<String, Object?>? query,
    String? societyId,
    bool authenticate = true,
    required T Function(Object? data) decode,
  }) async {
    final response = await _request(
      method: 'POST',
      path: path,
      body: formData,
      query: query,
      societyId: societyId,
      authenticate: authenticate,
      responseType: ResponseType.json,
    );
    return _decodeSuccess(response, decode);
  }

  /// CSV (or other non-JSON) download. JSON error envelopes are still parsed.
  Future<List<int>> getBytes(
    String path, {
    Map<String, Object?>? query,
    String? societyId,
    bool authenticate = true,
  }) async {
    final response = await _request(
      method: 'GET',
      path: path,
      query: query,
      societyId: societyId,
      authenticate: authenticate,
      responseType: ResponseType.bytes,
    );
    final data = response.data;
    if (data is List<int>) {
      return data;
    }
    throw ApiParseException('Expected binary response body');
  }

  Future<T> _send<T>({
    required String method,
    required String path,
    Object? body,
    Map<String, Object?>? query,
    String? societyId,
    required bool authenticate,
    required T Function(Object? data) decode,
  }) async {
    final response = await _request(
      method: method,
      path: path,
      body: body,
      query: query,
      societyId: societyId,
      authenticate: authenticate,
      responseType: ResponseType.json,
    );
    return _decodeSuccess(response, decode);
  }

  Future<Response<dynamic>> _request({
    required String method,
    required String path,
    Object? body,
    Map<String, Object?>? query,
    String? societyId,
    required bool authenticate,
    required ResponseType responseType,
    bool isRetry = false,
  }) async {
    final headers = <String, Object?>{};
    if (authenticate) {
      final token = accessToken?.call();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    final society = _resolveSociety(societyId);
    if (society != null) {
      headers['x-society-id'] = society;
    }

    try {
      final response = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query == null ? null : omitNullQuery(query),
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
        ),
      );
      _record(method, path, response.statusCode);
      return response;
    } on DioException catch (error) {
      _record(method, path, error.response?.statusCode);
      final mapped = _mapDio(error);
      if (!isRetry &&
          authenticate &&
          mapped.isUnauthorized &&
          onUnauthorized != null) {
        final refreshed = await onUnauthorized!();
        if (refreshed) {
          return _request(
            method: method,
            path: path,
            body: body,
            query: query,
            societyId: societyId,
            authenticate: authenticate,
            responseType: responseType,
            isRetry: true,
          );
        }
      }
      throw mapped;
    }
  }

  T _decodeSuccess<T>(
    Response<dynamic> response,
    T Function(Object? data) decode,
  ) {
    final body = response.data;
    if (body is! Map) {
      throw ApiParseException('Expected JSON object response');
    }
    if (body['success'] == false) {
      throw ApiException.fromEnvelope(
        body,
        statusCode: response.statusCode,
      );
    }
    if (body['success'] != true) {
      throw ApiParseException('Response is missing success: true');
    }
    try {
      return decode(body['data']);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiParseException('Could not read response data');
    }
  }

  ApiException _mapDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException(
          code: 'NETWORK_TIMEOUT',
          message: 'The request timed out',
        );
      case DioExceptionType.connectionError:
        return ApiException(
          code: 'NETWORK_UNAVAILABLE',
          message: 'Could not reach the server',
        );
      case DioExceptionType.cancel:
        return ApiException(
          code: 'REQUEST_CANCELLED',
          message: 'The request was cancelled',
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          code: 'TLS_ERROR',
          message: 'The server certificate could not be verified',
        );
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        final data = error.response?.data;
        final envelope = _asEnvelope(data);
        if (envelope != null && envelope['success'] == false) {
          return ApiException.fromEnvelope(envelope, statusCode: status);
        }
        return ApiException(
          code: status == null ? 'HTTP_ERROR' : 'HTTP_$status',
          message: 'Request failed',
          statusCode: status,
        );
      case DioExceptionType.unknown:
        return ApiException(
          code: 'NETWORK_ERROR',
          message: 'The request could not be completed',
        );
    }
  }

  Map<dynamic, dynamic>? _asEnvelope(Object? data) {
    if (data is Map) return data;
    if (data is List<int>) {
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map) return decoded;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  String? _resolveSociety(String? override) {
    final raw = (override ?? _societyId)?.trim();
    if (raw == null || raw.isEmpty) return null;
    _assertObjectId(raw);
    return raw;
  }

  void _assertObjectId(String value) {
    if (!isObjectId(value)) {
      throw ApiException(
        code: 'INVALID_SOCIETY_CONTEXT',
        message: 'x-society-id must be a 24-character hex ObjectId',
      );
    }
  }

  void _record(String method, String path, int? statusCode) {
    if (!config.captureTrafficLog) return;
    trafficLog.add(
      ApiTrafficEvent(method: method, path: path, statusCode: statusCode),
    );
  }
}

Map<String, dynamic> omitNullQuery(Map<String, Object?> query) {
  return {
    for (final entry in query.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}
