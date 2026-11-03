import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/auth/app_role.dart';
import 'api/auth/auth_messages.dart';
import 'api/auth/auth_session.dart';
import 'api/auth/home_resolver.dart';
import 'api/config/api_config.dart';
import 'api/config/demo_environment.dart';
import 'api/http/api_exception.dart';
import 'api/socket/visitor_socket.dart';
import 'services/push_notification_service.dart';
import 'api/models/billing_models.dart'
    show
        AdditionalService,
        Bill,
        ListBillsQuery,
        billAmountDuePaise,
        canAddActiveAdditionalService,
        kAdditionalServiceLimitMessage;
import 'api/models/collection_models.dart' show CollectionCharge;
import 'api/models/common.dart' show Paged;
import 'api/models/resident_home_context.dart';
import 'api/models/resident_models.dart';
import 'api/models/society_models.dart';
import 'api/repositories/live_repositories.dart';
import 'app_core.dart';
import 'api/auth/admin_api_messages.dart';
import 'api/models/admin_user_models.dart';
import 'features/admin/admin_dashboard.dart';
import 'features/owner/owner_dashboard.dart';
import 'features/admin/admin_flat_detail_page.dart';
import 'features/admin/admin_flats_page.dart';
import 'features/admin/admin_more_page.dart';
import 'features/auth/society_selection_screen.dart';
import 'features/billing/live_additional_services_module.dart';
import 'features/billing/live_billing_module.dart';
import 'features/collections/live_collections_module.dart';
import 'features/reports/live_reports_module.dart';
import 'features/residents/admin_residents_module.dart';
import 'features/security/security_module.dart';
import 'features/announcements/live_announcements_module.dart';
import 'features/guards/admin_guards_module.dart';
import 'features/notifications/live_notifications_module.dart';
import 'features/vehicles/live_vehicles_module.dart';
import 'features/visitors/live_visitors_module.dart';
import 'services/occupancy_access.dart';
import 'services/session_store.dart';
import 'ui/components.dart';
import 'ui/demo_chrome.dart';
import 'ui/load_failure.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.bootstrap();
  AuthSession.onLocalSessionCleared = () {
    disconnectVisitorSocket();
    unawaited(PushNotificationService.instance.stop());
  };
  AuthSession.onAccessTokenRefreshed = (session) {
    VisitorSocket.instance.connectForSession(session);
  };
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  // Paint UI immediately. Heavy SQLite open/migrate/seed runs inside [AppBootstrap]
  // so release APKs never sit on a native black splash if init is slow or fails.
  runApp(const ApnaSocietyApp());
}

Future<void> _initializeLocalDatabase() async {
  await db
      .customSelect('SELECT 1')
      .get(); // Open local SQLite (runs migrations).
  // Idempotent one-shot billing reset (flagged in app_settings). Does not wipe flats/owners.
  await db.ensureFreshBillingStart(key: 'billing_clear_all_v12');
  final inventory = await db.verifyFlatInventory();
  if ((inventory['totalFlats'] ?? 0) != 140 ||
      (inventory['monthlyMaintenance'] ?? 0) != 588000) {
    await db.syncSocietyFlatsStructure(assignDemoOwner: true);
  }
}


class ApnaSocietyApp extends StatelessWidget {
  const ApnaSocietyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: kAppName,
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.3,
              ),
            ),
            child: DemoModeOverlay(
              onOpen: () {
                final nav = appNavigatorKey.currentContext;
                if (nav == null) return;
                showDemoInfoSheet(
                  nav,
                  onLeave: () async {
                    await DemoEnvironment.persist(false);
                    final session = replaceAuthSession(
                      config: ApiConfig.fromEnvironment(),
                    );
                    await session.clearLocal();
                    appNavigatorKey.currentState?.pushAndRemoveUntil(
                      unsignedInRoute(),
                      (_) => false,
                    );
                  },
                );
              },
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: const AppBootstrap(),
        routes: {
          kSelectSocietyRoute: (_) => const SocietySelectionScreen(),
          kLoginRoute: (context) => LoginScreen(
                society: societyKindFromRouteArgs(
                  ModalRoute.of(context)?.settings.arguments,
                ),
              ),
        },
      );
}

/// Opens SQLite / runs migrations after the first frame so the APK never freezes on a blank native splash.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    // Local SQLite is leftover cache — don't block login / demo on it.
    unawaited(_initializeLocalDatabase());
  }

  @override
  Widget build(BuildContext context) => const AuthGate();
}

/// Branded splash used while the app boots or restores a session.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen({required this.label, this.error, this.onRetry});
  final String label;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: C.blue,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 80,
                      height: 80,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(Rd.xxl),
                      ),
                      child: const BrandLogo(size: 52, radius: 16),
                    ),
                    const SizedBox(height: 20),
                    const Text(kAppName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        )),
                    const SizedBox(height: 6),
                    Text(kSocietyName,
                        textAlign: TextAlign.center,
                        style: T.secondary.copyWith(
                            color: Colors.white.withValues(alpha: 0.72))),
                    const SizedBox(height: 4),
                    Text(kAppTagline,
                        textAlign: TextAlign.center,
                        style: T.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.55))),
                    const SizedBox(height: 32),
                    if (error == null) ...[
                      const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Colors.white,
                          )),
                      const SizedBox(height: 14),
                      Text(label,
                          style: T.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.8))),
                    ] else ...[
                      Text(label,
                          textAlign: TextAlign.center,
                          style: T.h3.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      Text(error!,
                          textAlign: TextAlign.center,
                          style: T.secondary.copyWith(
                              color: Colors.white.withValues(alpha: 0.78))),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: C.blue,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try again'),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

String _sessionRestoreError(Object error) {
  final base = authErrorMessage(error);
  if (error is! ApiException) {
    return '$base\n\nYour sign-in was kept. Check your connection and try again.';
  }
  final network = error.code == 'NETWORK_TIMEOUT' ||
      error.code == 'NETWORK_UNAVAILABLE' ||
      error.code == 'NETWORK_ERROR';
  if (!network) {
    return '$base\n\nYour sign-in was kept. Check your connection and try again.';
  }
  final config = ApiConfig.fromEnvironment();
  if (config.flavor == ApiFlavor.development) {
    return '$base\n\nThis debug build is calling ${config.baseUrl} (local API). Your internet cannot reach that host unless the backend is running on that LAN address.\n\nQuit flutter run and start it with:\nflutter run --dart-define-from-file=dart_defines.production.json';
  }
  return '$base\n\nYour sign-in was kept. Check your connection and try again.';
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Widget> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _resolveHome();
  }

  Future<Widget> _resolveHome() async {
    // Legacy local-demo session keys must not restore an authenticated shell.
    await SessionStore.clear();
    await DemoEnvironment.restorePersisted();
    final session = ensureAuthSession();
    final remembered = await session.readRememberedUsername();
    if (DemoEnvironment.isDemoUsername(remembered)) {
      await session.clearLocal();
      await session.clearRememberedUsername();
      return const SocietySelectionScreen();
    }
    try {
      final profile = await session.restore();
      if (profile == null) {
        return const SocietySelectionScreen();
      }
      if (profile.mustChangePassword) {
        return const ChangePasswordScreen(forced: true);
      }
      final destination = await HomeResolver(session).resolve();
      PushNotificationService.instance.flushPending();
      return _widgetForDestination(destination);
    } catch (error) {
      // Only wipe credentials for terminal auth failures. Network / context
      // errors keep the refresh token so Retry can succeed without re-login.
      if (isTerminalSessionError(error)) {
        await session.clearLocal();
        await SessionStore.clear();
        return const SocietySelectionScreen();
      }
      rethrow;
    }
  }

  Widget _widgetForDestination(HomeDestination destination) {
    switch (destination.kind) {
      case HomeDestinationKind.login:
        return const SocietySelectionScreen();
      case HomeDestinationKind.admin:
        return const AdminHome();
      case HomeDestinationKind.guard:
        return GuardHome(guard: destination.guard);
      case HomeDestinationKind.resident:
        return OwnerHome(home: destination.resident!);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
        future: _boot,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _SplashScreen(
              label: 'Could not restore your session',
              error: _sessionRestoreError(snapshot.error!),
              onRetry: () {
                setState(() {
                  _boot = _resolveHome();
                });
              },
            );
          }
          if (!snapshot.hasData) {
            return const _SplashScreen(label: 'Opening your society…');
          }
          return snapshot.data!;
        },
      );
}

