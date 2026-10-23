import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/auth/app_role.dart';
import 'api/auth/auth_messages.dart';
import 'api/auth/auth_session.dart';
import 'api/auth/home_resolver.dart';
import 'api/socket/visitor_socket.dart';
import 'services/push_notification_service.dart';
import 'api/models/billing_models.dart'
    show
        AdditionalService,
        Bill,
        ListBillsQuery,
        activeAdditionalServiceCount,
        billAmountDuePaise,
        canAddActiveAdditionalService,
        kAdditionalServiceLimitMessage,
        kMaxActiveAdditionalServicesPerFlat;
import 'api/models/common.dart' show Paged;
import 'api/models/resident_home_context.dart';
import 'api/models/resident_models.dart';
import 'api/models/society_models.dart';
import 'api/repositories/live_repositories.dart';
import 'app_core.dart';
import 'data/local_database.dart' show LocalDatabase;
import 'api/auth/admin_api_messages.dart';
import 'api/models/admin_user_models.dart';
import 'features/billing/collect_payment_page.dart';
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
import 'services/bill_pdf.dart';
import 'services/occupancy_access.dart';
import 'services/receipt_pdf.dart';
import 'services/session_store.dart';
import 'ui/components.dart';
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

Future<void> exportBillPdf(BuildContext context, dynamic row,
    {bool preview = false}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final billId = row.read<int>('id') as int;
    final status = row.read<String>('status');
    final payment = status == 'paid' ? await db.paymentForBill(billId) : null;
    final address = await db.appSetting('society_address') ?? kSocietyAddress;
    final map = Map<String, dynamic>.from(row.data as Map);
    if (preview) {
      await BillPdf.preview(
        bill: map,
        paymentDate: payment?.read<String>('paid_at'),
        transactionRef: payment?.read<String>('receipt_number'),
        address: address,
      );
    } else {
      await BillPdf.share(
        bill: map,
        paymentDate: payment?.read<String>('paid_at'),
        transactionRef: payment?.read<String>('receipt_number'),
        address: address,
      );
      messenger?.showSnackBar(const SnackBar(
          content: Text('Bill PDF ready to save or share.'),
          backgroundColor: C.green));
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(
      content: Text(
          'Could not create PDF. ${e is StateError ? e.message : 'Please try again.'}'),
      backgroundColor: Colors.red.shade700,
    ));
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
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const AppBootstrap(),
        routes: {
          '/login': (_) => const LoginScreen(),
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
  late Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = _initializeLocalDatabase();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _init,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _SplashScreen(label: 'Starting…');
          }
          if (snapshot.hasError) {
            return _SplashScreen(
              label: 'Could not start the app',
              error: '${snapshot.error}',
              onRetry: () => setState(() => _init = _initializeLocalDatabase()),
            );
          }
          return const AuthGate();
        },
      );
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
    final session = ensureAuthSession();
    try {
      final profile = await session.restore();
      if (profile == null) {
        return const LoginScreen();
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
        return const LoginScreen();
      }
      rethrow;
    }
  }

  Widget _widgetForDestination(HomeDestination destination) {
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

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
        future: _boot,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _SplashScreen(
              label: 'Could not restore your session',
              error:
                  '${authErrorMessage(snapshot.error!)}\n\nYour sign-in was kept. Check your connection and try again.',
              onRetry: () => setState(() => _boot = _resolveHome()),
            );
          }
          if (!snapshot.hasData) {
            return const _SplashScreen(label: 'Opening your society…');
          }
          return snapshot.data!;
        },
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
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
    ('tenant', 'Flat Tenant', Icons.person_pin_circle_outlined),
    ('admin', 'Admin', Icons.admin_panel_settings_outlined),
    ('guard', 'Security Guard', Icons.shield_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    final remembered = await ensureAuthSession().readRememberedUsername();
    if (!mounted || remembered == null || remembered.isEmpty) return;
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

  void _onRoleChanged(String? value) {
    if (value == null || busy) return;
    setState(() {
      role = value;
      error = null;
    });
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: KeyboardDismissOnTap(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width < 360 ? 16 : 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                          child: const Icon(Icons.apartment_rounded,
                              color: Colors.white, size: 26),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text('Welcome back', style: T.h1),
                      const SizedBox(height: 4),
                      const Text(
                        'Monarch Solitaire A to E',
                        style: T.bodyStrong,
                      ),
                      const SizedBox(height: 4),
                      const Text(kAppTagline, style: T.secondary),
                      const SizedBox(height: 22),
                      const Text('Login As', style: T.title),
                      const SizedBox(height: 4),
                      const Text(
                        'Your account role is confirmed by the server. This only sets the sign-in context.',
                        style: T.caption,
                      ),
                      const SizedBox(height: 12),
                      _roleChooser(),
                      const SizedBox(height: 20),
                      TextField(
                        controller: username,
                        enabled: !busy,
                        autofocus: true,
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
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline_rounded),
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
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: busy
                                ? null
                                : () => setState(
                                      () => obscurePassword = !obscurePassword,
                                    ),
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onChanged: (_) {
                          if (error != null) setState(() => error = null);
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(
                            onTap: busy
                                ? null
                                : () =>
                                    setState(() => rememberMe = !rememberMe),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Checkbox(
                                value: rememberMe,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: busy
                                    ? null
                                    : (value) => setState(
                                          () => rememberMe = value ?? false,
                                        ),
                              ),
                              const SizedBox(width: 4),
                              const Text('Remember me', style: T.body),
                            ]),
                          ),
                          TextButton(
                            onPressed: busy ? null : _showForgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ],
                      ),
                      InlineError(error),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Login',
                        icon: Icons.login_rounded,
                        busy: busy,
                        onPressed: submitLogin,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Having trouble? Contact your society admin.',
                        textAlign: TextAlign.center,
                        style: T.caption.copyWith(color: C.faint),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Username & password · SkyLine Tech Ventures',
                        textAlign: TextAlign.center,
                        style: T.caption.copyWith(color: C.faint),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _roleChooser() => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 360;
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
        if (!wide) {
          return Column(children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              tiles[i],
            ],
          ]);
        }
        return Column(children: [
          Row(children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 8),
            Expanded(child: tiles[1]),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: tiles[2]),
            const SizedBox(width: 8),
            Expanded(child: tiles[3]),
          ]),
        ]);
      });
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
        MaterialPageRoute(builder: (_) => const LoginScreen()),
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
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
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
      color: selected ? C.chip : C.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rd.xl),
        side: BorderSide(
            color: selected ? C.blue : C.line, width: selected ? 1.4 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              IconWell(
                icon: icon,
                color: selected ? C.blue : C.muted,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style:
                      T.bodyStrong.copyWith(color: selected ? C.blue : C.navy),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
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

  OccupancyAccess get access => home.access;

  @override
  void initState() {
    super.initState();
    home = widget.home;
    // Keep create flows (vehicles) in sync with the selected flat.
    authSession?.selectResidentFlat(home.selectedFlat.flat.id);
    _profileFuture = _loadProfileBundle();
    _duesFuture = access.canFinance ? _loadDues() : null;
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

  void refresh() {
    if (!mounted) return;
    setState(() {
      _profileFuture = _loadProfileBundle(force: true);
      _duesFuture = access.canFinance ? _loadDues(force: true) : null;
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
    return ListView(
      padding: Sp.pagePadding,
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          homeChrome ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: PopScope(
        canPop: !_canPopInternally,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _popInternally();
        },
        child: Scaffold(
          appBar: homeChrome
              ? null
              : AppBar(
                  leading: inSubPage
                      ? IconButton(
                          tooltip: 'Back',
                          onPressed: _popInternally,
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      : null,
                  title: inSubPage
                      ? Text(_titleForBar)
                      : brandAppBarTitle(
                          title: _titleForBar, subtitle: kSocietyName),
                  actions: [
                    if (access.canResidential)
                      const LiveNotificationBellButton(),
                    if (layout.more.contains('profile'))
                      IconButton(
                        tooltip: 'Profile',
                        onPressed: () => _open('profile'),
                        icon: const Icon(Icons.account_circle_outlined),
                      ),
                    IconButton(
                      tooltip: 'Logout',
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout_rounded),
                    ),
                  ],
                ),
          body: IndexedStack(
            index: safeTab,
            children: [for (final key in layout.primary) _pageFor(key)],
          ),
          bottomNavigationBar: AppBottomNav(
            selectedIndex: safeTab,
            onDestinationSelected: (v) => setState(() {
              if (v == tab && layout.primary[v] == 'more') _morePage = null;
              tab = v;
              if (layout.primary[v] != 'more') _morePage = null;
            }),
            destinations: [
              for (final key in layout.primary)
                NavigationDestination(
                  icon: Icon(_kResidentDests[key]!.icon),
                  selectedIcon: Icon(_kResidentDests[key]!.selectedIcon),
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
        final layout = _layout;
        final services = <String>[
          for (final k in [...layout.primary, ...layout.more])
            if (k != 'home' && k != 'more' && k != 'profile') k,
        ];

        final quick = <QuickAccessItem>[
          if (ctx.access.canFinance)
            QuickAccessItem(
              icon: Icons.receipt_long_outlined,
              label: 'Pay bill',
              onTap: () => _open('bills'),
            ),
          if (ctx.access.canFinance)
            QuickAccessItem(
              icon: Icons.celebration_outlined,
              label: 'Collections',
              color: C.amber,
              onTap: () => _open('collections'),
            ),
          if (ctx.access.canResidential)
            QuickAccessItem(
              icon: Icons.groups_outlined,
              label: 'Visitors',
              color: C.softBlue,
              onTap: () => _open('visitors'),
            ),
          if (ctx.access.canResidential)
            QuickAccessItem(
              icon: Icons.directions_car_outlined,
              label: 'Vehicles',
              color: C.blueDark,
              onTap: () => _open('vehicles'),
            ),
          if (ctx.access.canResidential)
            QuickAccessItem(
              icon: Icons.campaign_outlined,
              label: 'Notices',
              color: C.amber,
              onTap: () => _open('news'),
            ),
        ];

        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            refresh();
            await _profileFuture;
          },
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              OverlapHero(
                header: ColoredBox(
                  color: C.blue,
                  child: SafeArea(
                    bottom: false,
                    child: PineHeader(
                      eyebrow: '${dayGreeting()} · $roleLabel',
                      title: name.split(' ').first,
                      subtitle: kSocietyName,
                      trailing: access.canResidential
                          ? const LiveNotificationBellButton(onPine: true)
                          : null,
                      bottomPadding: 52,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(Rd.xl),
                        ),
                        child: Row(children: [
                          const Icon(Icons.apartment_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Flat ${ctx.flatNumber} · ${ctx.wingLabel}',
                                    style: T.bodyStrong
                                        .copyWith(color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Floor ${flat.floor} · ${ctx.occupancyLabel}',
                                    style: T.caption.copyWith(
                                        color: Colors.white
                                            .withValues(alpha: 0.7)),
                                  ),
                                ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
                hero: ctx.access.canFinance ? _duesHero(flat) : _flatCard(ctx),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ctx.hasMultipleFlats) ...[
                        PickerField(
                          label: 'Active flat',
                          icon: Icons.apartment_outlined,
                          value: _flatOptionLabel(ctx.selectedFlat),
                          onTap: () => _showFlatPicker(ctx),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (ctx.access.canFinance && !ctx.access.canResidential)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: InfoNote(
                              'This flat is tenant occupied. Your account has financial access only — visitor and residential features are with the active tenant.'),
                        ),
                      if (!ctx.access.canFinance && ctx.access.canResidential)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: InfoNote(
                            'You manage day-to-day residential features for this flat. Maintenance bills and payments stay with the owner.',
                          ),
                        ),
                      if (quick.isNotEmpty) ...[
                        const SectionTitle('Quick access'),
                        QuickAccessGrid(items: quick),
                        const SizedBox(height: 22),
                      ],
                      ToolDirectory(
                        title: 'Also for this flat',
                        links: [
                          for (final key in services)
                            if (_showOnHome(key))
                              ToolLink(
                                icon: _kResidentDests[key]!.icon,
                                label: _kResidentDests[key]!.label,
                                subtitle: _residentToolHint(key),
                                onTap: () => _open(key),
                              ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const SectionTitle('Your flat'),
                      DetailCard(children: [
                        DetailRow('Flat', ctx.flatNumber),
                        DetailRow('Wing', ctx.wingLabel),
                        DetailRow('Floor', '${flat.floor}'),
                        DetailRow('Type', flatTypeLabel(flat.flatType)),
                        DetailRow('Occupancy', ctx.occupancyLabel),
                        DetailRow('Status', '',
                            valueWidget: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(
                                  flat.isActive ? 'Active' : 'Inactive'),
                            )),
                        if (ctx.access.canFinance)
                          DetailRow('Monthly maintenance',
                              money(flat.maintenanceRate),
                              emphasize: true),
                      ]),
                    ]),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Home already leads with dues (owner) or visitor actions (tenant).
  bool _showOnHome(String key) {
    if (access.canFinance && (key == 'bills' || key == 'payments')) {
      return false;
    }
    if (!access.canFinance && key == 'visitors') {
      return false;
    }
    return true;
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
        final due = duePaise > 0;
        return AppCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('MAINTENANCE DUE',
                    style:
                        T.label.copyWith(color: C.faint, letterSpacing: 0.8)),
              ),
              if (loading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                StatusBadge(
                  bills.isEmpty
                      ? 'Settled'
                      : (overdue > 0 ? 'Overdue' : 'Pending'),
                  tone: bills.isEmpty
                      ? BadgeTone.success
                      : (overdue > 0 ? BadgeTone.danger : BadgeTone.warning),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              loading ? '—' : moneyPaise(duePaise),
              style: T.display.copyWith(
                color: due ? C.error : C.navy,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loading
                  ? 'Checking your bills…'
                  : bills.isEmpty
                      ? 'No pending bills. Monthly ${money(flat.maintenanceRate)}.'
                      : '${bills.length} open ${bills.length == 1 ? 'bill' : 'bills'}'
                          '${overdue > 0 ? ' · $overdue overdue' : ''}'
                          ' · ${money(flat.maintenanceRate)}/mo',
              style: T.caption,
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: bills.isEmpty ? 'View bills' : 'Pay now',
              icon: Icons.payments_outlined,
              onPressed: () => _open('bills'),
            ),
          ]),
        );
      },
    );
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
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
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

String billNumberOf(dynamic row) {
  final v = row.data['bill_number'] as String?;
  if (v != null && v.isNotEmpty) return v;
  return 'AS-BILL-${row.read<int>('id')}';
}

String billingPeriodLabel(dynamic row) {
  final start =
      DateTime.tryParse(row.read<String>('period_start')) ?? DateTime.now();
  final months = (row.data['months_covered'] as int?) ?? 1;
  final endRaw = row.data['period_end'] as String?;
  final end =
      endRaw == null || endRaw.isEmpty ? null : DateTime.tryParse(endRaw);
  return maintenancePeriodLabel(
      startMonth: start, monthsCovered: months, periodEnd: end);
}

String billingPeriodLabelFromParts(
    String periodStart, int monthsCovered, String periodEnd) {
  return maintenancePeriodLabel(
    startMonth: DateTime.tryParse(periodStart) ?? DateTime.now(),
    monthsCovered: monthsCovered,
    periodEnd: DateTime.tryParse(periodEnd),
  );
}

Future<void> openCollectPayment(
  BuildContext context,
  dynamic bill,
  VoidCallback refresh, {
  bool ownerMode = false,
}) async {
  final status = bill.read<String>('status');
  if (status != 'pending' && status != 'overdue') return;
  final flatId = bill.read<int>('flat_id');
  final changed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => CollectPaymentPage(
          flatId: flatId, seedBill: bill, ownerMode: ownerMode),
    ),
  );
  if (changed == true) refresh();
}

Future<void> openPayAllOutstanding(
  BuildContext context,
  int flatId,
  VoidCallback refresh, {
  bool ownerMode = false,
}) async {
  final changed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => CollectPaymentPage(flatId: flatId, ownerMode: ownerMode),
    ),
  );
  if (changed == true) refresh();
}

Future<void> exportReceiptPdf(BuildContext context, dynamic paymentRow,
    {bool preview = false}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final billId = int.tryParse('${paymentRow.data['bill_ids'] ?? ''}');
    Map<String, dynamic> billMap = {
      'id': billId,
      'bill_number': paymentRow.data['bill_number'],
      'flat_number': paymentRow.data['flat_number'],
      'owner_name': paymentRow.data['owner_name'],
      'building': paymentRow.data['building'],
      'period_start': paymentRow.data['period_start'],
      'period_end': paymentRow.data['period_end'],
      'months_covered': paymentRow.data['months_covered'],
      'amount': paymentRow.data['bill_amount'] ?? paymentRow.data['amount'],
    };
    if (billId != null) {
      final bill = await db.billById(billId);
      if (bill != null) {
        billMap = Map<String, dynamic>.from(bill.data as Map);
        billMap['flat_number'] ??= paymentRow.data['flat_number'];
        billMap['owner_name'] ??= paymentRow.data['owner_name'];
        billMap['building'] ??= paymentRow.data['building'];
      }
    }
    final payMap = Map<String, dynamic>.from(paymentRow.data as Map);
    if (preview) {
      await ReceiptPdf.preview(payment: payMap, bill: billMap);
    } else {
      await ReceiptPdf.share(payment: payMap, bill: billMap);
      messenger?.showSnackBar(const SnackBar(
          content: Text('Receipt PDF ready to save or share.'),
          backgroundColor: C.green));
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(
        content: Text('Receipt PDF failed: $e'), backgroundColor: C.error));
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

  static const _moreGroups = <(String, List<(String, String, IconData)>)>[
    (
      'People',
      [
        ('residents', 'Residents', Icons.people_outline_rounded),
        ('guards', 'Security guards', Icons.shield_outlined),
        ('visitors', 'Visitors', Icons.groups_outlined),
        ('vehicles', 'Vehicles & parking', Icons.directions_car_outlined),
      ]
    ),
    (
      'Operations',
      [
        ('announcements', 'Announcements', Icons.campaign_outlined),
        ('collections', 'One-time collections', Icons.celebration_outlined),
      ]
    ),
    (
      'Insights & setup',
      [
        ('additional-services', 'Additional services', Icons.local_parking_outlined),
        ('reports', 'Reports & analytics', Icons.assessment_outlined),
        ('settings', 'Society settings', Icons.settings_outlined),
      ]
    ),
  ];

  static String _moreLabel(String key) {
    for (final (_, items) in _moreGroups) {
      for (final (k, label, _) in items) {
        if (k == key) return label;
      }
    }
    return 'More';
  }

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

  Future<void> logout() async {
    final session = authSession;
    if (session != null) {
      await performLogout(session);
    } else {
      clearLiveRepositories();
      await SessionStore.clear();
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _openMore(String key) => setState(() {
        tab = 4;
        _morePage = key;
      });

  Widget _adminMoreBody() {
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
        return _moreHub();
    }
  }

  Widget _moreHub() => ListView(
        padding: Sp.pagePadding,
        children: [
          const PageHeader('Directory',
              subtitle: 'People, operations and reports'),
          for (var g = 0; g < _moreGroups.length; g++) ...[
            if (g > 0) const SizedBox(height: 18),
            ToolDirectory(
              title: _moreGroups[g].$1,
              links: [
                for (final (key, label, icon) in _moreGroups[g].$2)
                  ToolLink(
                    icon: icon,
                    label: label,
                    subtitle: _adminToolHint(key),
                    onTap: () => _openMore(key),
                  ),
              ],
            ),
          ],
        ],
      );

  String _adminToolHint(String key) {
    switch (key) {
      case 'residents':
        return 'Provision owners and tenants';
      case 'visitors':
        return 'Society-wide visitor records';
      case 'vehicles':
        return 'Assign vehicles and parking numbers to flats';
      case 'guards':
        return 'Provision gate logins';
      case 'announcements':
        return 'Publish a notice';
      case 'additional-services':
        return 'Recurring charges on individual flats';
      case 'collections':
        return 'Festival, repair and special charges';
      case 'reports':
        return 'Collections and outstanding dues';
      case 'settings':
        return 'Society profile and wings';
      default:
        return '';
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

  static const _tabTitles = ['Overview', 'Flats', 'Bills', 'Payments', 'More'];

  @override
  Widget build(BuildContext context) {
    final inSubPage = tab == 4 && _morePage != null;
    return PopScope(
      canPop: !_canPopInternally,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popInternally();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: inSubPage
              ? IconButton(
                  tooltip: 'Back',
                  onPressed: _popInternally,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          title: inSubPage
              ? Text(_moreLabel(_morePage!))
              : brandAppBarTitle(
                  title: tab == 0 ? '$kAppName Admin' : _tabTitles[tab],
                  subtitle: kSocietyName),
          actions: [
            IconButton(
              tooltip: 'Logout',
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: IndexedStack(
          index: tab,
          children: [
            adminDashboard(),
            AdminFlatsPage(onChanged: refresh),
            const LiveAdminBillsPage(),
            const LiveAdminPaymentsPage(),
            _adminMoreBody(),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() {
            if (v == 4 && tab == 4) _morePage = null;
            tab = v;
            if (v != 4) _morePage = null;
            if (v == 0) reloadDashboard();
          }),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: 'Overview'),
            NavigationDestination(
                icon: Icon(Icons.apartment_outlined),
                selectedIcon: Icon(Icons.apartment_rounded),
                label: 'Flats'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Bills'),
            NavigationDestination(
                icon: Icon(Icons.payments_outlined),
                selectedIcon: Icon(Icons.payments_rounded),
                label: 'Payments'),
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'More'),
          ],
        ),
      ),
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
          final society = bundle.society;
          final totals = bundle.dashboard.totals;
          final wings = bundle.dashboard.wings;
          final occupied =
              totals.ownerOccupiedFlats + totals.tenantOccupiedFlats;
          final occRate =
              totals.flats == 0 ? 0 : (occupied * 100 / totals.flats).round();
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              reloadDashboard();
              await _dashboardFuture;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                Text('${dayGreeting()}, Admin',
                    style: T.caption.copyWith(color: C.faint)),
                const SizedBox(height: 4),
                Text(society.name,
                    style: T.h1, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                    '${monthName(DateTime.now())} · ${totals.wings} wings · ${society.code}',
                    style: T.secondary),
                const SizedBox(height: 18),
                StatGrid(children: [
                  StatCard(
                    title: 'Total flats',
                    value: '${totals.flats}',
                    icon: Icons.apartment_outlined,
                    caption: '${totals.wings} wings',
                    onTap: () => setState(() => tab = 1),
                  ),
                  StatCard(
                    title: 'Occupied',
                    value: '$occupied',
                    icon: Icons.groups_outlined,
                    caption: '${totals.vacantFlats} vacant',
                    onTap: () => setState(() => tab = 1),
                  ),
                  StatCard(
                    title: 'This month',
                    value: money(totals.monthlyMaintenanceTotal),
                    icon: Icons.payments_outlined,
                    caption: 'Maintenance',
                    onTap: () => setState(() => tab = 2),
                  ),
                  StatCard(
                    title: 'Occupancy',
                    value: '$occRate%',
                    icon: Icons.pie_chart_outline_rounded,
                    accent: C.green,
                    caption: '${totals.activeFlats} active',
                  ),
                ]),
                const SizedBox(height: 12),
                CollectionBar(
                  title: 'Occupancy',
                  progress: totals.flats == 0 ? 0 : occupied / totals.flats,
                  valueLabel: '$occRate%',
                  caption:
                      '${totals.ownerOccupiedFlats} owner · ${totals.tenantOccupiedFlats} tenant · ${totals.vacantFlats} vacant · ${totals.twoBhkCount} × 2 BHK · ${totals.threeBhkCount} × 3 BHK',
                ),
                const SizedBox(height: 20),
                const SectionTitle('Quick actions'),
                QuickAccessGrid(items: [
                  QuickAccessItem(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Residents',
                    onTap: () => _openMore('residents'),
                  ),
                  QuickAccessItem(
                    icon: Icons.shield_outlined,
                    label: 'Guards',
                    color: C.softBlue,
                    onTap: () => _openMore('guards'),
                  ),
                  QuickAccessItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Create bill',
                    color: C.amber,
                    onTap: () => setState(() => tab = 2),
                  ),
                  QuickAccessItem(
                    icon: Icons.campaign_outlined,
                    label: 'Notice',
                    color: C.blueDark,
                    onTap: () => _openMore('announcements'),
                  ),
                ]),
                const SizedBox(height: 22),
                ToolDirectory(
                  title: 'Operate',
                  links: [
                    ToolLink(
                      icon: Icons.apartment_outlined,
                      label: 'Find a flat',
                      subtitle: 'Occupancy, residents and rates',
                      onTap: () => setState(() => tab = 1),
                    ),
                    ToolLink(
                      icon: Icons.receipt_long_outlined,
                      label: 'Maintenance bills',
                      subtitle: 'Generate, adjust and collect',
                      onTap: () => setState(() => tab = 2),
                    ),
                    ToolLink(
                      icon: Icons.payments_outlined,
                      label: 'Payments',
                      subtitle: 'Recent collections and receipts',
                      onTap: () => setState(() => tab = 3),
                    ),
                    ToolLink(
                      icon: Icons.celebration_outlined,
                      label: 'One-time collections',
                      subtitle: 'Festival, repair and special charges',
                      onTap: () => _openMore('collections'),
                    ),
                    ToolLink(
                      icon: Icons.shield_outlined,
                      label: 'Security guards',
                      subtitle: 'Create and manage gate logins',
                      onTap: () => _openMore('guards'),
                    ),
                    ToolLink(
                      icon: Icons.campaign_outlined,
                      label: 'Announcements',
                      subtitle: 'Publish a notice',
                      onTap: () => _openMore('announcements'),
                    ),
                    ToolLink(
                      icon: Icons.assessment_outlined,
                      label: 'Reports',
                      subtitle: 'Collections and outstanding dues',
                      onTap: () => _openMore('reports'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SectionTitle('Wings',
                    action: TextButton(
                        onPressed: () => _openMore('settings'),
                        child: const Text('Society'))),
                if (wings.isEmpty)
                  const EmptyState('No wings configured yet',
                      icon: Icons.domain_outlined, compact: true)
                else
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < wings.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 56, endIndent: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(children: [
                            AppAvatar(
                                text: wings[i].code, square: true, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(wings[i].name, style: T.bodyStrong),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${wings[i].activeFlats} active · ${wings[i].vacantFlats} vacant',
                                    style: T.caption,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(money(wings[i].monthlyMaintenanceTotal),
                                    style: T.money.copyWith(fontSize: 13)),
                                Text('per month', style: T.caption),
                              ],
                            ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
              ],
            ),
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
  String statusFilter = 'all'; // all | active | inactive
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
    final wings = await repos.society.wings(force: force);
    bool? isActive;
    if (statusFilter == 'active') isActive = true;
    if (statusFilter == 'inactive') isActive = false;
    final flats = await repos.society.listFlats(
      force: force,
      query: ListFlatsQuery(
        wingId: wingId,
        isActive: isActive,
        search: query.trim().isEmpty ? null : query.trim(),
        page: page,
        limit: _limit,
        sortBy: 'number',
        sortOrder: 'asc',
      ),
    );
    return _AdminFlatsBundle(wings: wings, flats: flats);
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
          final refreshing =
              snapshot.connectionState == ConnectionState.waiting;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: SearchField(
                controller: _searchCtrl,
                hint: 'Search flat number',
                onChanged: (v) {
                  query = v;
                  _searchDebounce.run(() => reload(resetPage: true));
                },
              ),
            ),
            FilterBar(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                AppFilterChip(
                  label: 'All wings',
                  selected: wingId == null,
                  onSelected: () {
                    wingId = null;
                    reload(resetPage: true);
                  },
                ),
                for (final w in wings)
                  AppFilterChip(
                    label: 'Wing ${w.code}',
                    selected: wingId == w.id,
                    onSelected: () {
                      wingId = w.id;
                      reload(resetPage: true);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: FilterBar(children: [
                    for (final f in const [
                      ('all', 'All'),
                      ('active', 'Active'),
                      ('inactive', 'Inactive'),
                    ])
                      AppFilterChip(
                        label: f.$2,
                        selected: statusFilter == f.$1,
                        onSelected: () {
                          statusFilter = f.$1;
                          reload(resetPage: true);
                        },
                      ),
                  ]),
                ),
                const SizedBox(width: 8),
                if (refreshing)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  ResultCount(pagination.total, 'flat'),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: rows.isEmpty
                  ? EmptyState(
                      'No flats match your filters',
                      icon: Icons.apartment_outlined,
                      actionLabel: 'Clear filters',
                      onAction: () {
                        _searchCtrl.clear();
                        query = '';
                        wingId = null;
                        statusFilter = 'all';
                        reload(resetPage: true);
                      },
                    )
                  : RefreshIndicator(
                      color: C.blue,
                      onRefresh: () async {
                        reload(resetPage: true);
                        await _future;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length + 1,
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
                          final r = rows[i];
                          final label = r.number.contains('-')
                              ? r.number.split('-').last
                              : r.number;
                          final owner = r.activeOwner?.name.trim() ?? '';
                          return ListRow(
                            onTap: () => openDetail(r),
                            leading: AppAvatar(
                              text: label,
                              square: true,
                              color: r.isActive ? C.blue : C.muted,
                            ),
                            title: r.number,
                            subtitle:
                                '${r.wingName ?? r.wingCode ?? 'Wing'} · Floor ${r.floor} · ${flatTypeLabel(r.flatType)}\n'
                                '${owner.isEmpty ? 'No owner allotted' : owner}',
                            badges: [
                              StatusBadge(
                                  occupancyStatusLabel(r.occupancyStatus),
                                  tone: _occupancyTone(r.occupancyStatus)),
                              if (!r.isActive) const StatusBadge('Inactive'),
                            ],
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(money(r.maintenanceRate),
                                    style: T.money.copyWith(fontSize: 14)),
                                Text('per month', style: T.caption),
                              ],
                            ),
                            showChevron: true,
                          );
                        },
                      ),
                    ),
            ),
          ]);
        },
      );
}

BadgeTone _occupancyTone(String status) {
  switch (status.toUpperCase()) {
    case 'OWNER_OCCUPIED':
      return BadgeTone.success;
    case 'TENANT_OCCUPIED':
      return BadgeTone.info;
    case 'VACANT':
      return BadgeTone.warning;
    default:
      return BadgeTone.neutral;
  }
}

class _AdminFlatsBundle {
  const _AdminFlatsBundle({required this.wings, required this.flats});
  final List<WingSummary> wings;
  final Paged<FlatSummary> flats;
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
    setState(() => _future = _load(force: true));
  }

  Widget _flatServiceRow(
    BuildContext context,
    AdditionalService service, {
    required String title,
    required String subtitle,
  }) {
    return ListRow(
      onTap: () async {
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
      },
      leading: AppAvatar(
        icon: Icons.local_parking_outlined,
        color: service.isActive ? C.blue : C.muted,
        size: 42,
      ),
      title: title,
      subtitle: subtitle,
      trailing: Text(
        '${moneyPaise(service.monthlyTotalPaise)}/month',
        style: T.money.copyWith(fontSize: 14),
      ),
      showChevron: true,
    );
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
      appBar: AppBar(title: const Text('Flat details')),
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
          final hasActions =
              canAssignOwner || canAssignTenant || canEndTenant || canEndOwner;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                DetailHero(
                  title: flat.number,
                  subtitle:
                      '${flat.wingName ?? flat.wingCode ?? 'Wing'} · Floor ${flat.floor} · ${flatTypeLabel(flat.flatType)}',
                  leading: AppAvatar(
                    text: flat.number.contains('-')
                        ? flat.number.split('-').last
                        : flat.number,
                    size: Sz.avatarLg,
                    square: true,
                    color: flat.isActive ? C.blue : C.muted,
                  ),
                  badges: [
                    StatusBadge(occupancyStatusLabel(flat.occupancyStatus),
                        tone: _occupancyTone(flat.occupancyStatus)),
                    StatusBadge(flat.isActive ? 'Active' : 'Inactive'),
                  ],
                ),
                const SizedBox(height: 16),
                DetailCard(title: 'Flat', children: [
                  DetailRow('Monthly maintenance', money(flat.maintenanceRate),
                      emphasize: true),
                  DetailRow('Type', flatTypeLabel(flat.flatType)),
                  DetailRow('Floor', '${flat.floor}'),
                  if (flat.parking != null)
                    DetailRow('Parking', _parkingLabel(flat.parking!)),
                  if (flat.notes != null && flat.notes!.trim().isNotEmpty)
                    DetailRow('Notes', flat.notes!.trim()),
                ]),
                const SectionTitle('Who lives here'),
                _ResidentCard(
                  title: 'Owner',
                  icon: Icons.home_outlined,
                  resident: flat.activeOwner,
                  emptyText: 'No owner allotted',
                ),
                _ResidentCard(
                  title: 'Tenant',
                  icon: Icons.person_pin_circle_outlined,
                  resident: flat.activeTenant,
                  emptyText: status == 'OWNER_OCCUPIED'
                      ? 'Owner occupied · no tenant'
                      : 'No active tenant',
                ),
                const SizedBox(height: 12),
                const SectionTitle('Next occupancy step',
                    subtitle: 'Vacant → owner → tenant → owner → vacant'),
                if (!hasActions)
                  const EmptyState(
                      'No occupancy change is available in this state',
                      icon: Icons.lock_clock_outlined,
                      compact: true)
                else
                  ActionRail(
                    busy: busy,
                    primary: canAssignOwner
                        ? ToolLink(
                            icon: Icons.person_add_alt_1_outlined,
                            label: 'Assign owner',
                            subtitle: 'Pick an owner account for this flat',
                            onTap: () => _assign('OWNER'),
                          )
                        : canAssignTenant
                            ? ToolLink(
                                icon: Icons.group_add_outlined,
                                label: 'Assign tenant',
                                subtitle:
                                    'Residential access moves to the tenant',
                                onTap: () => _assign('TENANT'),
                              )
                            : canEndTenant
                                ? ToolLink(
                                    icon: Icons.person_remove_outlined,
                                    label: 'End tenant occupancy',
                                    subtitle: 'Flat returns to owner occupied',
                                    onTap: () => _end(owner: false),
                                  )
                                : canEndOwner
                                    ? ToolLink(
                                        icon: Icons.home_work_outlined,
                                        label: 'End owner occupancy',
                                        subtitle: 'Flat becomes vacant',
                                        onTap: () => _end(owner: true),
                                      )
                                    : null,
                  ),
                const SizedBox(height: 20),
                const SectionTitle('Billing & services'),
                Builder(builder: (_) {
                  final allServices = snap.data!.services;
                  final extra = allServices
                      .where((s) => s.isActive)
                      .fold<int>(0, (sum, s) => sum + s.monthlyTotalPaise);
                  final recurringPaise =
                      (flat.maintenanceRate * 100) + extra;
                  final activeCount =
                      activeAdditionalServiceCount(allServices);
                  final atCap = !canAddActiveAdditionalService(allServices);
                  final activeServices =
                      allServices.where((s) => s.isActive).toList();
                  final inactiveServices =
                      allServices.where((s) => !s.isActive).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailCard(title: 'Recurring monthly', children: [
                        DetailRow(
                            'Base maintenance', money(flat.maintenanceRate)),
                        DetailRow('Additional monthly charges',
                            moneyPaise(extra)),
                        DetailRow(
                            'Total recurring', moneyPaise(recurringPaise),
                            emphasize: true),
                      ]),
                      SectionTitle(
                        'Additional Services — $activeCount/$kMaxActiveAdditionalServicesPerFlat',
                      ),
                      if (atCap) ...[
                        const InfoNote(kAdditionalServiceLimitMessage,
                            tone: NoteTone.warning),
                        const SizedBox(height: 10),
                      ],
                      QuickActionTile(
                        icon: Icons.add_rounded,
                        label: 'Add additional service',
                        subtitle: atCap
                            ? kAdditionalServiceLimitMessage
                            : 'Parking or other recurring charges for this flat',
                        enabled: !atCap,
                        onTap: () async {
                          if (!canAddActiveAdditionalService(
                              snap.data!.services)) {
                            showAppSnack(context,
                                kAdditionalServiceLimitMessage,
                                tone: SnackTone.warning);
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
                        },
                      ),
                      const SizedBox(height: 8),
                      if (allServices.isEmpty)
                        const EmptyState(
                            'No additional services on this flat',
                            icon: Icons.local_parking_outlined,
                            compact: true)
                      else ...[
                        ...activeServices.asMap().entries.map((entry) {
                          final n = entry.key + 1;
                          final service = entry.value;
                          return _flatServiceRow(
                            context,
                            service,
                            title: 'Service $n: ${service.name}',
                            subtitle: 'Qty ${service.quantity}',
                          );
                        }),
                        ...inactiveServices.map(
                          (service) => _flatServiceRow(
                            context,
                            service,
                            title: service.name,
                            subtitle: 'Inactive · Qty ${service.quantity}',
                          ),
                        ),
                      ],
                    ],
                  );
                }),
                const SizedBox(height: 12),
                const SectionTitle('Billing history'),
                if (snap.data!.bills.isEmpty)
                  const EmptyState('No bills generated for this flat yet',
                      icon: Icons.receipt_long_outlined, compact: true)
                else
                  ...snap.data!.bills.map(
                    (bill) => ListRow(
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveAdminBillDetailPage(billId: bill.id),
                          ),
                        );
                        if (mounted) _reload();
                      },
                      title: bill.billNumber,
                      subtitle:
                          '${fmtIsoDate(bill.billingPeriodStart)} · ${humanizeStatus(bill.status)}',
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(moneyPaise(bill.totalAmountPaise),
                              style: T.money.copyWith(fontSize: 14)),
                          Text(
                            bill.outstandingPrincipalPaise > 0
                                ? 'Due ${moneyPaise(billAmountDuePaise(bill))}'
                                : 'Settled',
                            style: T.caption,
                          ),
                        ],
                      ),
                      showChevron: true,
                    ),
                  ),
                const SizedBox(height: 20),
                const SectionTitle('Occupancy history'),
                if (history.items.isEmpty)
                  const EmptyState('No occupancy history yet',
                      icon: Icons.history_rounded, compact: true)
                else
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < history.items.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 56, endIndent: 12),
                        Builder(builder: (_) {
                          final item = history.items[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppAvatar(
                                  icon: item.role == 'OWNER'
                                      ? Icons.home_outlined
                                      : Icons.person_pin_circle_outlined,
                                  color: item.status.toUpperCase() == 'ACTIVE'
                                      ? C.green
                                      : C.muted,
                                  size: 36,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.userName ?? item.userId,
                                          style: T.bodyStrong),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          if (item.userEmail != null)
                                            item.userEmail!,
                                          '${occupancyDateLabel(item.startsAt)}${item.endsAt == null ? ' → present' : ' → ${occupancyDateLabel(item.endsAt!)}'}',
                                          if (item.endReason != null)
                                            'Reason: ${item.endReason}',
                                        ].join('\n'),
                                        style: T.caption,
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            StatusBadge(
                                                item.role == 'OWNER'
                                                    ? 'Owner'
                                                    : 'Tenant',
                                                tone: BadgeTone.info),
                                            StatusBadge(item.status),
                                          ]),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _parkingLabel(FlatParking p) {
    if (!p.hasParking) return 'No parking';
    final slot = p.slotLabel?.trim();
    return slot == null || slot.isEmpty ? 'Allocated' : 'Slot $slot';
  }
}

class _ResidentCard extends StatelessWidget {
  const _ResidentCard({
    required this.title,
    required this.icon,
    required this.resident,
    required this.emptyText,
  });
  final String title;
  final IconData icon;
  final ResidentSummary? resident;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final r = resident;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        AppAvatar(
          icon: r == null ? icon : null,
          text: r == null ? null : initialsOf(r.name),
          color: r == null ? C.muted : C.blue,
          size: 44,
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: T.label),
            const SizedBox(height: 3),
            Text(r == null ? emptyText : r.name,
                style: r == null
                    ? T.secondary
                    : T.bodyStrong.copyWith(fontSize: 15)),
            if (r != null && r.displayContact.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(r.displayContact, style: T.secondary),
            ],
          ]),
        ),
      ]),
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

