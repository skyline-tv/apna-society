import 'package:flutter/material.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/common.dart';
import '../../api/models/staff_models.dart';
import '../../api/repositories/live_repositories.dart';
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

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _shortIso(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day}/${d.month}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<StaffMember>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading staff…');
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
                      'Staff',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveStaffFormPage(),
                        ),
                      );
                      if (ok == true) reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Employment records only — creating staff does not grant app login.',
                style: TextStyle(color: C.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All status'),
                    selected: employmentStatus == null,
                    onSelected: (_) {
                      setState(() {
                        employmentStatus = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  for (final s in kEmploymentStatuses)
                    FilterChip(
                      label: Text(employmentStatusLabel(s)),
                      selected: employmentStatus == s,
                      onSelected: (_) {
                        setState(() {
                          employmentStatus = s;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All categories'),
                    selected: category == null,
                    onSelected: (_) {
                      setState(() {
                        category = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  for (final c in kStaffCategories)
                    FilterChip(
                      label: Text(staffCategoryLabel(c)),
                      selected: category == c,
                      onSelected: (_) {
                        setState(() {
                          category = c;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No staff records')
              else
                ...items.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveStaffDetailPage(staffId: s.id),
                          ),
                        );
                        reload();
                      },
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${staffCategoryLabel(s.category)} · ${s.phone}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(
                                employmentStatusLabel(s.employmentStatus),
                              ),
                              StatusBadge(s.employmentType),
                              if (s.linkedUserId != null)
                                const StatusBadge('Linked user'),
                            ],
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

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        _toast(context, 'Updated');
        reload();
      }
    } catch (e) {
      if (mounted) _toast(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff detail')),
      body: FutureBuilder<StaffMember>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading…');
          }
          if (snapshot.hasError) {
            return LoadFailure(error: snapshot.error!, onRetry: reload);
          }
          final s = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                s.fullName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusBadge(employmentStatusLabel(s.employmentStatus)),
                  StatusBadge(staffCategoryLabel(s.category)),
                  StatusBadge(s.employmentType),
                ],
              ),
              const SizedBox(height: 16),
              _line('Phone', s.phone),
              _line('Email', s.email ?? '—'),
              _line('Joined', s.joiningDate),
              _line('Address', s.address ?? '—'),
              _line(
                'Emergency',
                s.emergencyContactName == null
                    ? '—'
                    : '${s.emergencyContactName} · ${s.emergencyContactPhone ?? ''}',
              ),
              _line('Notes', s.notes ?? '—'),
              _line(
                'Linked user',
                s.linkedUserId ?? 'None (employment record only)',
              ),
              if (s.statusReason != null) _line('Status reason', s.statusReason!),
              if (s.deactivatedAt != null)
                _line('Deactivated', _shortIso(s.deactivatedAt)),
              if (s.terminatedAt != null)
                _line('Terminated', _shortIso(s.terminatedAt)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveStaffFormPage(existing: s),
                          ),
                        );
                        if (ok == true) reload();
                      },
                child: const Text('Edit'),
              ),
              const SizedBox(height: 8),
              if (s.employmentStatus == 'ACTIVE') ...[
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final reason = await _askReason('Deactivate staff');
                          if (reason == null) return;
                          await _run(() async {
                            final session = authSession!;
                            await ensureLiveRepositories(session.api)
                                .staff
                                .deactivateStaff(
                                  s.id,
                                  reason: reason.isEmpty ? null : reason,
                                );
                          });
                        },
                  child: const Text('Deactivate'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final reason = await _askReason('Terminate staff');
                          if (reason == null) return;
                          await _run(() async {
                            final session = authSession!;
                            await ensureLiveRepositories(session.api)
                                .staff
                                .terminateStaff(
                                  s.id,
                                  reason: reason.isEmpty ? null : reason,
                                );
                          });
                        },
                  child: const Text('Terminate'),
                ),
              ] else if (s.employmentStatus == 'INACTIVE')
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final session = authSession!;
                            await ensureLiveRepositories(session.api)
                                .staff
                                .reactivateStaff(s.id);
                          }),
                  child: const Text('Reactivate'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(color: C.muted)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class LiveStaffFormPage extends StatefulWidget {
  const LiveStaffFormPage({super.key, this.existing});
  final StaffMember? existing;

  @override
  State<LiveStaffFormPage> createState() => _LiveStaffFormPageState();
}

class _LiveStaffFormPageState extends State<LiveStaffFormPage> {
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
  late String _category = widget.existing?.category ?? 'OTHER';
  late String _employmentType =
      widget.existing?.employmentType ?? 'PERMANENT';
  late String _joiningDate =
      widget.existing?.joiningDate ?? _ymd(DateTime.now());
  bool _submitting = false;

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

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.length < 7) {
      _toast(context, 'Enter full name and a valid phone');
      return;
    }
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
            address:
                _address.text.trim().isEmpty ? null : _address.text.trim(),
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
            address:
                _address.text.trim().isEmpty ? null : _address.text.trim(),
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
      if (mounted) _toast(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit staff' : 'Add staff')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            keyboardType: TextInputType.phone,
          ),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in kStaffCategories)
                DropdownMenuItem(value: c, child: Text(staffCategoryLabel(c))),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          DropdownButtonFormField<String>(
            value: _employmentType,
            decoration: const InputDecoration(labelText: 'Employment type'),
            items: [
              for (final t in kEmploymentTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) =>
                setState(() => _employmentType = v ?? _employmentType),
          ),
          if (!editing)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Joining date: $_joiningDate'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(_joiningDate) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _joiningDate = _ymd(picked));
                }
              },
            ),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address (optional)'),
          ),
          TextField(
            controller: _emergencyName,
            decoration: const InputDecoration(
              labelText: 'Emergency contact name',
            ),
          ),
          TextField(
            controller: _emergencyPhone,
            decoration: const InputDecoration(
              labelText: 'Emergency contact phone',
            ),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 3,
          ),
          TextField(
            controller: _linkedUserId,
            decoration: const InputDecoration(
              labelText: 'Linked user ObjectId (optional)',
              helperText:
                  'Does not create a login. Must be an existing society member.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

// ─── Attendance ──────────────────────────────────────────────────────────────

class LiveAdminAttendancePage extends StatefulWidget {
  const LiveAdminAttendancePage({super.key});

  @override
  State<LiveAdminAttendancePage> createState() =>
      _LiveAdminAttendancePageState();
}

class _LiveAdminAttendancePageState extends State<LiveAdminAttendancePage> {
  String? staffId;
  String? localDate;
  late Future<Paged<StaffAttendance>> _future = _load();

  Future<Paged<StaffAttendance>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).staff.listAttendance(
          force: force,
          query: ListAttendanceQuery(
            staffId: staffId,
            localDate: localDate,
            limit: 50,
          ),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<StaffAttendance>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading attendance…');
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
                      'Attendance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveMarkAttendancePage(),
                        ),
                      );
                      if (ok == true) reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Record'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  localDate == null
                      ? 'Filter date: all'
                      : 'Filter date: $localDate',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (localDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            localDate = null;
                            _future = _load(force: true);
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.tryParse(localDate ?? '') ??
                              DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (picked != null) {
                          setState(() {
                            localDate = _ymd(picked);
                            _future = _load(force: true);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Text(
                'Dates use society timezone from the backend — not device time.',
                style: TextStyle(color: C.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No attendance records')
              else
                ...items.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveAttendanceDetailPage(attendance: a),
                          ),
                        );
                        reload();
                      },
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Date ${a.localDate}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            'Staff ${a.staffId}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(attendanceStatusLabel(a.status)),
                              if (a.correctionHistory.isNotEmpty)
                                StatusBadge(
                                  '${a.correctionHistory.length} correction(s)',
                                ),
                            ],
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
  List<StaffMember> _staff = const [];

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final session = authSession;
    if (session == null) return;
    final page = await ensureLiveRepositories(session.api).staff.listStaff(
          force: true,
          query: const ListStaffQuery(employmentStatus: 'ACTIVE', limit: 100),
        );
    if (mounted) setState(() => _staff = page.items);
  }

  @override
  void dispose() {
    _staffId.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final id = _staffId.text.trim();
    if (id.isEmpty) {
      _toast(context, 'Select a staff member');
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
      if (mounted) _toast(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record attendance')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            value: _staff.any((s) => s.id == _staffId.text)
                ? _staffId.text
                : null,
            decoration: const InputDecoration(labelText: 'Staff'),
            items: [
              for (final s in _staff)
                DropdownMenuItem(
                  value: s.id,
                  child: Text('${s.fullName} (${staffCategoryLabel(s.category)})'),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _staffId.text = v);
            },
          ),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final s in kAttendanceStatuses)
                DropdownMenuItem(
                  value: s,
                  child: Text(attendanceStatusLabel(s)),
                ),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _localDate == null
                  ? 'Date: society today (omit to use server)'
                  : 'Date: $_localDate',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) {
                setState(() => _localDate = _ymd(picked));
              }
            },
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Record'),
          ),
        ],
      ),
    );
  }
}

