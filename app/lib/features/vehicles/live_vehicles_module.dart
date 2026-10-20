import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/common.dart';
import '../../api/models/vehicle_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

String vehicleErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'DUPLICATE_VEHICLE':
        return 'This registration number is already registered in the society.';
      case 'INVALID_REGISTRATION_NUMBER':
        return 'Invalid Indian registration number format.';
      case 'VEHICLE_INACTIVE':
        return 'This vehicle is inactive.';
      case 'VEHICLE_FLAT_MISMATCH':
        return 'Vehicle does not belong to the selected flat.';
      case 'SLOT_INACTIVE':
        return 'This parking slot is inactive.';
      case 'INCOMPATIBLE_SLOT_TYPE':
        return 'Slot type does not match the vehicle type.';
      case 'DUPLICATE_SLOT':
        return 'A parking slot with this number already exists.';
      case 'DUPLICATE_ALLOCATION':
        return 'Vehicle or slot already has an active allocation.';
      case 'VEHICLE_HAS_ALLOCATION':
        return 'Release the parking allocation before deactivating this vehicle.';
      case 'SLOT_OCCUPIED':
        return 'Release the allocation before deactivating this slot.';
      case 'ALLOCATION_CONFLICT':
        return 'Allocation conflict. Refresh and try again.';
      case 'DUPLICATE_ACTIVE_ENTRY':
        return 'This plate is already marked inside.';
      case 'EXIT_CONFLICT':
        return 'Exit conflict. Refresh and try again.';
      case 'VEHICLE_TYPE_REQUIRED':
        return 'Vehicle type is required for unregistered plates.';
      case 'REGISTRATION_MISMATCH':
        return 'Registration number does not match the selected vehicle.';
      case 'RESIDENTIAL_ACCESS_DENIED':
        return 'Residential vehicle access is not available for this flat.';
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to this action.';
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

// ─── Resident ────────────────────────────────────────────────────────────────

class LiveResidentVehiclesPage extends StatefulWidget {
  const LiveResidentVehiclesPage({super.key});

  @override
  State<LiveResidentVehiclesPage> createState() =>
      _LiveResidentVehiclesPageState();
}