class FlatEditorPage extends StatefulWidget {
  const FlatEditorPage({super.key, this.flat});
  final dynamic flat;
  bool get isEdit => flat != null;
  @override
  State<FlatEditorPage> createState() => _FlatEditorPageState();
}

class _ChargeRow {
  _ChargeRow({String description = '', String amount = ''})
      : description = TextEditingController(text: description),
        amount = TextEditingController(text: amount);
  final TextEditingController description;
  final TextEditingController amount;
  void dispose() {
    description.dispose();
    amount.dispose();
  }
}

class _FlatEditorPageState extends State<FlatEditorPage> {
  static const buildings = kAllBuildings;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController building;
  late final TextEditingController flatNumber;
  late final TextEditingController floor;
  late final TextEditingController ownerName;
  late final TextEditingController mobile;
  late final TextEditingController email;
  late final TextEditingController amount;
  late final TextEditingController tenantName;
  late final TextEditingController tenantMobile;
  String flatType = '2 BHK';
  String occupancyType = kOccupancyOwnerOccupied;
  String? formError;
  bool saving = false;
  bool removing = false;
  final List<_ChargeRow> chargeRows = [];

  @override
  void initState() {
    super.initState();
    final f = widget.flat;
    building = TextEditingController(
        text: f == null ? buildings.first : f.read<String>('building'));
    flatNumber =
        TextEditingController(text: f?.read<String>('flat_number') ?? '');
    floor =
        TextEditingController(text: f == null ? '' : '${f.read<int>('floor')}');
    ownerName =
        TextEditingController(text: f?.read<String>('owner_name') ?? '');
    mobile = TextEditingController(text: f?.read<String>('mobile') ?? '');
    final existingEmail = f?.data['email'] as String?;
    email = TextEditingController(text: existingEmail ?? '');
    flatType = (f?.data['flat_type'] as String?) ?? '2 BHK';
    if (flatType != '2 BHK' && flatType != '3 BHK') flatType = '2 BHK';
    amount = TextEditingController(
      text: f == null
          ? (flatType == '3 BHK' ? '5000' : '4000')
          : '${f.read<int>('monthly_amount')}',
    );
    occupancyType =
        f == null ? kOccupancyOwnerOccupied : OccupancyAccess.occupancyOf(f);
    tenantName = TextEditingController(
        text: f == null ? '' : OccupancyAccess.tenantNameOf(f));
    tenantMobile = TextEditingController(
        text: f == null ? '' : OccupancyAccess.tenantMobileOf(f));
    if (f != null) {
      _loadCharges(f.read<int>('id'));
    } else {
      chargeRows.add(_ChargeRow());
    }
  }