/// Visual tokens for the Monarch live sign-in screen only.
class _LoginLook {
  static const brand800 = Color(0xFF153B69);
  static const brand900 = Color(0xFF0F2C52);
  static const brand600 = Color(0xFF1E4C82);
  static const brand50 = Color(0xFFF0F5FC);
  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate200 = Color(0xFFE2E8F0);
  static const live = Color(0xFF10B981);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber200 = Color(0xFFFDE68A);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber900 = Color(0xFF78350F);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.society = SocietyKind.live,
  });

  final SocietyKind society;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String role = 'owner';
  final username = TextEditingController();
  final password = TextEditingController();
  bool obscurePassword = true;
  bool rememberMe = true;
  bool busy = false;
  String? error;

  static const _roleOptions = <(String, String, IconData)>[
    ('owner', 'Flat Owner', Icons.home_outlined),
    ('tenant', 'Flat Tenant', Icons.location_on_outlined),
    ('admin', 'Admin', Icons.key_outlined),
    ('guard', 'Security Guard', Icons.verified_user_outlined),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.society.isDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_enterDemoMode());
      });
    } else {
      _loadRemembered();
    }
  }

  Future<void> _loadRemembered() async {
    final remembered = await ensureAuthSession().readRememberedUsername();
    if (!mounted ||
        remembered == null ||
        remembered.isEmpty ||
        widget.society.isDemo ||
        DemoEnvironment.isDemoUsername(remembered)) {
      return;
    }
    setState(() {
      username.text = remembered;
      rememberMe = true;
    });
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submitLogin() async {
    if (busy) return;
    setState(() {
      error = null;
      busy = true;
    });
    try {
      final user = username.text.trim();
      if (!isValidUsername(user)) {
        setState(() => error = 'Enter a valid username (3–32 characters).');
        return;
      }
      if (password.text.isEmpty) {
        setState(() => error = 'Enter your password.');
        return;
      }
      if (widget.society.isDemo || DemoEnvironment.isDemoUsername(user)) {
        await DemoEnvironment.persist(true);
        replaceAuthSession(config: DemoEnvironment.config());
      }
      final session = ensureAuthSession();
      final profile = await session.login(
        username: user,
        password: password.text,
        rememberMe: rememberMe,
      );
      if (!mounted) return;
      if (profile.mustChangePassword) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const ChangePasswordScreen(forced: true),
          ),
          (_) => false,
        );
        return;
      }
      final destination = await HomeResolver(session).resolve();
      if (!mounted) return;
      final selected = tryParseDropdownRole(role);
      final actual = session.appRole;
      if (selected != null && actual != null && selected != actual) {
        showInfoSnack(
          context,
          'Signed in as ${actual.label}. Your account role is used for access.',
        );
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => _homeFromDestination(destination)),
        (_) => false,
      );
      PushNotificationService.instance.flushPending();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _homeFromDestination(HomeDestination destination) {
    switch (destination.kind) {
      case HomeDestinationKind.login:
        return const LoginScreen();
      case HomeDestinationKind.admin:
        return const AdminHome();
      case HomeDestinationKind.guard:
        return GuardHome(guard: destination.guard);
      case HomeDestinationKind.resident:
        return OwnerHome(home: destination.resident!);
    }
  }

  DemoAccount? _demoAccountForRole(String value) {
    final want = switch (value) {
      'admin' => 'Admin',
      'owner' => 'Owner',
      'tenant' => 'Tenant',
      _ => 'Security Guard',
    };
    for (final account in DemoEnvironment.accounts) {
      if (account.role == want) return account;
    }
    return null;
  }

  void _onRoleChanged(String? value) {
    if (value == null || busy) return;
    if (widget.society.isDemo) {
      final account = _demoAccountForRole(value);
      if (account != null) {
        _fillDemoAccount(account);
        return;
      }
    }
    setState(() {
      role = value;
      error = null;
    });
  }

  Future<void> _enterDemoMode() async {
    if (busy) return;
    setState(() => error = null);
    try {
      await DemoEnvironment.persist(true);
      replaceAuthSession(config: DemoEnvironment.config());
      if (!mounted) return;
      _fillDemoAccount(DemoEnvironment.accounts.first);
      unawaited(_confirmDemoServer());
    } catch (e) {
      await DemoEnvironment.persist(false);
      replaceAuthSession(config: ApiConfig.fromEnvironment());
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Could not reach the demo server. Sample data is isolated and is not available on the production API.';
      setState(() => error = message);
    }
  }

  Future<void> _confirmDemoServer() async {
    try {
      final env = await ensureAuthSession().api.auth.publicEnvironment();
      if (env.demoMode || !mounted) return;
      await DemoEnvironment.persist(false);
      replaceAuthSession(config: ApiConfig.fromEnvironment());
      if (!mounted) return;
      setState(() {
        error =
            'The demo server is not in DEMO MODE. Reviewer sample data was not opened.';
      });
    } catch (_) {
      // Sign-in will surface a connection error if the demo API is down.
    }
  }

  void _fillDemoAccount(DemoAccount account) {
    setState(() {
      username.text = account.username;
      password.text = account.password;
      error = null;
      role = switch (account.role) {
        'Admin' => 'admin',
        'Owner' => 'owner',
        'Tenant' => 'tenant',
        _ => 'guard',
      };
    });
  }

  void _goToSocieties() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(unsignedInRoute(), (_) => false);
  }

  void _showForgotPassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.lock_reset_rounded, color: C.blue),
        title: const Text('Forgot password?'),
        content: const Text(
          'Password reset is handled by your society admin. Ask them to issue a temporary password, then change it on first sign-in.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final demo = widget.society.isDemo;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _LoginLook.slate200),
    );
    final fieldFocusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _LoginLook.brand800, width: 1.4),
    );

    return Scaffold(
      backgroundColor: kAuthCanvas,
      body: KeyboardDismissOnTap(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        MediaQuery.sizeOf(context).width < 360 ? 16 : 24,
                        8,
                        MediaQuery.sizeOf(context).width < 360 ? 16 : 24,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _loginHeader(demo: demo),
                          const SizedBox(height: 8),
                          _loginHero(demo: demo),
                          const SizedBox(height: 20),
                          const Text(
                            'Sign in as',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _LoginLook.slate800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Your account role is confirmed by the server. This only sets the sign-in context.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: _LoginLook.slate500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _roleChooser(),
                          if (demo) ...[
                            const SizedBox(height: 12),
                            const _DemoModeNotice(),
                          ],
                          const SizedBox(height: 16),
                          TextField(
                            controller: username,
                            enabled: !busy,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.username],
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9_-]'),
                              ),
                              LengthLimitingTextInputFormatter(32),
                            ],
                            decoration: InputDecoration(
                              hintText: 'Username',
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                                color: _LoginLook.slate400,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: fieldBorder,
                              enabledBorder: fieldBorder,
                              disabledBorder: fieldBorder,
                              focusedBorder: fieldFocusBorder,
                            ),
                            onChanged: (_) {
                              if (error != null) setState(() => error = null);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: password,
                            enabled: !busy,
                            obscureText: obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => busy ? null : submitLogin(),
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: _LoginLook.slate400,
                              ),
                              suffixIcon: IconButton(
                                tooltip: obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: busy
                                    ? null
                                    : () => setState(
                                          () => obscurePassword =
                                              !obscurePassword,
                                        ),
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: _LoginLook.slate400,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              border: fieldBorder,
                              enabledBorder: fieldBorder,
                              disabledBorder: fieldBorder,
                              focusedBorder: fieldFocusBorder,
                            ),
                            onChanged: (_) {
                              if (error != null) setState(() => error = null);
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: busy
                                      ? null
                                      : () => setState(
                                            () => rememberMe = !rememberMe,
                                          ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(
                                          value: rememberMe,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          side: const BorderSide(
                                              color: _LoginLook.slate200),
                                          fillColor:
                                              WidgetStateProperty.resolveWith(
                                            (states) => states.contains(
                                                    WidgetState.selected)
                                                ? _LoginLook.brand800
                                                : Colors.white,
                                          ),
                                          onChanged: busy
                                              ? null
                                              : (value) => setState(
                                                    () => rememberMe =
                                                        value ?? false,
                                                  ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Flexible(
                                        child: Text(
                                          'Remember me',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _LoginLook.slate700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: busy ? null : _showForgotPassword,
                                style: TextButton.styleFrom(
                                  foregroundColor: _LoginLook.brand800,
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: const Text('Forgot password?'),
                              ),
                            ],
                          ),
                          InlineError(error),
                          const Spacer(),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: busy ? null : submitLogin,
                              style: FilledButton.styleFrom(
                                backgroundColor: _LoginLook.brand800,
                                disabledBackgroundColor: _LoginLook.brand800
                                    .withValues(alpha: 0.55),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            demo
                                                ? 'Sign in to Demo'
                                                : 'Sign In',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (!demo) ...[
                                          const Text(
                                            '  (Step 2)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.white70,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 20),
                                        ] else ...[
                                          const SizedBox(width: 8),
                                          const Icon(Icons.login_rounded,
                                              size: 18),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (demo)
                            const Divider(
                              height: 1,
                              color: Color(0x99E2E8F0),
                            ),
                          if (demo) const SizedBox(height: 16),
                          const Text(
                            'Powered by SkyLine Tech Ventures',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _LoginLook.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _loginHeader({required bool demo}) {
    return Row(
      children: [
        InkWell(
          key: const Key('login-back-societies'),
          onTap: busy ? null : _goToSocieties,
          borderRadius: BorderRadius.circular(Rd.pill),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(2, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left_rounded,
                    size: 22, color: _LoginLook.slate600),
                Text(
                  'Societies',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _LoginLook.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _LoginLook.brand50.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(Rd.pill),
                  border: Border.all(
                    color: _LoginLook.slate200.withValues(alpha: 0.9),
                  ),
                ),
                child: const Text(
                  'Step 2 of 2',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: _LoginLook.brand800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(Rd.pill),
                  border: Border.all(
                    color: _LoginLook.slate200.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: demo ? _LoginLook.amber500 : _LoginLook.live,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      demo ? 'DEMO MODE' : 'LIVE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: demo
                            ? _LoginLook.amber700
                            : _LoginLook.slate600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _loginHero({required bool demo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [
                _LoginLook.brand900,
                _LoginLook.brand800,
                _LoginLook.brand600,
              ],
            ),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: _LoginLook.brand800.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.apartment_outlined,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Welcome back',
          style: TextStyle(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: _LoginLook.slate900,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              demo ? widget.society.title : kSocietyName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: _LoginLook.brand800,
              ),
            ),
            InkWell(
              onTap: busy ? null : _goToSocieties,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Change Society',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _LoginLook.slate500,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.swap_horiz_rounded,
                        size: 14, color: _LoginLook.slate400),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          demo
              ? 'Sample walkthrough & simulated database'
              : kAppTagline,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _LoginLook.slate500,
          ),
        ),
      ],
    );
  }

  Widget _roleChooser() {
    final tiles = [
      for (final (value, label, icon) in _roleOptions)
        _RoleChoice(
          key: ValueKey('login-role-$value'),
          label: label,
          icon: icon,
          selected: role == value,
          onTap: busy ? null : () => _onRoleChanged(value),
        ),
    ];
    return Column(children: [
      Row(children: [
        Expanded(child: tiles[0]),
        const SizedBox(width: 10),
        Expanded(child: tiles[1]),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: tiles[2]),
        const SizedBox(width: 10),
        Expanded(child: tiles[3]),
      ]),
    ]);
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = false});

  /// When true, user cannot dismiss without changing (temporary credential).
  final bool forced;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool obscureCurrent = true;
  bool obscureNew = true;
  bool obscureConfirm = true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      error = null;
      busy = true;
    });
    try {
      if (currentPassword.text.isEmpty) {
        setState(() => error = 'Enter your current password.');
        return;
      }
      if (!isValidPasswordStrength(newPassword.text)) {
        setState(() => error =
            'New password needs 10+ characters with a letter and a number.');
        return;
      }
      if (newPassword.text != confirmPassword.text) {
        setState(() => error = 'Password confirmation does not match.');
        return;
      }
      final session = ensureAuthSession();
      await session.changePassword(
        currentPassword: currentPassword.text,
        newPassword: newPassword.text,
        confirmPassword: confirmPassword.text,
      );
      // Server revoked sessions — clear local and require fresh login.
      await session.clearLocal();
      if (!mounted) return;
      showInfoSnack(context, 'Password updated. Please sign in again.');
      Navigator.pushAndRemoveUntil(
        context,
        unsignedInRoute(),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: widget.forced
            ? null
            : AppBar(
                title: const Text('Change password'),
              ),
        body: KeyboardDismissOnTap(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width < 360 ? 16 : 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.forced) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: C.blue,
                              borderRadius: BorderRadius.circular(Rd.xl),
                            ),
                            child: const Icon(Icons.lock_reset_rounded,
                                color: Colors.white, size: 26),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text('Set a new password', style: T.h1),
                        const SizedBox(height: 8),
                        const Text(
                          'Your temporary password must be changed before continuing.',
                          style: T.body,
                        ),
                        const SizedBox(height: 24),
                      ],
                      TextField(
                        controller: currentPassword,
                        obscureText: obscureCurrent,
                        enabled: !busy,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => obscureCurrent = !obscureCurrent),
                            icon: Icon(obscureCurrent
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newPassword,
                        obscureText: obscureNew,
                        enabled: !busy,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'New password',
                          helperText:
                              'At least 10 characters, with a letter and a number.',
                          prefixIcon: const Icon(Icons.password_rounded),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => obscureNew = !obscureNew),
                            icon: Icon(obscureNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmPassword,
                        obscureText: obscureConfirm,
                        enabled: !busy,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => busy ? null : submit(),
                        decoration: InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => obscureConfirm = !obscureConfirm),
                            icon: Icon(obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                      ),
                      InlineError(error),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Update password',
                        icon: Icons.check_rounded,
                        busy: busy,
                        onPressed: submit,
                      ),
                      if (widget.forced) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await ensureAuthSession().logout();
                                  if (!context.mounted) return;
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    unsignedInRoute(),
                                    (_) => false,
                                  );
                                },
                          child: const Text('Sign out'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _DemoModeNotice extends StatelessWidget {
  const _DemoModeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _LoginLook.amber50.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _LoginLook.amber200.withValues(alpha: 0.8),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded,
                size: 16, color: _LoginLook.amber600),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: _LoginLook.amber900,
                ),
                children: [
                  TextSpan(
                    text: 'Demo Mode: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        'Pre-filled credentials loaded for instant testing. Feel free to explore any role.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _LoginLook.brand50.withValues(alpha: 0.7)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? _LoginLook.brand800 : _LoginLook.slate200,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? _LoginLook.brand800
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : _LoginLook.slate600,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: selected ? _LoginLook.brand900 : _LoginLook.slate700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key, required this.home});
  final ResidentHomeContext home;
  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

/// Resident shell destinations. Keys double as the "More" hub page ids.
class _ResidentDest {
  const _ResidentDest(this.key, this.label, this.icon, this.selectedIcon);
  final String key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _kResidentDests = <String, _ResidentDest>{
  'home':
      _ResidentDest('home', 'Home', Icons.home_outlined, Icons.home_rounded),
  'bills': _ResidentDest('bills', 'Bills', Icons.receipt_long_outlined,
      Icons.receipt_long_rounded),
  'payments': _ResidentDest(
      'payments', 'Payments', Icons.payments_outlined, Icons.payments_rounded),
  'collections': _ResidentDest('collections', 'Collections',
      Icons.celebration_outlined, Icons.celebration_rounded),
  'visitors': _ResidentDest(
      'visitors', 'Visitors', Icons.groups_outlined, Icons.groups_rounded),
  'vehicles': _ResidentDest('vehicles', 'Vehicles',
      Icons.directions_car_outlined, Icons.directions_car_rounded),
  'news': _ResidentDest(
      'news', 'Announcements', Icons.campaign_outlined, Icons.campaign_rounded),
  'profile': _ResidentDest(
      'profile', 'Profile', Icons.person_outline_rounded, Icons.person_rounded),
  'more': _ResidentDest(
      'more', 'More', Icons.grid_view_outlined, Icons.grid_view_rounded),
};

class _OwnerHomeState extends State<OwnerHome> {
  int tab = 0;
  String? _morePage;
  late ResidentHomeContext home;
  late Future<ResidentProfileBundle> _profileFuture;
  Future<List<Bill>>? _duesFuture;
  Future<List<CollectionCharge>>? _collectionsFuture;

  OccupancyAccess get access => home.access;

  @override
  void initState() {
    super.initState();
    home = widget.home;
    // Keep create flows (vehicles) in sync with the selected flat.
    authSession?.selectResidentFlat(home.selectedFlat.flat.id);
    _profileFuture = _loadProfileBundle();
    _duesFuture = access.canFinance ? _loadDues() : null;
    _collectionsFuture = access.canFinance ? _loadCollectionDues() : null;
  }

  void _selectFlat(ResidentFlat next) {
    authSession?.selectResidentFlat(next.flat.id);
    final session = authSession;
    if (session != null) {
      ensureLiveRepositories(session.api).invalidateAfterFlatSelectionChange();
    }
    setState(() {
      home = home.copyWithSelected(next);
      _morePage = null;
      tab = 0;
      _profileFuture = _loadProfileBundle(force: true);
      _duesFuture = home.access.canFinance ? _loadDues(force: true) : null;
      _collectionsFuture =
          home.access.canFinance ? _loadCollectionDues(force: true) : null;
    });
  }

  Future<ResidentProfileBundle> _loadProfileBundle({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    repos.resident.seedFromSession(
      profile: home.profile,
      flats: home.accessibleFlats,
    );
    final profile = await repos.resident.profile(force: force);
    final flats = await repos.resident.flats(force: force);
    final selectedId = home.selectedFlat.flat.id;
    if (flats.isEmpty) {
      throw StateError(
        'No flat access is assigned to this account yet. Contact your society admin.',
      );
    }
    final match = flats.where((f) => f.flat.id == selectedId);
    final preferOwner = match.isEmpty
        ? home.access.isOwnerSession
        : match.first.access.role == 'OWNER';
    final next = ResidentHomeContext.fromBackend(
      profile: profile,
      flats: flats,
      preferOwner: preferOwner,
    );
    final resolved = match.isEmpty ? next : next.copyWithSelected(match.first);
    if (mounted) setState(() => home = resolved);
    return ResidentProfileBundle(context: resolved);
  }

  /// Open (unpaid) bills for the selected flat, from the live billing API.
  Future<List<Bill>> _loadDues({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final page = await ensureLiveRepositories(session.api)
        .billing
        .listResidentBills(
            force: force, query: const ListBillsQuery(limit: 50));
    final flatId = home.selectedFlat.flat.id;
    return page.items
        .where((b) => b.flatId == flatId)
        .where((b) => billAmountDuePaise(b) > 0)
        .where((b) {
      final s = b.status.toUpperCase();
      return s != 'PAID' && s != 'CANCELLED';
    }).toList();
  }

  Future<List<CollectionCharge>> _loadCollectionDues({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final items = await ensureLiveRepositories(session.api)
        .collections
        .listResident(force: force);
    final flatId = home.selectedFlat.flat.id;
    return items
        .where((row) => row.flatId == flatId)
        .where((row) =>
            row.outstandingPaise > 0 &&
            row.status != 'PAID' &&
            row.status != 'CANCELLED')
        .toList();
  }

  void refresh() {
    if (!mounted) return;
    setState(() {
      _profileFuture = _loadProfileBundle(force: true);
      _duesFuture = access.canFinance ? _loadDues(force: true) : null;
      _collectionsFuture =
          access.canFinance ? _loadCollectionDues(force: true) : null;
    });
  }

  /// Bottom destinations (max 5) and the hub contents.
  ({List<String> primary, List<String> more}) get _layout {
    final finance = access.canFinance;
    final residential = access.canResidential;
    if (finance && residential) {
      // Bills and visitors stay one tap away. Payments and the rest live in More.
      return (
        primary: const ['home', 'bills', 'visitors', 'more'],
        more: const [
          'payments',
          'collections',
          'vehicles',
          'news',
          'profile',
        ],
      );
    }
    if (finance) {
      return (
        primary: const ['home', 'bills', 'payments', 'collections', 'profile'],
        more: const [],
      );
    }
    if (residential) {
      return (
        primary: const ['home', 'visitors', 'vehicles', 'more'],
        more: const ['news', 'profile'],
      );
    }
    return (primary: const ['home', 'profile'], more: const []);
  }

  Widget _pageFor(String key) {
    final flatKey = home.selectedFlat.flat.id;
    switch (key) {
      case 'home':
        return ownerDashboard();
      case 'bills':
        return LiveOwnerBillsPage(
            key: ValueKey('bills-$flatKey'), canFinance: access.canFinance);
      case 'payments':
        return LiveOwnerPaymentsPage(
            key: ValueKey('payments-$flatKey'), canFinance: access.canFinance);
      case 'collections':
        return LiveOwnerCollectionsPage(
            key: ValueKey('collections-$flatKey'),
            canFinance: access.canFinance);
      case 'visitors':
        return LiveResidentVisitorsPage(key: ValueKey('visitors-$flatKey'));
      case 'vehicles':
        return LiveResidentVehiclesPage(key: ValueKey('vehicles-$flatKey'));
      case 'news':
        return LiveResidentAnnouncementsPage(key: ValueKey('news-$flatKey'));
      case 'profile':
        return ResidentProfilePage(
          home: home,
          onLogout: logout,
          onRefresh: refresh,
          onSelectFlat: home.hasMultipleFlats ? _selectFlat : null,
        );
      case 'more':
        return _moreHub();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _moreHub() {
    final layout = _layout;
    if (_morePage != null && layout.more.contains(_morePage)) {
      return _pageFor(_morePage!);
    }
    return ConstrainedContent(
      child: ListView(
        padding: Sp.pageInsets(context),
        children: [
          const PageHeader('More', subtitle: 'Everything else for this flat'),
          ToolDirectory(
            links: [
              for (final key in layout.more)
                ToolLink(
                  icon: _kResidentDests[key]!.icon,
                  label: _kResidentDests[key]!.label,
                  subtitle: _residentToolHint(key),
                  onTap: () => setState(() => _morePage = key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens any destination: switches to a primary tab or a hub sub-page.
  void _open(String key) {
    final layout = _layout;
    final primaryIndex = layout.primary.indexOf(key);
    setState(() {
      if (primaryIndex >= 0) {
        tab = primaryIndex;
        _morePage = null;
      } else if (layout.more.contains(key)) {
        tab = layout.primary.indexOf('more');
        _morePage = key;
      }
    });
  }

  bool get _canPopInternally {
    if (_morePage != null) return true;
    return tab != 0;
  }

  void _popInternally() {
    setState(() {
      if (_morePage != null) {
        _morePage = null;
      } else {
        tab = 0;
      }
    });
  }

  String get _titleForBar {
    final layout = _layout;
    final safeTab = tab.clamp(0, layout.primary.length - 1);
    final key = layout.primary[safeTab];
    if (key == 'more' && _morePage != null) {
      return _kResidentDests[_morePage]?.label ?? 'More';
    }
    if (key == 'home') return kAppName;
    return _kResidentDests[key]?.label ?? kAppName;
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final safeTab = tab.clamp(0, layout.primary.length - 1);
    if (safeTab != tab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => tab = safeTab);
      });
    }
    final inSubPage = layout.primary[safeTab] == 'more' && _morePage != null;
    final homeChrome = safeTab == 0 && !inSubPage;
    final compactBar = MediaQuery.sizeOf(context).width < 400;
    final iconDensity =
        compactBar ? VisualDensity.compact : VisualDensity.standard;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          homeChrome ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: PopScope(
        canPop: !_canPopInternally,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _popInternally();
        },
        child: Scaffold(
          backgroundColor: OwnerDash.surface,
          appBar: homeChrome
              ? null
              : AppBar(
                  automaticallyImplyLeading: false,
                  leadingWidth: inSubPage ? 56 : null,
                  leading: inSubPage
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Center(
                            child: AppCircleBackButton(
                              onPressed: _popInternally,
                            ),
                          ),
                        )
                      : null,
                  title: inSubPage
                      ? Text(_titleForBar)
                      : brandAppBarTitle(
                          title: _titleForBar, subtitle: kSocietyName),
                  actions: [
                    if (access.canResidential)
                      const LiveNotificationBellButton(),
                    if (!compactBar && layout.more.contains('profile'))
                      IconButton(
                        tooltip: 'Profile',
                        visualDensity: iconDensity,
                        onPressed: () => _open('profile'),
                        icon: const Icon(Icons.account_circle_outlined),
                      ),
                    IconButton(
                      tooltip: 'Logout',
                      visualDensity: iconDensity,
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout_rounded),
                    ),
                  ],
                ),
          body: IndexedStack(
            index: safeTab,
            children: [for (final key in layout.primary) _pageFor(key)],
          ),
          bottomNavigationBar: OwnerDashBottomNav(
            selectedIndex: safeTab,
            onDestinationSelected: (v) => setState(() {
              if (v == tab && layout.primary[v] == 'more') _morePage = null;
              tab = v;
              if (layout.primary[v] != 'more') _morePage = null;
            }),
            items: [
              for (final key in layout.primary)
                OwnerDashNavItem(
                  icon: _kResidentDests[key]!.icon,
                  selectedIcon: _kResidentDests[key]!.selectedIcon,
                  label: _kResidentDests[key]!.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget ownerDashboard() {
    return FutureBuilder<ResidentProfileBundle>(
      future: _profileFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 4, showHeader: true);
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            title: 'Could not load your flat',
            onRetry: refresh,
          );
        }
        final ctx = snap.data?.context ?? home;
        final name = ctx.access.displayName;
        final flat = ctx.flat;
        final roleLabel = ctx.access.isTenantSession ? 'Tenant' : 'Owner';
        final first = name.split(' ').first;
        final below = <Widget>[
          if (ctx.hasMultipleFlats) ...[
            PickerField(
              label: 'Active flat',
              icon: Icons.apartment_outlined,
              value: _flatOptionLabel(ctx.selectedFlat),
              onTap: () => _showFlatPicker(ctx),
            ),
            const SizedBox(height: 16),
          ],
          if (ctx.access.canFinance && !ctx.access.canResidential) ...[
            const OwnerDashAdvisory(
              'This flat is tenant occupied. Your account has financial access only — visitor and residential features are with the active tenant.',
            ),
            const SizedBox(height: 16),
          ],
          if (!ctx.access.canFinance && ctx.access.canResidential) ...[
            const OwnerDashAdvisory(
              'You manage day-to-day residential features for this flat. Maintenance bills and payments stay with the owner.',
            ),
            const SizedBox(height: 16),
          ],
        ];
        final quick = <OwnerDashQuickItem>[
          if (ctx.access.canFinance)
            OwnerDashQuickItem(
              icon: Icons.receipt_long_outlined,
              label: 'Bills',
              iconColor: OwnerDash.navy,
              wellColor: OwnerDash.skyWell,
              onTap: () => _open('bills'),
            ),
          if (ctx.access.canFinance)
            OwnerDashQuickItem(
              icon: Icons.celebration_outlined,
              label: 'Collections',
              iconColor: OwnerDash.amberIcon,
              wellColor: OwnerDash.amberWell,
              onTap: () => _open('collections'),
            ),
          if (ctx.access.canResidential)
            OwnerDashQuickItem(
              icon: Icons.groups_outlined,
              label: 'Visitors',
              iconColor: OwnerDash.indigoIcon,
              wellColor: OwnerDash.indigoWell,
              onTap: () => _open('visitors'),
            ),
          if (ctx.access.canResidential)
            OwnerDashQuickItem(
              icon: Icons.directions_car_outlined,
              label: 'Vehicles',
              iconColor: OwnerDash.tealIcon,
              wellColor: OwnerDash.tealWell,
              onTap: () => _open('vehicles'),
            ),
        ];

        return OwnerDashboardOverview(
          greeting: dayGreeting(),
          roleLabel: roleLabel,
          firstName: first.isEmpty ? name : first,
          societyName: kSocietyName,
          flatTitle: 'Flat ${ctx.flatNumber} · ${ctx.wingLabel}',
          flatSubtitle: 'Floor ${flat.floor} · ${ctx.occupancyLabel}',
          showBell: access.canResidential,
          quickItems: quick,
          maintenanceCard: ctx.access.canFinance ? _duesHero(flat) : null,
          collectionsCard: ctx.access.canFinance ? _collectionsHero() : null,
          fallbackCard: ctx.access.canFinance ? null : _flatCard(ctx),
          showOfflineNotice:
              ctx.access.canFinance && !kResidentOnlinePaymentsEnabled,
          below: below,
          onRefresh: () async {
            refresh();
            await _profileFuture;
          },
        );
      },
    );
  }

  String _residentToolHint(String key) {
    switch (key) {
      case 'bills':
        return 'Current and previous maintenance';
      case 'payments':
        return 'History and receipts';
      case 'collections':
        return 'One-time and special charges';
      case 'visitors':
        return 'Approve or deny entry';
      case 'vehicles':
        return 'Registered vehicles';
      case 'news':
        return 'Notices from the society';
      case 'profile':
        return 'Account and this flat';
      default:
        return '';
    }
  }

  /// Outstanding dues from the live billing API for the selected flat.
  Widget _duesHero(FlatSummary flat) {
    return FutureBuilder<List<Bill>>(
      future: _duesFuture,
      builder: (context, snap) {
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        if (snap.hasError) {
          return AppCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MAINTENANCE DUE',
                  style: T.label.copyWith(color: C.faint, letterSpacing: 0.8)),
              const SizedBox(height: 6),
              Text(money(flat.maintenanceRate), style: T.display),
              const SizedBox(height: 6),
              const Text('Outstanding dues could not be loaded.',
                  style: T.secondary),
              const SizedBox(height: 14),
              SecondaryButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: () =>
                    setState(() => _duesFuture = _loadDues(force: true)),
              ),
            ]),
          );
        }
        final bills = snap.data ?? const <Bill>[];
        final duePaise =
            bills.fold<int>(0, (sum, b) => sum + billAmountDuePaise(b));
        final overdue = bills.where((b) {
          final due = DateTime.tryParse(b.dueDate);
          return due != null && due.isBefore(DateTime.now());
        }).length;
        return OwnerDashAmountCard(
          label: 'Maintenance due',
          amount: loading ? '—' : moneyPaise(duePaise),
          subtitle: loading
              ? 'Checking your bills…'
              : bills.isEmpty
                  ? 'No pending bills. Monthly ${money(flat.maintenanceRate)}.'
                  : '${bills.length} open ${bills.length == 1 ? 'bill' : 'bills'}'
                      '${overdue > 0 ? ' · $overdue overdue' : ''}'
                      ' · ${money(flat.maintenanceRate)}/mo',
          badge: loading
              ? null
              : bills.isEmpty
                  ? 'Settled'
                  : (overdue > 0 ? 'Overdue' : 'Pending'),
          badgeTone: bills.isEmpty
              ? BadgeTone.success
              : (overdue > 0 ? BadgeTone.danger : BadgeTone.warning),
          loading: loading,
          actionLabel: bills.isEmpty || !kResidentOnlinePaymentsEnabled
              ? 'View bills'
              : 'Pay now',
          actionIcon: Icons.receipt_long_outlined,
          onAction: () => _open('bills'),
        );
      },
    );
  }

  Widget _collectionsHero() {
    return FutureBuilder<List<CollectionCharge>>(
      future: _collectionsFuture,
      builder: (context, snap) {
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        if (snap.hasError) {
          return AppCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ONE-TIME COLLECTIONS',
                  style: T.label.copyWith(color: C.faint, letterSpacing: 0.8)),
              const SizedBox(height: 6),
              const Text('Special collection dues could not be loaded.',
                  style: T.secondary),
              const SizedBox(height: 14),
              SecondaryButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: () => setState(
                    () => _collectionsFuture = _loadCollectionDues(force: true)),
              ),
            ]),
          );
        }
        final charges = snap.data ?? const <CollectionCharge>[];
        final duePaise =
            charges.fold<int>(0, (sum, row) => sum + row.outstandingPaise);
        final overdue = charges.where((row) => row.overdue).length;
        return OwnerDashAmountCard(
          label: 'One-time collections',
          amount: loading ? '—' : moneyPaise(duePaise),
          subtitle: loading
              ? 'Checking special collections…'
              : charges.isEmpty
                  ? 'No special collection is due on this flat.'
                  : charges.length == 1
                      ? '${charges.first.collectionTitle ?? 'Collection'} · due ${fmtIsoDate(charges.first.dueDate)}'
                      : '${charges.length} open charges'
                          '${overdue > 0 ? ' · $overdue overdue' : ''}',
          badge: loading
              ? null
              : charges.isEmpty
                  ? 'Settled'
                  : (overdue > 0 ? 'Overdue' : 'Pending'),
          badgeTone: charges.isEmpty
              ? BadgeTone.success
              : (overdue > 0 ? BadgeTone.danger : BadgeTone.warning),
          loading: loading,
          actionLabel: charges.isEmpty || !kResidentOnlinePaymentsEnabled
              ? 'View collections'
              : 'Pay now',
          actionIcon: Icons.celebration_outlined,
          onAction: () => _openCollectionPay(charges),
        );
      },
    );
  }

  Future<void> _openCollectionPay(List<CollectionCharge> charges) async {
    if (charges.length == 1) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              LiveOwnerCollectionChargePage(chargeId: charges.first.id),
        ),
      );
      if (mounted) {
        setState(() =>
            _collectionsFuture = _loadCollectionDues(force: true));
      }
      return;
    }
    _open('collections');
  }

  Widget _flatCard(ResidentHomeContext ctx) => AppCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const AppAvatar(
              icon: Icons.apartment_outlined, size: 48, square: true),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Flat ${ctx.flatNumber}', style: T.h3),
              const SizedBox(height: 2),
              Text(
                '${ctx.wingLabel} · Floor ${ctx.flat.floor} · ${flatTypeLabel(ctx.flat.flatType)}',
                style: T.secondary,
              ),
            ]),
          ),
          StatusBadge(ctx.flat.isActive ? 'Active' : 'Inactive'),
        ]),
      );

  String _flatOptionLabel(ResidentFlat f) =>
      '${f.flat.label}${f.access.role == 'TENANT' ? ' (tenant)' : ''}';

  Future<void> _showFlatPicker(ResidentHomeContext ctx) async {
    final picked = await showAppSheet<ResidentFlat>(
      context,
      title: 'Switch flat',
      builder: (sheet) => Column(children: [
        for (final f in ctx.accessibleFlats)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppAvatar(
              text: f.flat.wingCode ?? '?',
              size: 40,
              square: true,
              color: f.flat.id == ctx.selectedFlat.flat.id ? C.blue : C.muted,
            ),
            title: Text(_flatOptionLabel(f), style: T.bodyStrong),
            subtitle: Text(
              '${f.flat.wingName ?? 'Wing'} · ${f.access.role == 'TENANT' ? 'Tenant' : 'Owner'}'
              '${f.access.financial ? ' · financial' : ''}'
              '${f.access.residential ? ' · residential' : ''}',
            ),
            trailing: f.flat.id == ctx.selectedFlat.flat.id
                ? const Icon(Icons.check_circle_rounded, color: C.blue)
                : null,
            onTap: () => Navigator.pop(sheet, f),
          ),
      ]),
    );
    if (picked != null && picked.flat.id != ctx.selectedFlat.flat.id) {
      _selectFlat(picked);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await confirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need your username and password to sign in again.',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (ok) await logout();
  }

  Future<void> logout() async {
    final session = authSession;
    if (session != null) {
      await performLogout(session);
    } else {
      clearLiveRepositories();
      await SessionStore.clear();
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, unsignedInRoute(), (_) => false);
  }
}

