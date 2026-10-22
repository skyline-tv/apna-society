import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/common.dart';
import '../../api/models/resident_home_context.dart' show occupancyStatusLabel;
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

/// Approval + entry badges for a visitor.
Widget visitorStatusChips(Visitor v) {
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      StatusBadge(approvalStatusLabel(v.approvalStatus)),
      StatusBadge(entryStatusLabel(v.entryStatus)),
      if (v.hasActiveOtp)
        const StatusBadge('OTP active',
            tone: BadgeTone.info, icon: Icons.key_rounded),
    ],
  );
}

IconData _visitorTypeIcon(String type) {
  switch (type) {
    case 'DELIVERY':
      return Icons.local_shipping_outlined;
    case 'CAB':
      return Icons.local_taxi_outlined;
    case 'COURIER':
      return Icons.inventory_2_outlined;
    case 'SERVICE_PROVIDER':
      return Icons.handyman_outlined;
    case 'OTHER':
      return Icons.person_outline_rounded;
    default:
      return Icons.person_outline_rounded;
  }
}

Color _visitorTone(Visitor v) {
  if (v.entryStatus == 'ENTERED') return C.green;
  switch (v.approvalStatus) {
    case 'PENDING':
      return C.amber;
    case 'REJECTED':
      return C.error;
    case 'APPROVED':
      return C.blue;
    default:
      return C.muted;
  }
}

String _flatLabel(Visitor v) => '${v.wingCodeSnapshot}-${v.flatNumberSnapshot}';

/// Shared visitor list row.
class _VisitorRow extends StatelessWidget {
  const _VisitorRow({
    required this.visitor,
    this.onTap,
    this.footer,
    this.trailing,
    this.extra,
  });
  final Visitor visitor;
  final VoidCallback? onTap;
  final Widget? footer;
  final Widget? trailing;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final v = visitor;
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        icon: _visitorTypeIcon(v.visitorType),
        color: _visitorTone(v),
        size: 42,
      ),
      title: v.visitorName,
      subtitle:
          '${_flatLabel(v)} · ${visitorTypeLabel(v.visitorType)}${extra == null ? '' : ' · $extra'}',
      badges: [
        StatusBadge(approvalStatusLabel(v.approvalStatus)),
        StatusBadge(entryStatusLabel(v.entryStatus)),
        if (v.hasActiveOtp)
          const StatusBadge('OTP active',
              tone: BadgeTone.info, icon: Icons.key_rounded),
      ],
      trailing: trailing,
      footer: footer,
      showChevron: onTap != null && trailing == null,
    );
  }
}

Widget _emptyScrollable(Widget child, Future<void> Function() onRefresh) =>
    RefreshIndicator(
      color: C.blue,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [const SizedBox(height: 60), child],
      ),
    );

// ─── Guard shell pages ───────────────────────────────────────────────────────

class LiveGuardDashboardPage extends StatefulWidget {
  const LiveGuardDashboardPage({
    super.key,
    required this.guardName,
    required this.onNavigate,
    required this.onOpenQueue,
  });

  final String guardName;
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenQueue;

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

