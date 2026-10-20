import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/auth/home_resolver.dart';
import '../../app_core.dart';
import '../../data/local_database.dart' show InviteCreateResult;
import '../../services/occupancy_access.dart';
import '../../services/session_store.dart';
import '../../ui/components.dart';
import '../vehicles/live_vehicles_module.dart';
import '../vehicles/vehicle_module.dart';
import '../visitors/live_visitors_module.dart';
import 'voice_visitor_registration.dart';

const kVisitorCategories = [
  'Guest',
  'Delivery',
  'Cab',
  'Domestic Help',
  'Technician',
  'Other',
];

const kSocietyWings = ['A', 'B', 'C', 'D', 'E'];

String visitorStatusLabel(String status) {
  switch (status) {
    case 'awaiting_owner':
      return 'Pending Owner Approval';
    case 'approved':
      return 'Approved';
    case 'denied':
      return 'Denied';
    case 'pending':
      return 'OTP Pending';
    case 'inside':
      return 'Inside';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    case 'expired':
      return 'Expired';
    default:
      return status;
  }
}

String _whatsAppInviteMessage({
  required String visitorName,
  required String otp,
  required String flatNumber,
  required String building,
  required String date,
  required String time,
}) =>
    'Monarch Solitaire A to E visitor invite\n'
    'Visitor: $visitorName\n'
    'Flat: $building · $flatNumber\n'
    'Visit: $date at $time\n'
    'Gate OTP (app-generated): $otp\n'
    'Show this OTP at the security desk. Not an SMS OTP.';

// ─── Guard shell ─────────────────────────────────────────────────────────────

class GuardHome extends StatefulWidget {
  const GuardHome({super.key, required this.guard});
  final dynamic guard;
  @override
  State<GuardHome> createState() => _GuardHomeState();
}

class _GuardHomeState extends State<GuardHome> {
  int tab = 0;
  int get guardId => widget.guard.read<int>('id');

  static const _titles = ['Gate desk', 'Verify', 'Inside', 'Account'];

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmLogout() async {
    final ok = await confirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need an SMS OTP to sign in again.',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (ok) await logout();
  }

  void _openQueue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: brandAppBarTitle(
              title: 'Gate queue',
              subtitle: kSocietyName,
            ),
          ),
          body: const LiveGateVisitorBoardPage(),
        ),
      ),
    );
  }

  Future<void> logout() async {
    final session = authSession;
    if (session != null) {
      await performLogout(session);
    } else {
      await SessionStore.clear();
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final guardName = widget.guard.read<String>('name');
    final pages = [
      LiveGuardDashboardPage(
        guardName: guardName,
        onNavigate: (i) => setState(() => tab = i),
        onOpenQueue: _openQueue,
      ),
      LiveVerifyVisitorOtpPage(
        onEntered: () => setState(() => tab = 2),
      ),
      const LiveInsideVisitorsPage(),
      GuardProfilePage(
          guard: widget.guard, onLogout: _confirmLogout, guardId: guardId),
    ];
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => tab = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: brandAppBarTitle(
              title: tab == 0 ? '$kAppName Security' : _titles[tab],
              subtitle: kSocietyName),
          actions: [
            IconButton(
              tooltip: 'Logout',
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: IndexedStack(index: tab, children: pages),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.sensor_door_outlined),
                selectedIcon: Icon(Icons.sensor_door_rounded),
                label: 'Desk'),
            NavigationDestination(
                icon: Icon(Icons.pin_outlined),
                selectedIcon: Icon(Icons.pin_rounded),
                label: 'Verify'),
            NavigationDestination(
                icon: Icon(Icons.meeting_room_outlined),
                selectedIcon: Icon(Icons.meeting_room_rounded),
                label: 'Inside'),
            NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Account'),
          ],
        ),
      ),
    );
  }
}

class GuardDashboardPage extends StatelessWidget {
  const GuardDashboardPage(
      {super.key,
      required this.guard,
      required this.onNavigate,
      required this.onRefresh});
  final dynamic guard;
  final ValueChanged<int> onNavigate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, int>>(
        future: db.visitorDashboardStats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading gate overview…');
          }
          final s = snapshot.data ?? {};
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async => onRefresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Text('Hello, ${guard.read<String>('name').split(' ').first}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: C.navy)),
                const SizedBox(height: 4),
                const Text('Security desk · Monarch Solitaire A to E',
                    style:
                        TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 18),
                AppCard(
                  onTap: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddGateVisitorPage(
                          guardId: guard.read<int>('id'),
                          guardName: guard.read<String>('name'),
                        ),
                      ),
                    );
                    if (changed == true) {
                      onRefresh();
                      onNavigate(2);
                    }
                  },
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: C.chip,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.person_add_alt_1_outlined,
                          color: C.blue),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add Visitor',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: C.navy,
                                    fontSize: 16)),
                            SizedBox(height: 4),
                            Text(
                                'Register a gate visitor and send approval to the flat owner',
                                style: TextStyle(
                                    color: C.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: C.muted),
                  ]),
                ),
                const SizedBox(height: 12),
                AppCard(
                  onTap: () => onNavigate(1),
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: C.chip,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.pin_outlined, color: C.blue),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Verify Visitor OTP',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: C.navy,
                                    fontSize: 16)),
                            SizedBox(height: 4),
                            Text(
                                'Enter the 6-digit OTP generated in the owner app',
                                style: TextStyle(
                                    color: C.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: C.muted),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Awaiting owner',
                          value: '${s['awaitingOwner'] ?? 0}',
                          icon: Icons.hourglass_top_outlined,
                          accent: C.amber)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Approved',
                          value: '${s['approved'] ?? 0}',
                          icon: Icons.verified_outlined,
                          accent: C.green)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Currently inside',
                          value: '${s['inside'] ?? 0}',
                          icon: Icons.groups_outlined)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Denied',
                          value: '${s['denied'] ?? 0}',
                          icon: Icons.block,
                          accent: C.error)),
                ]),
                const SizedBox(height: 22),
                const SectionTitle('Quick actions'),
                const SizedBox(height: 10),
                QuickActionTile(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Add Visitor',
                  onTap: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddGateVisitorPage(
                          guardId: guard.read<int>('id'),
                          guardName: guard.read<String>('name'),
                        ),
                      ),
                    );
                    if (changed == true) {
                      onRefresh();
                      onNavigate(2);
                    }
                  },
                ),
                QuickActionTile(
                    icon: Icons.fact_check_outlined,
                    label: 'Gate visitor board',
                    onTap: () => onNavigate(2)),
                QuickActionTile(
                    icon: Icons.pin_outlined,
                    label: 'Verify Visitor OTP',
                    onTap: () => onNavigate(1)),
                QuickActionTile(
                    icon: Icons.logout_outlined,
                    label: 'Visitor Exit',
                    onTap: () => onNavigate(3)),
                QuickActionTile(
                  icon: Icons.directions_car_outlined,
                  label: 'Vehicle Verification',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => VehicleVerificationPage(
                            guardId: guard.read<int>('id'))),
                  ),
                ),
                const SizedBox(height: 12),
                const InfoNote(
                  'Same-device demo: owner approval notifications appear when you switch to the owner account on this device. Production needs a shared backend and push notifications.',
                ),
              ],
            ),
          );
        },
      );
}

