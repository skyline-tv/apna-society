import '../http/json_read.dart';

/// `POST /api/v1/auth/request-otp` data.
class OtpRequestResult {
  const OtpRequestResult({required this.message});
  final String message;

  factory OtpRequestResult.fromJson(Object? data) {
    final json = requireMap(data, 'otp request');
    return OtpRequestResult(message: requireString(json, 'message'));
  }
}

/// `TokenPair` from verify-otp and refresh.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
  });

  final String accessToken;
  final String refreshToken;
  final String expiresIn;
  final String tokenType;

  factory TokenPair.fromJson(Object? data) {
    final json = requireMap(data, 'token pair');
    return TokenPair(
      accessToken: requireString(json, 'accessToken'),
      refreshToken: requireString(json, 'refreshToken'),
      expiresIn: requireString(json, 'expiresIn'),
      tokenType: requireString(json, 'tokenType'),
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
    this.phone,
    this.primarySocietyId,
    this.lastLoginAt,
  });

  final String id;
  final String email;
  final String name;
  final String? phone;
  final List<String> roles;
  final List<String> societyIds;
  final String? primarySocietyId;
  final String? lastLoginAt;

  factory AuthProfile.fromJson(Object? data) {
    final json = requireMap(data, 'profile');
    return AuthProfile(
      id: requireString(json, 'id'),
      email: requireString(json, 'email'),
      name: requireString(json, 'name'),
      phone: optionalString(json, 'phone'),
      roles: requireStringList(json, 'roles'),
      societyIds: requireStringList(json, 'societyIds'),
      primarySocietyId: optionalString(json, 'primarySocietyId'),
      lastLoginAt: optionalString(json, 'lastLoginAt'),
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
