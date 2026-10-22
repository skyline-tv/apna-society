import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/billing_models.dart';
import '../../api/models/common.dart';
import '../../api/models/society_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart' show moneyPaise;
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

class LiveAdditionalServicesPage extends StatefulWidget {
  const LiveAdditionalServicesPage({
    super.key,
    this.initialFlatId,
    this.embedded = false,
  });
  final String? initialFlatId;
  final bool embedded;

  @override
  State<LiveAdditionalServicesPage> createState() =>
      _LiveAdditionalServicesPageState();
}

class _LiveAdditionalServicesPageState extends State<LiveAdditionalServicesPage> {
  String? wingId;
  String? flatId;
  bool? activeOnly = true;
  late Future<_ServicesBundle> _future = _load();

  Future<_ServicesBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final wings = await repos.society.wings(force: force);
    final flats = await repos.society.listAllFlats(
      force: force,
      isActive: true,
      wingId: wingId,
    );
    final services = await repos.billing.listAdditionalServices(
      force: force,
      wingId: wingId,
      flatId: widget.initialFlatId ?? flatId,
      isActive: activeOnly,
      limit: 200,
    );
    return _ServicesBundle(wings: wings, flats: flats, services: services);
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _openForm({AdditionalService? existing, String? presetFlatId}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAdditionalServiceFormPage(
          existing: existing,
          presetFlatId: presetFlatId ?? widget.initialFlatId ?? flatId,
        ),
      ),
    );
    if (ok == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ServicesBundle>(
      future: _future,
      builder: (context, snap) {
        final bundle = snap.data;
        final rows = bundle?.services.items ?? const <AdditionalService>[];
        final scopedFlatId = widget.initialFlatId ?? flatId;
        final activeForFlat = scopedFlatId == null
            ? rows.where((s) => s.isActive).toList()
            : rows
                .where((s) => s.isActive && s.flatId == scopedFlatId)
                .toList();
        final atCap = scopedFlatId != null &&
            !canAddActiveAdditionalService(activeForFlat);
        void addService() {
          if (atCap) {
            showAppSnack(context, kAdditionalServiceLimitMessage,
                tone: SnackTone.warning);
            return;
          }
          _openForm();
        }

        final body = _buildBody(
          context,
          snap: snap,
          bundle: bundle,
          rows: rows,
          scopedFlatId: scopedFlatId,
          activeCount: activeForFlat.length,
          atCap: atCap,
          onAdd: addService,
        );
        if (widget.embedded) return body;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Additional services'),
            actions: [
              IconButton(
                tooltip: atCap
                    ? kAdditionalServiceLimitMessage
                    : 'Add service',
                onPressed: atCap ? null : addService,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required AsyncSnapshot<_ServicesBundle> snap,
    required _ServicesBundle? bundle,
    required List<AdditionalService> rows,
    required String? scopedFlatId,
    required int activeCount,
    required bool atCap,
    required VoidCallback onAdd,
  }) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const SkeletonList(items: 6, showHeader: true);
    }
    if (snap.hasError) {
      return LoadFailure(
        error: snap.error!,
        title: 'Could not load additional services',
        onRetry: reload,
      );
    }
    final loaded = bundle!;
    final monthlyTotal =
        rows.where((s) => s.isActive).fold<int>(0, (sum, s) => sum + s.monthlyTotalPaise);
    return RefreshIndicator(
      color: C.blue,
      onRefresh: () async {
        reload();
        await _future;
      },
      child: ListView(
        padding: Sp.pagePadding,
        children: [
          const PageHeader('Additional services',
              subtitle: 'Recurring monthly charges attached to a flat'),
          PrimaryButton(
            label: atCap ? 'Add service (10/10)' : 'Add service',
            icon: Icons.add_rounded,
            onPressed: atCap ? null : onAdd,
          ),
          const SizedBox(height: 12),
          MiniStatStrip(children: [
            MiniStat('Shown', '${rows.length}'),
            MiniStat('Active monthly', moneyPaise(monthlyTotal)),
            MiniStat(
              'Active slots',
              scopedFlatId == null
                  ? 'Select a flat'
                  : '$activeCount/$kMaxActiveAdditionalServicesPerFlat',
            ),
          ]),
          if (atCap) ...[
            const SizedBox(height: 10),
            const InfoNote(kAdditionalServiceLimitMessage, tone: NoteTone.warning),
          ],
          const SizedBox(height: 10),
          FilterBar(children: [
            AppFilterChip(
              label: 'All wings',
              selected: wingId == null,
              onSelected: () {
                wingId = null;
                flatId = null;
                reload();
              },
            ),
            for (final wing in loaded.wings)
              AppFilterChip(
                label: 'Wing ${wing.code}',
                selected: wingId == wing.id,
                onSelected: () {
                  wingId = wing.id;
                  flatId = null;
                  reload();
                },
              ),
          ]),
          const SizedBox(height: 8),
          _FlatPicker(
            flats: loaded.flats,
            selectedFlatId: widget.initialFlatId ?? flatId,
            enabled: widget.initialFlatId == null,
            onChanged: (id) {
              flatId = id;
              reload();
            },
          ),
          const SizedBox(height: 8),
          FilterBar(children: [
            AppFilterChip(
              label: 'Active',
              selected: activeOnly == true,
              onSelected: () {
                activeOnly = true;
                reload();
              },
            ),
            AppFilterChip(
              label: 'All statuses',
              selected: activeOnly == null,
              onSelected: () {
                activeOnly = null;
                reload();
              },
            ),
          ]),
          ResultCount(loaded.services.pagination.total, 'service'),
          if (rows.isEmpty)
            EmptyState(
              'No additional services yet',
              icon: Icons.local_parking_outlined,
              actionLabel: atCap ? null : 'Add service',
              onAction: atCap ? null : onAdd,
            )
          else
            ...rows.map(
              (service) => ListRow(
                onTap: () => _openForm(existing: service),
                leading: AppAvatar(
                  icon: Icons.local_parking_outlined,
                  color: service.isActive ? C.blue : C.muted,
                ),
                title: service.name,
                subtitle:
                    '${service.flatLabel}${service.quantity > 1 ? ' · Qty ${service.quantity}' : ''}\n'
                    '${fmtIsoDate(service.effectiveFrom)}'
                    '${service.effectiveTo == null ? '' : ' → ${fmtIsoDate(service.effectiveTo!)}'}',
                badges: [
                  StatusBadge(service.isActive ? 'Active' : 'Inactive',
                      tone: service.isActive
                          ? BadgeTone.success
                          : BadgeTone.neutral),
                ],
                trailing: Text(moneyPaise(service.monthlyTotalPaise),
                    style: T.money.copyWith(fontSize: 14)),
                showChevron: true,
              ),
            ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _ServicesBundle {
  const _ServicesBundle({
    required this.wings,
    required this.flats,
    required this.services,
  });
  final List<WingSummary> wings;
  final List<FlatSummary> flats;
  final Paged<AdditionalService> services;
}

class _FlatPicker extends StatelessWidget {
  const _FlatPicker({
    required this.flats,
    required this.selectedFlatId,
    required this.enabled,
    required this.onChanged,
  });

  final List<FlatSummary> flats;
  final String? selectedFlatId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: selectedFlatId,
      decoration: const InputDecoration(labelText: 'Flat'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All flats'),
        ),
        for (final flat in flats)
          DropdownMenuItem<String?>(
            value: flat.id,
            child: Text(
              flat.label,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

class LiveAdditionalServiceFormPage extends StatefulWidget {
  const LiveAdditionalServiceFormPage({
    super.key,
    this.existing,
    this.presetFlatId,
  });
  final AdditionalService? existing;
  final String? presetFlatId;

  @override
  State<LiveAdditionalServiceFormPage> createState() =>
      _LiveAdditionalServiceFormPageState();
}

class _LiveAdditionalServiceFormPageState
    extends State<LiveAdditionalServiceFormPage> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  final charge = TextEditingController();
  final quantity = TextEditingController(text: '1');
  DateTime effectiveFrom = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime? effectiveTo;
  String? wingId;
  String? flatId;
  bool busy = false;
  String? error;
  late Future<_FormLookups> _lookups = _loadLookups();

  bool get editing => widget.existing != null;

  Future<_FormLookups> _loadLookups() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final wings = await repos.society.wings();
    final flats = await repos.society.listAllFlats(isActive: true);
    return _FormLookups(wings: wings, flats: flats);
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      name.text = existing.name;
      description.text = existing.description ?? '';
      charge.text = paiseToRupeeInput(existing.monthlyChargePaise);
      quantity.text = '${existing.quantity}';
      effectiveFrom = DateTime.tryParse(existing.effectiveFrom) ?? effectiveFrom;
      effectiveTo = existing.effectiveTo == null
          ? null
          : DateTime.tryParse(existing.effectiveTo!);
      flatId = existing.flatId;
    } else {
      flatId = widget.presetFlatId;
    }
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    charge.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    final selectedFlat = flatId;
    if (selectedFlat == null) {
      setState(() => error = 'Select a flat.');
      return;
    }
    final paise = parseRupeesToPaise(charge.text);
    final qty = int.tryParse(quantity.text.trim());
    if (paise == null || qty == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession!;
      final repos = ensureLiveRepositories(session.api);
      if (editing) {
        await repos.billing.updateAdditionalService(
          widget.existing!.id,
          UpdateAdditionalServiceRequest(
            name: name.text.trim(),
            description: description.text.trim().isEmpty
                ? null
                : description.text.trim(),
            monthlyChargePaise: paise,
            quantity: qty,
            effectiveFrom: civilDateToIso(effectiveFrom),
            effectiveTo: effectiveTo == null ? null : civilDateToIso(effectiveTo!),
            clearEffectiveTo: effectiveTo == null,
          ),
        );
      } else {
        final existing = await repos.billing.listAdditionalServices(
          force: true,
          flatId: selectedFlat,
          isActive: true,
          limit: kMaxActiveAdditionalServicesPerFlat,
        );
        if (existing.pagination.total >= kMaxActiveAdditionalServicesPerFlat) {
          throw ApiException(
            code: kAdditionalServiceLimitCode,
            message: kAdditionalServiceLimitMessage,
          );
        }
        await repos.billing.createAdditionalService(
          CreateAdditionalServiceRequest(
            flatId: selectedFlat,
            name: name.text.trim(),
            description: description.text.trim().isEmpty
                ? null
                : description.text.trim(),
            monthlyChargePaise: paise,
            quantity: qty,
            effectiveFrom: civilDateToIso(effectiveFrom),
            effectiveTo: effectiveTo == null ? null : civilDateToIso(effectiveTo!),
          ),
        );
      }
      repos.invalidateAfterFinancialMutation();
      if (!mounted) return;
      showSuccessSnack(
          context, editing ? 'Service updated.' : 'Service added.');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = additionalServiceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _activate() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api).billing.updateAdditionalService(
            existing.id,
            const UpdateAdditionalServiceRequest(isActive: true),
          );
      ensureLiveRepositories(session.api).invalidateAfterFinancialMutation();
      if (!mounted) return;
      showSuccessSnack(context, 'Service activated.');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = additionalServiceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _deactivate() async {
    final existing = widget.existing;
    if (existing == null) return;
    final reason = await promptTextDialog(
      context,
      title: 'Deactivate this service?',
      message:
          'Future bills will stop including ${existing.name}. Historical bills stay unchanged.',
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
          .billing
          .deactivateAdditionalService(existing.id, reason: reason.isEmpty ? null : reason);
      ensureLiveRepositories(session.api).invalidateAfterFinancialMutation();
      if (!mounted) return;
      showAppSnack(context, 'Service deactivated.', tone: SnackTone.warning);
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = additionalServiceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FormLookups>(
      future: _lookups,
      builder: (context, snap) {
        final lookups = snap.data;
        final flats = lookups?.flats ?? const <FlatSummary>[];
        final wings = lookups?.wings ?? const <WingSummary>[];
        final wingFlats = wingId == null
            ? flats
            : flats.where((f) => f.wingId == wingId).toList();
        return FormScaffold(
          title: editing ? 'Edit service' : 'Add additional service',
          formKey: _form,
          bottom: PrimaryButton(
            label: editing ? 'Save changes' : 'Save service',
            icon: Icons.check_rounded,
            busy: busy,
            onPressed: lookups == null ? null : _save,
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
                'Additional services belong to the flat. They recur automatically on future bills while active. Past bills are never changed. Maximum 10 active services per flat.',
              ),
              const SizedBox(height: 16),
              if (!editing) ...[
                const FormSectionLabel('Flat'),
                DropdownButtonFormField<String?>(
                  value: wingId,
                  decoration: const InputDecoration(labelText: 'Wing'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All wings')),
                    for (final wing in wings)
                      DropdownMenuItem<String?>(
                          value: wing.id, child: Text('Wing ${wing.code}')),
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
                        child: Text(flat.number),
                      ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => flatId = v),
                  validator: (v) => v == null ? 'Select a flat.' : null,
                ),
                const SizedBox(height: 16),
              ],
              const FormSectionLabel('Service'),
              TextFormField(
                controller: name,
                enabled: !busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Service name *',
                  hintText: 'Additional car parking',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Service name is required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                enabled: !busy,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: charge,
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monthly charge (₹) *',
                  prefixText: '₹ ',
                ),
                validator: (v) {
                  final paise = parseRupeesToPaise(v ?? '');
                  if (paise == null) return 'Enter a valid rupee amount.';
                  if (paise < 0) return 'Charge cannot be negative.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantity,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Quantity *',
                  helperText: 'Use 2 for two extra parking slots of the same type.',
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1 || n > 99) return 'Enter 1–99.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const FormSectionLabel('Applicability'),
              PickerField(
                label: 'Effective from',
                icon: Icons.event_outlined,
                value: fmtDate(effectiveFrom),
                enabled: !busy,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: effectiveFrom,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => effectiveFrom = picked);
                },
              ),
              const SizedBox(height: 12),
              PickerField(
                label: 'End date (optional)',
                icon: Icons.event_busy_outlined,
                value: effectiveTo == null ? 'Open-ended' : fmtDate(effectiveTo!),
                enabled: !busy,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: effectiveTo ?? effectiveFrom,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => effectiveTo = picked);
                },
              ),
              if (effectiveTo != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy ? null : () => setState(() => effectiveTo = null),
                    child: const Text('Clear end date'),
                  ),
                ),
              if (editing && widget.existing!.isActive) ...[
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Deactivate service',
                  icon: Icons.block_outlined,
                  destructive: true,
                  onPressed: busy ? null : _deactivate,
                ),
              ],
              if (editing && !widget.existing!.isActive) ...[
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Activate service',
                  icon: Icons.check_circle_outline,
                  onPressed: busy ? null : _activate,
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

class _FormLookups {
  const _FormLookups({required this.wings, required this.flats});
  final List<WingSummary> wings;
  final List<FlatSummary> flats;
}

String additionalServiceError(Object error) {
  if (error is ApiException) {
    if (error.code == kAdditionalServiceLimitCode) {
      return kAdditionalServiceLimitMessage;
    }
    return error.message;
  }
  if (error is StateError) return error.message;
  return '$error';
}
