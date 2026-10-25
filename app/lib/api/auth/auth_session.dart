import 'dart:async';

import '../apna_api.dart';
import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/api_exception.dart';
import '../models/auth_models.dart';
import '../models/resident_models.dart';
import '../repositories/live_repositories.dart';
import 'app_role.dart';
import 'secure_token_store.dart';

/// Authenticated session for backend-v2.
///
/// Access token stays in memory. Refresh token is in [SecureTokenStore].
/// Concurrent 401s share one refresh. Terminal refresh failures clear the session.
///
/// Credential mutations are serialized and tagged with [_generation] so an
/// in-flight refresh cannot re-seed storage after [logout] / [clearLocal].
class AuthSession {
  AuthSession({
    ApiConfig? config,
    ApiClient? client,
    SecureTokenStore? tokenStore,
    ApnaApi? api,
  })  : _tokenStore = tokenStore ?? FlutterSecureTokenStore(),
        _client = client ??
            ApiClient(
              config: config ?? ApiConfig.fromEnvironment(),
            ) {
    _api = api ?? ApnaApi(client: _client);
    _client.accessToken = () => _accessToken;
    _client.onUnauthorized = _handleUnauthorized;
  }

  final SecureTokenStore _tokenStore;
  final ApiClient _client;
  late final ApnaApi _api;

  String? _accessToken;
  String? _refreshToken;
  AuthProfile? _profile;
  AppRole? _appRole;
  List<ResidentFlat> _residentFlats = const [];
  String? _selectedFlatId;
  Future<bool>? _refreshInFlight;

  /// Bumped on every local clear / logout so stale refresh applies are discarded.
  int _generation = 0;

  /// Serializes credential store mutations.
  Future<void>? _credentialGate;

  ApnaApi get api => _api;
  ApiClient get client => _client;
  AuthProfile? get profile => _profile;
  AppRole? get appRole => _appRole;
  List<ResidentFlat> get residentFlats => List.unmodifiable(_residentFlats);
  bool get isAuthenticated =>
      _accessToken != null && _accessToken!.isNotEmpty && _profile != null;

  String? get accessToken => _accessToken;

  /// Explicitly selected flat for multi-flat residents. Single-flat accounts
  /// always resolve to that flat. Multi-flat with no selection returns null.
  ResidentFlat? get selectedResidentFlat {
    if (_residentFlats.isEmpty) return null;
    if (_residentFlats.length == 1) return _residentFlats.first;
    final id = _selectedFlatId;
    if (id == null || id.isEmpty) return null;
    for (final flat in _residentFlats) {
      if (flat.flat.id == id) return flat;
    }
    return null;
  }

  String? get selectedResidentFlatId => selectedResidentFlat?.flat.id;

  /// Exposed for tests that assert logout/refresh generation races.
  int get debugGeneration => _generation;

  /// Optional hook after local credentials are wiped (e.g. disconnect Socket.IO).
  /// Set from app bootstrap to avoid an import cycle with the socket module.
  static void Function()? onLocalSessionCleared;

  /// Optional hook after a successful access-token refresh (reconnect Socket.IO).
  static void Function(AuthSession session)? onAccessTokenRefreshed;

  /// Test-only: set an in-memory access token without touching secure storage.
  void debugSetAccessToken(String? token) {
    _accessToken = token;
  }

  /// Preferred flat for display when no explicit multi-flat selection exists.
  /// Create flows must use [selectedResidentFlat] instead.
  ResidentFlat? get primaryResidentFlat {
    if (_residentFlats.isEmpty) return null;
    if (_appRole == AppRole.owner) {
      for (final flat in _residentFlats) {
        if (flat.access.role == 'OWNER') return flat;
      }
    }
    if (_appRole == AppRole.tenant) {
      for (final flat in _residentFlats) {
        if (flat.access.role == 'TENANT') return flat;
      }
    }
    return _residentFlats.first;
  }

