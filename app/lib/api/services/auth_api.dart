import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/auth_models.dart';

/// Auth routes under `/api/v1/auth`.
///
/// These methods do not store tokens. `verifyOtp` and `refresh` return the
/// pair to the caller.
class AuthApi {
  AuthApi(this._client);
  final ApiClient _client;

  Future<OtpRequestResult> requestOtp({required String mobile}) {
    return _client.post(
      '${ApiConfig.apiPrefix}/auth/request-otp',
      body: {'mobile': mobile},
      authenticate: false,
      decode: OtpRequestResult.fromJson,
    );
  }

  Future<TokenPair> verifyOtp({required String mobile, required String otp}) {
    return _client.post(
      '${ApiConfig.apiPrefix}/auth/verify-otp',
      body: {'mobile': mobile, 'otp': otp},
      authenticate: false,
      decode: TokenPair.fromJson,
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