class ResidentProfileBundle {
  const ResidentProfileBundle({required this.context});
  final ResidentHomeContext context;
}

class ResidentProfilePage extends StatelessWidget {
  const ResidentProfilePage({
    super.key,
    required this.home,
    required this.onLogout,
    this.onRefresh,
    this.onSelectFlat,
  });

  final ResidentHomeContext home;
  final VoidCallback onLogout;
  final VoidCallback? onRefresh;
  final ValueChanged<ResidentFlat>? onSelectFlat;

  @override
  Widget build(BuildContext context) {
    final access = home.access;
    final flat = home.flat;
    final isTenant = access.isTenantSession;
    final phone = home.profile.displayPhone;
    final permissions = <String>[
      if (access.canFinance) 'Financial',
      if (access.canResidential) 'Residential',
    ];
    return RefreshIndicator(
      color: C.blue,
      onRefresh: () async => onRefresh?.call(),
      child: ListView(padding: Sp.pagePadding, children: [
        DetailHero(
          title: access.displayName,
          subtitle: '${home.wingLabel} · Flat ${home.flatNumber}',
          leading: AppAvatar(
            text: initialsOf(access.displayName),
            size: Sz.avatarLg,
          ),
          badges: [
            StatusBadge(isTenant ? 'Tenant account' : 'Owner account',
                tone: BadgeTone.info),
            StatusBadge(home.occupancyLabel, tone: BadgeTone.neutral),
            if (permissions.isNotEmpty)
              StatusBadge(permissions.join(' · '), tone: BadgeTone.success),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(title: 'Contact', children: [
          SettingsRow(
            icon: Icons.phone_android_outlined,
            title: isTenant ? 'Tenant phone' : 'Owner phone',
            value: phone,
          ),
          if (home.profile.email.isNotEmpty)
            SettingsRow(
              icon: Icons.email_outlined,
              title: 'Email (notifications)',
              value: home.profile.email,
            ),
        ]),
        SettingsGroup(title: 'This flat', children: [
          SettingsRow(
            icon: Icons.home_work_outlined,
            title: 'Occupancy',
            value: home.occupancyLabel,
          ),
          SettingsRow(
            icon: Icons.layers_outlined,
            title: 'Floor',
            value: '${flat.floor}',
          ),
          SettingsRow(
            icon: Icons.apartment_outlined,
            title: 'Flat type',
            value: flatTypeLabel(flat.flatType),
          ),
          if (access.canFinance)
            SettingsRow(
              icon: Icons.currency_rupee_rounded,
              title: 'Monthly maintenance',
              value: money(flat.maintenanceRate),
            ),
          SettingsRow(
            icon: Icons.verified_user_outlined,
            title: 'Flat status',
            trailing: StatusBadge(flat.isActive ? 'Active' : 'Inactive'),
          ),
        ]),
        if (home.hasMultipleFlats) ...[
          const SectionTitle('Switch flat',
              subtitle: 'Tap another flat to make it active'),
          SettingsGroup(title: 'Accessible flats', children: [
            for (final item in home.accessibleFlats)
              SettingsRow(
                icon: item.flat.id == flat.id
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                title: item.flat.label,
                value:
                    '${item.flat.wingName ?? item.flat.wingCode ?? 'Wing'} · '
                    '${item.access.role == 'TENANT' ? 'Tenant' : 'Owner'}'
                    '${item.access.financial ? ' · financial' : ''}'
                    '${item.access.residential ? ' · residential' : ''}',
                trailing: item.flat.id == flat.id
                    ? const StatusBadge('Active', tone: BadgeTone.info)
                    : null,
                onTap: onSelectFlat == null || item.flat.id == flat.id
                    ? null
                    : () => onSelectFlat!(item),
              ),
          ]),
        ],
        const SizedBox(height: 8),
        SettingsGroup(title: 'Account', children: [
          SettingsRow(
            icon: Icons.logout_rounded,
            title: 'Log out',
            value: 'Requires username and password to sign in again',
            onTap: () async {
              final ok = await confirmDialog(
                context,
                title: 'Log out?',
                message:
                    'You will need your username and password to sign in again.',
                confirmLabel: 'Log out',
                icon: Icons.logout_rounded,
              );
              if (ok) onLogout();
            },
          ),
        ]),
        const SizedBox(height: 16),
        Text('$kAppName · $kSocietyName',
            textAlign: TextAlign.center,
            style: T.caption.copyWith(color: C.faint)),
      ]),
    );
  }
}


class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminDashboardBundle {
  const _AdminDashboardBundle({
    required this.society,
    required this.dashboard,
  });
  final SocietySummary society;
  final DashboardStats dashboard;
}

class _AdminHomeState extends State<AdminHome> {
  int tab = 0;
  String? _morePage;
  late Future<_AdminDashboardBundle> _dashboardFuture = _loadDashboard();

  static String _moreLabel(String key) => adminMoreLabel(key);

  Future<_AdminDashboardBundle> _loadDashboard({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final results = await Future.wait([
      repos.society.society(force: force),
      repos.society.dashboard(force: force),
    ]);
    return _AdminDashboardBundle(
      society: results[0] as SocietySummary,
      dashboard: results[1] as DashboardStats,
    );
  }

  void refresh() {
    if (!mounted) return;
    setState(() {});
  }

  void reloadDashboard() {
    if (!mounted) return;
    setState(() {
      _dashboardFuture = _loadDashboard(force: true);
    });
  }

  Future<void> _confirmLogout() async {
    final ok = await confirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need your username and password to sign in again.',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (ok) await logout();
  }

  Future<void> _confirmSwitchSociety() async {
    final ok = await confirmDialog(
      context,
      title: 'Switch society?',
      message: 'You will be signed out and can pick another society.',
      confirmLabel: 'Switch',
      icon: Icons.swap_horiz_rounded,
    );
    if (ok) await logout();
  }

  Future<void> logout() async {
    final session = authSession;
    if (session != null) {
      await performLogout(session);
    } else {
      clearLiveRepositories();
      await SessionStore.clear();
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, unsignedInRoute(), (_) => false);
  }

  void _openMore(String key) => setState(() {
        tab = 4;
        _morePage = key;
      });

  Widget _adminMoreBody({
    SocietySummary? society,
    DashboardStats? dashboard,
  }) {
    switch (_morePage) {
      case 'residents':
        return const AdminResidentsPage();
      case 'visitors':
        return const LiveAdminVisitorsPage();
      case 'vehicles':
        return const LiveAdminVehiclesPage();
      case 'guards':
        return const LiveAdminGuardsPage();
      case 'announcements':
        return const LiveAdminAnnouncementsPage();
      case 'additional-services':
        return const LiveAdditionalServicesPage(embedded: true);
      case 'collections':
        return const LiveAdminCollectionsPage(embedded: true);
      case 'reports':
        return const LiveAdminReportsPage();
      case 'settings':
        return const AdminSettingsPage();
      default:
        return ColoredBox(
          color: AdminDash.surface,
          child: AdminMoreHub(
            society: society,
            dashboard: dashboard,
            onOpen: _openMore,
            onExport: () => _openMore('reports'),
            onSwitchSociety: _confirmSwitchSociety,
            onSignOut: _confirmLogout,
            onRefresh: () async {
              reloadDashboard();
              await _dashboardFuture;
            },
          ),
        );
    }
  }

  bool get _canPopInternally => _morePage != null || tab != 0;

  void _popInternally() => setState(() {
        if (_morePage != null) {
          _morePage = null;
        } else {
          tab = 0;
        }
      });

  @override
  Widget build(BuildContext context) {
    final inSubPage = tab == 4 && _morePage != null;
    return FutureBuilder<_AdminDashboardBundle>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        final societyName = snapshot.data?.society.name ?? kSocietyName;
        return PopScope(
          canPop: !_canPopInternally,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _popInternally();
          },
          child: Scaffold(
            backgroundColor: AdminDash.surface,
            body: Column(
              children: [
                AdminDashHeader(
                  societyName: societyName,
                  backLabel: inSubPage ? _moreLabel(_morePage!) : null,
                  onBack: inSubPage ? _popInternally : null,
                  onSocietyTap: () => _openMore('settings'),
                  onProfileTap: _confirmLogout,
                ),
                Expanded(
                  child: IndexedStack(
                    index: tab,
                    children: [
                      adminDashboard(),
                      AdminFlatsPage(onChanged: refresh),
                      const LiveAdminBillsPage(),
                      const LiveAdminPaymentsPage(),
                      _adminMoreBody(
                        society: snapshot.data?.society,
                        dashboard: snapshot.data?.dashboard,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: AdminDashBottomNav(
              selectedIndex: tab,
              onDestinationSelected: (v) => setState(() {
                if (v == 4 && tab == 4) _morePage = null;
                tab = v;
                if (v != 4) _morePage = null;
                if (v == 0) reloadDashboard();
              }),
            ),
          ),
        );
      },
    );
  }

  Widget adminDashboard() => FutureBuilder<_AdminDashboardBundle>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 4, showHeader: true);
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load dashboard',
              onRetry: reloadDashboard,
            );
          }
          final bundle = snapshot.data;
          if (bundle == null) {
            return LoadFailure(
              error: StateError('Dashboard returned no data.'),
              title: 'Could not load dashboard',
              onRetry: reloadDashboard,
            );
          }
          return AdminDashboardOverview(
            society: bundle.society,
            dashboard: bundle.dashboard,
            onOpenFlats: () => setState(() => tab = 1),
            onOpenBills: () => setState(() => tab = 2),
            onOpenPayments: () => setState(() => tab = 3),
            onOpenResidents: () => _openMore('residents'),
            onOpenGuards: () => _openMore('guards'),
            onOpenAnnouncements: () => _openMore('announcements'),
            onOpenCollections: () => _openMore('collections'),
            onOpenReports: () => _openMore('reports'),
            onOpenSettings: () => _openMore('settings'),
            onRefresh: () async {
              reloadDashboard();
              await _dashboardFuture;
            },
          );
        },
      );
}

class AdminFlatsPage extends StatefulWidget {
  const AdminFlatsPage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<AdminFlatsPage> createState() => _AdminFlatsPageState();
}

class _AdminFlatsPageState extends State<AdminFlatsPage> {
  String query = '';
  String? wingId;
  String occupancyFilter = 'all'; // all | owner | tenant | vacant
  String activeFilter = 'all'; // all | active | inactive
  int page = 1;
  static const _limit = 30;
  late Future<_AdminFlatsBundle> _future;
  final _searchDebounce = Debouncer();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_AdminFlatsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    bool? isActive;
    if (activeFilter == 'active') isActive = true;
    if (activeFilter == 'inactive') isActive = false;
    String? occupancy;
    if (occupancyFilter == 'owner') occupancy = 'OWNER_OCCUPIED';
    if (occupancyFilter == 'tenant') occupancy = 'TENANT_OCCUPIED';
    if (occupancyFilter == 'vacant') occupancy = 'VACANT';
    final results = await Future.wait([
      repos.society.wings(force: force),
      repos.society.listFlats(
        force: force,
        query: ListFlatsQuery(
          wingId: wingId,
          isActive: isActive,
          occupancyStatus: occupancy,
          search: query.trim().isEmpty ? null : query.trim(),
          page: page,
          limit: _limit,
          sortBy: 'number',
          sortOrder: 'asc',
        ),
      ),
      repos.society.dashboard(force: force),
    ]);
    return _AdminFlatsBundle(
      wings: results[0] as List<WingSummary>,
      flats: results[1] as Paged<FlatSummary>,
      dashboard: results[2] as DashboardStats,
    );
  }

