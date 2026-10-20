import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/common.dart';
import '../models/facility_models.dart';

/// Resident and admin facility / booking routes.
class FacilityApi {
  FacilityApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';
  static const _resident = '${ApiConfig.apiPrefix}/resident';

  // ─── Resident facilities ─────────────────────────────────────────────────

  Future<Paged<Facility>> listResident({
    ListFacilitiesQuery query = const ListFacilitiesQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_resident/facilities',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Facility.fromJson),
    );
  }

  Future<Facility> getResident(String facilityId, {String? societyId}) {
    return _client.get(
      '$_resident/facilities/$facilityId',
      societyId: societyId,
      decode: Facility.fromJson,
    );
  }

  Future<FacilityAvailability> availability(
    String facilityId, {
    required String date,
    String? societyId,
  }) {
    return _client.get(
      '$_resident/facilities/$facilityId/availability',
      query: {'date': date},
      societyId: societyId,
      decode: FacilityAvailability.fromJson,
    );
  }

  Future<FacilityBooking> createBooking(
    String facilityId,
    CreateFacilityBookingRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_resident/facilities/$facilityId/bookings',
      body: request.toJson(),
      societyId: societyId,
      decode: FacilityBooking.fromJson,
    );
  }

  Future<Paged<FacilityBooking>> listResidentBookings({
    ListFacilityBookingsQuery query = const ListFacilityBookingsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_resident/facility-bookings',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, FacilityBooking.fromJson),
    );
  }

  Future<FacilityBooking> getResidentBooking(
    String bookingId, {
    String? societyId,
  }) {
    return _client.get(
      '$_resident/facility-bookings/$bookingId',
      societyId: societyId,
      decode: FacilityBooking.fromJson,
    );
  }

  Future<FacilityBooking> cancelResidentBooking(
    String bookingId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_resident/facility-bookings/$bookingId/cancel',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: FacilityBooking.fromJson,
    );
  }

  // ─── Admin facilities ────────────────────────────────────────────────────

  Future<Facility> createFacility(
    CreateFacilityRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/facilities',
      body: request.toJson(),
      societyId: societyId,
      decode: Facility.fromJson,
    );
  }

  Future<Paged<Facility>> listAdmin({
    ListFacilitiesQuery query = const ListFacilitiesQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/facilities',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Facility.fromJson),
    );
  }

  Future<Facility> getAdmin(String facilityId, {String? societyId}) {
    return _client.get(
      '$_admin/facilities/$facilityId',
      societyId: societyId,
      decode: Facility.fromJson,
    );
  }

  Future<Facility> updateFacility(
    String facilityId,
    UpdateFacilityRequest request, {
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/facilities/$facilityId',
      body: request.toJson(),
      societyId: societyId,
      decode: Facility.fromJson,
    );
  }

  Future<Facility> setActive(
    String facilityId, {
    required bool isActive,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/facilities/$facilityId/set-active',
      body: {'isActive': isActive},
      societyId: societyId,
      decode: Facility.fromJson,
    );
  }

  Future<Paged<FacilityBooking>> listAdminBookings({
    ListFacilityBookingsQuery query = const ListFacilityBookingsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/facility-bookings',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, FacilityBooking.fromJson),
    );
  }

  Future<FacilityBooking> getAdminBooking(
    String bookingId, {
    String? societyId,
  }) {
    return _client.get(
      '$_admin/facility-bookings/$bookingId',
      societyId: societyId,
      decode: FacilityBooking.fromJson,
    );
  }

  Future<FacilityBooking> approveBooking(
    String bookingId, {
    String? adminNotes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/facility-bookings/$bookingId/approve',
      body: omitNulls({'adminNotes': adminNotes}),
      societyId: societyId,
      decode: FacilityBooking.fromJson,
    );
  }

  Future<FacilityBooking> rejectBooking(
    String bookingId, {
    required String reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/facility-bookings/$bookingId/reject',
      body: {'reason': reason.trim()},
      societyId: societyId,
      decode: FacilityBooking.fromJson,
    );
  }

  Future<FacilityBooking> cancelAdminBooking(
    String bookingId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/facility-bookings/$bookingId/cancel',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: FacilityBooking.fromJson,
    );
  }
}
