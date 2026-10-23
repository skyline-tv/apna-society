import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/admin_user_models.dart';
import '../../api/models/common.dart';
import '../../api/models/staff_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart' show Debouncer;
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

String staffErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'DUPLICATE_ATTENDANCE':
        return 'Attendance already recorded for this staff member on that date.';
      case 'SHIFT_OVERLAP':
        return 'This shift overlaps an existing scheduled shift.';
      case 'INVALID_SHIFT_TIMES':
        return 'Invalid shift start/end times.';
      case 'STAFF_INACTIVE':
        return 'Staff member is not active.';
      case 'INVALID_LINKED_USER':
        return 'Linked user is invalid or not an active society member.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this action.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _employmentTypeLabel(String v) => humanizeStatus(v);

IconData _categoryIcon(String category) {
  switch (category.toUpperCase()) {
    case 'SECURITY':
      return Icons.shield_outlined;
    case 'HOUSEKEEPING':
      return Icons.cleaning_services_outlined;
    case 'MAINTENANCE':
      return Icons.build_outlined;
    case 'ELECTRICIAN':
      return Icons.electrical_services_outlined;
    case 'PLUMBER':
      return Icons.plumbing_outlined;
    case 'GARDENER':
      return Icons.yard_outlined;
    case 'LIFT_OPERATOR':
      return Icons.elevator_outlined;
    default:
      return Icons.badge_outlined;
  }
}

BadgeTone _employmentTone(String status) {
  switch (status.toUpperCase()) {
    case 'ACTIVE':
      return BadgeTone.success;
    case 'INACTIVE':
      return BadgeTone.warning;
    case 'TERMINATED':
      return BadgeTone.danger;
    default:
      return BadgeTone.neutral;
  }
}

BadgeTone _attendanceTone(String status) {
  switch (status.toUpperCase()) {
    case 'PRESENT':
      return BadgeTone.success;
    case 'HALF_DAY':
      return BadgeTone.warning;
    case 'ABSENT':
      return BadgeTone.danger;
    case 'ON_LEAVE':
      return BadgeTone.info;
    default:
      return BadgeTone.neutral;
  }
}

BadgeTone _shiftTone(String status) {
  switch (status.toUpperCase()) {
    case 'SCHEDULED':
      return BadgeTone.info;
    case 'COMPLETED':
      return BadgeTone.success;
    case 'CANCELLED':
      return BadgeTone.neutral;
    default:
      return BadgeTone.neutral;
  }
}

/// Loads a `staffId → name` map for decorating attendance and shift rows.
/// Failures return an empty map; names are decorative.
Future<Map<String, StaffMember>> _staffIndex({bool force = false}) async {
  final session = authSession;
  if (session == null) return const {};
  try {
    final page = await ensureLiveRepositories(session.api).staff.listStaff(
          force: force,
          query: const ListStaffQuery(limit: 100),
        );
    return {for (final s in page.items) s.id: s};
  } catch (_) {
    return const {};
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.staff, required this.onTap});
  final StaffMember staff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = staff;
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        text: initialsOf(s.fullName),
        color: s.employmentStatus == 'ACTIVE' ? C.blue : C.muted,
      ),
      title: s.fullName,
      subtitle: '${staffCategoryLabel(s.category)} · ${s.phone}',
      badges: [
        StatusBadge(employmentStatusLabel(s.employmentStatus),
            tone: _employmentTone(s.employmentStatus)),
        StatusBadge(_employmentTypeLabel(s.employmentType),
            tone: BadgeTone.neutral),
        if (s.linkedUserId != null)
          const StatusBadge('App account',
              tone: BadgeTone.info, icon: Icons.link_rounded),
      ],
    );
  }
}

// ─── Admin staff list ────────────────────────────────────────────────────────

class LiveAdminStaffPage extends StatefulWidget {
  const LiveAdminStaffPage({super.key});

  @override
  State<LiveAdminStaffPage> createState() => _LiveAdminStaffPageState();
}

class _LiveAdminStaffPageState extends State<LiveAdminStaffPage> {
  String? category;
  String? employmentStatus;
  late Future<Paged<StaffMember>> _future = _load();

