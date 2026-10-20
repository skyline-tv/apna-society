import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/common.dart';
import '../models/visitor_models.dart';

/// Guard, resident, and admin visitor routes.
/// Plaintext entry OTP is never returned by these models.
class VisitorApi {
  VisitorApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';
  static const _guard = '${ApiConfig.apiPrefix}/guard';
  static const _resident = '${ApiConfig.apiPrefix}/resident';

  Future<GuardDashboard> guardDashboard({String? societyId}) {
    return _client.get(
      '$_guard/dashboard',
      societyId: societyId,
      decode: GuardDashboard.fromJson,
    );
  }

  Future<Visitor> createVisitor(
    CreateVisitorRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_guard/visitors',
      body: omitNulls(request.toJson()),
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Paged<Visitor>> listGuardVisitors({
    ListVisitorsQuery query = const ListVisitorsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_guard/visitors',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Visitor.fromJson),
    );
  }

  Future<Visitor> guardVisitor(String visitorId, {String? societyId}) {
    return _client.get(
      '$_guard/visitors/$visitorId',
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Visitor> verifyEntryOtp(
    String visitorId, {
    required String otp,
    String? societyId,
  }) {
    return _client.post(
      '$_guard/visitors/$visitorId/verify-entry-otp',
      body: {'otp': otp},
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Visitor> checkout(String visitorId, {String? societyId}) {
    return _client.post(
      '$_guard/visitors/$visitorId/checkout',
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Paged<Visitor>> listResidentVisitors({
    ListVisitorsQuery query = const ListVisitorsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_resident/visitors',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Visitor.fromJson),
    );
  }

  Future<Paged<Visitor>> pendingVisitors({
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_resident/visitors/pending',
      query: omitNulls({'page': page, 'limit': limit}),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Visitor.fromJson),
    );
  }

  Future<Visitor> residentVisitor(String visitorId, {String? societyId}) {
    return _client.get(
      '$_resident/visitors/$visitorId',
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Visitor> approve(String visitorId, {String? societyId}) {
    return _client.post(
      '$_resident/visitors/$visitorId/approve',
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Visitor> reject(
    String visitorId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_resident/visitors/$visitorId/reject',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Visitor> cancel(String visitorId, {String? societyId}) {
    return _client.post(
      '$_resident/visitors/$visitorId/cancel',
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }

  Future<Paged<Visitor>> listAdminVisitors({
    ListVisitorsQuery query = const ListVisitorsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/visitors',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Visitor.fromJson),
    );
  }

  Future<AdminVisitorSummary> adminVisitorSummary({String? societyId}) {
    return _client.get(
      '$_admin/visitors/summary',
      societyId: societyId,
      decode: AdminVisitorSummary.fromJson,
    );
  }

  Future<Visitor> adminVisitor(String visitorId, {String? societyId}) {
    return _client.get(
      '$_admin/visitors/$visitorId',
      societyId: societyId,
      decode: Visitor.fromJson,
    );
  }
}