class GuardProfilePage extends StatelessWidget {
  const GuardProfilePage(
      {super.key,
      required this.guard,
      required this.onLogout,
      required this.guardId});
  final dynamic guard;
  final VoidCallback onLogout;
  final int guardId;

  @override
  Widget build(BuildContext context) {
    final name = guard.read<String>('name') as String;
    final mobile = guard.read<String>('mobile') as String;
    return ListView(
      padding: Sp.pagePadding,
      children: [
        DetailHero(
          title: name,
          subtitle: 'Security desk · $kSocietyName',
          leading: AppAvatar(text: initialsOf(name), size: Sz.avatarLg),
          badges: const [
            StatusBadge('Security guard', tone: BadgeTone.info),
          ],
        ),
        const SizedBox(height: 20),
        SettingsGroup(title: 'Account', children: [
          SettingsRow(
              icon: Icons.phone_android_outlined,
              title: 'Mobile',
              value: mobile),
          const SettingsRow(
              icon: Icons.apartment_outlined,
              title: 'Society',
              value: kSocietyName),
        ]),
        SettingsGroup(title: 'Gate tools', children: [
          SettingsRow(
            icon: Icons.directions_car_outlined,
            title: 'Vehicle gate',
            value: 'Log vehicle entry and exit',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LiveGuardVehiclesPage(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SettingsGroup(title: 'Session', children: [
          SettingsRow(
            icon: Icons.logout_rounded,
            title: 'Log out',
            value: 'Requires SMS OTP to sign in again',
            onTap: onLogout,
          ),
        ]),
        const SizedBox(height: 16),
        Text('$kAppName · $kSocietyName',
            textAlign: TextAlign.center,
            style: T.caption.copyWith(color: C.faint)),
      ],
    );
  }
}

// ─── Guard: Verify app-generated visitor OTP ─────────────────────────────────

class VerifyVisitorOtpPage extends StatefulWidget {
  const VerifyVisitorOtpPage(
      {super.key, required this.guardId, this.onEntered});
  final int guardId;
  final VoidCallback? onEntered;
  @override
  State<VerifyVisitorOtpPage> createState() => _VerifyVisitorOtpPageState();
}

class _VerifyVisitorOtpPageState extends State<VerifyVisitorOtpPage> {
  final otp = TextEditingController();
  bool busy = false;
  String? error;
  dynamic invitation;

  @override
  void dispose() {
    otp.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    setState(() {
      busy = true;
      error = null;
      invitation = null;
    });
    try {
      final result = await db.verifyVisitorOtp(otp.text);
      if (!result.ok) {
        await db.recordInvalidOtpAttempt(otp.text);
        setState(() => error = result.message ?? 'Invalid OTP');
        return;
      }
      setState(() => invitation = result.invitation);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmEntry() async {
    if (invitation == null) return;
    setState(() => busy = true);
    try {
      await db.confirmInvitationEntry(
          invitationId: invitation.read<int>('id'), guardId: widget.guardId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visitor entry confirmed.')));
      otp.clear();
      setState(() => invitation = null);
      widget.onEntered?.call();
    } catch (e) {
      setState(() =>
          error = e is StateError ? e.message : 'Could not confirm entry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionTitle('Verify visitor OTP'),
          const SizedBox(height: 8),
          const InfoNote(
            'Enter the 6-digit OTP generated in the flat owner’s app when they invited the visitor. This is not an SMS OTP.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: otp,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: C.navy),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Visitor OTP',
              counterText: '',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            onSubmitted: (_) => verify(),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: busy ? null : verify,
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : const Text('Verify'),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: C.error, fontWeight: FontWeight.w800, fontSize: 15)),
          ],
          if (invitation != null) ...[
            const SizedBox(height: 20),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OTP verified',
                        style: TextStyle(
                            color: C.green, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    billDetailLine(
                        'Visitor', invitation.read<String>('visitor_name')),
                    billDetailLine(
                        'Category', invitation.read<String>('category')),
                    billDetailLine('Flat',
                        '${invitation.read<String>('building')} · ${invitation.read<String>('flat_number')}'),
                    billDetailLine(
                        'Owner', invitation.read<String>('owner_name')),
                    billDetailLine(
                        'Purpose', invitation.read<String>('purpose')),
                    billDetailLine('Expected',
                        '${invitation.read<String>('expected_date')} · ${invitation.read<String>('expected_time')}'),
                    if ((invitation.data['vehicle_number'] as String?)
                            ?.isNotEmpty ==
                        true)
                      billDetailLine('Vehicle',
                          invitation.data['vehicle_number'] as String),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: busy ? null : confirmEntry,
                          child: const Text('Confirm Entry')),
                    ),
                  ]),
            ),
          ],
        ],
      );
}

class InsideVisitorsPage extends StatefulWidget {
  const InsideVisitorsPage({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<InsideVisitorsPage> createState() => _InsideVisitorsPageState();
}

class _InsideVisitorsPageState extends State<InsideVisitorsPage> {
  final search = TextEditingController();
  final _debounce = Debouncer();
  late Future<List<dynamic>> _future = db.invitations(status: 'inside');

  void _reload() {
    setState(() {
      _future = db.invitations(status: 'inside', search: search.text);
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> exitVisitor(dynamic row) async {
    try {
      await db.markInvitationExit(row.read<int>('id'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('${row.read<String>('visitor_name')} marked as exited.')));
      _reload();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is StateError ? e.message : 'Could not mark exit.'),
          backgroundColor: C.error));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: search,
              decoration: InputDecoration(
                labelText: 'Search name, mobile or flat',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh), onPressed: _reload),
              ),
              onChanged: (_) => _debounce.run(_reload),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const LoadingView(label: 'Loading visitors inside…');
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty)
                  return const EmptyState('No visitors currently inside');
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return InvitationCard(
                      row: r,
                      showOtp: false,
                      trailing: FilledButton(
                          onPressed: () => exitVisitor(r),
                          child: const Text('Mark Exit')),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
}

class VisitorHistoryPage extends StatefulWidget {
  const VisitorHistoryPage({super.key, this.flatId, this.admin = false});
  final int? flatId;
  final bool admin;
  @override
  State<VisitorHistoryPage> createState() => _VisitorHistoryPageState();
}

class _VisitorHistoryPageState extends State<VisitorHistoryPage> {
  final search = TextEditingController();
  final _debounce = Debouncer();
  String status = 'all';
  DateTime? filterDate;
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _query();
  }

  Future<List<dynamic>> _query() => db.invitations(
        flatId: widget.flatId,
        status: status,
        search: search.text,
        date: filterDate?.toIso8601String().substring(0, 10),
      );

  void _reload() {
    setState(() {
      _future = _query();
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(children: [
              TextField(
                controller: search,
                decoration: const InputDecoration(
                    labelText: 'Search visitors',
                    prefixIcon: Icon(Icons.search)),
                onChanged: (_) => _debounce.run(_reload),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in [
                    'all',
                    'awaiting_owner',
                    'approved',
                    'denied',
                    'pending',
                    'inside',
                    'completed',
                    'expired',
                    'cancelled',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(visitorStatusLabel(s)),
                        selected: status == s,
                        onSelected: (_) {
                          status = s;
                          _reload();
                        },
                      ),
                    ),
                  FilterChip(
                    label: Text(filterDate == null
                        ? 'Any date'
                        : filterDate!.toIso8601String().substring(0, 10)),
                    selected: filterDate != null,
                    onSelected: (_) async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: filterDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      filterDate = picked;
                      _reload();
                    },
                  ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const LoadingView(label: 'Loading visitor history…');
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty)
                  return const EmptyState(
                      'No visitor records match your filters');
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return InvitationCard(
                      row: r,
                      showOtp: false,
                      trailing:
                          widget.admin && r.read<String>('status') == 'pending'
                              ? TextButton(
                                  onPressed: () async {
                                    await db.cancelInvitation(
                                        invitationId: r.read<int>('id'));
                                    if (mounted) setState(() {});
                                  },
                                  child: const Text('Cancel'),
                                )
                              : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
}

class InvitationCard extends StatelessWidget {
  const InvitationCard(
      {super.key,
      required this.row,
      this.trailing,
      this.showOtp = false,
      this.onShare});
  final dynamic row;
  final Widget? trailing;
  final bool showOtp;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final status = row.read<String>('status');
    final otp = row.data['otp_code'] as String?;
    final source = (row.data['source'] as String?) ?? 'owner';
    final decision = row.data['owner_decision'] as String?;
    final decisionAt = row.data['owner_decision_at'] as String?;
    final decisionBy = row.data['owner_decision_by_name'] as String?;
    final decisionNote = row.data['owner_decision_note'] as String?;
    final guardName = row.data['guard_name'] as String?;
    final photo = row.data['photo_path'] as String?;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(row.read<String>('visitor_name'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: C.navy,
                      fontSize: 15))),
          StatusBadge(visitorStatusLabel(status)),
        ]),
        const SizedBox(height: 8),
        billDetailLine('Mobile', row.read<String>('mobile')),
        billDetailLine('Category', row.read<String>('category')),
        billDetailLine('Flat',
            '${row.read<String>('building')} · ${row.read<String>('flat_number')}'),
        billDetailLine('Purpose', row.read<String>('purpose')),
        billDetailLine(
          source == 'guard' ? 'Gate request time' : 'Expected',
          '${row.read<String>('expected_date')} · ${row.read<String>('expected_time')}',
        ),
        if (source == 'guard')
          billDetailLine('Request source', 'Security gate'),
        if ((guardName ?? '').isNotEmpty)
          billDetailLine('Registered by', guardName!),
        if ((row.data['vehicle_number'] as String?)?.isNotEmpty == true)
          billDetailLine('Vehicle', row.data['vehicle_number'] as String),
        if ((photo ?? '').isNotEmpty)
          billDetailLine('Visitor photo',
              photo == 'demo_gate_photo' ? 'Captured at gate (demo)' : photo!),
        if (decision != null) ...[
          billDetailLine('Owner decision', decision.toUpperCase()),
          if ((decisionBy ?? '').isNotEmpty)
            billDetailLine('Decided by', decisionBy!),
          if (decisionAt != null)
            billDetailLine('Decision time', shortDate(decisionAt)),
          if ((decisionNote ?? '').isNotEmpty)
            billDetailLine('Denial reason', decisionNote!),
        ],
        if (row.data['entry_at'] != null)
          billDetailLine('Entry', shortDate(row.data['entry_at'] as String)),
        if (row.data['exit_at'] != null)
          billDetailLine('Exit', shortDate(row.data['exit_at'] as String)),
        if (showOtp &&
            otp != null &&
            status == 'pending' &&
            source != 'guard') ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: C.chip, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              const Text('APP-GENERATED OTP',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: C.muted,
                      letterSpacing: .8)),
              const SizedBox(height: 4),
              Text(otp,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: C.navy,
                      letterSpacing: 4)),
              const Text('Not sent by SMS · Share with your visitor',
                  style: TextStyle(
                      fontSize: 11,
                      color: C.muted,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        if (trailing != null || onShare != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            if (onShare != null)
              TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share OTP')),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
        ],
      ]),
    );
  }
}

// ─── Owner: Invite visitor (OTP generated in-app) ────────────────────────────

class OwnerVisitorsPage extends StatefulWidget {
  const OwnerVisitorsPage(
      {super.key, required this.flatId, this.flat, required this.access});
  final int flatId;
  final dynamic flat;
  final OccupancyAccess access;
  @override
  State<OwnerVisitorsPage> createState() => _OwnerVisitorsPageState();
}

class _OwnerVisitorsPageState extends State<OwnerVisitorsPage> {
  String filter = 'all';

