import '../../services/occupancy_access.dart';
import 'resident_models.dart';
import 'society_models.dart';

/// Backend-backed resident shell context.
///
/// All flats stay on [accessibleFlats]. The resident shell exposes a flat
/// selector when more than one flat is accessible.
/// Permissions come only from backend [FlatAccess] flags.
class ResidentHomeContext {
  const ResidentHomeContext({
    required this.profile,
    required this.accessibleFlats,
    required this.selectedFlat,
    required this.access,
  });

  final ResidentProfile profile;
  final List<ResidentFlat> accessibleFlats;
  final ResidentFlat selectedFlat;
  final OccupancyAccess access;

  FlatSummary get flat => selectedFlat.flat;
  FlatAccess get flatAccess => selectedFlat.access;

  String get flatNumber => flat.number;
  String get wingLabel {
    final name = flat.wingName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final code = flat.wingCode?.trim();
    if (code != null && code.isNotEmpty) return 'Wing $code';
    return 'Wing';
  }

  String get occupancyLabel {
    switch (flat.occupancyStatus.toUpperCase()) {
      case 'TENANT_OCCUPIED':
        return 'Tenant occupied';
      case 'VACANT':
        return 'Vacant';
      default:
        return 'Owner occupied';
    }
  }

  bool get hasMultipleFlats => accessibleFlats.length > 1;

  ResidentHomeContext copyWithSelected(ResidentFlat next) {
    final access = OccupancyAccess.fromBackend(
      financial: next.access.financial,
      residential: next.access.residential,
      backendRole: next.access.role,
      occupancyStatus: next.flat.occupancyStatus,
      displayName: profile.name,
    );
    return ResidentHomeContext(
      profile: profile,
      accessibleFlats: accessibleFlats,
      selectedFlat: next,
      access: access,
    );
  }

  /// Builds context from `/resident/profile` + `/resident/flats`.
  ///
  /// Prefer an OWNER flat when [preferOwner] is true, else a TENANT flat,
  /// otherwise the first accessible flat. Never discards extra flats.
  factory ResidentHomeContext.fromBackend({
    required ResidentProfile profile,
    required List<ResidentFlat> flats,
    bool preferOwner = true,
  }) {
    if (flats.isEmpty) {
      throw StateError(
        'No flat access is assigned to this account yet. Contact your society admin.',
      );
    }
    ResidentFlat? selected;
    if (preferOwner) {
      for (final item in flats) {
        if (item.access.role == 'OWNER') {
          selected = item;
          break;
        }
      }
    } else {
      for (final item in flats) {
        if (item.access.role == 'TENANT') {
          selected = item;
          break;
        }
      }
    }
    selected ??= flats.first;
    final access = OccupancyAccess.fromBackend(
      financial: selected.access.financial,
      residential: selected.access.residential,
      backendRole: selected.access.role,
      occupancyStatus: selected.flat.occupancyStatus,
      displayName: profile.name,
    );
    return ResidentHomeContext(
      profile: profile,
      accessibleFlats: List.unmodifiable(flats),
      selectedFlat: selected,
      access: access,
    );
  }
}

/// Formats backend occupancy status for admin lists.
String occupancyStatusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'TENANT_OCCUPIED':
      return 'Tenant occupied';
    case 'VACANT':
      return 'Vacant';
    case 'OWNER_OCCUPIED':
      return 'Owner occupied';
    default:
      return status;
  }
}

/// Formats backend flat type for display (`2BHK` → `2 BHK`).
String flatTypeLabel(String flatType) {
  switch (flatType.toUpperCase()) {
    case '2BHK':
      return '2 BHK';
    case '3BHK':
      return '3 BHK';
    default:
      return flatType;
  }
}