  Future<void> _loadCharges(int flatId) async {
    final rows = await db.otherChargesForFlat(flatId);
    if (!mounted) return;
    setState(() {
      for (final r in chargeRows) {
        r.dispose();
      }
      chargeRows
        ..clear()
        ..addAll(rows.map((r) => _ChargeRow(
              description: r.read<String>('description'),
              amount: '${r.read<int>('amount')}',
            )));
      if (chargeRows.isEmpty) chargeRows.add(_ChargeRow());
    });
  }

  @override
  void dispose() {
    building.dispose();
    flatNumber.dispose();
    floor.dispose();
    ownerName.dispose();
    mobile.dispose();
    email.dispose();
    amount.dispose();
    tenantName.dispose();
    tenantMobile.dispose();
    for (final r in chargeRows) {
      r.dispose();
    }
    super.dispose();
  }

  List<Map<String, Object?>> _validatedCharges() {
    final out = <Map<String, Object?>>[];
    for (final row in chargeRows) {
      final desc = row.description.text.trim();
      final amtText = row.amount.text.trim();
      if (desc.isEmpty && amtText.isEmpty) continue;
      if (desc.isEmpty)
        throw StateError(
            'Enter a service / charge description for every filled row.');
      final amt = int.tryParse(amtText);
      if (amt == null || amt <= 0)
        throw StateError('Each charge amount must be a valid positive number.');
      out.add({'description': desc, 'amount': amt});
    }
    if (out.length > LocalDatabase.maxOtherChargesPerFlat) {
      throw StateError(
          'A flat can have at most ${LocalDatabase.maxOtherChargesPerFlat} other charges.');
    }
    return out;
  }

