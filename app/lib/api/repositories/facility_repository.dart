import '../models/common.dart';
import '../models/facility_models.dart';
import '../services/facility_api.dart';

/// Cached facility / booking reads and guarded mutations.
class FacilityRepository {
  FacilityRepository(this._api);

  final FacilityApi _api;

  Paged<Facility>? lastResidentFacilities;
  String? lastResidentFacilitiesKey;
  Paged<Facility>? lastAdminFacilities;
  String? lastAdminFacilitiesKey;
  Paged<FacilityBooking>? lastResidentBookings;
  String? lastResidentBookingsKey;
  Paged<FacilityBooking>? lastAdminBookings;
  String? lastAdminBookingsKey;
  final Map<String, Facility> _facilityById = {};
  final Map<String, FacilityBooking> _bookingById = {};
  final Map<String, FacilityAvailability> _availabilityByKey = {};

  bool mutationLocked = false;

  void clear() {
    lastResidentFacilities = null;
    lastResidentFacilitiesKey = null;
    lastAdminFacilities = null;
    lastAdminFacilitiesKey = null;
    lastResidentBookings = null;
    lastResidentBookingsKey = null;
    lastAdminBookings = null;
    lastAdminBookingsKey = null;
    _facilityById.clear();
    _bookingById.clear();
    _availabilityByKey.clear();
    mutationLocked = false;
  }

  void invalidateCaches({String? facilityId, String? bookingId}) {
    lastResidentFacilities = null;
    lastResidentFacilitiesKey = null;
    lastAdminFacilities = null;
    lastAdminFacilitiesKey = null;
    lastResidentBookings = null;
    lastResidentBookingsKey = null;
    lastAdminBookings = null;
    lastAdminBookingsKey = null;
    _availabilityByKey.clear();
    if (facilityId != null) {
      _facilityById.remove(facilityId);
    } else {
      _facilityById.clear();
    }
    if (bookingId != null) {
      _bookingById.remove(bookingId);
    } else {
      _bookingById.clear();
    }
  }

  Future<T> _locked<T>(Future<T> Function() run) async {
    if (mutationLocked) {
      throw StateError('A facility action is already in progress.');
    }
    mutationLocked = true;
    try {
      return await run();
    } finally {
      mutationLocked = false;
    }
  }

  // ─── Resident ────────────────────────────────────────────────────────────

  Future<Paged<Facility>> listResident({
    ListFacilitiesQuery query = const ListFacilitiesQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force &&
        lastResidentFacilities != null &&
        lastResidentFacilitiesKey == key) {
      return lastResidentFacilities!;
    }
    final page = await _api.listResident(query: query);
    lastResidentFacilities = page;
    lastResidentFacilitiesKey = key;
    for (final f in page.items) {
      _facilityById[f.id] = f;
    }
    return page;
  }

  Future<Facility> getResident(String id, {bool force = false}) async {
    if (!force && _facilityById.containsKey(id)) return _facilityById[id]!;
    final f = await _api.getResident(id);
    _facilityById[f.id] = f;
    return f;
  }

  Future<FacilityAvailability> availability(
    String facilityId, {
    required String date,
    bool force = false,
  }) async {
    final key = '$facilityId|$date';
    if (!force && _availabilityByKey.containsKey(key)) {
      return _availabilityByKey[key]!;
    }
    final a = await _api.availability(facilityId, date: date);
    _availabilityByKey[key] = a;
    return a;
  }

  Future<FacilityBooking> createBooking(
    String facilityId,
    CreateFacilityBookingRequest request,
  ) {
    return _locked(() async {
      final b = await _api.createBooking(facilityId, request);
      invalidateCaches(facilityId: facilityId, bookingId: b.id);
      _bookingById[b.id] = b;
      return b;
    });
  }

  Future<Paged<FacilityBooking>> listResidentBookings({
    ListFacilityBookingsQuery query = const ListFacilityBookingsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force &&
        lastResidentBookings != null &&
        lastResidentBookingsKey == key) {
      return lastResidentBookings!;
    }
    final page = await _api.listResidentBookings(query: query);
    lastResidentBookings = page;
    lastResidentBookingsKey = key;
    for (final b in page.items) {
      _bookingById[b.id] = b;
    }
    return page;
  }

