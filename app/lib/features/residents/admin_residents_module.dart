import 'package:flutter/material.dart';

import '../../api/auth/admin_api_messages.dart';
import '../../api/auth/auth_session.dart';
import '../../api/models/admin_user_models.dart';
import '../../api/models/common.dart';
import '../../api/models/society_models.dart';
import '../../api/models/vehicle_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../../ui/issued_credentials_dialog.dart';
import '../../ui/load_failure.dart';
import '../vehicles/live_vehicles_module.dart' show vehicleErrorMessage;
import '../vehicles/vehicle_drafts.dart';

String _userPhone(AdminUser user) {
  if (user.mobileE164 != null) return '+${user.mobileE164}';
  final p = (user.phone ?? '').trim();
  return p.isEmpty ? 'No phone' : p;
}

String _roleLabel(String role) {
  switch (role.toUpperCase()) {
    case 'OWNER':
      return 'Owner';
    case 'TENANT':
      return 'Tenant';
    case 'ADMIN':
      return 'Admin';
    case 'GUARD':
      return 'Guard';
    default:
      return humanizeStatus(role);
  }
}

/// Shared resident row for lists and pickers.
class _ResidentRow extends StatelessWidget {
  const _ResidentRow({required this.user, required this.onTap});
  final AdminUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roles = user.societyRoles.isEmpty ? user.roles : user.societyRoles;
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        text: initialsOf(user.name),
        color: user.isActive ? C.blue : C.muted,
        size: 42,
      ),
      title: user.name.isEmpty ? user.email : user.name,
      subtitle: '${_userPhone(user)}\n${user.email}',
      badges: [
        for (final r in roles) StatusBadge(_roleLabel(r), tone: BadgeTone.info),
        if (!user.isActive) const StatusBadge('Inactive'),
        if (user.mobileE164 != null && !user.mobileVerified)
          const StatusBadge('Mobile unverified', tone: BadgeTone.warning),
      ],
      showChevron: true,
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

/// Admin resident list with Owner / Tenant filters.
class AdminResidentsPage extends StatefulWidget {
  const AdminResidentsPage({super.key});

  @override
  State<AdminResidentsPage> createState() => _AdminResidentsPageState();
}

class _AdminResidentsPageState extends State<AdminResidentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: 0);
  String query = '';
  String statusFilter = 'all';
  int ownersPage = 1;
  int tenantsPage = 1;
  static const _limit = 20;
  late Future<_ResidentsBundle> _ownersFuture = _load(role: 'OWNER', page: 1);
  late Future<_ResidentsBundle> _tenantsFuture = _load(role: 'TENANT', page: 1);
  final _searchDebounce = Debouncer();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_ResidentsBundle> _load({
    required String role,
    required int page,
    bool force = false,
  }) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    bool? isActive;
    if (statusFilter == 'active') isActive = true;
    if (statusFilter == 'inactive') isActive = false;
    final result = await ensureLiveRepositories(session.api).users.listUsers(
          force: force,
          query: ListUsersQuery(
            role: role,
            search: query.trim().isEmpty ? null : query.trim(),
            isActive: isActive,
            page: page,
            limit: _limit,
          ),
        );
    return _ResidentsBundle(page: result);
  }

  void reload() {
    setState(() {
      _ownersFuture = _load(role: 'OWNER', page: ownersPage, force: true);
      _tenantsFuture = _load(role: 'TENANT', page: tenantsPage, force: true);
    });
  }

  Future<void> _refreshAll() async {
    reload();
    await Future.wait([_ownersFuture, _tenantsFuture]);
  }

  Future<void> _openProvision(String role) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminProvisionResidentPage(initialRole: role),
      ),
    );
    if (created == true && mounted) reload();
  }

  Future<void> _openDetail(AdminUser user) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminResidentDetailPage(userId: user.id),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'provision-resident',
        onPressed: () => _openProvision(_tabs.index == 0 ? 'OWNER' : 'TENANT'),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(_tabs.index == 0 ? 'Add owner' : 'Add tenant'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: SearchField(
              controller: _searchCtrl,
              hint: 'Search name, email or phone',
              onChanged: (v) {
                query = v;
                _searchDebounce.run(() {
                  ownersPage = 1;
                  tenantsPage = 1;
                  reload();
                });
              },
            ),
          ),
          FilterBar(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            children: [
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
                    ownersPage = 1;
                    tenantsPage = 1;
                    reload();
                  },
                ),
            ],
          ),
          Material(
            color: C.surface,
            child: TabBar(
              controller: _tabs,
              onTap: (_) => setState(() {}),
              tabs: const [
                Tab(text: 'Owners'),
                Tab(text: 'Tenants'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _list(
                  future: _ownersFuture,
                  emptyLabel: 'No owners found',
                  onPage: (p) {
                    ownersPage = p;
                    setState(() {
                      _ownersFuture =
                          _load(role: 'OWNER', page: p, force: true);
                    });
                  },
                  currentPage: ownersPage,
                ),
                _list(
                  future: _tenantsFuture,
                  emptyLabel: 'No tenants found',
                  onPage: (p) {
                    tenantsPage = p;
                    setState(() {
                      _tenantsFuture =
                          _load(role: 'TENANT', page: p, force: true);
                    });
                  },
                  currentPage: tenantsPage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list({
    required Future<_ResidentsBundle> future,
    required String emptyLabel,
    required ValueChanged<int> onPage,
    required int currentPage,
  }) {
    return FutureBuilder<_ResidentsBundle>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 6);
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            title: 'Could not load residents',
            onRetry: reload,
          );
        }
        final page = snap.data!.page;
        final rows = page.items;
        if (rows.isEmpty) {
          return _emptyScrollable(
            EmptyState(
              emptyLabel,
              icon: Icons.people_outline_rounded,
              actionLabel: query.isNotEmpty || statusFilter != 'all'
                  ? 'Clear filters'
                  : null,
              onAction: () {
                _searchCtrl.clear();
                query = '';
                statusFilter = 'all';
                ownersPage = 1;
                tenantsPage = 1;
                reload();
              },
            ),
            _refreshAll,
          );
        }
        return RefreshIndicator(
          color: C.blue,
          onRefresh: _refreshAll,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rows.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return ResultCount(page.pagination.total, 'resident');
              }
              if (i == rows.length + 1) {
                return PaginationBar(
                  page: page.pagination.page,
                  totalPages: page.pagination.totalPages,
                  onPrevious: () => onPage(currentPage - 1),
                  onNext: () => onPage(currentPage + 1),
                );
              }
              final user = rows[i - 1];
              return _ResidentRow(user: user, onTap: () => _openDetail(user));
            },
          ),
        );
      },
    );
  }
}