  String get _actorName => widget.access.displayName;

  Future<void> openInvite() async {
    if (!widget.access.canResidential) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Residential access is required to invite visitors.'),
            backgroundColor: C.error),
      );
      return;
    }
    final session = await SessionStore.read();
    if (!mounted) return;
    final created = await Navigator.push<InviteCreateResult>(
      context,
      MaterialPageRoute(
        builder: (_) => InviteVisitorPage(
          flatId: widget.flatId,
          flat: widget.flat,
          actorRole: widget.access.sessionRole,
          actorMobile: session?.mobile ?? '',
        ),
      ),
    );
    if (created != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invitation created'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('App-generated visitor OTP',
                style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(created.otp,
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: C.navy,
                    letterSpacing: 6)),
            const SizedBox(height: 8),
            const Text('Share this code with your visitor. No SMS is sent.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: C.muted)),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: created.otp));
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('OTP copied')));
              },
              child: const Text('Copy OTP'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        ),
      );
      setState(() {});
    }
  }

  Future<void> shareInvite(dynamic row) async {
    final otp = row.data['otp_code'] as String?;
    if (otp == null) return;
    final msg = _whatsAppInviteMessage(
      visitorName: row.read<String>('visitor_name'),
      otp: otp,
      flatNumber: row.read<String>('flat_number'),
      building: row.read<String>('building'),
      date: row.read<String>('expected_date'),
      time: row.read<String>('expected_time'),
    );
    await Clipboard.setData(ClipboardData(text: msg));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Invite message copied — paste it in WhatsApp to share.')),
    );
  }

  Future<void> approveRequest(dynamic row) async {
    try {
      final session = await SessionStore.read();
      await db.ownerApproveVisitorRequest(
        invitationId: row.read<int>('id'),
        flatId: widget.flatId,
        ownerName: _actorName,
        actorRole: widget.access.sessionRole,
        actorMobile: session?.mobile,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${row.read<String>('visitor_name')} approved for entry.'),
            backgroundColor: C.green),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is StateError ? e.message : 'Could not approve.'),
            backgroundColor: C.error),
      );
    }
  }

  Future<void> denyRequest(dynamic row) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deny entry'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Deny ${row.read<String>('visitor_name')} from entering ${row.read<String>('flat_number')}?'),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 2,
            decoration:
                const InputDecoration(labelText: 'Denial reason (optional)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deny Entry'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reasonCtrl.dispose();
      return;
    }
    try {
      final session = await SessionStore.read();
      await db.ownerDenyVisitorRequest(
        invitationId: row.read<int>('id'),
        flatId: widget.flatId,
        ownerName: _actorName,
        reason: reasonCtrl.text,
        actorRole: widget.access.sessionRole,
        actorMobile: session?.mobile,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${row.read<String>('visitor_name')} denied.'),
            backgroundColor: C.error),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is StateError ? e.message : 'Could not deny.'),
            backgroundColor: C.error),
      );
    } finally {
      reasonCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: openInvite,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Invite Visitor'),
        ),
        body: FutureBuilder<List<dynamic>>(
          future: db.ownerInvitations(widget.flatId,
              status: filter == 'all' ? null : filter),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const LoadingView(label: 'Loading invitations…');
            }
            final rows = snapshot.data ?? [];
            final awaiting = rows
                .where((r) => r.read<String>('status') == 'awaiting_owner')
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                Row(children: [
                  const Expanded(
                      child: SectionTitle('Visitor Approval Requests')),
                  _NotificationBellButton(
                    recipientRole: widget.access.notificationRole,
                    flatId: widget.flatId,
                    onChanged: () => setState(() {}),
                  ),
                ]),
                const SizedBox(height: 8),
                InfoNote(
                  widget.access.isTenantSession
                      ? 'Gate requests for this tenant-occupied flat need your Approve or Deny. Maintenance stays with the owner.'
                      : 'Gate requests from security need your Approve or Deny. Owner OTP invites still work as before.',
                ),
                if (awaiting.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Pending your approval',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, color: C.navy)),
                  const SizedBox(height: 8),
                  ...awaiting.map((r) => InvitationCard(
                        row: r,
                        trailing: Wrap(spacing: 8, children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: C.green),
                            onPressed: () => approveRequest(r),
                            child: const Text('Approve Entry'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: C.error),
                            onPressed: () => denyRequest(r),
                            child: const Text('Deny Entry'),
                          ),
                        ]),
                      )),
                ],
                const SizedBox(height: 16),
                const SectionTitle('My visitors'),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final s in [
                      'all',
                      'awaiting_owner',
                      'approved',
                      'denied',
                      'pending',
                      'inside',
                      'completed',
                      'cancelled',
                      'expired',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(visitorStatusLabel(s)),
                          selected: filter == s,
                          onSelected: (_) => setState(() => filter = s),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const EmptyState('No invitations yet — tap Invite Visitor'),
                ...rows
                    .where((r) =>
                        filter != 'all' ||
                        r.read<String>('status') != 'awaiting_owner')
                    .map((r) {
                  final status = r.read<String>('status');
                  final source = (r.data['source'] as String?) ?? 'owner';
                  if (status == 'awaiting_owner') {
                    return InvitationCard(
                      row: r,
                      trailing: Wrap(spacing: 8, children: [
                        FilledButton(
                          style:
                              FilledButton.styleFrom(backgroundColor: C.green),
                          onPressed: () => approveRequest(r),
                          child: const Text('Approve Entry'),
                        ),
                        FilledButton(
                          style:
                              FilledButton.styleFrom(backgroundColor: C.error),
                          onPressed: () => denyRequest(r),
                          child: const Text('Deny Entry'),
                        ),
                      ]),
                    );
                  }
                  return InvitationCard(
                    row: r,
                    showOtp: true,
                    onShare: status == 'pending' && source != 'guard'
                        ? () => shareInvite(r)
                        : null,
                    trailing: status == 'pending' && source != 'guard'
                        ? TextButton(
                            onPressed: () async {
                              await db.cancelInvitation(
                                  invitationId: r.read<int>('id'),
                                  flatId: widget.flatId);
                              if (mounted) setState(() {});
                            },
                            child: const Text('Cancel'),
                          )
                        : null,
                  );
                }),
              ],
            );
          },
        ),
      );
}

