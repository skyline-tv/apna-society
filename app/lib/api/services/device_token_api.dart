import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';

class DeviceTokenApi {
  DeviceTokenApi(this._client);
  final ApiClient _client;

  static const _root = '${ApiConfig.apiPrefix}/me/device-tokens';

  Future<void> register({
    required String token,
    required String platform,
    String? deviceId,
    String? societyId,
  }) {
    return _client.post(
      _root,
      body: omitNulls({
        'token': token,
        'platform': platform,
        'deviceId': deviceId,
      }),
      societyId: societyId,
      decode: (_) => true,
    );
  }

  Future<void> unregister({
    required String token,
    String? societyId,
  }) {
    return _client.delete(
      _root,
      body: {'token': token},
      societyId: societyId,
      decode: (_) => true,
    );
  }
}
