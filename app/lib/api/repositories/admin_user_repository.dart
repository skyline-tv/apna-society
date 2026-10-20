import '../models/admin_user_models.dart';
import '../models/common.dart';
import '../services/admin_user_api.dart';

/// Cached admin resident user reads and provisioning writes.
class AdminUserRepository {
  AdminUserRepository(this._api);

  final AdminUserApi _api;

  final Map<String, AdminUser> _byId = {};
  Paged<AdminUser>? lastList;
  String? lastListKey;

  void clear() {
    _byId.clear();
    lastList = null;
    lastListKey = null;
  }

  void invalidateUser(String userId) {
    _byId.remove(userId);
    lastList = null;
    lastListKey = null;
  }

  void invalidateLists() {
    lastList = null;
    lastListKey = null;
  }

  Future<Paged<AdminUser>> listUsers({
    ListUsersQuery query = const ListUsersQuery(),
    bool force = false,
  }) async {
    final key = [
      query.search,
      query.role,
      query.isActive,
      query.page,
      query.limit,
    ].join('|');
    if (!force && lastList != null && lastListKey == key) {
      return lastList!;
    }
    final page = await _api.listUsers(query: query);
    lastList = page;
    lastListKey = key;
    for (final user in page.items) {
      _byId[user.id] = user;
    }
    return page;
  }

  Future<AdminUser> getUser(String userId, {bool force = false}) async {
    if (!force && _byId.containsKey(userId)) {
      return _byId[userId]!;
    }
    final user = await _api.getUser(userId);
    _byId[userId] = user;
    return user;
  }

  Future<ProvisionUserResult> provision({
    required String name,
    required String email,
    required String role,
    String? phone,
  }) async {
    final result = await _api.provision(
      name: name,
      email: email,
      role: role,
      phone: phone,
    );
    _byId[result.user.id] = result.user;
    invalidateLists();
    return result;
  }

  Future<AdminUser> updateUser(
    String userId, {
    String? name,
    String? phone,
    bool? canLogin,
    bool? isActive,
  }) async {
    final user = await _api.updateUser(
      userId,
      name: name,
      phone: phone,
      canLogin: canLogin,
      isActive: isActive,
    );
    _byId[userId] = user;
    invalidateLists();
    return user;
  }

  Future<AdminUser> deactivateUser(String userId, {String? reason}) async {
    final user = await _api.deactivateUser(userId, reason: reason);
    _byId[userId] = user;
    invalidateLists();
    return user;
  }
}
