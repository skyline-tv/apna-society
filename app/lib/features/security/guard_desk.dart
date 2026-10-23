import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/auth/home_resolver.dart';
import '../../api/models/society_models.dart';
import '../../api/models/vehicle_models.dart';
import '../../api/models/visitor_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../services/session_store.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import '../visitors/visitor_messages.dart';

/// Simplified gate desk: New Visitor, Verify OTP, Check Vehicle.
class GuardDeskHome extends StatefulWidget {
  const GuardDeskHome({super.key, required this.guard});
  final dynamic guard;

  @override
  State<GuardDeskHome> createState() => _GuardDeskHomeState();
}

class _GuardDeskHomeState extends State<GuardDeskHome> {
  late Future<GuardDashboard> _dashboard = _load();
  StreamSubscription<VisitorEventPayload>? _sub;

  Future<GuardDashboard> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).visitors.guardDashboard(
          force: force,
        );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.events.listen((_) {
      if (mounted) setState(() => _dashboard = _load(force: true));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _dashboard = _load(force: true));

  Future<void> _logout() async {
    final ok = await confirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need your username and password to sign in again.',
      confirmLabel: 'Log out',
      icon: Icons.logout_rounded,
    );
    if (!ok) return;
    final session = authSession;
    if (session != null) {
      await performLogout(session);
    } else {
      await SessionStore.clear();
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.guard.read<String>('name').split(' ').first;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: Text('Hello, $name'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: FutureBuilder<GuardDashboard>(
        future: _dashboard,
        builder: (context, snapshot) {
          final pending = snapshot.data?.pendingApprovals ?? 0;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              _reload();
              await _dashboard;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: Sp.pageInsets(context),
              children: [
                if (snapshot.hasError && snapshot.data == null) ...[
                  const InlineError(
                      'Could not load waiting visitors. Pull to retry.'),
                  const SizedBox(height: 16),
                ] else if (pending > 0) ...[
                  _PendingBanner(
                    count: pending,
                    onTap: () => _open(const GuardPendingPage()),
                  ),
                  const SizedBox(height: 16),
                ],
                _BigActionButton(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'New Visitor',
                  subtitle: 'Send for approval',
                  color: C.blue,
                  onTap: () => _open(const GuardNewVisitorPage()),
                ),
                const SizedBox(height: 14),
                _BigActionButton(
                  icon: Icons.pin_rounded,
                  label: 'Verify OTP',
                  subtitle: 'Check the 6-digit code',
                  color: C.green,
                  onTap: () => _open(const GuardVerifyOtpPage()),
                ),
                const SizedBox(height: 14),
                _BigActionButton(
                  icon: Icons.directions_car_rounded,
                  label: 'Check Vehicle',
                  subtitle: 'Is this a building vehicle?',
                  color: C.navy,
                  onTap: () => _open(const GuardVehicleCheckPage()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.amberSoft,
      borderRadius: BorderRadius.circular(Rd.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: C.amber, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 visitor waiting for approval'
                      : '$count visitors waiting for approval',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: C.navy,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: C.amber),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigActionButton extends StatelessWidget {
  const _BigActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class GuardNewVisitorPage extends StatefulWidget {
  const GuardNewVisitorPage({super.key});

  @override
  State<GuardNewVisitorPage> createState() => _GuardNewVisitorPageState();
}

class _GuardNewVisitorPageState extends State<GuardNewVisitorPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _purpose = TextEditingController();
  String _type = 'GUEST';
  SocietyFlatPick? _flat;
  List<SocietyFlatPick> _flats = const [];
  bool _loadingFlats = true;
  bool _submitting = false;
  String? _error;

  static const _types = [
    ('GUEST', 'Guest'),
    ('DELIVERY', 'Delivery'),
    ('CAB', 'Cab'),
    ('COURIER', 'Courier'),
    ('SERVICE_PROVIDER', 'Help / work'),
    ('OTHER', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _loadFlats();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _loadFlats() async {
    setState(() {
      _loadingFlats = true;
      _error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final societyId = session.client.societyId;
      if (societyId == null || societyId.isEmpty) {
        throw StateError('Society context is required.');
      }
      final flats = await ensureLiveRepositories(session.api)
          .society
          .listMemberFlats(societyId: societyId, force: true);
      if (!mounted) return;
      setState(() {
        _flats = flats;
        _loadingFlats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFlats = false;
        _error = visitorErrorMessage(e);
      });
    }
  }

  Future<void> _pickFlat() async {
    final picked = await showModalBottomSheet<SocietyFlatPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _FlatSheet(flats: _flats, selected: _flat),
      ),
    );
    if (picked != null) setState(() => _flat = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final valid = _form.currentState?.validate() ?? false;
    if (!valid || _flat == null) {
      setState(() {
        _error = _flat == null ? 'Select the flat.' : null;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final visitor = await ensureLiveRepositories(session.api).visitors.createVisitor(
            CreateVisitorRequest(
              flatId: _flat!.id,
              visitorName: _name.text.trim(),
              visitorPhone: _phone.text.trim(),
              visitorType: _type,
              purpose: _purpose.text.trim(),
              entryMode: 'WALK_IN',
            ),
          );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => GuardVisitorStatusPage(visitorId: visitor.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Visitor')),
      body: _loadingFlats
          ? const LoadingView(label: 'Loading flats…')
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                  const Text(
                    'Fill this form. The flat will get a call-style alert.',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: C.navy,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: 'Visitor name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter the name.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (digits.length < 8) return 'Enter a valid mobile number.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _pickFlat,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Flat number',
                        prefixIcon: const Icon(Icons.apartment_outlined),
                        errorText: _flat == null && _error == 'Select the flat.'
                            ? 'Select the flat.'
                            : null,
                      ),
                      child: Text(
                        _flat?.label ?? 'Tap to choose flat',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _flat == null ? C.muted : C.navy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Visitor type',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: C.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _types
                        .map(
                          (item) => ChoiceChip(
                            label: Text(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selected: _type == item.$1,
                            onSelected: (_) => setState(() {
                              _type = item.$1;
                              if (_purpose.text.trim().isEmpty) {
                                _purpose.text = item.$2;
                              }
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _purpose,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: 'Purpose of visit',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter the purpose.' : null,
                  ),
                  if (_error != null && _error != 'Select the flat.') ...[
                    const SizedBox(height: 16),
                    InlineError(_error),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            height: 64,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'SEND FOR APPROVAL',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlatSheet extends StatefulWidget {
  const _FlatSheet({required this.flats, this.selected});
  final List<SocietyFlatPick> flats;
  final SocietyFlatPick? selected;

  @override
  State<_FlatSheet> createState() => _FlatSheetState();
}

class _FlatSheetState extends State<_FlatSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = widget.flats
        .where((f) => q.isEmpty || f.label.toLowerCase().contains(q))
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose flat',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: C.navy,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                hintText: 'Search flat number',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final f = rows[i];
                  return ListTile(
                    title: Text(
                      f.label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    trailing: widget.selected?.id == f.id
                        ? const Icon(Icons.check_circle_rounded, color: C.blue)
                        : null,
                    onTap: () => Navigator.pop(context, f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GuardVisitorStatusPage extends StatefulWidget {
  const GuardVisitorStatusPage({super.key, required this.visitorId});
  final String visitorId;

  @override
  State<GuardVisitorStatusPage> createState() => _GuardVisitorStatusPageState();
}

class _GuardVisitorStatusPageState extends State<GuardVisitorStatusPage> {
  late Future<Visitor> _future = _load();
  StreamSubscription<VisitorEventPayload>? _sub;
  bool _busy = false;

  Future<Visitor> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .guardVisitor(widget.visitorId, force: force);
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.events.listen((_) {
      if (mounted) setState(() => _future = _load(force: true));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _confirm(Visitor visitor) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final entered = await ensureLiveRepositories(session.api)
          .visitors
          .confirmVisitorEntry(visitor.id);
      if (!mounted) return;
      setState(() => _future = Future.value(entered));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visitor status')),
      body: FutureBuilder<Visitor>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Checking status…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final v = snapshot.data!;
          final canConfirm = v.approvalStatus == 'APPROVED' &&
              v.entryStatus == 'NOT_ENTERED' &&
              (v.isWalkIn || v.otpVerified);
          final needsOtp = v.approvalStatus == 'APPROVED' &&
              v.entryStatus == 'NOT_ENTERED' &&
              !v.isWalkIn &&
              !v.otpVerified;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _StatusCard(visitor: v),
                const SizedBox(height: 20),
                Text(
                  v.visitorName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: C.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Flat ${v.flatLabel}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: C.muted,
                  ),
                ),
                if (v.entryAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Entered at ${fmtIsoDateTime(v.entryAt)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: C.green,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (needsOtp)
                  SizedBox(
                    height: 64,
                    child: FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const GuardVerifyOtpPage(),
                        ),
                      ),
                      child: const Text(
                        'Verify OTP',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                if (canConfirm)
                  SizedBox(
                    height: 64,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _confirm(v),
                      child: Text(
                        _busy ? 'Saving…' : 'Confirm they entered',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.visitor});
  final Visitor visitor;

  @override
  Widget build(BuildContext context) {
    final v = visitor;
    late final Color bg;
    late final Color fg;
    late final String label;
    late final IconData icon;
    if (v.entryStatus == 'ENTERED' || v.entryStatus == 'EXITED') {
      bg = C.greenSoft;
      fg = C.green;
      label = 'Entered';
      icon = Icons.login_rounded;
    } else if (v.approvalStatus == 'PENDING') {
      bg = C.amberSoft;
      fg = C.amber;
      label = 'Waiting for Approval';
      icon = Icons.hourglass_top_rounded;
    } else if (v.approvalStatus == 'APPROVED') {
      bg = C.greenSoft;
      fg = C.green;
      label = 'Approved';
      icon = Icons.check_circle_rounded;
    } else if (v.approvalStatus == 'REJECTED') {
      bg = C.errorSoft;
      fg = C.error;
      label = 'Rejected';
      icon = Icons.cancel_rounded;
    } else {
      bg = C.neutralSoft;
      fg = C.muted;
      label = approvalStatusLabel(v.approvalStatus);
      icon = Icons.info_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GuardPendingPage extends StatefulWidget {
  const GuardPendingPage({super.key});

  @override
  State<GuardPendingPage> createState() => _GuardPendingPageState();
}

class _GuardPendingPageState extends State<GuardPendingPage> {
  late Future<List<Visitor>> _future = _load();

  Future<List<Visitor>> _load() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final page = await ensureLiveRepositories(session.api).visitors.listGuardVisitors(
          query: const ListVisitorsQuery(
            approvalStatus: 'PENDING',
            limit: 50,
          ),
          force: true,
        );
    return page.items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Waiting for approval')),
      body: FutureBuilder<List<Visitor>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const EmptyState('No visitors waiting');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final v = items[i];
              return ListTile(
                tileColor: C.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Text(
                  v.visitorName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  'Flat ${v.flatLabel} · Waiting for Approval',
                  style: const TextStyle(fontSize: 16),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => GuardVisitorStatusPage(visitorId: v.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class GuardVerifyOtpPage extends StatefulWidget {
  const GuardVerifyOtpPage({super.key});

  @override
  State<GuardVerifyOtpPage> createState() => _GuardVerifyOtpPageState();
}

class _GuardVerifyOtpPageState extends State<GuardVerifyOtpPage> {
  final _otp = TextEditingController();
  final _focus = FocusNode();
  Visitor? _verified;
  bool _busy = false;
  String? _error;
  bool _failed = false;

  @override
  void dispose() {
    _otp.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final otp = _otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() {
        _failed = true;
        _error = 'Enter all 6 digits.';
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _failed = false;
      _verified = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final visitor = await ensureLiveRepositories(session.api)
          .visitors
          .verifyEntryOtpByCode(otp: otp);
      if (!mounted) return;
      setState(() {
        _verified = visitor;
        _failed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verified = null;
        _failed = true;
        _error = visitorErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final visitor = _verified;
    if (_busy || visitor == null) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final entered = await ensureLiveRepositories(session.api)
          .visitors
          .confirmVisitorEntry(visitor.id);
      if (!mounted) return;
      setState(() => _verified = entered);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _verified;
    final entered = verified?.entryStatus == 'ENTERED';
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (verified == null) ...[
            const Text(
              'Type the 6-digit OTP.',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: C.navy,
              ),
            ),
            const SizedBox(height: 18),
            OtpBoxes(
              controller: _otp,
              focusNode: _focus,
              enabled: !_busy,
              autofocus: true,
              onSubmitted: (_) => _verify(),
            ),
            if (_failed) ...[
              const SizedBox(height: 20),
              _ResultBanner(
                ok: false,
                title: 'NOT ALLOWED',
                body: _error ??
                    'This OTP is wrong or expired. Do not let them in.',
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              height: 64,
              child: FilledButton(
                onPressed: _busy ? null : _verify,
                child: Text(
                  _busy ? 'Checking…' : 'Verify',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ] else ...[
            _ResultBanner(
              ok: true,
              title: entered ? 'ENTERED' : 'OTP OK',
              body: entered
                  ? '${verified.visitorName} has entered Flat ${verified.flatLabel}.'
                  : '${verified.visitorName} · Flat ${verified.flatLabel}. Tap below when they walk in.',
            ),
            if (!entered) ...[
              const SizedBox(height: 24),
              SizedBox(
                height: 64,
                child: FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: Text(
                    _busy ? 'Saving…' : 'Confirm they entered',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _otp.clear();
                      setState(() {
                        _verified = null;
                        _error = null;
                        _failed = false;
                      });
                      _focus.requestFocus();
                    },
              child: const Text('Check another OTP'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({
    required this.ok,
    required this.title,
    required this.body,
  });

  final bool ok;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final bg = ok ? C.greenSoft : C.errorSoft;
    final fg = ok ? C.green : C.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class GuardVehicleCheckPage extends StatefulWidget {
  const GuardVehicleCheckPage({super.key});

  @override
  State<GuardVehicleCheckPage> createState() => _GuardVehicleCheckPageState();
}

class _GuardVehicleCheckPageState extends State<GuardVehicleCheckPage> {
  final _reg = TextEditingController();
  bool _busy = false;
  VehicleLookup? _result;
  String? _error;

  @override
  void dispose() {
    _reg.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    final plate = normalizeRegistrationNumber(_reg.text);
    if (!isValidIndianRegistrationNumber(plate)) {
      setState(() {
        _result = null;
        _error = 'Enter a valid vehicle number.';
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final lookup = await ensureLiveRepositories(session.api)
          .vehicles
          .lookup(registrationNumber: plate);
      if (!mounted) return;
      setState(() => _result = lookup);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Check Vehicle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Text(
            'Enter the vehicle number.',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: C.navy,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reg,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
            decoration: const InputDecoration(
              labelText: 'Vehicle number',
              hintText: 'MH12AB1234',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s-]')),
            ],
            onSubmitted: (_) => _check(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 64,
            child: FilledButton(
              onPressed: _busy ? null : _check,
              child: Text(
                _busy ? 'Checking…' : 'Check',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            InlineError(_error),
          ],
          if (result != null) ...[
            const SizedBox(height: 24),
            _ResultBanner(
              ok: result.registered,
              title: result.registered ? 'BUILDING VEHICLE' : 'NOT REGISTERED',
              body: result.registered
                  ? '${result.registrationNumber} is registered with the society.'
                  : '${result.registrationNumber} is not a society vehicle.',
            ),
          ],
        ],
      ),
    );
  }
}
