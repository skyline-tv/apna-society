import '../http/json_read.dart';

/// `TokenPair` from login, verify-otp (legacy), and refresh.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
    this.mustChangePassword = false,
  });

  final String accessToken;
  final String refreshToken;
  final String expiresIn;
  final String tokenType;
  final bool mustChangePassword;

  factory TokenPair.fromJson(Object? data) {
    final json = requireMap(data, 'token pair');
    return TokenPair(
      accessToken: requireString(json, 'accessToken'),
      refreshToken: requireString(json, 'refreshToken'),
      expiresIn: requireString(json, 'expiresIn'),
      tokenType: requireString(json, 'tokenType'),
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }
}

/// `AuthProfile` from `GET /api/v1/auth/me`.
class AuthProfile {
  const AuthProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.roles,
    required this.societyIds,
    this.username,
    this.phone,
    this.mobileE164,
    this.mobileVerified = false,
    this.primarySocietyId,
    this.lastLoginAt,
    this.mustChangePassword = false,
  });

  final String id;
  final String email;
  final String? username;
  final String name;
  final String? phone;
  final String? mobileE164;
  final bool mobileVerified;
  final List<String> roles;
  final List<String> societyIds;
  final String? primarySocietyId;
  final String? lastLoginAt;
  final bool mustChangePassword;

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

  factory AuthProfile.fromJson(Object? data) {
    final json = requireMap(data, 'profile');
    return AuthProfile(
      id: requireString(json, 'id'),
      email: requireString(json, 'email'),
      username: optionalString(json, 'username'),
      name: requireString(json, 'name'),
      phone: optionalString(json, 'phone'),
      mobileE164: optionalString(json, 'mobileE164'),
      mobileVerified: json['mobileVerified'] == true,
      roles: requireStringList(json, 'roles'),
      societyIds: requireStringList(json, 'societyIds'),
      primarySocietyId: optionalString(json, 'primarySocietyId'),
      lastLoginAt: optionalString(json, 'lastLoginAt'),
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }
}

class LogoutResult {
  const LogoutResult({required this.message});
  final String message;

  factory LogoutResult.fromJson(Object? data) {
    final json = requireMap(data, 'logout');
    return LogoutResult(message: requireString(json, 'message'));
  }
}

class LogoutAllResult {
  const LogoutAllResult({required this.revoked});
  final int revoked;

  factory LogoutAllResult.fromJson(Object? data) {
    final json = requireMap(data, 'logout-all');
    return LogoutAllResult(revoked: requireInt(json, 'revoked'));
  }
}

class ChangePasswordResult {
  const ChangePasswordResult({required this.mustChangePassword});
  final bool mustChangePassword;

  factory ChangePasswordResult.fromJson(Object? data) {
    final json = requireMap(data, 'change-password');
    return ChangePasswordResult(
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }
}