  Future<void> _register() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveAddGateVisitorPage()),
    );
    if (changed == true) {
      reload();
      widget.onOpenQueue();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GuardDashboard>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 4, showHeader: true);
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
          onRefresh: () async {
            reload();
            await _future;
          },
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ColoredBox(
                color: C.blueDark,
                child: SafeArea(
                  bottom: false,
                  child: PineHeader(
                    color: C.blueDark,
                    eyebrow: 'On duty',
                    title: first,
                    subtitle: 'Register, verify, then let them in',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: C.blue,
                        borderRadius: BorderRadius.circular(Rd.pill),
                      ),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        _PulseDot(),
                        SizedBox(width: 6),
                        Text('Active',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: _GuardKpi(
                          label: 'Pending',
                          value: '${d.pendingApprovals}',
                          color: C.amber,
                          fill: C.amberSoft,
                          onTap: widget.onOpenQueue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _GuardKpi(
                          label: 'Inside',
                          value: '${d.currentlyInside}',
                          color: C.green,
                          fill: C.greenSoft,
                          onTap: () => widget.onNavigate(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _GuardKpi(
                          label: 'Entered',
                          value: '${d.enteredToday}',
                          color: C.muted,
                          fill: C.neutralSoft,
                          onTap: widget.onOpenQueue,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: Sp.pagePadding,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        label: 'Verify visitor OTP',
                        icon: Icons.key_rounded,
                        onPressed: () => widget.onNavigate(1),
                      ),
                      const SizedBox(height: 8),
                      SecondaryButton(
                        label: 'Register visitor',
                        icon: Icons.person_add_alt_1_outlined,
                        onPressed: _register,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onOpenQueue,
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: Text(
                            'Gate queue · ${d.exitedToday} exited today',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ToolDirectory(links: [
                        ToolLink(
                          icon: Icons.directions_car_outlined,
                          label: 'Vehicle gate',
                          subtitle: 'Log vehicle entry and exit',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LiveGuardVehiclesPage(),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      SectionTitle('Recent',
                          action: TextButton(
                              onPressed: widget.onOpenQueue,
                              child: const Text('Queue'))),
                      if (d.recent.isEmpty)
                        const EmptyState('No recent visitors',
                            icon: Icons.groups_outlined, compact: true)
                      else
                        ...d.recent.map(
                          (v) => _VisitorRow(
                            visitor: v,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LiveGuardVisitorDetailPage(visitorId: v.id),
                              ),
                            ),
                          ),
                        ),
                    ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: C.softBlue,
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _GuardKpi extends StatelessWidget {
  const _GuardKpi({
    required this.label,
    required this.value,
    required this.color,
    required this.fill,
    this.onTap,
  });
  final String label;
  final String value;
  final Color color;
  final Color fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Rd.lg),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.1)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(),
            style: T.label.copyWith(color: color, letterSpacing: 0.6)),
      ]),
    );
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }
}

class LiveAddGateVisitorPage extends StatefulWidget {
  const LiveAddGateVisitorPage({super.key});

  @override
  State<LiveAddGateVisitorPage> createState() => _LiveAddGateVisitorPageState();
}

class _LiveAddGateVisitorPageState extends State<LiveAddGateVisitorPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _purpose = TextEditingController();
  final _vehicle = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'GUEST';
  int _count = 1;
  SocietyFlatPick? _flat;
  List<SocietyFlatPick> _flats = const [];
  bool _loadingFlats = true;
  bool _submitting = false;
  bool _reviewing = false;
  String? _flatError;
  String? _flatFieldError;
  String? _submitError;

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

  Future<void> _pickFlat() async {
    final picked = await showAppSheet<SocietyFlatPick>(
      context,
      title: 'Select flat',
      builder: (sheet) => _FlatPickerSheet(flats: _flats, selected: _flat),
    );
    if (picked != null) {
      setState(() {
        _flat = picked;
        _flatFieldError = null;
      });
    }
  }

  bool _validateForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    final flat = _flat;
    final valid = _form.currentState?.validate() ?? false;
    if (flat == null) {
      setState(() => _flatFieldError = 'Select the flat being visited.');
    }
    return valid && flat != null;
  }

  void _openReview() {
    if (_submitting) return;
    if (!_validateForm()) return;
    setState(() {
      _reviewing = true;
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_reviewing) return;
    if (!_validateForm()) {
      setState(() => _reviewing = false);
      return;
    }
    final flat = _flat!;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.createVisitor(
            CreateVisitorRequest(
              flatId: flat.id,
              visitorName: _name.text.trim(),
              visitorPhone: _phone.text.trim(),
              visitorType: _type,
              purpose: _purpose.text.trim(),
              vehicleNumber:
                  _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim(),
              numberOfVisitors: _count,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      showSuccessSnack(context, 'Visitor request sent for resident approval');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitError = visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingFlats) {
      return Scaffold(
        appBar: AppBar(title: const Text('Register visitor')),
        body: const LoadingView(label: 'Loading flats…'),
      );
    }
    if (_flatError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Register visitor')),
        body: LoadFailure(
          error: _flatError!,
          title: 'Could not load flats',
          onRetry: _loadFlats,
        ),
      );
    }

    final purpose = _purpose.text.trim();
    final vehicle = _vehicle.text.trim();
    final notes = _notes.text.trim();

    return FormScaffold(
      title: _reviewing ? 'Review visitor' : 'Register visitor',
      formKey: _form,
      actions: _reviewing
          ? [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _reviewing = false;
                          _submitError = null;
                        }),
                child: const Text('Edit'),
              ),
            ]
          : null,
      bottom: PrimaryButton(
        label: _reviewing ? 'Send approval request' : 'Review request',
        icon: _reviewing ? Icons.send_rounded : Icons.fact_check_outlined,
        busy: _submitting,
        onPressed: _reviewing ? _submit : _openReview,
      ),
      children: _reviewing
          ? [
              ReviewSummary(
                title: 'Visitor request',
                rows: [
                  ('Flat', _flat?.label ?? '—'),
                  ('Name', _name.text.trim()),
                  ('Phone', _phone.text.trim()),
                  ('Type', visitorTypeLabel(_type)),
                  (
                    'Party size',
                    '$_count ${_count == 1 ? 'person' : 'people'}'
                  ),
                  ('Purpose', purpose.isEmpty ? '—' : purpose),
                  if (vehicle.isNotEmpty) ('Vehicle', vehicle),
                  if (notes.isNotEmpty) ('Notes', notes),
                ],
                note:
                    'Resident approval is required before this visitor can enter. Entry OTP is emailed after approval.',
              ),
              InlineError(_submitError),
            ]
          : [
              const FormSectionLabel('Visiting'),
              PickerField(
                label: 'Flat *',
                icon: Icons.apartment_outlined,
                value: _flat?.label,
                onTap: _submitting ? () {} : _pickFlat,
              ),
              if (_flatFieldError != null)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 6),
                  child: Text(_flatFieldError!,
                      style: const TextStyle(
                          color: C.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 20),
              const FormSectionLabel('Visitor'),
              TextFormField(
                controller: _name,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Visitor name *',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Enter the visitor’s name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Visitor phone *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.isEmpty) return 'Enter a phone number.';
                  if (digits.length < 8) {
                    return 'Enter a valid phone number.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Visitor type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: kVisitorTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Row(children: [
                            Icon(_visitorTypeIcon(t), size: 18, color: C.muted),
                            const SizedBox(width: 10),
                            Text(visitorTypeLabel(t)),
                          ]),
                        ))
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _type = v ?? 'GUEST'),
              ),
              const SizedBox(height: 12),
              QuantityStepper(
                label: 'Number of visitors',
                value: _count,
                min: 1,
                max: 50,
                onChanged:
                    _submitting ? (_) {} : (v) => setState(() => _count = v),
              ),
              const SizedBox(height: 20),
              const FormSectionLabel('Optional'),
              TextFormField(
                controller: _purpose,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Purpose *',
                  hintText: 'e.g. Family visit, parcel delivery',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Enter the purpose of the visit.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vehicle,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Vehicle number',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                enabled: !_submitting,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
              ),
              InlineError(_submitError),
            ],
    );
  }
}