  void reload({bool resetPage = false}) {
    if (resetPage) page = 1;
    setState(() {
      _future = _load(force: true);
    });
    widget.onChanged();
  }

  Future<void> openDetail(FlatSummary flat) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => AdminFlatDetailPage(flatId: flat.id)),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AdminFlatsBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 6);
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load flats',
              onRetry: () => reload(resetPage: true),
            );
          }
          final bundle = snapshot.data!;
          final wings = bundle.wings;
          final pageData = bundle.flats;
          final rows = pageData.items;
          final pagination = pageData.pagination;
          return ColoredBox(
            color: AdminDash.surface,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  children: [
                    AdminFlatsSearchBar(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        query = v;
                        _searchDebounce.run(() => reload(resetPage: true));
                      },
                      onClear: () {
                        _searchCtrl.clear();
                        query = '';
                        reload(resetPage: true);
                      },
                      onTune: () async {
                        final next = await showAdminFlatsTuneSheet(
                          context,
                          activeFilter: activeFilter,
                        );
                        if (next == null || !mounted) return;
                        activeFilter = next;
                        reload(resetPage: true);
                      },
                    ),
                    const SizedBox(height: 12),
                    AdminFlatsWingChips(
                      wings: wings,
                      selectedWingId: wingId,
                      onSelect: (id) {
                        wingId = id;
                        reload(resetPage: true);
                      },
                    ),
                    const SizedBox(height: 10),
                    AdminFlatsStatusRow(
                      selected: occupancyFilter,
                      unitCount: pagination.total,
                      onSelect: (value) {
                        occupancyFilter = value;
                        reload(resetPage: true);
                      },
                    ),
                    const SizedBox(height: 12),
                    AdminFlatsSummaryStrip(totals: bundle.dashboard.totals),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? AdminFlatsEmpty(
                        onReset: () {
                          _searchCtrl.clear();
                          query = '';
                          wingId = null;
                          occupancyFilter = 'all';
                          activeFilter = 'all';
                          reload(resetPage: true);
                        },
                      )
                    : RefreshIndicator(
                        color: AdminDash.primary,
                        onRefresh: () async {
                          reload(resetPage: true);
                          await _future;
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: rows.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            if (i == rows.length) {
                              return PaginationBar(
                                page: pagination.page,
                                totalPages: pagination.totalPages,
                                onPrevious: () {
                                  page -= 1;
                                  reload();
                                },
                                onNext: () {
                                  page += 1;
                                  reload();
                                },
                              );
                            }
                            return AdminFlatUnitCard(
                              flat: rows[i],
                              onTap: () => openDetail(rows[i]),
                            );
                          },
                        ),
                      ),
              ),
            ]),
          );
        },
      );
}