  String? _required(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _validateMobile(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null; // Owner mobile may be blank until allotted.
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(t))
      return 'Enter a valid 10-digit Indian mobile number.';
    return null;
  }

  String? _validateEmail(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t))
      return 'Enter a valid email address.';
    return null;
  }

  String? _validateAmount(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null) return 'Monthly maintenance amount is required.';
    if (n <= 0) return 'Maintenance amount must be greater than zero.';
    return null;
  }

  String? _validateFloor(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null) return 'Floor number is required.';
    if (n < 0 || n > 200) return 'Enter a valid floor number.';
    return null;
  }

  Future<void> save() async {
    setState(() => formError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final charges = _validatedCharges();
      final emailValue = email.text.trim().isEmpty ? null : email.text.trim();
      late final int flatId;
      if (widget.isEdit) {
        flatId = widget.flat.read<int>('id');
        await db.updateFlat(
          id: flatId,
          building: building.text.trim(),
          flatNumber: flatNumber.text.trim(),
          floor: int.parse(floor.text.trim()),
          flatType: flatType,
          ownerName: ownerName.text.trim(),
          mobile: mobile.text.trim(),
          email: emailValue,
          monthlyAmount: int.parse(amount.text.trim()),
          occupancyType: occupancyType,
          tenantName: tenantName.text.trim(),
          tenantMobile: tenantMobile.text.trim(),
        );
      } else {
        flatId = await db.createFlat(
          building: building.text.trim(),
          flatNumber: flatNumber.text.trim(),
          floor: int.parse(floor.text.trim()),
          flatType: flatType,
          ownerName: ownerName.text.trim(),
          mobile: mobile.text.trim(),
          email: emailValue,
          monthlyAmount: int.parse(amount.text.trim()),
          occupancyType: occupancyType,
          tenantName: tenantName.text.trim(),
          tenantMobile: tenantMobile.text.trim(),
        );
      }
      await db.replaceFlatOtherCharges(flatId, charges);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.isEdit
            ? 'Flat details updated.'
            : 'Flat created successfully.'),
        backgroundColor: C.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => formError = e is StateError
          ? e.message
          : 'Could not save flat. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> removeFlat() async {
    final id = widget.flat.read<int>('id') as int;
    final hasHistory = await db.flatHasHistory(id);
    if (!mounted) return;
    final active = (widget.flat.data['is_active'] as int? ?? 1) == 1;
    if (!active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reactivate flat?'),
          content: const Text(
              'This flat is inactive and will not receive new bills. Reactivate it?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reactivate')),
          ],
        ),
      );
      if (ok != true) return;
      setState(() => removing = true);
      try {
        await db.reactivateFlat(id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Flat reactivated.'), backgroundColor: C.green));
        Navigator.pop(context, true);
      } catch (_) {
        setState(() => formError = 'Could not reactivate flat.');
      } finally {
        if (mounted) setState(() => removing = false);
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasHistory ? 'Deactivate flat?' : 'Delete flat?'),
        content: Text(hasHistory
            ? 'This flat has bill or payment history, so it will be deactivated instead of permanently deleted. Inactive flats will not receive new maintenance bills.'
            : 'This flat has no bills or payments. It will be permanently removed from the directory.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(context, true),
            child: Text(hasHistory ? 'Deactivate' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => removing = true);
    try {
      final result = await db.removeOrDeactivateFlat(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result == 'deactivated'
            ? 'Flat deactivated. Existing history preserved.'
            : 'Flat deleted.'),
        backgroundColor: C.navy,
      ));
      Navigator.pop(context, true);
    } catch (_) {
      setState(() => formError = 'Could not remove flat.');
    } finally {
      if (mounted) setState(() => removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isEdit
        ? ((widget.flat.data['is_active'] as int? ?? 1) == 1)
        : true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit flat' : 'Add flat',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (widget.isEdit)
            TextButton(
              onPressed: removing || saving ? null : removeFlat,
              child: Text(active ? 'Deactivate' : 'Reactivate',
                  style: TextStyle(
                      color: active ? Colors.red : C.green,
                      fontWeight: FontWeight.w800)),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              const Text('Flat & owner details',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: C.navy)),
              const SizedBox(height: 6),
              Text(
                widget.isEdit
                    ? 'Update the flat record stored on this device.'
                    : 'Create a new flat in the local society directory.',
                style: const TextStyle(color: C.muted),
              ),
              if (!active) ...[
                const SizedBox(height: 12),
                const InfoNote(
                    'This flat is inactive and will be skipped when generating new maintenance bills.'),
              ],
              const SizedBox(height: 18),
              TextFormField(
                controller: building,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Building / Wing',
                  hintText: 'e.g. Monarch Solitaire A–E',
                  prefixIcon: Icon(Icons.domain),
                ),
                validator: (v) => _required(v, 'Building / Wing'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: buildings
                    .map((b) => ActionChip(
                          label: Text(b, style: const TextStyle(fontSize: 12)),
                          onPressed: saving
                              ? null
                              : () => setState(() => building.text = b),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: flatNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Flat number',
                    hintText: 'e.g. C-301',
                    prefixIcon: Icon(Icons.tag)),
                validator: (v) => _required(v, 'Flat number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: floor,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Floor number',
                    prefixIcon: Icon(Icons.layers_outlined)),
                validator: _validateFloor,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: flatType,
                decoration: const InputDecoration(
                    labelText: 'Flat type',
                    prefixIcon: Icon(Icons.apartment_outlined)),
                items: const [
                  DropdownMenuItem(value: '2 BHK', child: Text('2 BHK')),
                  DropdownMenuItem(value: '3 BHK', child: Text('3 BHK')),
                ],
                onChanged: saving
                    ? null
                    : (v) => setState(() {
                          flatType = v ?? '2 BHK';
                          amount.text = flatType == '3 BHK' ? '5000' : '4000';
                        }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: ownerName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Owner name (optional)',
                    prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Owner mobile number (optional)',
                    prefixIcon: Icon(Icons.phone_android),
                    counterText: ''),
                validator: _validateMobile,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Owner email (optional)',
                    prefixIcon: Icon(Icons.email_outlined)),
                validator: _validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Monthly maintenance amount (₹)',
                    prefixIcon: Icon(Icons.currency_rupee)),
                validator: _validateAmount,
              ),
              const SizedBox(height: 22),
              const SectionTitle('Occupancy'),
              const SizedBox(height: 6),
              const InfoNote(
                'Owner Occupied: owner has full resident access. Tenant Occupied: owner keeps financial access only; the active tenant handles visitors and residential features.',
              ),
              const SizedBox(height: 12),
              ScaleToWidth(
                child: SegmentedButton<String>(
                  showSelectedIcon: MediaQuery.sizeOf(context).width >= 400,
                  segments: const [
                    ButtonSegment(
                        value: kOccupancyOwnerOccupied,
                        label: Text('Owner Occupied'),
                        icon: Icon(Icons.home_outlined)),
                    ButtonSegment(
                        value: kOccupancyTenantOccupied,
                        label: Text('Tenant Occupied'),
                        icon: Icon(Icons.person_pin_circle_outlined)),
                  ],
                  selected: {occupancyType},
                  onSelectionChanged: saving
                      ? null
                      : (s) => setState(() => occupancyType = s.first),
                ),
              ),
              if (occupancyType == kOccupancyTenantOccupied) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: tenantName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Tenant name *',
                      prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) {
                    if (occupancyType != kOccupancyTenantOccupied) return null;
                    return _required(v, 'Tenant name');
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: tenantMobile,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Tenant mobile *',
                      prefixIcon: Icon(Icons.phone_android),
                      counterText: ''),
                  validator: (v) {
                    if (occupancyType != kOccupancyTenantOccupied) return null;
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Tenant mobile is required.';
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(t))
                      return 'Enter a valid 10-digit Indian mobile number.';
                    return null;
                  },
                ),
              ] else ...[
                const SizedBox(height: 12),
                const Text(
                  'Switching to Owner Occupied deactivates the tenant login but keeps tenant name/mobile on record.',
                  style: TextStyle(
                      color: C.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 22),
              const SectionTitle('Other Charges'),
              const SizedBox(height: 6),
              const Text(
                'Optional per-flat services. Added once on each new bill (not multiplied by prepaid months). Max 10 rows.',
                style: TextStyle(
                    color: C.muted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: C.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.line),
                ),
                child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(children: [
                      Expanded(
                          flex: 3,
                          child: Text('Service / Charge Description',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: C.muted))),
                      SizedBox(width: 8),
                      Expanded(
                          flex: 2,
                          child: Text('Amount (₹)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: C.muted))),
                      SizedBox(width: 40),
                    ]),
                  ),
                  const Divider(height: 1),
                  for (var i = 0; i < chargeRows.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: chargeRows[i].description,
                                enabled: !saving,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'e.g. Car Washing',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: chargeRows[i].amount,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '0',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove row',
                              onPressed: saving || chargeRows.length <= 1
                                  ? null
                                  : () => setState(() {
                                        chargeRows.removeAt(i).dispose();
                                        if (chargeRows.isEmpty)
                                          chargeRows.add(_ChargeRow());
                                      }),
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: C.error),
                            ),
                          ]),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: saving ||
                        chargeRows.length >=
                            LocalDatabase.maxOtherChargesPerFlat
                    ? null
                    : () => setState(() => chargeRows.add(_ChargeRow())),
                icon: const Icon(Icons.add),
                label: Text(
                  chargeRows.length >= LocalDatabase.maxOtherChargesPerFlat
                      ? 'Maximum 10 charges'
                      : '+ Add Charge',
                ),
              ),
              if (formError != null) ...[
                const SizedBox(height: 12),
                Text(formError!,
                    style: const TextStyle(
                        color: C.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: C.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: saving || removing ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : Text(widget.isEdit ? 'Save changes' : 'Create flat',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 10),
              const InfoNote(
                  'New flats are saved locally and will be included the next time you generate monthly bills (unless deactivated).'),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminBillsPage extends StatefulWidget {
  const AdminBillsPage({super.key});
  @override
  State<AdminBillsPage> createState() => _AdminBillsPageState();
}

class _AdminBillsPageState extends State<AdminBillsPage> {
  String filter = 'all';
  String wingFilter = 'All';
  String flatQuery = '';
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = db.bills();
  }

  void reload() {
    setState(() {
      _future = db.bills(
        status: filter == 'all' ? null : filter,
        building: wingFilter == 'All' ? null : wingFilter,
      );
    });
  }

  Future<void> openCreate() async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const CreateBillPage()));
    if (changed == true && mounted) reload();
  }

  Future<void> openEdit(dynamic row) async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => EditBillPage(bill: row)));
    if (changed == true && mounted) reload();
  }

  Future<void> openCollect(dynamic row) async {
    await openCollectPayment(context, row, reload);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: C.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: openCreate,
              icon: const Icon(Icons.add),
              label: const Text('+ Create Bill',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => flatQuery = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Search flat number (e.g. A-101)',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final b in const ['All', ...kAllBuildings])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(b == 'All'
                      ? 'All wings'
                      : b.replaceFirst('Monarch Solitaire ', '')),
                  selected: wingFilter == b,
                  onSelected: (_) {
                    wingFilter = b;
                    reload();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final f in const [
              'all',
              'pending',
              'overdue',
              'paid',
              'cancelled'
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f[0].toUpperCase() + f.substring(1)),
                  selected: filter == f,
                  onSelected: (_) {
                    filter = f;
                    reload();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const LoadingView(label: 'Loading bills…');
              }
              final q = flatQuery.toLowerCase();
              final rows = (snapshot.data ?? []).where((row) {
                if (q.isEmpty) return true;
                return row
                    .read<String>('flat_number')
                    .toLowerCase()
                    .contains(q);
              }).toList();
              if (rows.isEmpty) {
                final wingLabel = wingFilter == 'All'
                    ? ''
                    : ' in wing ${wingFilter.replaceFirst('Monarch Solitaire ', '')}';
                if (q.isNotEmpty) {
                  return EmptyState(
                      'No bills match flat "$flatQuery"$wingLabel.');
                }
                return EmptyState(
                  filter == 'all'
                      ? 'No bills yet$wingLabel.\nUse Create Bill to generate prepaid maintenance bills.'
                      : 'No $filter bills found$wingLabel.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final status = row.read<String>('status');
                  final unpaid = status == 'pending' || status == 'overdue';
                  return BillTile(
                    row: row,
                    admin: true,
                    onEdit: unpaid ? () => openEdit(row) : null,
                    onCollect: unpaid ? () => openCollect(row) : null,
                  );
                },
              );
            },
          ),
        ),
      ]);
}

