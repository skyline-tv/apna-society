import '../models/common.dart';
import '../models/parcel_models.dart';
import '../models/visitor_models.dart';
import '../services/visitor_api.dart';

/// Cached visitor reads and guarded mutations for guard / resident / admin.
class VisitorRepository {
  VisitorRepository(this._api);

  final VisitorApi _api;

  GuardDashboard? lastDashboard;
  AdminVisitorSummary? lastAdminSummary;
  Paged<Visitor>? lastGuardVisitors;
  String? lastGuardVisitorsKey;
  Paged<Visitor>? lastResidentVisitors;
  String? lastResidentVisitorsKey;
  Paged<Visitor>? lastResidentPending;
  Paged<Visitor>? lastAdminVisitors;
  String? lastAdminVisitorsKey;
  Paged<ParcelHandover>? lastGuardParcels;
  String? lastGuardParcelsKey;
  Paged<ParcelHandover>? lastResidentParcels;
  String? lastResidentParcelsKey;
  final Map<String, Visitor> _byId = {};
  final Map<String, ParcelHandover> _parcelsById = {};

  /// Prevents duplicate OTP verify / checkout / approve / reject / cancel / create.
  bool mutationLocked = false;

  void clear() {
    lastDashboard = null;
    lastAdminSummary = null;
    lastGuardVisitors = null;
    lastGuardVisitorsKey = null;
    lastResidentVisitors = null;
    lastResidentVisitorsKey = null;
    lastResidentPending = null;
    lastAdminVisitors = null;
    lastAdminVisitorsKey = null;
    lastGuardParcels = null;
    lastGuardParcelsKey = null;
    lastResidentParcels = null;
    lastResidentParcelsKey = null;
    _byId.clear();
    _parcelsById.clear();
    mutationLocked = false;
  }

  void invalidateCaches({String? visitorId}) {
    lastDashboard = null;
    lastAdminSummary = null;
    lastGuardVisitors = null;
    lastGuardVisitorsKey = null;
    lastResidentVisitors = null;
    lastResidentVisitorsKey = null;
    lastResidentPending = null;
    lastAdminVisitors = null;
    lastAdminVisitorsKey = null;
    lastGuardParcels = null;
    lastGuardParcelsKey = null;
    lastResidentParcels = null;
    lastResidentParcelsKey = null;
    if (visitorId != null) {
      _byId.remove(visitorId);
    } else {
      _byId.clear();
    }
    _parcelsById.clear();
  }

  void _store(Visitor visitor) {
    _byId[visitor.id] = visitor;
  }

  void _storePage(Paged<Visitor> page) {
    for (final v in page.items) {
      _store(v);
    }
  }

  Future<GuardDashboard> guardDashboard({bool force = false}) async {
    if (!force && lastDashboard != null) return lastDashboard!;
    final dash = await _api.guardDashboard();
    lastDashboard = dash;
    for (final v in dash.recent) {
      _store(v);
    }
    return dash;
  }

  Future<Paged<Visitor>> listGuardVisitors({
    ListVisitorsQuery query = const ListVisitorsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastGuardVisitors != null && lastGuardVisitorsKey == key) {
      return lastGuardVisitors!;
    }
    final page = await _api.listGuardVisitors(query: query);
    lastGuardVisitors = page;
    lastGuardVisitorsKey = key;
    _storePage(page);
    return page;
  }

  Future<Visitor> guardVisitor(String visitorId, {bool force = false}) async {
    if (!force && _byId.containsKey(visitorId)) return _byId[visitorId]!;
    final visitor = await _api.guardVisitor(visitorId);
    _store(visitor);
    return visitor;
  }

