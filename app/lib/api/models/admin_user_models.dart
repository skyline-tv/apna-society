import '../http/json_read.dart';
import 'common.dart';

/// Serialized admin user (`GET/POST /api/v1/admin/users`).
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.name,
    required this.roles,
    required this.isActive,
    required this.canLogin,
    required this.createdAt,
    required this.updatedAt,
    this.username,
    this.phone,
    this.mobileE164,
    this.mobileVerified = false,
    this.mobileVerifiedAt,
    this.primarySocietyId,
    this.lastLoginAt,
    this.mustChangePassword = false,
    this.hasPassword = false,
    this.societyRoles = const [],
    this.activeOccupancies = const [],
  });

  final String id;
  final String email;
  final String? username;
  final String name;
  final String? phone;
  final String? mobileE164;
  final bool mobileVerified;
  final String? mobileVerifiedAt;
  final List<String> roles;
  final bool isActive;
  final bool canLogin;
  final bool mustChangePassword;
  final bool hasPassword;
  final String? primarySocietyId;
  final String? lastLoginAt;
  final String createdAt;
  final String updatedAt;

  /// Society membership roles from list responses.
  final List<String> societyRoles;

  /// Present on `GET /users/:userId`.
  final List<ActiveOccupancySummary> activeOccupancies;

  bool get isOwner =>
      roles.contains('OWNER') || societyRoles.contains('OWNER');
  bool get isTenant =>
      roles.contains('TENANT') || societyRoles.contains('TENANT');

  factory AdminUser.fromJson(Object? data) {
    final json = requireMap(data, 'user');
    final roles = requireStringList(json, 'roles');
    final societyRoles = json.containsKey('societyRoles')
        ? requireStringList(json, 'societyRoles')
        : const <String>[];
    final occupancies = json['activeOccupancies'];
    return AdminUser(
      id: requireString(json, 'id'),
      email: requireString(json, 'email'),
      username: optionalString(json, 'username'),
      name: requireString(json, 'name'),
      phone: optionalString(json, 'phone'),
      mobileE164: optionalString(json, 'mobileE164'),
      mobileVerified: json['mobileVerified'] == true,
      mobileVerifiedAt: optionalString(json, 'mobileVerifiedAt'),
      roles: roles,
      isActive: requireBool(json, 'isActive'),
      canLogin: requireBool(json, 'canLogin'),
      mustChangePassword: json['mustChangePassword'] == true,
      hasPassword: json['hasPassword'] == true,
      primarySocietyId: optionalString(json, 'primarySocietyId'),
      lastLoginAt: optionalString(json, 'lastLoginAt'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
      societyRoles: societyRoles,
      activeOccupancies: occupancies is! List
          ? const []
          : occupancies
              .map((item) => ActiveOccupancySummary.fromJson(
                    requireMap(item, 'activeOccupancy'),
                  ))
              .toList(),
    );
  }
}

class ActiveOccupancySummary {
  const ActiveOccupancySummary({
    required this.id,
    required this.flatId,
    required this.role,
    required this.startsAt,
  });

  final String id;
  final String flatId;
  final String role;
  final String startsAt;

  factory ActiveOccupancySummary.fromJson(JsonMap json) {
    return ActiveOccupancySummary(
      id: requireString(json, 'id'),
      flatId: requireString(json, 'flatId'),
      role: requireString(json, 'role'),
      startsAt: requireString(json, 'startsAt'),
    );
  }
}

class ProvisionUserResult {
  const ProvisionUserResult({
    required this.user,
    required this.reusedExisting,
    required this.flatAssigned,
    this.temporaryPassword,
    this.mustChangePassword = false,
    this.passwordGenerated,
  });

  final AdminUser user;
  final bool reusedExisting;
  final bool flatAssigned;
  final String? temporaryPassword;
  final bool mustChangePassword;
  final bool? passwordGenerated;

  factory ProvisionUserResult.fromJson(Object? data) {
    final json = requireMap(data, 'provision');
    return ProvisionUserResult(
      user: AdminUser.fromJson(json['user']),
      reusedExisting: requireBool(json, 'reusedExisting'),
      flatAssigned: requireBool(json, 'flatAssigned'),
      temporaryPassword: optionalString(json, 'temporaryPassword'),
      mustChangePassword: json['mustChangePassword'] == true,
      passwordGenerated: json['passwordGenerated'] is bool
          ? json['passwordGenerated'] as bool
          : null,
    );
  }
}

class AdminSetPasswordResult {
  const AdminSetPasswordResult({
    required this.user,
    required this.temporaryPassword,
    required this.mustChangePassword,
    this.passwordGenerated = true,
  });