  /// Records the active flat for multi-flat create flows and the resident shell.
  void selectResidentFlat(String flatId) {
    final match = _residentFlats.where((f) => f.flat.id == flatId);
    if (match.isEmpty) {
      throw StateError('Flat is not in the accessible set for this account.');
    }
    _selectedFlatId = flatId;
  }

  void clearResidentFlatSelection() {
    _selectedFlatId = null;
  }

  Future<T> _exclusiveCredentials<T>(Future<T> Function() action) async {
    while (_credentialGate != null) {
      try {
        await _credentialGate;
      } catch (_) {}
    }
    final gate = Completer<void>();
    _credentialGate = gate.future;
    try {
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_credentialGate, gate.future)) {
        _credentialGate = null;
      }
    }
  }

  /// Username/password login, stores tokens, loads `/me`, and role context.
  ///
  /// If context loading fails after tokens were applied, the new local session
  /// is rolled back so the app is not left half-authenticated.
  Future<AuthProfile> login({
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    final tokens = await _api.auth.login(
      username: username.trim(),
      password: password,
    );
    final generation = _generation;
    await _applyTokens(tokens, generation);
    if (rememberMe) {
      await _tokenStore.writeRememberedUsername(username.trim());
    } else {
      await _tokenStore.clearRememberedUsername();
    }
    try {
      return await loadProfileAndContext();
    } catch (_) {
      // Only roll back if this login still owns the generation (no newer login).
      if (generation == _generation) {
        await clearLocal();
      }
      rethrow;
    }
  }

  Future<String?> readRememberedUsername() =>
      _tokenStore.readRememberedUsername();

  /// Changes password. Revokes server sessions; caller should re-login.
  Future<ChangePasswordResult> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _api.auth.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
  }

  /// Restores a previous session from the refresh token.
  /// Returns null when there is nothing to restore or restore fails terminally.
  ///
  /// Recoverable network / context errors are rethrown without clearing
  /// credentials so AuthGate can offer retry.
  Future<AuthProfile?> restore() async {
    final refresh = await _tokenStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      await clearLocal();
      return null;
    }
    _refreshToken = refresh;
    try {
      final ok = await refreshSession();
      if (!ok) return null;
      return loadProfileAndContext();
    } on ApiException catch (error) {
      if (isTerminalSessionError(error)) {
        await clearLocal();
        return null;
      }
      rethrow;
    }
  }

  Future<AuthProfile> loadProfileAndContext() async {
    final profile = await _api.auth.me();
    _profile = profile;
    _appRole = resolveAppRole(profile);
    await _tokenStore.writeUserId(profile.id);

    final societyId = profile.primarySocietyId ??
        (profile.societyIds.isEmpty ? null : profile.societyIds.first);
    _client.societyId = societyId;

    _residentFlats = const [];
    if (_appRole == AppRole.owner || _appRole == AppRole.tenant) {
      _residentFlats = await _api.residents.flats(societyId: societyId);
      if (_residentFlats.isEmpty) {
        throw StateError(
          'No flat access is assigned to this account yet. Contact your society admin.',
        );
      }
      _syncFlatSelectionAfterLoad();
    } else {
      _selectedFlatId = null;
    }
    return profile;
  }

  void _syncFlatSelectionAfterLoad() {
    if (_residentFlats.length == 1) {
      _selectedFlatId = _residentFlats.first.flat.id;
      return;
    }
    // Multi-flat: keep an existing valid selection; otherwise clear so the UI
    // cannot silently submit as primaryResidentFlat.
    if (_selectedFlatId != null &&
        _residentFlats.every((f) => f.flat.id != _selectedFlatId)) {
      _selectedFlatId = null;
    }
  }

  /// Rotates tokens. Returns false when the session must end.
  Future<bool> refreshSession() async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }
    final refresh = _refreshToken ?? await _tokenStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      await clearLocal();
      return false;
    }
    final generation = _generation;
    final inFlight = _performRefresh(refresh, generation);
    _refreshInFlight = inFlight;
    try {
      return await inFlight;
    } finally {
      if (identical(_refreshInFlight, inFlight)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _performRefresh(String refresh, int generation) async {
    try {
      final tokens = await _api.auth.refresh(refreshToken: refresh);
      if (generation != _generation) {
        return false;
      }
      await _applyTokens(tokens, generation);
      final ok = generation == _generation &&
          _accessToken != null &&
          _accessToken!.isNotEmpty;
      if (ok) {
        onAccessTokenRefreshed?.call(this);
      }
      return ok;
    } on ApiException catch (error) {
      if (isTerminalSessionError(error)) {
        if (generation == _generation) {
          await clearLocal();
        }
        return false;
      }
      rethrow;
    }
  }

  Future<bool> _handleUnauthorized() async {
    return refreshSession();
  }

  Future<void> _applyTokens(TokenPair tokens, int generation) async {
    await _exclusiveCredentials(() async {
      if (generation != _generation) return;
      _accessToken = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      await _tokenStore.writeRefreshToken(tokens.refreshToken);
      if (generation != _generation) {
        // clearLocal/logout ran during the await; undo a stale write without
        // touching a newer generation's credentials.
        if (_refreshToken == tokens.refreshToken) {
          _accessToken = null;
          _refreshToken = null;
          await _tokenStore.clear();
        }
      }
    });
  }

  /// Calls logout with the refresh token, then clears local state.
  ///
  /// Generation is bumped before the network call so any in-flight refresh
  /// that completes afterward cannot restore credentials.
  Future<void> logout() async {
    final refresh = _refreshToken ?? await _tokenStore.readRefreshToken();
    // Invalidate in-flight refresh/apply immediately.
    _generation++;
    final logoutGeneration = _generation;
    try {
      if (refresh != null && refresh.isNotEmpty) {
        await _api.auth.logout(refreshToken: refresh);
      }
    } on ApiException {
      // Local clear still runs when the network call fails.
    } finally {
      if (logoutGeneration == _generation) {
        await _clearLocalPreservingGeneration();
      }
    }
  }

  Future<void> clearLocal() async {
    await _exclusiveCredentials(() async {
      _generation++;
      await _wipeMemoryAndStore();
    });
    onLocalSessionCleared?.call();
  }

  /// Used by [logout] after generation was already bumped.
  Future<void> _clearLocalPreservingGeneration() async {
    await _exclusiveCredentials(() async {
      await _wipeMemoryAndStore();
    });
    onLocalSessionCleared?.call();
  }

  Future<void> _wipeMemoryAndStore() async {
    _accessToken = null;
    _refreshToken = null;
    _profile = null;
    _appRole = null;
    _residentFlats = const [];
    _selectedFlatId = null;
    _client.societyId = null;
    clearLiveRepositories();
    await _tokenStore.clear();
  }
}

/// True when an auth error must end the local session (do not retry with same tokens).
bool isTerminalSessionError(Object error) {
  if (error is! ApiException) return false;
  if (error.isUnauthorized) return true;
  return isTerminalRefreshFailure(error.code);
}

/// Process-wide session used by AuthGate and home logout actions.
AuthSession? authSession;

AuthSession ensureAuthSession({
  ApiConfig? config,
  ApiClient? client,
  SecureTokenStore? tokenStore,
  ApnaApi? api,
}) {
  return authSession ??= AuthSession(
    config: config,
    client: client,
    tokenStore: tokenStore,
    api: api,
  );
}

void resetAuthSessionForTests() {
  authSession = null;
  AuthSession.onLocalSessionCleared = null;
  AuthSession.onAccessTokenRefreshed = null;
}

/// Replace the process-wide session (used when entering or leaving demo mode).
AuthSession replaceAuthSession({
  ApiConfig? config,
  ApiClient? client,
  SecureTokenStore? tokenStore,
  ApnaApi? api,
}) {
  authSession = AuthSession(
    config: config,
    client: client,
    tokenStore: tokenStore,
    api: api,
  );
  return authSession!;
}
