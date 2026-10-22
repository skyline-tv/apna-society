import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/admin_api_messages.dart';
import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/admin_guard_models.dart';
import '../../api/models/common.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart' show Debouncer;
import '../../ui/components.dart';
import '../../ui/issued_credentials_dialog.dart';
import '../../ui/load_failure.dart';

String guardErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'DUPLICATE_EMAIL':
        return 'A user with this email already exists.';
      case 'DUPLICATE_USERNAME':
        return 'A user with this username already exists.';
      case 'DUPLICATE_GUARD':
        return 'This person already has an active guard login in this society.';
      case 'PROTECTED_ROLE':
        return 'Admin accounts cannot be converted into guards.';
      case 'NOT_A_GUARD':
        return 'That account is not a security guard.';
      case 'SELF_DEACTIVATE':
        return 'You cannot deactivate your own account from here.';
      case 'USERNAME_MISMATCH':
        return 'This email is already registered with a different username.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this action.';
      default:
        return adminApiErrorMessage(error);
    }
  }
  if (error is StateError) return error.message;
  return '$error';
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

class _GuardRow extends StatelessWidget {
  const _GuardRow({required this.guard, required this.onTap});
  final AdminGuard guard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final phone = (guard.phone ?? '').trim();
    return ListRow(
      onTap: onTap,
      leading: AppAvatar(
        text: initialsOf(guard.name),
        color: guard.membershipActive ? C.blue : C.muted,
      ),
      title: guard.name,
      subtitle: [
        if (phone.isNotEmpty) phone,
        guard.username ?? guard.email,
      ].join(' · '),
      badges: [
        StatusBadge(
          guard.membershipActive ? 'On duty' : 'Deactivated',
          tone: guard.membershipActive ? BadgeTone.success : BadgeTone.warning,
        ),
        if (guard.membershipActive)
          StatusBadge(
            guard.canLogin ? 'Can log in' : 'Login off',
            tone: guard.canLogin ? BadgeTone.info : BadgeTone.neutral,
          ),
      ],
    );
  }
}

/// Admin list of society security guards (live `/admin/guards`).
class LiveAdminGuardsPage extends StatefulWidget {
  const LiveAdminGuardsPage({super.key});

  @override
  State<LiveAdminGuardsPage> createState() => _LiveAdminGuardsPageState();
}

class _LiveAdminGuardsPageState extends State<LiveAdminGuardsPage> {
  String query = '';
  String statusFilter = 'active';
  int page = 1;
  static const _limit = 20;
  late Future<Paged<AdminGuard>> _future = _load();
  final _searchDebounce = Debouncer();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool? get _isActiveFilter {
    if (statusFilter == 'active') return true;
    if (statusFilter == 'inactive') return false;
    return null;
  }

