import '../http/json_read.dart';
import 'society_models.dart';

class FlatAccess {
  const FlatAccess({
    required this.financial,
    required this.residential,
    required this.role,
  });

  final bool financial;
  final bool residential;
  final String role;

  factory FlatAccess.fromJson(JsonMap json) {
    return FlatAccess(
      financial: requireBool(json, 'financial'),
      residential: requireBool(json, 'residential'),
      role: requireString(json, 'role'),
    );
  }
}

/// `GET /api/v1/resident/profile`.
class ResidentProfile {
  const ResidentProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.roles,
    required this.societyIds,
    required this.activeFlatIds,
    this.phone,
    this.mobileE164,
  });

  final String id;
  final String email;
  final String name;
  final String? phone;
  final String? mobileE164;
  final List<String> roles;
  final List<String> societyIds;
  final List<String> activeFlatIds;

  /// Preferred display phone for UI (login mobile, then legacy phone).
  String get displayPhone {
    final mobile = mobileE164?.trim();
    if (mobile != null && mobile.isNotEmpty) {
      return mobile.startsWith('+') ? mobile : '+$mobile';
    }
    final legacy = phone?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return '—';
  }

  factory ResidentProfile.fromJson(Object? data) {
    final json = requireMap(data, 'resident profile');
    return ResidentProfile(
      id: requireString(json, 'id'),
      email: requireString(json, 'email'),
      name: requireString(json, 'name'),
      phone: optionalString(json, 'phone'),
      mobileE164: optionalString(json, 'mobileE164'),
      roles: requireStringList(json, 'roles'),
      societyIds: requireStringList(json, 'societyIds'),
      activeFlatIds: requireStringList(json, 'activeFlatIds'),
    );
  }
}

class ResidentFlat {
  const ResidentFlat({required this.flat, required this.access});

  final FlatSummary flat;
  final FlatAccess access;

  factory ResidentFlat.fromJson(Object? data) {
    final json = requireMap(data, 'resident flat');
    return ResidentFlat(
      flat: FlatSummary.fromJson(json),
      access: FlatAccess.fromJson(requireMap(json['access'], 'access')),
    );
  }
}

class OccupancyHistoryItem {
  const OccupancyHistoryItem({
    required this.id,
    required this.userId,
    required this.role,
    required this.status,
    required this.startsAt,
    this.endsAt,
    this.notes,
    this.endReason,
  });

  final String id;
  final String userId;
  final String role;
  final String status;
  final String startsAt;
  final String? endsAt;
  final String? notes;
  final String? endReason;

  factory OccupancyHistoryItem.fromJson(JsonMap json) {
    return OccupancyHistoryItem(
      id: requireString(json, 'id'),
      userId: requireString(json, 'userId'),
      role: requireString(json, 'role'),
      status: requireString(json, 'status'),
      startsAt: requireString(json, 'startsAt'),
      endsAt: optionalString(json, 'endsAt'),
      notes: optionalString(json, 'notes'),
      endReason: optionalString(json, 'endReason'),
    );
  }
}

class ResidentOccupancy {
  const ResidentOccupancy({
    required this.flatId,
    required this.occupancyStatus,
    required this.access,
    required this.items,
  });

  final String flatId;
  final String occupancyStatus;
  final FlatAccess access;
  final List<OccupancyHistoryItem> items;

  factory ResidentOccupancy.fromJson(Object? data) {
    final json = requireMap(data, 'occupancy');
    return ResidentOccupancy(
      flatId: requireString(json, 'flatId'),
      occupancyStatus: requireString(json, 'occupancyStatus'),
      access: FlatAccess.fromJson(requireMap(json['access'], 'access')),
      items: requireMapList(json, 'items').map(OccupancyHistoryItem.fromJson).toList(),
    );
  }
}
