import '../models/admin_user_models.dart';
import '../models/common.dart';
import '../models/society_models.dart';
import '../models/vehicle_models.dart';
import '../services/society_api.dart';

/// Cached admin society / wing / flat / dashboard reads and occupancy writes.
///
/// Widgets call this repository instead of [SocietyApi] so rebuilds do not
/// duplicate in-flight HTTP requests. Call [clear] on logout.
class SocietyRepository {
  SocietyRepository(this._api);

  final SocietyApi _api;

  SocietySummary? _society;
  Future<SocietySummary>? _societyInFlight;

  SocietyConfiguration? _configuration;
  Future<SocietyConfiguration>? _configurationInFlight;

  List<WingSummary>? _wings;
  Future<List<WingSummary>>? _wingsInFlight;

  DashboardStats? _dashboard;
  Future<DashboardStats>? _dashboardInFlight;

  final Map<String, FlatSummary> _flatById = {};
  final Map<String, Future<FlatSummary>> _flatInFlight = {};

  /// Last flats list page keyed by query fingerprint (for UI restore).
  Paged<FlatSummary>? lastFlatsPage;
  String? lastFlatsQueryKey;

  /// Full multi-page flat catalog for selectors (keyed by filter fingerprint).
  List<FlatSummary>? lastAllFlats;
  String? lastAllFlatsKey;

  /// Guard-safe society member flats cache.
  List<SocietyFlatPick>? lastMemberFlats;

  final Map<String, AdminOccupancyHistory> _historyByFlat = {};

  void clear() {
    _society = null;
    _societyInFlight = null;
    _configuration = null;
    _configurationInFlight = null;
    _wings = null;
    _wingsInFlight = null;
    _dashboard = null;
    _dashboardInFlight = null;
    _flatById.clear();
    _flatInFlight.clear();
    lastFlatsPage = null;
    lastFlatsQueryKey = null;
    lastAllFlats = null;
    lastAllFlatsKey = null;
    lastMemberFlats = null;
    _historyByFlat.clear();
  }

  /// Drops flat list, flat detail, dashboard, and history after occupancy writes.
  void invalidateAfterOccupancy(String flatId) {
    _flatById.remove(flatId);
    _flatInFlight.remove(flatId);
    lastFlatsPage = null;
    lastFlatsQueryKey = null;
    lastAllFlats = null;
    lastAllFlatsKey = null;
    _dashboard = null;
    _dashboardInFlight = null;
    _historyByFlat.remove(flatId);
  }

  Future<SocietySummary> society({bool force = false}) {
    if (!force && _society != null) return Future<SocietySummary>.value(_society!);
    if (!force && _societyInFlight != null) return _societyInFlight!;
    final future = _api.getSociety().then((value) {
      _society = value;
      return value;
    });
    _societyInFlight = future;
    return future.whenComplete(() {
      if (identical(_societyInFlight, future)) _societyInFlight = null;
    });
  }

  Future<SocietyConfiguration> configuration({bool force = false}) {
    if (!force && _configuration != null) {
      return Future<SocietyConfiguration>.value(_configuration!);
    }
    if (!force && _configurationInFlight != null) {
      return _configurationInFlight!;
    }
    final future = _api.getConfiguration().then((value) {
      _configuration = value;
      _society = value.society;
      _wings = value.wings;
      return value;
    });
    _configurationInFlight = future;
    return future.whenComplete(() {
      if (identical(_configurationInFlight, future)) {
        _configurationInFlight = null;
      }
    });
  }

  Future<List<WingSummary>> wings({bool force = false}) {
    if (!force && _wings != null) {
      return Future<List<WingSummary>>.value(_wings!);
    }
    if (!force && _wingsInFlight != null) return _wingsInFlight!;
    final future = _api.listWings().then((value) {
      _wings = value;
      return value;
    });
    _wingsInFlight = future;
    return future.whenComplete(() {
      if (identical(_wingsInFlight, future)) _wingsInFlight = null;
    });
  }

  Future<DashboardStats> dashboard({bool force = false}) {
    if (!force && _dashboard != null) {
      return Future<DashboardStats>.value(_dashboard!);
    }
    if (!force && _dashboardInFlight != null) return _dashboardInFlight!;
    final future = _api.dashboard().then((value) {
      _dashboard = value;
      return value;
    });
    _dashboardInFlight = future;
    return future.whenComplete(() {
      if (identical(_dashboardInFlight, future)) _dashboardInFlight = null;
    });
  }

  Future<Paged<FlatSummary>> listFlats({
    ListFlatsQuery query = const ListFlatsQuery(),
    bool force = false,
  }) async {
    final key = _flatsQueryKey(query);
    if (!force &&
        lastFlatsPage != null &&
        lastFlatsQueryKey == key &&
        query.page == lastFlatsPage!.pagination.page) {
      return lastFlatsPage!;
    }
    final page = await _api.listFlats(query: query);
    lastFlatsPage = page;
    lastFlatsQueryKey = key;
    for (final flat in page.items) {
      _flatById[flat.id] = flat;
    }
    return page;
  }