class InviteVisitorPage extends StatefulWidget {
  const InviteVisitorPage({
    super.key,
    required this.flatId,
    this.flat,
    this.actorRole,
    this.actorMobile,
  });
  final int flatId;
  final dynamic flat;
  final String? actorRole;
  final String? actorMobile;
  @override
  State<InviteVisitorPage> createState() => _InviteVisitorPageState();
}

class _InviteVisitorPageState extends State<InviteVisitorPage> {
  final name = TextEditingController();
  final mobile = TextEditingController();
  final purpose = TextEditingController();
  final vehicle = TextEditingController();
  String category = kVisitorCategories.first;
  DateTime expectedDate = DateTime.now();
  TimeOfDay expectedTime = TimeOfDay.now();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    mobile.dispose();
    purpose.dispose();
    vehicle.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await db.createInvitation(
        flatId: widget.flatId,
        visitorName: name.text,
        mobile: mobile.text.trim(),
        category: category,
        purpose: purpose.text,
        expectedDate: expectedDate.toIso8601String().substring(0, 10),
        expectedTime:
            '${expectedTime.hour.toString().padLeft(2, '0')}:${expectedTime.minute.toString().padLeft(2, '0')}',
        vehicleNumber: vehicle.text,
        actorRole: widget.actorRole,
        actorMobile: widget.actorMobile,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      setState(() =>
          error = e is StateError ? e.message : 'Could not create invitation.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Invite Visitor')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const InfoNote(
              'On submit, the app generates a unique 6-digit OTP and saves it locally. No SMS gateway is used — share the OTP yourself (e.g. WhatsApp).',
            ),
            const SizedBox(height: 16),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Visitor name',
                    prefixIcon: Icon(Icons.badge_outlined))),
            const SizedBox(height: 12),
            TextField(
              controller: mobile,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Visitor mobile number',
                  prefixIcon: Icon(Icons.phone_android),
                  counterText: ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Visitor category'),
              items: kVisitorCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: purpose,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Purpose of visit')),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Expected visit date',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(expectedDate.toIso8601String().substring(0, 10)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: busy
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: expectedDate,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (d != null) setState(() => expectedDate = d);
                    },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Expected arrival time',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(expectedTime.format(context)),
              trailing: const Icon(Icons.schedule_outlined),
              onTap: busy
                  ? null
                  : () async {
                      final t = await showTimePicker(
                          context: context, initialTime: expectedTime);
                      if (t != null) setState(() => expectedTime = t);
                    },
            ),
            TextField(
              controller: vehicle,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Vehicle number (optional)',
                  prefixIcon: Icon(Icons.directions_car_outlined)),
            ),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      style: const TextStyle(
                          color: C.error, fontWeight: FontWeight.w700))),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Generate OTP & invite'),
            ),
          ],
        ),
      );
}