class _ResidentsBundle {
  const _ResidentsBundle({required this.page});
  final Paged<AdminUser> page;
}

/// Provision OWNER or TENANT via `POST /admin/users`.
class AdminProvisionResidentPage extends StatefulWidget {
  const AdminProvisionResidentPage({super.key, required this.initialRole});
  final String initialRole;

  @override
  State<AdminProvisionResidentPage> createState() =>
      _AdminProvisionResidentPageState();
}

class _AdminProvisionResidentPageState
    extends State<AdminProvisionResidentPage> {
  final _formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final username = TextEditingController();
  late String role = widget.initialRole;
  bool saving = false;
  bool reviewing = false;
  String? formError;
  String? flatId;
  final vehicleDrafts = <VehicleDraftControllers>[];
  late final Future<List<FlatSummary>> _flats = _loadFlats();

  Future<List<FlatSummary>> _loadFlats() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).society.listAllFlats(
          isActive: true,
        );
  }

  List<FlatSummary> _assignableFlats(List<FlatSummary> flats) {
    final wanted = role == 'OWNER' ? 'VACANT' : 'OWNER_OCCUPIED';
    return flats
        .where((f) => f.occupancyStatus.toUpperCase() == wanted)
        .toList();
  }

  String _flatLabel(FlatSummary flat) {
    final wing = (flat.wingCode ?? '').trim();
    final label = wing.isEmpty ? flat.number : '$wing-${flat.number}';
    return '$label · ${humanizeStatus(flat.occupancyStatus)}';
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    username.dispose();
    for (final draft in vehicleDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  String get _roleLabel => role == 'OWNER' ? 'Owner' : 'Tenant';

  Future<void> _continue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => formError = null);
    if (!_formKey.currentState!.validate()) return;
    final vehicleError = validateVehicleDrafts(vehicleDrafts);
    if (vehicleError != null) {
      setState(() => formError = vehicleError);
      return;
    }
    final payloads = vehicleDraftPayloads(vehicleDrafts);
    if (payloads.isNotEmpty && (flatId == null || flatId!.isEmpty)) {
      setState(() => formError = 'Assign a flat to register vehicles.');
      return;
    }
    setState(() => reviewing = true);
  }

  Future<void> save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => formError = null);
    final session = authSession;
    if (session == null) {
      setState(() => formError = 'Not signed in.');
      return;
    }
    setState(() => saving = true);
    try {
      final repos = ensureLiveRepositories(session.api);
      final result = await repos.users.provision(
        name: name.text,
        email: email.text,
        role: role,
        phone: phone.text.trim().isEmpty ? null : phone.text,
        username: username.text.trim().isEmpty ? null : username.text.trim(),
        flatId: flatId,
        vehicles: vehicleDraftPayloads(vehicleDrafts),
      );
      repos.invalidateAfterResidentMutation();
      if (!mounted) return;
      final temp = result.temporaryPassword;
      if (temp != null && temp.isNotEmpty) {
        await showIssuedCredentialsDialog(
          context,
          recipientName: result.user.name,
          username: result.user.username ?? username.text.trim(),
          temporaryPassword: temp,
        );
      }
      if (!mounted) return;
      showSuccessSnack(
          context,
          result.reusedExisting
              ? 'Existing account updated and linked to this society.'
              : '$_roleLabel account created.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        formError = adminApiErrorMessage(e);
        reviewing = false;
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: reviewing ? 'Confirm resident' : 'Add resident',
      formKey: reviewing ? null : _formKey,
      actions: reviewing
          ? [
              TextButton(
                onPressed: saving
                    ? null
                    : () => setState(() {
                          reviewing = false;
                          formError = null;
                        }),
                child: const Text('Edit'),
              ),
            ]
          : null,
      bottom: PrimaryButton(
        label: reviewing
            ? 'Create $_roleLabel account'
            : 'Review & continue',
        icon: reviewing
            ? Icons.person_add_alt_1_outlined
            : Icons.arrow_forward_rounded,
        busy: saving,
        onPressed: reviewing ? save : _continue,
      ),
      children: reviewing ? _reviewBody() : _formBody(),
    );
  }

  List<Widget> _formBody() => [
        const FormSectionLabel('Role in this society'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'OWNER',
                label: Text('Owner'),
                icon: Icon(Icons.home_outlined, size: 18)),
            ButtonSegment(
                value: 'TENANT',
                label: Text('Tenant'),
                icon: Icon(Icons.person_pin_circle_outlined, size: 18)),
          ],
          selected: {role},
          onSelectionChanged: saving
              ? null
              : (s) => setState(() {
                    role = s.first;
                    flatId = null;
                  }),
        ),
        const SizedBox(height: 8),
        Text(
          role == 'OWNER'
              ? 'Owners can hold financial access for a flat.'
              : 'Tenants receive residential access when assigned to a flat.',
          style: T.caption,
        ),
        const SizedBox(height: 20),
        const FormSectionLabel('Contact'),
        TextFormField(
          controller: name,
          enabled: !saving,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Full name *',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: email,
          enabled: !saving,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email *',
            helperText: 'Used for notifications and receipts.',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Email is required.';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
              return 'Enter a valid email.';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: username,
          enabled: !saving,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Username *',
            helperText: '3–32 chars: letters, numbers, underscore, hyphen.',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Username is required.';
            if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{2,31}$').hasMatch(t)) {
              return 'Enter a valid username.';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: phone,
          enabled: !saving,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => saving ? null : _continue(),
          decoration: const InputDecoration(
            labelText: 'Phone',
            hintText: '+91 98765 43210',
            helperText: 'Optional contact number (not used for login).',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 20),
        const FormSectionLabel('Flat assignment'),
        Text(
          role == 'OWNER'
              ? 'Optional. Vacant flats can be assigned now so vehicles can be registered with this owner.'
              : 'Optional. Owner-occupied flats can be assigned now so vehicles can be registered with this tenant.',
          style: T.caption,
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<FlatSummary>>(
          future: _flats,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              );
            }
            if (snap.hasError) {
              return InfoNote(
                'Could not load flats. ${adminApiErrorMessage(snap.error!)}',
                tone: NoteTone.warning,
              );
            }
            final options = _assignableFlats(snap.data ?? const []);
            final selectedId =
                options.any((f) => f.id == flatId) ? (flatId ?? '') : '';
            return DropdownButtonFormField<String>(
              value: selectedId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Assign to flat',
                helperText: options.isEmpty
                    ? (role == 'OWNER'
                        ? 'No vacant flats available right now.'
                        : 'No owner-occupied flats available right now.')
                    : 'Leave empty to assign later from Flat details.',
                border: const OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Do not assign yet'),
                ),
                for (final flat in options)
                  DropdownMenuItem<String>(
                    value: flat.id,
                    child: Text(_flatLabel(flat)),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(
                        () => flatId =
                            (value == null || value.isEmpty) ? null : value,
                      ),
            );
          },
        ),
        const SizedBox(height: 20),
        VehicleDraftsEditor(
          drafts: vehicleDrafts,
          enabled: !saving,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        const InfoNote(
          'A temporary password is generated securely. Share it out-of-band; the resident must change it on first login. If this email already exists, the server reuses that account.',
        ),
        InlineError(formError),
      ];

  List<Widget> _reviewBody() {
    final vehicles = vehicleDraftPayloads(vehicleDrafts);
    final vehicleLines = vehicles.isEmpty
        ? 'None'
        : vehicles
            .map(
              (v) =>
                  '${vehicleTypeLabel(v.vehicleType)} ${v.registrationNumber}'
                  '${v.make == null && v.model == null ? '' : ' · ${[
                    v.make,
                    v.model,
                  ].whereType<String>().join(' ')}'}',
            )
            .join('\n');
    return [
      ReviewSummary(
        title: 'About to create',
        rows: [
          ('Role', _roleLabel),
          ('Name', name.text.trim()),
          ('Email', email.text.trim()),
          ('Username', username.text.trim()),
          (
            'Phone',
            phone.text.trim().isEmpty ? 'Not set yet' : phone.text.trim()
          ),
          (
            'Flat',
            flatId == null ? 'Assign later from Flat details' : 'Assign now'
          ),
          ('Vehicles', vehicleLines),
        ],
        note: flatId == null
            ? 'After creation, assign this person to a flat from Flat details. A temporary password will be shown once for you to share securely.'
            : 'This resident will be assigned to the selected flat. Any vehicles listed here are saved on that assignment.',
      ),
      InlineError(formError),
    ];
  }
}