class _LiveResidentVehiclesPageState extends State<LiveResidentVehiclesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<VehicleList> _vehicles = _loadVehicles();
  late Future<ParkingList> _parking = _loadParking();
  final _busy = <String>{};

  Future<VehicleList> _loadVehicles({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .vehicles
        .listResident(force: force);
  }

  Future<ParkingList> _loadParking({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .vehicles
        .residentParking(force: force);
  }

  void reload() {
    setState(() {
      _vehicles = _loadVehicles(force: true);
      _parking = _loadParking(force: true);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openRegister() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveRegisterVehiclePage()),
    );
    if (ok == true) reload();
  }

  Future<void> _deactivate(Vehicle v) async {
    if (_busy.contains(v.id)) return;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate vehicle'),
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
            child: const Text('Deactivate'),
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
      await ensureLiveRepositories(session.api).vehicles.deactivate(
            v.id,
            reason: reason.isEmpty ? null : reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle deactivated')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: C.navy,
          tabs: const [
            Tab(text: 'My vehicles'),
            Tab(text: 'Parking'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _vehiclesTab(),
              _parkingTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vehiclesTab() {
    return FutureBuilder<VehicleList>(
      future: _vehicles,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading vehicles…');
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
                      'Registered vehicles',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openRegister,
                    icon: const Icon(Icons.add),
                    label: const Text('Register'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const InfoNote(
                'Registration numbers are validated by the server. '
                'Parking slots are assigned by the society admin.',
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No vehicles registered yet')
              else
                ...items.map((v) => _vehicleCard(v)),
            ],
          ),
        );
      },
    );
  }

  Widget _vehicleCard(Vehicle v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LiveResidentVehicleDetailPage(vehicleId: v.id),
            ),
          );
          reload();
        },
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              v.registrationNumber,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: C.navy,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${vehicleTypeLabel(v.vehicleType)}'
              '${v.make != null ? ' · ${v.make}' : ''}'
              '${v.model != null ? ' ${v.model}' : ''}',
              style: const TextStyle(color: C.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                StatusBadge(v.isActive ? 'Active' : 'Inactive'),
                if (v.parkingSlotId != null)
                  const StatusBadge('Slot allocated')
                else
                  const StatusBadge('No slot'),
              ],
            ),
            if (v.isActive) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed:
                      _busy.contains(v.id) ? null : () => _deactivate(v),
                  child: const Text('Deactivate'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _parkingTab() {
    return FutureBuilder<ParkingList>(
      future: _parking,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading parking…');
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
                'Active allocations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              const InfoNote(
                'Allocations are managed by the society admin. '
                'This list shows only active parking assignments for your flats.',
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No active parking allocations')
              else
                ...items.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.slot?.slotNumber ?? a.parkingSlotId,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            a.vehicle?.registrationNumber ?? a.vehicleId,
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          StatusBadge(a.status),
                          Text(
                            'Since ${_shortIso(a.startsAt)}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 12,
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

class LiveRegisterVehiclePage extends StatefulWidget {
  const LiveRegisterVehiclePage({super.key});

  @override
  State<LiveRegisterVehiclePage> createState() =>
      _LiveRegisterVehiclePageState();
}

class _LiveRegisterVehiclePageState extends State<LiveRegisterVehiclePage> {
  final _reg = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _colour = TextEditingController();
  String _type = 'FOUR_WHEELER';
  String? _flatId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _flatId = authSession?.selectedResidentFlatId;
  }

  @override
  void dispose() {
    _reg.dispose();
    _make.dispose();
    _model.dispose();
    _colour.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final flatId = _flatId;
    if (flatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active flat for registration')),
      );
      return;
    }
    final normalized = normalizeRegistrationNumber(_reg.text);
    if (!isValidIndianRegistrationNumber(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid Indian registration number'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).vehicles.register(
            RegisterVehicleRequest(
              flatId: flatId,
              vehicleType: _type,
              registrationNumber: normalized,
              make: _make.text.trim().isEmpty ? null : _make.text.trim(),
              model: _model.text.trim().isEmpty ? null : _model.text.trim(),
              colour:
                  _colour.text.trim().isEmpty ? null : _colour.text.trim(),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle registered')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flats = authSession?.residentFlats ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Register vehicle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (flats.length > 1)
            DropdownButtonFormField<String>(
              value: _flatId,
              decoration: const InputDecoration(
                labelText: 'Flat',
                border: OutlineInputBorder(),
              ),
              items: flats
                  .map(
                    (f) => DropdownMenuItem(
                      value: f.flat.id,
                      child: Text(
                        '${f.flat.wingCode ?? '?'}-${f.flat.number}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => _flatId = v);
                if (v != null) authSession?.selectResidentFlat(v);
              },
            ),
          if (flats.length > 1) const SizedBox(height: 12),
          TextField(
            controller: _reg,
            decoration: const InputDecoration(
              labelText: 'Registration number',
              helperText: 'Example: MH12AB1234',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s-]')),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(
              labelText: 'Vehicle type',
              border: OutlineInputBorder(),
            ),
            items: kApiVehicleTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(vehicleTypeLabel(t)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? 'FOUR_WHEELER'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _make,
            decoration: const InputDecoration(
              labelText: 'Make (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'Model (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _colour,
            decoration: const InputDecoration(
              labelText: 'Colour (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Registering…' : 'Register'),
          ),
        ],
      ),
    );
  }
}

class LiveResidentVehicleDetailPage extends StatefulWidget {
  const LiveResidentVehicleDetailPage({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  State<LiveResidentVehicleDetailPage> createState() =>
      _LiveResidentVehicleDetailPageState();
}

class _LiveResidentVehicleDetailPageState
    extends State<LiveResidentVehicleDetailPage> {
  late Future<Vehicle> _future = _load();
  bool _saving = false;
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _colour = TextEditingController();
  String? _type;
  String? _seededForId;

  Future<Vehicle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final v = await ensureLiveRepositories(session.api)
        .vehicles
        .getResident(widget.vehicleId, force: force);
    if (_seededForId != v.id) {
      _make.text = v.make ?? '';
      _model.text = v.model ?? '';
      _colour.text = v.colour ?? '';
      _type = v.vehicleType;
      _seededForId = v.id;
    }
    return v;
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _colour.dispose();
    super.dispose();
  }

  Future<void> _save(Vehicle v) async {
    if (_saving || !v.isActive) return;
    setState(() => _saving = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).vehicles.update(
            v.id,
            make: _make.text.trim().isEmpty ? null : _make.text.trim(),
            model: _model.text.trim().isEmpty ? null : _model.text.trim(),
            colour: _colour.text.trim().isEmpty ? null : _colour.text.trim(),
            vehicleType: _type,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle updated')),
      );
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle detail')),
      body: FutureBuilder<Vehicle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading vehicle…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              error: snapshot.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final v = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                v.registrationNumber,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              StatusBadge(v.isActive ? 'Active' : 'Inactive'),
              const SizedBox(height: 16),
              if (v.isActive) ...[
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: kApiVehicleTypes
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(vehicleTypeLabel(t)),
                        ),
                      )
                      .toList(),
                  onChanged: (t) => setState(() => _type = t),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _make,
                  decoration: const InputDecoration(
                    labelText: 'Make',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _colour,
                  decoration: const InputDecoration(
                    labelText: 'Colour',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : () => _save(v),
                  child: Text(_saving ? 'Saving…' : 'Save changes'),
                ),
              ] else ...[
                _line('Type', vehicleTypeLabel(v.vehicleType)),
                if (v.make != null) _line('Make', v.make!),
                if (v.model != null) _line('Model', v.model!),
                if (v.deactivationReason != null)
                  _line('Deactivated', v.deactivationReason!),
              ],
              const SizedBox(height: 16),
              if (v.parkingSlotId != null)
                _line('Parking slot', v.parkingSlotId!)
              else
                _line('Parking', 'Not allocated'),
            ],
          );
        },
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
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

// ─── Admin ───────────────────────────────────────────────────────────────────

class LiveAdminVehiclesPage extends StatefulWidget {
  const LiveAdminVehiclesPage({super.key});

  @override
  State<LiveAdminVehiclesPage> createState() => _LiveAdminVehiclesPageState();
}

class _LiveAdminVehiclesPageState extends State<LiveAdminVehiclesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: C.navy,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Vehicles'),
            Tab(text: 'Slots'),
            Tab(text: 'Allocations'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _AdminVehiclesTab(),
              _AdminSlotsTab(),
              _AdminAllocationsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminVehiclesTab extends StatefulWidget {
  const _AdminVehiclesTab();

  @override
  State<_AdminVehiclesTab> createState() => _AdminVehiclesTabState();
}

class _AdminVehiclesTabState extends State<_AdminVehiclesTab> {
  final _search = TextEditingController();
  bool? _activeFilter = true;
  late Future<Paged<Vehicle>> _future = _load();

  Future<Paged<Vehicle>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final q = _search.text.trim();
    return ensureLiveRepositories(session.api).vehicles.listAdminVehicles(
          force: force,
          query: ListAdminVehiclesQuery(
            isActive: _activeFilter,
            registrationNumber: q.isEmpty ? null : q,
            limit: 50,
          ),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<Vehicle>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading vehicles…');
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
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search registration',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: reload,
                  ),
                ),
                onSubmitted: (_) => reload(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Active'),
                    selected: _activeFilter == true,
                    onSelected: (_) {
                      setState(() {
                        _activeFilter = true;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Inactive'),
                    selected: _activeFilter == false,
                    onSelected: (_) {
                      setState(() {
                        _activeFilter = false;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('All'),
                    selected: _activeFilter == null,
                    onSelected: (_) {
                      setState(() {
                        _activeFilter = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const InfoNote(
                'Residents register their own vehicles. '
                'Admins allocate parking slots from the Slots and Allocations tabs.',
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No vehicles found')
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
                            v.registrationNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${vehicleTypeLabel(v.vehicleType)} · Flat ${v.flatId}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(v.isActive ? 'Active' : 'Inactive'),
                              if (v.parkingSlotId != null)
                                const StatusBadge('Allocated'),
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

class _AdminSlotsTab extends StatefulWidget {
  const _AdminSlotsTab();

  @override
  State<_AdminSlotsTab> createState() => _AdminSlotsTabState();
}

class _AdminSlotsTabState extends State<_AdminSlotsTab> {
  String? _availability = 'all';
  late Future<_SlotsBundle> _future = _load();
  bool _busy = false;

  Future<_SlotsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final slots = await repos.vehicles.listSlots(
      force: force,
      query: ListParkingSlotsQuery(
        availability: _availability,
        isActive: true,
        limit: 100,
      ),
    );
    final summary = await repos.vehicles.parkingSummary(force: force);
    return _SlotsBundle(slots: slots, summary: summary);
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _createSlot() async {
    final numberCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    var type = 'FOUR_WHEELER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Create parking slot'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Slot number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: kApiVehicleTypes
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(vehicleTypeLabel(t)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocal(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locCtrl,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  border: OutlineInputBorder(),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).vehicles.createSlot(
            slotNumber: numberCtrl.text.trim(),
            parkingType: type,
            locationDescription:
                locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slot created')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      numberCtrl.dispose();
      locCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(ParkingSlot slot) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).vehicles.setSlotActive(
            slot.id,
            isActive: !slot.isActive,
            reason: slot.isActive ? 'Deactivated by admin' : null,
          );
      if (!mounted) return;
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SlotsBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading slots…');
        }
        if (snapshot.hasError) {
          return LoadFailure(error: snapshot.error!, onRetry: reload);
        }
        final bundle = snapshot.data!;
        final s = bundle.summary;
        final items = bundle.slots.items;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Available ${s.availableSlots} · Occupied ${s.occupiedSlots}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: C.navy,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createSlot,
                    icon: const Icon(Icons.add),
                    label: const Text('Add slot'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in ['all', 'available', 'occupied'])
                    FilterChip(
                      label: Text(a),
                      selected: _availability == a,
                      onSelected: (_) {
                        setState(() {
                          _availability = a;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No parking slots')
              else
                ...items.map(
                  (slot) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot.slotNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            '${vehicleTypeLabel(slot.parkingType)}'
                            '${slot.locationDescription != null ? ' · ${slot.locationDescription}' : ''}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              StatusBadge(
                                slot.isOccupied == true
                                    ? 'Occupied'
                                    : 'Available',
                              ),
                              StatusBadge(
                                slot.isActive ? 'Active' : 'Inactive',
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed:
                                  _busy ? null : () => _toggleActive(slot),
                              child: Text(
                                slot.isActive ? 'Deactivate' : 'Reactivate',
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

class _SlotsBundle {
  const _SlotsBundle({required this.slots, required this.summary});
  final Paged<ParkingSlot> slots;
  final ParkingSummary summary;
}

class _AdminAllocationsTab extends StatefulWidget {
  const _AdminAllocationsTab();

  @override
  State<_AdminAllocationsTab> createState() => _AdminAllocationsTabState();
}

class _AdminAllocationsTabState extends State<_AdminAllocationsTab> {
  String? _status = 'ACTIVE';
  late Future<Paged<ParkingAllocation>> _future = _load();
  bool _busy = false;

  Future<Paged<ParkingAllocation>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).vehicles.listAllocations(
          force: force,
          query: ListAllocationsQuery(status: _status, limit: 50),
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _allocate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveAllocateParkingPage()),
    );
    if (ok == true) reload();
  }

  Future<void> _release(ParkingAllocation a) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api)
          .vehicles
          .release(a.id, reason: 'Released by admin');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Allocation released')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<ParkingAllocation>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(label: 'Loading allocations…');
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
                      'Parking allocations',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: C.navy,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _allocate,
                    icon: const Icon(Icons.link),
                    label: const Text('Allocate'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Active'),
                    selected: _status == 'ACTIVE',
                    onSelected: (_) {
                      setState(() {
                        _status = 'ACTIVE';
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Ended'),
                    selected: _status == 'ENDED',
                    onSelected: (_) {
                      setState(() {
                        _status = 'ENDED';
                        _future = _load(force: true);
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('All'),
                    selected: _status == null,
                    onSelected: (_) {
                      setState(() {
                        _status = null;
                        _future = _load(force: true);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState('No allocations')
              else
                ...items.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Slot ${a.parkingSlotId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: C.navy,
                            ),
                          ),
                          Text(
                            'Vehicle ${a.vehicleId} · Flat ${a.flatId}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          StatusBadge(a.status),
                          Text(
                            'Started ${_shortIso(a.startsAt)}'
                            '${a.endsAt != null ? ' · Ended ${_shortIso(a.endsAt)}' : ''}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 12,
                            ),
                          ),
                          if (a.status == 'ACTIVE')
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: _busy ? null : () => _release(a),
                                child: const Text('Release'),
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

class LiveAllocateParkingPage extends StatefulWidget {
  const LiveAllocateParkingPage({super.key});

  @override
  State<LiveAllocateParkingPage> createState() =>
      _LiveAllocateParkingPageState();
}

class _LiveAllocateParkingPageState extends State<LiveAllocateParkingPage> {
  List<Vehicle> _vehicles = const [];
  List<ParkingSlot> _slots = const [];
  Vehicle? _vehicle;
  ParkingSlot? _slot;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repos = ensureLiveRepositories(session.api);
      final vehicles = await repos.vehicles.listAdminVehicles(
        force: true,
        query: const ListAdminVehiclesQuery(isActive: true, limit: 100),
      );
      final slots = await repos.vehicles.listSlots(
        force: true,
        query: const ListParkingSlotsQuery(
          availability: 'available',
          isActive: true,
          limit: 100,
        ),
      );
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles.items;
        _slots = slots.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = vehicleErrorMessage(e);
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final v = _vehicle;
    final s = _slot;
    if (v == null || s == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select vehicle and slot')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).vehicles.allocate(
            flatId: v.flatId,
            vehicleId: v.id,
            parkingSlotId: s.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parking allocated')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Allocate parking')),
      body: _loading
          ? const LoadingView(label: 'Loading options…')
          : _error != null
              ? LoadFailure(error: _error!, onRetry: _loadOptions)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    DropdownButtonFormField<Vehicle>(
                      value: _vehicle,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle',
                        border: OutlineInputBorder(),
                      ),
                      items: _vehicles
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                '${v.registrationNumber} (${vehicleTypeLabel(v.vehicleType)})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _vehicle = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ParkingSlot>(
                      value: _slot,
                      decoration: const InputDecoration(
                        labelText: 'Available slot',
                        border: OutlineInputBorder(),
                      ),
                      items: _slots
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                '${s.slotNumber} (${vehicleTypeLabel(s.parkingType)})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (s) => setState(() => _slot = s),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting ? 'Allocating…' : 'Allocate',
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ─── Guard ───────────────────────────────────────────────────────────────────

class LiveGuardVehiclesPage extends StatefulWidget {
  const LiveGuardVehiclesPage({super.key});

  @override
  State<LiveGuardVehiclesPage> createState() => _LiveGuardVehiclesPageState();
}

class _LiveGuardVehiclesPageState extends State<LiveGuardVehiclesPage> {
  final _reg = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'FOUR_WHEELER';
  late Future<Paged<VehicleLog>> _logs = _loadLogs();
  bool _busy = false;

  Future<Paged<VehicleLog>> _loadLogs({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).vehicles.listLogs(
          force: force,
          status: 'INSIDE',
          limit: 50,
        );
  }

  void reload() => setState(() => _logs = _loadLogs(force: true));

  @override
  void dispose() {
    _reg.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _entry() async {
    if (_busy) return;
    final normalized = normalizeRegistrationNumber(_reg.text);
    if (!isValidIndianRegistrationNumber(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid registration number')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api).vehicles.recordEntry(
            registrationNumber: normalized,
            vehicleType: _type,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      _reg.clear();
      _notes.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle entry recorded')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exit(VehicleLog log) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      await ensureLiveRepositories(session.api)
          .vehicles
          .recordExit(logId: log.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${log.registrationNumber} exited')),
      );
      reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vehicleErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle gate')),
      body: FutureBuilder<Paged<VehicleLog>>(
        future: _logs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading vehicle logs…');
          }
          if (snapshot.hasError) {
            return LoadFailure(error: snapshot.error!, onRetry: reload);
          }
          final inside = snapshot.data!.items;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                const Text(
                  'Record entry',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: C.navy,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reg,
                  decoration: const InputDecoration(
                    labelText: 'Registration number',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type (required if unregistered)',
                    border: OutlineInputBorder(),
                  ),
                  items: kApiVehicleTypes
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(vehicleTypeLabel(t)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _type = v ?? 'FOUR_WHEELER'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _entry,
                  child: Text(_busy ? 'Recording…' : 'Record entry'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Inside now',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: C.navy,
                  ),
                ),
                const SizedBox(height: 8),
                if (inside.isEmpty)
                  const EmptyState('No vehicles currently inside')
                else
                  ...inside.map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.registrationNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: C.navy,
                              ),
                            ),
                            Text(
                              '${vehicleTypeLabel(log.vehicleType)} · '
                              'In since ${_shortIso(log.entryAt)}'
                              '${log.isRegisteredResidentVehicle ? ' · Resident' : ' · Guest'}',
                              style: const TextStyle(
                                color: C.muted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: _busy ? null : () => _exit(log),
                                child: const Text('Record exit'),
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
      ),
    );
  }
}