class AdminVisitorsPage extends StatefulWidget {
  const AdminVisitorsPage({super.key});
  @override
  State<AdminVisitorsPage> createState() => _AdminVisitorsPageState();
}

class _AdminVisitorsPageState extends State<AdminVisitorsPage> {
  final search = TextEditingController();
  String wing = 'All';
  String status = 'all';
  String flatFilter = '';
  DateTime? filterDate;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(children: [
              const InfoNote(
                'Admin can view all visitor requests and who approved or denied them. Owner decisions are not silently overwritten — changes are audited.',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: search,
                decoration: const InputDecoration(
                    labelText: 'Search visitors',
                    prefixIcon: Icon(Icons.search)),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: wing,
                    decoration: const InputDecoration(labelText: 'Wing'),
                    items: ['All', ...kSocietyWings]
                        .map((w) => DropdownMenuItem(
                            value: w,
                            child: Text(w == 'All' ? 'All wings' : 'Wing $w')))
                        .toList(),
                    onChanged: (v) => setState(() => wing = v ?? 'All'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Flat number'),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) => setState(() => flatFilter = v),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in [
                    'all',
                    'awaiting_owner',
                    'approved',
                    'denied',
                    'pending',
                    'inside',
                    'completed',
                    'cancelled',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(visitorStatusLabel(s)),
                        selected: status == s,
                        onSelected: (_) => setState(() => status = s),
                      ),
                    ),
                  FilterChip(
                    label: Text(filterDate == null
                        ? 'Any date'
                        : filterDate!.toIso8601String().substring(0, 10)),
                    selected: filterDate != null,
                    onSelected: (_) async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: filterDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      setState(() => filterDate = picked);
                    },
                  ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: db.adminVisitorRequests(
                wing: wing,
                flatNumber: flatFilter,
                status: status,
                date: filterDate?.toIso8601String().substring(0, 10),
                search: search.text,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const LoadingView(label: 'Loading visitor history…');
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty)
                  return const EmptyState(
                      'No visitor records match your filters');
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return InvitationCard(
                      row: r,
                      trailing: r.read<String>('status') == 'pending' ||
                              r.read<String>('status') == 'awaiting_owner'
                          ? TextButton(
                              onPressed: () async {
                                await db.cancelInvitation(
                                    invitationId: r.read<int>('id'));
                                if (mounted) setState(() {});
                              },
                              child: const Text('Cancel'),
                            )
                          : TextButton(
                              onPressed: () async {
                                final audit = await db
                                    .visitorRequestAudit(r.read<int>('id'));
                                if (!context.mounted) return;
                                await showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Visitor audit'),
                                    content: SizedBox(
                                      width: double.maxFinite,
                                      child: audit.isEmpty
                                          ? const Text(
                                              'No audit events recorded.')
                                          : ListView(
                                              shrinkWrap: true,
                                              children: audit
                                                  .map((a) => ListTile(
                                                        dense: true,
                                                        title: Text(
                                                            a.read<String>(
                                                                'action')),
                                                        subtitle: Text(
                                                          '${a.data['actor_role'] ?? ''} · ${a.data['actor_name'] ?? ''}\n'
                                                          '${a.read<String>('created_at')}'
                                                          '${(a.data['details'] as String?)?.isNotEmpty == true ? '\n${a.data['details']}' : ''}',
                                                        ),
                                                      ))
                                                  .toList(),
                                            ),
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('Close'))
                                    ],
                                  ),
                                );
                              },
                              child: const Text('Audit'),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
}

// ─── Guard: Add visitor (owner approval) ─────────────────────────────────────

class AddGateVisitorPage extends StatefulWidget {
  const AddGateVisitorPage(
      {super.key, required this.guardId, required this.guardName});
  final int guardId;
  final String guardName;
  @override
  State<AddGateVisitorPage> createState() => _AddGateVisitorPageState();
}

class _AddGateVisitorPageState extends State<AddGateVisitorPage> {
  final name = TextEditingController();
  final mobile = TextEditingController();
  final purpose = TextEditingController();
  final vehicle = TextEditingController();
  String category = kVisitorCategories.first;
  String wing = 'A';
  String? selectedFlat;
  List<String> flatOptions = [];
  bool photoCaptured = false;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadFlats();
  }