class AdminResidentDetailPage extends StatefulWidget {
  const AdminResidentDetailPage({super.key, required this.userId});
  final String userId;

  @override
  State<AdminResidentDetailPage> createState() =>
      _AdminResidentDetailPageState();
}

class _ResidentDetailBundle {
  const _ResidentDetailBundle({required this.user, required this.vehicles});
  final AdminUser user;
  final List<Vehicle> vehicles;
}

class _AdminResidentDetailPageState extends State<AdminResidentDetailPage> {
  late Future<_ResidentDetailBundle> _future = _load();
  bool _busy = false;

  Future<_ResidentDetailBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final user = await repos.users.getUser(widget.userId, force: force);
    final vehicles = await repos.vehicles.listAdminVehicles(
      force: true,
      query: ListAdminVehiclesQuery(
        registeredUserId: widget.userId,
        limit: 100,
      ),
    );
    return _ResidentDetailBundle(user: user, vehicles: vehicles.items);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate(AdminUser user) async {
    final reason = await promptTextDialog(
      context,
      title: 'Deactivate ${user.name}?',
      message:
          'The resident will no longer be able to sign in. Active flat assignments are not changed here.',
      label: 'Reason (optional)',
      confirmLabel: 'Deactivate',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    final session = authSession;
    if (session == null) return;
    await _run(() async {
      try {
        final repos = ensureLiveRepositories(session.api);
        await repos.users.deactivateUser(
          user.id,
          reason: reason.trim().isEmpty ? null : reason.trim(),
        );
        repos.invalidateAfterResidentMutation();
        if (!mounted) return;
        showAppSnack(context, 'Resident deactivated.', tone: SnackTone.warning);
        setState(() => _future = _load(force: true));
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, adminApiErrorMessage(e));
      }
    });
  }

