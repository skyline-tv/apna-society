import 'package:flutter/material.dart';

import '../../api/auth/admin_api_messages.dart';
import '../../api/auth/auth_session.dart';
import '../../api/models/admin_user_models.dart';
import '../../api/models/common.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

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

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    username.dispose();
    super.dispose();
  }

  String get _roleLabel => role == 'OWNER' ? 'Owner' : 'Tenant';

  Future<void> _continue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => formError = null);
    if (!_formKey.currentState!.validate()) return;
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
      );
      repos.invalidateAfterResidentMutation();
      if (!mounted) return;
      final temp = result.temporaryPassword;
      if (temp != null && temp.isNotEmpty) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Credentials issued'),
            content: Text(
              'Username: ${result.user.username ?? username.text.trim()}\n'
              'Temporary password: $temp\n\n'
              'Share this out-of-band. The user must change it on first login. '
              'It will not be shown again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('I saved it'),
              ),
            ],
          ),
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
          onSelectionChanged:
              saving ? null : (s) => setState(() => role = s.first),
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
        const SizedBox(height: 16),
        const InfoNote(
          'A temporary password is generated securely. Share it out-of-band; the resident must change it on first login. If this email already exists, the server reuses that account.',
        ),
        InlineError(formError),
      ];

  List<Widget> _reviewBody() => [
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
          ],
          note:
              'After creation, assign this person to a flat from Flat details. A temporary password will be shown once for you to share securely.',
        ),
        InlineError(formError),
      ];
}

class AdminResidentDetailPage extends StatefulWidget {
  const AdminResidentDetailPage({super.key, required this.userId});
  final String userId;

  @override
  State<AdminResidentDetailPage> createState() =>
      _AdminResidentDetailPageState();
}

class _AdminResidentDetailPageState extends State<AdminResidentDetailPage> {
  late Future<AdminUser> _future = _load();
  bool _busy = false;

  Future<AdminUser> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .users
        .getUser(widget.userId, force: force);
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
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Temporary password'),
            content: Text(
              'Username: ${result.user.username ?? user.username}\n'
              'Temporary password: ${result.temporaryPassword}\n\n'
              'Share this securely. The user must change it on next login.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('I saved it'),
              ),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resident details')),
      body: FutureBuilder<AdminUser>(
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
          final user = snap.data!;
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

String occupancyDateLabel(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  return fmtDate(dt);
}
