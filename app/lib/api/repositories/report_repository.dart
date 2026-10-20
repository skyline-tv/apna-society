import '../models/report_models.dart';
import '../services/report_api.dart';

/// Cached admin report reads. CSV export is never cached.
class ReportRepository {
  ReportRepository(this._api);

  final ReportApi _api;

  ReportsDashboard? _dashboard;
  String? _dashboardKey;
  FinancialReport? _financial;
  String? _financialKey;
  CollectionReport? _collections;
  String? _collectionsKey;
  OutstandingReport? _outstanding;
  String? _outstandingKey;
  ComplaintReport? _complaints;
  String? _complaintsKey;

  void clear() {
    _dashboard = null;
    _dashboardKey = null;
    _financial = null;
    _financialKey = null;
    _collections = null;
    _collectionsKey = null;
    _outstanding = null;
    _outstandingKey = null;
    _complaints = null;
    _complaintsKey = null;
  }

  String _key(ReportQuery query) => query.toQuery().values.join('|');

  Future<ReportsDashboard> dashboard({
    ReportQuery query = const ReportQuery(),
    bool force = false,
  }) async {
    final key = _key(query);
    if (!force && _dashboard != null && _dashboardKey == key) {
      return _dashboard!;
    }
    final result = await _api.dashboard(query: query);
    _dashboard = result;
    _dashboardKey = key;
    return result;
  }

  Future<FinancialReport> financial({
    ReportQuery query = const ReportQuery(),
    bool force = false,
  }) async {
    final key = _key(query);
    if (!force && _financial != null && _financialKey == key) {
      return _financial!;
    }
    final result = await _api.financial(query: query);
    _financial = result;
    _financialKey = key;
    return result;
  }

  Future<CollectionReport> collections({
    ReportQuery query = const ReportQuery(),
    bool force = false,
  }) async {
    final key = _key(query);
    if (!force && _collections != null && _collectionsKey == key) {
      return _collections!;
    }
    final result = await _api.collections(query: query);
    _collections = result;
    _collectionsKey = key;
    return result;
  }

  Future<OutstandingReport> outstanding({
    ReportQuery query = const ReportQuery(),
    bool force = false,
  }) async {
    final key = _key(query);
    if (!force && _outstanding != null && _outstandingKey == key) {
      return _outstanding!;
    }
    final result = await _api.outstanding(query: query);
    _outstanding = result;
    _outstandingKey = key;
    return result;
  }

  Future<ComplaintReport> complaints({
    ReportQuery query = const ReportQuery(),
    bool force = false,
  }) async {
    final key = _key(query);
    if (!force && _complaints != null && _complaintsKey == key) {
      return _complaints!;
    }
    final result = await _api.complaints(query: query);
    _complaints = result;
    _complaintsKey = key;
    return result;
  }

  Future<List<int>> exportCsv(
    String type, {
    ReportQuery query = const ReportQuery(),
  }) {
    return _api.exportCsv(type, query: query);
  }
}
