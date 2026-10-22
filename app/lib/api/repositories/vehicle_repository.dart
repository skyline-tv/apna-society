import '../models/common.dart';
import '../models/vehicle_models.dart';
import '../services/vehicle_api.dart';

/// Cached vehicle / parking reads and guarded mutations.
class VehicleRepository {
  VehicleRepository(this._api);

  final VehicleApi _api;

  VehicleList? lastResidentVehicles;
  ParkingList? lastResidentParking;
  Paged<Vehicle>? lastAdminVehicles;
  String? lastAdminVehiclesKey;
  Paged<ParkingSlot>? lastSlots;
  String? lastSlotsKey;
  ParkingSummary? lastSummary;
  Paged<ParkingAllocation>? lastAllocations;
  String? lastAllocationsKey;
  Paged<VehicleLog>? lastLogs;
  String? lastLogsKey;
  final Map<String, Vehicle> _vehicles = {};
  final Map<String, ParkingSlot> _slots = {};
  final Map<String, ParkingAllocation> _allocations = {};

  bool mutationLocked = false;

  void clear() {
    lastResidentVehicles = null;
    lastResidentParking = null;
    lastAdminVehicles = null;
    lastAdminVehiclesKey = null;
    lastSlots = null;
    lastSlotsKey = null;
    lastSummary = null;
    lastAllocations = null;
    lastAllocationsKey = null;
    lastLogs = null;
    lastLogsKey = null;
    _vehicles.clear();
    _slots.clear();
    _allocations.clear();
    mutationLocked = false;
  }

  void invalidateCaches({String? vehicleId, String? slotId}) {
    lastResidentVehicles = null;
    lastResidentParking = null;
    lastAdminVehicles = null;
    lastAdminVehiclesKey = null;
    lastSlots = null;
    lastSlotsKey = null;
    lastSummary = null;
    lastAllocations = null;
    lastAllocationsKey = null;
    lastLogs = null;
    lastLogsKey = null;
    if (vehicleId != null) {
      _vehicles.remove(vehicleId);
    } else {
      _vehicles.clear();
    }
    if (slotId != null) {
      _slots.remove(slotId);
    } else {
      _slots.clear();
    }
    _allocations.clear();
  }

  Future<T> _locked<T>(Future<T> Function() run) async {
    if (mutationLocked) {
      throw StateError('A vehicle or parking action is already in progress.');
    }
    mutationLocked = true;
    try {
      return await run();
    } finally {
      mutationLocked = false;
    }
  }

  // ─── Resident ────────────────────────────────────────────────────────────

  Future<VehicleList> listResident({bool force = false}) async {
    if (!force && lastResidentVehicles != null) return lastResidentVehicles!;
    final list = await _api.list();
    lastResidentVehicles = list;
    for (final v in list.items) {
      _vehicles[v.id] = v;
    }
    return list;
  }

  Future<Vehicle> getResident(String vehicleId, {bool force = false}) async {
    if (!force && _vehicles.containsKey(vehicleId)) return _vehicles[vehicleId]!;
    final v = await _api.get(vehicleId);
    _vehicles[v.id] = v;
    return v;
  }

  Future<Vehicle> register(RegisterVehicleRequest request) {
    return _locked(() async {
      final v = await _api.register(request);
      invalidateCaches(vehicleId: v.id);
      _vehicles[v.id] = v;
      return v;
    });
  }

  Future<Vehicle> update(
    String vehicleId, {
    String? make,
    String? model,
    String? colour,
    String? vehicleType,
  }) {
    return _locked(() async {
      final v = await _api.update(
        vehicleId,
        make: make,
        model: model,
        colour: colour,
        vehicleType: vehicleType,
      );
      invalidateCaches(vehicleId: vehicleId);
      _vehicles[v.id] = v;
      return v;
    });
  }

  Future<Vehicle> deactivate(String vehicleId, {String? reason}) {
    return _locked(() async {
      final v = await _api.deactivate(vehicleId, reason: reason);
      invalidateCaches(vehicleId: vehicleId);
      _vehicles[v.id] = v;
      return v;
    });
  }

  Future<ParkingList> residentParking({bool force = false}) async {
    if (!force && lastResidentParking != null) return lastResidentParking!;
    final list = await _api.parking();
    lastResidentParking = list;
    for (final a in list.items) {
      _allocations[a.id] = a;
    }
    return list;
  }

  Future<ParkingAllocation> residentAllocation(
    String allocationId, {
    bool force = false,
  }) async {
    if (!force && _allocations.containsKey(allocationId)) {
      return _allocations[allocationId]!;
    }
    final a = await _api.parkingAllocation(allocationId);
    _allocations[a.id] = a;
    return a;
  }

  // ─── Admin ───────────────────────────────────────────────────────────────

  Future<Paged<Vehicle>> listAdminVehicles({
    ListAdminVehiclesQuery query = const ListAdminVehiclesQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastAdminVehicles != null && lastAdminVehiclesKey == key) {
      return lastAdminVehicles!;
    }
    final page = await _api.listAdminVehicles(query: query);
    lastAdminVehicles = page;
    lastAdminVehiclesKey = key;
    for (final v in page.items) {
      _vehicles[v.id] = v;
    }
    return page;
  }

  Future<Vehicle> adminRegister(AdminRegisterVehicleRequest request) {
    return _locked(() async {
      final v = await _api.adminRegister(request);
      invalidateCaches(vehicleId: v.id);
      _vehicles[v.id] = v;
      return v;
    });
  }

