import '../config/api_config.dart';
import '../http/api_client.dart';
import '../models/admin_user_models.dart';
import '../models/common.dart';

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
      },
      decode: ProvisionUserResult.fromJson,
    );
  }

  Future<AdminUser> updateUser(
    String userId, {
    String? name,
    String? phone,
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
        if (canLogin != null) 'canLogin': canLogin,
        if (isActive != null) 'isActive': isActive,
      },
      decode: AdminUser.fromJson,
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
}
