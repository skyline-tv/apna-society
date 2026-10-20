import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_core.dart';
import '../../ui/components.dart';

const kVehicleTypes = ['Car', 'Bike', 'Scooter', 'Other'];

/// Owner: view-only list of vehicles mapped to their flat by admin.
class OwnerVehiclesPage extends StatefulWidget {
  const OwnerVehiclesPage({super.key, required this.flatId});
  final int flatId;
  @override
  State<OwnerVehiclesPage> createState() => _OwnerVehiclesPageState();
}

class _OwnerVehiclesPageState extends State<OwnerVehiclesPage> {
  late final Future<List<dynamic>> _future =
      db.vehicles(flatId: widget.flatId, includeInactive: false);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(label: 'Loading your vehicles…');
          }
          final rows = snapshot.data ?? [];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.isEmpty ? 3 : rows.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) return const SectionTitle('My vehicles');
              if (i == 1) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 12),
                  child: InfoNote(
                    'Vehicles are registered and mapped by the society admin. Owners cannot add or edit vehicle records.',
                  ),
                );
              }
              if (rows.isEmpty)
                return const EmptyState(
                    'No active vehicles mapped to your flat');
              return VehicleCard(row: rows[i - 2]);
            },
          );
        },
      );
}

class AdminVehiclesPage extends StatefulWidget {
  const AdminVehiclesPage({super.key});
  @override
  State<AdminVehiclesPage> createState() => _AdminVehiclesPageState();
}

class _AdminVehiclesPageState extends State<AdminVehiclesPage> {
  final search = TextEditingController();
  final _debounce = Debouncer();
  late Future<List<dynamic>> _future = db.vehicles();

