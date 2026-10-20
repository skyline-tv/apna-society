import '../models/auth_models.dart';

/// Dashboard role chosen from backend `/auth/me` roles.
///
/// The login dropdown is never used for this decision.
enum AppRole {
  admin,
  owner,
  tenant,
  guard,
}

extension AppRoleLabel on AppRole {
  String get label {
    switch (this) {
      case AppRole.admin:
        return 'Admin';
      case AppRole.owner:
        return 'Flat Owner';
      case AppRole.tenant:
        return 'Flat Tenant';
      case AppRole.guard:
        return 'Security Guard';
    }
  }

  String get sessionKey {
    switch (this) {
      case AppRole.admin:
        return 'admin';
      case AppRole.owner:
        return 'owner';
      case AppRole.tenant:
        return 'tenant';
      case AppRole.guard:
        return 'guard';
    }
  }
}

/// Resolves the home experience from backend roles.
///
/// Priority: ADMIN → resident OWNER/TENANT → GUARD.
/// A user who is both OWNER and TENANT is treated as OWNER for routing;
/// flat-level access still comes from `/resident/flats`.
AppRole resolveAppRole(AuthProfile profile) {
  final roles = profile.roles.map((r) => r.toUpperCase()).toSet();
  if (roles.contains('ADMIN')) return AppRole.admin;
  if (roles.contains('OWNER')) return AppRole.owner;
  if (roles.contains('TENANT')) return AppRole.tenant;
  if (roles.contains('GUARD')) return AppRole.guard;
  throw StateError('This account has no supported application role.');
}

AppRole? tryParseDropdownRole(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'admin':
      return AppRole.admin;
    case 'owner':
      return AppRole.owner;
    case 'tenant':
      return AppRole.tenant;
    case 'guard':
      return AppRole.guard;
    default:
      return null;
  }
}

bool isTerminalRefreshFailure(String code) {
  return code == 'REFRESH_EXPIRED' ||
      code == 'REFRESH_REUSE' ||
      code == 'INVALID_REFRESH' ||
      code == 'REFRESH_REQUIRED' ||
      code == 'LOGIN_DISABLED';
}