  Future<FacilityBooking> getResidentBooking(
    String id, {
    bool force = false,
  }) async {
    if (!force && _bookingById.containsKey(id)) return _bookingById[id]!;
    final b = await _api.getResidentBooking(id);
    _bookingById[b.id] = b;
    return b;
  }

  Future<FacilityBooking> cancelResidentBooking(
    String id, {
    String? reason,
  }) {
    return _locked(() async {
      final b = await _api.cancelResidentBooking(id, reason: reason);
      invalidateCaches(bookingId: id, facilityId: b.facilityId);
      _bookingById[b.id] = b;
      return b;
    });
  }

  // ─── Admin ───────────────────────────────────────────────────────────────

  Future<Paged<Facility>> listAdmin({
    ListFacilitiesQuery query = const ListFacilitiesQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force &&
        lastAdminFacilities != null &&
        lastAdminFacilitiesKey == key) {
      return lastAdminFacilities!;
    }
    final page = await _api.listAdmin(query: query);
    lastAdminFacilities = page;
    lastAdminFacilitiesKey = key;
    for (final f in page.items) {
      _facilityById[f.id] = f;
    }
    return page;
  }

  Future<Facility> getAdmin(String id, {bool force = false}) async {
    if (!force && _facilityById.containsKey(id)) return _facilityById[id]!;
    final f = await _api.getAdmin(id);
    _facilityById[f.id] = f;
    return f;
  }

  Future<Facility> createFacility(CreateFacilityRequest request) {
    return _locked(() async {
      final f = await _api.createFacility(request);
      invalidateCaches();
      _facilityById[f.id] = f;
      return f;
    });
  }

  Future<Facility> updateFacility(String id, UpdateFacilityRequest request) {
    return _locked(() async {
      final f = await _api.updateFacility(id, request);
      invalidateCaches(facilityId: id);
      _facilityById[f.id] = f;
      return f;
    });
  }

  Future<Facility> setActive(String id, {required bool isActive}) {
    return _locked(() async {
      final f = await _api.setActive(id, isActive: isActive);
      invalidateCaches(facilityId: id);
      _facilityById[f.id] = f;
      return f;
    });
  }

  Future<Paged<FacilityBooking>> listAdminBookings({
    ListFacilityBookingsQuery query = const ListFacilityBookingsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastAdminBookings != null && lastAdminBookingsKey == key) {
      return lastAdminBookings!;
    }
    final page = await _api.listAdminBookings(query: query);
    lastAdminBookings = page;
    lastAdminBookingsKey = key;
    for (final b in page.items) {
      _bookingById[b.id] = b;
    }
    return page;
  }

  Future<FacilityBooking> getAdminBooking(String id, {bool force = false}) async {
    if (!force && _bookingById.containsKey(id)) return _bookingById[id]!;
    final b = await _api.getAdminBooking(id);
    _bookingById[b.id] = b;
    return b;
  }

  Future<FacilityBooking> approveBooking(String id, {String? adminNotes}) {
    return _locked(() async {
      final b = await _api.approveBooking(id, adminNotes: adminNotes);
      invalidateCaches(bookingId: id, facilityId: b.facilityId);
      _bookingById[b.id] = b;
      return b;
    });
  }

  Future<FacilityBooking> rejectBooking(String id, {required String reason}) {
    return _locked(() async {
      final b = await _api.rejectBooking(id, reason: reason);
      invalidateCaches(bookingId: id, facilityId: b.facilityId);
      _bookingById[b.id] = b;
      return b;
    });
  }

  Future<FacilityBooking> cancelAdminBooking(String id, {String? reason}) {
    return _locked(() async {
      final b = await _api.cancelAdminBooking(id, reason: reason);
      invalidateCaches(bookingId: id, facilityId: b.facilityId);
      _bookingById[b.id] = b;
      return b;
    });
  }
}
