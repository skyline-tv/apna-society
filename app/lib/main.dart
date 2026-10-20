import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/auth/app_role.dart';
import 'api/auth/auth_messages.dart';
import 'api/auth/auth_session.dart';
import 'api/auth/home_resolver.dart';
import 'api/socket/visitor_socket.dart';
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
import 'features/billing/live_billing_module.dart';
import 'features/reports/live_reports_module.dart';
import 'features/residents/admin_residents_module.dart';
import 'features/security/security_module.dart';
import 'features/announcements/live_announcements_module.dart';
import 'features/complaints/live_complaints_module.dart';
import 'features/facilities/live_facilities_module.dart';
import 'features/notifications/live_notifications_module.dart';
import 'features/staff/live_staff_module.dart';
import 'features/vehicles/live_vehicles_module.dart';
import 'features/visitors/live_visitors_module.dart';
import 'services/bill_pdf.dart';
import 'services/occupancy_access.dart';
import 'services/receipt_pdf.dart';
import 'services/session_store.dart';
import 'ui/components.dart';
import 'ui/load_failure.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AuthSession.onLocalSessionCleared = disconnectVisitorSocket;
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
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
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
            return const Scaffold(
              backgroundColor: Colors.white,
              body: LoadingView(label: 'Starting Monarch Solitaire A to E…'),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: Colors.white,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const BrandLogo(size: 72, radius: 18),
                      const SizedBox(height: 20),
                      const Text(
                        'Could not open local data',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: C.navy),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: C.muted,
                            fontWeight: FontWeight.w600,
                            height: 1.35),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () =>
                            setState(() => _init = _initializeLocalDatabase()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return const AuthGate();
        },
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
      final destination = await HomeResolver(session).resolve();
      return _widgetForDestination(destination);
    } catch (error) {
      // Only wipe credentials for terminal auth failures. Network / context
      // errors keep the refresh token so Retry can succeed without re-OTP.
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
            return Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      authErrorMessage(snapshot.error!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: C.error, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your session was kept. Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _boot = _resolveHome()),
                      child: const Text('Retry'),
                    ),
                  ]),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: LoadingView(label: 'Opening Monarch Solitaire A to E…'),
            );
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
  final email = TextEditingController();
  final otp = TextEditingController();
  bool otpStep = false;
  bool busy = false;
  String? error;
  int resendSeconds = 0;
  Timer? _resendTimer;

  /// Backend OTP resend cooldown (`OTP_RESEND_COOLDOWN_MS` = 60s).
  static const _resendCooldown = 60;

  @override
  void dispose() {
    _resendTimer?.cancel();
    email.dispose();
    otp.dispose();
    super.dispose();
  }

  void _startResendCountdown([int seconds = _resendCooldown]) {
    _resendTimer?.cancel();
    setState(() => resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (resendSeconds <= 1) {
        t.cancel();
        setState(() => resendSeconds = 0);
      } else {
        setState(() => resendSeconds--);
      }
    });
  }

  Future<void> sendOtp({bool resend = false}) async {
    setState(() {
      error = null;
      busy = true;
    });
    try {
      final address = email.text.trim();
      if (!isValidEmail(address)) {
        setState(() => error = 'Enter a valid email address.');
        return;
      }
      final session = ensureAuthSession();
      await session.requestOtp(address);
      if (!mounted) return;
      setState(() {
        otpStep = true;
        if (!resend) otp.clear();
      });
      _startResendCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyAndLogin() async {
    setState(() {
      error = null;
      busy = true;
    });
    try {
      final address = email.text.trim();
      final code = otp.text.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(code)) {
        setState(() => error = 'Enter the 6-digit code from your email.');
        return;
      }
      final session = ensureAuthSession();
      await session.verifyOtp(email: address, otp: code);
      if (!mounted) return;
      final destination = await HomeResolver(session).resolve();
      if (!mounted) return;
      final selected = tryParseDropdownRole(role);
      final actual = session.appRole;
      if (selected != null && actual != null && selected != actual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Signed in as ${actual.label}. Your account role is used for access.',
            ),
            backgroundColor: C.blue,
          ),
        );
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => _homeFromDestination(destination)),
        (_) => false,
      );
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

  Future<void> continueLogin() async {
    if (otpStep) {
      await verifyAndLogin();
    } else {
      await sendOtp();
    }
  }

  void _onRoleChanged(String? value) {
    if (value == null || busy || otpStep) return;
    setState(() {
      role = value;
      error = null;
    });
  }

  String get _roleLabel {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'guard':
        return 'Security Guard';
      case 'tenant':
        return 'Flat Tenant';
      default:
        return 'Flat Owner';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Center(child: BrandLogo(size: 96, radius: 24)),
                    const SizedBox(height: 20),
                    const Text(
                      'Welcome to Monarch Solitaire\nA to E',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: C.navy,
                          height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      kAppTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: C.blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      otpStep
                          ? 'Verify OTP for $_roleLabel'
                          : 'Select your account type to continue',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: C.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    if (!otpStep) ...[
                      const Text('Login As',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                              fontSize: 13)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: C.blue),
                        dropdownColor: C.surface,
                        borderRadius: BorderRadius.circular(14),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.account_circle_outlined,
                              color: C.blue),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'owner',
                            child: Row(children: [
                              Icon(Icons.home_outlined,
                                  color: C.blue, size: 22),
                              SizedBox(width: 12),
                              Text('Flat Owner',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: C.navy)),
                            ]),
                          ),
                          DropdownMenuItem(
                            value: 'tenant',
                            child: Row(children: [
                              Icon(Icons.person_pin_circle_outlined,
                                  color: C.blue, size: 22),
                              SizedBox(width: 12),
                              Text('Flat Tenant',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: C.navy)),
                            ]),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Row(children: [
                              Icon(Icons.admin_panel_settings_outlined,
                                  color: C.blue, size: 22),
                              SizedBox(width: 12),
                              Text('Admin',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: C.navy)),
                            ]),
                          ),
                          DropdownMenuItem(
                            value: 'guard',
                            child: Row(children: [
                              Icon(Icons.security, color: C.blue, size: 22),
                              SizedBox(width: 12),
                              Text('Security Guard',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: C.navy)),
                            ]),
                          ),
                        ],
                        onChanged: busy ? null : _onRoleChanged,
                      ),
                      const SizedBox(height: 18),
                    ] else ...[
                      AppCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Icon(
                            role == 'admin'
                                ? Icons.admin_panel_settings_outlined
                                : role == 'guard'
                                    ? Icons.security
                                    : Icons.home_outlined,
                            color: C.blue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Logging in as $_roleLabel',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: C.navy)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: email,
                      enabled: !otpStep && !busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined, color: C.blue),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    if (otpStep) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Email OTP',
                          prefixIcon: Icon(Icons.lock_outline, color: C.blue),
                          counterText: '',
                          helperText: 'Enter the 6-digit code sent to your email',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: (busy || resendSeconds > 0)
                              ? null
                              : () => sendOtp(resend: true),
                          child: Text(
                            resendSeconds > 0
                                ? 'Resend OTP in ${resendSeconds}s'
                                : 'Resend OTP',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  otpStep = false;
                                  error = null;
                                  otp.clear();
                                  _resendTimer?.cancel();
                                  resendSeconds = 0;
                                }),
                        child: const Text('Change email address'),
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: const TextStyle(
                                color: C.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: busy ? null : continueLogin,
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white))
                          : Text(otpStep ? 'Verify & Login' : 'Send OTP'),
                    ),
                    const SizedBox(height: 18),
                    const InfoNote(
                      'Sign in with the email registered for your society account. '
                      'Access is determined by your account role, not the selection above.',
                    ),
                    const SizedBox(height: 24),
                    const Text('Email OTP · Powered by SkyLine Tech Ventures',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.muted, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key, required this.home});
  final ResidentHomeContext home;
  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  int tab = 0;
  late ResidentHomeContext home;
  late Future<ResidentProfileBundle> _profileFuture;

  OccupancyAccess get access => home.access;

  @override
  void initState() {
    super.initState();
    home = widget.home;
    // Keep create flows (complaints / facilities / vehicles) in sync.
    authSession?.selectResidentFlat(home.selectedFlat.flat.id);
    _profileFuture = _loadProfileBundle();
  }

  void _selectFlat(ResidentFlat next) {
    authSession?.selectResidentFlat(next.flat.id);
    final session = authSession;
    if (session != null) {
      ensureLiveRepositories(session.api).invalidateAfterFlatSelectionChange();
    }
    setState(() {
      home = home.copyWithSelected(next);
      _profileFuture = _loadProfileBundle(force: true);
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
    final resolved =
        match.isEmpty ? next : next.copyWithSelected(match.first);
    if (mounted) setState(() => home = resolved);
    return ResidentProfileBundle(context: resolved);
  }

  void refresh() {
    if (!mounted) return;
    setState(() {
      _profileFuture = _loadProfileBundle(force: true);
    });
  }

  List<({Widget page, NavigationDestination dest})> get _tabs {
    final tabs = <({Widget page, NavigationDestination dest})>[
      (
        page: ownerDashboard(),
        dest: const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home'),
      ),
    ];
    final flatKey = home.selectedFlat.flat.id;
    if (access.canFinance) {
      tabs.addAll([
        (
          page: LiveOwnerBillsPage(
            key: ValueKey('bills-$flatKey'),
            canFinance: access.canFinance,
          ),
          dest: const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'My Bills'),
        ),
        (
          page: LiveOwnerPaymentsPage(
            key: ValueKey('payments-$flatKey'),
            canFinance: access.canFinance,
          ),
          dest: const NavigationDestination(
              icon: Icon(Icons.payments_outlined), label: 'Payments'),
        ),
      ]);
    }
    if (access.canResidential) {
      tabs.addAll([
        (
          page: LiveResidentVehiclesPage(key: ValueKey('vehicles-$flatKey')),
          dest: const NavigationDestination(
              icon: Icon(Icons.directions_car_outlined), label: 'Vehicles'),
        ),
        (
          page: LiveResidentVisitorsPage(key: ValueKey('visitors-$flatKey')),
          dest: const NavigationDestination(
              icon: Icon(Icons.groups_outlined), label: 'Visitors'),
        ),
        (
          page: LiveResidentComplaintsPage(
              key: ValueKey('complaints-$flatKey')),
          dest: const NavigationDestination(
              icon: Icon(Icons.report_problem_outlined), label: 'Complaints'),
        ),
        (
          page: LiveResidentFacilitiesPage(
              key: ValueKey('facilities-$flatKey')),
          dest: const NavigationDestination(
              icon: Icon(Icons.meeting_room_outlined), label: 'Facilities'),
        ),
        (
          page: LiveResidentAnnouncementsPage(key: ValueKey('news-$flatKey')),
          dest: const NavigationDestination(
              icon: Icon(Icons.campaign_outlined), label: 'News'),
        ),
      ]);
    }
    tabs.add((
      page: ResidentProfilePage(home: home, onLogout: logout, onRefresh: refresh),
      dest: const NavigationDestination(
          icon: Icon(Icons.person_outline), label: 'Profile'),
    ));
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final safeTab = tab.clamp(0, tabs.length - 1);
    if (safeTab != tab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => tab = safeTab);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: brandAppBarTitle(title: kAppName, subtitle: kSocietyName),
        actions: [
          if (access.canResidential) const LiveNotificationBellButton(),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: tabs[safeTab].page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeTab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: [for (final t in tabs) t.dest],
      ),
    );
  }

  Widget ownerDashboard() {
    return FutureBuilder<ResidentProfileBundle>(
      future: _profileFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const LoadingView(label: 'Loading your account…');
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
        final accessLabel = [
          if (ctx.access.canFinance) 'financial',
          if (ctx.access.canResidential) 'residential',
        ].join(' · ');
        final roleLabel = ctx.access.isTenantSession ? 'Tenant' : 'Owner';

        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Hello, ${name.split(' ').first}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: C.navy)),
              const SizedBox(height: 5),
              Text('${ctx.flatNumber}  •  ${ctx.wingLabel}',
                  style: const TextStyle(color: C.muted)),
              const SizedBox(height: 2),
              Text('$roleLabel · ${ctx.occupancyLabel}'
                  '${accessLabel.isEmpty ? '' : ' · $accessLabel access'}',
                  style: const TextStyle(
                      color: C.blue, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(ctx.profile.email,
                  style: const TextStyle(
                      color: C.muted, fontWeight: FontWeight.w600, fontSize: 12)),
              if (ctx.hasMultipleFlats) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: ctx.selectedFlat.flat.id,
                  decoration: const InputDecoration(
                    labelText: 'Active flat',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final f in ctx.accessibleFlats)
                      DropdownMenuItem(
                        value: f.flat.id,
                        child: Text(
                          '${f.flat.wingCode ?? '?'}-${f.flat.number}'
                          '${f.access.role == 'TENANT' ? ' (tenant)' : ''}',
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    final next = ctx.accessibleFlats
                        .firstWhere((f) => f.flat.id == id);
                    _selectFlat(next);
                  },
                ),
              ],
              const SizedBox(height: 20),
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
              if (ctx.access.canFinance) ...[
                HeroMoneyCard(
                  label: 'MONTHLY MAINTENANCE',
                  amount: money(flat.maintenanceRate),
                  subtitle: '${flatTypeLabel(flat.flatType)} · Floor ${flat.floor}',
                ),
                const SizedBox(height: 14),
                const InfoNote(
                  'Outstanding bills and payments will load from the live billing API in a later phase. Amounts below are the server maintenance rate only.',
                ),
              ] else ...[
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your flat',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, color: C.navy)),
                      const SizedBox(height: 8),
                      billDetailLine('Flat', ctx.flatNumber),
                      billDetailLine('Wing', ctx.wingLabel),
                      billDetailLine('Floor', '${flat.floor}'),
                      billDetailLine('Type', flatTypeLabel(flat.flatType)),
                      billDetailLine('Occupancy', ctx.occupancyLabel),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: StatCard(
                        title: 'Flat status',
                        value: flat.isActive ? 'Active' : 'Inactive',
                        icon: Icons.verified_outlined)),
                const SizedBox(width: 12),
                Expanded(
                    child: StatCard(
                        title: 'Access flats',
                        value: '${ctx.accessibleFlats.length}',
                        icon: Icons.apartment_outlined,
                        accent: C.blue)),
              ]),
              if (ctx.access.canResidential) ...[
                const SizedBox(height: 24),
                const SectionTitle('Residential'),
                const SizedBox(height: 10),
                QuickActionTile(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Invite Visitor (coming with live API)',
                  onTap: () => _goToTabLabel('Visitors'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _goToTabLabel(String label) {
    final tabs = _tabs;
    final i = tabs.indexWhere((t) => t.dest.label == label);
    if (i >= 0) setState(() => tab = i);
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
  });

  final ResidentHomeContext home;
  final VoidCallback onLogout;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final access = home.access;
    final flat = home.flat;
    final isTenant = access.isTenantSession;
    final phone = home.profile.phone?.trim() ?? '';
    return RefreshIndicator(
      color: C.blue,
      onRefresh: () async => onRefresh?.call(),
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Center(child: BrandLogo(size: 72, radius: 18)),
        const SizedBox(height: 14),
        Text(access.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: C.navy)),
        const SizedBox(height: 4),
        Text('${home.wingLabel} · Flat ${home.flatNumber}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          isTenant
              ? 'Tenant account · ${home.occupancyLabel}'
              : 'Owner account · ${home.occupancyLabel}',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: C.blue, fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(home.profile.email,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: C.muted, fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 22),
        CardTile(
            child: ListTile(
                leading: const Icon(Icons.phone_android, color: C.blue),
                title: Text(isTenant ? 'Tenant phone' : 'Owner phone'),
                subtitle: Text(phone.isEmpty ? '—' : phone))),
        CardTile(
          child: ListTile(
            leading: const Icon(Icons.email_outlined, color: C.blue),
            title: const Text('Email'),
            subtitle: Text(home.profile.email),
          ),
        ),
        CardTile(
            child: ListTile(
                leading: const Icon(Icons.home_work_outlined, color: C.blue),
                title: const Text('Occupancy'),
                subtitle: Text(home.occupancyLabel))),
        CardTile(
            child: ListTile(
                leading: const Icon(Icons.layers_outlined, color: C.blue),
                title: const Text('Floor'),
                subtitle: Text('${flat.floor}'))),
        CardTile(
            child: ListTile(
                leading: const Icon(Icons.apartment_outlined, color: C.blue),
                title: const Text('Flat type'),
                subtitle: Text(flatTypeLabel(flat.flatType)))),
        if (access.canFinance)
          CardTile(
              child: ListTile(
                  leading: const Icon(Icons.currency_rupee, color: C.blue),
                  title: const Text('Monthly maintenance'),
                  subtitle: Text(money(flat.maintenanceRate)))),
        CardTile(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined, color: C.blue),
            title: const Text('Flat status'),
            trailing: StatusBadge(flat.isActive ? 'active' : 'inactive'),
          ),
        ),
        if (home.hasMultipleFlats) ...[
          const SizedBox(height: 8),
          const SectionTitle('Accessible flats'),
          const SizedBox(height: 8),
          for (final item in home.accessibleFlats)
            CardTile(
              child: ListTile(
                leading: Icon(
                  item.flat.id == flat.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: C.blue,
                ),
                title: Text(item.flat.number,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  '${item.flat.wingName ?? item.flat.wingCode ?? 'Wing'} · '
                  '${item.access.role}'
                  '${item.access.financial ? ' · financial' : ''}'
                  '${item.access.residential ? ' · residential' : ''}',
                ),
              ),
            ),
        ],
        const SizedBox(height: 18),
        CardTile(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined, color: C.blue),
            title: const Text('Permissions'),
            subtitle: Text(() {
              final parts = <String>[
                if (access.canFinance) 'Financial',
                if (access.canResidential) 'Residential',
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

  Widget _adminMoreBody() {
    switch (_morePage) {
      case 'residents':
        return const AdminResidentsPage();
      case 'visitors':
        return const LiveAdminVisitorsPage();
      case 'vehicles':
        return const LiveAdminVehiclesPage();
      case 'complaints':
        return const LiveAdminComplaintsPage();
      case 'staff':
        return const LiveAdminStaffPage();
      case 'attendance':
        return const LiveAdminAttendancePage();
      case 'shifts':
        return const LiveAdminShiftsPage();
      case 'facilities':
        return const LiveAdminFacilitiesPage();
      case 'facility-bookings':
        return const LiveAdminFacilityBookingsPage();
      case 'announcements':
        return const LiveAdminAnnouncementsPage();
      case 'reports':
        return const LiveAdminReportsPage();
      case 'settings':
        return const AdminSettingsPage();
      default:
        return AdminMorePage(onOpen: (key) => setState(() => _morePage = key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            brandAppBarTitle(title: '$kAppName Admin', subtitle: kSocietyName),
        actions: [
          if (tab == 4 && _morePage != null)
            IconButton(
              tooltip: 'Back to More',
              onPressed: () => setState(() => _morePage = null),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout_rounded)),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() {
          tab = v;
          if (v != 4) _morePage = null;
          if (v == 0) reloadDashboard();
        }),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.apartment_outlined), label: 'Flats'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Bills'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }

  Widget adminDashboard() => FutureBuilder<_AdminDashboardBundle>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading society overview…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load dashboard',
              onRetry: reloadDashboard,
            );
          }
          final bundle = snapshot.data!;
          final society = bundle.society;
          final totals = bundle.dashboard.totals;
          final wings = bundle.dashboard.wings;
          final occupied =
              totals.ownerOccupiedFlats + totals.tenantOccupiedFlats;
          final occRate =
              totals.flats == 0 ? 0 : (occupied * 100 / totals.flats).round();
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async => reloadDashboard(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(children: [
                  const BrandLogo(size: 42, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(society.name,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: C.navy)),
                          Text(
                              'Admin overview · ${society.code} · ${monthName(DateTime.now())}',
                              style: const TextStyle(
                                  color: C.muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ]),
                  ),
                ]),
                const SizedBox(height: 18),
                HeroMoneyCard(
                  label: 'MONTHLY MAINTENANCE TOTAL',
                  amount: money(totals.monthlyMaintenanceTotal),
                  subtitle:
                      '${totals.activeFlats} active flats · ${totals.wings} wings',
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Active flats',
                          value: '${totals.activeFlats}',
                          icon: Icons.apartment_outlined)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Vacant',
                          value: '${totals.vacantFlats}',
                          icon: Icons.meeting_room_outlined,
                          accent: C.amber)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Owner occupied',
                          value: '${totals.ownerOccupiedFlats}',
                          icon: Icons.home_outlined)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Tenant occupied',
                          value: '${totals.tenantOccupiedFlats}',
                          icon: Icons.groups_outlined,
                          accent: C.blue)),
                ]),
                const SizedBox(height: 14),
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Occupancy',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: C.navy)),
                              Text('$occRate%',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: C.green)),
                            ]),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            value: totals.flats == 0
                                ? 0
                                : occupied / totals.flats,
                            minHeight: 10,
                            backgroundColor: C.bg,
                            color: C.green,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                            '${totals.ownerOccupiedFlats} owner · ${totals.tenantOccupiedFlats} tenant · ${totals.vacantFlats} vacant',
                            style: const TextStyle(
                                fontSize: 11,
                                color: C.muted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(
                            '${totals.twoBhkCount} × 2 BHK · ${totals.threeBhkCount} × 3 BHK · ${totals.inactiveFlats} inactive',
                            style: const TextStyle(
                                fontSize: 11,
                                color: C.muted,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
                const SizedBox(height: 22),
                const SectionTitle('Wings'),
                const SizedBox(height: 10),
                if (wings.isEmpty)
                  const EmptyState('No wings configured yet')
                else
                  ...wings.map((w) => AppCard(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: C.chip,
                            child: Text(w.code,
                                style: const TextStyle(
                                    color: C.blue, fontWeight: FontWeight.w800)),
                          ),
                          title: Text(w.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, color: C.navy)),
                          subtitle: Text(
                            '${w.activeFlats} active · ${w.vacantFlats} vacant · ${money(w.monthlyMaintenanceTotal)}/mo',
                            style: const TextStyle(color: C.muted, fontSize: 12),
                          ),
                        ),
                      )),
                const SizedBox(height: 16),
                const SectionTitle('Quick actions'),
                const SizedBox(height: 10),
                QuickActionTile(
                    icon: Icons.auto_awesome,
                    label: 'Generate Bills',
                    onTap: () => setState(() => tab = 2)),
                QuickActionTile(
                    icon: Icons.apartment_outlined,
                    label: 'View All Flats',
                    onTap: () => setState(() => tab = 1)),
                QuickActionTile(
                  icon: Icons.people_outline,
                  label: 'Residents',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'residents';
                  }),
                ),
                QuickActionTile(
                    icon: Icons.payments_outlined,
                    label: 'View Payments',
                    onTap: () => setState(() => tab = 3)),
                QuickActionTile(
                  icon: Icons.groups_outlined,
                  label: 'Visitors',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'visitors';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.directions_car_outlined,
                  label: 'Vehicles',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'vehicles';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.report_problem_outlined,
                  label: 'Complaints',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'complaints';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.badge_outlined,
                  label: 'Staff HR',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'staff';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.fact_check_outlined,
                  label: 'Attendance',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'attendance';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.schedule_outlined,
                  label: 'Shifts',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'shifts';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.meeting_room_outlined,
                  label: 'Facilities',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'facilities';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.event_available_outlined,
                  label: 'Facility bookings',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'facility-bookings';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.campaign_outlined,
                  label: 'Announcements',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'announcements';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.assessment_outlined,
                  label: 'Reports & Analytics',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'reports';
                  }),
                ),
                QuickActionTile(
                  icon: Icons.settings_outlined,
                  label: 'Society settings',
                  onTap: () => setState(() {
                    tab = 4;
                    _morePage = 'settings';
                  }),
                ),
                const SizedBox(height: 10),
                const InfoNote(
                    'Society stats and flats load from the live API. Bills and payments tabs still use on-device demo data until the billing phase.'),
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

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
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
            return const LoadingView(label: 'Loading flats…');
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
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) {
                      query = v;
                      _searchDebounce.run(() => reload(resetPage: true));
                    },
                    decoration: const InputDecoration(
                        hintText: 'Search flat number',
                        prefixIcon: Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Flat creation will be available in a later phase.'),
                      backgroundColor: C.blue,
                    ));
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add'),
                ),
              ]),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All wings'),
                    selected: wingId == null,
                    onSelected: (_) {
                      wingId = null;
                      reload(resetPage: true);
                    },
                  ),
                ),
                for (final w in wings)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(w.code),
                      selected: wingId == w.id,
                      onSelected: (_) {
                        wingId = w.id;
                        reload(resetPage: true);
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (final f in const [
                  ('all', 'All'),
                  ('active', 'Active'),
                  ('inactive', 'Inactive'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: statusFilter == f.$1,
                      onSelected: (_) {
                        statusFilter = f.$1;
                        reload(resetPage: true);
                      },
                    ),
                  ),
                const Spacer(),
                Text('${pagination.total} flats',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: C.navy,
                        fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState('No flats match your filters')
                  : RefreshIndicator(
                      color: C.blue,
                      onRefresh: () async => reload(resetPage: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: rows.length + 1,
                        itemBuilder: (context, i) {
                          if (i == rows.length) {
                            return _paginationBar(
                              page: pagination.page,
                              totalPages: pagination.totalPages);
                          }
                          final r = rows[i];
                          final label = r.number.contains('-')
                              ? r.number.split('-').last
                              : r.number;
                          final owner = r.activeOwner?.name.trim() ?? '';
                          return AppCard(
                            onTap: () => openDetail(r),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    r.isActive ? C.chip : const Color(0xFFF0F0F0),
                                child: Text(label,
                                    style: TextStyle(
                                        color: r.isActive ? C.blue : C.muted,
                                        fontWeight: FontWeight.w800)),
                              ),
                              title: Text(
                                '${r.number} · ${flatTypeLabel(r.flatType)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: C.navy,
                                    fontSize: 14),
                              ),
                              subtitle: Text(
                                '${r.wingName ?? r.wingCode ?? 'Wing'} · Floor ${r.floor}\n'
                                '${owner.isEmpty ? 'Unallotted' : owner}'
                                ' · ${money(r.maintenanceRate)}/mo'
                                ' · ${occupancyStatusLabel(r.occupancyStatus)}',
                                style: const TextStyle(
                                    color: C.muted, fontSize: 12, height: 1.35),
                              ),
                              isThreeLine: true,
                              trailing: StatusBadge(
                                  r.isActive ? 'active' : 'inactive'),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ]);
        },
      );

  Widget _paginationBar({required int page, required int totalPages}) {
    if (totalPages <= 1) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: page <= 1
                ? null
                : () {
                    this.page -= 1;
                    reload();
                  },
            child: const Text('Previous'),
          ),
          Text('Page $page of $totalPages',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: C.navy, fontSize: 12)),
          TextButton(
            onPressed: page >= totalPages
                ? null
                : () {
                    this.page += 1;
                    reload();
                  },
            child: const Text('Next'),
          ),
        ],
      ),
    );
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
    return _FlatDetailBundle(flat: flat, history: history);
  }

  void _reload() {
    setState(() => _future = _load(force: true));
  }

  Future<void> _assign(String role) async {
    final user = await Navigator.push<AdminUser>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPickResidentPage(role: role),
      ),
    );
    if (user == null || !mounted) return;
    final notes = await _promptOptional('Notes (optional)');
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repos = ensureLiveRepositories(session.api);
      if (role == 'OWNER') {
        await repos.society.assignOwner(
          widget.flatId,
          userId: user.id,
          effectiveFrom: DateTime.now(),
          notes: notes,
        );
      } else {
        await repos.society.assignTenant(
          widget.flatId,
          userId: user.id,
          effectiveFrom: DateTime.now(),
          notes: notes,
        );
      }
      repos.invalidateAfterResidentMutation(flatId: widget.flatId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${role == 'OWNER' ? 'Owner' : 'Tenant'} assigned.'),
        backgroundColor: C.green,
      ));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(adminApiErrorMessage(e)),
        backgroundColor: C.error,
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _end({required bool owner}) async {
    final reason = await _promptRequired(
      owner ? 'End owner occupancy' : 'End tenant occupancy',
      'Reason (required)',
    );
    if (reason == null || !mounted) return;
    final notes = await _promptOptional('Notes (optional)');
    if (!mounted) return;
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
          notes: notes,
        );
      } else {
        await repos.society.endTenantOccupancy(
          widget.flatId,
          effectiveTo: DateTime.now(),
          reason: reason,
          notes: notes,
        );
      }
      repos.invalidateAfterResidentMutation(flatId: widget.flatId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(owner ? 'Owner occupancy ended.' : 'Tenant occupancy ended.'),
        backgroundColor: C.green,
      ));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(adminApiErrorMessage(e)),
        backgroundColor: C.error,
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _promptRequired(String title, String label) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.length < 3) return;
              Navigator.pop(ctx, t);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<String?> _promptOptional(String label) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: ctrl, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''), child: const Text('Skip')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return null;
    final trimmed = result.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flat details')),
      body: FutureBuilder<_FlatDetailBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
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
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(flat.number,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: C.navy)),
                const SizedBox(height: 4),
                Text(
                    '${flat.wingName ?? flat.wingCode ?? 'Wing'} · Floor ${flat.floor}',
                    style: const TextStyle(color: C.muted)),
                const SizedBox(height: 16),
                CardTile(
                    child: ListTile(
                        title: const Text('Type'),
                        subtitle: Text(flatTypeLabel(flat.flatType)))),
                CardTile(
                    child: ListTile(
                        title: const Text('Occupancy'),
                        subtitle:
                            Text(occupancyStatusLabel(flat.occupancyStatus)))),
                CardTile(
                    child: ListTile(
                        title: const Text('Monthly maintenance'),
                        subtitle: Text(money(flat.maintenanceRate)))),
                CardTile(
                  child: ListTile(
                    title: const Text('Status'),
                    trailing:
                        StatusBadge(flat.isActive ? 'active' : 'inactive'),
                  ),
                ),
                CardTile(
                    child: ListTile(
                        title: const Text('Owner'),
                        subtitle: Text(flat.activeOwner == null
                            ? '—'
                            : '${flat.activeOwner!.name}\n${flat.activeOwner!.email}'),
                        isThreeLine: flat.activeOwner != null)),
                CardTile(
                    child: ListTile(
                        title: const Text('Tenant'),
                        subtitle: Text(flat.activeTenant == null
                            ? '—'
                            : '${flat.activeTenant!.name}\n${flat.activeTenant!.email}'),
                        isThreeLine: flat.activeTenant != null)),
                if (flat.notes != null && flat.notes!.trim().isNotEmpty)
                  CardTile(
                      child: ListTile(
                          title: const Text('Notes'),
                          subtitle: Text(flat.notes!))),
                const SizedBox(height: 16),
                const SectionTitle('Occupancy actions'),
                const SizedBox(height: 8),
                const InfoNote(
                  'Lifecycle: Vacant → Owner occupied → Tenant occupied → Owner occupied → Vacant. All changes go through backend lifecycle APIs.',
                ),
                const SizedBox(height: 10),
                if (canAssignOwner)
                  QuickActionTile(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Assign owner',
                    onTap: busy ? () {} : () => _assign('OWNER'),
                  ),
                if (canAssignTenant)
                  QuickActionTile(
                    icon: Icons.group_add_outlined,
                    label: 'Assign tenant',
                    onTap: busy ? () {} : () => _assign('TENANT'),
                  ),
                if (canEndTenant)
                  QuickActionTile(
                    icon: Icons.person_remove_outlined,
                    label: 'End tenant occupancy',
                    onTap: busy ? () {} : () => _end(owner: false),
                  ),
                if (canEndOwner)
                  QuickActionTile(
                    icon: Icons.home_work_outlined,
                    label: 'End owner occupancy',
                    onTap: busy ? () {} : () => _end(owner: true),
                  ),
                if (!canAssignOwner &&
                    !canAssignTenant &&
                    !canEndTenant &&
                    !canEndOwner)
                  const EmptyState('No occupancy actions available for this state'),
                const SizedBox(height: 18),
                const SectionTitle('Occupancy history'),
                const SizedBox(height: 8),
                if (history.items.isEmpty)
                  const EmptyState('No occupancy history yet')
                else
                  ...history.items.map((item) => AppCard(
                        child: ListTile(
                          title: Text(
                            '${item.role} · ${item.status}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, color: C.navy),
                          ),
                          subtitle: Text(
                            '${item.userName ?? item.userId}'
                            '${item.userEmail == null ? '' : ' · ${item.userEmail}'}\n'
                            '${occupancyDateLabel(item.startsAt)}'
                            '${item.endsAt == null ? '' : ' → ${occupancyDateLabel(item.endsAt!)}'}'
                            '${item.endReason == null ? '' : '\n${item.endReason}'}',
                            style: const TextStyle(
                                color: C.muted, fontSize: 12, height: 1.35),
                          ),
                          isThreeLine: true,
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FlatDetailBundle {
  const _FlatDetailBundle({required this.flat, required this.history});
  final FlatSummary flat;
  final AdminOccupancyHistory history;
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
              SegmentedButton<String>(
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
              return _PaymentCard(row: rows[i - 2]);
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
            title: const Text('Email'),
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
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        const SectionTitle('Society (live)'),
        const SizedBox(height: 8),
        const InfoNote(
          'Late interest for live bills is calculated by the server. '
          'On-device demo interest settings are not part of the live admin experience.',
        ),
        const SizedBox(height: 12),
        FutureBuilder<SocietyConfiguration>(
          future: _configFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LoadingView(label: 'Loading society…'),
              );
            }
            if (snap.hasError) {
              return LoadFailure(
                error: snap.error!,
                title: 'Could not load society',
                onRetry: () => setState(
                    () => _configFuture = _loadConfig(force: true)),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTile(
                    child: ListTile(
                        leading: const Padding(
                            padding: EdgeInsets.all(2),
                            child: BrandLogo(size: 28, radius: 8)),
                        title: const Text('Society name'),
                        subtitle: Text(society.name))),
                CardTile(
                    child: ListTile(
                        leading: const Icon(Icons.tag, color: C.blue),
                        title: const Text('Society code'),
                        subtitle: Text(society.code))),
                CardTile(
                    child: ListTile(
                        leading:
                            const Icon(Icons.location_on_outlined, color: C.blue),
                        title: const Text('Address'),
                        subtitle: Text(address.isEmpty ? '—' : address))),
                CardTile(
                    child: ListTile(
                        leading: const Icon(Icons.email_outlined, color: C.blue),
                        title: const Text('Contact email'),
                        subtitle: Text(society.contactEmail ?? '—'))),
                CardTile(
                    child: ListTile(
                        leading: const Icon(Icons.phone_outlined, color: C.blue),
                        title: const Text('Contact phone'),
                        subtitle: Text(society.contactPhone ?? '—'))),
                CardTile(
                    child: ListTile(
                        leading: const Icon(Icons.schedule, color: C.blue),
                        title: const Text('Timezone / currency'),
                        subtitle: Text(
                            '${society.timezone} · ${society.currency}'))),
                CardTile(
                    child: ListTile(
                        leading: const Icon(Icons.event, color: C.blue),
                        title: const Text('Maintenance day of month'),
                        subtitle: Text('${society.maintenanceDayOfMonth}'))),
                CardTile(
                    child: ListTile(
                        leading:
                            const Icon(Icons.apartment_outlined, color: C.blue),
                        title: const Text('Inventory'),
                        subtitle: Text(
                            '${totals.wings} wings · ${totals.flats} flats · ${money(totals.monthlyMaintenanceTotal)}/mo'))),
                const SizedBox(height: 8),
                const SectionTitle('Wings'),
                const SizedBox(height: 8),
                if (config.wings.isEmpty)
                  const EmptyState('No wings yet')
                else
                  for (final wing in config.wings)
                    CardTile(
                      child: ListTile(
                        title: Text('${wing.code} · ${wing.name}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            '${wing.flatCount} flats · ${wing.floors} floors · ${wing.flatsPerFloor}/floor'),
                      ),
                    ),
              ],
            );
          },
        ),
      ]);
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