/// Searchable flat picker sheet used by the guard register form.
class _FlatPickerSheet extends StatefulWidget {
  const _FlatPickerSheet({required this.flats, this.selected});
  final List<SocietyFlatPick> flats;
  final SocietyFlatPick? selected;

  @override
  State<_FlatPickerSheet> createState() => _FlatPickerSheetState();
}

class _FlatPickerSheetState extends State<_FlatPickerSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.flats
        : widget.flats
            .where((f) =>
                f.label.toLowerCase().contains(q) ||
                f.number.toLowerCase().contains(q))
            .toList();
    final maxH = MediaQuery.sizeOf(context).height * 0.5;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SearchField(
        controller: _q,
        hint: 'Search flat (e.g. A-101)',
        autofocus: true,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        const EmptyState('No flats match', compact: true)
      else
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final f = rows[i];
              final selected = widget.selected?.id == f.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AppAvatar(
                    text: f.wingCode ?? '?',
                    square: true,
                    size: 38,
                    color: selected ? C.blue : C.muted),
                title: Text(f.label, style: T.bodyStrong),
                subtitle: Text(occupancyStatusLabel(f.occupancyStatus),
                    style: T.caption),
                trailing: selected
                    ? const Icon(Icons.check_circle_rounded, color: C.blue)
                    : null,
                onTap: () => Navigator.pop(context, f),
              );
            },
          ),
        ),
    ]);
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
  final _otpFocus = FocusNode();
  Visitor? _selected;
  bool _verifying = false;
  String? _error;

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
    _otpFocus.dispose();
    super.dispose();
  }

  void reload() => setState(() => _future = _load(force: true));

  void _select(Visitor v) {
    setState(() {
      _selected = _selected?.id == v.id ? null : v;
      _error = null;
    });
    if (_selected != null) _otpFocus.requestFocus();
  }

  Future<void> _verify() async {
    if (_verifying) return;
    final visitor = _selected;
    final otp = _otp.text.trim();
    if (visitor == null) {
      setState(() => _error = 'Select the visitor first.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => _error = 'Enter the 6-digit OTP shown by the visitor.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api)
          .visitors
          .verifyEntryOtp(visitor.id, otp: otp);
      if (!mounted) return;
      _otp.clear();
      setState(() => _selected = null);
      showSuccessSnack(context, '${visitor.visitorName} entered.');
      reload();
      widget.onEntered();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = visitorErrorMessage(e));
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
          return const SkeletonList(items: 4, showHeader: true);
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        final selected = _selected;
        return Column(children: [
          Expanded(
            child: RefreshIndicator(
              color: C.blue,
              onRefresh: () async {
                reload();
                await _future;
              },
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: Sp.pagePadding,
                children: [
                  const PageHeader('Allow entry',
                      subtitle:
                          'Tap the visitor at the gate → enter their 6-digit OTP → Verify.'),
                  if (items.isEmpty)
                    const EmptyState('No approved visitors awaiting entry',
                        icon: Icons.key_off_outlined,
                        title: 'Nothing to verify')
                  else ...[
                    ResultCount(items.length, 'visitor awaiting entry'),
                    ...items.map((v) {
                      final isSel = selected?.id == v.id;
                      return AppCard(
                        onTap: _verifying ? null : () => _select(v),
                        borderColor: isSel ? C.blue : null,
                        color: isSel ? C.chip : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(children: [
                          AppAvatar(
                            icon: _visitorTypeIcon(v.visitorType),
                            color: isSel ? C.blue : C.muted,
                            size: 42,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.visitorName, style: T.title),
                                const SizedBox(height: 2),
                                Text(
                                  '${_flatLabel(v)} · ${visitorTypeLabel(v.visitorType)}'
                                  '${v.otpExpiresAt == null ? '' : ' · OTP expires ${fmtIsoDateTime(v.otpExpiresAt)}'}',
                                  style: T.secondary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isSel
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSel ? C.blue : C.lineStrong,
                          ),
                        ]),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          if (items.isNotEmpty)
            BottomActionBar(children: [
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.person_outline_rounded,
                        size: 16, color: C.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Verifying ${selected.visitorName} · ${_flatLabel(selected)}',
                        style: T.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              OtpBoxes(
                controller: _otp,
                focusNode: _otpFocus,
                enabled: !_verifying,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null && _error!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InlineError(_error),
                ),
              const SizedBox(height: 4),
              PrimaryButton(
                label: 'Verify & allow entry',
                icon: Icons.login_rounded,
                busy: _verifying,
                onPressed: selected == null ? null : _verify,
              ),
            ]),
        ]);
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
  String _nameQuery = '';
  final _searchCtrl = TextEditingController();
  Timer? _searchTimer;
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
            visitorName: _nameQuery.trim().isEmpty ? null : _nameQuery.trim(),
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
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void reload() => setState(() => _future = _load(force: true));

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _nameQuery = value;
        _future = _load(force: true);
      });
    });
  }

  void _setFilter(String? approval, String? entry) {
    setState(() {
      approvalFilter = approval;
      entryFilter = entry;
      _future = _load(force: true);
    });
  }

  Future<void> _register() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveAddGateVisitorPage()),
    );
    if (ok == true) reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Visitor>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        final refreshing = snapshot.connectionState == ConnectionState.waiting;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'gate-register',
            onPressed: _register,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Register'),
          ),
          body: Column(children: [
            if (refreshing) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: SearchField(
                controller: _searchCtrl,
                hint: 'Search visitor name',
                onChanged: _onSearch,
                onClear: () {
                  _searchCtrl.clear();
                  _onSearch('');
                },
              ),
            ),
            FilterBar(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                AppFilterChip(
                  label: 'All',
                  selected: approvalFilter == null && entryFilter == null,
                  onSelected: () => _setFilter(null, null),
                ),
                AppFilterChip(
                  label: 'Pending approval',
                  icon: Icons.hourglass_top_rounded,
                  selected: approvalFilter == 'PENDING',
                  onSelected: () => _setFilter('PENDING', null),
                ),
                AppFilterChip(
                  label: 'Awaiting entry',
                  icon: Icons.key_outlined,
                  selected: approvalFilter == 'APPROVED' &&
                      entryFilter == 'NOT_ENTERED',
                  onSelected: () => _setFilter('APPROVED', 'NOT_ENTERED'),
                ),
                AppFilterChip(
                  label: 'Inside',
                  icon: Icons.meeting_room_outlined,
                  selected: entryFilter == 'ENTERED',
                  onSelected: () => _setFilter(null, 'ENTERED'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? _emptyScrollable(
                      EmptyState(
                        'No visitors match these filters',
                        icon: Icons.groups_outlined,
                        actionLabel: 'Show all',
                        onAction: () => _setFilter(null, null),
                      ),
                      () async {
                        reload();
                        await _future;
                      },
                    )
                  : RefreshIndicator(
                      color: C.blue,
                      onRefresh: () async {
                        reload();
                        await _future;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final v = items[i];
                          return _VisitorRow(
                            visitor: v,
                            extra: v.purpose,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LiveGuardVisitorDetailPage(
                                      visitorId: v.id),
                                ),
                              );
                              reload();
                            },
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
    final ok = await confirmDialog(
      context,
      title: 'Check out ${v.visitorName}?',
      message: '${_flatLabel(v)} · inside since ${fmtIsoDateTime(v.entryAt)}',
      confirmLabel: 'Check out',
      icon: Icons.logout_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busyIds.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.checkout(v.id);
      if (!mounted) return;
      showSuccessSnack(context, '${v.visitorName} checked out');
      reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
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
          return const SkeletonList(items: 4, showHeader: true);
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            reload();
            await _future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: Sp.pagePadding,
            children: [
              PageHeader('Inside now',
                  subtitle: items.isEmpty
                      ? 'Visitors currently inside the premises'
                      : '${items.length} ${items.length == 1 ? 'visitor' : 'visitors'} inside'),
              if (items.isEmpty)
                const EmptyState('No visitors currently inside',
                    icon: Icons.meeting_room_outlined)
              else
                ...items.map((v) {
                  final busy = _busyIds.contains(v.id);
                  return _VisitorRow(
                    visitor: v,
                    extra: 'In since ${fmtIsoDateTime(v.entryAt)}',
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
                    trailing: SizedBox(
                      width: 108,
                      height: 48,
                      child: PrimaryButton(
                        label: 'Exit',
                        icon: Icons.logout_rounded,
                        color: C.amber,
                        busy: busy,
                        onPressed: () => _checkout(v),
                      ),
                    ),
                  );
                }),
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
      appBar: AppBar(title: const Text('Visitor details')),
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
          return _VisitorDetailBody(
            visitor: snapshot.data!,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
          );
        },
      ),
    );
  }
}

class _VisitorDetailBody extends StatelessWidget {
  const _VisitorDetailBody({
    required this.visitor,
    this.onRefresh,
    this.footer,
  });
  final Visitor visitor;
  final Future<void> Function()? onRefresh;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final v = visitor;
    final timeline = <(String, String?, IconData)>[
      ('Requested', v.createdAt, Icons.add_circle_outline_rounded),
      if (v.approvedAt != null)
        ('Approved', v.approvedAt, Icons.check_circle_outline_rounded),
      if (v.rejectedAt != null)
        ('Rejected', v.rejectedAt, Icons.cancel_outlined),
      if (v.expiredAt != null)
        ('Expired', v.expiredAt, Icons.timer_off_outlined),
      if (v.entryAt != null) ('Entered', v.entryAt, Icons.login_rounded),
      if (v.exitAt != null) ('Exited', v.exitAt, Icons.logout_rounded),
    ];
    final list = ListView(
      padding: Sp.pagePadding,
      children: [
        DetailHero(
          title: v.visitorName,
          subtitle: '${_flatLabel(v)} · ${visitorTypeLabel(v.visitorType)}',
          leading: AppAvatar(
            icon: _visitorTypeIcon(v.visitorType),
            color: _visitorTone(v),
            size: Sz.avatarLg,
          ),
          badges: [
            StatusBadge(approvalStatusLabel(v.approvalStatus)),
            StatusBadge(entryStatusLabel(v.entryStatus)),
            if (v.hasActiveOtp)
              const StatusBadge('OTP active',
                  tone: BadgeTone.info, icon: Icons.key_rounded),
          ],
        ),
        const SizedBox(height: 18),
        DetailCard(title: 'Visit', children: [
          DetailRow('Purpose', v.purpose),
          DetailRow('Flat', _flatLabel(v)),
          DetailRow('Party size',
              '${v.numberOfVisitors} ${v.numberOfVisitors == 1 ? 'person' : 'people'}'),
          if (v.vehicleNumber != null) DetailRow('Vehicle', v.vehicleNumber!),
          DetailRow('Approver', humanizeStatus(v.assignedResidentRole)),
          if (v.notes != null && v.notes!.trim().isNotEmpty)
            DetailRow('Notes', v.notes!),
        ]),
        DetailCard(title: 'Contact', children: [
          DetailRow('Phone', v.visitorPhone,
              valueWidget: Row(children: [
                Expanded(child: Text(v.visitorPhone, style: T.bodyStrong)),
                IconButton(
                  tooltip: 'Copy phone',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: v.visitorPhone));
                    if (context.mounted) {
                      showInfoSnack(context, 'Phone number copied');
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ])),
        ]),
        if (v.hasActiveOtp ||
            v.otpExpiresAt != null ||
            v.rejectionReason != null)
          DetailCard(title: 'Entry', children: [
            if (v.hasActiveOtp)
              const DetailRow('OTP', 'Active · code is emailed to the visitor'),
            if (v.otpExpiresAt != null)
              DetailRow('OTP expires', fmtIsoDateTime(v.otpExpiresAt)),
            if (v.otpAttempts != null && v.otpAttempts! > 0)
              DetailRow('OTP attempts', '${v.otpAttempts}'),
            if (v.rejectionReason != null)
              DetailRow('Rejection reason', v.rejectionReason!),
          ]),
        const SizedBox(height: 6),
        const SectionTitle('Timeline'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(children: [
            for (var i = 0; i < timeline.length; i++)
              _TimelineRow(
                icon: timeline[i].$3,
                label: timeline[i].$1,
                value: fmtIsoDateTime(timeline[i].$2),
                last: i == timeline.length - 1,
              ),
          ]),
        ),
        if (footer != null) ...[
          const SizedBox(height: 20),
          footer!,
          const SizedBox(height: 12),
        ] else
          const SizedBox(height: 24),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(color: C.blue, onRefresh: onRefresh!, child: list);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.last,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(children: [
            Container(
              width: 28,
              height: 28,
              decoration:
                  const BoxDecoration(color: C.chip, shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: C.blue),
            ),
            if (!last) Expanded(child: Container(width: 2, color: C.line)),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 4 : 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: T.bodyStrong),
                    const SizedBox(height: 2),
                    Text(value, style: T.secondary),
                  ]),
            ),
          ),
        ]),
      );
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
  late final TabController _tabs = TabController(length: 2, vsync: this);
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
    final ok = await confirmDialog(
      context,
      title: 'Approve ${v.visitorName}?',
      message:
          '${_flatLabel(v)} · ${visitorTypeLabel(v.visitorType)}\nEntry OTP will be emailed after approval.',
      confirmLabel: 'Approve',
      icon: Icons.check_circle_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.approve(v.id);
      if (!mounted) return;
      showSuccessSnack(
          context, '${v.visitorName} approved. Entry OTP sent by email.');
      reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  Future<void> _reject(Visitor v) async {
    if (_busy.contains(v.id)) return;
    final reason = await promptTextDialog(
      context,
      title: 'Reject ${v.visitorName}?',
      message: 'The guard will be notified. You can add a short reason.',
      label: 'Reason (optional)',
      confirmLabel: 'Reject',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.reject(
            v.id,
            reason: reason.isEmpty ? null : reason,
          );
      if (!mounted) return;
      showAppSnack(context, 'Visitor rejected', tone: SnackTone.warning);
      reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  Future<void> _cancel(Visitor v) async {
    if (_busy.contains(v.id)) return;
    final ok = await confirmDialog(
      context,
      title: 'Cancel this visitor request?',
      message:
          '${v.visitorName} will no longer be able to enter with this request.',
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep',
      destructive: true,
      icon: Icons.cancel_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(v.id));
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.cancel(v.id);
      if (!mounted) return;
      showAppSnack(context, 'Visitor request cancelled',
          tone: SnackTone.warning);
      reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  Widget _list(
    Future<Paged<Visitor>> future, {
    required bool showActions,
    required String emptyMessage,
    required IconData emptyIcon,
  }) {
    return FutureBuilder<Paged<Visitor>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SkeletonList(items: 4);
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final items = snapshot.data!.items;
        Future<void> refresh() async {
          reload();
          await Future.wait([_pending, _history]);
        }

        if (items.isEmpty) {
          return _emptyScrollable(
              EmptyState(emptyMessage, icon: emptyIcon), refresh);
        }
        return RefreshIndicator(
          color: C.blue,
          onRefresh: refresh,
          child: ListView.builder(
            padding: Sp.pagePadding,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final v = items[i];
              final busy = _busy.contains(v.id);
              final canAct = showActions &&
                  v.approvalStatus == 'PENDING' &&
                  v.entryStatus == 'NOT_ENTERED';
              final canCancel = showActions &&
                  (v.approvalStatus == 'PENDING' ||
                      v.approvalStatus == 'APPROVED') &&
                  v.entryStatus == 'NOT_ENTERED';
              Widget? footer;
              if (canAct) {
                footer = Row(children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Reject',
                      icon: Icons.close_rounded,
                      destructive: true,
                      onPressed: busy ? null : () => _reject(v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      color: C.green,
                      busy: busy,
                      onPressed: () => _approve(v),
                    ),
                  ),
                ]);
              } else if (canCancel) {
                footer = SecondaryButton(
                  label: 'Cancel request',
                  icon: Icons.cancel_outlined,
                  destructive: true,
                  busy: busy,
                  onPressed: () => _cancel(v),
                );
              }
              return _VisitorRow(
                visitor: v,
                extra: v.purpose,
                footer: footer,
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
        Container(
          color: C.surface,
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'History'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _list(_pending,
                  showActions: true,
                  emptyMessage: 'No visitor requests waiting for your approval',
                  emptyIcon: Icons.how_to_reg_outlined),
              _list(_history,
                  showActions: true,
                  emptyMessage: 'No visitors yet for this flat',
                  emptyIcon: Icons.groups_outlined),
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
  bool _busy = false;

  Future<Visitor> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .visitors
        .residentVisitor(widget.visitorId, force: force);
  }

  void _reload() => setState(() => _future = _load(force: true));

  Future<void> _approve(Visitor v) async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'Approve ${v.visitorName}?',
      message:
          '${_flatLabel(v)} · ${visitorTypeLabel(v.visitorType)}\nEntry OTP will be emailed after approval.',
      confirmLabel: 'Approve',
      icon: Icons.check_circle_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.approve(v.id);
      if (!mounted) return;
      showSuccessSnack(
          context, '${v.visitorName} approved. Entry OTP sent by email.');
      _reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Visitor v) async {
    if (_busy) return;
    final reason = await promptTextDialog(
      context,
      title: 'Reject ${v.visitorName}?',
      message: 'The guard will be notified. You can add a short reason.',
      label: 'Reason (optional)',
      confirmLabel: 'Reject',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).visitors.reject(
            v.id,
            reason: reason.isEmpty ? null : reason,
          );
      if (!mounted) return;
      showAppSnack(context, 'Visitor rejected', tone: SnackTone.warning);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, visitorErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Visitor>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Visitor details')),
            body: const LoadingView(label: 'Loading visitor…'),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Visitor details')),
            body: LoadFailure(
              error: snapshot.error!,
              onRetry: _reload,
            ),
          );
        }
        final v = snapshot.data!;
        final canAct =
            v.approvalStatus == 'PENDING' && v.entryStatus == 'NOT_ENTERED';
        return Scaffold(
          appBar: AppBar(title: const Text('Visitor details')),
          body: _VisitorDetailBody(
            visitor: v,
            onRefresh: () async {
              _reload();
              await _future;
            },
            footer: canAct
                ? ActionRail(
                    busy: _busy,
                    primary: ToolLink(
                      icon: Icons.check_rounded,
                      label: 'Approve visitor',
                      subtitle: 'Sends entry OTP by email',
                      onTap: () => _approve(v),
                    ),
                    secondary: [
                      ToolLink(
                        icon: Icons.close_rounded,
                        label: 'Reject request',
                        subtitle: 'Optional reason for the guard',
                        onTap: () => _reject(v),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
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
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final bundle = snapshot.data!;
        final s = bundle.summary;
        final items = bundle.list.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            reload();
            await _future;
          },
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: Sp.pagePadding,
            children: [
              const PageHeader('Visitors',
                  subtitle: 'Society-wide visitor log'),
              MiniStatStrip(children: [
                MiniStat('Total', '${s.total}'),
                MiniStat('Pending', '${s.byApprovalStatus['PENDING'] ?? 0}',
                    tone: BadgeTone.warning),
                MiniStat('Inside', '${s.byEntryStatus['ENTERED'] ?? 0}',
                    tone: BadgeTone.success),
                MiniStat('Exited', '${s.byEntryStatus['EXITED'] ?? 0}',
                    tone: BadgeTone.neutral),
              ]),
              const SizedBox(height: 14),
              SearchField(
                controller: _search,
                hint: 'Search by visitor name',
                onSubmitted: (_) => reload(),
                onClear: reload,
              ),
              const SizedBox(height: 10),
              FilterBar(children: [
                AppFilterChip(
                  label: 'All',
                  selected: approvalFilter == null && entryFilter == null,
                  onSelected: () {
                    setState(() {
                      approvalFilter = null;
                      entryFilter = null;
                      _future = _load(force: true);
                    });
                  },
                ),
                for (final st in const [
                  'PENDING',
                  'APPROVED',
                  'REJECTED',
                  'EXPIRED',
                  'CANCELLED'
                ])
                  AppFilterChip(
                    label: approvalStatusLabel(st),
                    selected: approvalFilter == st,
                    onSelected: () {
                      setState(() {
                        approvalFilter = st;
                        _future = _load(force: true);
                      });
                    },
                  ),
              ]),
              const SizedBox(height: 6),
              ResultCount(items.length, 'visitor'),
              if (items.isEmpty)
                const EmptyState('No visitors found',
                    icon: Icons.groups_outlined)
              else
                ...items.map(
                  (v) => _VisitorRow(
                    visitor: v,
                    extra: 'Approver ${humanizeStatus(v.assignedResidentRole)}',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            LiveAdminVisitorDetailPage(visitorId: v.id),
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
      appBar: AppBar(title: const Text('Visitor details')),
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
          return _VisitorDetailBody(
            visitor: snapshot.data!,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
          );
        },
      ),
    );
  }
}
