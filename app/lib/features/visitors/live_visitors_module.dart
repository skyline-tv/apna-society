import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/common.dart';
import '../../api/models/society_models.dart';
import '../../api/models/visitor_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../api/socket/visitor_socket.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import '../vehicles/live_vehicles_module.dart';

String visitorErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'NO_ACTIVE_RESIDENT':
        return 'This flat has no active resident to approve visitors.';
      case 'FLAT_INACTIVE':
        return 'This flat is inactive.';
      case 'INVALID_OCCUPANCY':
        return 'This flat occupancy cannot receive visitors.';
      case 'VISITOR_EMAIL_REQUIRED':
        return 'A visitor or resident email is required for entry OTP delivery.';
      case 'NOT_APPROVED':
        return 'Visitor is not approved for entry yet.';
      case 'OTP_MISSING':
        return 'No active entry OTP for this visitor.';
      case 'OTP_EXPIRED':
        return 'Entry OTP has expired. Ask the resident to approve again.';
      case 'OTP_INVALID':
        return 'Incorrect OTP. Try again.';
      case 'OTP_MAX_ATTEMPTS':
        return 'Too many incorrect OTP attempts. Entry is locked.';
      case 'ALREADY_ENTERED':
        return 'This visitor has already entered.';
      case 'NOT_ENTERED':
        return 'Visitor has not entered yet.';
      case 'CHECKOUT_CONFLICT':
        return 'Checkout conflict. Refresh and try again.';
      case 'NOT_CURRENT_APPROVER':
        return 'You are no longer the approver for this flat.';
      case 'INVALID_STATUS':
        return 'This action is not allowed in the current visitor status.';
      case 'ALREADY_PROCESSED':
        return 'This request was already processed.';
      case 'RATE_LIMITED':
        return 'Too many OTP attempts. Wait and try again.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this visitor action.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

String _shortIso(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day}/${d.month}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

Widget visitorStatusChips(Visitor v) {
  return Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      StatusBadge(approvalStatusLabel(v.approvalStatus)),
      StatusBadge(entryStatusLabel(v.entryStatus)),
    ],
  );
}

// ─── Guard shell pages ───────────────────────────────────────────────────────

class LiveGuardDashboardPage extends StatefulWidget {
  const LiveGuardDashboardPage({
    super.key,
    required this.guardName,
    required this.onNavigate,
  });

  final String guardName;
  final ValueChanged<int> onNavigate;

  @override
  State<LiveGuardDashboardPage> createState() => _LiveGuardDashboardPageState();
}

