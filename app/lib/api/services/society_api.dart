import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/api_exception.dart';
import '../http/json_read.dart';
import '../models/admin_user_models.dart';
import '../models/common.dart';
import '../models/society_models.dart';

/// Admin society, wing, flat reads, and occupancy lifecycle writes.
///
/// Responses are the serialized summaries (`id`, not Mongo `_id`).
/// Foundation `GET /api/v1/societies/:societyId` returns lean documents and
/// is intentionally not wrapped here.
class SocietyApi {
  SocietyApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';

  static const _societies = '${ApiConfig.apiPrefix}/societies';

  Future<SocietySummary> getSociety({String? societyId}) {
    return _client.get(
      '$_admin/society',
      societyId: societyId,
      decode: SocietySummary.fromJson,
    );
  }

  /// Foundation flats list — any society member (including GUARD) may call.
  /// Lean Mongo documents; mapped to [SocietyFlatPick] for UI pickers.
  Future<List<SocietyFlatPick>> listMemberFlats({
    required String societyId,
  }) async {
    final wingCodes = await _memberWingCodes(societyId);
    return _client.get(
      '$_societies/$societyId/flats',
      societyId: societyId,
      decode: (data) {
        if (data is! List) {
          throw ApiParseException('Expected society flat list');
        }
        return data
            .map(
              (item) => SocietyFlatPick.fromLeanJson(
                item,
                wingCodesById: wingCodes,
              ),
            )
            .toList();
      },
    );
  }

  Future<Map<String, String>> _memberWingCodes(String societyId) async {
    try {
      return await _client.get(
        '$_societies/$societyId/wings',
        societyId: societyId,
        decode: (data) {
          final codes = <String, String>{};
          if (data is! List) return codes;
          for (final item in data) {
            final map = requireMap(item, 'wing');
            final id = optionalString(map, 'id') ??
                optionalString(map, '_id') ??
                map['_id']?.toString() ??
                '';
            final code = optionalString(map, 'code') ?? '?';
            if (id.isNotEmpty) codes[id] = code;
          }
          return codes;
        },
      );
    } catch (_) {
      return const {};
    }
  }

  Future<SocietyConfiguration> getConfiguration({String? societyId}) {
    return _client.get(
      '$_admin/society/configuration',
      societyId: societyId,
      decode: SocietyConfiguration.fromJson,
    );
  }

  Future<List<WingSummary>> listWings({String? societyId}) {
    return _client.get(
      '$_admin/wings',
      societyId: societyId,
      decode: (data) {
        if (data is! List) {
          throw ApiParseException('Expected wing list');
        }
        return data.map((item) => WingSummary.fromJson(requireMap(item, 'wing'))).toList();
      },
    );
  }

  Future<WingSummary> getWing(String wingId, {String? societyId}) {
    return _client.get(
      '$_admin/wings/$wingId',
      societyId: societyId,
      decode: (data) => WingSummary.fromJson(requireMap(data, 'wing')),
    );
  }

  Future<Paged<FlatSummary>> listFlats({
    ListFlatsQuery query = const ListFlatsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/flats',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, FlatSummary.fromJson),
    );
  }

  Future<FlatSummary> getFlat(String flatId, {String? societyId}) {
    return _client.get(
      '$_admin/flats/$flatId',
      societyId: societyId,
      decode: FlatSummary.fromJson,
    );
  }

  Future<DashboardStats> dashboard({String? societyId}) {
    return _client.get(
      '$_admin/dashboard',
      societyId: societyId,
      decode: DashboardStats.fromJson,
    );
  }

  Future<OccupancyMutationResult> assignOwner(
    String flatId, {
    required String userId,
    required DateTime effectiveFrom,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/flats/$flatId/assign-owner',
      societyId: societyId,
      body: {
        'userId': userId,
        'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      decode: OccupancyMutationResult.fromJson,
    );
  }

  Future<OccupancyMutationResult> assignTenant(
    String flatId, {
    required String userId,
    required DateTime effectiveFrom,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/flats/$flatId/assign-tenant',
      societyId: societyId,
      body: {
        'userId': userId,
        'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      decode: OccupancyMutationResult.fromJson,
    );
  }

  Future<OccupancyMutationResult> endOwnerOccupancy(
    String flatId, {
    required DateTime effectiveTo,
    required String reason,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/flats/$flatId/end-owner-occupancy',
      societyId: societyId,
      body: {
        'effectiveTo': effectiveTo.toUtc().toIso8601String(),
        'reason': reason.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      decode: OccupancyMutationResult.fromJson,
    );
  }

  Future<OccupancyMutationResult> endTenantOccupancy(
    String flatId, {
    required DateTime effectiveTo,
    required String reason,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/flats/$flatId/end-tenant-occupancy',
      societyId: societyId,
      body: {
        'effectiveTo': effectiveTo.toUtc().toIso8601String(),
        'reason': reason.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      decode: OccupancyMutationResult.fromJson,
    );
  }

  Future<AdminOccupancyHistory> occupancyHistory(
    String flatId, {
    int page = 1,
    int limit = 50,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/flats/$flatId/occupancy-history',
      societyId: societyId,
      query: {'page': page, 'limit': limit},
      decode: AdminOccupancyHistory.fromJson,
    );
  }

  Future<Paged<OccupancyRecordSummary>> listOccupancies({
    String? status,
    String? role,
    String? flatId,
    String? userId,
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/occupancies',
      societyId: societyId,
      query: {
        'status': status,
        'role': role,
        'flatId': flatId,
        'userId': userId,
        'page': page,
        'limit': limit,
      },
      decode: (data) => Paged.fromJson(
        data,
        OccupancyRecordSummary.fromJson,
      ),
    );
  }
}