  Future<void> _loadFlats() async {
    final flats = await db.flatNumbersForWing(wing);
    if (!mounted) return;
    setState(() {
      flatOptions = flats;
      if (selectedFlat != null && !flats.contains(selectedFlat)) {
        selectedFlat = null;
      }
    });
  }

  @override
  void dispose() {
    name.dispose();
    mobile.dispose();
    purpose.dispose();
    vehicle.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if ((selectedFlat ?? '').isEmpty)
        throw StateError('Select a destination flat number.');
      await db.createGuardVisitorRequest(
        guardId: widget.guardId,
        guardName: widget.guardName,
        wing: wing,
        flatNumber: selectedFlat!,
        visitorName: name.text,
        mobile: mobile.text.trim(),
        category: category,
        purpose: purpose.text,
        vehicleNumber: vehicle.text,
        photoPath: photoCaptured ? 'demo_gate_photo' : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Visitor request sent for owner approval (same-device demo notification).'),
          backgroundColor: C.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error =
          e is StateError ? e.message : 'Could not create visitor request.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final requestTime =
        '${now.toIso8601String().substring(0, 10)} · ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Add Visitor')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const InfoNote(
            'This creates a Pending Owner Approval request for the destination flat. You cannot approve your own request. Entry is allowed only after the owner approves.',
          ),
          const SizedBox(height: 14),
          Material(
            color: C.blue,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: busy
                  ? null
                  : () async {
                      final nav = Navigator.of(context);
                      final changed = await nav.push<bool>(
                        MaterialPageRoute(
                          builder: (_) => VoiceVisitorRegistrationPage(
                            guardId: widget.guardId,
                            guardName: widget.guardName,
                            onManualFallback: () => nav.pop(),
                          ),
                        ),
                      );
                      if (changed == true && mounted) nav.pop(true);
                    },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic_rounded,
                          color: Colors.white, size: 34),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Register Visitor by Voice',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 17),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Speak name, mobile, flat and purpose — then review before sending for owner approval',
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          billDetailLine('Entry request time', requestTime),
          const SizedBox(height: 12),
          TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'Visitor full name *',
                  prefixIcon: Icon(Icons.badge_outlined))),
          const SizedBox(height: 12),
          TextField(
            controller: mobile,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Mobile number *',
                prefixIcon: Icon(Icons.phone_android),
                counterText: ''),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Visitor category'),
            items: kVisitorCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: purpose,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Purpose of visit *')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: wing,
            decoration: const InputDecoration(labelText: 'Destination wing *'),
            items: kSocietyWings
                .map((w) => DropdownMenuItem(value: w, child: Text('Wing $w')))
                .toList(),
            onChanged: busy
                ? null
                : (v) async {
                    setState(() => wing = v!);
                    await _loadFlats();
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('flat-$wing-${flatOptions.length}-$selectedFlat'),
            initialValue:
                selectedFlat != null && flatOptions.contains(selectedFlat)
                    ? selectedFlat
                    : null,
            decoration: const InputDecoration(
                labelText: 'Destination flat number *',
                prefixIcon: Icon(Icons.apartment_outlined)),
            items: flatOptions
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: busy || flatOptions.isEmpty
                ? null
                : (v) => setState(() => selectedFlat = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: vehicle,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Vehicle registration (optional)',
                prefixIcon: Icon(Icons.directions_car_outlined)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visitor photo captured',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'Optional demo marker — no camera upload in this build'),
            value: photoCaptured,
            onChanged: busy ? null : (v) => setState(() => photoCaptured = v),
          ),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: const TextStyle(
                        color: C.error, fontWeight: FontWeight.w700))),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : const Text('Submit for owner approval'),
          ),
        ],
      ),
    );
  }
}

