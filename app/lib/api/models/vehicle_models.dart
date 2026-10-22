import '../http/json_read.dart';

/// Backend `VEHICLE_TYPES` / slot `parkingType`.
const kApiVehicleTypes = ['TWO_WHEELER', 'FOUR_WHEELER', 'OTHER'];

/// Admin resident registration only offers two- and four-wheelers.
const kAdminSelectableVehicleTypes = ['TWO_WHEELER', 'FOUR_WHEELER'];

const kAllocationStatuses = ['ACTIVE', 'ENDED'];
const kVehicleLogStatuses = ['INSIDE', 'EXITED'];

String vehicleTypeLabel(String type) {
  switch (type) {
    case 'TWO_WHEELER':
      return 'Two-wheeler';
    case 'FOUR_WHEELER':
      return 'Four-wheeler';
    case 'OTHER':
      return 'Other';
    default:
      return type;
  }
}

/// Client-side mirror of backend plate normalization (uppercase, strip spaces/hyphens).
String normalizeRegistrationNumber(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');
}

bool isValidIndianRegistrationNumber(String normalized) {
  if (normalized.length < 6 || normalized.length > 12) return false;
  final stateSeries = RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$');
  final bharatSeries = RegExp(r'^[0-9]{2}BH[0-9]{4}[A-Z]{1,2}$');
  return stateSeries.hasMatch(normalized) || bharatSeries.hasMatch(normalized);
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.registeredUserId,
    required this.vehicleType,
    required this.registrationNumber,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.make,
    this.model,
    this.colour,
    this.deactivatedAt,
    this.deactivationReason,
    this.activeAllocationId,
    this.parkingSlotId,
    this.residentName,
    this.flatNumber,
    this.wingCode,
    this.societyName,
    this.societyCode,
  });

  final String id;
  final String societyId;
  final String flatId;
  final String registeredUserId;
  final String vehicleType;
  final String registrationNumber;
  final String? make;
  final String? model;
  final String? colour;
  final bool isActive;
  final String? deactivatedAt;
  final String? deactivationReason;
  final String createdAt;
  final String updatedAt;
  final String? activeAllocationId;
  final String? parkingSlotId;
  final String? residentName;
  final String? flatNumber;
  final String? wingCode;
  final String? societyName;
  final String? societyCode;

  String get makeModelLabel {
    final parts = [
      if ((make ?? '').trim().isNotEmpty) make!.trim(),
      if ((model ?? '').trim().isNotEmpty) model!.trim(),
    ];
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  String get flatLabel {
    final number = (flatNumber ?? '').trim();
    final wing = (wingCode ?? '').trim();
    if (number.isEmpty) return flatId;
    if (wing.isEmpty) return number;
    final upperNumber = number.toUpperCase();
    final upperWing = wing.toUpperCase();
    if (upperNumber.startsWith('$upperWing-') ||
        upperNumber.startsWith(upperWing)) {
      return number;
    }
    return '$wing-$number';
  }

  factory Vehicle.fromJson(Object? data) {
    final json = requireMap(data, 'vehicle');
    return Vehicle(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      registeredUserId: requireString(json, 'registeredUserId'),
      vehicleType: requireString(json, 'vehicleType'),
      registrationNumber: requireString(json, 'registrationNumber'),
      make: optionalString(json, 'make'),
      model: optionalString(json, 'model'),
      colour: optionalString(json, 'colour'),
      isActive: requireBool(json, 'isActive'),
      deactivatedAt: optionalString(json, 'deactivatedAt'),
      deactivationReason: optionalString(json, 'deactivationReason'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
      activeAllocationId: optionalString(json, 'activeAllocationId'),
      parkingSlotId: optionalString(json, 'parkingSlotId'),
      residentName: optionalString(json, 'residentName'),
      flatNumber: optionalString(json, 'flatNumber'),
      wingCode: optionalString(json, 'wingCode'),
      societyName: optionalString(json, 'societyName'),
      societyCode: optionalString(json, 'societyCode'),
    );
  }
}

class VehicleList {
  const VehicleList({required this.items});
  final List<Vehicle> items;

  factory VehicleList.fromJson(Object? data) {
    final json = requireMap(data, 'vehicles');
    return VehicleList(
      items: requireMapList(json, 'items').map(Vehicle.fromJson).toList(),
    );
  }
}

class RegisterVehicleRequest {
  const RegisterVehicleRequest({
    required this.flatId,
    required this.vehicleType,
    required this.registrationNumber,
    this.make,
    this.model,
    this.colour,
  });

  final String flatId;
  final String vehicleType;
  final String registrationNumber;
  final String? make;
  final String? model;
  final String? colour;

  Map<String, Object?> toJson() => {
        'flatId': flatId,
        'vehicleType': vehicleType,
        'registrationNumber': registrationNumber,
        'make': make,
        'model': model,
        'colour': colour,
      };
}

class VehicleDraftPayload {
  const VehicleDraftPayload({
    required this.vehicleType,
    required this.registrationNumber,
    this.make,
    this.model,
    this.colour,
  });

  final String vehicleType;
  final String registrationNumber;
  final String? make;
  final String? model;
  final String? colour;

  Map<String, Object?> toJson() => omitNulls({
        'vehicleType': vehicleType,
        'registrationNumber': registrationNumber,
        'make': make,
        'model': model,
        'colour': colour,
      });
}

class AdminRegisterVehicleRequest {
  const AdminRegisterVehicleRequest({
    required this.flatId,
    required this.registeredUserId,
    required this.vehicleType,
    required this.registrationNumber,
    this.make,
    this.model,
    this.colour,
  });

  final String flatId;
  final String registeredUserId;
  final String vehicleType;
  final String registrationNumber;
  final String? make;
  final String? model;
  final String? colour;

  Map<String, Object?> toJson() => omitNulls({
        'flatId': flatId,
        'registeredUserId': registeredUserId,
        'vehicleType': vehicleType,
        'registrationNumber': registrationNumber,
        'make': make,
        'model': model,
        'colour': colour,
      });
}

class VehicleLog {
  const VehicleLog({
    required this.id,
    required this.societyId,
    required this.registrationNumber,
    required this.vehicleType,
    required this.status,
    required this.entryAt,
    required this.guardUserId,
    required this.isRegisteredResidentVehicle,
    required this.createdAt,
    required this.updatedAt,
    this.vehicleId,
    this.flatId,
    this.exitAt,
    this.checkedOutBy,
    this.notes,
  });

  final String id;
  final String societyId;
  final String? vehicleId;
  final String? flatId;
  final String registrationNumber;
  final String vehicleType;
  final String status;
  final String entryAt;
  final String? exitAt;
  final String guardUserId;
  final String? checkedOutBy;
  final String? notes;
  final bool isRegisteredResidentVehicle;
  final String createdAt;
  final String updatedAt;

  factory VehicleLog.fromJson(Object? data) {
    final json = requireMap(data, 'vehicle log');
    return VehicleLog(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      vehicleId: optionalString(json, 'vehicleId'),
      flatId: optionalString(json, 'flatId'),
      registrationNumber: requireString(json, 'registrationNumber'),
      vehicleType: requireString(json, 'vehicleType'),
      status: requireString(json, 'status'),
      entryAt: requireString(json, 'entryAt'),
      exitAt: optionalString(json, 'exitAt'),
      guardUserId: requireString(json, 'guardUserId'),
      checkedOutBy: optionalString(json, 'checkedOutBy'),
      notes: optionalString(json, 'notes'),
      isRegisteredResidentVehicle: requireBool(json, 'isRegisteredResidentVehicle'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class ParkingSlotBrief {
  const ParkingSlotBrief({
    required this.id,
    required this.slotNumber,
    required this.parkingType,
    this.locationDescription,
  });

  final String id;
  final String slotNumber;
  final String parkingType;
  final String? locationDescription;

  factory ParkingSlotBrief.fromJson(JsonMap json) {
    return ParkingSlotBrief(
      id: requireString(json, 'id'),
      slotNumber: requireString(json, 'slotNumber'),
      parkingType: requireString(json, 'parkingType'),
      locationDescription: optionalString(json, 'locationDescription'),
    );
  }
}

class ParkingVehicleBrief {
  const ParkingVehicleBrief({
    required this.id,
    required this.registrationNumber,
    required this.vehicleType,
  });

  final String id;
  final String registrationNumber;
  final String vehicleType;

  factory ParkingVehicleBrief.fromJson(JsonMap json) {
    return ParkingVehicleBrief(
      id: requireString(json, 'id'),
      registrationNumber: requireString(json, 'registrationNumber'),
      vehicleType: requireString(json, 'vehicleType'),
    );
  }
}

class ParkingAllocation {
  const ParkingAllocation({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.vehicleId,
    required this.parkingSlotId,
    required this.startsAt,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.endsAt,
    this.endedBy,
    this.endReason,
    this.slot,
    this.vehicle,
  });

  final String id;
  final String societyId;
  final String flatId;
  final String vehicleId;
  final String parkingSlotId;
  final String startsAt;
  final String? endsAt;
  final String status;
  final String createdBy;
  final String? endedBy;
  final String? endReason;
  final String createdAt;
  final String updatedAt;
  final ParkingSlotBrief? slot;
  final ParkingVehicleBrief? vehicle;

  factory ParkingAllocation.fromJson(JsonMap json) {
    final slot = json['slot'];
    final vehicle = json['vehicle'];
    return ParkingAllocation(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      vehicleId: requireString(json, 'vehicleId'),
      parkingSlotId: requireString(json, 'parkingSlotId'),
      startsAt: requireString(json, 'startsAt'),
      endsAt: optionalString(json, 'endsAt'),
      status: requireString(json, 'status'),
      createdBy: requireString(json, 'createdBy'),
      endedBy: optionalString(json, 'endedBy'),
      endReason: optionalString(json, 'endReason'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
      slot: slot == null ? null : ParkingSlotBrief.fromJson(requireMap(slot, 'slot')),
      vehicle: vehicle == null
          ? null
          : ParkingVehicleBrief.fromJson(requireMap(vehicle, 'vehicle')),
    );
  }
}

class ParkingList {
  const ParkingList({required this.items});
  final List<ParkingAllocation> items;

  factory ParkingList.fromJson(Object? data) {
    final json = requireMap(data, 'parking');
    return ParkingList(
      items: requireMapList(json, 'items').map(ParkingAllocation.fromJson).toList(),
    );
  }
}

/// Admin parking slot (serialized).
class ParkingSlot {
  const ParkingSlot({
    required this.id,
    required this.societyId,
    required this.slotNumber,
    required this.parkingType,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.locationDescription,
    this.deactivatedAt,
    this.deactivationReason,
    this.isOccupied,
    this.activeAllocationId,
  });

  final String id;
  final String societyId;
  final String slotNumber;
  final String parkingType;
  final String? locationDescription;
  final bool isActive;
  final String? deactivatedAt;
  final String? deactivationReason;
  final String createdAt;
  final String updatedAt;
  final bool? isOccupied;
  final String? activeAllocationId;

  factory ParkingSlot.fromJson(Object? data) {
    final json = requireMap(data, 'parking slot');
    return ParkingSlot(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      slotNumber: requireString(json, 'slotNumber'),
      parkingType: requireString(json, 'parkingType'),
      locationDescription: optionalString(json, 'locationDescription'),
      isActive: requireBool(json, 'isActive'),
      deactivatedAt: optionalString(json, 'deactivatedAt'),
      deactivationReason: optionalString(json, 'deactivationReason'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
      isOccupied: optionalBool(json, 'isOccupied'),
      activeAllocationId: optionalString(json, 'activeAllocationId'),
    );
  }
}

class ParkingSummary {
  const ParkingSummary({
    required this.totalActiveSlots,
    required this.occupiedSlots,
    required this.availableSlots,
    required this.byParkingType,
  });

  final int totalActiveSlots;
  final int occupiedSlots;
  final int availableSlots;
  final Map<String, int> byParkingType;

  factory ParkingSummary.fromJson(Object? data) {
    final json = requireMap(data, 'parking summary');
    final raw = json['byParkingType'];
    final byType = <String, int>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is num) {
          byType[e.key as String] = (e.value as num).toInt();
        }
      }
    }
    return ParkingSummary(
      totalActiveSlots: requireInt(json, 'totalActiveSlots'),
      occupiedSlots: requireInt(json, 'occupiedSlots'),
      availableSlots: requireInt(json, 'availableSlots'),
      byParkingType: byType,
    );
  }
}

class ListAdminVehiclesQuery {
  const ListAdminVehiclesQuery({
    this.flatId,
    this.registeredUserId,
    this.isActive,
    this.registrationNumber,
    this.page,
    this.limit,
  });

  final String? flatId;
  final String? registeredUserId;
  final bool? isActive;
  final String? registrationNumber;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'flatId': flatId,
        'registeredUserId': registeredUserId,
        'isActive': isActive == null ? null : (isActive! ? 'true' : 'false'),
        'registrationNumber': registrationNumber,
        'page': page,
        'limit': limit,
      };
}

class ListParkingSlotsQuery {
  const ListParkingSlotsQuery({
    this.parkingType,
    this.isActive,
    this.availability,
    this.page,
    this.limit,
  });

  final String? parkingType;
  final bool? isActive;
  /// `available` | `occupied` | `all`
  final String? availability;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'parkingType': parkingType,
        'isActive': isActive == null ? null : (isActive! ? 'true' : 'false'),
        'availability': availability,
        'page': page,
        'limit': limit,
      };
}

class ListAllocationsQuery {
  const ListAllocationsQuery({
    this.status,
    this.flatId,
    this.vehicleId,
    this.parkingSlotId,
    this.page,
    this.limit,
  });

  final String? status;
  final String? flatId;
  final String? vehicleId;
  final String? parkingSlotId;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'status': status,
        'flatId': flatId,
        'vehicleId': vehicleId,
        'parkingSlotId': parkingSlotId,
        'page': page,
        'limit': limit,
      };
}
