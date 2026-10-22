import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/common.dart';
import '../models/vehicle_models.dart';

/// Resident vehicles, admin parking, and guard gate logs.
class VehicleApi {
  VehicleApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';
  static const _resident = '${ApiConfig.apiPrefix}/resident';
  static const _guard = '${ApiConfig.apiPrefix}/guard';

  // ─── Resident vehicles ───────────────────────────────────────────────────

  Future<Vehicle> register(
    RegisterVehicleRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_resident/vehicles',
      body: omitNulls(request.toJson()),
      societyId: societyId,
      decode: Vehicle.fromJson,
    );
  }

  Future<VehicleList> list({String? societyId}) {
    return _client.get(
      '$_resident/vehicles',
      societyId: societyId,
      decode: VehicleList.fromJson,
    );
  }

  Future<Vehicle> get(String vehicleId, {String? societyId}) {
    return _client.get(
      '$_resident/vehicles/$vehicleId',
      societyId: societyId,
      decode: Vehicle.fromJson,
    );
  }

  Future<Vehicle> update(
    String vehicleId, {
    String? make,
    String? model,
    String? colour,
    String? vehicleType,
    String? societyId,
  }) {
    return _client.patch(
      '$_resident/vehicles/$vehicleId',
      body: omitNulls({
        'make': make,
        'model': model,
        'colour': colour,
        'vehicleType': vehicleType,
      }),
      societyId: societyId,
      decode: Vehicle.fromJson,
    );
  }

  Future<Vehicle> deactivate(
    String vehicleId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_resident/vehicles/$vehicleId/deactivate',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: Vehicle.fromJson,
    );
  }

  Future<ParkingList> parking({String? societyId}) {
    return _client.get(
      '$_resident/parking',
      societyId: societyId,
      decode: ParkingList.fromJson,
    );
  }

  Future<ParkingAllocation> parkingAllocation(
    String allocationId, {
    String? societyId,
  }) {
    return _client.get(
      '$_resident/parking/allocations/$allocationId',
      societyId: societyId,
      decode: (data) =>
          ParkingAllocation.fromJson(requireMap(data, 'allocation')),
    );
  }

  // ─── Admin vehicles & parking ────────────────────────────────────────────

  Future<Paged<Vehicle>> listAdminVehicles({
    ListAdminVehiclesQuery query = const ListAdminVehiclesQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/vehicles',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Vehicle.fromJson),
    );
  }

  Future<Vehicle> adminRegister(
    AdminRegisterVehicleRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/vehicles',
      body: request.toJson(),
      societyId: societyId,
      decode: Vehicle.fromJson,
    );
  }

  Future<Vehicle> adminUpdate(
    String vehicleId, {
    String? make,
    String? model,
    String? colour,
    String? vehicleType,
    String? registrationNumber,
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/vehicles/$vehicleId',
      body: omitNulls({
        'make': make,
        'model': model,
        'colour': colour,
        'vehicleType': vehicleType,
        'registrationNumber': registrationNumber,
      }),
      societyId: societyId,
      decode: Vehicle.fromJson,
    );
  }

  Future<Vehicle> adminDeactivate(
    String vehicleId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/vehicles/$vehicleId/deactivate',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: Vehicle.fromJson,
    );
  }

  Future<ParkingSlot> createParkingSlot({
    required String slotNumber,
    required String parkingType,
    String? locationDescription,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/parking/slots',
      body: omitNulls({
        'slotNumber': slotNumber,
        'parkingType': parkingType,
        'locationDescription': locationDescription,
      }),
      societyId: societyId,
      decode: ParkingSlot.fromJson,
    );
  }

  Future<Paged<ParkingSlot>> listParkingSlots({
    ListParkingSlotsQuery query = const ListParkingSlotsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/parking/slots',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, ParkingSlot.fromJson),
    );
  }

  Future<ParkingSummary> parkingSummary({String? societyId}) {
    return _client.get(
      '$_admin/parking/summary',
      societyId: societyId,
      decode: ParkingSummary.fromJson,
    );
  }

  Future<ParkingSlot> getParkingSlot(String slotId, {String? societyId}) {
    return _client.get(
      '$_admin/parking/slots/$slotId',
      societyId: societyId,
      decode: ParkingSlot.fromJson,
    );
  }

  Future<ParkingSlot> updateParkingSlot(
    String slotId, {
    String? locationDescription,
    String? parkingType,
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/parking/slots/$slotId',
      body: omitNulls({
        'locationDescription': locationDescription,
        'parkingType': parkingType,
      }),
      societyId: societyId,
      decode: ParkingSlot.fromJson,
    );
  }

  Future<ParkingSlot> setParkingSlotActive(
    String slotId, {
    required bool isActive,
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/parking/slots/$slotId/set-active',
      body: omitNulls({
        'isActive': isActive,
        'reason': reason,
      }),
      societyId: societyId,
      decode: ParkingSlot.fromJson,
    );
  }

  Future<ParkingAllocation> allocateParking({
    required String flatId,
    required String vehicleId,
    required String parkingSlotId,
    String? startsAt,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/parking/allocations',
      body: omitNulls({
        'flatId': flatId,
        'vehicleId': vehicleId,
        'parkingSlotId': parkingSlotId,
        'startsAt': startsAt,
      }),
      societyId: societyId,
      decode: (data) =>
          ParkingAllocation.fromJson(requireMap(data, 'allocation')),
    );
  }

  Future<Paged<ParkingAllocation>> listAllocations({
    ListAllocationsQuery query = const ListAllocationsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/parking/allocations',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, ParkingAllocation.fromJson),
    );
  }

  Future<ParkingAllocation> getAllocation(
    String allocationId, {
    String? societyId,
  }) {
    return _client.get(
      '$_admin/parking/allocations/$allocationId',
      societyId: societyId,
      decode: (data) =>
          ParkingAllocation.fromJson(requireMap(data, 'allocation')),
    );
  }

  Future<ParkingAllocation> releaseAllocation(
    String allocationId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/parking/allocations/$allocationId/release',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: (data) =>
          ParkingAllocation.fromJson(requireMap(data, 'allocation')),
    );
  }

  // ─── Guard gate logs ─────────────────────────────────────────────────────

  Future<VehicleLog> recordEntry({
    required String registrationNumber,
    String? vehicleType,
    String? vehicleId,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_guard/vehicles/entry',
      body: omitNulls({
        'registrationNumber': registrationNumber,
        'vehicleType': vehicleType,
        'vehicleId': vehicleId,
        'notes': notes,
      }),
      societyId: societyId,
      decode: VehicleLog.fromJson,
    );
  }

  Future<VehicleLog> recordExit({
    String? logId,
    String? registrationNumber,
    String? societyId,
  }) {
    return _client.post(
      '$_guard/vehicles/exit',
      body: omitNulls({
        'logId': logId,
        'registrationNumber': registrationNumber,
      }),
      societyId: societyId,
      decode: VehicleLog.fromJson,
    );
  }

  Future<Paged<VehicleLog>> logs({
    String? status,
    String? registrationNumber,
    String? vehicleId,
    String? from,
    String? to,
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_guard/vehicles/logs',
      query: omitNulls({
        'status': status,
        'registrationNumber': registrationNumber,
        'vehicleId': vehicleId,
        'from': from,
        'to': to,
        'page': page,
        'limit': limit,
      }),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, VehicleLog.fromJson),
    );
  }
}
