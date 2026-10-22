import '../http/json_read.dart';

/// Serialized admin guard from `GET/POST /api/v1/admin/guards`.
class AdminGuard {
  const AdminGuard({
    required this.id,
    required this.email,
    required this.name,
    required this.roles,
    required this.isActive,
    required this.canLogin,
    required this.membershipActive,
    required this.createdAt,
    required this.updatedAt,
    this.username,
    this.phone,
    this.mustChangePassword = false,
    this.primarySocietyId,
    this.lastLoginAt,
    this.membershipStartsAt,
    this.membershipEndsAt,
  });

  final String id;
  final String email;
  final String? username;
  final String name;
  final String? phone;
  final List<String> roles;
  final bool isActive;
  final bool canLogin;
  final bool mustChangePassword;
  final String? primarySocietyId;
  final String? lastLoginAt;
  final bool membershipActive;
  final String? membershipStartsAt;
  final String? membershipEndsAt;
  final String createdAt;
  final String updatedAt;

  factory AdminGuard.fromJson(Object? data) {
    final json = requireMap(data, 'guard');
    return AdminGuard(
      id: requireString(json, 'id'),
      email: requireString(json, 'email'),
      username: optionalString(json, 'username'),
      name: requireString(json, 'name'),
      phone: optionalString(json, 'phone'),
      roles: requireStringList(json, 'roles'),
      isActive: requireBool(json, 'isActive'),
      canLogin: requireBool(json, 'canLogin'),
      mustChangePassword: json['mustChangePassword'] == true,
      primarySocietyId: optionalString(json, 'primarySocietyId'),
      lastLoginAt: optionalString(json, 'lastLoginAt'),
      membershipActive: optionalBool(json, 'membershipActive') ?? false,
      membershipStartsAt: optionalString(json, 'membershipStartsAt'),
      membershipEndsAt: optionalString(json, 'membershipEndsAt'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class ProvisionGuardResult {
  const ProvisionGuardResult({
    required this.guard,
    required this.reusedExisting,
    this.temporaryPassword,
    this.mustChangePassword = false,
    this.passwordGenerated,
  });

  final AdminGuard guard;
  final bool reusedExisting;
  final String? temporaryPassword;
  final bool mustChangePassword;
  final bool? passwordGenerated;

  factory ProvisionGuardResult.fromJson(Object? data) {
    final json = requireMap(data, 'provision guard');
    return ProvisionGuardResult(
      guard: AdminGuard.fromJson(json['guard']),
      reusedExisting: requireBool(json, 'reusedExisting'),
      temporaryPassword: optionalString(json, 'temporaryPassword'),
      mustChangePassword: json['mustChangePassword'] == true,
      passwordGenerated: json['passwordGenerated'] is bool
          ? json['passwordGenerated'] as bool
          : null,
    );
  }
}

class ListGuardsQuery {
  const ListGuardsQuery({
    this.search,
    this.isActive,
    this.page,
    this.limit,
  });

  final String? search;
  final bool? isActive;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'search': search,
        'isActive': isActive == null ? null : (isActive! ? 'true' : 'false'),
        'page': page,
        'limit': limit,
      };
}

class CreateGuardRequest {
  const CreateGuardRequest({
    required this.name,
    required this.email,
    this.phone,
    this.username,
    this.password,
  });

  final String name;
  final String email;
  final String? phone;
  final String? username;
  final String? password;

  Map<String, Object?> toJson() => omitNulls({
        'name': name,
        'email': email,
        'phone': phone,
        'username': username,
        'password': password,
      });
}

class UpdateGuardRequest {
  const UpdateGuardRequest({
    this.name,
    this.phone,
    this.canLogin,
  });

  final String? name;
  final String? phone;
  final bool? canLogin;

  Map<String, Object?> toJson() => omitNulls({
        'name': name,
        'phone': phone,
        'canLogin': canLogin,
      });
}