class LiveAttendanceDetailPage extends StatefulWidget {
  const LiveAttendanceDetailPage({super.key, required this.attendance});
  final StaffAttendance attendance;

  @override
  State<LiveAttendanceDetailPage> createState() =>
      _LiveAttendanceDetailPageState();
}

class _LiveAttendanceDetailPageState extends State<LiveAttendanceDetailPage> {
  late StaffAttendance _a = widget.attendance;
  bool _busy = false;

  Future<void> _checkout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final updated =
          await ensureLiveRepositories(session.api).staff.checkOut(_a.id);
      if (mounted) {
        setState(() => _a = updated);
        _toast(context, 'Checked out');
      }
    } catch (e) {
      if (mounted) _toast(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correct() async {
    final status = _a.status;
    final reasonCtrl = TextEditingController();
    String newStatus = status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Correct attendance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: newStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final s in kAttendanceStatuses)
                  DropdownMenuItem(
                    value: s,
                    child: Text(attendanceStatusLabel(s)),
                  ),
              ],
              onChanged: (v) => newStatus = v ?? newStatus,
            ),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final reason = reasonCtrl.text.trim();
    if (reason.length < 3) {
      _toast(context, 'Reason must be at least 3 characters');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession!;
      final updated = await ensureLiveRepositories(session.api)
          .staff
          .correctAttendance(
            _a.id,
            CorrectAttendanceRequest(status: newStatus, reason: reason),
          );
      if (mounted) {
        setState(() => _a = updated);
        _toast(context, 'Corrected');
      }
    } catch (e) {
      if (mounted) _toast(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance detail')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _a.localDate,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: C.navy,
            ),
          ),
          const SizedBox(height: 8),
          StatusBadge(attendanceStatusLabel(_a.status)),
          const SizedBox(height: 16),
          Text('Staff: ${_a.staffId}'),
          Text('Check-in: ${_shortIso(_a.checkInAt)}'),
          Text('Check-out: ${_shortIso(_a.checkOutAt)}'),
          Text('Notes: ${_a.notes ?? '—'}'),
          const SizedBox(height: 16),
          const SectionTitle('Correction history'),
          if (_a.correctionHistory.isEmpty)
            const Text('No corrections', style: TextStyle(color: C.muted))
          else
            ..._a.correctionHistory.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_shortIso(c.correctedAt)} · ${c.reason}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (_a.checkOutAt == null &&
              (_a.status == 'PRESENT' || _a.status == 'HALF_DAY'))
            FilledButton(
              onPressed: _busy ? null : _checkout,
              child: const Text('Check out'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _correct,
            child: const Text('Correct'),
          ),
        ],
      ),
    );
  }
}