class CreateBillPage extends StatefulWidget {
  const CreateBillPage({super.key});
  @override
  State<CreateBillPage> createState() => _CreateBillPageState();
}

class _CreateBillPageState extends State<CreateBillPage> {
  final remarks = TextEditingController();
  final customMonths = TextEditingController(text: '4');
  DateTime period = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime issueDate;
  late DateTime dueDate;
  int monthsChoice = 1; // 1,2,3 or -1 for custom
  bool confirming = false;
  bool generating = false;
  String? error;
  Map<String, int>? preview;

  @override
  void initState() {
    super.initState();
    _syncDefaultDates();
    _refreshPreview();
  }

  int get monthsCovered {
    if (monthsChoice == -1) return int.tryParse(customMonths.text.trim()) ?? 0;
    return monthsChoice;
  }

  void _syncDefaultDates() {
    issueDate = DateTime(period.year, period.month, 1);
    dueDate = DateTime(period.year, period.month, 10);
  }

  Future<void> _refreshPreview() async {
    if (monthsCovered < 1) {
      setState(() => preview = null);
      return;
    }
    final p = await db.previewSocietyBilling(
        periodStart: period, monthsCovered: monthsCovered);
    if (mounted) setState(() => preview = p);
  }

  @override
  void dispose() {
    remarks.dispose();
    customMonths.dispose();
    super.dispose();
  }