  Future<void> _resetPassword(AdminUser user) async {
    final ok = await confirmDialog(
      context,
      title: 'Reset password for ${user.name}?',
      message:
          'A temporary password will be generated once. All active sessions for this account will be revoked. Share the password out-of-band; it is never logged.',
      confirmLabel: 'Reset password',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final session = authSession;
    if (session == null) return;
    await _run(() async {
      try {
        final repos = ensureLiveRepositories(session.api);
        final result = await repos.users.setPassword(user.id);
        repos.invalidateAfterResidentMutation();
        if (!mounted) return;
        await showIssuedCredentialsDialog(
          context,
          recipientName: result.user.name,
          username: result.user.username ?? user.username ?? '',
          temporaryPassword: result.temporaryPassword,
          kind: IssuedCredentialsKind.reset,
        );
        if (!mounted) return;
        setState(() => _future = _load(force: true));
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, adminApiErrorMessage(e));
      }
    });
  }

  Future<void> _setMobile(AdminUser user) async {
    final entered = await promptTextDialog(
      context,
      title: user.mobileE164 == null
          ? 'Set mobile number'
          : 'Update mobile number',
      message:
          'Optional contact number. Login uses username and password.',
      label: 'Mobile number',
      hint: '+91 98765 43210 or 10 digits',
      initialValue: user.mobileE164 == null ? null : '+${user.mobileE164}',
      confirmLabel: 'Save',
      required: true,
      keyboardType: TextInputType.phone,
    );
    if (entered == null || entered.trim().isEmpty || !mounted) return;
    final session = authSession;
    if (session == null) return;
    await _run(() async {
      try {
        final repos = ensureLiveRepositories(session.api);
        await repos.users.setMobile(user.id, mobile: entered.trim());
        repos.invalidateAfterResidentMutation();
        if (!mounted) return;
        showSuccessSnack(context,
            'Mobile saved. Confirm ownership before the resident can log in.');
        setState(() => _future = _load(force: true));
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, adminApiErrorMessage(e));
      }
    });
  }

  Future<void> _confirmMobile(AdminUser user) async {
    final ok = await confirmDialog(
      context,
      title: 'Confirm mobile ownership',
      message: 'Confirm that +${user.mobileE164} belongs to ${user.name} '
          '(verified in person or by another trusted channel). '
          'This enables SMS OTP login for this account.',
      confirmLabel: 'Confirm',
      icon: Icons.verified_outlined,
    );
    if (!ok || !mounted) return;
    final session = authSession;
    if (session == null) return;
    await _run(() async {
      try {
        final repos = ensureLiveRepositories(session.api);
        await repos.users.confirmMobile(user.id);
        repos.invalidateAfterResidentMutation();
        if (!mounted) return;
        showSuccessSnack(
            context, 'Mobile verified. SMS OTP login is now allowed.');
        setState(() => _future = _load(force: true));
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, adminApiErrorMessage(e));
      }
    });
  }

  Future<void> _addVehicle(AdminUser user) async {
    final occupancies = user.activeOccupancies;
    if (occupancies.isEmpty) {
      showAppSnack(
        context,
        'Assign this resident to a flat before adding a vehicle.',
        tone: SnackTone.warning,
      );
      return;
    }
    String? flatId = occupancies.first.flatId;
    if (occupancies.length > 1) {
      flatId = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Which flat?'),
          children: [
            for (final occupancy in occupancies)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, occupancy.flatId),
                child: Text(
                  '${_roleLabel(occupancy.role)} occupancy',
                ),
              ),
          ],
        ),
      );
    }
    if (flatId == null || !mounted) return;
    final selectedFlatId = flatId;
    final payload = await showDialog<VehicleDraftPayload>(
      context: context,
      builder: (ctx) => const _VehicleEditorDialog(),
    );
    if (payload == null || !mounted) return;
    final session = authSession;
    if (session == null) return;
    await _run(() async {
      try {
        final repos = ensureLiveRepositories(session.api);
        await repos.vehicles.adminRegister(
          AdminRegisterVehicleRequest(
            flatId: selectedFlatId,
            registeredUserId: user.id,
            vehicleType: payload.vehicleType,
            registrationNumber: payload.registrationNumber,
            make: payload.make,
            model: payload.model,
          ),
        );
        repos.invalidateAfterResidentMutation(flatId: selectedFlatId);
        if (!mounted) return;
        showSuccessSnack(context, 'Vehicle registered.');
        setState(() => _future = _load(force: true));
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, vehicleErrorMessage(e));
      }
    });
  }

  Future<void> _editVehicle(Vehicle vehicle) async {
    final payload = await showDialog<VehicleDraftPayload>(
      context: context,
      builder: (ctx) => _VehicleEditorDialog(existing: vehicle),
    );
    if (payload == null || !mounted) return;
    final session = authSession;
    if (session == null) return;
    await _run(() async {
      try {
        final repos = ensureLiveRepositories(session.api);
        await repos.vehicles.adminUpdate(
          vehicle.id,
          vehicleType: payload.vehicleType,
          registrationNumber: payload.registrationNumber,
          make: payload.make,
          model: payload.model,
        );
        repos.invalidateAfterResidentMutation(flatId: vehicle.flatId);
        if (!mounted) return;
        showSuccessSnack(context, 'Vehicle updated.');
        setState(() => _future = _load(force: true));
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, vehicleErrorMessage(e));
      }
    });
  }

  Future<void> _deactivateVehicle(Vehicle vehicle) async {
    final reason = await promptTextDialog(
      context,
      title: 'Deactivate ${vehicle.registrationNumber}?',
      message: 'The vehicle stays on record but is no longer active.',
      label: 'Reason (optional)',
      confirmLabel: 'Deactivate',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    final session = authSession;
    if (session == null) return;
    await _run(() async {
      try {
        final repos = ensureLiveRepositories(session.api);
        await repos.vehicles.adminDeactivate(
          vehicle.id,
          reason: reason.trim().isEmpty ? null : reason.trim(),
        );
        repos.invalidateAfterResidentMutation(flatId: vehicle.flatId);
        if (!mounted) return;
        showAppSnack(context, 'Vehicle deactivated.', tone: SnackTone.warning);
        setState(() => _future = _load(force: true));
      } catch (e) {
        if (!mounted) return;
        showErrorSnack(context, vehicleErrorMessage(e));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resident details')),
      body: FutureBuilder<_ResidentDetailBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const LoadingView(label: 'Loading resident…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              title: 'Could not load resident',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final user = snap.data!.user;
          final vehicles = snap.data!.vehicles;
          final roles =
              user.societyRoles.isEmpty ? user.roles : user.societyRoles;
          final canDeactivate = user.isActive &&
              !user.roles.contains('ADMIN') &&
              !user.roles.contains('GUARD');
          final needsMobile = user.mobileE164 == null;
          final needsConfirm =
              user.mobileE164 != null && !user.mobileVerified;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                DetailHero(
                  title: user.name.isEmpty ? user.email : user.name,
                  subtitle: user.email,
                  leading: AppAvatar(
                    text: initialsOf(user.name.isEmpty ? user.email : user.name),
                    size: Sz.avatarLg,
                    color: user.isActive ? C.blue : C.muted,
                  ),
                  badges: [
                    for (final r in roles)
                      StatusBadge(_roleLabel(r), tone: BadgeTone.info),
                    StatusBadge(user.isActive ? 'Active' : 'Inactive'),
                    StatusBadge(
                      user.canLogin ? 'Can log in' : 'Cannot log in',
                      tone: user.canLogin
                          ? BadgeTone.success
                          : BadgeTone.warning,
                      icon: user.canLogin
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if ((user.username ?? '').isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: InfoNote(
                      'No username yet. Assign one, then reset the password so this resident can sign in.',
                      tone: NoteTone.warning,
                    ),
                  )
                else if (!user.hasPassword)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: InfoNote(
                      'Username is set but no password yet. Use Reset password to issue a temporary credential.',
                      tone: NoteTone.warning,
                    ),
                  ),
                DetailCard(title: 'Contact', children: [
                  DetailRow('Username', user.username ?? 'Not set'),
                  DetailRow(
                    'Mobile',
                    user.mobileE164 == null ? '—' : '+${user.mobileE164}',
                    valueWidget: user.mobileE164 == null
                        ? Text(
                            (user.phone ?? '').trim().isEmpty
                                ? 'Not set'
                                : user.phone!,
                            style: T.bodyStrong)
                        : Row(children: [
                            Flexible(
                              child: Text('+${user.mobileE164}',
                                  style: T.bodyStrong,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            StatusBadge(user.mobileVerified
                                ? 'Verified'
                                : 'Unverified'),
                          ]),
                  ),
                  if (user.mobileE164 != null &&
                      (user.phone ?? '').isNotEmpty &&
                      user.phone != '+${user.mobileE164}')
                    DetailRow('Phone', user.phone!),
                  DetailRow('Email', user.email),
                ]),
                DetailCard(title: 'Account', children: [
                  DetailRow('Roles', roles.map(_roleLabel).join(', ')),
                  DetailRow(
                    'Password',
                    user.hasPassword
                        ? (user.mustChangePassword
                            ? 'Temporary (must change)'
                            : 'Set')
                        : 'Not set',
                  ),
                  DetailRow('Last login', fmtIsoDateTime(user.lastLoginAt)),
                  DetailRow('Created', fmtIsoDate(user.createdAt)),
                ]),
                const SizedBox(height: 8),
                const SectionTitle('Active flat occupancy',
                    subtitle: 'Assign flats from Flat details'),
                if (user.activeOccupancies.isEmpty)
                  const EmptyState(
                    'Not assigned to any flat yet',
                    icon: Icons.apartment_outlined,
                    compact: true,
                  )
                else
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < user.activeOccupancies.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 56, endIndent: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(children: [
                            AppAvatar(
                              icon: user.activeOccupancies[i].role == 'OWNER'
                                  ? Icons.home_outlined
                                  : Icons.person_pin_circle_outlined,
                              square: true,
                              size: 36,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_roleLabel(user.activeOccupancies[i].role)} occupancy',
                                    style: T.bodyStrong,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Since ${occupancyDateLabel(user.activeOccupancies[i].startsAt)}',
                                    style: T.caption,
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(
                              _roleLabel(user.activeOccupancies[i].role),
                              tone: BadgeTone.info,
                            ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                const SizedBox(height: 20),
                SectionTitle(
                  'Registered vehicles',
                  subtitle: user.activeOccupancies.isEmpty
                      ? 'Assign a flat before adding vehicles'
                      : 'Linked to this resident, their assigned flat, and the society',
                  action: user.activeOccupancies.isEmpty
                      ? null
                      : TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _addVehicle(user),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                ),
                if (vehicles.isEmpty)
                  const EmptyState(
                    'No vehicles registered',
                    icon: Icons.directions_car_outlined,
                    compact: true,
                  )
                else
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < vehicles.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 56, endIndent: 12),
                        _ResidentVehicleRow(
                          vehicle: vehicles[i],
                          busy: _busy,
                          onEdit: vehicles[i].isActive
                              ? () => _editVehicle(vehicles[i])
                              : null,
                          onDeactivate: vehicles[i].isActive
                              ? () => _deactivateVehicle(vehicles[i])
                              : null,
                        ),
                      ],
                    ]),
                  ),
                const SizedBox(height: 20),
                const SectionTitle('Manage access'),
                ActionRail(
                  busy: _busy,
                  primary: (user.username ?? '').isNotEmpty
                      ? ToolLink(
                          icon: Icons.password_rounded,
                          label: user.hasPassword
                              ? 'Reset password'
                              : 'Issue temporary password',
                          subtitle:
                              'Shows a one-time credential; sessions are revoked',
                          onTap: () => _resetPassword(user),
                        )
                      : needsMobile
                          ? ToolLink(
                              icon: Icons.phone_android_outlined,
                              label: 'Set mobile number',
                              subtitle: 'Optional contact number',
                              onTap: () => _setMobile(user),
                            )
                          : needsConfirm
                              ? ToolLink(
                                  icon: Icons.verified_outlined,
                                  label: 'Confirm mobile ownership',
                                  subtitle: 'Marks +${user.mobileE164} verified',
                                  onTap: () => _confirmMobile(user),
                                )
                              : null,
                  secondary: [
                    if (!needsMobile)
                      ToolLink(
                        icon: Icons.phone_android_outlined,
                        label: 'Update mobile number',
                        subtitle: 'Optional contact number',
                        onTap: () => _setMobile(user),
                      ),
                    if (canDeactivate)
                      ToolLink(
                        icon: Icons.person_off_outlined,
                        label: 'Deactivate resident',
                        subtitle: 'Blocks sign-in for this account',
                        onTap: () => _deactivate(user),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pick an OWNER or TENANT for flat assignment.
class AdminPickResidentPage extends StatefulWidget {
  const AdminPickResidentPage({super.key, required this.role});
  final String role;

  @override
  State<AdminPickResidentPage> createState() => _AdminPickResidentPageState();
}

class _AdminPickResidentPageState extends State<AdminPickResidentPage> {
  String query = '';
  int page = 1;
  late Future<_ResidentsBundle> _future = _load();
  final _debounce = Debouncer();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _debounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_ResidentsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final result = await ensureLiveRepositories(session.api).users.listUsers(
          force: force,
          query: ListUsersQuery(
            role: widget.role,
            search: query.trim().isEmpty ? null : query.trim(),
            isActive: true,
            page: page,
            limit: 30,
          ),
        );
    return _ResidentsBundle(page: result);
  }

  Future<void> _provisionNew() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminProvisionResidentPage(initialRole: widget.role),
      ),
    );
    if (created == true && mounted) {
      setState(() => _future = _load(force: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = widget.role == 'OWNER' ? 'owner' : 'tenant';
    return Scaffold(
      appBar: AppBar(
        title: Text('Select $roleLabel'),
        actions: [
          TextButton.icon(
            onPressed: _provisionNew,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('New'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: SearchField(
              controller: _searchCtrl,
              hint: 'Search active ${roleLabel}s',
              autofocus: true,
              onChanged: (v) {
                query = v;
                _debounce.run(() {
                  page = 1;
                  setState(() => _future = _load(force: true));
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<_ResidentsBundle>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const SkeletonList(items: 6);
                }
                if (snap.hasError) {
                  return LoadFailure(
                    error: snap.error!,
                    onRetry: () => setState(() => _future = _load(force: true)),
                  );
                }
                final paged = snap.data!.page;
                final rows = paged.items;
                if (rows.isEmpty) {
                  return EmptyState(
                    'No matching active ${roleLabel}s',
                    icon: Icons.person_search_outlined,
                    actionLabel: 'Add new $roleLabel',
                    onAction: _provisionNew,
                  );
                }
                return ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length + 1,
                  itemBuilder: (context, i) {
                    if (i == rows.length) {
                      return PaginationBar(
                        page: paged.pagination.page,
                        totalPages: paged.pagination.totalPages,
                        onPrevious: () {
                          page -= 1;
                          setState(() => _future = _load(force: true));
                        },
                        onNext: () {
                          page += 1;
                          setState(() => _future = _load(force: true));
                        },
                      );
                    }
                    final user = rows[i];
                    return _ResidentRow(
                      user: user,
                      onTap: () => Navigator.pop(context, user),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResidentVehicleRow extends StatelessWidget {
  const _ResidentVehicleRow({
    required this.vehicle,
    required this.busy,
    this.onEdit,
    this.onDeactivate,
  });

  final Vehicle vehicle;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            icon: vehicle.vehicleType == 'TWO_WHEELER'
                ? Icons.two_wheeler_outlined
                : Icons.directions_car_outlined,
            square: true,
            size: 36,
            color: vehicle.isActive ? C.blue : C.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicle.registrationNumber, style: T.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  '${vehicleTypeLabel(vehicle.vehicleType)} · ${vehicle.makeModelLabel}',
                  style: T.caption,
                ),
                Text('Flat ${vehicle.flatLabel}', style: T.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(vehicle.isActive ? 'Active' : 'Inactive'),
              if (onEdit != null || onDeactivate != null)
                PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'deactivate') onDeactivate?.call();
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit details'),
                      ),
                    if (onDeactivate != null)
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Text('Deactivate'),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VehicleEditorDialog extends StatefulWidget {
  const _VehicleEditorDialog({this.existing});
  final Vehicle? existing;

  @override
  State<_VehicleEditorDialog> createState() => _VehicleEditorDialogState();
}

class _VehicleEditorDialogState extends State<_VehicleEditorDialog> {
  late final draft = VehicleDraftControllers(
    vehicleType: widget.existing?.vehicleType == 'TWO_WHEELER'
        ? 'TWO_WHEELER'
        : 'FOUR_WHEELER',
    registration: widget.existing?.registrationNumber ?? '',
    make: widget.existing?.make ?? '',
    model: widget.existing?.model ?? '',
  );

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validateVehicleDrafts([draft]);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final payload = draft.toPayloadOrNull();
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a vehicle registration number.')),
      );
      return;
    }
    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add vehicle' : 'Edit vehicle'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: draft.vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Vehicle type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final type in kAdminSelectableVehicleTypes)
                    DropdownMenuItem(
                      value: type,
                      child: Text(vehicleTypeLabel(type)),
                    ),
                ],
                onChanged: (value) => setState(
                  () => draft.vehicleType = value ?? 'FOUR_WHEELER',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: draft.registration,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Registration number',
                  helperText: 'Example: MH12AB1234',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: draft.make,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Make',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: draft.model,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

/// Confirm occupancy assignment with optional vehicle details.
class AssignOccupancyPage extends StatefulWidget {
  const AssignOccupancyPage({
    super.key,
    required this.role,
    required this.user,
    required this.flatId,
  });

  final String role;
  final AdminUser user;
  final String flatId;

  @override
  State<AssignOccupancyPage> createState() => _AssignOccupancyPageState();
}

class _AssignOccupancyPageState extends State<AssignOccupancyPage> {
  final notes = TextEditingController();
  final vehicleDrafts = <VehicleDraftControllers>[];
  bool saving = false;
  String? formError;

  String get _roleLabel => widget.role == 'OWNER' ? 'owner' : 'tenant';

  @override
  void dispose() {
    notes.dispose();
    for (final draft in vehicleDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final vehicleError = validateVehicleDrafts(vehicleDrafts);
    if (vehicleError != null) {
      setState(() => formError = vehicleError);
      return;
    }
    final session = authSession;
    if (session == null) {
      setState(() => formError = 'Not signed in.');
      return;
    }
    setState(() {
      saving = true;
      formError = null;
    });
    try {
      final repos = ensureLiveRepositories(session.api);
      final payloads = vehicleDraftPayloads(vehicleDrafts);
      final trimmed = notes.text.trim();
      if (widget.role == 'OWNER') {
        await repos.society.assignOwner(
          widget.flatId,
          userId: widget.user.id,
          effectiveFrom: DateTime.now(),
          notes: trimmed.isEmpty ? null : trimmed,
          vehicles: payloads,
        );
      } else {
        await repos.society.assignTenant(
          widget.flatId,
          userId: widget.user.id,
          effectiveFrom: DateTime.now(),
          notes: trimmed.isEmpty ? null : trimmed,
          vehicles: payloads,
        );
      }
      repos.invalidateAfterResidentMutation(flatId: widget.flatId);
      if (!mounted) return;
      showSuccessSnack(context, '${_roleLabel[0].toUpperCase()}${_roleLabel.substring(1)} assigned.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => formError = vehicleErrorMessage(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: 'Assign $_roleLabel',
      bottom: PrimaryButton(
        label: 'Assign $_roleLabel',
        icon: Icons.person_pin_circle_outlined,
        busy: saving,
        onPressed: saving ? null : _save,
      ),
      children: [
        InfoNote(
          '${widget.user.name} will be assigned from today. Vehicle details are optional.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: notes,
          enabled: !saving,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        VehicleDraftsEditor(
          drafts: vehicleDrafts,
          enabled: !saving,
          onChanged: () => setState(() {}),
        ),
        InlineError(formError),
      ],
    );
  }
}

String occupancyDateLabel(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  return fmtDate(dt);
}