  /// Loads every flat page for the authenticated society.
  ///
  /// Uses the API max page size (100). Stops when `page >= totalPages` or an
  /// empty page is returned — never assumes a fixed society flat count.
  Future<List<FlatSummary>> listAllFlats({
    bool force = false,
    String? search,
    bool? isActive,
    String? wingId,
    int pageSize = 100,
  }) async {
    final capped = pageSize.clamp(1, 100);
    final key = [
      search ?? '',
      isActive?.toString() ?? '',
      wingId ?? '',
      '$capped',
    ].join('|');
    if (!force && lastAllFlats != null && lastAllFlatsKey == key) {
      return lastAllFlats!;
    }

    final collected = <FlatSummary>[];
    final seen = <String>{};
    var page = 1;
    var totalPages = 1;

    while (page <= totalPages) {
      final result = await listFlats(
        force: true,
        query: ListFlatsQuery(
          search: search,
          isActive: isActive,
          wingId: wingId,
          page: page,
          limit: capped,
        ),
      );
      totalPages = result.pagination.totalPages;
      if (result.items.isEmpty) break;
      for (final flat in result.items) {
        if (seen.add(flat.id)) {
          collected.add(flat);
        }
      }
      if (page >= totalPages) break;
      page += 1;
      // Safety against a buggy totalPages; not a society-size hardcode.
      if (page > 500) {
        throw StateError('Flat pagination exceeded safety page limit.');
      }
    }

    lastAllFlats = collected;
    lastAllFlatsKey = key;
    return collected;
  }

  /// Guard-safe flat picker via `/api/v1/societies/:id/flats`.
  Future<List<SocietyFlatPick>> listMemberFlats({
    required String societyId,
    bool force = false,
  }) async {
    if (!force && lastMemberFlats != null) return lastMemberFlats!;
    final flats = await _api.listMemberFlats(societyId: societyId);
    lastMemberFlats = flats;
    return flats;
  }

  Future<FlatSummary> flat(String flatId, {bool force = false}) {
    if (!force && _flatById.containsKey(flatId)) {
      return Future<FlatSummary>.value(_flatById[flatId]!);
    }
    final existing = _flatInFlight[flatId];
    if (!force && existing != null) return existing;
    final future = _api.getFlat(flatId).then((value) {
      _flatById[flatId] = value;
      return value;
    });
    _flatInFlight[flatId] = future;
    return future.whenComplete(() {
      if (identical(_flatInFlight[flatId], future)) {
        _flatInFlight.remove(flatId);
      }
    });
  }

  static String _flatsQueryKey(ListFlatsQuery query) {
    return [
      query.wingId,
      query.floor,
      query.flatType,
      query.occupancyStatus,
      query.isActive,
      query.search,
      query.page,
      query.limit,
      query.sortBy,
      query.sortOrder,
    ].join('|');
  }

  Future<AdminOccupancyHistory> occupancyHistory(
    String flatId, {
    int page = 1,
    int limit = 50,
    bool force = false,
  }) async {
    if (!force && page == 1 && _historyByFlat.containsKey(flatId)) {
      return _historyByFlat[flatId]!;
    }
    final history = await _api.occupancyHistory(
      flatId,
      page: page,
      limit: limit,
    );
    if (page == 1) _historyByFlat[flatId] = history;
    return history;
  }

  Future<OccupancyMutationResult> assignOwner(
    String flatId, {
    required String userId,
    required DateTime effectiveFrom,
    String? notes,
    List<VehicleDraftPayload>? vehicles,
  }) async {
    final result = await _api.assignOwner(
      flatId,
      userId: userId,
      effectiveFrom: effectiveFrom,
      notes: notes,
      vehicles: vehicles,
    );
    invalidateAfterOccupancy(flatId);
    return result;
  }

  Future<OccupancyMutationResult> assignTenant(
    String flatId, {
    required String userId,
    required DateTime effectiveFrom,
    String? notes,
    List<VehicleDraftPayload>? vehicles,
  }) async {
    final result = await _api.assignTenant(
      flatId,
      userId: userId,
      effectiveFrom: effectiveFrom,
      notes: notes,
      vehicles: vehicles,
    );
    invalidateAfterOccupancy(flatId);
    return result;
  }

  Future<OccupancyMutationResult> endOwnerOccupancy(
    String flatId, {
    required DateTime effectiveTo,
    required String reason,
    String? notes,
  }) async {
    final result = await _api.endOwnerOccupancy(
      flatId,
      effectiveTo: effectiveTo,
      reason: reason,
      notes: notes,
    );
    invalidateAfterOccupancy(flatId);
    return result;
  }

  Future<OccupancyMutationResult> endTenantOccupancy(
    String flatId, {
    required DateTime effectiveTo,
    required String reason,
    String? notes,
  }) async {
    final result = await _api.endTenantOccupancy(
      flatId,
      effectiveTo: effectiveTo,
      reason: reason,
      notes: notes,
    );
    invalidateAfterOccupancy(flatId);
    return result;
  }
}