  Future<void> pickDate({required bool issue}) async {
    final initial = issue ? issueDate : dueDate;
    final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (picked != null)
      setState(() => issue ? issueDate = picked : dueDate = picked);
  }

  Future<void> goToConfirmation() async {
    setState(() => error = null);
    if (monthsCovered < 1) {
      setState(() => error = 'Enter a valid number of months (1 or more).');
      return;
    }
    await _refreshPreview();
    if (preview == null || (preview!['activeFlats'] ?? 0) == 0) {
      setState(() => error = 'No active flats found to bill.');
      return;
    }
    setState(() => confirming = true);
  }

  Future<void> generate() async {
    setState(() {
      generating = true;
      error = null;
    });
    try {
      final result = await db.createSocietyBills(
        periodStart: period,
        monthsCovered: monthsCovered,
        issueDate: issueDate,
        dueDate: dueDate,
        remarks: remarks.text.trim().isEmpty
            ? 'Society maintenance'
            : remarks.text.trim(),
      );
      final report = await db.periodBillReport(period);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Bills generated'),
          content: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Created: ${result.created} bills · ${money(result.createdAmount)}'),
                  Text('Skipped: ${result.skipped}'),
                  const SizedBox(height: 12),
                  const Text('Period report',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, color: C.navy)),
                  const SizedBox(height: 6),
                  Text('Total bills: ${report['totalBills']}'),
                  Text('Total bill amount: ${money(report['totalAmount']!)}'),
                  Text('Paid amount: ${money(report['paidAmount']!)}'),
                  Text('Pending amount: ${money(report['pendingAmount']!)}'),
                  Text('Overdue amount: ${money(report['overdueAmount']!)}'),
                  if (result.skippedFlats.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Skipped flats',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, color: C.navy)),
                    const SizedBox(height: 6),
                    ...result.skippedFlats.take(20).map((s) => Text('• $s',
                        style: const TextStyle(fontSize: 12, color: C.muted))),
                    if (result.skippedFlats.length > 20)
                      Text('…and ${result.skippedFlats.length - 20} more',
                          style: const TextStyle(fontSize: 12, color: C.muted)),
                  ],
                ]),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'))
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() =>
          error = e is StateError ? e.message : 'Could not generate bills.');
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(confirming ? 'Confirm generation' : 'Create bill',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        leading: confirming
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: generating
                    ? null
                    : () => setState(() => confirming = false))
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (!confirming) ...[
            const Text(
                'Generate individual bills for every active flat in Monarch Solitaire A to E.',
                style: TextStyle(color: C.muted)),
            const SizedBox(height: 6),
            const InfoNote(
                'Each flat is billed using its saved monthly maintenance × number of months. Existing bills for the same period are skipped.'),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Maintenance start month',
                  style: TextStyle(fontWeight: FontWeight.w700, color: C.navy)),
              subtitle: Text(monthName(period)),
              trailing:
                  const Icon(Icons.calendar_month_outlined, color: C.blue),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: period,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  helpText: 'Select start month and year',
                );
                if (picked != null) {
                  setState(() {
                    period = DateTime(picked.year, picked.month);
                    _syncDefaultDates();
                  });
                  _refreshPreview();
                }
              },
            ),
            const SizedBox(height: 8),
            const Text('Number of prepaid months',
                style: TextStyle(fontWeight: FontWeight.w700, color: C.navy)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [1, 2, 3])
                ChoiceChip(
                  label: Text('$m month${m == 1 ? '' : 's'}'),
                  selected: monthsChoice == m,
                  onSelected: (_) {
                    setState(() => monthsChoice = m);
                    _refreshPreview();
                  },
                ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: monthsChoice == -1,
                onSelected: (_) {
                  setState(() => monthsChoice = -1);
                  _refreshPreview();
                },
              ),
            ]),
            if (monthsChoice == -1) ...[
              const SizedBox(height: 10),
              TextField(
                controller: customMonths,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Custom months',
                    prefixIcon: Icon(Icons.pin_outlined)),
                onChanged: (_) {
                  setState(() {});
                  _refreshPreview();
                },
              ),
            ],
            if (monthsCovered >= 1) ...[
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: billDetailLine(
                  'Maintenance Period',
                  maintenancePeriodLabel(
                      startMonth: period, monthsCovered: monthsCovered),
                ),
              ),
            ],
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Issue date',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(shortDate(issueDate.toIso8601String())),
              trailing: const Icon(Icons.event_outlined, color: C.blue),
              onTap: () => pickDate(issue: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Due date',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(shortDate(dueDate.toIso8601String())),
              trailing:
                  const Icon(Icons.event_available_outlined, color: C.blue),
              onTap: () => pickDate(issue: false),
            ),
            TextField(
              controller: remarks,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                  prefixIcon: Icon(Icons.notes_outlined)),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style: const TextStyle(
                      color: C.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: C.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: goToConfirmation,
                child: const Text('Generate Bills for Entire Society',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ] else ...[
            const Text('Review before generating',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: C.navy)),
            const SizedBox(height: 8),
            const Text(
                'A separate bill will be created for every active flat using its own monthly maintenance amount.',
                style: TextStyle(color: C.muted)),
            const SizedBox(height: 16),
            CardTile(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  billDetailLine('Society', kSocietyName),
                  billDetailLine(
                    'Maintenance Period',
                    maintenancePeriodLabel(
                        startMonth: period, monthsCovered: monthsCovered),
                  ),
                  billDetailLine('Prepaid months', '$monthsCovered'),
                  billDetailLine(
                      'Issue date', shortDate(issueDate.toIso8601String())),
                  billDetailLine(
                      'Due date', shortDate(dueDate.toIso8601String())),
                  billDetailLine(
                      'Total active flats', '${preview?['activeFlats'] ?? 0}'),
                  billDetailLine('Bills to generate',
                      '${preview?['billsToGenerate'] ?? 0}'),
                  billDetailLine('Already billed (skip)',
                      '${preview?['alreadyBilled'] ?? 0}'),
                  billDetailLine('Maintenance subtotal',
                      money(preview?['maintenanceTotal'] ?? 0)),
                  billDetailLine('Other Charges total',
                      money(preview?['otherChargesTotal'] ?? 0)),
                  billDetailLine('Estimated grand total',
                      money(preview?['estimatedTotal'] ?? 0)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            const InfoNote(
                'Other charges are added once per bill from each flat’s saved Other Charges. They are not multiplied by prepaid months.'),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style: const TextStyle(
                      color: C.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: C.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: generating ? null : generate,
                child: generating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white))
                    : const Text('Confirm & Generate Bills',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            const InfoNote(
                'Existing paid or pending bills for the same flat and billing period will not be overwritten.'),
          ],
        ],
      ),
    );
  }
}

