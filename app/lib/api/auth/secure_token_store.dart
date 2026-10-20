import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Platform secure storage for the refresh token and minimal identity.
///
/// Access tokens are never written here. Values are never logged.
abstract class SecureTokenStore {
  Future<void> writeRefreshToken(String token);
  Future<String?> readRefreshToken();
  Future<void> writeUserId(String userId);
  Future<String?> readUserId();
  Future<void> clear();
}

class FlutterSecureTokenStore implements SecureTokenStore {
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _refreshKey = 'apna_refresh_token';
  static const _userIdKey = 'apna_user_id';

  final FlutterSecureStorage _storage;

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshKey, value: token);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> writeUserId(String userId) =>
      _storage.write(key: _userIdKey, value: userId);

  @override
  Future<String?> readUserId() => _storage.read(key: _userIdKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
  }
}

/// In-memory store for unit tests.
class MemorySecureTokenStore implements SecureTokenStore {
  final Map<String, String> _values = {};

  @override
  Future<void> writeRefreshToken(String token) async {
    _values['refresh'] = token;
  }

  @override
  Future<String?> readRefreshToken() async => _values['refresh'];

  @override
  Future<void> writeUserId(String userId) async {
    _values['userId'] = userId;
  }

  @override
  Future<String?> readUserId() async => _values['userId'];

  @override
  Future<void> clear() async => _values.clear();
}
