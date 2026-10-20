import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/api_exception.dart';
import '../models/report_models.dart';

/// Admin report JSON routes and CSV export.
class ReportApi {
  ReportApi(this._client);
  final ApiClient _client;

  static const _root = '${ApiConfig.apiPrefix}/admin/reports';

  Future<ReportsDashboard> dashboard({
    ReportQuery query = const ReportQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_root/dashboard',
      query: query.toQuery(),
      societyId: societyId,
      decode: ReportsDashboard.fromJson,
    );
  }

  Future<FinancialReport> financial({
    ReportQuery query = const ReportQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_root/financial',
      query: query.toQuery(),
      societyId: societyId,
      decode: FinancialReport.fromJson,
    );
  }

  Future<CollectionReport> collections({
    ReportQuery query = const ReportQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_root/collections',
      query: query.toQuery(),
      societyId: societyId,
      decode: CollectionReport.fromJson,
    );
  }

  Future<OutstandingReport> outstanding({
    ReportQuery query = const ReportQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_root/outstanding',
      query: query.toQuery(),
      societyId: societyId,
      decode: OutstandingReport.fromJson,
    );
  }

  Future<ComplaintReport> complaints({
    ReportQuery query = const ReportQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_root/complaints',
      query: query.toQuery(),
      societyId: societyId,
      decode: ComplaintReport.fromJson,
    );
  }

  /// `GET /api/v1/admin/reports/export/:type?format=csv`.
  /// [type] is `financial`, `collections`, `outstanding`, `payments`, or `complaints`.
  Future<List<int>> exportCsv(
    String type, {
    ReportQuery query = const ReportQuery(),
    String? societyId,
  }) async {
    if (!reportExportTypes.contains(type)) {
      throw ApiException(
        code: 'INVALID_EXPORT_TYPE',
        message: 'Unknown export type',
      );
    }
    return _client.getBytes(
      '$_root/export/$type',
      query: {
        ...query.toQuery(),
        'format': 'csv',
      },
      societyId: societyId,
    );
  }
}
