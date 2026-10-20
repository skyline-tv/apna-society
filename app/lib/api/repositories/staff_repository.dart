import '../models/common.dart';
import '../models/staff_models.dart';
import '../services/staff_api.dart';

/// Cached staff / attendance / shift reads and guarded mutations.
class StaffRepository {
  StaffRepository(this._api);

  final StaffApi _api;

  Paged<StaffMember>? lastStaffList;
  String? lastStaffListKey;
  Paged<StaffAttendance>? lastAttendanceList;
  String? lastAttendanceListKey;
  AttendanceSummary? lastAttendanceSummary;
  Paged<StaffShift>? lastShiftList;
  String? lastShiftListKey;
  final Map<String, StaffMember> _staffById = {};
  final Map<String, StaffAttendance> _attendanceById = {};
  final Map<String, StaffShift> _shiftById = {};

  bool mutationLocked = false;

  void clear() {
    lastStaffList = null;
    lastStaffListKey = null;
    lastAttendanceList = null;
    lastAttendanceListKey = null;
    lastAttendanceSummary = null;
    lastShiftList = null;
    lastShiftListKey = null;
    _staffById.clear();
    _attendanceById.clear();
    _shiftById.clear();
    mutationLocked = false;
  }

  void invalidateCaches({
    String? staffId,
    String? attendanceId,
    String? shiftId,
  }) {
    lastStaffList = null;
    lastStaffListKey = null;
    lastAttendanceList = null;
    lastAttendanceListKey = null;
    lastAttendanceSummary = null;
    lastShiftList = null;
    lastShiftListKey = null;
    if (staffId != null) {
      _staffById.remove(staffId);
    } else {
      _staffById.clear();
    }
    if (attendanceId != null) {
      _attendanceById.remove(attendanceId);
    } else {
      _attendanceById.clear();
    }
    if (shiftId != null) {
      _shiftById.remove(shiftId);
    } else {
      _shiftById.clear();
    }
  }

  Future<T> _locked<T>(Future<T> Function() run) async {
    if (mutationLocked) {
      throw StateError('A staff action is already in progress.');
    }
    mutationLocked = true;
    try {
      return await run();
    } finally {
      mutationLocked = false;
    }
  }

  // ─── Staff ───────────────────────────────────────────────────────────────

  Future<Paged<StaffMember>> listStaff({
    ListStaffQuery query = const ListStaffQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastStaffList != null && lastStaffListKey == key) {
      return lastStaffList!;
    }
    final page = await _api.list(query: query);
    lastStaffList = page;
    lastStaffListKey = key;
    for (final s in page.items) {
      _staffById[s.id] = s;
    }
    return page;
  }

  Future<StaffMember> getStaff(String id, {bool force = false}) async {
    if (!force && _staffById.containsKey(id)) return _staffById[id]!;
    final s = await _api.get(id);
    _staffById[s.id] = s;
    return s;
  }

  Future<StaffMember> createStaff(CreateStaffRequest request) {
    return _locked(() async {
      final s = await _api.create(request);
      invalidateCaches();
      _staffById[s.id] = s;
      return s;
    });
  }

  Future<StaffMember> updateStaff(String id, UpdateStaffRequest request) {
    return _locked(() async {
      final s = await _api.update(id, request);
      invalidateCaches(staffId: id);
      _staffById[s.id] = s;
      return s;
    });
  }

  Future<StaffMember> deactivateStaff(String id, {String? reason}) {
    return _locked(() async {
      final s = await _api.deactivate(id, reason: reason);
      invalidateCaches(staffId: id);
      _staffById[s.id] = s;
      return s;
    });
  }

  Future<StaffMember> terminateStaff(String id, {String? reason}) {
    return _locked(() async {
      final s = await _api.terminate(id, reason: reason);
      invalidateCaches(staffId: id);
      _staffById[s.id] = s;
      return s;
    });
  }

  Future<StaffMember> reactivateStaff(String id) {
    return _locked(() async {
      final s = await _api.reactivate(id);
      invalidateCaches(staffId: id);
      _staffById[s.id] = s;
      return s;
    });
  }

  // ─── Attendance ──────────────────────────────────────────────────────────

  Future<Paged<StaffAttendance>> listAttendance({
    ListAttendanceQuery query = const ListAttendanceQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force &&
        lastAttendanceList != null &&
        lastAttendanceListKey == key) {
      return lastAttendanceList!;
    }
    final page = await _api.listAttendance(query: query);
    lastAttendanceList = page;
    lastAttendanceListKey = key;
    for (final a in page.items) {
      _attendanceById[a.id] = a;
    }
    return page;
  }

  Future<AttendanceSummary> attendanceSummary({
    String? from,
    String? to,
    bool force = false,
  }) async {
    if (!force && lastAttendanceSummary != null && from == null && to == null) {
      return lastAttendanceSummary!;
    }
    final s = await _api.attendanceSummary(from: from, to: to);
    if (from == null && to == null) lastAttendanceSummary = s;
    return s;
  }

  Future<StaffAttendance> markAttendance(MarkAttendanceRequest request) {
    return _locked(() async {
      final a = await _api.markAttendance(request);
      invalidateCaches(attendanceId: a.id, staffId: request.staffId);
      _attendanceById[a.id] = a;
      return a;
    });
  }

  Future<StaffAttendance> checkOut(String attendanceId) {
    return _locked(() async {
      final a = await _api.checkOut(attendanceId);
      invalidateCaches(attendanceId: attendanceId);
      _attendanceById[a.id] = a;
      return a;
    });
  }

  Future<StaffAttendance> correctAttendance(
    String attendanceId,
    CorrectAttendanceRequest request,
  ) {
    return _locked(() async {
      final a = await _api.correctAttendance(attendanceId, request);
      invalidateCaches(attendanceId: attendanceId);
      _attendanceById[a.id] = a;
      return a;
    });
  }

  // ─── Shifts ──────────────────────────────────────────────────────────────

  Future<Paged<StaffShift>> listShifts({
    ListShiftsQuery query = const ListShiftsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastShiftList != null && lastShiftListKey == key) {
      return lastShiftList!;
    }
    final page = await _api.listShifts(query: query);
    lastShiftList = page;
    lastShiftListKey = key;
    for (final s in page.items) {
      _shiftById[s.id] = s;
    }
    return page;
  }

  Future<Paged<StaffShift>> schedule({
    required String from,
    required String to,
    bool force = false,
  }) {
    return listShifts(
      query: ListShiftsQuery(
        from: from,
        to: to,
        status: 'SCHEDULED',
        page: 1,
        limit: 500,
      ),
      force: force,
    );
  }

  Future<StaffShift> getShift(String id, {bool force = false}) async {
    if (!force && _shiftById.containsKey(id)) return _shiftById[id]!;
    final s = await _api.getShift(id);
    _shiftById[s.id] = s;
    return s;
  }

  Future<StaffShift> createShift(CreateShiftRequest request) {
    return _locked(() async {
      final s = await _api.createShift(request);
      invalidateCaches(shiftId: s.id, staffId: request.staffId);
      _shiftById[s.id] = s;
      return s;
    });
  }

  Future<StaffShift> updateShift(String id, UpdateShiftRequest request) {
    return _locked(() async {
      final s = await _api.updateShift(id, request);
      invalidateCaches(shiftId: id);
      _shiftById[s.id] = s;
      return s;
    });
  }

  Future<StaffShift> cancelShift(String id, {String? reason}) {
    return _locked(() async {
      final s = await _api.cancelShift(id, reason: reason);
      invalidateCaches(shiftId: id);
      _shiftById[s.id] = s;
      return s;
    });
  }
}