class _AdminFlatsBundle {
  const _AdminFlatsBundle({
    required this.wings,
    required this.flats,
    required this.dashboard,
  });
  final List<WingSummary> wings;
  final Paged<FlatSummary> flats;
  final DashboardStats dashboard;
}

class AdminFlatDetailPage extends StatefulWidget {
  const AdminFlatDetailPage({super.key, required this.flatId});
  final String flatId;
  @override
  State<AdminFlatDetailPage> createState() => _AdminFlatDetailPageState();
}

class _AdminFlatDetailPageState extends State<AdminFlatDetailPage> {
  late Future<_FlatDetailBundle> _future = _load();
  bool busy = false;

  Future<_FlatDetailBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final flat = await repos.society.flat(widget.flatId, force: force);
    final history = await repos.society.occupancyHistory(
      widget.flatId,
      force: force,
    );
    final services = await repos.billing.listAdditionalServices(
      flatId: widget.flatId,
      force: force,
      limit: 200,
    );
    final bills = await repos.billing.listAdminBills(
      force: force,
      query: ListBillsQuery(flatId: widget.flatId, limit: 20),
    );
    return _FlatDetailBundle(
      flat: flat,
      history: history,
      services: services.items,
      bills: bills.items,
    );
  }

  void _reload() {
    setState(() {
      _future = _load(force: true);
    });
  }

  Future<void> _openService(AdditionalService service) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAdditionalServiceFormPage(
          existing: service,
          presetFlatId: widget.flatId,
        ),
      ),
    );
    if (ok == true && mounted) _reload();
  }

  Future<void> _addService(List<AdditionalService> services) async {
    if (!canAddActiveAdditionalService(services)) {
      showAppSnack(
        context,
        kAdditionalServiceLimitMessage,
        tone: SnackTone.warning,
      );
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAdditionalServiceFormPage(
          presetFlatId: widget.flatId,
        ),
      ),
    );
    if (ok == true && mounted) _reload();
  }

  Future<void> _openBill(Bill bill) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAdminBillDetailPage(billId: bill.id),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _assign(String role) async {
    final user = await Navigator.push<AdminUser>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPickResidentPage(role: role),
      ),
    );
    if (user == null || !mounted) return;
    final assigned = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AssignOccupancyPage(
          role: role,
          user: user,
          flatId: widget.flatId,
        ),
      ),
    );
    if (assigned == true && mounted) _reload();
  }

  Future<void> _end({required bool owner}) async {
    final reason = await promptTextDialog(
      context,
      title: owner ? 'End owner occupancy' : 'End tenant occupancy',
      message: owner
          ? 'The flat becomes vacant from today. This is recorded in occupancy history.'
          : 'The flat returns to owner occupied from today. This is recorded in occupancy history.',
      label: 'Reason',
      hint: 'e.g. Flat sold, lease ended',
      confirmLabel: 'End occupancy',
      required: true,
      minLength: 3,
      maxLines: 3,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    setState(() => busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repos = ensureLiveRepositories(session.api);
      if (owner) {
        await repos.society.endOwnerOccupancy(
          widget.flatId,
          effectiveTo: DateTime.now(),
          reason: reason,
        );
      } else {
        await repos.society.endTenantOccupancy(
          widget.flatId,
          effectiveTo: DateTime.now(),
          reason: reason,
        );
      }
      repos.invalidateAfterResidentMutation(flatId: widget.flatId);
      if (!mounted) return;
      showSuccessSnack(context,
          owner ? 'Owner occupancy ended.' : 'Tenant occupancy ended.');
      _reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, adminApiErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Flat details'),
        backgroundColor: const Color(0xFFF6F8FC),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<_FlatDetailBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const LoadingView(label: 'Loading flat…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              title: 'Could not load flat',
              onRetry: _reload,
            );
          }
          final flat = snap.data!.flat;
          final history = snap.data!.history;
          final status = flat.occupancyStatus.toUpperCase();
          final canAssignOwner = status == 'VACANT';
          final canAssignTenant = status == 'OWNER_OCCUPIED';
          final canEndTenant = status == 'TENANT_OCCUPIED';
          final canEndOwner =
              status == 'OWNER_OCCUPIED' && flat.activeTenant == null;
          final String? stepLabel;
          final String? stepCaption;
          final IconData? stepIcon;
          final VoidCallback? stepAction;
          if (canAssignOwner) {
            stepLabel = 'Assign owner';
            stepCaption = 'Pick an owner account for this flat';
            stepIcon = Icons.person_add_alt_1_outlined;
            stepAction = () => _assign('OWNER');
          } else if (canAssignTenant) {
            stepLabel = 'Assign tenant';
            stepCaption = 'Residential access moves to the tenant';
            stepIcon = Icons.group_add_outlined;
            stepAction = () => _assign('TENANT');
          } else if (canEndTenant) {
            stepLabel = 'End tenant occupancy';
            stepCaption = 'Flat returns to owner occupied';
            stepIcon = Icons.person_remove_outlined;
            stepAction = () => _end(owner: false);
          } else if (canEndOwner) {
            stepLabel = 'End owner occupancy';
            stepCaption = 'Flat becomes vacant';
            stepIcon = Icons.home_work_outlined;
            stepAction = () => _end(owner: true);
          } else {
            stepLabel = null;
            stepCaption = null;
            stepIcon = null;
            stepAction = null;
          }
          return RefreshIndicator(
            color: const Color(0xFF153B69),
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: AdminFlatDetailBody(
              flat: flat,
              history: history,
              services: snap.data!.services,
              bills: snap.data!.bills,
              busy: busy,
              ownerActionLabel: canAssignOwner ? 'Add' : null,
              onOwnerAction:
                  canAssignOwner ? () => _assign('OWNER') : null,
              tenantActionLabel: canAssignTenant ? 'Add' : null,
              onTenantAction:
                  canAssignTenant ? () => _assign('TENANT') : null,
              occupancyStepLabel: stepLabel,
              occupancyStepCaption: stepCaption,
              occupancyStepIcon: stepIcon,
              onOccupancyStep: stepAction,
              onAddService: () => _addService(snap.data!.services),
              onOpenService: _openService,
              onOpenBill: _openBill,
            ),
          );
        },
      ),
    );
  }
}