class EditBillPage extends StatefulWidget {
  const EditBillPage({super.key, required this.bill});
  final dynamic bill;
  @override
  State<EditBillPage> createState() => _EditBillPageState();
}

class _EditBillPageState extends State<EditBillPage> {
  final remarks = TextEditingController();
  final unitAmount = TextEditingController();
  late DateTime period;
  late DateTime issueDate;
  late DateTime dueDate;
  int monthsCovered = 1;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final b = widget.bill;
    period =
        DateTime.tryParse(b.read<String>('period_start')) ?? DateTime.now();
    period = DateTime(period.year, period.month);
    monthsCovered = (b.data['months_covered'] as int?) ?? 1;
    unitAmount.text =
        '${(b.data['unit_amount'] as int?) ?? b.read<int>('amount')}';
    issueDate = DateTime.tryParse(
            b.data['issue_date'] as String? ?? b.read<String>('created_at')) ??
        DateTime(period.year, period.month, 1);
    dueDate = DateTime.tryParse(b.read<String>('due_date')) ??
        DateTime(period.year, period.month, 10);
    remarks.text = (b.data['remarks'] as String?) ?? '';
  }

  @override
  void dispose() {
    remarks.dispose();
    unitAmount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final unit = int.tryParse(unitAmount.text.trim());
    if (unit == null || unit <= 0) {
      setState(() => error = 'Monthly amount must be greater than zero.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await db.updateUnpaidBill(
        billId: widget.bill.read<int>('id'),
        periodStart: period,
        monthsCovered: monthsCovered,
        unitAmount: unit,
        issueDate: issueDate,
        dueDate: dueDate,
        remarks: remarks.text.trim().isEmpty ? null : remarks.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bill updated.'), backgroundColor: C.green));
      Navigator.pop(context, true);
    } catch (e) {
      setState(
          () => error = e is StateError ? e.message : 'Could not update bill.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> cancelBill() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel bill?'),
        content: const Text(
            'This unpaid bill will be marked cancelled and cannot be paid.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel bill')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.cancelBill(widget.bill.read<int>('id'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bill cancelled.'), backgroundColor: C.navy));
      Navigator.pop(context, true);
    } catch (e) {
      setState(
          () => error = e is StateError ? e.message : 'Could not cancel bill.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Edit bill',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            TextButton(
                onPressed: saving ? null : cancelBill,
                child: const Text('Cancel bill',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w800)))
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            CardTile(
              child: ListTile(
                title: Text(
                    '${widget.bill.read<String>('flat_number')} · ${widget.bill.read<String>('owner_name')}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(billNumberOf(widget.bill)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Maintenance start month',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(monthName(period)),
              trailing:
                  const Icon(Icons.calendar_month_outlined, color: C.blue),
              onTap: () async {
                final picked = await showDatePicker(
                    context: context,
                    initialDate: period,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (picked != null)
                  setState(() => period = DateTime(picked.year, picked.month));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Maintenance Period',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(maintenancePeriodLabel(
                  startMonth: period, monthsCovered: monthsCovered)),
            ),
            Row(children: [
              const Text('Prepaid months',
                  style: TextStyle(fontWeight: FontWeight.w700, color: C.navy)),
              const Spacer(),
              IconButton(
                  onPressed: monthsCovered > 1
                      ? () => setState(() => monthsCovered--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline)),
              Text('$monthsCovered',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18)),
              IconButton(
                  onPressed: monthsCovered < 12
                      ? () => setState(() => monthsCovered++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline)),
            ]),
            TextField(
              controller: unitAmount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Monthly maintenance (₹)',
                prefixIcon: const Icon(Icons.currency_rupee),
                helperText:
                    'Total = amount × $monthsCovered = ${money((int.tryParse(unitAmount.text.trim()) ?? 0) * monthsCovered)}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Issue date',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(shortDate(issueDate.toIso8601String())),
              onTap: () async {
                final picked = await showDatePicker(
                    context: context,
                    initialDate: issueDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (picked != null) setState(() => issueDate = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Due date',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(shortDate(dueDate.toIso8601String())),
              onTap: () async {
                final picked = await showDatePicker(
                    context: context,
                    initialDate: dueDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (picked != null) setState(() => dueDate = picked);
              },
            ),
            TextField(
                controller: remarks,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                    prefixIcon: Icon(Icons.notes_outlined))),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!,
                      style: const TextStyle(
                          color: C.error, fontWeight: FontWeight.w600))),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: C.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save bill',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
}

class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key});
  @override
  State<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> {
  late Future<List<dynamic>> _future = db.payments();

  void reload() {
    setState(() {
      _future = db.payments();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading payments…');
          }
          if (snapshot.hasError) {
            return EmptyState('Could not load payments.\n${snapshot.error}',
                icon: Icons.error_outline);
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty)
            return const EmptyState(
                'No payments recorded yet.\nCollect cash or cheque from unpaid bills.');
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async => reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length + 3,
              itemBuilder: (context, i) {
                if (i == 0) return const SectionTitle('Society payments');
                if (i == 1) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 12),
                    child: InfoNote(
                        'Admin cash & cheque collections. Cheque payments show as Cheque Recorded until Cleared or Bounced.'),
                  );
                }
                if (i == 2) return const SizedBox.shrink();
                return _PaymentCard(
                    row: rows[i - 3], showFlat: true, onChanged: reload);
              },
            ),
          );
        },
      );
}

class OwnerBillsPage extends StatefulWidget {
  const OwnerBillsPage(
      {super.key, required this.flatId, required this.onChanged});
  final int flatId;
  final VoidCallback onChanged;
  @override
  State<OwnerBillsPage> createState() => _OwnerBillsPageState();
}

class _OwnerBillsPageState extends State<OwnerBillsPage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = db.bills(flatId: widget.flatId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading your bills…');
          }
          if (snapshot.hasError) {
            return EmptyState('Could not load bills.\n${snapshot.error}',
                icon: Icons.error_outline);
          }
          final rows = snapshot.data ?? [];
          final unpaid = rows.where((r) {
            final s = r.read<String>('status');
            return s == 'pending' || s == 'overdue';
          }).toList();
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SectionTitle('My maintenance bills'),
                    const SizedBox(height: 8),
                    if (unpaid.isNotEmpty) ...[
                      const AppCard(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Previous maintenance dues are pending. Please clear all outstanding bills to proceed with the latest maintenance payment.',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: C.navy,
                              height: 1.35),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: C.blue,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () async {
                            await openPayAllOutstanding(context, widget.flatId,
                                () {
                              setState(() =>
                                  _future = db.bills(flatId: widget.flatId));
                              widget.onChanged();
                            }, ownerMode: true);
                          },
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Pay Outstanding Bills',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const InfoNote(
                      'Outstanding bills must be settled oldest-first in one payment. You cannot pay only the latest bill while older dues remain.',
                    ),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      const EmptyState('No bills found for your flat yet'),
                  ]),
                ),
              ),
              if (rows.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => BillTile(row: rows[i]),
                      childCount: rows.length,
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class OwnerPaymentsPage extends StatefulWidget {
  const OwnerPaymentsPage({super.key, required this.flatId});
  final int flatId;
  @override
  State<OwnerPaymentsPage> createState() => _OwnerPaymentsPageState();
}

class _OwnerPaymentsPageState extends State<OwnerPaymentsPage> {
  late final Future<List<dynamic>> _future = db.payments(flatId: widget.flatId);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading payment history…');
          }
          if (snapshot.hasError) {
            return EmptyState('Could not load payments.\n${snapshot.error}',
                icon: Icons.error_outline);
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return const EmptyState('No payment history yet');
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) return const SectionTitle('Payment history');
              if (i == 1) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 12),
                  child: InfoNote(
                      'Payments collected by the society admin for your flat. Tap a row to open the receipt.'),
                );
              }
              return _PaymentCard(row: rows[i - 2], showFlat: true);
            },
          );
        },
      );
}

String paymentMethodLabel(dynamic row) {
  final method = row.read<String>('method');
  if (method == 'Cheque') {
    final cs = row.data['cheque_status'] as String? ?? 'Pending';
    if (cs == 'Pending') return 'Cheque Recorded';
    return 'Cheque · $cs';
  }
  return method;
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard(
      {required this.row, this.showFlat = false, this.onChanged});
  final dynamic row;
  final bool showFlat;
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context) {
    final paidAt = shortDate(row.read<String>('paid_at'));
    final flat = row.read<String>('flat_number');
    final owner = row.read<String>('owner_name');
    final status = row.read<String>('status');
    final method = row.read<String>('method');
    final reversed = status == 'reversed';
    return AppCard(
      onTap: () => showReceipt(context, row, onChanged: onChanged),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            backgroundColor:
                reversed ? const Color(0xFFFDECEC) : const Color(0xFFE8F7F0),
            child: Icon(reversed ? Icons.undo_rounded : Icons.check_rounded,
                color: reversed ? C.error : C.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(money(row.read<int>('amount')),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: C.navy,
                      fontSize: 16)),
              const SizedBox(height: 2),
              Text(
                showFlat
                    ? '$flat · $owner'
                    : row.read<String>('receipt_number'),
                style: const TextStyle(
                    fontSize: 12, color: C.muted, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          StatusBadge(reversed
              ? 'reversed'
              : (method == 'Cheque' ? paymentMethodLabel(row) : 'paid')),
        ]),
        const SizedBox(height: 10),
        billDetailLine('Receipt number', row.read<String>('receipt_number')),
        if (showFlat) billDetailLine('Flat number', flat),
        billDetailLine('Payment date', paidAt),
        billDetailLine('Payment method', paymentMethodLabel(row)),
        if (method == 'Cheque') ...[
          billDetailLine(
              'Cheque number', '${row.data['cheque_number'] ?? '—'}'),
          billDetailLine('Bank', '${row.data['bank_name'] ?? '—'}'),
        ],
        if ((row.data['collected_by_name'] as String?)?.isNotEmpty == true)
          billDetailLine(
              'Collected by', row.data['collected_by_name'] as String),
      ]),
    );
  }
}