class GateVisitorBoardPage extends StatefulWidget {
  const GateVisitorBoardPage(
      {super.key, required this.guardId, this.onChanged});
  final int guardId;
  final VoidCallback? onChanged;
  @override
  State<GateVisitorBoardPage> createState() => _GateVisitorBoardPageState();
}

class _GateVisitorBoardPageState extends State<GateVisitorBoardPage> {
  String section = 'awaiting_owner';

  Future<void> markEntered(dynamic row) async {
    try {
      await db.confirmApprovedVisitorEntry(
          invitationId: row.read<int>('id'), guardId: widget.guardId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${row.read<String>('visitor_name')} marked as entered.'),
            backgroundColor: C.green),
      );
      setState(() {});
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(e is StateError ? e.message : 'Could not mark entry.'),
            backgroundColor: C.error),
      );
    }
  }

  Future<void> markExit(dynamic row) async {
    try {
      await db.markInvitationExit(row.read<int>('id'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${row.read<String>('visitor_name')} exited.')));
      setState(() {});
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is StateError ? e.message : 'Could not mark exit.'),
            backgroundColor: C.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('Gate visitor board'),
              const SizedBox(height: 8),
              const InfoNote(
                  'Pending Approval · Approved · Denied · Currently Inside · Completed Visits'),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in [
                    ('awaiting_owner', 'Pending Approval'),
                    ('approved', 'Approved'),
                    ('denied', 'Denied'),
                    ('inside', 'Currently Inside'),
                    ('completed', 'Completed Visits'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.$2),
                        selected: section == s.$1,
                        onSelected: (_) => setState(() => section = s.$1),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: db.invitations(status: section),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const LoadingView(label: 'Loading gate visitors…');
                }
                final rows = (snapshot.data ?? []).where((r) {
                  // Gate board focuses on guard requests + inside/completed from either source.
                  final source = (r.data['source'] as String?) ?? 'owner';
                  if (section == 'awaiting_owner' ||
                      section == 'approved' ||
                      section == 'denied') {
                    return source == 'guard';
                  }
                  return true;
                }).toList();
                if (rows.isEmpty)
                  return EmptyState(
                      'No ${visitorStatusLabel(section).toLowerCase()} visitors');
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final status = r.read<String>('status');
                    Widget? trailing;
                    if (status == 'approved') {
                      trailing = FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: C.green),
                        onPressed: () => markEntered(r),
                        child: const Text('Mark Entered'),
                      );
                    } else if (status == 'denied') {
                      trailing = const Text('Entry blocked',
                          style: TextStyle(
                              color: C.error, fontWeight: FontWeight.w800));
                    } else if (status == 'inside') {
                      trailing = FilledButton(
                          onPressed: () => markExit(r),
                          child: const Text('Mark Exit'));
                    } else if (status == 'awaiting_owner') {
                      trailing = const Text('Waiting for owner',
                          style: TextStyle(
                              color: C.amber, fontWeight: FontWeight.w800));
                    }
                    return InvitationCard(row: r, trailing: trailing);
                  },
                );
              },
            ),
          ),
        ],
      );
}

class _NotificationBellButton extends StatefulWidget {
  const _NotificationBellButton({
    required this.recipientRole,
    this.flatId,
    this.guardId,
    this.onChanged,
  });
  final String recipientRole;
  final int? flatId;
  final int? guardId;
  final VoidCallback? onChanged;

  @override
  State<_NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<_NotificationBellButton> {
  late Future<int> _unread;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipientRole != widget.recipientRole ||
        oldWidget.flatId != widget.flatId ||
        oldWidget.guardId != widget.guardId) {
      _reload();
    }
  }

  void _reload() {
    _unread = db.unreadNotificationCount(
      recipientRole: widget.recipientRole,
      flatId: widget.flatId,
      guardId: widget.guardId,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: _unread,
        builder: (context, snap) {
          final count = snap.data ?? 0;
          return IconButton(
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => InAppNotificationsPage(
                    recipientRole: widget.recipientRole,
                    flatId: widget.flatId,
                    guardId: widget.guardId,
                  ),
                ),
              );
              if (!mounted) return;
              setState(_reload);
              widget.onChanged?.call();
            },
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.notifications_outlined),
            ),
          );
        },
      );
}

class InAppNotificationsPage extends StatefulWidget {
  const InAppNotificationsPage({
    super.key,
    required this.recipientRole,
    this.flatId,
    this.guardId,
  });
  final String recipientRole;
  final int? flatId;
  final int? guardId;
  @override
  State<InAppNotificationsPage> createState() => _InAppNotificationsPageState();
}

class _InAppNotificationsPageState extends State<InAppNotificationsPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            TextButton(
              onPressed: () async {
                await db.markAllNotificationsRead(
                  recipientRole: widget.recipientRole,
                  flatId: widget.flatId,
                  guardId: widget.guardId,
                );
                if (mounted) setState(() {});
              },
              child: const Text('Mark all read'),
            ),
          ],
        ),
        body: FutureBuilder<List<dynamic>>(
          future: db.appNotifications(
            recipientRole: widget.recipientRole,
            flatId: widget.flatId,
            guardId: widget.guardId,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const LoadingView(label: 'Loading notifications…');
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const EmptyState(
                'No in-app notifications yet.\nSame-device demo: switch accounts on this phone to see approval updates.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = rows[i];
                final unread = (n.data['is_read'] as int? ?? 0) == 0;
                return AppCard(
                  onTap: () async {
                    await db.markNotificationRead(n.read<int>('id'));
                    if (mounted) setState(() {});
                  },
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              n.read<String>('title'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: C.navy,
                                  fontSize: unread ? 15 : 14),
                            ),
                          ),
                          if (unread) const StatusBadge('new'),
                        ]),
                        const SizedBox(height: 6),
                        Text(n.read<String>('body'),
                            style: const TextStyle(
                                color: C.muted,
                                fontWeight: FontWeight.w600,
                                height: 1.35)),
                        const SizedBox(height: 6),
                        Text(shortDate(n.read<String>('created_at')),
                            style:
                                const TextStyle(fontSize: 11, color: C.muted)),
                      ]),
                );
              },
            );
          },
        ),
      );
}