  final AdminUser user;
  final String temporaryPassword;
  final bool mustChangePassword;
  final bool passwordGenerated;

  factory AdminSetPasswordResult.fromJson(Object? data) {
    final json = requireMap(data, 'set-password');
    return AdminSetPasswordResult(
      user: AdminUser.fromJson(json['user']),
      temporaryPassword: requireString(json, 'temporaryPassword'),
      mustChangePassword: json['mustChangePassword'] == true,
      passwordGenerated: json['passwordGenerated'] != false,
    );
  }
}

class ListUsersQuery {
  const ListUsersQuery({
    this.search,
    this.role,
    this.isActive,
    this.page,
    this.limit,
  });

  final String? search;
  final String? role;
  final bool? isActive;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'search': search,
        'role': role,
        'isActive': isActive == null ? null : (isActive! ? 'true' : 'false'),
        'page': page,
        'limit': limit,
      };
}

class OccupancyMutationResult {
  const OccupancyMutationResult({
    required this.flatId,
    required this.occupancyStatus,
    this.activeOwnerUserId,
    this.activeTenantUserId,
  });

  final String flatId;
  final String occupancyStatus;
  final String? activeOwnerUserId;
  final String? activeTenantUserId;

  factory OccupancyMutationResult.fromJson(Object? data) {
    final json = requireMap(data, 'occupancy mutation');
    return OccupancyMutationResult(
      flatId: requireString(json, 'flatId'),
      occupancyStatus: requireString(json, 'occupancyStatus'),
      activeOwnerUserId: optionalString(json, 'activeOwnerUserId'),
      activeTenantUserId: optionalString(json, 'activeTenantUserId'),
    );
  }
}

class AdminOccupancyHistoryItem {
  const AdminOccupancyHistoryItem({
    required this.id,
    required this.userId,
    required this.role,
    required this.status,
    required this.startsAt,
    this.userName,
    this.userEmail,
    this.endsAt,
    this.endReason,
    this.notes,
  });

  final String id;
  final String userId;
  final String? userName;
  final String? userEmail;
  final String role;
  final String status;
  final String startsAt;
  final String? endsAt;
  final String? endReason;
  final String? notes;

  factory AdminOccupancyHistoryItem.fromJson(JsonMap json) {
    return AdminOccupancyHistoryItem(
      id: requireString(json, 'id'),
      userId: requireString(json, 'userId'),
      userName: optionalString(json, 'userName'),
      userEmail: optionalString(json, 'userEmail'),
      role: requireString(json, 'role'),
      status: requireString(json, 'status'),
      startsAt: requireString(json, 'startsAt'),
      endsAt: optionalString(json, 'endsAt'),
      endReason: optionalString(json, 'endReason'),
      notes: optionalString(json, 'notes'),
    );
  }
}

class AdminOccupancyHistory {
  const AdminOccupancyHistory({
    required this.flatId,
    required this.occupancyStatus,
    required this.items,
    required this.pagination,
    this.activeOwnerUserId,
    this.activeTenantUserId,
  });

  final String flatId;
  final String occupancyStatus;
  final String? activeOwnerUserId;
  final String? activeTenantUserId;
  final List<AdminOccupancyHistoryItem> items;
  final Page pagination;

  factory AdminOccupancyHistory.fromJson(Object? data) {
    final json = requireMap(data, 'occupancy history');
    return AdminOccupancyHistory(
      flatId: requireString(json, 'flatId'),
      occupancyStatus: requireString(json, 'occupancyStatus'),
      activeOwnerUserId: optionalString(json, 'activeOwnerUserId'),
      activeTenantUserId: optionalString(json, 'activeTenantUserId'),
      items: requireMapList(json, 'items')
          .map(AdminOccupancyHistoryItem.fromJson)
          .toList(),
      pagination: Page.fromJson(requireMap(json['pagination'], 'pagination')),
    );
  }
}

class OccupancyRecordSummary {
  const OccupancyRecordSummary({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.userId,
    required this.role,
    required this.status,
    required this.startsAt,
    this.endsAt,
    this.endReason,
    this.notes,
  });

  final String id;
  final String societyId;
  final String flatId;
  final String userId;
  final String role;
  final String status;
  final String startsAt;
  final String? endsAt;
  final String? endReason;
  final String? notes;

  factory OccupancyRecordSummary.fromJson(JsonMap json) {
    return OccupancyRecordSummary(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      userId: requireString(json, 'userId'),
      role: requireString(json, 'role'),
      status: requireString(json, 'status'),
      startsAt: requireString(json, 'startsAt'),
      endsAt: optionalString(json, 'endsAt'),
      endReason: optionalString(json, 'endReason'),
      notes: optionalString(json, 'notes'),
    );
  }
}