// ─── Shifts ──────────────────────────────────────────────────────────────────

class LiveAdminShiftsPage extends StatefulWidget {
  const LiveAdminShiftsPage({super.key});

  @override
  State<LiveAdminShiftsPage> createState() => _LiveAdminShiftsPageState();
}

class _LiveAdminShiftsPageState extends State<LiveAdminShiftsPage> {
  String? status = 'SCHEDULED';
  late Future<Paged<StaffShift>> _future = _load();

  Future<Paged<StaffShift>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).staff.listShifts(
          force: force,
          query: ListShiftsQuery(status: status, limit: 100),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<StaffShift>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading shifts…');
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
                      'Shifts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LiveCreateShiftPage(),
                        ),
                      );
                      if (ok == true) reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Assign'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in [null, ...kShiftStatuses])
                    FilterChip(
                      label: Text(s ?? 'All'),
                      selected: status == s,
                      onSelected: (_) {
                        setState(() {
                          status = s;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No shifts')
              else
                ...items.map(
                  (sh) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${sh.shiftDate} · ${sh.startTime}–${sh.endTime}'
                            '${sh.isOvernight ? ' (overnight)' : ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            'Staff ${sh.staffId}'
                            '${sh.dutyLocation != null ? ' · ${sh.dutyLocation}' : ''}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StatusBadge(sh.status),
                          if (sh.status == 'SCHEDULED') ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () async {
                                final reasonCtrl = TextEditingController();
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Cancel shift'),
                                    content: TextField(
                                      controller: reasonCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Reason (optional)',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Back'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Cancel shift'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                try {
                                  final session = authSession!;
                                  await ensureLiveRepositories(session.api)
                                      .staff
                                      .cancelShift(
                                        sh.id,
                                        reason: reasonCtrl.text.trim().isEmpty
                                            ? null
                                            : reasonCtrl.text.trim(),
                                      );
                                  reload();
                                } catch (e) {
                                  if (context.mounted) {
                                    _toast(context, staffErrorMessage(e));
                                  }
                                }
                              },
                              child: const Text('Cancel shift'),
                            ),
                          ],
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
  List<StaffMember> _staff = const [];

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final session = authSession;
    if (session == null) return;
    final page = await ensureLiveRepositories(session.api).staff.listStaff(
          force: true,
          query: const ListStaffQuery(employmentStatus: 'ACTIVE', limit: 100),
        );
    if (mounted) setState(() => _staff = page.items);
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

  Future<void> _submit() async {
    if (_submitting) return;
    final id = _staffId.text.trim();
    if (id.isEmpty) {
      _toast(context, 'Select staff');
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
              dutyLocation: _location.text.trim().isEmpty
                  ? null
                  : _location.text.trim(),
              notes:
                  _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _toast(context, staffErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assign shift')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            value: _staff.any((s) => s.id == _staffId.text)
                ? _staffId.text
                : null,
            decoration: const InputDecoration(labelText: 'Staff'),
            items: [
              for (final s in _staff)
                DropdownMenuItem(value: s.id, child: Text(s.fullName)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _staffId.text = v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date: $_shiftDate'),
            trailing: const Icon(Icons.calendar_today),
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
          TextField(
            controller: _start,
            decoration: const InputDecoration(
              labelText: 'Start (HH:mm)',
              helperText: 'Overnight: end time earlier than start is allowed',
            ),
          ),
          TextField(
            controller: _end,
            decoration: const InputDecoration(labelText: 'End (HH:mm)'),
          ),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Duty location'),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Create shift'),
          ),
        ],
      ),
    );
  }
}