  void _reload() {
    setState(() {
      _future = db.vehicles(search: search.text);
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> openEditor([dynamic row]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AdminVehicleEditorPage(vehicle: row)),
    );
    if (saved == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Register vehicle'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: search,
                decoration: const InputDecoration(
                    labelText: 'Search registration / flat / slot',
                    prefixIcon: Icon(Icons.search)),
                onChanged: (_) => _debounce.run(_reload),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const LoadingView(label: 'Loading vehicles…');
                  }
                  final rows = snapshot.data ?? [];
                  if (rows.isEmpty)
                    return const EmptyState('No registered vehicles found');
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: InfoNote(
                              'Admin-only registration. Inactive vehicles stay in history but are not authorized at the gate.'),
                        );
                      }
                      final r = rows[i - 1];
                      final active = (r.data['is_active'] as int? ?? 1) == 1;
                      return VehicleCard(
                        row: r,
                        admin: true,
                        onTap: () => openEditor(r),
                        onToggle: () async {
                          await db.setVehicleActive(r.read<int>('id'), !active);
                          if (mounted) _reload();
                        },
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

class AdminVehicleEditorPage extends StatefulWidget {
  const AdminVehicleEditorPage({super.key, this.vehicle});
  final dynamic vehicle;
  @override
  State<AdminVehicleEditorPage> createState() => _AdminVehicleEditorPageState();
}

class _AdminVehicleEditorPageState extends State<AdminVehicleEditorPage> {
  late final TextEditingController reg;
  late final TextEditingController brand;
  late final TextEditingController colour;
  late final TextEditingController slot;
  String type = kVehicleTypes.first;
  String? building;
  int? flatId;
  List<String> buildings = [];
  List<dynamic> flats = [];
  bool photo = false;
  bool busy = false;
  String? error;
  bool get editing => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    reg = TextEditingController(
        text: widget.vehicle?.read<String>('registration_number') ?? '');
    brand = TextEditingController(
        text: widget.vehicle?.read<String>('brand_model') ?? '');
    colour = TextEditingController(
        text: (widget.vehicle?.data['colour'] as String?) ?? '');
    slot = TextEditingController(
        text: (widget.vehicle?.data['parking_slot'] as String?) ?? '');
    type = widget.vehicle?.read<String>('vehicle_type') ?? kVehicleTypes.first;
    if (!kVehicleTypes.contains(type)) type = 'Other';
    photo = (widget.vehicle?.data['photo_path'] as String?) != null;
    flatId = widget.vehicle?.read<int>('flat_id') as int?;
    building = widget.vehicle?.read<String>('building') as String?;
    _load();
  }

  Future<void> _load() async {
    buildings = await db.buildings();
    flats = await db.flats(includeInactive: false);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    reg.dispose();
    brand.dispose();
    colour.dispose();
    slot.dispose();
    super.dispose();
  }

  dynamic get selectedFlat {
    if (flatId == null) return null;
    for (final f in flats) {
      if (f.read<int>('id') == flatId) return f;
    }
    return null;
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (flatId == null) throw StateError('Select a flat number.');
      if (editing) {
        await db.updateVehicle(
          id: widget.vehicle.read<int>('id'),
          flatId: flatId!,
          registrationNumber: reg.text,
          vehicleType: type,
          brandModel: brand.text,
          colour: colour.text,
          parkingSlot: slot.text,
          photoPath: photo ? 'demo://vehicle_photo' : null,
        );
      } else {
        await db.createVehicle(
          flatId: flatId!,
          registrationNumber: reg.text,
          vehicleType: type,
          brandModel: brand.text,
          colour: colour.text,
          parkingSlot: slot.text.isEmpty ? null : slot.text,
          photoPath: photo ? 'demo://vehicle_photo' : null,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() =>
          error = e is StateError ? e.message : 'Could not save vehicle.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildingFlats = flats
        .where(
            (f) => building == null || f.read<String>('building') == building)
        .toList();
    final owner = selectedFlat?.read<String>('owner_name') as String?;
    return Scaffold(
      appBar: AppBar(
          title: Text(editing ? 'Edit vehicle mapping' : 'Register vehicle')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const InfoNote(
              'Map each vehicle to a society flat. Registration numbers must be unique.'),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: building,
            decoration: const InputDecoration(labelText: 'Building / Wing'),
            items: buildings
                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                .toList(),
            onChanged: busy
                ? null
                : (v) => setState(() {
                      building = v;
                      flatId = null;
                    }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: flatId,
            decoration: const InputDecoration(labelText: 'Flat number'),
            items: buildingFlats
                .map((f) => DropdownMenuItem(
                    value: f.read<int>('id') as int,
                    child: Text(f.read<String>('flat_number'))))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => flatId = v),
          ),
          if (owner != null) ...[
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: billDetailLine('Mapped owner', owner),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: reg,
            textCapitalization: TextCapitalization.characters,
            decoration:
                const InputDecoration(labelText: 'Vehicle registration number'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Vehicle type'),
            items: kVehicleTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => type = v!),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: brand,
              decoration: const InputDecoration(labelText: 'Brand and model')),
          const SizedBox(height: 12),
          TextField(
              controller: colour,
              decoration: const InputDecoration(labelText: 'Colour')),
          const SizedBox(height: 12),
          TextField(
              controller: slot,
              decoration: const InputDecoration(labelText: 'Parking slot')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: photo,
            onChanged: busy ? null : (v) => setState(() => photo = v),
            title: const Text('Vehicle photo (optional demo)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Simulated attachment for presentation'),
          ),
          if (error != null)
            Text(error!,
                style: const TextStyle(
                    color: C.error, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: busy ? null : save,
              child: Text(editing ? 'Save mapping' : 'Register vehicle')),
        ],
      ),
    );
  }
}

class VehicleVerificationPage extends StatefulWidget {
  const VehicleVerificationPage({super.key, this.guardId});
  final int? guardId;
  @override
  State<VehicleVerificationPage> createState() =>
      _VehicleVerificationPageState();
}

class _VehicleVerificationPageState extends State<VehicleVerificationPage> {
  final reg = TextEditingController();
  dynamic result;
  bool searched = false;
  bool busy = false;

  @override
  void dispose() {
    reg.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    setState(() {
      busy = true;
      searched = true;
    });
    try {
      result = await db.vehicleByRegistration(reg.text, activeOnly: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logEvent(String direction, {String? note}) async {
    final guardId = widget.guardId;
    if (guardId == null) return;
    try {
      await db.recordVehicleGateEvent(
        registrationNumber: reg.text,
        direction: direction,
        guardId: guardId,
        approvalNote: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vehicle $direction recorded.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: C.error));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: brandAppBarTitle(
                title: 'Vehicle verification', subtitle: kSocietyName)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const InfoNote(
              'Search society-registered vehicles. Unregistered plates show a warning and need admin/authorized approval before entry. No financial data is shown.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reg,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'Registration number',
                  prefixIcon: Icon(Icons.directions_car_outlined)),
              onSubmitted: (_) => verify(),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: busy ? null : verify,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Verify vehicle'),
            ),
            const SizedBox(height: 20),
            if (searched && result == null) ...[
              const EmptyState(
                  'UNREGISTERED VEHICLE — not authorized in society records',
                  icon: Icons.warning_amber_rounded),
              const InfoNote(
                  'Do not allow entry without admin or authorized approval.'),
              if (widget.guardId != null) ...[
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: C.amber),
                  onPressed: () => logEvent('entry',
                      note: 'Unregistered — approved exception recorded'),
                  child: const Text('Record approved entry (exception)'),
                ),
                OutlinedButton(
                    onPressed: () =>
                        logEvent('exit', note: 'Unregistered exit'),
                    child: const Text('Record exit')),
              ],
            ],
            if (result != null) ...[
              const StatusBadge('registered'),
              const SizedBox(height: 10),
              VehicleCard(row: result, showVerifyBanner: true),
              if (widget.guardId != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => logEvent('entry'),
                    child: const Text('Record vehicle entry')),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => logEvent('exit'),
                    child: const Text('Record vehicle exit')),
              ],
            ],
          ],
        ),
      );
}

class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.row,
    this.onTap,
    this.onToggle,
    this.admin = false,
    this.showVerifyBanner = false,
  });
  final dynamic row;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final bool admin;
  final bool showVerifyBanner;

  @override
  Widget build(BuildContext context) {
    final active = (row.data['is_active'] as int? ?? 1) == 1;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showVerifyBanner) ...[
          const Text('REGISTERED & AUTHORIZED',
              style: TextStyle(
                  color: C.green,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: .6)),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(
              child: Text(row.read<String>('registration_number'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: C.navy,
                      fontSize: 16))),
          StatusBadge(active ? 'active' : 'inactive'),
        ]),
        const SizedBox(height: 8),
        billDetailLine('Type', row.read<String>('vehicle_type')),
        billDetailLine('Brand / model', row.read<String>('brand_model')),
        if ((row.data['colour'] as String?)?.isNotEmpty == true)
          billDetailLine('Colour', row.data['colour'] as String),
        billDetailLine('Flat',
            '${row.read<String>('building')} · ${row.read<String>('flat_number')}'),
        billDetailLine('Owner', row.read<String>('owner_name')),
        billDetailLine(
            'Parking slot',
            (row.data['parking_slot'] as String?)?.isNotEmpty == true
                ? row.data['parking_slot'] as String
                : 'Unassigned'),
        if (admin) ...[
          const SizedBox(height: 10),
          Row(children: [
            TextButton(onPressed: onTap, child: const Text('Edit / reassign')),
            TextButton(
                onPressed: onToggle,
                child: Text(active ? 'Deactivate' : 'Activate')),
          ]),
        ],
      ]),
    );
  }
}
