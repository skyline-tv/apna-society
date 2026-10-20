import 'package:drift/drift.dart' show QueryRow;

import 'session_store.dart';

/// Flat occupancy modes (stored on `flats.occupancy_type`).
const kOccupancyOwnerOccupied = 'owner_occupied';
const kOccupancyTenantOccupied = 'tenant_occupied';

/// Resolved access for a logged-in resident against a flat's occupancy.
class OccupancyAccess {
  const OccupancyAccess({
    required this.sessionRole,
    required this.occupancyType,
    required this.canFinance,
    required this.canResidential,
    required this.displayName,
  });

  /// [SessionStore.roleOwner] or [SessionStore.roleTenant].
  final String sessionRole;
  final String occupancyType;
  final bool canFinance;
  final bool canResidential;
  final String displayName;

  bool get isOwnerSession => sessionRole == SessionStore.roleOwner;
  bool get isTenantSession => sessionRole == SessionStore.roleTenant;
  bool get isTenantOccupied => occupancyType == kOccupancyTenantOccupied;
  bool get isOwnerOccupied => occupancyType == kOccupancyOwnerOccupied;

  /// Notification recipient role for visitor / security alerts for this session.
  String get notificationRole =>
      isTenantSession ? SessionStore.roleTenant : SessionStore.roleOwner;

  static String occupancyOf(QueryRow flat) {
    final raw = (flat.data['occupancy_type'] as String?)?.trim();
    if (raw == kOccupancyTenantOccupied) return kOccupancyTenantOccupied;
    return kOccupancyOwnerOccupied;
  }

  static bool tenantActive(QueryRow flat) =>
      (flat.data['tenant_is_active'] as int? ?? 0) == 1;

  static String ownerNameOf(QueryRow flat) => flat.read<String>('owner_name');

  static String tenantNameOf(QueryRow flat) =>
      (flat.data['tenant_name'] as String?)?.trim() ?? '';

  static String tenantMobileOf(QueryRow flat) =>
      (flat.data['tenant_mobile'] as String?)?.trim() ?? '';

  /// Access flags from backend `/resident/flats` (financial / residential / role).
  ///
  /// The login dropdown is not consulted. [access.role] must be OWNER or TENANT.
  static OccupancyAccess fromBackend({
    required bool financial,
    required bool residential,
    required String backendRole,
    required String occupancyStatus,
    required String displayName,
  }) {
    final role = backendRole.toUpperCase();
    if (role != 'OWNER' && role != 'TENANT') {
      throw StateError('Unsupported resident role from backend.');
    }
    final occupancy = occupancyStatus.toUpperCase() == 'TENANT_OCCUPIED'
        ? kOccupancyTenantOccupied
        : kOccupancyOwnerOccupied;
    return OccupancyAccess(
      sessionRole:
          role == 'TENANT' ? SessionStore.roleTenant : SessionStore.roleOwner,
      occupancyType: occupancy,
      canFinance: financial,
      canResidential: residential,
      displayName: displayName.trim().isEmpty
          ? (role == 'TENANT' ? 'Tenant' : 'Owner')
          : displayName.trim(),
    );
  }

  /// Build access for an authenticated resident session against [flat].
  /// Throws [StateError] when the session is not allowed for this flat.
  static OccupancyAccess forSession({
    required QueryRow flat,
    required String sessionRole,
    required String sessionMobile,
  }) {
    final occupancy = occupancyOf(flat);
    final ownerMobile = flat.read<String>('mobile').trim();
    final tenantMobile = tenantMobileOf(flat);
    final mobile = sessionMobile.trim();

    if (sessionRole == SessionStore.roleOwner) {
      if (ownerMobile.isEmpty || ownerMobile != mobile) {
        throw StateError(
            'This owner session does not match the flat owner mobile.');
      }
      const finance = true;
      // Owner gets residential only when the flat is owner-occupied.
      final residential = occupancy == kOccupancyOwnerOccupied;
      return OccupancyAccess(
        sessionRole: SessionStore.roleOwner,
        occupancyType: occupancy,
        canFinance: finance,
        canResidential: residential,
        displayName: ownerNameOf(flat).trim().isEmpty
            ? 'Owner'
            : ownerNameOf(flat).trim(),
      );
    }

    if (sessionRole == SessionStore.roleTenant) {
      if (occupancy != kOccupancyTenantOccupied) {
        throw StateError(
            'Tenant login is only allowed for tenant-occupied flats.');
      }
      if (!tenantActive(flat)) {
        throw StateError('This tenant account is inactive for the flat.');
      }
      if (tenantMobile.isEmpty || tenantMobile != mobile) {
        throw StateError(
            'This tenant session does not match the active tenant mobile.');
      }
      return OccupancyAccess(
        sessionRole: SessionStore.roleTenant,
        occupancyType: occupancy,
        canFinance: false,
        canResidential: true,
        displayName: tenantNameOf(flat).isEmpty ? 'Tenant' : tenantNameOf(flat),
      );
    }

    throw StateError('Unsupported resident role.');
  }

  void assertFinance() {
    if (!canFinance) {
      throw StateError(
          'Financial access is not available for this account on this flat.');
    }
  }

  void assertResidential() {
    if (!canResidential) {
      throw StateError(
          'Residential access is not available for this account on this flat.');
    }
  }
}

/// Who should receive visitor / security notifications for a flat.
class ResidentialRecipient {
  const ResidentialRecipient({
    required this.role,
    required this.name,
    required this.fallbackUsed,
  });

  final String role; // owner | tenant
  final String name;
  final bool fallbackUsed;
}

ResidentialRecipient residentialRecipientForFlat(QueryRow flat) {
  final occupancy = OccupancyAccess.occupancyOf(flat);
  if (occupancy == kOccupancyTenantOccupied &&
      OccupancyAccess.tenantActive(flat) &&
      OccupancyAccess.tenantMobileOf(flat).isNotEmpty) {
    final name = OccupancyAccess.tenantNameOf(flat);
    return ResidentialRecipient(
      role: SessionStore.roleTenant,
      name: name.isEmpty ? 'Tenant' : name,
      fallbackUsed: false,
    );
  }
  final owner = OccupancyAccess.ownerNameOf(flat).trim();
  return ResidentialRecipient(
    role: SessionStore.roleOwner,
    name: owner.isEmpty ? 'Owner' : owner,
    fallbackUsed: occupancy == kOccupancyTenantOccupied,
  );
}
