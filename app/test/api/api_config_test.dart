import 'package:apna_society/api/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('development uses the LAN backend host when no override is set', () {
    final config = ApiConfig.resolve(flavorName: 'development');
    expect(config.flavor, ApiFlavor.development);
    expect(config.baseUrl, 'http://192.168.1.130:4000');
    expect(ApiConfig.apiPrefix, '/api/v1');
  });

  test('API_BASE_URL override wins and trailing slashes are removed', () {
    final config = ApiConfig.resolve(
      flavorName: 'production',
      baseUrlOverride: 'https://api.example.test/',
    );
    expect(config.flavor, ApiFlavor.production);
    expect(config.baseUrl, 'https://api.example.test');
  });

  test('trailing /api/v1 on base URL is stripped to avoid doubled paths', () {
    final config = ApiConfig.resolve(
      flavorName: 'production',
      baseUrlOverride: 'https://apiapnasociety.skylinetv.in/api/v1/',
    );
    expect(config.baseUrl, 'https://apiapnasociety.skylinetv.in');
  });

  test('staging requires an explicit URL', () {
    expect(
      () => ApiConfig.resolve(flavorName: 'staging'),
      throwsA(
        isA<ApiConfigurationException>().having(
          (error) => error.message,
          'message',
          contains('STAGING_API_URL'),
        ),
      ),
    );
  });

  test('production defaults to the VPS origin', () {
    final config = ApiConfig.resolve(flavorName: 'production');
    expect(config.flavor, ApiFlavor.production);
    expect(config.baseUrl, ApiConfig.productionBaseUrl);
    expect(config.baseUrl, 'https://apiapnasociety.skylinetv.in');
    expect(config.baseUrl.contains('/api/v1'), isFalse);
  });

  test('production accepts an explicit PRODUCTION_API_URL override', () {
    final config = ApiConfig.resolve(
      flavorName: 'production',
      productionBaseUrl: 'https://society.example.test',
    );
    expect(config.baseUrl, 'https://society.example.test');
  });

  test('demo flavor uses the isolated demo host', () {
    final config = ApiConfig.resolve(
      flavorName: 'demo',
      demoBaseUrl: 'https://demo.example.test',
    );
    expect(config.flavor, ApiFlavor.demo);
    expect(config.baseUrl, 'https://demo.example.test');
    expect(config.baseUrl.contains('/api/v1'), isFalse);
  });

  test('unknown flavor is rejected', () {
    expect(
      () => ApiConfig.resolve(flavorName: 'local'),
      throwsA(isA<ApiConfigurationException>()),
    );
  });
}
