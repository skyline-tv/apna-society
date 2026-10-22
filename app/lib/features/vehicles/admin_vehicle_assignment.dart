import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/models/common.dart';
import '../../api/models/society_models.dart';
import '../../api/models/vehicle_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import 'vehicle_drafts.dart';

/// Admin vehicle-to-flat assignment. No payment fields.
class AdminVehicleAssignmentPage extends StatefulWidget {
  const AdminVehicleAssignmentPage({super.key});

  @override
  State<AdminVehicleAssignmentPage> createState() =>
      _AdminVehicleAssignmentPageState();
}

class _AdminVehicleAssignmentPageState extends State<AdminVehicleAssignmentPage> {
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

  Future<void> _openForm({Vehicle? existing}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminVehicleAssignmentFormPage(existing: existing),
      ),
    );
    if (ok == true && mounted) reload();
  }

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
              const PageHeader(
                'Vehicles',
                subtitle: 'Link a vehicle and parking number to a flat',
              ),
              PrimaryButton(
                label: 'Add vehicle',
                icon: Icons.add_rounded,
                onPressed: () => _openForm(),
              ),
              const SizedBox(height: 12),
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
                'Select a flat, confirm the resident, then save the vehicle type, '
                'registration number, and parking number. Residents can only view '
                'vehicles registered to their account.',
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                EmptyState(
                  'No vehicles found',
                  actionLabel: 'Add vehicle',
                  onAction: () => _openForm(),
                )
              else
                ...items.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: v.isActive ? () => _openForm(existing: v) : null,
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
                          const SizedBox(height: 4),
                          Text(
                            '${vehicleTypeLabel(v.vehicleType)} · Parking ${v.parkingLabel}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${v.residentName ?? 'Resident'} · Flat ${v.flatLabel}',
                            style: const TextStyle(
                              color: C.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          StatusBadge(v.isActive ? 'Active' : 'Inactive'),
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

class AdminVehicleAssignmentFormPage extends StatefulWidget {
  const AdminVehicleAssignmentFormPage({super.key, this.existing});
  final Vehicle? existing;

  @override
  State<AdminVehicleAssignmentFormPage> createState() =>
      _AdminVehicleAssignmentFormPageState();
}

class _AdminVehicleAssignmentFormPageState
    extends State<AdminVehicleAssignmentFormPage> {
  final _form = GlobalKey<FormState>();
  final registration = TextEditingController();
  final parkingNumber = TextEditingController();
  String vehicleType = 'FOUR_WHEELER';
  String? wingId;
  String? flatId;
  bool busy = false;
  String? error;
  late Future<_VehicleLookups> _lookups = _loadLookups();

  bool get editing => widget.existing != null;

  Future<_VehicleLookups> _loadLookups() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final wings = await repos.society.wings();
    final flats = await repos.society.listAllFlats(isActive: true);
    return _VehicleLookups(wings: wings, flats: flats);
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      registration.text = existing.registrationNumber;
      parkingNumber.text = existing.parkingNumber ?? '';
      vehicleType = kAdminSelectableVehicleTypes.contains(existing.vehicleType)
          ? existing.vehicleType
          : 'FOUR_WHEELER';
      flatId = existing.flatId;
    }
  }

  @override
  void dispose() {
    registration.dispose();
    parkingNumber.dispose();
    super.dispose();
  }

  ResidentSummary? _residentFor(FlatSummary? flat) {
    if (flat == null) return null;
    return flat.activeTenant ?? flat.activeOwner;
  }

  Future<void> _save(_VehicleLookups lookups) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    final selectedFlatId = flatId;
    if (selectedFlatId == null) {
      setState(() => error = 'Select a flat.');
      return;
    }
    FlatSummary? flat;
    for (final item in lookups.flats) {
      if (item.id == selectedFlatId) {
        flat = item;
        break;
      }
    }
    final resident = editing
        ? null
        : _residentFor(flat);
    if (!editing && resident == null) {
      setState(() => error = 'Assign a resident to this flat first.');
      return;
    }
    final plate = normalizeRegistrationNumber(registration.text);
    if (!isValidIndianRegistrationNumber(plate)) {
      setState(() => error = 'Enter a valid Indian registration number.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession!;
      final repos = ensureLiveRepositories(session.api);
      if (editing) {
        await repos.vehicles.adminUpdate(
          widget.existing!.id,
          vehicleType: vehicleType,
          registrationNumber: plate,
          parkingNumber: parkingNumber.text.trim(),
        );
      } else {
        await repos.vehicles.adminRegister(
          AdminRegisterVehicleRequest(
            flatId: selectedFlatId,
            registeredUserId: resident!.id,
            vehicleType: vehicleType,
            registrationNumber: plate,
            parkingNumber: parkingNumber.text.trim().isEmpty
                ? null
                : parkingNumber.text.trim(),
          ),
        );
      }
      repos.invalidateAfterVehicleMutation();
      if (!mounted) return;
      showSuccessSnack(
        context,
        editing ? 'Vehicle updated.' : 'Vehicle saved.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = vehicleErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _deactivate() async {
    final existing = widget.existing;
    if (existing == null) return;
    final reason = await promptTextDialog(
      context,
      title: 'Deactivate this vehicle?',
      message:
          '${existing.registrationNumber} will no longer be an active society vehicle. The record is kept.',
      label: 'Reason (optional)',
      confirmLabel: 'Deactivate',
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .vehicles
          .adminDeactivate(existing.id, reason: reason.isEmpty ? null : reason);
      ensureLiveRepositories(session.api).invalidateAfterVehicleMutation(
        vehicleId: existing.id,
      );
      if (!mounted) return;
      showAppSnack(context, 'Vehicle deactivated.', tone: SnackTone.warning);
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = vehicleErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VehicleLookups>(
      future: _lookups,
      builder: (context, snap) {
        final lookups = snap.data;
        final flats = lookups?.flats ?? const <FlatSummary>[];
        final wings = lookups?.wings ?? const <WingSummary>[];
        final wingFlats = wingId == null
            ? flats
            : flats.where((f) => f.wingId == wingId).toList();
        FlatSummary? selected;
        for (final flat in flats) {
          if (flat.id == flatId) {
            selected = flat;
            break;
          }
        }
        final resident = _residentFor(selected);
        return FormScaffold(
          title: editing ? 'Edit vehicle' : 'Add vehicle',
          formKey: _form,
          bottom: PrimaryButton(
            label: editing ? 'Save changes' : 'Save vehicle',
            icon: Icons.check_rounded,
            busy: busy,
            onPressed: lookups == null ? null : () => _save(lookups),
          ),
          children: [
            if (snap.hasError)
              LoadFailure(
                error: snap.error!,
                compact: true,
                onRetry: () => setState(() => _lookups = _loadLookups()),
              )
            else if (lookups == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LoadingView(label: 'Loading flats…'),
              )
            else ...[
              const InfoNote(
                'This assigns a vehicle to a flat and resident. '
                'It does not collect or record a payment.',
              ),
              const SizedBox(height: 16),
              const FormSectionLabel('Flat'),
              if (editing)
                DetailCard(children: [
                  DetailRow('Flat', widget.existing!.flatLabel),
                  DetailRow(
                    'Resident',
                    widget.existing!.residentName ?? '—',
                  ),
                ])
              else ...[
                DropdownButtonFormField<String?>(
                  value: wingId,
                  decoration: const InputDecoration(labelText: 'Wing'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All wings'),
                    ),
                    for (final wing in wings)
                      DropdownMenuItem<String?>(
                        value: wing.id,
                        child: Text('Wing ${wing.code}'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                            wingId = v;
                            if (flatId != null &&
                                !flats
                                    .where((f) => v == null || f.wingId == v)
                                    .any((f) => f.id == flatId)) {
                              flatId = null;
                            }
                          }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: flatId,
                  decoration: const InputDecoration(labelText: 'Flat *'),
                  items: [
                    for (final flat in wingFlats)
                      DropdownMenuItem(
                        value: flat.id,
                        child: Text(
                          flat.label,
                        ),
                      ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => flatId = v),
                  validator: (v) => v == null ? 'Select a flat.' : null,
                ),
                const SizedBox(height: 12),
                if (selected != null)
                  DetailCard(children: [
                    DetailRow(
                      'Resident',
                      resident == null
                          ? 'No owner or tenant assigned'
                          : resident.name,
                    ),
                    if (selected.activeOwner != null &&
                        selected.activeTenant != null)
                      DetailRow('Owner', selected.activeOwner!.name),
                  ]),
              ],
              const SizedBox(height: 16),
              const FormSectionLabel('Vehicle'),
              DropdownButtonFormField<String>(
                value: vehicleType,
                decoration: const InputDecoration(labelText: 'Vehicle type *'),
                items: [
                  for (final type in kAdminSelectableVehicleTypes)
                    DropdownMenuItem(
                      value: type,
                      child: Text(vehicleTypeLabel(type)),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() => vehicleType = v ?? vehicleType),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: registration,
                enabled: !busy,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Registration number *',
                  hintText: 'MH12AB1234',
                ),
                validator: (v) {
                  final plate = normalizeRegistrationNumber(v ?? '');
                  if (!isValidIndianRegistrationNumber(plate)) {
                    return 'Enter a valid Indian registration number.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: parkingNumber,
                enabled: !busy,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Parking number',
                  hintText: 'B-12',
                ),
              ),
              if (editing && widget.existing!.isActive) ...[
                const SizedBox(height: 16),
                SecondaryButton(
                  label: 'Deactivate vehicle',
                  icon: Icons.block_outlined,
                  destructive: true,
                  onPressed: busy ? null : _deactivate,
                ),
              ],
              InlineError(error),
            ],
          ],
        );
      },
    );
  }
}

class _VehicleLookups {
  const _VehicleLookups({required this.wings, required this.flats});
  final List<WingSummary> wings;
  final List<FlatSummary> flats;
}