class _FlatDetailBundle {
  const _FlatDetailBundle({
    required this.flat,
    required this.history,
    this.services = const [],
    this.bills = const [],
  });
  final FlatSummary flat;
  final AdminOccupancyHistory history;
  final List<AdditionalService> services;
  final List<Bill> bills;
}


class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  late Future<SocietyConfiguration> _configFuture = _loadConfig();

  Future<SocietyConfiguration> _loadConfig({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .society
        .configuration(force: force);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SocietyConfiguration>(
        future: _configFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const SkeletonList(items: 5, showHeader: true);
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              title: 'Could not load society',
              onRetry: () =>
                  setState(() => _configFuture = _loadConfig(force: true)),
            );
          }
          final config = snap.data!;
          final society = config.society;
          final totals = config.totals;
          final address = [
            if ((society.address ?? '').trim().isNotEmpty) society.address,
            if ((society.city ?? '').trim().isNotEmpty) society.city,
            if ((society.state ?? '').trim().isNotEmpty) society.state,
            if ((society.pincode ?? '').trim().isNotEmpty) society.pincode,
          ].whereType<String>().join(', ');
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _configFuture = _loadConfig(force: true));
              await _configFuture;
            },
            child: ListView(padding: Sp.pagePadding, children: [
              DetailHero(
                title: society.name,
                subtitle: 'Code ${society.code}',
                leading: const BrandLogo(size: 52, radius: 12),
                badges: [
                  StatusBadge('${totals.wings} wings', tone: BadgeTone.info),
                  StatusBadge('${totals.flats} flats', tone: BadgeTone.neutral),
                ],
              ),
              const SizedBox(height: 16),
              MetricBand(items: [
                MetricItem('Flats', '${totals.flats}'),
                MetricItem('Wings', '${totals.wings}'),
                MetricItem('Monthly maintenance',
                    money(totals.monthlyMaintenanceTotal)),
              ]),
              const SizedBox(height: 16),
              SettingsGroup(title: 'Society', children: [
                SettingsRow(
                    icon: Icons.location_on_outlined,
                    title: 'Address',
                    value: address.isEmpty ? '—' : address),
                SettingsRow(
                    icon: Icons.email_outlined,
                    title: 'Contact email',
                    value: society.contactEmail ?? '—'),
                SettingsRow(
                    icon: Icons.phone_outlined,
                    title: 'Contact phone',
                    value: society.contactPhone ?? '—'),
              ]),
              SettingsGroup(title: 'Billing policy', children: [
                SettingsRow(
                    icon: Icons.event_outlined,
                    title: 'Maintenance day of month',
                    value: '${society.maintenanceDayOfMonth}'),
                SettingsRow(
                    icon: Icons.schedule_outlined,
                    title: 'Timezone · currency',
                    value: '${society.timezone} · ${society.currency}'),
              ]),
              const InfoNote(
                'Late interest for live bills is calculated by the server. '
                'This screen does not change the rate.',
              ),
              const SizedBox(height: 20),
              const SectionTitle('Wings',
                  subtitle: 'Structure is managed on the server'),
              if (config.wings.isEmpty)
                const EmptyState('No wings yet',
                    icon: Icons.domain_outlined, compact: true)
              else
                AppCard(
                  margin: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < config.wings.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 56, endIndent: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(children: [
                          AppAvatar(
                              text: config.wings[i].code,
                              square: true,
                              size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(config.wings[i].name, style: T.bodyStrong),
                                const SizedBox(height: 2),
                                Text(
                                  '${config.wings[i].flatCount} flats · ${config.wings[i].floors} floors · ${config.wings[i].flatsPerFloor} per floor',
                                  style: T.caption,
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
            ]),
          );
        },
      );
}

