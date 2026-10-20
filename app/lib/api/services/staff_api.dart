import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/common.dart';
import '../models/staff_models.dart';

/// Admin staff, attendance, and shift routes.
class StaffApi {
  StaffApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';

  // ─── Staff ───────────────────────────────────────────────────────────────

  Future<StaffMember> create(
    CreateStaffRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/staff',
      body: request.toJson(),
      societyId: societyId,
      decode: StaffMember.fromJson,
    );
  }

  Future<Paged<StaffMember>> list({
    ListStaffQuery query = const ListStaffQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/staff',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, StaffMember.fromJson),
    );
  }

  Future<StaffMember> get(String staffId, {String? societyId}) {
    return _client.get(
      '$_admin/staff/$staffId',
      societyId: societyId,
      decode: StaffMember.fromJson,
    );
  }

  Future<StaffMember> update(
    String staffId,
    UpdateStaffRequest request, {
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/staff/$staffId',
      body: request.toJson(),
      societyId: societyId,
      decode: StaffMember.fromJson,
    );
  }

  Future<StaffMember> deactivate(
    String staffId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/staff/$staffId/deactivate',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: StaffMember.fromJson,
    );
  }

  Future<StaffMember> terminate(
    String staffId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/staff/$staffId/terminate',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: StaffMember.fromJson,
    );
  }

  Future<StaffMember> reactivate(String staffId, {String? societyId}) {
    return _client.post(
      '$_admin/staff/$staffId/reactivate',
      societyId: societyId,
      decode: StaffMember.fromJson,
    );
  }

  // ─── Attendance ──────────────────────────────────────────────────────────

  Future<StaffAttendance> markAttendance(
    MarkAttendanceRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/staff-attendance',
      body: request.toJson(),
      societyId: societyId,
      decode: StaffAttendance.fromJson,
    );
  }

  Future<Paged<StaffAttendance>> listAttendance({
    ListAttendanceQuery query = const ListAttendanceQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/staff-attendance',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, StaffAttendance.fromJson),
    );
  }

  Future<AttendanceSummary> attendanceSummary({
    String? from,
    String? to,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/staff-attendance/summary',
      query: omitNulls({'from': from, 'to': to}),
      societyId: societyId,
      decode: AttendanceSummary.fromJson,
    );
  }

  Future<StaffAttendance> checkOut(String attendanceId, {String? societyId}) {
    return _client.post(
      '$_admin/staff-attendance/$attendanceId/checkout',
      societyId: societyId,
      decode: StaffAttendance.fromJson,
    );
  }

  Future<StaffAttendance> correctAttendance(
    String attendanceId,
    CorrectAttendanceRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/staff-attendance/$attendanceId/correct',
      body: request.toJson(),
      societyId: societyId,
      decode: StaffAttendance.fromJson,
    );
  }

  // ─── Shifts ──────────────────────────────────────────────────────────────

  Future<StaffShift> createShift(
    CreateShiftRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/staff-shifts',
      body: request.toJson(),
      societyId: societyId,
      decode: StaffShift.fromJson,
    );
  }

  Future<Paged<StaffShift>> listShifts({
    ListShiftsQuery query = const ListShiftsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/staff-shifts',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, StaffShift.fromJson),
    );
  }

  Future<Paged<StaffShift>> schedule({
    required String from,
    required String to,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/staff-shifts/schedule',
      query: {'from': from, 'to': to},
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, StaffShift.fromJson),
    );
  }

  Future<StaffShift> getShift(String shiftId, {String? societyId}) {
    return _client.get(
      '$_admin/staff-shifts/$shiftId',
      societyId: societyId,
      decode: StaffShift.fromJson,
    );
  }

  Future<StaffShift> updateShift(
    String shiftId,
    UpdateShiftRequest request, {
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/staff-shifts/$shiftId',
      body: request.toJson(),
      societyId: societyId,
      decode: StaffShift.fromJson,
    );
  }

  Future<StaffShift> cancelShift(
    String shiftId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/staff-shifts/$shiftId/cancel',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: StaffShift.fromJson,
    );
  }
}
