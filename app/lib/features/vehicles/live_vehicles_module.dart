import 'package:flutter/material.dart';

import '../../api/auth/auth_session.dart';
import '../../api/models/common.dart';
import '../../api/models/vehicle_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import 'admin_vehicle_assignment.dart';
import 'vehicle_drafts.dart';

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

class _LiveResidentVehiclesPageState extends State<LiveResidentVehiclesPage> {
  late Future<VehicleList> _vehicles = _loadVehicles();

  Future<VehicleList> _loadVehicles({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .vehicles
        .listResident(force: force);
  }

  void reload() {
    setState(() {
      _vehicles = _loadVehicles(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _vehiclesTab();
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
              const Text(
                'Registered vehicles',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: C.navy,
                ),
              ),
              const SizedBox(height: 8),
              const InfoNote(
                'These are the vehicles registered to your account. '
                'The society admin adds, updates, or deactivates vehicles.',
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
              '${vehicleTypeLabel(v.vehicleType)} · ${v.makeModelLabel}',
              style: const TextStyle(color: C.muted, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              'Flat ${v.flatLabel} · Parking ${v.parkingLabel}',
              style: const TextStyle(color: C.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            StatusBadge(v.isActive ? 'Active' : 'Inactive'),
          ],
        ),
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

  Future<Vehicle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .vehicles
        .getResident(widget.vehicleId, force: force);
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
              _line('Type', vehicleTypeLabel(v.vehicleType)),
              _line('Make / model', v.makeModelLabel),
              _line('Flat', v.flatLabel),
              if (v.deactivationReason != null)
                _line('Deactivated', v.deactivationReason!),
              const SizedBox(height: 8),
              _line('Parking number', v.parkingLabel),
              const SizedBox(height: 12),
              const InfoNote(
                'Vehicle details are managed by the society admin.',
              ),
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

class LiveAdminVehiclesPage extends StatelessWidget {
  const LiveAdminVehiclesPage({super.key});

  @override
  Widget build(BuildContext context) => const AdminVehicleAssignmentPage();
}


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