class _LiveGuardDashboardPageState extends State<LiveGuardDashboardPage> {
  late Future<GuardDashboard> _future = _load();
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
      if (mounted) setState(() => _future = _load(force: true));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GuardDashboard>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading gate overview…');
        }
        if (snapshot.hasError) {
          return LoadFailure(
            error: snapshot.error!,
            onRetry: reload,
            title: 'Could not load dashboard',
          );
        }
        final d = snapshot.data!;
        final first = widget.guardName.split(' ').first;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                'Hello, $first',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Security desk · live visitors',
                style: TextStyle(color: C.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              AppCard(
                onTap: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LiveAddGateVisitorPage(),
                    ),
                  );
                  if (changed == true) {
                    reload();
                    widget.onNavigate(2);
                  }
                },
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: C.chip,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_outlined,
                        color: C.blue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Register visitor',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Send approval request to the flat resident',
                            style: TextStyle(color: C.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: C.muted),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LiveGuardVehiclesPage(),
                    ),
                  );
                },
                padding: const EdgeInsets.all(18),
                child: const Row(
                  children: [
                    Icon(Icons.directions_car_outlined, color: C.blue),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vehicle gate',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Record vehicle entry and exit',
                            style: TextStyle(color: C.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: C.muted),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.45,
                children: [
                  _StatTile(
                    label: 'Inside now',
                    value: '${d.currentlyInside}',
                    onTap: () => widget.onNavigate(3),
                  ),
                  _StatTile(
                    label: 'Pending approval',
                    value: '${d.pendingApprovals}',
                    onTap: () => widget.onNavigate(2),
                  ),
                  _StatTile(
                    label: 'Awaiting entry',
                    value: '${d.awaitingEntry}',
                    onTap: () => widget.onNavigate(1),
                  ),
                  _StatTile(
                    label: 'Entered today',
                    value: '${d.enteredToday}',
                    onTap: () => widget.onNavigate(2),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Recent',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: C.navy,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              if (d.recent.isEmpty)
                const EmptyState('No recent visitors')
              else
                ...d.recent.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LiveGuardVisitorDetailPage(visitorId: v.id),
                        ),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.visitorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${v.wingCodeSnapshot}-${v.flatNumberSnapshot} · '
                            '${visitorTypeLabel(v.visitorType)}',
                            style: const TextStyle(color: C.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          visitorStatusChips(v),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: C.navy,
            ),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: C.muted,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class LiveAddGateVisitorPage extends StatefulWidget {
  const LiveAddGateVisitorPage({super.key});

  @override
  State<LiveAddGateVisitorPage> createState() => _LiveAddGateVisitorPageState();
}

class _LiveAddGateVisitorPageState extends State<LiveAddGateVisitorPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _purpose = TextEditingController();
  final _vehicle = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'GUEST';
  int _count = 1;
  SocietyFlatPick? _flat;
  List<SocietyFlatPick> _flats = const [];
  bool _loadingFlats = true;
  bool _submitting = false;
  String? _flatError;

  @override
  void initState() {
    super.initState();
    _loadFlats();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _purpose.dispose();
    _vehicle.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadFlats() async {
    setState(() {
      _loadingFlats = true;
      _flatError = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final societyId = session.client.societyId;
      if (societyId == null || societyId.isEmpty) {
        throw StateError('Society context is required.');
      }
      // Guards cannot call /admin/flats; use society member foundation route.
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
        _flatError = visitorErrorMessage(e);
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final flat = _flat;
    if (flat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a flat')),
      );
      return;
    }
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final purpose = _purpose.text.trim();
    if (name.isEmpty || phone.isEmpty || purpose.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, phone, and purpose are required')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.createVisitor(
            CreateVisitorRequest(
              flatId: flat.id,
              visitorName: name,
              visitorPhone: phone,
              visitorEmail:
                  _email.text.trim().isEmpty ? null : _email.text.trim(),
              visitorType: _type,
              purpose: purpose,
              vehicleNumber:
                  _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
              numberOfVisitors: _count,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Visitor request sent for resident approval'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(visitorErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register visitor')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (_loadingFlats)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_flatError != null)
            LoadFailure(error: _flatError!, onRetry: _loadFlats)
          else ...[
            DropdownButtonFormField<SocietyFlatPick>(
              value: _flat,
              decoration: const InputDecoration(
                labelText: 'Flat',
                border: OutlineInputBorder(),
              ),
              items: _flats
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(f.label),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _flat = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Visitor name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Visitor phone',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Visitor email (for OTP delivery)',
                helperText:
                    'Entry OTP is emailed by the server. Prefer visitor email.',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Visitor type',
                border: OutlineInputBorder(),
              ),
              items: kVisitorTypes
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(visitorTypeLabel(t)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'GUEST'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purpose,
              decoration: const InputDecoration(
                labelText: 'Purpose',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vehicle,
              decoration: const InputDecoration(
                labelText: 'Vehicle number (optional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Visitors', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: _count > 1
                      ? () => setState(() => _count--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_count', style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  onPressed: _count < 50
                      ? () => setState(() => _count++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Submit request'),
            ),
          ],
        ],
      ),
    );
  }
}

class LiveVerifyVisitorOtpPage extends StatefulWidget {
  const LiveVerifyVisitorOtpPage({
    super.key,
    required this.onEntered,
  });

  final VoidCallback onEntered;

  @override
  State<LiveVerifyVisitorOtpPage> createState() =>
      _LiveVerifyVisitorOtpPageState();
}

class _LiveVerifyVisitorOtpPageState extends State<LiveVerifyVisitorOtpPage> {
  late Future<Paged<Visitor>> _future = _load();
  final _otp = TextEditingController();
  Visitor? _selected;
  bool _verifying = false;
  StreamSubscription<VisitorEventPayload>? _sub;

  Future<Paged<Visitor>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).visitors.listGuardVisitors(
          force: force,
          query: const ListVisitorsQuery(
            approvalStatus: 'APPROVED',
            entryStatus: 'NOT_ENTERED',
            limit: 50,
          ),
        );
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
    _otp.dispose();
    super.dispose();
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _verify() async {
    if (_verifying) return;
    final visitor = _selected;
    final otp = _otp.text.trim();
    if (visitor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a visitor')),
      );
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit OTP')),
      );
      return;
    }
    setState(() => _verifying = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api)
          .visitors
          .verifyEntryOtp(visitor.id, otp: otp);
      if (!mounted) return;
      _otp.clear();
      setState(() => _selected = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry recorded')),
      );
      reload();
      widget.onEntered();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(visitorErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Visitor>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading awaiting entry…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              const Text(
                'Verify entry OTP',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'OTP is emailed by the server. Enter the code the visitor shows you.',
                style: TextStyle(color: C.muted),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const EmptyState('No approved visitors awaiting entry')
              else ...[
                ...items.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => setState(() => _selected = v),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.visitorName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: C.navy,
                                  ),
                                ),
                                Text(
                                  '${v.wingCodeSnapshot}-${v.flatNumberSnapshot}'
                                  '${v.hasActiveOtp ? ' · OTP active' : ''}',
                                  style: const TextStyle(
                                    color: C.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_selected?.id == v.id)
                            const Icon(Icons.check_circle, color: C.blue),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _otp,
                  decoration: const InputDecoration(
                    labelText: '6-digit OTP',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _verifying ? null : _verify,
                  child: Text(_verifying ? 'Verifying…' : 'Verify & enter'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class LiveGateVisitorBoardPage extends StatefulWidget {
  const LiveGateVisitorBoardPage({super.key});

  @override
  State<LiveGateVisitorBoardPage> createState() =>
      _LiveGateVisitorBoardPageState();
}

class _LiveGateVisitorBoardPageState extends State<LiveGateVisitorBoardPage> {
  String? approvalFilter;
  String? entryFilter;
  late Future<Paged<Visitor>> _future = _load();
  StreamSubscription<VisitorEventPayload>? _sub;

  Future<Paged<Visitor>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).visitors.listGuardVisitors(
          force: force,
          query: ListVisitorsQuery(
            approvalStatus: approvalFilter,
            entryStatus: entryFilter,
            limit: 50,
          ),
        );
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

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Visitor>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading gate board…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Gate board',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveAddGateVisitorPage(),
                        ),
                      );
                      if (ok == true) reload();
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: approvalFilter == null && entryFilter == null,
                    onSelected: (_) {
                      setState(() {
                        approvalFilter = null;
                        entryFilter = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Pending'),
                    selected: approvalFilter == 'PENDING',
                    onSelected: (_) {
                      setState(() {
                        approvalFilter = 'PENDING';
                        entryFilter = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Awaiting entry'),
                    selected: approvalFilter == 'APPROVED' &&
                        entryFilter == 'NOT_ENTERED',
                    onSelected: (_) {
                      setState(() {
                        approvalFilter = 'APPROVED';
                        entryFilter = 'NOT_ENTERED';
                        _future = _load(force: true);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No visitors match these filters')
              else
                ...items.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveGuardVisitorDetailPage(visitorId: v.id),
                          ),
                        );
                        reload();
                      },
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.visitorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${v.wingCodeSnapshot}-${v.flatNumberSnapshot} · '
                            '${visitorTypeLabel(v.visitorType)} · ${v.purpose}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          visitorStatusChips(v),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class LiveInsideVisitorsPage extends StatefulWidget {
  const LiveInsideVisitorsPage({super.key});

  @override
  State<LiveInsideVisitorsPage> createState() => _LiveInsideVisitorsPageState();
}

class _LiveInsideVisitorsPageState extends State<LiveInsideVisitorsPage> {
  late Future<Paged<Visitor>> _future = _load();
  final _busyIds = <String>{};
  StreamSubscription<VisitorEventPayload>? _sub;

  Future<Paged<Visitor>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).visitors.listGuardVisitors(
          force: force,
          query: const ListVisitorsQuery(
            entryStatus: 'ENTERED',
            limit: 50,
          ),
        );
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

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _checkout(Visitor v) async {
    if (_busyIds.contains(v.id)) return;
    setState(() => _busyIds.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.checkout(v.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${v.visitorName} checked out')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(visitorErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(v.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Visitor>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading inside visitors…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              const Text(
                'Inside now',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No visitors currently inside')
              else
                ...items.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.visitorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${v.wingCodeSnapshot}-${v.flatNumberSnapshot} · '
                            'In since ${_shortIso(v.entryAt)}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: _busyIds.contains(v.id)
                                  ? null
                                  : () => _checkout(v),
                              child: Text(
                                _busyIds.contains(v.id)
                                    ? 'Checking out…'
                                    : 'Checkout',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class LiveGuardVisitorDetailPage extends StatefulWidget {
  const LiveGuardVisitorDetailPage({super.key, required this.visitorId});
  final String visitorId;

  @override
  State<LiveGuardVisitorDetailPage> createState() =>
      _LiveGuardVisitorDetailPageState();
}

class _LiveGuardVisitorDetailPageState
    extends State<LiveGuardVisitorDetailPage> {
  late Future<Visitor> _future = _load();

  Future<Visitor> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .guardVisitor(widget.visitorId, force: force);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visitor detail')),
      body: FutureBuilder<Visitor>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading visitor…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          return _VisitorDetailBody(visitor: snapshot.data!);
        },
      ),
    );
  }
}

class _VisitorDetailBody extends StatelessWidget {
  const _VisitorDetailBody({required this.visitor});
  final Visitor visitor;

  @override
  Widget build(BuildContext context) {
    final v = visitor;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text(
          v.visitorName,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: C.navy,
          ),
        ),
        const SizedBox(height: 8),
        visitorStatusChips(v),
        const SizedBox(height: 16),
        _line('Flat', '${v.wingCodeSnapshot}-${v.flatNumberSnapshot}'),
        _line('Type', visitorTypeLabel(v.visitorType)),
        _line('Purpose', v.purpose),
        _line('Phone', v.visitorPhone),
        _line('Party size', '${v.numberOfVisitors}'),
        if (v.vehicleNumber != null) _line('Vehicle', v.vehicleNumber!),
        _line('Assigned role', v.assignedResidentRole),
        _line('Requested', _shortIso(v.createdAt)),
        if (v.approvedAt != null) _line('Approved', _shortIso(v.approvedAt)),
        if (v.rejectedAt != null) _line('Rejected', _shortIso(v.rejectedAt)),
        if (v.rejectionReason != null)
          _line('Rejection reason', v.rejectionReason!),
        if (v.entryAt != null) _line('Entered', _shortIso(v.entryAt)),
        if (v.exitAt != null) _line('Exited', _shortIso(v.exitAt)),
        if (v.expiredAt != null) _line('Expired', _shortIso(v.expiredAt)),
        if (v.hasActiveOtp) _line('OTP', 'Active (code not shown)'),
        if (v.otpExpiresAt != null)
          _line('OTP expires', _shortIso(v.otpExpiresAt)),
        if (v.notes != null) _line('Notes', v.notes!),
      ],
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: C.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: C.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Resident ────────────────────────────────────────────────────────────────

class LiveResidentVisitorsPage extends StatefulWidget {
  const LiveResidentVisitorsPage({super.key});

  @override
  State<LiveResidentVisitorsPage> createState() =>
      _LiveResidentVisitorsPageState();
}

class _LiveResidentVisitorsPageState extends State<LiveResidentVisitorsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this);
  late Future<Paged<Visitor>> _pending = _loadPending();
  late Future<Paged<Visitor>> _history = _loadHistory();
  StreamSubscription<VisitorEventPayload>? _sub;
  final _busy = <String>{};

  Future<Paged<Visitor>> _loadPending({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .pendingVisitors(force: force, limit: 50);
  }

  Future<Paged<Visitor>> _loadHistory({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).visitors.listResidentVisitors(
          force: force,
          query: const ListVisitorsQuery(limit: 50),
        );
  }

  @override
  void initState() {
    super.initState();
    _sub = VisitorSocket.instance.events.listen((_) {
      if (mounted) {
        setState(() {
          _pending = _loadPending(force: true);
          _history = _loadHistory(force: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void reload() {
    setState(() {
      _pending = _loadPending(force: true);
      _history = _loadHistory(force: true);
    });
  }

  Future<void> _approve(Visitor v) async {
    if (_busy.contains(v.id)) return;
    setState(() => _busy.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.approve(v.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approved. Entry OTP emailed by the server.'),
        ),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(visitorErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  Future<void> _reject(Visitor v) async {
    if (_busy.contains(v.id)) return;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject visitor'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final reason = reasonCtrl.text.trim();
      await ensureLiveRepositories(session.api).visitors.reject(
            v.id,
            reason: reason.isEmpty ? null : reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visitor rejected')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(visitorErrorMessage(e))),
      );
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  Future<void> _cancel(Visitor v) async {
    if (_busy.contains(v.id)) return;
    setState(() => _busy.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.cancel(v.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visitor request cancelled')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(visitorErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  Widget _list(
    Future<Paged<Visitor>> future, {
    required bool showActions,
  }) {
    return FutureBuilder<Paged<Visitor>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading visitors…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        if (items.isEmpty) {
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async => reload(),
            child: ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState('No visitors'),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final v = items[i];
              final canAct = showActions &&
                  v.approvalStatus == 'PENDING' &&
                  v.entryStatus == 'NOT_ENTERED';
              final canCancel = showActions &&
                  (v.approvalStatus == 'PENDING' ||
                      v.approvalStatus == 'APPROVED') &&
                  v.entryStatus == 'NOT_ENTERED';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            LiveResidentVisitorDetailPage(visitorId: v.id),
                      ),
                    );
                    reload();
                  },
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.visitorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: C.navy,
                        ),
                      ),
                      Text(
                        '${v.wingCodeSnapshot}-${v.flatNumberSnapshot} · '
                        '${visitorTypeLabel(v.visitorType)} · ${v.purpose}',
                        style: const TextStyle(color: C.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      visitorStatusChips(v),
                      if (canAct || canCancel) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (canAct)
                              FilledButton(
                                onPressed: _busy.contains(v.id)
                                    ? null
                                    : () => _approve(v),
                                child: const Text('Approve'),
                              ),
                            if (canAct)
                              OutlinedButton(
                                onPressed: _busy.contains(v.id)
                                    ? null
                                    : () => _reject(v),
                                child: const Text('Reject'),
                              ),
                            if (canCancel && !canAct)
                              OutlinedButton(
                                onPressed: _busy.contains(v.id)
                                    ? null
                                    : () => _cancel(v),
                                child: const Text('Cancel'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: C.navy,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'History'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _list(_pending, showActions: true),
              _list(_history, showActions: true),
            ],
          ),
        ),
      ],
    );
  }
}

class LiveResidentVisitorDetailPage extends StatefulWidget {
  const LiveResidentVisitorDetailPage({super.key, required this.visitorId});
  final String visitorId;

  @override
  State<LiveResidentVisitorDetailPage> createState() =>
      _LiveResidentVisitorDetailPageState();
}

class _LiveResidentVisitorDetailPageState
    extends State<LiveResidentVisitorDetailPage> {
  late Future<Visitor> _future = _load();

  Future<Visitor> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .residentVisitor(widget.visitorId, force: force);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visitor detail')),
      body: FutureBuilder<Visitor>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading visitor…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          return _VisitorDetailBody(visitor: snapshot.data!);
        },
      ),
    );
  }
}

// ─── Admin ───────────────────────────────────────────────────────────────────

class LiveAdminVisitorsPage extends StatefulWidget {
  const LiveAdminVisitorsPage({super.key});

  @override
  State<LiveAdminVisitorsPage> createState() => _LiveAdminVisitorsPageState();
}

class _LiveAdminVisitorsPageState extends State<LiveAdminVisitorsPage> {
  String? approvalFilter;
  String? entryFilter;
  final _search = TextEditingController();
  late Future<_AdminVisitorsBundle> _future = _load();
  StreamSubscription<VisitorEventPayload>? _sub;

  Future<_AdminVisitorsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final name = _search.text.trim();
    final list = await repos.visitors.listAdminVisitors(
      force: force,
      query: ListVisitorsQuery(
        approvalStatus: approvalFilter,
        entryStatus: entryFilter,
        visitorName: name.isEmpty ? null : name,
        limit: 50,
      ),
    );
    final summary = await repos.visitors.adminSummary(force: force);
    return _AdminVisitorsBundle(list: list, summary: summary);
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
    _search.dispose();
    super.dispose();
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminVisitorsBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading visitors…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final bundle = snapshot.data!;
        final s = bundle.summary;
        final items = bundle.list.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              const Text(
                'Visitor management',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _miniStat('Total', '${s.total}'),
                  _miniStat(
                    'Pending',
                    '${s.byApprovalStatus['PENDING'] ?? 0}',
                  ),
                  _miniStat(
                    'Inside',
                    '${s.byEntryStatus['ENTERED'] ?? 0}',
                  ),
                  _miniStat(
                    'Exited',
                    '${s.byEntryStatus['EXITED'] ?? 0}',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search by name',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: reload,
                  ),
                ),
                onSubmitted: (_) => reload(),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: approvalFilter == null && entryFilter == null,
                    onSelected: (_) {
                      setState(() {
                        approvalFilter = null;
                        entryFilter = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  ...['PENDING', 'APPROVED', 'REJECTED', 'EXPIRED', 'CANCELLED']
                      .map(
                    (st) => FilterChip(
                      label: Text(approvalStatusLabel(st)),
                      selected: approvalFilter == st,
                      onSelected: (_) {
                        setState(() {
                          approvalFilter = st;
                          _future = _load(force: true);
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No visitors found')
              else
                ...items.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LiveAdminVisitorDetailPage(visitorId: v.id),
                        ),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.visitorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${v.wingCodeSnapshot}-${v.flatNumberSnapshot} · '
                            '${visitorTypeLabel(v.visitorType)} · '
                            'Assigned ${v.assignedResidentRole}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          visitorStatusChips(v),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, String value) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: C.navy,
              fontSize: 18,
            ),
          ),
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _AdminVisitorsBundle {
  const _AdminVisitorsBundle({required this.list, required this.summary});
  final Paged<Visitor> list;
  final AdminVisitorSummary summary;
}

class LiveAdminVisitorDetailPage extends StatefulWidget {
  const LiveAdminVisitorDetailPage({super.key, required this.visitorId});
  final String visitorId;

  @override
  State<LiveAdminVisitorDetailPage> createState() =>
      _LiveAdminVisitorDetailPageState();
}

class _LiveAdminVisitorDetailPageState
    extends State<LiveAdminVisitorDetailPage> {
  late Future<Visitor> _future = _load();

  Future<Visitor> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .adminVisitor(widget.visitorId, force: force);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visitor detail')),
      body: FutureBuilder<Visitor>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading visitor…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          return _VisitorDetailBody(visitor: snapshot.data!);
        },
      ),
    );
  }
}
