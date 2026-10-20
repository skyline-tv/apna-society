import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Platform secure storage for the refresh token and minimal identity.
///
/// Access tokens and passwords are never written here. Values are never logged.
abstract class SecureTokenStore {
  Future<void> writeRefreshToken(String token);
  Future<String?> readRefreshToken();
  Future<void> writeUserId(String userId);
  Future<String?> readUserId();
  Future<void> writeRememberedUsername(String username);
  Future<String?> readRememberedUsername();
  Future<void> clearRememberedUsername();
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
  static const _rememberUsernameKey = 'apna_remember_username';

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
  Future<void> writeRememberedUsername(String username) =>
      _storage.write(key: _rememberUsernameKey, value: username.trim());

  @override
  Future<String?> readRememberedUsername() =>
      _storage.read(key: _rememberUsernameKey);

  @override
  Future<void> clearRememberedUsername() =>
      _storage.delete(key: _rememberUsernameKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
    // Remembered username survives logout when "Remember me" was enabled;
    // callers clear it explicitly when the option is unchecked.
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
  Future<void> writeRememberedUsername(String username) async {
    _values['rememberUsername'] = username.trim();
  }

  @override
  Future<String?> readRememberedUsername() async => _values['rememberUsername'];

  @override
  Future<void> clearRememberedUsername() async {
    _values.remove('rememberUsername');
  }

  @override
  Future<void> clear() async {
    final remembered = _values['rememberUsername'];
    _values.clear();
    if (remembered != null) {
      _values['rememberUsername'] = remembered;
    }
  }
}
