import '../http/api_exception.dart';
import '../http/json_read.dart';

class ResidentSummary {
  const ResidentSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.mobileE164,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? mobileE164;
  final String role;

  /// Prefer login mobile, then display phone, then email as last resort.
  String get displayContact {
    final mobile = mobileE164?.trim();
    if (mobile != null && mobile.isNotEmpty) {
      return mobile.startsWith('+') ? mobile : '+$mobile';
    }
    final legacy = phone?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return email;
  }

  factory ResidentSummary.fromJson(JsonMap json) {
    return ResidentSummary(
      id: requireString(json, 'id'),
      name: requireString(json, 'name'),
      email: requireString(json, 'email'),
      phone: optionalString(json, 'phone'),
      mobileE164: optionalString(json, 'mobileE164'),
      role: requireString(json, 'role'),
    );
  }
}

class SocietySummary {
  const SocietySummary({
    required this.id,
    required this.name,
    required this.code,
    required this.timezone,
    required this.currency,
    required this.maintenanceDayOfMonth,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.contactEmail,
    this.contactPhone,
  });

  final String id;
  final String name;
  final String code;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? contactEmail;
  final String? contactPhone;
  final String timezone;
  final String currency;
  final int maintenanceDayOfMonth;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  factory SocietySummary.fromJson(Object? data) {
    final json = requireMap(data, 'society');
    return SocietySummary(
      id: requireString(json, 'id'),
      name: requireString(json, 'name'),
      code: requireString(json, 'code'),
      address: optionalString(json, 'address'),
      city: optionalString(json, 'city'),
      state: optionalString(json, 'state'),
      pincode: optionalString(json, 'pincode'),
      contactEmail: optionalString(json, 'contactEmail'),
      contactPhone: optionalString(json, 'contactPhone'),
      timezone: requireString(json, 'timezone'),
      currency: requireString(json, 'currency'),
      maintenanceDayOfMonth: requireInt(json, 'maintenanceDayOfMonth'),
      isActive: requireBool(json, 'isActive'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class WingSummary {
  const WingSummary({
    required this.id,
    required this.societyId,
    required this.name,
    required this.code,
    required this.floors,
    required this.flatsPerFloor,
    required this.sortOrder,
    required this.isActive,
    required this.flatCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String societyId;
  final String name;
  final String code;
  final int floors;
  final int flatsPerFloor;
  final int sortOrder;
  final bool isActive;
  final int flatCount;
  final String createdAt;
  final String updatedAt;

  factory WingSummary.fromJson(JsonMap json) {
    return WingSummary(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      name: requireString(json, 'name'),
      code: requireString(json, 'code'),
      floors: requireInt(json, 'floors'),
      flatsPerFloor: requireInt(json, 'flatsPerFloor'),
      sortOrder: requireInt(json, 'sortOrder'),
      isActive: requireBool(json, 'isActive'),
      flatCount: requireInt(json, 'flatCount'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class FlatParking {
  const FlatParking({required this.hasParking, this.slotLabel});
  final bool hasParking;
  final String? slotLabel;

  factory FlatParking.fromJson(JsonMap json) {
    return FlatParking(
      hasParking: requireBool(json, 'hasParking'),
      slotLabel: optionalString(json, 'slotLabel'),
    );
  }
}

class FlatSummary {
  const FlatSummary({
    required this.id,
    required this.societyId,
    required this.wingId,
    required this.number,
    required this.floor,
    required this.position,
    required this.flatType,
    required this.maintenanceRate,
    required this.isActive,
    required this.occupancyStatus,
    required this.createdAt,
    required this.updatedAt,
    this.wingCode,
    this.wingName,
    this.parking,
    this.notes,
    this.activeOwner,
    this.activeTenant,
  });

  final String id;
  final String societyId;
  final String wingId;
  final String? wingCode;
  final String? wingName;
  final String number;
  final int floor;
  final int position;
  final String flatType;
  final int maintenanceRate;
  final bool isActive;
  final String occupancyStatus;
  final FlatParking? parking;
  final String? notes;
  final ResidentSummary? activeOwner;
  final ResidentSummary? activeTenant;
  final String createdAt;
  final String updatedAt;

  factory FlatSummary.fromJson(Object? data) {
    final json = requireMap(data, 'flat');
    final parking = json['parking'];
    final owner = json['activeOwner'];
    final tenant = json['activeTenant'];
    return FlatSummary(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      wingId: requireString(json, 'wingId'),
      wingCode: optionalString(json, 'wingCode'),
      wingName: optionalString(json, 'wingName'),
      number: requireString(json, 'number'),
      floor: requireInt(json, 'floor'),
      position: requireInt(json, 'position'),
      flatType: requireString(json, 'flatType'),
      maintenanceRate: requireInt(json, 'maintenanceRate'),
      isActive: requireBool(json, 'isActive'),
      occupancyStatus: requireString(json, 'occupancyStatus'),
      parking: parking == null ? null : FlatParking.fromJson(requireMap(parking, 'parking')),
      notes: optionalString(json, 'notes'),
      activeOwner: owner == null ? null : ResidentSummary.fromJson(requireMap(owner, 'activeOwner')),
      activeTenant: tenant == null ? null : ResidentSummary.fromJson(requireMap(tenant, 'activeTenant')),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class SocietyTotals {
  const SocietyTotals({
    required this.wings,
    required this.flats,
    required this.activeFlats,
    required this.inactiveFlats,
    required this.monthlyMaintenanceTotal,
    required this.rate4000Count,
    required this.rate5000Count,
  });

  final int wings;
  final int flats;
  final int activeFlats;
  final int inactiveFlats;
  final int monthlyMaintenanceTotal;
  final int rate4000Count;
  final int rate5000Count;

  factory SocietyTotals.fromJson(JsonMap json) {
    return SocietyTotals(
      wings: requireInt(json, 'wings'),
      flats: requireInt(json, 'flats'),
      activeFlats: requireInt(json, 'activeFlats'),
      inactiveFlats: requireInt(json, 'inactiveFlats'),
      monthlyMaintenanceTotal: requireInt(json, 'monthlyMaintenanceTotal'),
      rate4000Count: requireInt(json, 'rate4000Count'),
      rate5000Count: requireInt(json, 'rate5000Count'),
    );
  }
}

class SocietyConfiguration {
  const SocietyConfiguration({
    required this.society,
    required this.totals,
    required this.wings,
  });

  final SocietySummary society;
  final SocietyTotals totals;
  final List<WingSummary> wings;

  factory SocietyConfiguration.fromJson(Object? data) {
    final json = requireMap(data, 'configuration');
    return SocietyConfiguration(
      society: SocietySummary.fromJson(json['society']),
      totals: SocietyTotals.fromJson(requireMap(json['totals'], 'totals')),
      wings: requireMapList(json, 'wings').map(WingSummary.fromJson).toList(),
    );
  }
}

class DashboardWingStats {
  const DashboardWingStats({
    required this.id,
    required this.code,
    required this.name,
    required this.flatCount,
    required this.activeFlats,
    required this.inactiveFlats,
    required this.ownerOccupiedFlats,
    required this.tenantOccupiedFlats,
    required this.vacantFlats,
    required this.twoBhkCount,
    required this.threeBhkCount,
    required this.monthlyMaintenanceTotal,
  });

  final String id;
  final String code;
  final String name;
  final int flatCount;
  final int activeFlats;
  final int inactiveFlats;
  final int ownerOccupiedFlats;
  final int tenantOccupiedFlats;
  final int vacantFlats;
  final int twoBhkCount;
  final int threeBhkCount;
  final int monthlyMaintenanceTotal;

  factory DashboardWingStats.fromJson(JsonMap json) {
    return DashboardWingStats(
      id: requireString(json, 'id'),
      code: requireString(json, 'code'),
      name: requireString(json, 'name'),
      flatCount: requireInt(json, 'flatCount'),
      activeFlats: requireInt(json, 'activeFlats'),
      inactiveFlats: requireInt(json, 'inactiveFlats'),
      ownerOccupiedFlats: requireInt(json, 'ownerOccupiedFlats'),
      tenantOccupiedFlats: requireInt(json, 'tenantOccupiedFlats'),
      vacantFlats: requireInt(json, 'vacantFlats'),
      twoBhkCount: requireInt(json, 'twoBhkCount'),
      threeBhkCount: requireInt(json, 'threeBhkCount'),
      monthlyMaintenanceTotal: requireInt(json, 'monthlyMaintenanceTotal'),
    );
  }
}

class DashboardTotals {
  const DashboardTotals({
    required this.wings,
    required this.flats,
    required this.activeFlats,
    required this.inactiveFlats,
    required this.ownerOccupiedFlats,
    required this.tenantOccupiedFlats,
    required this.vacantFlats,
    required this.twoBhkCount,
    required this.threeBhkCount,
    required this.monthlyMaintenanceTotal,
  });

  final int wings;
  final int flats;
  final int activeFlats;
  final int inactiveFlats;
  final int ownerOccupiedFlats;
  final int tenantOccupiedFlats;
  final int vacantFlats;
  final int twoBhkCount;
  final int threeBhkCount;
  final int monthlyMaintenanceTotal;

  factory DashboardTotals.fromJson(JsonMap json) {
    return DashboardTotals(
      wings: requireInt(json, 'wings'),
      flats: requireInt(json, 'flats'),
      activeFlats: requireInt(json, 'activeFlats'),
      inactiveFlats: requireInt(json, 'inactiveFlats'),
      ownerOccupiedFlats: requireInt(json, 'ownerOccupiedFlats'),
      tenantOccupiedFlats: requireInt(json, 'tenantOccupiedFlats'),
      vacantFlats: requireInt(json, 'vacantFlats'),
      twoBhkCount: requireInt(json, 'twoBhkCount'),
      threeBhkCount: requireInt(json, 'threeBhkCount'),
      monthlyMaintenanceTotal: requireInt(json, 'monthlyMaintenanceTotal'),
    );
  }
}

class DashboardStats {
  const DashboardStats({required this.totals, required this.wings});

  final DashboardTotals totals;
  final List<DashboardWingStats> wings;

  factory DashboardStats.fromJson(Object? data) {
    final json = requireMap(data, 'dashboard');
    return DashboardStats(
      totals: DashboardTotals.fromJson(requireMap(json['totals'], 'totals')),
      wings: requireMapList(json, 'wings').map(DashboardWingStats.fromJson).toList(),
    );
  }
}

/// Minimal flat row from `GET /api/v1/societies/:societyId/flats` (lean docs).
/// Used by GUARD visitor registration when `/admin/flats` is not authorized.
class SocietyFlatPick {
  const SocietyFlatPick({
    required this.id,
    required this.wingId,
    required this.number,
    required this.occupancyStatus,
    this.wingCode,
  });

  final String id;
  final String wingId;
  final String number;
  final String occupancyStatus;
  final String? wingCode;

  String get label {
    final wing = wingCode ?? '?';
    final vacant = occupancyStatus == 'VACANT' ? ' (vacant)' : '';
    return '$wing-$number$vacant';
  }

  factory SocietyFlatPick.fromLeanJson(
    Object? data, {
    Map<String, String> wingCodesById = const {},
  }) {
    final json = requireMap(data, 'flat');
    final id = optionalString(json, 'id') ??
        optionalString(json, '_id') ??
        (json['_id']?.toString() ?? '');
    if (id.isEmpty) {
      throw ApiParseException('Flat lean document missing id');
    }
    final wingRaw = json['wingId'];
    final wingId = wingRaw is String
        ? wingRaw
        : (wingRaw?.toString() ?? '');
    return SocietyFlatPick(
      id: id,
      wingId: wingId,
      number: requireString(json, 'number'),
      occupancyStatus: optionalString(json, 'occupancyStatus') ?? 'VACANT',
      wingCode: wingCodesById[wingId],
    );
  }
}

class ListFlatsQuery {
  const ListFlatsQuery({
    this.wingId,
    this.floor,
    this.flatType,
    this.occupancyStatus,
    this.isActive,
    this.search,
    this.page,
    this.limit,
    this.sortBy,
    this.sortOrder,
  });

  final String? wingId;
  final int? floor;
  final String? flatType;
  final String? occupancyStatus;
  final bool? isActive;
  final String? search;
  final int? page;
  final int? limit;
  final String? sortBy;
  final String? sortOrder;

  Map<String, Object?> toQuery() => {
        'wingId': wingId,
        'floor': floor,
        'flatType': flatType,
        'occupancyStatus': occupancyStatus,
        'isActive': isActive == null ? null : (isActive! ? 'true' : 'false'),
        'search': search,
        'page': page,
        'limit': limit,
        'sortBy': sortBy,
        'sortOrder': sortOrder,
      };
}
