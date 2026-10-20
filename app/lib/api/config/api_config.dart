/// API base URLs for the Flutter client.
///
/// The only host defined by `backend-v2` is the local server
/// (`PORT` default `4000`, OpenAPI server `http://localhost:4000`).
/// Staging and production hosts are not in that repository, so selecting
/// those flavors requires `STAGING_API_URL` / `PRODUCTION_API_URL` or
/// `API_BASE_URL` at build time.
enum ApiFlavor {
  development,
  staging,
  production,
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

  /// Local API from backend-v2 (`PORT` default and `/api/docs` server URL).
  static const developmentBaseUrl = 'http://127.0.0.1:4000';

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
  factory ApiConfig.fromEnvironment() {
    return ApiConfig.resolve(
      flavorName: const String.fromEnvironment(
        'API_ENV',
        defaultValue: 'development',
      ),
      baseUrlOverride: const String.fromEnvironment('API_BASE_URL'),
      stagingBaseUrl: const String.fromEnvironment('STAGING_API_URL'),
      productionBaseUrl: const String.fromEnvironment('PRODUCTION_API_URL'),
    );
  }

  factory ApiConfig.resolve({
    required String flavorName,
    String baseUrlOverride = '',
    String stagingBaseUrl = '',
    String productionBaseUrl = '',
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
            ApiFlavor.production => _requiredUrl(
                productionBaseUrl,
                'PRODUCTION_API_URL',
              ),
          };
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
        'backend-v2 does not define a staging or production host. '
        'Pass --dart-define=$defineName=https://… or --dart-define=API_BASE_URL=https://…',
      );
    }
    return url;
  }

  static String _normalizeBaseUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