class AdminSecurityStaffPage extends StatefulWidget {
  const AdminSecurityStaffPage({super.key});
  @override
  State<AdminSecurityStaffPage> createState() => _AdminSecurityStaffPageState();
}

class _AdminSecurityStaffPageState extends State<AdminSecurityStaffPage> {
  Future<void> openEditor([dynamic row]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SecurityGuardEditorPage(guard: row)),
    );
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => openEditor(),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add guard'),
        ),
        body: FutureBuilder<List<dynamic>>(
          future: db.securityGuards(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const LoadingView(label: 'Loading security staff…');
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty)
              return const EmptyState('No security accounts yet');
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const InfoNote(
                    'Only mobiles listed here can sign in as Security Guard. Demo: $kDemoGuardMobile · Login OTP $kDemoOtp'),
                const SizedBox(height: 12),
                ...rows.map((r) {
                  final active = (r.data['is_active'] as int? ?? 1) == 1;
                  return AppCard(
                    onTap: () => openEditor(r),
                    child: ListTile(
                      leading: CircleAvatar(
                          backgroundColor: C.chip,
                          child: Icon(Icons.security,
                              color: active ? C.blue : C.muted)),
                      title: Text(r.read<String>('name'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: C.navy)),
                      subtitle: Text(r.read<String>('mobile')),
                      trailing: StatusBadge(active ? 'active' : 'inactive'),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );
}

class SecurityGuardEditorPage extends StatefulWidget {
  const SecurityGuardEditorPage({super.key, this.guard});
  final dynamic guard;
  @override
  State<SecurityGuardEditorPage> createState() =>
      _SecurityGuardEditorPageState();
}

class _SecurityGuardEditorPageState extends State<SecurityGuardEditorPage> {
  late final TextEditingController name;
  late final TextEditingController mobile;
  late final TextEditingController notes;
  bool busy = false;
  String? error;
  bool get editing => widget.guard != null;

  @override
  void initState() {
    super.initState();
    name =
        TextEditingController(text: widget.guard?.read<String>('name') ?? '');
    mobile =
        TextEditingController(text: widget.guard?.read<String>('mobile') ?? '');
    notes = TextEditingController(
        text: (widget.guard?.data['notes'] as String?) ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    mobile.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (editing) {
        await db.updateSecurityGuard(
            id: widget.guard.read<int>('id'),
            name: name.text,
            mobile: mobile.text.trim(),
            notes: notes.text);
      } else {
        await db.createSecurityGuard(
            name: name.text, mobile: mobile.text.trim(), notes: notes.text);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error =
          e is StateError ? e.message : 'Could not save security account.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggleActive() async {
    final active = (widget.guard.data['is_active'] as int? ?? 1) == 1;
    await db.setSecurityGuardActive(widget.guard.read<int>('id'), !active);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(editing ? 'Edit security guard' : 'Add security guard')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 12),
            TextField(
              controller: mobile,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Authorized mobile', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: notes,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)')),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      style: const TextStyle(
                          color: C.error, fontWeight: FontWeight.w700))),
            const SizedBox(height: 18),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(editing ? 'Save changes' : 'Authorize guard')),
            if (editing) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: busy ? null : toggleActive,
                child: Text((widget.guard.data['is_active'] as int? ?? 1) == 1
                    ? 'Deactivate account'
                    : 'Reactivate account'),
              ),
            ],
          ],
        ),
      );
}

class AdminMorePage extends StatelessWidget {
  const AdminMorePage({super.key, required this.onOpen});
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionTitle('Society management'),
          const SizedBox(height: 12),
          QuickActionTile(
              icon: Icons.people_outline,
              label: 'Residents',
              onTap: () => onOpen('residents')),
          QuickActionTile(
              icon: Icons.groups_outlined,
              label: 'Visitors',
              onTap: () => onOpen('visitors')),
          QuickActionTile(
              icon: Icons.directions_car_outlined,
              label: 'Vehicles',
              onTap: () => onOpen('vehicles')),
          QuickActionTile(
              icon: Icons.report_problem_outlined,
              label: 'Complaints',
              onTap: () => onOpen('complaints')),
          QuickActionTile(
              icon: Icons.badge_outlined,
              label: 'Staff HR',
              onTap: () => onOpen('staff')),
          QuickActionTile(
              icon: Icons.fact_check_outlined,
              label: 'Attendance',
              onTap: () => onOpen('attendance')),
          QuickActionTile(
              icon: Icons.schedule_outlined,
              label: 'Shifts',
              onTap: () => onOpen('shifts')),
          QuickActionTile(
              icon: Icons.meeting_room_outlined,
              label: 'Facilities',
              onTap: () => onOpen('facilities')),
          QuickActionTile(
              icon: Icons.event_available_outlined,
              label: 'Facility bookings',
              onTap: () => onOpen('facility-bookings')),
          QuickActionTile(
              icon: Icons.campaign_outlined,
              label: 'Announcements',
              onTap: () => onOpen('announcements')),
          QuickActionTile(
              icon: Icons.assessment_outlined,
              label: 'Reports & Analytics',
              onTap: () => onOpen('reports')),
          QuickActionTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => onOpen('settings')),
        ],
      );
}
