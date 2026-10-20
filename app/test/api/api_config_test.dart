import 'package:apna_society/api/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('development uses the local backend port when no override is set', () {
    final config = ApiConfig.resolve(flavorName: 'development');
    expect(config.flavor, ApiFlavor.development);
    expect(config.baseUrl, 'http://127.0.0.1:4000');
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

  test('production requires an explicit URL', () {
    expect(
      () => ApiConfig.resolve(flavorName: 'prod', productionBaseUrl: ''),
      throwsA(isA<ApiConfigurationException>()),
    );
    final config = ApiConfig.resolve(
      flavorName: 'production',
      productionBaseUrl: 'https://society.example.test',
    );
    expect(config.baseUrl, 'https://society.example.test');
  });

  test('unknown flavor is rejected', () {
    expect(
      () => ApiConfig.resolve(flavorName: 'local'),
      throwsA(isA<ApiConfigurationException>()),
    );
  });
}
