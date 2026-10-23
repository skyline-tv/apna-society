import 'dart:async';

import '../../services/push_notification_service.dart';
import '../../services/session_store.dart';
import '../models/auth_models.dart';
import '../models/resident_home_context.dart';
import '../repositories/live_repositories.dart';
import '../socket/visitor_socket.dart';
import 'app_role.dart';
import 'auth_session.dart';

enum HomeDestinationKind {
  login,
  admin,
  guard,
  resident,
}

/// Navigation target after authentication. Screens stay in `main.dart`.
class HomeDestination {
  const HomeDestination.login()
      : kind = HomeDestinationKind.login,
        resident = null,
        guard = null;

  const HomeDestination.admin()
      : kind = HomeDestinationKind.admin,
        resident = null,
        guard = null;

  const HomeDestination.guard(this.guard)
      : kind = HomeDestinationKind.guard,
        resident = null;

  const HomeDestination.resident(this.resident)
      : kind = HomeDestinationKind.resident,
        guard = null;

  final HomeDestinationKind kind;
  final ResidentHomeContext? resident;
  final GuardSessionRow? guard;
}

/// Builds the destination from an authenticated [AuthSession].
///
/// Society / resident / flat identity comes from the backend only.
/// Local SQLite is not used to match flats, admins, or guards by phone.
class HomeResolver {
  HomeResolver(this.session);

  final AuthSession session;

  Future<HomeDestination> resolve() async {
    final profile = session.profile;
    final role = session.appRole;
    if (profile == null || role == null || !session.isAuthenticated) {
      return const HomeDestination.login();
    }

    // Drop legacy demo session keys so they cannot restore identity.
    await SessionStore.clear();

    final repos = ensureLiveRepositories(session.api);

    VisitorSocket.instance.connectForSession(session);
    unawaited(PushNotificationService.instance.start(session));

    switch (role) {
      case AppRole.admin:
        return const HomeDestination.admin();
      case AppRole.guard:
        return HomeDestination.guard(_guardFromProfile(profile));
      case AppRole.owner:
      case AppRole.tenant:
        return _resolveResident(repos, role);
    }
  }

  Future<HomeDestination> _resolveResident(
    LiveRepositories repos,
    AppRole role,
  ) async {
    final sessionFlats = session.residentFlats;
    final profile = await repos.resident.profile();
    final flats = sessionFlats.isNotEmpty
        ? sessionFlats
        : await repos.resident.flats();
    repos.resident.seedFromSession(profile: profile, flats: flats);

    final context = ResidentHomeContext.fromBackend(
      profile: profile,
      flats: flats,
      preferOwner: role == AppRole.owner,
    );
    return HomeDestination.resident(context);
  }

  GuardSessionRow _guardFromProfile(AuthProfile profile) {
    final phone = (profile.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final mobile = phone.length >= 10
        ? phone.substring(phone.length - 10)
        : (phone.isEmpty ? '—' : phone);
    return GuardSessionRow(
      id: 0,
      name: profile.name.trim().isEmpty ? 'Security' : profile.name.trim(),
      mobile: mobile,
      isActive: 1,
    );
  }
}

/// Display-only guard row for GuardHome. Not a local SQLite identity.
class GuardSessionRow {
  GuardSessionRow({
    required this.id,
    required this.name,
    required this.mobile,
    required this.isActive,
  });

  final int id;
  final String name;
  final String mobile;
  final int isActive;

  Map<String, Object?> get data => {
        'id': id,
        'name': name,
        'mobile': mobile,
        'is_active': isActive,
      };

  T read<T>(String column) {
    final value = data[column];
    if (value is T) return value;
    throw StateError('GuardSessionRow.$column is not $T');
  }
}

/// Clears backend session, live caches, and legacy local demo keys.
Future<void> performLogout(AuthSession session) async {
  disconnectVisitorSocket();
  clearLiveRepositories();
  await session.logout();
  await SessionStore.clear();
}
