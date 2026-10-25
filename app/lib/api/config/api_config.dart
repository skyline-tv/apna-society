import 'package:flutter/foundation.dart';

/// API base URLs for the Flutter client.
///
/// Dio [baseUrl] is the **origin only** (scheme + host). Route modules append
/// [apiPrefix] (`/api/v1/...`). Passing a URL that already ends in `/api/v1`
/// is normalized so paths are not doubled.
///
/// Flavors:
/// - **development** — LAN backend-v2 (override with `API_BASE_URL`).
/// - **staging** — requires `STAGING_API_URL` or `API_BASE_URL`.
/// - **production** — VPS origin [productionBaseUrl] by default.
///
/// Release APKs/AABs default to the production flavor when `API_ENV` is unset.
/// Local `flutter run` defaults to development.
enum ApiFlavor {
  development,
  staging,
  production,
  demo,
}

class ApiConfigurationException implements Exception {
  ApiConfigurationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ApiConfig {
  const ApiConfig({
    required this.flavor,
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 15),
    this.sendTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.captureTrafficLog = false,
  });

  /// LAN API from backend-v2 (device/emulator reachability on the local network).
  static const developmentBaseUrl = 'http://192.168.1.130:4000';

  /// Deployed VPS API origin (no `/api/v1` path — see [apiPrefix]).
  static const productionBaseUrl = 'https://apiapnasociety.skylinetv.in';

  static const apiPrefix = '/api/v1';

  final ApiFlavor flavor;
  final String baseUrl;
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;

  /// When true, the client records method, path, and status only.
  /// Headers and bodies are never written to that log.
  final bool captureTrafficLog;

  /// Reads compile-time environment defines:
  /// `API_ENV` (`development` | `staging` | `production`),
  /// `API_BASE_URL` (overrides the flavor URL),
  /// `STAGING_API_URL`, `PRODUCTION_API_URL`.
  ///
  /// When `API_ENV` is omitted: release → production, debug/profile → development.
  factory ApiConfig.fromEnvironment() {
    const definedFlavor = String.fromEnvironment('API_ENV');
    final flavorName = definedFlavor.isNotEmpty
        ? definedFlavor
        : (kReleaseMode ? 'production' : 'development');
    return ApiConfig.resolve(
      flavorName: flavorName,
      baseUrlOverride: const String.fromEnvironment('API_BASE_URL'),
      stagingBaseUrl: const String.fromEnvironment('STAGING_API_URL'),
      productionBaseUrl: const String.fromEnvironment(
        'PRODUCTION_API_URL',
        defaultValue: productionBaseUrl,
      ),
      demoBaseUrl: const String.fromEnvironment('DEMO_API_URL'),
      captureTrafficLog: !kReleaseMode &&
          const bool.fromEnvironment('API_TRAFFIC_LOG', defaultValue: false),
    );
  }

  factory ApiConfig.resolve({
    required String flavorName,
    String baseUrlOverride = '',
    String stagingBaseUrl = '',
    String productionBaseUrl = '',
    String demoBaseUrl = '',
    Duration connectTimeout = const Duration(seconds: 15),
    Duration sendTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 30),
    bool captureTrafficLog = false,
  }) {
    final flavor = _flavorFromName(flavorName);
    final override = _normalizeBaseUrl(baseUrlOverride);
    final baseUrl = override.isNotEmpty
        ? override
        : switch (flavor) {
            ApiFlavor.development => developmentBaseUrl,
            ApiFlavor.staging => _requiredUrl(
                stagingBaseUrl,
                'STAGING_API_URL',
              ),
            ApiFlavor.production => _normalizeBaseUrl(
                productionBaseUrl.isNotEmpty
                    ? productionBaseUrl
                    : ApiConfig.productionBaseUrl,
              ),
            ApiFlavor.demo => _normalizeBaseUrl(
                demoBaseUrl.isNotEmpty
                    ? demoBaseUrl
                    : (kReleaseMode
                        ? 'https://demo-apiapnasociety.skylinetv.in'
                        : 'http://192.168.1.130:4001'),
              ),
          };
    if (baseUrl.isEmpty) {
      throw ApiConfigurationException('Resolved API base URL is empty.');
    }
    return ApiConfig(
      flavor: flavor,
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
      captureTrafficLog: captureTrafficLog,
    );
  }

  static ApiFlavor _flavorFromName(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'development':
      case 'dev':
        return ApiFlavor.development;
      case 'staging':
        return ApiFlavor.staging;
      case 'production':
      case 'prod':
        return ApiFlavor.production;
      case 'demo':
        return ApiFlavor.demo;
      default:
        throw ApiConfigurationException(
          'Unknown API_ENV "$raw". Use development, staging, or production.',
        );
    }
  }

  static String _requiredUrl(String raw, String defineName) {
    final url = _normalizeBaseUrl(raw);
    if (url.isEmpty) {
      throw ApiConfigurationException(
        '$defineName is required for this API flavor. '
        'Pass --dart-define=$defineName=https://… or --dart-define=API_BASE_URL=https://…',
      );
    }
    return url;
  }

  /// Trims trailing slashes and a trailing `/api/v1` so Dio + [apiPrefix] do
  /// not produce `/api/v1/api/v1/...`.
  static String _normalizeBaseUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    const suffix = '/api/v1';
    if (url.toLowerCase().endsWith(suffix)) {
      url = url.substring(0, url.length - suffix.length);
      while (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
    }
    return url;
  }
}
