import '../config/api_config.dart';
import '../http/api_client.dart';
import '../models/admin_guard_models.dart';
import '../models/common.dart';

/// Admin security-guard APIs under `/api/v1/admin/guards`.
class AdminGuardApi {
  AdminGuardApi(this._client);
  final ApiClient _client;

  static const _root = '${ApiConfig.apiPrefix}/admin/guards';

  Future<Paged<AdminGuard>> listGuards({
    ListGuardsQuery query = const ListGuardsQuery(),
    String? societyId,
  }) {
    return _client.get(
      _root,
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, AdminGuard.fromJson),
    );
  }

  Future<AdminGuard> getGuard(String guardId, {String? societyId}) {
    return _client.get(
      '$_root/$guardId',
      societyId: societyId,
      decode: AdminGuard.fromJson,
    );
  }

  Future<ProvisionGuardResult> provision(
    CreateGuardRequest request, {
    String? societyId,
  }) {
    return _client.post(
      _root,
      societyId: societyId,
      body: request.toJson(),
      decode: ProvisionGuardResult.fromJson,
    );
  }

  Future<AdminGuard> updateGuard(
    String guardId,
    UpdateGuardRequest request, {
    String? societyId,
  }) {
    return _client.patch(
      '$_root/$guardId',
      societyId: societyId,
      body: request.toJson(),
      decode: AdminGuard.fromJson,
    );
  }

  Future<AdminGuard> deactivateGuard(
    String guardId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_root/$guardId/deactivate',
      societyId: societyId,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      decode: AdminGuard.fromJson,
    );
  }
}
