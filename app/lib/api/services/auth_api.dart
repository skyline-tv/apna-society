import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/auth_models.dart';

/// Auth routes under `/api/v1/auth`.
///
/// These methods do not store tokens. `login` and `refresh` return the
/// pair to the caller.
class AuthApi {
  AuthApi(this._client);
  final ApiClient _client;

  Future<TokenPair> login({
    required String username,
    required String password,
  }) {
    return _client.post(
      '${ApiConfig.apiPrefix}/auth/login',
      body: {
        'username': username.trim(),
        'password': password,
      },
      authenticate: false,
      decode: TokenPair.fromJson,
    );
  }

  Future<ChangePasswordResult> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _client.post(
      '${ApiConfig.apiPrefix}/auth/change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      },
      decode: ChangePasswordResult.fromJson,
    );
  }

  Future<TokenPair> refresh({required String refreshToken}) {
    return _client.post(
      '${ApiConfig.apiPrefix}/auth/refresh',
      body: {'refreshToken': refreshToken},
      authenticate: false,
      decode: TokenPair.fromJson,
    );
  }

  Future<LogoutResult> logout({String? refreshToken}) {
    return _client.post(
      '${ApiConfig.apiPrefix}/auth/logout',
      body: omitNulls({'refreshToken': refreshToken}),
      authenticate: false,
      decode: LogoutResult.fromJson,
    );
  }

  Future<LogoutAllResult> logoutAll() {
    return _client.post(
      '${ApiConfig.apiPrefix}/auth/logout-all',
      decode: LogoutAllResult.fromJson,
    );
  }

  Future<AuthProfile> me() {
    return _client.get(
      '${ApiConfig.apiPrefix}/auth/me',
      decode: AuthProfile.fromJson,
    );
  }
}