  Future<Vehicle> adminUpdate(
    String vehicleId, {
    String? make,
    String? model,
    String? colour,
    String? vehicleType,
    String? registrationNumber,
  }) {
    return _locked(() async {
      final v = await _api.adminUpdate(
        vehicleId,
        make: make,
        model: model,
        colour: colour,
        vehicleType: vehicleType,
        registrationNumber: registrationNumber,
      );
      invalidateCaches(vehicleId: vehicleId);
      _vehicles[v.id] = v;
      return v;
    });
  }

  Future<Vehicle> adminDeactivate(String vehicleId, {String? reason}) {
    return _locked(() async {
      final v = await _api.adminDeactivate(vehicleId, reason: reason);
      invalidateCaches(vehicleId: vehicleId);
      _vehicles[v.id] = v;
      return v;
    });
  }

  Future<ParkingSummary> parkingSummary({bool force = false}) async {
    if (!force && lastSummary != null) return lastSummary!;
    final s = await _api.parkingSummary();
    lastSummary = s;
    return s;
  }

  Future<Paged<ParkingSlot>> listSlots({
    ListParkingSlotsQuery query = const ListParkingSlotsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastSlots != null && lastSlotsKey == key) {
      return lastSlots!;
    }
    final page = await _api.listParkingSlots(query: query);
    lastSlots = page;
    lastSlotsKey = key;
    for (final s in page.items) {
      _slots[s.id] = s;
    }
    return page;
  }

  Future<ParkingSlot> getSlot(String slotId, {bool force = false}) async {
    if (!force && _slots.containsKey(slotId)) return _slots[slotId]!;
    final s = await _api.getParkingSlot(slotId);
    _slots[s.id] = s;
    return s;
  }

  Future<ParkingSlot> createSlot({
    required String slotNumber,
    required String parkingType,
    String? locationDescription,
  }) {
    return _locked(() async {
      final s = await _api.createParkingSlot(
        slotNumber: slotNumber,
        parkingType: parkingType,
        locationDescription: locationDescription,
      );
      invalidateCaches(slotId: s.id);
      _slots[s.id] = s;
      return s;
    });
  }

  Future<ParkingSlot> updateSlot(
    String slotId, {
    String? locationDescription,
    String? parkingType,
  }) {
    return _locked(() async {
      final s = await _api.updateParkingSlot(
        slotId,
        locationDescription: locationDescription,
        parkingType: parkingType,
      );
      invalidateCaches(slotId: slotId);
      _slots[s.id] = s;
      return s;
    });
  }

  Future<ParkingSlot> setSlotActive(
    String slotId, {
    required bool isActive,
    String? reason,
  }) {
    return _locked(() async {
      final s = await _api.setParkingSlotActive(
        slotId,
        isActive: isActive,
        reason: reason,
      );
      invalidateCaches(slotId: slotId);
      _slots[s.id] = s;
      return s;
    });
  }

  Future<ParkingAllocation> allocate({
    required String flatId,
    required String vehicleId,
    required String parkingSlotId,
    String? startsAt,
  }) {
    return _locked(() async {
      final a = await _api.allocateParking(
        flatId: flatId,
        vehicleId: vehicleId,
        parkingSlotId: parkingSlotId,
        startsAt: startsAt,
      );
      invalidateCaches(vehicleId: vehicleId, slotId: parkingSlotId);
      _allocations[a.id] = a;
      return a;
    });
  }

  Future<Paged<ParkingAllocation>> listAllocations({
    ListAllocationsQuery query = const ListAllocationsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastAllocations != null && lastAllocationsKey == key) {
      return lastAllocations!;
    }
    final page = await _api.listAllocations(query: query);
    lastAllocations = page;
    lastAllocationsKey = key;
    for (final a in page.items) {
      _allocations[a.id] = a;
    }
    return page;
  }

  Future<ParkingAllocation> getAllocation(
    String allocationId, {
    bool force = false,
  }) async {
    if (!force && _allocations.containsKey(allocationId)) {
      return _allocations[allocationId]!;
    }
    final a = await _api.getAllocation(allocationId);
    _allocations[a.id] = a;
    return a;
  }

  Future<ParkingAllocation> release(String allocationId, {String? reason}) {
    return _locked(() async {
      final a = await _api.releaseAllocation(allocationId, reason: reason);
      invalidateCaches();
      _allocations[a.id] = a;
      return a;
    });
  }

  // ─── Guard ───────────────────────────────────────────────────────────────

  Future<VehicleLog> recordEntry({
    required String registrationNumber,
    String? vehicleType,
    String? vehicleId,
    String? notes,
  }) {
    return _locked(() async {
      final log = await _api.recordEntry(
        registrationNumber: registrationNumber,
        vehicleType: vehicleType,
        vehicleId: vehicleId,
        notes: notes,
      );
      lastLogs = null;
      lastLogsKey = null;
      return log;
    });
  }

  Future<VehicleLog> recordExit({
    String? logId,
    String? registrationNumber,
  }) {
    return _locked(() async {
      final log = await _api.recordExit(
        logId: logId,
        registrationNumber: registrationNumber,
      );
      lastLogs = null;
      lastLogsKey = null;
      return log;
    });
  }

  Future<Paged<VehicleLog>> listLogs({
    String? status,
    String? registrationNumber,
    int? page,
    int? limit,
    bool force = false,
  }) async {
    final key = '$status|$registrationNumber|$page|$limit';
    if (!force && lastLogs != null && lastLogsKey == key) return lastLogs!;
    final result = await _api.logs(
      status: status,
      registrationNumber: registrationNumber,
      page: page,
      limit: limit,
    );
    lastLogs = result;
    lastLogsKey = key;
    return result;
  }
}