  Future<Paged<AdminGuard>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).guards.listGuards(
          force: force,
          query: ListGuardsQuery(
            search: query.trim().isEmpty ? null : query.trim(),
            isActive: _isActiveFilter,
            page: page,
            limit: _limit,
          ),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  Future<void> _add() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveAdminGuardFormPage()),
    );
    if (ok == true && mounted) {
      page = 1;
      reload();
    }
  }

  Future<void> _open(AdminGuard guard) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAdminGuardDetailPage(guardId: guard.id),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-guard',
        onPressed: _add,
        icon: const Icon(Icons.shield_outlined),
        label: const Text('Add guard'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SearchField(
              controller: _searchCtrl,
              hint: 'Search by name, email or phone',
              onChanged: (v) {
                query = v;
                _searchDebounce.run(() {
                  page = 1;
                  reload();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: FilterBar(
              padding: EdgeInsets.zero,
              children: [
                for (final entry in const [
                  ('active', 'Active'),
                  ('inactive', 'Deactivated'),
                  ('all', 'All'),
                ])
                  AppFilterChip(
                    label: entry.$2,
                    selected: statusFilter == entry.$1,
                    onSelected: () {
                      statusFilter = entry.$1;
                      page = 1;
                      reload();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Paged<AdminGuard>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const SkeletonList(items: 6, showHeader: true);
                }
                if (snapshot.hasError) {
                  return LoadFailure(
                    error: snapshot.error!,
                    title: 'Could not load security guards',
                    onRetry: reload,
                  );
                }
                final paged = snapshot.data!;
                final items = paged.items;
                if (items.isEmpty) {
                  return _emptyScrollable(
                    EmptyState(
                      query.isNotEmpty || statusFilter != 'active'
                          ? 'No guards match these filters'
                          : 'No security guards yet',
                      icon: Icons.shield_outlined,
                      actionLabel: query.isNotEmpty || statusFilter != 'active'
                          ? 'Show active'
                          : 'Add guard',
                      onAction: query.isNotEmpty || statusFilter != 'active'
                          ? () {
                              _searchCtrl.clear();
                              query = '';
                              statusFilter = 'active';
                              page = 1;
                              reload();
                            }
                          : _add,
                    ),
                    _refresh,
                  );
                }
                return RefreshIndicator(
                  color: C.blue,
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                    children: [
                      const PageHeader(
                        'Security guards',
                        subtitle:
                            'Gate login accounts for this society. Attendance and shifts stay off this screen.',
                      ),
                      ResultCount(paged.pagination.total, 'guard'),
                      for (final g in items)
                        _GuardRow(guard: g, onTap: () => _open(g)),
                      PaginationBar(
                        page: paged.pagination.page,
                        totalPages: paged.pagination.totalPages,
                        onPrevious: () {
                          page = paged.pagination.page - 1;
                          reload();
                        },
                        onNext: () {
                          page = paged.pagination.page + 1;
                          reload();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LiveAdminGuardDetailPage extends StatefulWidget {
  const LiveAdminGuardDetailPage({super.key, required this.guardId});
  final String guardId;

  @override
  State<LiveAdminGuardDetailPage> createState() =>
      _LiveAdminGuardDetailPageState();
}

class _LiveAdminGuardDetailPageState extends State<LiveAdminGuardDetailPage> {
  late Future<AdminGuard> _future = _load();
  bool _busy = false;

  Future<AdminGuard> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .guards
        .getGuard(widget.guardId, force: force);
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        if (success != null) showSuccessSnack(context, success);
        setState(() => _future = _load(force: true));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, guardErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(AdminGuard g) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LiveAdminGuardFormPage(existing: g)),
    );
    if (ok == true && mounted) {
      showSuccessSnack(context, 'Guard details updated.');
      setState(() => _future = _load(force: true));
    }
  }

  Future<void> _toggleLogin(AdminGuard g) async {
    final enable = !g.canLogin;
    final ok = await confirmDialog(
      context,
      title: enable ? 'Allow login?' : 'Turn off login?',
      message: enable
          ? '${g.name} will be able to sign in as a security guard.'
          : '${g.name} will stay assigned to the society but cannot sign in.',
      confirmLabel: enable ? 'Allow login' : 'Turn off login',
      destructive: !enable,
    );
    if (!ok) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).guards.updateGuard(
            g.id,
            UpdateGuardRequest(canLogin: enable),
          );
    }, success: enable ? 'Login enabled.' : 'Login turned off.');
  }

  Future<void> _deactivate(AdminGuard g) async {
    final reason = await promptTextDialog(
      context,
      title: 'Deactivate ${g.name}?',
      message:
          'Ends this guard assignment in the society. The current API has no reactivate action, so a new assignment would be required later.',
      label: 'Reason (optional)',
      confirmLabel: 'Deactivate',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null) return;
    await _run(() async {
      final session = authSession!;
      await ensureLiveRepositories(session.api).guards.deactivateGuard(
            g.id,
            reason: reason.trim().length < 3 ? null : reason.trim(),
          );
    }, success: 'Guard deactivated.');
  }

  Future<void> _resetPassword(AdminGuard g) async {
    if ((g.username ?? '').isEmpty) {
      showErrorSnack(
        context,
        'This guard has no username yet. Username is set when the account is created.',
      );
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Reset password for ${g.name}?',
      message:
          'A temporary password will be generated once. Active sessions are revoked. Share it out-of-band; it is never logged.',
      confirmLabel: 'Reset password',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final session = authSession!;
      final repos = ensureLiveRepositories(session.api);
      final result = await repos.users.setPassword(g.id);
      repos.guards.invalidate(guardId: g.id);
      if (!mounted) return;
      await showIssuedCredentialsDialog(
        context,
        recipientName: result.user.name.isEmpty ? g.name : result.user.name,
        username: result.user.username ?? g.username ?? '',
        temporaryPassword: result.temporaryPassword,
        kind: IssuedCredentialsKind.reset,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security guard'),
        actions: [
          FutureBuilder<AdminGuard>(
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
      body: FutureBuilder<AdminGuard>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading guard…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              title: 'Could not load guard',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final g = snapshot.data!;
          final phone = (g.phone ?? '').trim();
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
                  title: g.name,
                  subtitle: g.email,
                  leading: AppAvatar(
                    text: initialsOf(g.name),
                    size: Sz.avatarLg,
                    color: g.membershipActive ? C.blue : C.muted,
                  ),
                  badges: [
                    const StatusBadge('Guard', tone: BadgeTone.info),
                    StatusBadge(
                      g.membershipActive ? 'Assigned' : 'Deactivated',
                      tone: g.membershipActive
                          ? BadgeTone.success
                          : BadgeTone.warning,
                    ),
                    StatusBadge(
                      g.canLogin ? 'Can log in' : 'Cannot log in',
                      tone: g.canLogin ? BadgeTone.success : BadgeTone.warning,
                      icon: g.canLogin
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!g.membershipActive)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: InfoNote(
                      'This guard assignment has ended. The live API does not offer a reactivate action, so create a new assignment if they should return.',
                      tone: NoteTone.warning,
                    ),
                  ),
                DetailCard(title: 'Login', children: [
                  DetailRow('Username', g.username ?? 'Not set'),
                  DetailRow('Email', g.email),
                  if (g.mustChangePassword)
                    const DetailRow('Password', 'Must change on next login'),
                ]),
                DetailCard(title: 'Contact', children: [
                  DetailRow(
                    'Mobile',
                    phone.isEmpty ? '—' : phone,
                    valueWidget: phone.isEmpty
                        ? null
                        : Row(children: [
                            Expanded(child: Text(phone, style: T.bodyStrong)),
                            IconButton(
                              tooltip: 'Copy',
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: phone));
                                if (context.mounted) {
                                  showInfoSnack(
                                      context, 'Phone number copied.');
                                }
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                            ),
                          ]),
                  ),
                ]),
                DetailCard(title: 'Society assignment', children: [
                  const DetailRow('Role', 'Security guard'),
                  DetailRow(
                    'Membership',
                    g.membershipActive ? 'Active in this society' : 'Ended',
                  ),
                  if (g.membershipStartsAt != null)
                    DetailRow('Started', fmtIsoDateTime(g.membershipStartsAt)),
                  if (g.membershipEndsAt != null)
                    DetailRow('Ended', fmtIsoDateTime(g.membershipEndsAt)),
                  if (g.lastLoginAt != null)
                    DetailRow('Last login', fmtIsoDateTime(g.lastLoginAt)),
                ]),
                const SizedBox(height: 8),
                const SectionTitle('Manage'),
                ActionRail(
                  busy: _busy,
                  primary: ToolLink(
                    icon: Icons.edit_outlined,
                    label: 'Edit details',
                    subtitle: 'Name and mobile number',
                    onTap: () => _edit(g),
                  ),
                  secondary: [
                    if ((g.username ?? '').isNotEmpty)
                      ToolLink(
                        icon: Icons.password_rounded,
                        label: 'Reset password',
                        subtitle: 'Issues a one-time temporary password',
                        onTap: () => _resetPassword(g),
                      ),
                    if (g.membershipActive)
                      ToolLink(
                        icon: g.canLogin
                            ? Icons.lock_outline_rounded
                            : Icons.lock_open_rounded,
                        label: g.canLogin ? 'Turn off login' : 'Allow login',
                        subtitle: g.canLogin
                            ? 'Keep the assignment, block sign-in'
                            : 'Let this guard sign in again',
                        onTap: () => _toggleLogin(g),
                      ),
                    if (g.membershipActive)
                      ToolLink(
                        icon: Icons.person_off_outlined,
                        label: 'Deactivate guard',
                        subtitle: 'End the society assignment',
                        onTap: () => _deactivate(g),
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

class LiveAdminGuardFormPage extends StatefulWidget {
  const LiveAdminGuardFormPage({super.key, this.existing});
  final AdminGuard? existing;

  @override
  State<LiveAdminGuardFormPage> createState() => _LiveAdminGuardFormPageState();
}

class _LiveAdminGuardFormPageState extends State<LiveAdminGuardFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name);
  late final email = TextEditingController(text: widget.existing?.email);
  late final phone = TextEditingController(text: widget.existing?.phone);
  late final username = TextEditingController(text: widget.existing?.username);
  bool saving = false;
  bool reviewing = false;
  String? formError;

  bool get editing => widget.existing != null;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    username.dispose();
    super.dispose();
  }

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
      if (editing) {
        await repos.guards.updateGuard(
          widget.existing!.id,
          UpdateGuardRequest(
            name: name.text.trim(),
            phone: phone.text.trim(),
          ),
        );
        if (!mounted) return;
        showSuccessSnack(context, 'Guard details saved.');
        Navigator.pop(context, true);
        return;
      }
      final result = await repos.guards.provision(
        CreateGuardRequest(
          name: name.text.trim(),
          email: email.text.trim(),
          phone: phone.text.trim(),
          username: username.text.trim(),
        ),
      );
      if (!mounted) return;
      final temp = result.temporaryPassword;
      if (temp != null && temp.isNotEmpty) {
        await showIssuedCredentialsDialog(
          context,
          recipientName: result.guard.name,
          username: result.guard.username ?? username.text.trim(),
          temporaryPassword: temp,
        );
      }
      if (!mounted) return;
      showSuccessSnack(
        context,
        result.reusedExisting
            ? 'Existing account linked as a security guard.'
            : 'Security guard created.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        formError = guardErrorMessage(e);
        reviewing = false;
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: reviewing
          ? (editing ? 'Confirm changes' : 'Confirm guard')
          : (editing ? 'Edit guard' : 'Add security guard'),
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
            ? (editing ? 'Save changes' : 'Create guard account')
            : 'Review & continue',
        icon: reviewing ? Icons.shield_outlined : Icons.arrow_forward_rounded,
        busy: saving,
        onPressed: reviewing ? save : _continue,
      ),
      children: reviewing ? _reviewBody() : _formBody(),
    );
  }

  List<Widget> _formBody() => [
        const FormSectionLabel('Identity'),
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
          controller: phone,
          enabled: !saving,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Mobile number *',
            hintText: '+91 98765 43210',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Mobile number is required.';
            if (t.length < 7) return 'Enter a valid mobile number.';
            return null;
          },
        ),
        if (!editing) ...[
          const SizedBox(height: 20),
          const FormSectionLabel('Login'),
          TextFormField(
            controller: email,
            enabled: !saving,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email *',
              helperText: 'Required by the existing account API.',
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
            textInputAction: TextInputAction.done,
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
          const SizedBox(height: 16),
          const InfoNote(
            'This guard is assigned to the current society. A temporary password is generated securely and shown once. They must change it on first login.',
          ),
        ] else ...[
          const SizedBox(height: 16),
          const InfoNote(
            'Email and username are set at creation and cannot be changed from this form.',
          ),
        ],
        InlineError(formError),
      ];

  List<Widget> _reviewBody() => [
        ReviewSummary(
          title: editing ? 'About to update' : 'About to create',
          rows: [
            ('Name', name.text.trim()),
            ('Mobile', phone.text.trim()),
            if (!editing) ('Email', email.text.trim()),
            if (!editing) ('Username', username.text.trim()),
            ('Society', 'Current society assignment'),
            if (!editing) ('Role', 'Security guard'),
          ],
          note: editing
              ? 'Only name and mobile are sent to the existing update API.'
              : 'A temporary password will be shown once for you to share securely.',
        ),
        InlineError(formError),
      ];
}
