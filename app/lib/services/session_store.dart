import 'package:shared_preferences/shared_preferences.dart';

/// Local session for demo login persistence (no backend).
class SessionStore {
  SessionStore._();

  static const roleOwner = 'owner';
  static const roleTenant = 'tenant';
  static const roleAdmin = 'admin';
  static const roleGuard = 'guard';

  static const _role = 'session_role';
  static const _mobile = 'session_mobile';
  static const _flatId = 'session_flat_id';
  static const _adminId = 'session_admin_id';
  static const _guardId = 'session_guard_id';

  static Future<void> saveOwner(
      {required String mobile, required int flatId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_role, roleOwner);
    await prefs.setString(_mobile, mobile);
    await prefs.setInt(_flatId, flatId);
    await prefs.remove(_adminId);
    await prefs.remove(_guardId);
  }

  static Future<void> saveTenant(
      {required String mobile, required int flatId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_role, roleTenant);
    await prefs.setString(_mobile, mobile);
    await prefs.setInt(_flatId, flatId);
    await prefs.remove(_adminId);
    await prefs.remove(_guardId);
  }

  static Future<void> saveAdmin(
      {required String mobile, required int adminId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_role, roleAdmin);
    await prefs.setString(_mobile, mobile);
    await prefs.setInt(_adminId, adminId);
    await prefs.remove(_flatId);
    await prefs.remove(_guardId);
  }

  static Future<void> saveGuard(
      {required String mobile, required int guardId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_role, roleGuard);
    await prefs.setString(_mobile, mobile);
    await prefs.setInt(_guardId, guardId);
    await prefs.remove(_flatId);
    await prefs.remove(_adminId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_role);
    await prefs.remove(_mobile);
    await prefs.remove(_flatId);
    await prefs.remove(_adminId);
    await prefs.remove(_guardId);
  }

  static Future<SavedSession?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(_role);
    final mobile = prefs.getString(_mobile);
    if (role == null || mobile == null) return null;
    if (role == roleOwner || role == roleTenant) {
      final flatId = prefs.getInt(_flatId);
      if (flatId == null) return null;
      return SavedSession(role: role, mobile: mobile, flatId: flatId);
    }
    if (role == roleAdmin) {
      final adminId = prefs.getInt(_adminId);
      if (adminId == null) return null;
      return SavedSession(role: roleAdmin, mobile: mobile, adminId: adminId);
    }
    if (role == roleGuard) {
      final guardId = prefs.getInt(_guardId);
      if (guardId == null) return null;
      return SavedSession(role: roleGuard, mobile: mobile, guardId: guardId);
    }
    return null;
  }
}

class SavedSession {
  SavedSession({
    required this.role,
    required this.mobile,
    this.flatId,
    this.adminId,
    this.guardId,
  });
  final String role;
  final String mobile;
  final int? flatId;
  final int? adminId;
  final int? guardId;
  bool get isAdmin => role == SessionStore.roleAdmin;
  bool get isOwner => role == SessionStore.roleOwner;
  bool get isTenant => role == SessionStore.roleTenant;
  bool get isGuard => role == SessionStore.roleGuard;
  bool get isResident => isOwner || isTenant;
}