  Future<Paged<StaffMember>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).staff.listStaff(
          force: force,
          query: ListStaffQuery(
            category: category,
            employmentStatus: employmentStatus,
            limit: 50,
          ),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  bool get _filtered => category != null || employmentStatus != null;

  Future<void> _add() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveStaffFormPage()),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Staff record created.');
      reload();
    }
  }

  Future<void> _pickCategory() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Filter by category',
      builder: (ctx) => Column(children: [
        ListRow(
          dense: true,
          title: 'All categories',
          leading: const AppAvatar(
              icon: Icons.all_inclusive_rounded, square: true, size: 36),
          trailing: category == null
              ? const Icon(Icons.check_rounded, color: C.blue)
              : null,
          showChevron: false,
          onTap: () => Navigator.pop(ctx, ''),
        ),
        for (final c in kStaffCategories)
          ListRow(
            dense: true,
            title: staffCategoryLabel(c),
            leading: AppAvatar(icon: _categoryIcon(c), square: true, size: 36),
            trailing: category == c
                ? const Icon(Icons.check_rounded, color: C.blue)
                : null,
            showChevron: false,
            onTap: () => Navigator.pop(ctx, c),
          ),
      ]),
    );
    if (picked == null) return;
    setState(() {
      category = picked.isEmpty ? null : picked;
      _future = _load(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-staff',
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add staff'),
      ),
      body: FutureBuilder<Paged<StaffMember>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 6, showHeader: true);
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load staff',
                onRetry: reload);
          }
          final items = snapshot.data!.items;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              children: [
                const PageHeader('Staff',
                    subtitle:
                        'Employment records. Adding staff does not create an app login.'),
                FilterBar(
                  padding: EdgeInsets.zero,
                  children: [
                    AppFilterChip(
                      label: category == null
                          ? 'Category'
                          : staffCategoryLabel(category!),
                      icon: Icons.category_outlined,
                      selected: category != null,
                      onSelected: _pickCategory,
                    ),
                    AppFilterChip(
                      label: 'All status',
                      selected: employmentStatus == null,
                      onSelected: () => setState(() {
                        employmentStatus = null;
                        _future = _load(force: true);
                      }),
                    ),
                    for (final s in kEmploymentStatuses)
                      AppFilterChip(
                        label: employmentStatusLabel(s),
                        selected: employmentStatus == s,
                        onSelected: () => setState(() {
                          employmentStatus = s;
                          _future = _load(force: true);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  EmptyState(
                    _filtered
                        ? 'No staff match these filters'
                        : 'No staff records yet',
                    icon: Icons.badge_outlined,
                    actionLabel: _filtered ? 'Clear filters' : 'Add staff',
                    onAction: _filtered
                        ? () => setState(() {
                              category = null;
                              employmentStatus = null;
                              _future = _load(force: true);
                            })
                        : _add,
                  )
                else ...[
                  ResultCount(snapshot.data!.pagination.total, 'staff member'),
                  for (final s in items)
                    _StaffRow(
                      staff: s,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveStaffDetailPage(staffId: s.id),
                          ),
                        );
                        if (mounted) reload();
                      },
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class LiveStaffDetailPage extends StatefulWidget {
  const LiveStaffDetailPage({super.key, required this.staffId});
  final String staffId;

  @override
  State<LiveStaffDetailPage> createState() => _LiveStaffDetailPageState();
}

class _LiveStaffDetailPageState extends State<LiveStaffDetailPage> {
  late Future<StaffMember> _future = _load();
  bool _busy = false;

  Future<StaffMember> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .staff
        .getStaff(widget.staffId, force: force);
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        if (success != null) showSuccessSnack(context, success);
        reload();
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(StaffMember s) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LiveStaffFormPage(existing: s)),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Staff record updated.');
      reload();
    }
  }

  Future<void> _deactivate(StaffMember s) async {
    final reason = await promptTextDialog(
      context,
      title: 'Deactivate ${s.fullName}?',
      message:
          'Marks this staff member inactive. Attendance and shifts cannot be recorded until reactivated.',
      label: 'Reason (optional)',
      confirmLabel: 'Deactivate',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).staff.deactivateStaff(
            s.id,
            reason: reason.trim().isEmpty ? null : reason.trim(),
          );
    }, success: 'Staff member deactivated.');
  }

  Future<void> _terminate(StaffMember s) async {
    final reason = await promptTextDialog(
      context,
      title: 'Terminate ${s.fullName}?',
      message:
          'Ends employment permanently. This record cannot be reactivated afterwards.',
      label: 'Reason (optional)',
      confirmLabel: 'Terminate',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).staff.terminateStaff(
            s.id,
            reason: reason.trim().isEmpty ? null : reason.trim(),
          );
    }, success: 'Employment terminated.');
  }

  Future<void> _reactivate(StaffMember s) async {
    final ok = await confirmDialog(
      context,
      title: 'Reactivate ${s.fullName}?',
      message: 'Attendance and shifts can be recorded again.',
      confirmLabel: 'Reactivate',
      icon: Icons.restart_alt_rounded,
    );
    if (!ok) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).staff.reactivateStaff(s.id);
    }, success: 'Staff member reactivated.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff member'),
        actions: [
          FutureBuilder<StaffMember>(
            future: _future,
            builder: (context, snap) => snap.hasData
                ? IconButton(
                    tooltip: 'Edit',
                    onPressed: _busy ? null : () => _edit(snap.data!),
                    icon: const Icon(Icons.edit_outlined),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: FutureBuilder<StaffMember>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading staff member…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load staff member',
                onRetry: reload);
          }
          final s = snapshot.data!;
          final active = s.employmentStatus == 'ACTIVE';
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              reload();
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AppAvatar(
                    text: initialsOf(s.fullName),
                    size: Sz.avatarLg,
                    color: active ? C.blue : C.muted,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.fullName, style: T.h1),
                          const SizedBox(height: 3),
                          Text(
                            '${staffCategoryLabel(s.category)} · ${_employmentTypeLabel(s.employmentType)}',
                            style: T.secondary,
                          ),
                        ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusBadge(employmentStatusLabel(s.employmentStatus),
                      tone: _employmentTone(s.employmentStatus)),
                  if (s.linkedUserId != null)
                    const StatusBadge('App account linked',
                        tone: BadgeTone.info, icon: Icons.link_rounded),
                ]),
                const SizedBox(height: 18),
                if (s.statusReason != null && s.statusReason!.trim().isNotEmpty)
                  InfoNote(
                    '${s.employmentStatus == 'TERMINATED' ? 'Termination' : 'Status'} reason: ${s.statusReason}',
                    tone: s.employmentStatus == 'TERMINATED'
                        ? NoteTone.danger
                        : NoteTone.warning,
                  ),
                DetailCard(title: 'Contact', children: [
                  DetailRow('Phone', s.phone,
                      valueWidget: Row(children: [
                        Expanded(child: Text(s.phone, style: T.bodyStrong)),
                        IconButton(
                          tooltip: 'Copy',
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: s.phone));
                            if (context.mounted) {
                              showInfoSnack(context, 'Phone number copied.');
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
                      ])),
                  DetailRow('Email', s.email ?? '—'),
                  DetailRow('Address', s.address ?? '—'),
                  DetailRow(
                    'Emergency',
                    s.emergencyContactName == null
                        ? '—'
                        : '${s.emergencyContactName}'
                            '${s.emergencyContactPhone != null ? ' · ${s.emergencyContactPhone}' : ''}',
                  ),
                ]),
                DetailCard(title: 'Employment', children: [
                  DetailRow('Category', staffCategoryLabel(s.category)),
                  DetailRow('Type', _employmentTypeLabel(s.employmentType)),
                  DetailRow('Joined', fmtYmd(s.joiningDate)),
                  DetailRow('App account',
                      s.linkedUserId == null ? 'Not linked' : 'Linked'),
                  if (s.deactivatedAt != null)
                    DetailRow('Deactivated', fmtIsoDateTime(s.deactivatedAt)),
                  if (s.terminatedAt != null)
                    DetailRow('Terminated', fmtIsoDateTime(s.terminatedAt)),
                  if (s.notes != null && s.notes!.trim().isNotEmpty)
                    DetailRow('Notes', s.notes!),
                ]),
                const SizedBox(height: 6),
                const SectionTitle('Actions'),
                QuickActionTile(
                  icon: Icons.edit_outlined,
                  label: 'Edit details',
                  subtitle: 'Contact, category, emergency contact',
                  enabled: !_busy,
                  onTap: () => _edit(s),
                ),
                if (active) ...[
                  QuickActionTile(
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Deactivate',
                    subtitle: 'Temporarily pause employment',
                    color: C.amber,
                    enabled: !_busy,
                    onTap: () => _deactivate(s),
                  ),
                  QuickActionTile(
                    icon: Icons.person_off_outlined,
                    label: 'Terminate',
                    subtitle: 'End employment permanently',
                    color: C.error,
                    enabled: !_busy,
                    onTap: () => _terminate(s),
                  ),
                ] else if (s.employmentStatus == 'INACTIVE')
                  QuickActionTile(
                    icon: Icons.restart_alt_rounded,
                    label: 'Reactivate',
                    subtitle: 'Resume employment',
                    color: C.green,
                    enabled: !_busy,
                    onTap: () => _reactivate(s),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Searchable picker of society users for the optional "linked app account".
class _UserPickerSheet extends StatefulWidget {
  const _UserPickerSheet();

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  final _ctrl = TextEditingController();
  final _debounce = Debouncer();
  late Future<Paged<AdminUser>> _future = _load();

  Future<Paged<AdminUser>> _load() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final q = _ctrl.text.trim();
    return ensureLiveRepositories(session.api).users.listUsers(
          force: true,
          query: ListUsersQuery(
            search: q.isEmpty ? null : q,
            isActive: true,
            limit: 50,
          ),
        );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SearchField(
        controller: _ctrl,
        hint: 'Search by name, email or phone',
        autofocus: true,
        onChanged: (_) =>
            _debounce.run(() => setState(() => _future = _load())),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 360,
        child: FutureBuilder<Paged<AdminUser>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const SkeletonList(items: 4);
            }
            if (snap.hasError) {
              return LoadFailure(
                  error: snap.error!,
                  compact: true,
                  onRetry: () => setState(() => _future = _load()));
            }
            final users = snap.data!.items;
            if (users.isEmpty) {
              return const EmptyState('No matching members', compact: true);
            }
            return ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, i) {
                final u = users[i];
                return ListRow(
                  dense: true,
                  leading: AppAvatar(text: initialsOf(u.name), size: 36),
                  title: u.name,
                  subtitle: u.mobileE164 != null ? '+${u.mobileE164}' : u.email,
                  badges: [
                    for (final r
                        in (u.societyRoles.isEmpty ? u.roles : u.societyRoles))
                      StatusBadge(humanizeStatus(r), tone: BadgeTone.info),
                  ],
                  showChevron: false,
                  onTap: () => Navigator.pop(context, u),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class LiveStaffFormPage extends StatefulWidget {
  const LiveStaffFormPage({super.key, this.existing});
  final StaffMember? existing;

  @override
  State<LiveStaffFormPage> createState() => _LiveStaffFormPageState();
}

class _LiveStaffFormPageState extends State<LiveStaffFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.fullName);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final _emergencyName =
      TextEditingController(text: widget.existing?.emergencyContactName);
  late final _emergencyPhone =
      TextEditingController(text: widget.existing?.emergencyContactPhone);
  late final _linkedUserId =
      TextEditingController(text: widget.existing?.linkedUserId);
  String? _linkedUserName;
  late String _category = widget.existing?.category ?? 'OTHER';
  late String _employmentType = widget.existing?.employmentType ?? 'PERMANENT';
  late String _joiningDate =
      widget.existing?.joiningDate ?? _ymd(DateTime.now());
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveLinkedUserName();
  }

  Future<void> _resolveLinkedUserName() async {
    final id = widget.existing?.linkedUserId;
    final session = authSession;
    if (id == null || session == null) return;
    try {
      final u = await ensureLiveRepositories(session.api).users.getUser(id);
      if (mounted) setState(() => _linkedUserName = u.name);
    } catch (_) {
      // Decorative only.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _linkedUserId.dispose();
    super.dispose();
  }

  Future<void> _pickLinkedUser() async {
    final picked = await showAppSheet<AdminUser>(
      context,
      title: 'Link app account',
      builder: (_) => const _UserPickerSheet(),
    );
    if (picked == null) return;
    setState(() {
      _linkedUserId.text = picked.id;
      _linkedUserName = picked.name;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repo = ensureLiveRepositories(session.api).staff;
      final linked = _linkedUserId.text.trim();
      if (widget.existing == null) {
        await repo.createStaff(
          CreateStaffRequest(
            fullName: name,
            phone: phone,
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            category: _category,
            employmentType: _employmentType,
            joiningDate: _joiningDate,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            emergencyContactName: _emergencyName.text.trim().isEmpty
                ? null
                : _emergencyName.text.trim(),
            emergencyContactPhone: _emergencyPhone.text.trim().isEmpty
                ? null
                : _emergencyPhone.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            linkedUserId: linked.isEmpty ? null : linked,
          ),
        );
      } else {
        final existingLink = widget.existing!.linkedUserId;
        await repo.updateStaff(
          widget.existing!.id,
          UpdateStaffRequest(
            fullName: name,
            phone: phone,
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            category: _category,
            employmentType: _employmentType,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            emergencyContactName: _emergencyName.text.trim().isEmpty
                ? null
                : _emergencyName.text.trim(),
            emergencyContactPhone: _emergencyPhone.text.trim().isEmpty
                ? null
                : _emergencyPhone.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            linkedUserId: linked.isEmpty ? null : linked,
            clearLinkedUser: linked.isEmpty && existingLink != null,
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final linkedId = _linkedUserId.text.trim();
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit staff' : 'Add staff')),
      body: KeyboardDismissOnTap(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: Sp.pagePadding,
            children: [
              const FormSectionLabel('Identity'),
              TextFormField(
                controller: _name,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name *',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Full name is required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => (v ?? '').trim().length < 7
                    ? 'Enter a valid phone number.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                      ? null
                      : 'Enter a valid email.';
                },
              ),
              const SizedBox(height: 20),
              const FormSectionLabel('Role'),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(_categoryIcon(_category)),
                ),
                items: [
                  for (final c in kStaffCategories)
                    DropdownMenuItem(
                        value: c, child: Text(staffCategoryLabel(c))),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              ScaleToWidth(
                child: SegmentedButton<String>(
                  showSelectedIcon: MediaQuery.sizeOf(context).width >= 400,
                  segments: [
                    for (final t in kEmploymentTypes)
                      ButtonSegment(
                          value: t, label: Text(_employmentTypeLabel(t))),
                  ],
                  selected: {_employmentType},
                  onSelectionChanged: _submitting
                      ? null
                      : (s) => setState(() => _employmentType = s.first),
                ),
              ),
              if (!editing) ...[
                const SizedBox(height: 12),
                PickerField(
                  label: 'Joining date',
                  value: fmtYmd(_joiningDate),
                  enabled: !_submitting,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.tryParse(_joiningDate) ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _joiningDate = _ymd(picked));
                    }
                  },
                ),
              ],
              const SizedBox(height: 20),
              const FormSectionLabel('Address & emergency contact'),
              TextFormField(
                controller: _address,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emergencyName,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Emergency contact name',
                  prefixIcon: Icon(Icons.contact_emergency_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emergencyPhone,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Emergency contact phone',
                  prefixIcon: Icon(Icons.phone_in_talk_outlined),
                ),
              ),
              const SizedBox(height: 20),
              const FormSectionLabel('Notes & app account'),
              TextFormField(
                controller: _notes,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              PickerField(
                label: 'Linked app account',
                value: linkedId.isEmpty
                    ? 'None'
                    : (_linkedUserName ?? 'Member $linkedId'),
                icon: Icons.link_rounded,
                helper:
                    'Optional. Links an existing society member; it does not create a login.',
                enabled: !_submitting,
                onTap: _pickLinkedUser,
                onClear: linkedId.isEmpty
                    ? null
                    : () => setState(() {
                          _linkedUserId.clear();
                          _linkedUserName = null;
                        }),
              ),
              InlineError(_error),
              const SizedBox(height: 24),
              PrimaryButton(
                label: editing ? 'Save changes' : 'Create staff record',
                icon: Icons.check_rounded,
                busy: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Attendance ──────────────────────────────────────────────────────────────

class _AttendanceBundle {
  const _AttendanceBundle({required this.page, required this.staff});
  final Paged<StaffAttendance> page;
  final Map<String, StaffMember> staff;
}

class LiveAdminAttendancePage extends StatefulWidget {
  const LiveAdminAttendancePage({super.key});

  @override
  State<LiveAdminAttendancePage> createState() =>
      _LiveAdminAttendancePageState();
}

class _LiveAdminAttendancePageState extends State<LiveAdminAttendancePage> {
  String? staffId;
  String? localDate;
  String? statusFilter;
  late Future<_AttendanceBundle> _future = _load();

  Future<_AttendanceBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final page = await ensureLiveRepositories(session.api).staff.listAttendance(
          force: force,
          query: ListAttendanceQuery(
            staffId: staffId,
            localDate: localDate,
            status: statusFilter,
            limit: 50,
          ),
        );
    final staff = await _staffIndex(force: force);
    return _AttendanceBundle(page: page, staff: staff);
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  Future<void> _record() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveMarkAttendancePage()),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Attendance recorded.');
      reload();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(localDate ?? '') ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        localDate = _ymd(picked);
        _future = _load(force: true);
      });
    }
  }

  Future<void> _pickStaff(Map<String, StaffMember> staff) async {
    final list = staff.values.toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final picked = await showAppSheet<String>(
      context,
      title: 'Filter by staff member',
      builder: (ctx) => Column(children: [
        ListRow(
          dense: true,
          title: 'All staff',
          leading: const AppAvatar(
              icon: Icons.groups_outlined, square: true, size: 36),
          trailing: staffId == null
              ? const Icon(Icons.check_rounded, color: C.blue)
              : null,
          showChevron: false,
          onTap: () => Navigator.pop(ctx, ''),
        ),
        for (final s in list)
          ListRow(
            dense: true,
            title: s.fullName,
            subtitle: staffCategoryLabel(s.category),
            leading: AppAvatar(text: initialsOf(s.fullName), size: 36),
            trailing: staffId == s.id
                ? const Icon(Icons.check_rounded, color: C.blue)
                : null,
            showChevron: false,
            onTap: () => Navigator.pop(ctx, s.id),
          ),
      ]),
    );
    if (picked == null) return;
    setState(() {
      staffId = picked.isEmpty ? null : picked;
      _future = _load(force: true);
    });
  }

  bool get _filtered =>
      staffId != null || localDate != null || statusFilter != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'record-attendance',
        onPressed: _record,
        icon: const Icon(Icons.how_to_reg_outlined),
        label: const Text('Record'),
      ),
      body: FutureBuilder<_AttendanceBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 6, showHeader: true);
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load attendance',
                onRetry: reload);
          }
          final bundle = snapshot.data!;
          final items = bundle.page.items;
          final staffName = staffId == null
              ? null
              : bundle.staff[staffId]?.fullName ?? 'Selected staff';
          return RefreshIndicator(
            color: C.blue,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              children: [
                const PageHeader('Attendance',
                    subtitle:
                        'Dates follow the society timezone, not this device.'),
                FilterBar(
                  padding: EdgeInsets.zero,
                  children: [
                    AppFilterChip(
                      label:
                          localDate == null ? 'Any date' : fmtYmd(localDate!),
                      icon: Icons.calendar_today_outlined,
                      selected: localDate != null,
                      onSelected: _pickDate,
                    ),
                    AppFilterChip(
                      label: staffName ?? 'All staff',
                      icon: Icons.person_outline_rounded,
                      selected: staffId != null,
                      onSelected: () => _pickStaff(bundle.staff),
                    ),
                    for (final s in kAttendanceStatuses)
                      AppFilterChip(
                        label: attendanceStatusLabel(s),
                        selected: statusFilter == s,
                        onSelected: () => setState(() {
                          statusFilter = statusFilter == s ? null : s;
                          _future = _load(force: true);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  EmptyState(
                    _filtered
                        ? 'No attendance matches these filters'
                        : 'No attendance recorded yet',
                    icon: Icons.how_to_reg_outlined,
                    actionLabel:
                        _filtered ? 'Clear filters' : 'Record attendance',
                    onAction: _filtered
                        ? () => setState(() {
                              staffId = null;
                              localDate = null;
                              statusFilter = null;
                              _future = _load(force: true);
                            })
                        : _record,
                  )
                else ...[
                  Row(children: [
                    Expanded(
                        child: ResultCount(
                            bundle.page.pagination.total, 'record')),
                    if (_filtered)
                      TextButton(
                        onPressed: () => setState(() {
                          staffId = null;
                          localDate = null;
                          statusFilter = null;
                          _future = _load(force: true);
                        }),
                        child: const Text('Clear'),
                      ),
                  ]),
                  for (final a in items)
                    ListRow(
                      leading: AppAvatar(
                        text: initialsOf(
                            bundle.staff[a.staffId]?.fullName ?? '?'),
                        color: badgeColors(_attendanceTone(a.status)).fg,
                      ),
                      title:
                          bundle.staff[a.staffId]?.fullName ?? 'Staff member',
                      subtitle: '${fmtYmd(a.localDate)}'
                          '${a.checkInAt != null ? ' · in ${_hhmm(a.checkInAt)}' : ''}'
                          '${a.checkOutAt != null ? ' · out ${_hhmm(a.checkOutAt)}' : ''}',
                      badges: [
                        StatusBadge(attendanceStatusLabel(a.status),
                            tone: _attendanceTone(a.status)),
                        if (a.correctionHistory.isNotEmpty)
                          StatusBadge(
                            'Corrected ×${a.correctionHistory.length}',
                            tone: BadgeTone.neutral,
                            icon: Icons.history_rounded,
                          ),
                      ],
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveAttendanceDetailPage(
                              attendance: a,
                              staffName: bundle.staff[a.staffId]?.fullName,
                            ),
                          ),
                        );
                        if (mounted) reload();
                      },
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

String _hhmm(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class LiveMarkAttendancePage extends StatefulWidget {
  const LiveMarkAttendancePage({super.key});

  @override
  State<LiveMarkAttendancePage> createState() => _LiveMarkAttendancePageState();
}

class _LiveMarkAttendancePageState extends State<LiveMarkAttendancePage> {
  final _staffId = TextEditingController();
  final _notes = TextEditingController();
  String _status = 'PRESENT';
  String? _localDate;
  bool _submitting = false;
  String? _error;
  List<StaffMember> _staff = const [];
  bool _loadingStaff = true;
  String? _staffError;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final session = authSession;
    if (session == null) return;
    setState(() {
      _loadingStaff = true;
      _staffError = null;
    });
    try {
      final page = await ensureLiveRepositories(session.api).staff.listStaff(
            force: true,
            query: const ListStaffQuery(employmentStatus: 'ACTIVE', limit: 100),
          );
      if (mounted) setState(() => _staff = page.items);
    } catch (e) {
      if (mounted) setState(() => _staffError = staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  @override
  void dispose() {
    _staffId.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStaff() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Select staff member',
      builder: (ctx) => Column(children: [
        for (final s in _staff)
          ListRow(
            dense: true,
            title: s.fullName,
            subtitle: staffCategoryLabel(s.category),
            leading: AppAvatar(text: initialsOf(s.fullName), size: 36),
            trailing: _staffId.text == s.id
                ? const Icon(Icons.check_rounded, color: C.blue)
                : null,
            showChevron: false,
            onTap: () => Navigator.pop(ctx, s.id),
          ),
      ]),
    );
    if (picked != null) {
      setState(() {
        _staffId.text = picked;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    final id = _staffId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Select a staff member.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).staff.markAttendance(
            MarkAttendanceRequest(
              staffId: id,
              status: _status,
              localDate: _localDate,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    StaffMember? selected;
    for (final s in _staff) {
      if (s.id == _staffId.text) selected = s;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Record attendance')),
      body: KeyboardDismissOnTap(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: Sp.pagePadding,
          children: [
            const FormSectionLabel('Who'),
            if (_loadingStaff)
              const SkeletonBox(height: Sz.input)
            else if (_staffError != null)
              Row(children: [
                Expanded(
                    child: Text(_staffError!,
                        style: T.secondary.copyWith(color: C.error))),
                TextButton(onPressed: _loadStaff, child: const Text('Retry')),
              ])
            else if (_staff.isEmpty)
              const InfoNote(
                  'No active staff members. Add staff before recording attendance.',
                  tone: NoteTone.warning)
            else
              PickerField(
                label: 'Staff member',
                value: selected == null
                    ? 'Choose…'
                    : '${selected.fullName} · ${staffCategoryLabel(selected.category)}',
                icon: Icons.person_outline_rounded,
                enabled: !_submitting,
                onTap: _pickStaff,
              ),
            const SizedBox(height: 20),
            const FormSectionLabel('Status'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in kAttendanceStatuses)
                AppFilterChip(
                  label: attendanceStatusLabel(s),
                  selected: _status == s,
                  onSelected:
                      _submitting ? () {} : () => setState(() => _status = s),
                ),
            ]),
            const SizedBox(height: 20),
            const FormSectionLabel('When'),
            PickerField(
              label: 'Date',
              value: _localDate == null
                  ? 'Today (society time)'
                  : fmtYmd(_localDate!),
              helper: 'Leave as today unless back-filling a previous day.',
              enabled: !_submitting,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(_localDate ?? '') ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() => _localDate = _ymd(picked));
                }
              },
              onClear: _localDate == null
                  ? null
                  : () => setState(() => _localDate = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
            InlineError(_error),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Record ${attendanceStatusLabel(_status).toLowerCase()}',
              icon: Icons.how_to_reg_outlined,
              busy: _submitting,
              onPressed: _staff.isEmpty ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class LiveAttendanceDetailPage extends StatefulWidget {
  const LiveAttendanceDetailPage({
    super.key,
    required this.attendance,
    this.staffName,
  });
  final StaffAttendance attendance;
  final String? staffName;

  @override
  State<LiveAttendanceDetailPage> createState() =>
      _LiveAttendanceDetailPageState();
}

class _LiveAttendanceDetailPageState extends State<LiveAttendanceDetailPage> {
  late StaffAttendance _a = widget.attendance;
  bool _busy = false;

  Future<void> _checkout() async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'Check out now?',
      message:
          'Records the current time as the check-out for ${fmtYmd(_a.localDate)}.',
      confirmLabel: 'Check out',
      icon: Icons.logout_rounded,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final updated =
          await ensureLiveRepositories(session.api).staff.checkOut(_a.id);
      if (mounted) {
        setState(() => _a = updated);
        showSuccessSnack(context, 'Checked out.');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correct() async {
    final reasonCtrl = TextEditingController();
    String newStatus = _a.status;
    String? localError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Correct attendance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in kAttendanceStatuses)
                    AppFilterChip(
                      label: attendanceStatusLabel(s),
                      selected: newStatus == s,
                      onSelected: () => setLocal(() => newStatus = s),
                    ),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonCtrl,
                  autofocus: true,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason *',
                    helperText: 'Kept in the correction history.',
                  ),
                  onChanged: (_) => setLocal(() => localError = null),
                ),
                InlineError(localError),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reasonCtrl.text.trim().length < 3) {
                  setLocal(() =>
                      localError = 'Reason must be at least 3 characters.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save correction'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || _busy) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final updated =
          await ensureLiveRepositories(session.api).staff.correctAttendance(
                _a.id,
                CorrectAttendanceRequest(status: newStatus, reason: reason),
              );
      if (mounted) {
        setState(() => _a = updated);
        showSuccessSnack(context, 'Attendance corrected.');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final canCheckout = a.checkOutAt == null &&
        (a.status == 'PRESENT' || a.status == 'HALF_DAY');
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: ListView(
        padding: Sp.pagePadding,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppAvatar(
              text: initialsOf(widget.staffName ?? '?'),
              size: Sz.avatarLg,
              color: badgeColors(_attendanceTone(a.status)).fg,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.staffName ?? 'Staff member', style: T.h1),
                    const SizedBox(height: 3),
                    Text(fmtYmd(a.localDate), style: T.secondary),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusBadge(attendanceStatusLabel(a.status),
                tone: _attendanceTone(a.status)),
            if (a.correctionHistory.isNotEmpty)
              StatusBadge('Corrected ×${a.correctionHistory.length}',
                  tone: BadgeTone.neutral, icon: Icons.history_rounded),
          ]),
          const SizedBox(height: 18),
          DetailCard(title: 'Times', children: [
            DetailRow('Check-in', fmtIsoDateTime(a.checkInAt)),
            DetailRow('Check-out', fmtIsoDateTime(a.checkOutAt)),
            DetailRow('Recorded', fmtIsoDateTime(a.createdAt)),
            if (a.notes != null && a.notes!.trim().isNotEmpty)
              DetailRow('Notes', a.notes!),
          ]),
          const SizedBox(height: 6),
          const SectionTitle('Actions'),
          if (canCheckout)
            QuickActionTile(
              icon: Icons.logout_rounded,
              label: 'Check out',
              subtitle: 'Record the current time as check-out',
              color: C.green,
              enabled: !_busy,
              onTap: _checkout,
            ),
          QuickActionTile(
            icon: Icons.edit_calendar_outlined,
            label: 'Correct status',
            subtitle: 'Requires a reason; kept in history',
            color: C.amber,
            enabled: !_busy,
            onTap: _correct,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          const SizedBox(height: 14),
          const SectionTitle('Correction history'),
          if (a.correctionHistory.isEmpty)
            const EmptyState('No corrections',
                compact: true, icon: Icons.history_rounded)
          else
            AppCard(
              child: Column(children: [
                for (var i = 0; i < a.correctionHistory.length; i++) ...[
                  if (i > 0) const Divider(height: 18),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const AppAvatar(
                        icon: Icons.history_rounded,
                        size: 34,
                        square: true,
                        color: C.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.correctionHistory[i].reason,
                                style: T.bodyStrong),
                            const SizedBox(height: 2),
                            Text(
                                fmtIsoDateTime(
                                    a.correctionHistory[i].correctedAt),
                                style: T.caption),
                            if (a.correctionHistory[i].previous?['status']
                                is String) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Previously ${attendanceStatusLabel(a.correctionHistory[i].previous!['status'] as String)}',
                                style: T.secondary,
                              ),
                            ],
                          ]),
                    ),
                  ]),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

// ─── Shifts ──────────────────────────────────────────────────────────────────

class _ShiftsBundle {
  const _ShiftsBundle({required this.page, required this.staff});
  final Paged<StaffShift> page;
  final Map<String, StaffMember> staff;
}

class LiveAdminShiftsPage extends StatefulWidget {
  const LiveAdminShiftsPage({super.key});

  @override
  State<LiveAdminShiftsPage> createState() => _LiveAdminShiftsPageState();
}

class _LiveAdminShiftsPageState extends State<LiveAdminShiftsPage> {
  String? status = 'SCHEDULED';
  late Future<_ShiftsBundle> _future = _load();
  bool _busy = false;

  Future<_ShiftsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final page = await ensureLiveRepositories(session.api).staff.listShifts(
          force: force,
          query: ListShiftsQuery(status: status, limit: 100),
        );
    final staff = await _staffIndex(force: force);
    return _ShiftsBundle(page: page, staff: staff);
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  Future<void> _assign() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveCreateShiftPage()),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Shift assigned.');
      reload();
    }
  }

  Future<void> _cancelShift(StaffShift sh, String? staffName) async {
    if (_busy) return;
    final reason = await promptTextDialog(
      context,
      title: 'Cancel shift?',
      message:
          '${staffName ?? 'This staff member'} will no longer be scheduled on ${fmtYmd(sh.shiftDate)} ${sh.startTime}–${sh.endTime}.',
      label: 'Reason (optional)',
      confirmLabel: 'Cancel shift',
      cancelLabel: 'Back',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api).staff.cancelShift(
            sh.id,
            reason: reason.trim().isEmpty ? null : reason.trim(),
          );
      if (mounted) {
        showAppSnack(context, 'Shift cancelled.', tone: SnackTone.warning);
        reload();
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'assign-shift',
        onPressed: _assign,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Assign shift'),
      ),
      body: FutureBuilder<_ShiftsBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SkeletonList(items: 6, showHeader: true);
          }
          if (snapshot.hasError) {
            return LoadFailure(
                error: snapshot.error!,
                title: 'Could not load shifts',
                onRetry: reload);
          }
          final bundle = snapshot.data!;
          final items = bundle.page.items.toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
          // Group by date for scannability.
          final groups = <String, List<StaffShift>>{};
          for (final sh in items) {
            groups.putIfAbsent(sh.shiftDate, () => []).add(sh);
          }
          return RefreshIndicator(
            color: C.blue,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              children: [
                const PageHeader('Shifts', subtitle: 'Duty roster for staff'),
                FilterBar(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final s in [null, ...kShiftStatuses])
                      AppFilterChip(
                        label: s == null ? 'All' : humanizeStatus(s),
                        selected: status == s,
                        onSelected: () => setState(() {
                          status = s;
                          _future = _load(force: true);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_busy) const LinearProgressIndicator(minHeight: 3),
                if (items.isEmpty)
                  EmptyState(
                    status == null
                        ? 'No shifts yet'
                        : 'No ${humanizeStatus(status!).toLowerCase()} shifts',
                    icon: Icons.schedule_rounded,
                    actionLabel: status == 'SCHEDULED' || status == null
                        ? 'Assign a shift'
                        : 'Show all',
                    onAction: status == 'SCHEDULED' || status == null
                        ? _assign
                        : () => setState(() {
                              status = null;
                              _future = _load(force: true);
                            }),
                  )
                else ...[
                  ResultCount(bundle.page.pagination.total, 'shift'),
                  for (final entry in groups.entries) ...[
                    SectionTitle(fmtYmd(entry.key)),
                    for (final sh in entry.value)
                      ListRow(
                        leading: AppAvatar(
                          text: initialsOf(
                              bundle.staff[sh.staffId]?.fullName ?? '?'),
                          color: badgeColors(_shiftTone(sh.status)).fg,
                        ),
                        title: bundle.staff[sh.staffId]?.fullName ??
                            'Staff member',
                        subtitle: '${sh.startTime}–${sh.endTime}'
                            '${sh.isOvernight ? ' (overnight)' : ''}'
                            '${sh.dutyLocation != null ? ' · ${sh.dutyLocation}' : ''}',
                        badges: [
                          StatusBadge(humanizeStatus(sh.status),
                              tone: _shiftTone(sh.status)),
                          if (bundle.staff[sh.staffId] != null)
                            StatusBadge(
                              staffCategoryLabel(
                                  bundle.staff[sh.staffId]!.category),
                              tone: BadgeTone.neutral,
                            ),
                        ],
                        showChevron: false,
                        trailing: sh.status == 'SCHEDULED'
                            ? IconButton(
                                tooltip: 'Cancel shift',
                                onPressed: _busy
                                    ? null
                                    : () => _cancelShift(
                                        sh, bundle.staff[sh.staffId]?.fullName),
                                icon: const Icon(Icons.event_busy_outlined,
                                    color: C.error),
                              )
                            : null,
                        footer: sh.cancelReason != null &&
                                sh.cancelReason!.trim().isNotEmpty
                            ? Text('Cancelled: ${sh.cancelReason}',
                                style: T.caption)
                            : null,
                      ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class LiveCreateShiftPage extends StatefulWidget {
  const LiveCreateShiftPage({super.key});

  @override
  State<LiveCreateShiftPage> createState() => _LiveCreateShiftPageState();
}

class _LiveCreateShiftPageState extends State<LiveCreateShiftPage> {
  final _staffId = TextEditingController();
  final _start = TextEditingController(text: '09:00');
  final _end = TextEditingController(text: '17:00');
  final _location = TextEditingController();
  final _notes = TextEditingController();
  String _shiftDate = _ymd(DateTime.now());
  bool _submitting = false;
  String? _error;
  List<StaffMember> _staff = const [];
  bool _loadingStaff = true;
  String? _staffError;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final session = authSession;
    if (session == null) return;
    setState(() {
      _loadingStaff = true;
      _staffError = null;
    });
    try {
      final page = await ensureLiveRepositories(session.api).staff.listStaff(
            force: true,
            query: const ListStaffQuery(employmentStatus: 'ACTIVE', limit: 100),
          );
      if (mounted) setState(() => _staff = page.items);
    } catch (e) {
      if (mounted) setState(() => _staffError = staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  @override
  void dispose() {
    _staffId.dispose();
    _start.dispose();
    _end.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStaff() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Select staff member',
      builder: (ctx) => Column(children: [
        for (final s in _staff)
          ListRow(
            dense: true,
            title: s.fullName,
            subtitle: staffCategoryLabel(s.category),
            leading: AppAvatar(text: initialsOf(s.fullName), size: 36),
            trailing: _staffId.text == s.id
                ? const Icon(Icons.check_rounded, color: C.blue)
                : null,
            showChevron: false,
            onTap: () => Navigator.pop(ctx, s.id),
          ),
      ]),
    );
    if (picked != null) {
      setState(() {
        _staffId.text = picked;
        _error = null;
      });
    }
  }

  bool get _overnight {
    int? m(String v) {
      final x = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v.trim());
      if (x == null) return null;
      return int.parse(x.group(1)!) * 60 + int.parse(x.group(2)!);
    }

    final s = m(_start.text);
    final e = m(_end.text);
    return s != null && e != null && e <= s;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    final id = _staffId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Select a staff member.');
      return;
    }
    if (_start.text.trim().isEmpty || _end.text.trim().isEmpty) {
      setState(() => _error = 'Set start and end times.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).staff.createShift(
            CreateShiftRequest(
              staffId: id,
              shiftDate: _shiftDate,
              startTime: _start.text.trim(),
              endTime: _end.text.trim(),
              dutyLocation:
                  _location.text.trim().isEmpty ? null : _location.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    StaffMember? selected;
    for (final s in _staff) {
      if (s.id == _staffId.text) selected = s;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Assign shift')),
      body: KeyboardDismissOnTap(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: Sp.pagePadding,
          children: [
            const FormSectionLabel('Who'),
            if (_loadingStaff)
              const SkeletonBox(height: Sz.input)
            else if (_staffError != null)
              Row(children: [
                Expanded(
                    child: Text(_staffError!,
                        style: T.secondary.copyWith(color: C.error))),
                TextButton(onPressed: _loadStaff, child: const Text('Retry')),
              ])
            else if (_staff.isEmpty)
              const InfoNote(
                  'No active staff members. Add staff before assigning shifts.',
                  tone: NoteTone.warning)
            else
              PickerField(
                label: 'Staff member',
                value: selected == null
                    ? 'Choose…'
                    : '${selected.fullName} · ${staffCategoryLabel(selected.category)}',
                icon: Icons.person_outline_rounded,
                enabled: !_submitting,
                onTap: _pickStaff,
              ),
            const SizedBox(height: 20),
            const FormSectionLabel('When'),
            PickerField(
              label: 'Shift date',
              value: fmtYmd(_shiftDate),
              enabled: !_submitting,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(_shiftDate) ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _shiftDate = _ymd(picked));
                }
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TimeField(
                    controller: _start, label: 'Start', enabled: !_submitting),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TimeField(
                    controller: _end, label: 'End', enabled: !_submitting),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              _overnight
                  ? 'Ends after midnight — recorded as an overnight shift.'
                  : 'An end time earlier than the start is treated as overnight.',
              style: T.caption,
            ),
            const SizedBox(height: 20),
            const FormSectionLabel('Details'),
            TextField(
              controller: _location,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Duty location',
                hintText: 'e.g. Main gate, Tower B lobby',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
            InlineError(_error),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Assign shift',
              icon: Icons.check_rounded,
              busy: _submitting,
              onPressed: _staff.isEmpty ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