Future<void> showReceipt(BuildContext context, dynamic row,
    {VoidCallback? onChanged}) async {
  final method = row.read<String>('method');
  final status = row.read<String>('status');
  final isCheque = method == 'Cheque';
  final refreshCb = onChanged;
  final canUpdateCheque = isCheque && status == 'success' && refreshCb != null;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      icon: const BrandLogo(size: 48, radius: 12),
      title: const Text('Payment receipt'),
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(kSocietyName,
                  style: TextStyle(
                      fontSize: 11,
                      color: C.muted,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              billDetailLine(
                  'Receipt number', row.read<String>('receipt_number')),
              billDetailLine('Flat', row.read<String>('flat_number')),
              billDetailLine('Owner', row.read<String>('owner_name')),
              billDetailLine('Amount', money(row.read<int>('amount'))),
              billDetailLine('Method', paymentMethodLabel(row)),
              billDetailLine('Paid on', shortDate(row.read<String>('paid_at'))),
              if (isCheque) ...[
                billDetailLine(
                    'Cheque number', '${row.data['cheque_number'] ?? '—'}'),
                billDetailLine('Cheque date',
                    shortDate(row.data['cheque_date'] as String? ?? '')),
                billDetailLine('Bank name', '${row.data['bank_name'] ?? '—'}'),
                billDetailLine('Cheque status',
                    '${row.data['cheque_status'] ?? 'Pending'}'),
              ],
              if ((row.data['collected_by_name'] as String?)?.isNotEmpty ==
                  true)
                billDetailLine(
                    'Collected by', row.data['collected_by_name'] as String),
              if ((row.data['remarks'] as String?)?.isNotEmpty == true)
                billDetailLine('Remarks', row.data['remarks'] as String),
              billDetailLine('Record status', status.toUpperCase()),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close')),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogCtx);
            exportReceiptPdf(context, row, preview: true);
          },
          child: const Text('Preview PDF'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dialogCtx);
            exportReceiptPdf(context, row);
          },
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: const Text('Share PDF'),
        ),
        if (canUpdateCheque)
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _updateChequeStatusSheet(context, row, refreshCb);
            },
            child: const Text('Cheque status'),
          ),
      ],
    ),
  );
}

Future<void> _updateChequeStatusSheet(
    BuildContext context, dynamic row, VoidCallback onChanged) async {
  final current = row.data['cheque_status'] as String? ?? 'Pending';
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Update cheque status',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: C.navy)),
              const SizedBox(height: 4),
              Text('Current: $current',
                  style: const TextStyle(
                      color: C.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const InfoNote(
                  'Bouncing a cheque reverses the payment and restores the bill as unpaid. Payment history is kept for audit.'),
              const SizedBox(height: 12),
              for (final s in const ['Pending', 'Cleared', 'Bounced'])
                ListTile(
                  title: Text(s == 'Pending' ? 'Pending (Cheque Recorded)' : s),
                  trailing: current == s
                      ? const Icon(Icons.check, color: C.blue)
                      : null,
                  onTap: () => Navigator.pop(ctx, s),
                ),
            ]),
      ),
    ),
  );
  if (choice == null || choice == current) return;
  if (!context.mounted) return;
  if (choice == 'Bounced') {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bounce cheque?'),
        content: const Text(
            'This will reverse the collection and mark the bill unpaid again. The payment record stays in history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm bounce'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  try {
    final session = await SessionStore.read();
    if (session == null || !session.isAdmin || session.adminId == null) {
      throw StateError('Admin session required.');
    }
    final admin = await db.adminById(session.adminId!);
    await db.updateChequeStatus(
      paymentId: row.read<int>('id'),
      newStatus: choice,
      adminId: session.adminId!,
      adminName: admin?.read<String>('name') ?? 'Society Admin',
    );
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(choice == 'Bounced'
            ? 'Cheque bounced · bill restored to unpaid.'
            : 'Cheque status updated to $choice.'),
        backgroundColor: C.green,
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            e is StateError ? e.message : 'Could not update cheque status.'),
        backgroundColor: C.error,
      ));
    }
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage(
      {super.key, required this.flat, required this.onLogout, this.access});
  final dynamic flat;
  final VoidCallback onLogout;
  final OccupancyAccess? access;
  @override
  Widget build(BuildContext context) {
    final isTenant = access?.isTenantSession == true;
    final titleName = access?.displayName ?? flat.read<String>('owner_name');
    final mobile = isTenant
        ? OccupancyAccess.tenantMobileOf(flat)
        : flat.read<String>('mobile');
    final occupancy = OccupancyAccess.occupancyOf(flat);
    final occupancyLabel = occupancy == kOccupancyTenantOccupied
        ? 'Tenant Occupied'
        : 'Owner Occupied';
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Center(child: BrandLogo(size: 72, radius: 18)),
      const SizedBox(height: 14),
      Text(titleName,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: C.navy)),
      const SizedBox(height: 4),
      Text(
          '${flat.read<String>('building')} · Flat ${flat.read<String>('flat_number')}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(
        isTenant
            ? 'Tenant account · $occupancyLabel'
            : 'Owner account · $occupancyLabel',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: C.blue, fontWeight: FontWeight.w700, fontSize: 13),
      ),
      const SizedBox(height: 4),
      const Text(kSocietyName,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: C.muted, fontWeight: FontWeight.w600, fontSize: 12)),
      const SizedBox(height: 22),
      CardTile(
          child: ListTile(
              leading: const Icon(Icons.phone_android, color: C.blue),
              title: Text(isTenant ? 'Tenant mobile' : 'Owner mobile'),
              subtitle: Text(mobile.isEmpty ? '—' : mobile))),
      if (!isTenant)
        CardTile(
          child: ListTile(
            leading: const Icon(Icons.email_outlined, color: C.blue),
            title: const Text('Email (notifications)'),
            subtitle: Text(() {
              final email = flat.data['email'] as String?;
              return (email != null && email.isNotEmpty)
                  ? email
                  : 'Not provided';
            }()),
          ),
        ),
      CardTile(
          child: ListTile(
              leading: const Icon(Icons.home_work_outlined, color: C.blue),
              title: const Text('Occupancy'),
              subtitle: Text(occupancyLabel))),
      CardTile(
          child: ListTile(
              leading: const Icon(Icons.layers_outlined, color: C.blue),
              title: const Text('Floor'),
              subtitle: Text('${flat.read<int>('floor')}'))),
      CardTile(
          child: ListTile(
              leading: const Icon(Icons.apartment_outlined, color: C.blue),
              title: const Text('Flat type'),
              subtitle: Text((flat.data['flat_type'] as String?) ?? '—'))),
      if (access?.canFinance != false)
        CardTile(
            child: ListTile(
                leading: const Icon(Icons.currency_rupee, color: C.blue),
                title: const Text('Monthly maintenance'),
                subtitle: Text(money(flat.read<int>('monthly_amount'))))),
      CardTile(
        child: ListTile(
          leading: const Icon(Icons.verified_user_outlined, color: C.blue),
          title: const Text('Flat status'),
          trailing: StatusBadge((flat.data['is_active'] as int? ?? 1) == 1
              ? 'active'
              : 'inactive'),
        ),
      ),
      const SizedBox(height: 18),
      CardTile(
        child: ListTile(
          leading: const Icon(Icons.shield_outlined, color: C.blue),
          title: const Text('Permissions'),
          subtitle: Text(() {
            final parts = <String>[
              if (access?.canFinance == true) 'Financial',
              if (access?.canResidential == true) 'Residential',
            ];
            return parts.isEmpty ? '—' : parts.join(' · ');
          }()),
        ),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Logout')),
    ]);
  }
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

void showBillDetails(BuildContext context, dynamic row,
    {bool admin = false, VoidCallback? onCollect}) {
  final status = row.read<String>('status');
  final unpaid = status == 'pending' || status == 'overdue';
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Bill details'),
      content: FutureBuilder<List<Widget>>(
        future: billFullBreakdownLines(row),
        builder: (context, snap) {
          final lines = snap.data;
          return SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    BrandLogo(size: 28, radius: 8),
                    SizedBox(width: 8),
                    Text(kSocietyName,
                        style: TextStyle(
                            fontSize: 12,
                            color: C.navy,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 12),
                  billDetailLine('Bill number', billNumberOf(row)),
                  if (admin)
                    billDetailLine('Flat',
                        '${row.read<String>('flat_number')} · ${row.read<String>('owner_name')}'),
                  billDetailLine('Maintenance Period', billingPeriodLabel(row)),
                  if (lines == null)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: LoadingView(label: 'Loading amounts…'))
                  else
                    ...lines,
                  billDetailLine('Status', status.toUpperCase()),
                  if ((row.data['remarks'] as String?)?.isNotEmpty == true)
                    billDetailLine('Remarks', row.data['remarks'] as String),
                ]),
          );
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close')),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogCtx);
            exportBillPdf(context, row, preview: true);
          },
          child: const Text('View PDF'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dialogCtx);
            exportBillPdf(context, row);
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download'),
        ),
        if (admin && unpaid && onCollect != null)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.green),
            onPressed: () {
              Navigator.pop(dialogCtx);
              onCollect();
            },
            child: const Text('Pay Outstanding'),
          ),
      ],
    ),
  );
}

class BillTile extends StatelessWidget {
  const BillTile(
      {super.key,
      required this.row,
      this.admin = false,
      this.onTap,
      this.onCollect,
      this.onEdit});
  final dynamic row;
  final bool admin;
  final VoidCallback? onTap;
  final VoidCallback? onCollect;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final status = row.read<String>('status');
    final paid = status == 'paid';
    final overdue = status == 'overdue';
    final cancelled = status == 'cancelled';
    final color =
        paid ? C.green : (overdue ? C.error : (cancelled ? C.muted : C.amber));
    final unpaid = status == 'pending' || status == 'overdue';
    return CardTile(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.10),
              child:
                  Icon(paid ? Icons.check : Icons.receipt_long, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${billingPeriodLabel(row)}${admin ? ' · ${row.read<String>('flat_number')}' : ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: C.navy,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${billNumberOf(row)} · Due ${shortDate(row.read<String>('due_date'))} · ${status.toUpperCase()}',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                    if (admin)
                      Text(row.read<String>('owner_name'),
                          style: const TextStyle(color: C.muted, fontSize: 11)),
                  ]),
            ),
            Text(money(row.read<int>('amount')),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: C.navy)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: onTap ??
                  () => showBillDetails(context, row,
                      admin: admin, onCollect: onCollect),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View Bill'),
            ),
            OutlinedButton.icon(
              onPressed: () => exportBillPdf(context, row),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Download PDF'),
            ),
            if (admin && unpaid && onCollect != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: C.green),
                onPressed: onCollect,
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('Pay Outstanding'),
              ),
            if (admin && paid)
              OutlinedButton.icon(
                onPressed: () async {
                  final payment = await db.paymentForBill(row.read<int>('id'));
                  if (payment == null || !context.mounted) return;
                  await showReceipt(context, payment);
                },
                icon: const Icon(Icons.receipt_outlined, size: 16),
                label: const Text('Receipt'),
              ),
            if (admin && onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Thin alias kept for existing call sites; styling comes from [AppCard].
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AppCard(child: child);
}
