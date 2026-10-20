import 'package:flutter/material.dart';

import '../../api/auth/admin_api_messages.dart';
import '../../api/auth/auth_session.dart';
import '../../api/models/admin_user_models.dart';
import '../../api/models/common.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

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

  @override
  void dispose() {
    _tabs.dispose();
    _searchDebounce.dispose();
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
      _ownersFuture =
          _load(role: 'OWNER', page: ownersPage, force: true);
      _tenantsFuture =
          _load(role: 'TENANT', page: tenantsPage, force: true);
    });
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) {
                    query = v;
                    _searchDebounce.run(() {
                      ownersPage = 1;
                      tenantsPage = 1;
                      reload();
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search name, email or phone',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: 'Provision resident',
                onSelected: _openProvision,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'OWNER', child: Text('Provision owner')),
                  PopupMenuItem(value: 'TENANT', child: Text('Provision tenant')),
                ],
                icon: const Icon(Icons.person_add_alt_1, color: C.blue),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
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
                      ownersPage = 1;
                      tenantsPage = 1;
                      reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: C.blue,
          unselectedLabelColor: C.muted,
          indicatorColor: C.blue,
          tabs: const [
            Tab(text: 'Owners'),
            Tab(text: 'Tenants'),
          ],
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
          return const LoadingView(label: 'Loading residents…');
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
        if (rows.isEmpty) return EmptyState(emptyLabel);
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == rows.length) {
                return _pageBar(
                  page: page.pagination.page,
                  totalPages: page.pagination.totalPages,
                  onPage: onPage,
                  currentPage: currentPage,
                );
              }
              final user = rows[i];
              return AppCard(
                onTap: () => _openDetail(user),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: user.isActive ? C.chip : const Color(0xFFF0F0F0),
                    child: Text(
                      user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                      style: TextStyle(
                        color: user.isActive ? C.blue : C.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(
                    user.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: C.navy),
                  ),
                  subtitle: Text(
                    '${user.email}\n'
                    '${(user.phone ?? '').isEmpty ? 'No phone' : user.phone}'
                    ' · ${(user.societyRoles.isEmpty ? user.roles : user.societyRoles).join(', ')}',
                    style: const TextStyle(
                        color: C.muted, fontSize: 12, height: 1.35),
                  ),
                  isThreeLine: true,
                  trailing: StatusBadge(user.isActive ? 'active' : 'inactive'),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _pageBar({
    required int page,
    required int totalPages,
    required ValueChanged<int> onPage,
    required int currentPage,
  }) {
    if (totalPages <= 1) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: currentPage <= 1 ? null : () => onPage(currentPage - 1),
            child: const Text('Previous'),
          ),
          Text('Page $page of $totalPages',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: C.navy, fontSize: 12)),
          TextButton(
            onPressed:
                currentPage >= totalPages ? null : () => onPage(currentPage + 1),
            child: const Text('Next'),
          ),
        ],
      ),
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

class _AdminProvisionResidentPageState extends State<AdminProvisionResidentPage> {
  final _formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  late String role = widget.initialRole;
  bool saving = false;
  String? formError;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => formError = null);
    if (!_formKey.currentState!.validate()) return;
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
      );
      repos.invalidateAfterResidentMutation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.reusedExisting
            ? 'Existing account updated and linked to this society.'
            : 'Resident account created.'),
        backgroundColor: C.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => formError = adminApiErrorMessage(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Provision resident')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const InfoNote(
              'If the email already exists, the backend reuses that user and adds the role/membership. Duplicate User records are not created.',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'OWNER', child: Text('Owner')),
                DropdownMenuItem(value: 'TENANT', child: Text('Tenant')),
              ],
              onChanged: saving
                  ? null
                  : (v) {
                      if (v != null) setState(() => role = v);
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: name,
              enabled: !saving,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: email,
              enabled: !saving,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
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
              controller: phone,
              enabled: !saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                hintText: '+91…',
              ),
            ),
            if (formError != null) ...[
              const SizedBox(height: 12),
              Text(formError!,
                  style: const TextStyle(
                      color: C.error, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Provision account'),
            ),
          ],
        ),
      ),
    );
  }
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

  Future<AdminUser> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .users
        .getUser(widget.userId, force: force);
  }

  Future<void> _deactivate(AdminUser user) async {
    final reason = await _promptText(
      title: 'Deactivate ${user.name}',
      label: 'Reason (optional)',
    );
    if (reason == null || !mounted) return;
    final session = authSession;
    if (session == null) return;
    try {
      final repos = ensureLiveRepositories(session.api);
      await repos.users.deactivateUser(
        user.id,
        reason: reason.trim().isEmpty ? null : reason.trim(),
      );
      repos.invalidateAfterResidentMutation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Resident deactivated.'),
        backgroundColor: C.green,
      ));
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(adminApiErrorMessage(e)),
        backgroundColor: C.error,
      ));
    }
  }

  Future<String?> _promptText({
    required String title,
    required String label,
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Confirm')),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resident details')),
      body: FutureBuilder<AdminUser>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
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
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: C.navy)),
                const SizedBox(height: 4),
                Text(user.email, style: const TextStyle(color: C.muted)),
                const SizedBox(height: 16),
                AppCard(
                    child: ListTile(
                        title: const Text('Phone'),
                        subtitle: Text(user.phone ?? '—'))),
                AppCard(
                    child: ListTile(
                        title: const Text('Roles'),
                        subtitle: Text(user.roles.join(', ')))),
                AppCard(
                  child: ListTile(
                    title: const Text('Status'),
                    trailing:
                        StatusBadge(user.isActive ? 'active' : 'inactive'),
                  ),
                ),
                AppCard(
                  child: ListTile(
                    title: const Text('Can login'),
                    trailing: StatusBadge(user.canLogin ? 'yes' : 'no'),
                  ),
                ),
                const SizedBox(height: 12),
                const SectionTitle('Active flat occupancy'),
                const SizedBox(height: 8),
                if (user.activeOccupancies.isEmpty)
                  const EmptyState('No active flat assignment')
                else
                  for (final occ in user.activeOccupancies)
                    AppCard(
                      child: ListTile(
                        title: Text('${occ.role} · flat ${occ.flatId}'),
                        subtitle: Text('Since ${occupancyDateLabel(occ.startsAt)}'),
                      ),
                    ),
                const SizedBox(height: 18),
                if (user.isActive &&
                    !user.roles.contains('ADMIN') &&
                    !user.roles.contains('GUARD'))
                  OutlinedButton.icon(
                    onPressed: () => _deactivate(user),
                    icon: const Icon(Icons.person_off_outlined),
                    label: const Text('Deactivate resident'),
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

  @override
  void dispose() {
    _debounce.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select ${widget.role == 'OWNER' ? 'owner' : 'tenant'}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              onChanged: (v) {
                query = v;
                _debounce.run(() {
                  page = 1;
                  setState(() => _future = _load(force: true));
                });
              },
              decoration: const InputDecoration(
                hintText: 'Search residents',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<_ResidentsBundle>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const LoadingView(label: 'Loading…');
                }
                if (snap.hasError) {
                  return LoadFailure(
                    error: snap.error!,
                    onRetry: () =>
                        setState(() => _future = _load(force: true)),
                  );
                }
                final rows = snap.data!.page.items;
                if (rows.isEmpty) {
                  return const EmptyState('No matching residents');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final user = rows[i];
                    return AppCard(
                      onTap: () => Navigator.pop(context, user),
                      child: ListTile(
                        title: Text(user.name,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(user.email),
                      ),
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
  return '${dt.day}/${dt.month}/${dt.year}';
}