  Future<Visitor> createVisitor(CreateVisitorRequest request) async {
    if (mutationLocked) {
      throw StateError('A visitor request is already in progress.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.createVisitor(request);
      invalidateCaches();
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Visitor> verifyEntryOtpByCode({required String otp}) async {
    if (mutationLocked) {
      throw StateError('Entry verification is already in progress.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.verifyEntryOtpByCode(otp: otp);
      invalidateCaches(visitorId: visitor.id);
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Visitor> verifyEntryOtp(String visitorId, {required String otp}) async {
    if (mutationLocked) {
      throw StateError('Entry verification is already in progress.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.verifyEntryOtp(visitorId, otp: otp);
      invalidateCaches(visitorId: visitorId);
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Visitor> confirmVisitorEntry(String visitorId) async {
    if (mutationLocked) {
      throw StateError('Visitor entry is already being recorded.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.confirmVisitorEntry(visitorId);
      invalidateCaches(visitorId: visitorId);
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Visitor> checkout(String visitorId) async {
    if (mutationLocked) {
      throw StateError('Checkout is already in progress.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.checkout(visitorId);
      invalidateCaches(visitorId: visitorId);
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Paged<Visitor>> listResidentVisitors({
    ListVisitorsQuery query = const ListVisitorsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force &&
        lastResidentVisitors != null &&
        lastResidentVisitorsKey == key) {
      return lastResidentVisitors!;
    }
    final page = await _api.listResidentVisitors(query: query);
    lastResidentVisitors = page;
    lastResidentVisitorsKey = key;
    _storePage(page);
    return page;
  }

  Future<Paged<Visitor>> pendingVisitors({
    int? page,
    int? limit,
    bool force = false,
  }) async {
    if (!force && lastResidentPending != null && page == null) {
      return lastResidentPending!;
    }
    final result = await _api.pendingVisitors(page: page, limit: limit);
    lastResidentPending = result;
    _storePage(result);
    return result;
  }

  Future<Visitor> residentVisitor(String visitorId, {bool force = false}) async {
    if (!force && _byId.containsKey(visitorId)) return _byId[visitorId]!;
    final visitor = await _api.residentVisitor(visitorId);
    _store(visitor);
    return visitor;
  }

  Future<Visitor> approve(String visitorId) async {
    if (mutationLocked) {
      throw StateError('Visitor action is already in progress.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.approve(visitorId);
      invalidateCaches(visitorId: visitorId);
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Visitor> reject(String visitorId, {String? reason}) async {
    if (mutationLocked) {
      throw StateError('Visitor action is already in progress.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.reject(visitorId, reason: reason);
      invalidateCaches(visitorId: visitorId);
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<ParcelAuthorizationResult> leaveParcel(String visitorId) async {
    if (mutationLocked) {
      throw StateError('Visitor action is already in progress.');
    }
    mutationLocked = true;
    try {
      final result = await _api.leaveParcel(visitorId);
      invalidateCaches(visitorId: visitorId);
      _parcelsById[result.parcel.id] = result.parcel;
      return result;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Paged<ParcelHandover>> listGuardParcels({
    String? status,
    bool force = false,
  }) async {
    final key = status ?? '';
    if (!force && lastGuardParcels != null && lastGuardParcelsKey == key) {
      return lastGuardParcels!;
    }
    final page = await _api.listGuardParcels(status: status);
    lastGuardParcels = page;
    lastGuardParcelsKey = key;
    for (final parcel in page.items) {
      _parcelsById[parcel.id] = parcel;
    }
    return page;
  }

  Future<ParcelHandover> guardParcel(String parcelId, {bool force = false}) async {
    if (!force && _parcelsById.containsKey(parcelId)) {
      return _parcelsById[parcelId]!;
    }
    final parcel = await _api.guardParcel(parcelId);
    _parcelsById[parcel.id] = parcel;
    return parcel;
  }

  Future<ParcelHandover> receiveParcel(String parcelId) async {
    if (mutationLocked) {
      throw StateError('A parcel action is already in progress.');
    }
    mutationLocked = true;
    try {
      final parcel = await _api.receiveParcel(parcelId);
      lastGuardParcels = null;
      lastResidentParcels = null;
      _parcelsById[parcel.id] = parcel;
      return parcel;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Paged<ParcelHandover>> listResidentParcels({
    String? status,
    bool force = false,
  }) async {
    final key = status ?? '';
    if (!force &&
        lastResidentParcels != null &&
        lastResidentParcelsKey == key) {
      return lastResidentParcels!;
    }
    final page = await _api.listResidentParcels(status: status);
    lastResidentParcels = page;
    lastResidentParcelsKey = key;
    for (final parcel in page.items) {
      _parcelsById[parcel.id] = parcel;
    }
    return page;
  }

  Future<ParcelHandover> residentParcel(String parcelId, {bool force = false}) async {
    if (!force && _parcelsById.containsKey(parcelId)) {
      return _parcelsById[parcelId]!;
    }
    final parcel = await _api.residentParcel(parcelId);
    _parcelsById[parcel.id] = parcel;
    return parcel;
  }

  Future<Visitor> cancel(String visitorId) async {
    if (mutationLocked) {
      throw StateError('Visitor action is already in progress.');
    }
    mutationLocked = true;
    try {
      final visitor = await _api.cancel(visitorId);
      invalidateCaches(visitorId: visitorId);
      _store(visitor);
      return visitor;
    } finally {
      mutationLocked = false;
    }
  }

  Future<Paged<Visitor>> listAdminVisitors({
    ListVisitorsQuery query = const ListVisitorsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastAdminVisitors != null && lastAdminVisitorsKey == key) {
      return lastAdminVisitors!;
    }
    final page = await _api.listAdminVisitors(query: query);
    lastAdminVisitors = page;
    lastAdminVisitorsKey = key;
    _storePage(page);
    return page;
  }

  Future<AdminVisitorSummary> adminSummary({bool force = false}) async {
    if (!force && lastAdminSummary != null) return lastAdminSummary!;
    final summary = await _api.adminVisitorSummary();
    lastAdminSummary = summary;
    return summary;
  }

  Future<Visitor> adminVisitor(String visitorId, {bool force = false}) async {
    if (!force && _byId.containsKey(visitorId)) return _byId[visitorId]!;
    final visitor = await _api.adminVisitor(visitorId);
    _store(visitor);
    return visitor;
  }
}
