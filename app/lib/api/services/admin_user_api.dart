import '../config/api_config.dart';
import '../http/api_client.dart';
import '../models/admin_user_models.dart';
import '../models/common.dart';
import '../models/vehicle_models.dart';

/// Admin resident user APIs under `/api/v1/admin/users`.
class AdminUserApi {
  AdminUserApi(this._client);
  final ApiClient _client;

  static const _root = '${ApiConfig.apiPrefix}/admin/users';

  Future<Paged<AdminUser>> listUsers({
    ListUsersQuery query = const ListUsersQuery(),
    String? societyId,
  }) {
    return _client.get(
      _root,
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, (json) => AdminUser.fromJson(json)),
    );
  }

  Future<AdminUser> getUser(String userId, {String? societyId}) {
    return _client.get(
      '$_root/$userId',
      societyId: societyId,
      decode: AdminUser.fromJson,
    );
  }

  Future<ProvisionUserResult> provision({
    required String name,
    required String email,
    required String role,
    String? phone,
    String? username,
    String? password,
    String? flatId,
    List<VehicleDraftPayload>? vehicles,
    String? societyId,
  }) {
    return _client.post(
      _root,
      societyId: societyId,
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'role': role,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (username != null && username.trim().isNotEmpty)
          'username': username.trim(),
        if (password != null && password.isNotEmpty) 'password': password,
        if (flatId != null && flatId.isNotEmpty) 'flatId': flatId,
        if (vehicles != null && vehicles.isNotEmpty)
          'vehicles': vehicles.map((v) => v.toJson()).toList(),
      },
      decode: ProvisionUserResult.fromJson,
    );
  }

  Future<AdminUser> updateUser(
    String userId, {
    String? name,
    String? phone,
    String? username,
    bool? canLogin,
    bool? isActive,
    String? societyId,
  }) {
    return _client.patch(
      '$_root/$userId',
      societyId: societyId,
      body: {
        if (name != null) 'name': name.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (username != null) 'username': username.trim(),
        if (canLogin != null) 'canLogin': canLogin,
        if (isActive != null) 'isActive': isActive,
      },
      decode: AdminUser.fromJson,
    );
  }

  /// Admin-assisted password set/reset. Returns a one-time temporary password.
  Future<AdminSetPasswordResult> setPassword(
    String userId, {
    String? password,
    bool mustChangePassword = true,
    String? societyId,
  }) {
    return _client.post(
      '$_root/$userId/password',
      societyId: societyId,
      body: {
        if (password != null && password.isNotEmpty) 'password': password,
        'mustChangePassword': mustChangePassword,
      },
      decode: AdminSetPasswordResult.fromJson,
    );
  }

  Future<AdminUser> deactivateUser(
    String userId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_root/$userId/deactivate',
      societyId: societyId,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      decode: AdminUser.fromJson,
    );
  }

  /// Sets mobile for login. Clears verification until [confirmMobile] is called.
  Future<AdminUser> setMobile(
    String userId, {
    required String mobile,
    String? societyId,
  }) {
    return _client.put(
      '$_root/$userId/mobile',
      societyId: societyId,
      body: {'mobile': mobile.trim()},
      decode: AdminUser.fromJson,
    );
  }

  /// Admin attestation that mobile ownership was verified offline.
  Future<AdminUser> confirmMobile(String userId, {String? societyId}) {
    return _client.post(
      '$_root/$userId/mobile/confirm',
      societyId: societyId,
      decode: AdminUser.fromJson,
    );
  }
}
