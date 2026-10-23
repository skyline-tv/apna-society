import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/billing_models.dart'
    show CreatePaymentOrderResult, PaymentSettlement, civilDateToIso;
import '../../api/models/collection_models.dart';
import '../../api/models/common.dart';
import '../../api/models/society_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import '../billing/demo_payment_checkout.dart';

String collectionErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'TENANT_BILLING_DENIED':
      case 'GUARD_BILLING_DENIED':
      case 'FINANCIAL_ACCESS_DENIED':
        return 'Financial access is not available for this account.';
      case 'NOT_CHARGE_OWNER':
        return 'Only the assigned owner can view or pay this collection.';
      case 'COLLECTION_NOT_ACTIVE':
      case 'COLLECTION_NOT_EDITABLE':
        return 'This collection is no longer open.';
      case 'COLLECTION_CANCELLED':
        return 'This collection was cancelled.';
      case 'CHARGE_ALREADY_PAID':
        return 'This collection is already fully paid.';
      case 'PARTIAL_PAYMENT_DISABLED':
        return 'Partial payment is not enabled for this collection.';
      case 'DUPLICATE_FLAT_ASSIGNMENT':
        return 'A flat cannot be assigned twice to the same collection.';
      case 'CHARGE_HAS_PAYMENT':
        return 'This flat already has a payment, so it cannot be removed.';
      case 'FLAT_NOT_ASSIGNED':
        return 'That flat is not assigned to this collection.';
      case 'NO_FLATS_ASSIGNED':
        return 'No configured flats matched this assignment.';
      case 'MISSING_FLAT_AMOUNT':
        return 'Enter an amount for the flats you are adding.';
      case 'RECEIPT_NOT_AVAILABLE':
        return 'A receipt is only available after the payment is confirmed.';
      case 'RECEIPT_ACCESS_DENIED':
      case 'PAYMENT_ACCESS_DENIED':
        return 'You do not have access to this receipt.';
      case 'PAYMENTS_LIVE_DISABLED':
        return 'Online payments are not enabled on the server yet.';
      case 'DEMO_PAYMENTS_DISABLED':
        return 'Payment simulation is not available while live payments are enabled.';
      case 'INVALID_GATEWAY_SIGNATURE':
        return 'Payment could not be verified. Contact the society office if money was deducted.';
      case 'OFFLINE_PAYMENTS_DISABLED':
        return 'Offline collection recording is not enabled on the server.';
      case 'ADJUSTMENT_BELOW_PAID':
        return 'The assigned amount cannot go below what has already been paid.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

Future<bool> _removeUnpaidCollectionFlats({
  required BuildContext context,
  required String collectionId,
  List<String>? flatIds,
  List<String>? chargeIds,
  required String confirmTitle,
  required String successMessage,
}) async {
  final ok = await confirmDialog(
    context,
    title: confirmTitle,
    message:
        'This flat will be taken off the collection and will no longer owe this charge. Flats that already paid cannot be removed.',
    confirmLabel: 'Remove',
    destructive: true,
    icon: Icons.delete_outline_rounded,
  );
  if (!ok) return false;
  try {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    await repos.collections.removeFlats(
      collectionId,
      RemoveCollectionFlatsRequest(flatIds: flatIds, chargeIds: chargeIds),
    );
    repos.invalidateAfterFinancialMutation();
    if (context.mounted) showSuccessSnack(context, successMessage);
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnack(context, collectionErrorMessage(e));
    return false;
  }
}

bool _canRemoveCollectionCharge(CollectionCharge row) {
  if (row.amountPaidPaise > 0) return false;
  switch (row.status.toUpperCase()) {
    case 'PAID':
    case 'PARTIALLY_PAID':
    case 'CANCELLED':
      return false;
    default:
      return true;
  }
}

String _collectionStatusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'ACTIVE':
      return 'Active';
    case 'CLOSED':
      return 'Closed';
    case 'CANCELLED':
      return 'Cancelled';
    case 'PENDING':
      return 'Pending';
    case 'PARTIALLY_PAID':
      return 'Partially paid';
    case 'PAID':
      return 'Paid';
    case 'OVERDUE':
      return 'Overdue';
    default:
      return humanizeStatus(status);
  }
}

String _amountModeLabel(String mode) {
  switch (mode.toUpperCase()) {
    case 'PER_FLAT':
      return 'Per-flat amount';
    case 'TOTAL_SPLIT':
      return 'Total split equally';
    case 'CUSTOM':
      return 'Custom per flat';
    default:
      return humanizeStatus(mode);
  }
}

String _assignmentLabel(String type) {
  switch (type.toUpperCase()) {
    case 'ALL_FLATS':
      return 'All society flats';
    case 'WINGS':
      return 'Selected wings';
    case 'SELECTED_FLATS':
      return 'Selected flats';
    default:
      return humanizeStatus(type);
  }
}

bool _isSuccessfulPayment(CollectionPayment payment) =>
    payment.status.toUpperCase() == 'SUCCESS';

class _CollectionPaymentCard extends StatelessWidget {
  const _CollectionPaymentCard({required this.payment, this.onReceipt});
  final CollectionPayment payment;
  final VoidCallback? onReceipt;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final flat = p.displayFlat;
    final status = p.status.toUpperCase();
    final tone = status == 'SUCCESS'
        ? C.green
        : status == 'FAILED'
            ? C.error
            : C.amber;
    return ListRow(
      leading: AppAvatar(
        icon: Icons.payments_outlined,
        color: tone,
        size: 42,
      ),
      title: flat.isNotEmpty ? flat : p.paymentNumber,
      subtitle: [
        if (flat.isNotEmpty) p.paymentNumber,
        humanizeStatus(p.paymentMethod),
        humanizeStatus(p.status),
        if (p.paidAt != null) fmtIsoDateTime(p.paidAt),
      ].join(' · '),
      trailing: Text(moneyPaise(p.amountPaise),
          style: T.money.copyWith(fontSize: 15, color: tone)),
      showChevron: false,
      footer: onReceipt == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onReceipt,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Receipt'),
              ),
            ),
    );
  }
}

CreatePaymentOrderResult _asCheckoutOrder(CollectionPaymentOrderResult order) {
  return CreatePaymentOrderResult(
    paymentId: order.paymentId,
    paymentNumber: order.paymentNumber,
    billId: order.chargeId,
    amountPaise: order.amountPaise,
    order: order.order,
  );
}

Future<void> _shareBytes({
  required List<int> bytes,
  required String filename,
  required String mimeType,
  required String title,
}) {
  return SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: mimeType,
          name: filename,
        ),
      ],
      subject: title,
      text: title,
    ),
  );
}

Future<Uint8List> _collectionReportPdf({
  required CollectionSummary collection,
  required CollectionDashboard dashboard,
  required List<CollectionCharge> charges,
}) {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      build: (_) => [
        pw.Text('APNA SOCIETY',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('One-time collection report',
            style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 12),
        pw.Text('${collection.collectionNumber}  ${collection.title}'),
        pw.Text('Status: ${_collectionStatusLabel(collection.status)}'),
        pw.Text('Due: ${fmtIsoDate(collection.dueDate)}'),
        pw.Text(
            'Expected ${moneyPaise(dashboard.expectedTotalPaise)}  ·  Collected ${moneyPaise(dashboard.collectedPaise)}  ·  Outstanding ${moneyPaise(dashboard.outstandingPaise)}'),
        pw.Text(
            'Flats ${dashboard.assignedFlatCount}  ·  Paid ${dashboard.paidFlats}  ·  Partial ${dashboard.partiallyPaidFlats}  ·  Pending ${dashboard.pendingFlats}  ·  ${dashboard.collectionPercentage.toStringAsFixed(1)}%'),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: const ['Flat', 'Owner', 'Assigned', 'Paid', 'Due', 'Status'],
          data: [
            for (final row in charges)
              [
                row.flatLabel,
                row.ownerNameSnapshot,
                moneyPaise(row.assignedAmountPaise),
                moneyPaise(row.amountPaidPaise),
                moneyPaise(row.outstandingPaise),
                _collectionStatusLabel(row.status),
              ],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Special collections are separate from monthly maintenance. Interest is not applied.',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
  return doc.save();
}

/// Admin list of one-time collections.
class LiveAdminCollectionsPage extends StatefulWidget {
  const LiveAdminCollectionsPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<LiveAdminCollectionsPage> createState() =>
      _LiveAdminCollectionsPageState();
}

class _LiveAdminCollectionsPageState extends State<LiveAdminCollectionsPage> {
  String? statusFilter;
  late Future<Paged<CollectionSummary>> _future = _load();

  Future<Paged<CollectionSummary>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).collections.listAdmin(
          status: statusFilter,
          force: force,
        );
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _create() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveCreateCollectionPage()),
    );
    if (ok == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<Paged<CollectionSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            title: 'Could not load collections',
            onRetry: reload,
          );
        }
        final page = snap.data!;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            reload();
            await _future;
          },
          child: ListView(
            padding: Sp.pagePadding,
            children: [
              const PageHeader(
                'One-time collections',
                subtitle: 'Festival, repair and special charges — not maintenance',
              ),
              PrimaryButton(
                label: 'Create collection',
                icon: Icons.add_rounded,
                onPressed: _create,
              ),
              const SizedBox(height: 14),
              FilterBar(children: [
                for (final s in const [null, 'ACTIVE', 'CLOSED', 'CANCELLED'])
                  AppFilterChip(
                    label: s == null ? 'All' : _collectionStatusLabel(s),
                    selected: statusFilter == s,
                    onSelected: () {
                      statusFilter = s;
                      reload();
                    },
                  ),
              ]),
              const SizedBox(height: 8),
              ResultCount(page.pagination.total, 'collection'),
              if (page.items.isEmpty)
                const EmptyState(
                  'No one-time collections yet',
                  icon: Icons.celebration_outlined,
                )
              else
                ...page.items.map(
                  (row) => AppCard(
                    onTap: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LiveAdminCollectionDetailPage(collectionId: row.id),
                        ),
                      );
                      if (mounted) reload();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(row.title, style: T.bodyStrong),
                          ),
                          StatusBadge(row.status),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          '${row.collectionNumber} · ${row.assignedFlatCount} flats · due ${fmtIsoDate(row.dueDate)}',
                          style: T.caption,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${moneyPaise(row.collectedPaise)} of ${moneyPaise(row.expectedTotalPaise)}  ·  ${row.collectionPercentage.toStringAsFixed(0)}%',
                          style: T.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(body: body);
  }
}

class LiveCreateCollectionPage extends StatefulWidget {
  const LiveCreateCollectionPage({super.key});

  @override
  State<LiveCreateCollectionPage> createState() =>
      _LiveCreateCollectionPageState();
}

class _LiveCreateCollectionPageState extends State<LiveCreateCollectionPage> {
  final _form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final amount = TextEditingController();
  final instructions = TextEditingController();
  DateTime dueDate = DateTime.now().add(const Duration(days: 14));
  DateTime? startDate;
  String amountMode = 'PER_FLAT';
  String assignmentType = 'ALL_FLATS';
  bool allowPartial = false;
  bool busy = false;
  String? error;
  CollectionPreview? preview;
  final selectedWingIds = <String>{};
  final selectedFlatIds = <String>{};
  final customAmounts = <String, int>{};
  late Future<_CreateLookups> _lookups = _loadLookups();

  Future<_CreateLookups> _loadLookups() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final wings = await repos.society.wings();
    final flats = await repos.society.listAllFlats(isActive: true);
    return _CreateLookups(wings: wings, flats: flats);
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    amount.dispose();
    instructions.dispose();
    super.dispose();
  }

  CreateCollectionRequest? _request() {
    if (!(_form.currentState?.validate() ?? false)) return null;
    final paise = amountMode == 'CUSTOM' ? null : parseRupeesToPaise(amount.text);
    if (amountMode != 'CUSTOM' && (paise == null || paise <= 0)) {
      setState(() => error = 'Enter a valid amount.');
      return null;
    }
    if (assignmentType == 'WINGS' && selectedWingIds.isEmpty) {
      setState(() => error = 'Select at least one wing.');
      return null;
    }
    if (assignmentType == 'SELECTED_FLATS' && selectedFlatIds.isEmpty) {
      setState(() => error = 'Select at least one flat.');
      return null;
    }
    List<Map<String, Object?>>? flatAmounts;
    if (amountMode == 'CUSTOM') {
      final ids = assignmentType == 'ALL_FLATS'
          ? null
          : selectedFlatIds;
      final source = ids ?? customAmounts.keys;
      flatAmounts = [
        for (final id in source)
          if (customAmounts[id] != null && customAmounts[id]! > 0)
            {'flatId': id, 'amountPaise': customAmounts[id]},
      ];
      if (flatAmounts.isEmpty) {
        setState(() => error = 'Enter a custom amount for each selected flat.');
        return null;
      }
    }
    return CreateCollectionRequest(
      title: title.text.trim(),
      description: description.text.trim(),
      amountMode: amountMode,
      assignmentType: assignmentType,
      amountPaise: paise,
      wingIds: assignmentType == 'WINGS' ? selectedWingIds.toList() : null,
      flatIds: assignmentType == 'SELECTED_FLATS' ? selectedFlatIds.toList() : null,
      flatAmounts: flatAmounts,
      dueDate: civilDateToIso(dueDate),
      startDate: startDate == null ? null : civilDateToIso(startDate!),
      paymentInstructions:
          instructions.text.trim().isEmpty ? null : instructions.text.trim(),
      allowPartialPayment: allowPartial,
    );
  }

  Future<void> _preview() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final request = _request();
    if (request == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession!;
      final result =
          await ensureLiveRepositories(session.api).collections.preview(request);
      if (!mounted) return;
      setState(() => preview = result);
    } catch (e) {
      setState(() => error = collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _create() async {
    final request = _request();
    if (request == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession!;
      final repos = ensureLiveRepositories(session.api);
      await repos.collections.create(request);
      repos.invalidateAfterFinancialMutation();
      if (!mounted) return;
      showSuccessSnack(context, 'Collection created.');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? (startDate ?? DateTime.now()) : dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        startDate = picked;
      } else {
        dueDate = picked;
      }
      preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CreateLookups>(
      future: _lookups,
      builder: (context, snap) {
        final lookups = snap.data;
        final wings = lookups?.wings ?? const <WingSummary>[];
        final flats = lookups?.flats ?? const <FlatSummary>[];
        return FormScaffold(
          title: 'Create collection',
          formKey: _form,
          bottom: PrimaryButton(
            label: preview == null ? 'Preview assignment' : 'Confirm & create',
            icon: preview == null ? Icons.preview_outlined : Icons.check_rounded,
            busy: busy,
            onPressed: lookups == null
                ? null
                : preview == null
                    ? _preview
                    : _create,
          ),
          children: [
            if (snap.hasError)
              LoadFailure(
                error: snap.error!,
                title: 'Could not load flats',
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
                'One-time collections are separate from monthly maintenance. They do not use the 24% interest rule and never merge into maintenance bills. Vacant and unassigned flats are included when you select them.',
              ),
              const SizedBox(height: 16),
              const FormSectionLabel('Collection'),
              TextFormField(
                controller: title,
                enabled: !busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'Diwali celebration collection',
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 3 ? 'Enter a title.' : null,
                onChanged: (_) => setState(() => preview = null),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                enabled: !busy,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description *'),
                validator: (v) =>
                    (v ?? '').trim().length < 3 ? 'Enter a description.' : null,
                onChanged: (_) => setState(() => preview = null),
              ),
              const SizedBox(height: 16),
              const FormSectionLabel('Assignment'),
              ScaleToWidth(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ALL_FLATS', label: Text('All flats')),
                    ButtonSegment(value: 'WINGS', label: Text('Wings')),
                    ButtonSegment(value: 'SELECTED_FLATS', label: Text('Flats')),
                  ],
                  selected: {assignmentType},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() {
                            assignmentType = v.first;
                            preview = null;
                          }),
                ),
              ),
              if (assignmentType == 'WINGS') ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final wing in wings)
                      FilterChip(
                        label: Text('Wing ${wing.code}'),
                        selected: selectedWingIds.contains(wing.id),
                        onSelected: busy
                            ? null
                            : (on) => setState(() {
                                  if (on) {
                                    selectedWingIds.add(wing.id);
                                  } else {
                                    selectedWingIds.remove(wing.id);
                                  }
                                  preview = null;
                                }),
                      ),
                  ],
                ),
              ],
              if (assignmentType == 'SELECTED_FLATS') ...[
                const SizedBox(height: 12),
                PickerField(
                  label: 'Flats',
                  icon: Icons.apartment_outlined,
                  value: selectedFlatIds.isEmpty
                      ? 'Select flats'
                      : '${selectedFlatIds.length} selected',
                  enabled: !busy,
                  onTap: () async {
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (ctx) {
                        var query = '';
                        return StatefulBuilder(
                          builder: (ctx, setSheet) {
                            final filtered = flats
                                .where((f) =>
                                    query.isEmpty ||
                                    f.label
                                        .toLowerCase()
                                        .contains(query.toLowerCase()) ||
                                    f.number
                                        .toLowerCase()
                                        .contains(query.toLowerCase()))
                                .toList();
                            return SizedBox(
                              height: MediaQuery.of(ctx).size.height * 0.75,
                              child: Column(children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  child: SearchField(
                                    hint: 'Search flats',
                                    onChanged: (v) =>
                                        setSheet(() => query = v.trim()),
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (_, i) {
                                      final flat = filtered[i];
                                      final selected =
                                          selectedFlatIds.contains(flat.id);
                                      return CheckboxListTile(
                                        value: selected,
                                        title: Text(flat.label),
                                        subtitle: Text(
                                          '${humanizeStatus(flat.occupancyStatus)} · ${flat.activeOwner?.name ?? 'Unassigned'}',
                                        ),
                                        onChanged: (on) {
                                          setSheet(() {
                                            if (on == true) {
                                              selectedFlatIds.add(flat.id);
                                            } else {
                                              selectedFlatIds.remove(flat.id);
                                              customAmounts.remove(flat.id);
                                            }
                                          });
                                          setState(() => preview = null);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ]),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              const FormSectionLabel('Amount'),
              ScaleToWidth(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'PER_FLAT', label: Text('Per flat')),
                    ButtonSegment(value: 'TOTAL_SPLIT', label: Text('Total split')),
                    ButtonSegment(value: 'CUSTOM', label: Text('Custom')),
                  ],
                  selected: {amountMode},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() {
                            amountMode = v.first;
                            preview = null;
                          }),
                ),
              ),
              if (amountMode != 'CUSTOM') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: amount,
                  enabled: !busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: amountMode == 'TOTAL_SPLIT'
                        ? 'Total amount (₹) *'
                        : 'Amount per flat (₹) *',
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    if (amountMode == 'CUSTOM') return null;
                    final paise = parseRupeesToPaise(v ?? '');
                    if (paise == null || paise <= 0) {
                      return 'Enter a valid rupee amount.';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() => preview = null),
                ),
              ] else ...[
                const SizedBox(height: 12),
                const InfoNote(
                    'Enter a rupee amount for each selected flat. Vacant flats can still be charged.'),
                const SizedBox(height: 8),
                ...flats
                    .where((f) =>
                        assignmentType == 'ALL_FLATS' ||
                        selectedFlatIds.contains(f.id) ||
                        (assignmentType == 'WINGS' &&
                            selectedWingIds.contains(f.wingId)))
                    .take(160)
                    .map(
                      (flat) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextFormField(
                          initialValue: customAmounts[flat.id] == null
                              ? ''
                              : paiseToRupeeInput(customAmounts[flat.id]!),
                          enabled: !busy,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: '${flat.label} (₹)',
                            prefixText: '₹ ',
                          ),
                          onChanged: (v) {
                            final paise = parseRupeesToPaise(v);
                            setState(() {
                              if (paise == null || paise <= 0) {
                                customAmounts.remove(flat.id);
                              } else {
                                customAmounts[flat.id] = paise;
                              }
                              preview = null;
                            });
                          },
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 16),
              const FormSectionLabel('Schedule'),
              PickerField(
                label: 'Due date',
                icon: Icons.event_outlined,
                value: fmtIsoDate(civilDateToIso(dueDate)),
                enabled: !busy,
                onTap: () => _pickDate(start: false),
              ),
              const SizedBox(height: 10),
              PickerField(
                label: 'Start date (optional)',
                icon: Icons.play_circle_outline_rounded,
                value: startDate == null
                    ? 'Not set'
                    : fmtIsoDate(civilDateToIso(startDate!)),
                enabled: !busy,
                onTap: () => _pickDate(start: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: instructions,
                enabled: !busy,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Payment instructions'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow partial payments'),
                subtitle: const Text(
                    'Residents may pay less than the full assigned amount'),
                value: allowPartial,
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                          allowPartial = v;
                          preview = null;
                        }),
              ),
              if (preview != null) ...[
                const SizedBox(height: 8),
                const SectionTitle('Preview'),
                DetailCard(children: [
                  DetailRow('Assigned flats', '${preview!.assignedFlatCount}'),
                  DetailRow(
                    'Amount per flat',
                    preview!.defaultAmountPaise > 0
                        ? moneyPaise(preview!.defaultAmountPaise)
                        : 'Varies',
                  ),
                  DetailRow(
                    'Total expected',
                    moneyPaise(preview!.expectedTotalPaise),
                    emphasize: true,
                  ),
                  DetailRow('Method', _assignmentLabel(preview!.assignmentType)),
                ]),
                const SizedBox(height: 8),
                ...preview!.allocations.take(12).map(
                      (row) => DetailRow(
                        row.flatLabel,
                        '${moneyPaise(row.amountPaise)} · ${humanizeStatus(row.occupancyStatus)}',
                      ),
                    ),
                if (preview!.allocations.length > 12)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+ ${preview!.allocations.length - 12} more flats',
                      style: T.caption,
                    ),
                  ),
                SecondaryButton(
                  label: 'Edit details',
                  onPressed: busy ? null : () => setState(() => preview = null),
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

class _CreateLookups {
  const _CreateLookups({required this.wings, required this.flats});
  final List<WingSummary> wings;
  final List<FlatSummary> flats;
}

class LiveEditCollectionPage extends StatefulWidget {
  const LiveEditCollectionPage({super.key, required this.collection});
  final CollectionSummary collection;

  @override
  State<LiveEditCollectionPage> createState() => _LiveEditCollectionPageState();
}

class _LiveEditCollectionPageState extends State<LiveEditCollectionPage> {
  final _form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.collection.title);
  late final description =
      TextEditingController(text: widget.collection.description);
  late final instructions =
      TextEditingController(text: widget.collection.paymentInstructions ?? '');
  late final addAmount = TextEditingController(
    text: widget.collection.amountPaise > 0
        ? paiseToRupeeInput(widget.collection.amountPaise)
        : '',
  );
  late DateTime dueDate =
      DateTime.tryParse(widget.collection.dueDate) ?? DateTime.now();
  late bool allowPartial = widget.collection.allowPartialPayment;
  bool busy = false;
  bool addingFlats = false;
  bool removingFlats = false;
  String? error;
  bool includeRemaining = false;
  final selectedWingIds = <String>{};
  final selectedFlatIds = <String>{};
  final selectedRemoveFlatIds = <String>{};
  CollectionPreview? addPreview;
  late Future<_EditLookups> _lookups = _loadLookups();

  Future<_EditLookups> _loadLookups() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final wings = await repos.society.wings();
    final flats = await repos.society.listAllFlats(isActive: true);
    final assigned = await repos.collections.listCharges(
      widget.collection.id,
      query: const CollectionChargeQuery(limit: 200),
    );
    return _EditLookups(
      wings: wings,
      flats: flats,
      assignedCharges: assigned.items,
      assignedFlatIds: assigned.items.map((row) => row.flatId).toSet(),
    );
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    instructions.dispose();
    addAmount.dispose();
    super.dispose();
  }

  AddCollectionFlatsRequest? _addRequest() {
    if (includeRemaining) {
      return AddCollectionFlatsRequest(
        includeRemaining: true,
        amountPaise: parseRupeesToPaise(addAmount.text),
      );
    }
    if (selectedWingIds.isEmpty && selectedFlatIds.isEmpty) {
      setState(() => error = 'Select flats or wings to add.');
      return null;
    }
    final paise = parseRupeesToPaise(addAmount.text);
    if (paise == null || paise <= 0) {
      setState(() => error = 'Enter an amount for the new flats.');
      return null;
    }
    return AddCollectionFlatsRequest(
      wingIds: selectedWingIds.isEmpty ? null : selectedWingIds.toList(),
      flatIds: selectedFlatIds.isEmpty ? null : selectedFlatIds.toList(),
      amountPaise: paise,
    );
  }

  Future<void> _previewAdd() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final request = _addRequest();
    if (request == null) return;
    setState(() {
      addingFlats = true;
      error = null;
    });
    try {
      final preview = await ensureLiveRepositories(authSession!.api)
          .collections
          .previewAddFlats(widget.collection.id, request);
      if (!mounted) return;
      setState(() => addPreview = preview);
    } catch (e) {
      setState(() => error = collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => addingFlats = false);
    }
  }

  Future<void> _confirmAdd() async {
    final request = _addRequest();
    if (request == null) return;
    setState(() {
      addingFlats = true;
      error = null;
    });
    try {
      final session = authSession!;
      final repos = ensureLiveRepositories(session.api);
      if (_form.currentState?.validate() ?? false) {
        await repos.collections.update(
          widget.collection.id,
          title: title.text.trim(),
          description: description.text.trim(),
          dueDate: civilDateToIso(dueDate),
          paymentInstructions: instructions.text.trim(),
          allowPartialPayment: allowPartial,
        );
      }
      await repos.collections.addFlats(widget.collection.id, request);
      repos.invalidateAfterFinancialMutation();
      if (!mounted) return;
      showSuccessSnack(
        context,
        addPreview == null
            ? 'Flats added to the collection.'
            : '${addPreview!.assignedFlatCount} flats added.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => addingFlats = false);
    }
  }

  Future<void> _confirmRemove() async {
    if (selectedRemoveFlatIds.isEmpty) {
      setState(() => error = 'Select unpaid flats to remove.');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Remove ${selectedRemoveFlatIds.length} unpaid ${selectedRemoveFlatIds.length == 1 ? 'flat' : 'flats'}?',
      message:
          'Those flats will be taken off this collection and will no longer owe this charge. Flats that already paid stay.',
      confirmLabel: 'Remove flats',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() {
      removingFlats = true;
      error = null;
    });
    try {
      final session = authSession!;
      final repos = ensureLiveRepositories(session.api);
      await repos.collections.removeFlats(
        widget.collection.id,
        RemoveCollectionFlatsRequest(
          flatIds: selectedRemoveFlatIds.toList(),
        ),
      );
      repos.invalidateAfterFinancialMutation();
      if (!mounted) return;
      showSuccessSnack(
        context,
        selectedRemoveFlatIds.length == 1
            ? 'Flat removed from the collection.'
            : '${selectedRemoveFlatIds.length} flats removed.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => removingFlats = false);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api).collections.update(
            widget.collection.id,
            title: title.text.trim(),
            description: description.text.trim(),
            dueDate: civilDateToIso(dueDate),
            paymentInstructions: instructions.text.trim(),
            allowPartialPayment: allowPartial,
          );
      if (!mounted) return;
      showSuccessSnack(context, 'Collection updated.');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickRemovable(List<CollectionCharge> removable) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final filtered = removable
                .where((row) =>
                    query.isEmpty ||
                    row.flatLabel.toLowerCase().contains(query.toLowerCase()) ||
                    row.ownerNameSnapshot
                        .toLowerCase()
                        .contains(query.toLowerCase()))
                .toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchField(
                    hint: 'Search unpaid flats',
                    onChanged: (v) => setSheet(() => query = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final row = filtered[i];
                      final selected =
                          selectedRemoveFlatIds.contains(row.flatId);
                      return CheckboxListTile(
                        value: selected,
                        title: Text(row.flatLabel),
                        subtitle: Text(
                          '${moneyPaise(row.assignedAmountPaise)} · ${row.ownerNameSnapshot}',
                        ),
                        onChanged: (on) {
                          setSheet(() {
                            if (on == true) {
                              selectedRemoveFlatIds.add(row.flatId);
                            } else {
                              selectedRemoveFlatIds.remove(row.flatId);
                            }
                          });
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _pickFlats(List<FlatSummary> available) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final filtered = available
                .where((f) =>
                    query.isEmpty ||
                    f.label.toLowerCase().contains(query.toLowerCase()) ||
                    f.number.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchField(
                    hint: 'Search unassigned flats',
                    onChanged: (v) => setSheet(() => query = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final flat = filtered[i];
                      final selected = selectedFlatIds.contains(flat.id);
                      return CheckboxListTile(
                        value: selected,
                        title: Text(flat.label),
                        subtitle: Text(
                          '${humanizeStatus(flat.occupancyStatus)} · ${flat.activeOwner?.name ?? 'Unassigned'}',
                        ),
                        onChanged: (on) {
                          setSheet(() {
                            if (on == true) {
                              selectedFlatIds.add(flat.id);
                            } else {
                              selectedFlatIds.remove(flat.id);
                            }
                          });
                          setState(() => addPreview = null);
                        },
                      );
                    },
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EditLookups>(
      future: _lookups,
      builder: (context, snap) {
        final lookups = snap.data;
        final available = lookups == null
            ? const <FlatSummary>[]
            : lookups.flats
                .where((flat) => !lookups.assignedFlatIds.contains(flat.id))
                .toList();
        final removable = lookups == null
            ? const <CollectionCharge>[]
            : lookups.assignedCharges
                .where(_canRemoveCollectionCharge)
                .toList();
        final paidCount = lookups == null
            ? 0
            : lookups.assignedCharges.length - removable.length;
        return FormScaffold(
          title: 'Edit collection',
          formKey: _form,
          bottom: PrimaryButton(
            label: 'Save changes',
            icon: Icons.check_rounded,
            busy: busy,
            onPressed: busy || addingFlats || removingFlats ? null : _save,
          ),
          children: [
            const InfoNote(
              'Existing paid amounts stay unchanged. Add more flats, or remove unpaid flats before any payment is recorded.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: title,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Title *'),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Enter a title.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              enabled: !busy,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description *'),
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Enter a description.' : null,
            ),
            const SizedBox(height: 12),
            PickerField(
              label: 'Due date',
              icon: Icons.event_outlined,
              value: fmtIsoDate(civilDateToIso(dueDate)),
              enabled: !busy,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: dueDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => dueDate = picked);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: instructions,
              enabled: !busy,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Payment instructions'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow partial payments'),
              value: allowPartial,
              onChanged: busy ? null : (v) => setState(() => allowPartial = v),
            ),
            const SizedBox(height: 8),
            const SectionTitle('Add more flats'),
            if (snap.hasError)
              LoadFailure(
                error: snap.error!,
                title: 'Could not load flats',
                compact: true,
                onRetry: () => setState(() => _lookups = _loadLookups()),
              )
            else if (lookups == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LoadingView(label: 'Loading flats…'),
              )
            else if (available.isEmpty)
              const InfoNote(
                'Every configured flat is already on this collection.',
              )
            else ...[
              Text(
                '${lookups.assignedFlatIds.length} flats already assigned · ${available.length} can still be added',
                style: T.caption,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add all remaining society flats'),
                subtitle: const Text(
                    'Includes vacant and unassigned flats that are not already on this collection'),
                value: includeRemaining,
                onChanged: addingFlats
                    ? null
                    : (v) => setState(() {
                          includeRemaining = v;
                          addPreview = null;
                        }),
              ),
              if (!includeRemaining) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final wing in lookups.wings)
                      FilterChip(
                        label: Text('Wing ${wing.code}'),
                        selected: selectedWingIds.contains(wing.id),
                        onSelected: addingFlats
                            ? null
                            : (on) => setState(() {
                                  if (on) {
                                    selectedWingIds.add(wing.id);
                                  } else {
                                    selectedWingIds.remove(wing.id);
                                  }
                                  addPreview = null;
                                }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: 'Additional flats',
                  icon: Icons.apartment_outlined,
                  value: selectedFlatIds.isEmpty
                      ? 'Select flats'
                      : '${selectedFlatIds.length} selected',
                  enabled: !addingFlats,
                  onTap: () => _pickFlats(available),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: addAmount,
                enabled: !addingFlats,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount for new flats (₹)',
                  prefixText: '₹ ',
                ),
                onChanged: (_) => setState(() => addPreview = null),
              ),
              const SizedBox(height: 12),
              if (addPreview == null)
                SecondaryButton(
                  label: 'Preview new flats',
                  icon: Icons.preview_outlined,
                  busy: addingFlats,
                  onPressed: addingFlats ? null : _previewAdd,
                )
              else ...[
                DetailCard(children: [
                  DetailRow('New flats', '${addPreview!.assignedFlatCount}'),
                  DetailRow(
                    'Amount per flat',
                    addPreview!.defaultAmountPaise > 0
                        ? moneyPaise(addPreview!.defaultAmountPaise)
                        : 'Varies',
                  ),
                  DetailRow(
                    'Added expected total',
                    moneyPaise(addPreview!.expectedTotalPaise),
                    emphasize: true,
                  ),
                  if (addPreview!.skippedAssignedCount > 0)
                    DetailRow(
                      'Already assigned (skipped)',
                      '${addPreview!.skippedAssignedCount}',
                    ),
                ]),
                const SizedBox(height: 8),
                ...addPreview!.allocations.take(12).map(
                      (row) => DetailRow(
                        row.flatLabel,
                        '${moneyPaise(row.amountPaise)} · ${humanizeStatus(row.occupancyStatus)}',
                      ),
                    ),
                if (addPreview!.allocations.length > 12)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(
                      '+ ${addPreview!.allocations.length - 12} more flats',
                      style: T.caption,
                    ),
                  ),
                PrimaryButton(
                  label: 'Add ${addPreview!.assignedFlatCount} flats',
                  icon: Icons.add_rounded,
                  busy: addingFlats,
                  onPressed: addingFlats ? null : _confirmAdd,
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  label: 'Change selection',
                  onPressed: addingFlats
                      ? null
                      : () => setState(() => addPreview = null),
                ),
              ],
            ],
            if (lookups != null) ...[
              const SizedBox(height: 20),
              const SectionTitle('Remove unpaid flats'),
              if (removable.isEmpty)
                InfoNote(
                  paidCount == 0
                      ? 'No flats are assigned yet.'
                      : 'Every assigned flat already has a payment, so none can be removed.',
                )
              else ...[
                Text(
                  '${removable.length} unpaid ${removable.length == 1 ? 'flat' : 'flats'} can be removed'
                  '${paidCount > 0 ? ' · $paidCount already paid stay on the collection' : ''}',
                  style: T.caption,
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: 'Unpaid flats to remove',
                  icon: Icons.delete_outline_rounded,
                  value: selectedRemoveFlatIds.isEmpty
                      ? 'Select flats'
                      : '${selectedRemoveFlatIds.length} selected',
                  enabled: !removingFlats,
                  onTap: () => _pickRemovable(removable),
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: selectedRemoveFlatIds.isEmpty
                      ? 'Remove selected flats'
                      : 'Remove ${selectedRemoveFlatIds.length} unpaid ${selectedRemoveFlatIds.length == 1 ? 'flat' : 'flats'}',
                  icon: Icons.delete_outline_rounded,
                  busy: removingFlats,
                  onPressed: removingFlats || selectedRemoveFlatIds.isEmpty
                      ? null
                      : _confirmRemove,
                ),
              ],
            ],
            InlineError(error),
          ],
        );
      },
    );
  }
}

class _EditLookups {
  const _EditLookups({
    required this.wings,
    required this.flats,
    required this.assignedCharges,
    required this.assignedFlatIds,
  });
  final List<WingSummary> wings;
  final List<FlatSummary> flats;
  final List<CollectionCharge> assignedCharges;
  final Set<String> assignedFlatIds;
}

class LiveAdminCollectionDetailPage extends StatefulWidget {
  const LiveAdminCollectionDetailPage({super.key, required this.collectionId});
  final String collectionId;

  @override
  State<LiveAdminCollectionDetailPage> createState() =>
      _LiveAdminCollectionDetailPageState();
}

class _LiveAdminCollectionDetailPageState
    extends State<LiveAdminCollectionDetailPage> {
  late Future<_AdminCollectionBundle> _future = _load();
  String? statusFilter;
  String? wingFilter;
  String search = '';
  int page = 1;
  bool exporting = false;

  Future<_AdminCollectionBundle> _load() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final collection = await repos.collections.adminCollection(widget.collectionId);
    final dashboard = collection.dashboard ??
        await repos.collections.dashboard(widget.collectionId);
    final charges = await repos.collections.listCharges(
      widget.collectionId,
      query: CollectionChargeQuery(
        status: statusFilter,
        wingCode: wingFilter,
        search: search.isEmpty ? null : search,
        page: page,
        limit: 50,
      ),
    );
    final payments = await repos.collections.listAdminPayments(widget.collectionId);
    final wings = await repos.society.wings();
    return _AdminCollectionBundle(
      collection: collection,
      dashboard: dashboard,
      charges: charges,
      payments: payments,
      wings: wings,
    );
  }

  void reload({bool resetPage = false}) {
    if (resetPage) page = 1;
    setState(() => _future = _load());
  }

  Future<void> _exportCsv() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final session = authSession!;
      final bytes = await ensureLiveRepositories(session.api)
          .collections
          .exportChargesCsv(widget.collectionId);
      await _shareBytes(
        bytes: bytes,
        filename: 'collection-${widget.collectionId}.csv',
        mimeType: 'text/csv',
        title: 'Collection report (CSV / Excel)',
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _exportPdf(_AdminCollectionBundle bundle) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final session = authSession!;
      final all = await ensureLiveRepositories(session.api).collections.listCharges(
            widget.collectionId,
            query: const CollectionChargeQuery(limit: 200),
          );
      final bytes = await _collectionReportPdf(
        collection: bundle.collection,
        dashboard: bundle.dashboard,
        charges: all.items,
      );
      await Printing.layoutPdf(
        name: '${bundle.collection.collectionNumber}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _close() async {
    final ok = await confirmDialog(
      context,
      title: 'Close this collection?',
      message:
          'No new payments will be accepted. Existing payments and receipts are kept.',
      confirmLabel: 'Close collection',
    );
    if (!ok || !mounted) return;
    try {
      await ensureLiveRepositories(authSession!.api)
          .collections
          .close(widget.collectionId);
      if (!mounted) return;
      showSuccessSnack(context, 'Collection closed.');
      reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, collectionErrorMessage(e));
    }
  }

  Future<void> _cancel() async {
    final reason = await promptTextDialog(
      context,
      title: 'Cancel this collection?',
      message:
          'Unpaid charges are cancelled. Paid amounts, receipts and history are preserved.',
      label: 'Reason',
      confirmLabel: 'Cancel collection',
      destructive: true,
    );
    if (reason == null || reason.trim().length < 3 || !mounted) return;
    try {
      await ensureLiveRepositories(authSession!.api)
          .collections
          .cancel(widget.collectionId, reason: reason.trim());
      if (!mounted) return;
      showAppSnack(context, 'Collection cancelled.', tone: SnackTone.warning);
      reload();
    } catch (e) {
      if (mounted) showErrorSnack(context, collectionErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collection')),
      body: FutureBuilder<_AdminCollectionBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const LoadingView(label: 'Loading collection…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              title: 'Could not load collection',
              onRetry: reload,
            );
          }
          final bundle = snap.data!;
          final c = bundle.collection;
          final d = bundle.dashboard;
          final pct = d.collectionPercentage.clamp(0, 100);
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              reload();
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                Row(children: [
                  Expanded(child: Text(c.title, style: T.h2)),
                  StatusBadge(c.status),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${c.collectionNumber} · ${_amountModeLabel(c.amountMode)} · ${_assignmentLabel(c.assignmentType)}',
                  style: T.secondary,
                ),
                const SizedBox(height: 12),
                HeroMoneyCard(
                  label: 'Expected collection',
                  amount: moneyPaise(d.expectedTotalPaise),
                  subtitle:
                      '${moneyPaise(d.collectedPaise)} collected · ${moneyPaise(d.outstandingPaise)} outstanding',
                ),
                const SizedBox(height: 12),
                CollectionBar(
                  title: 'Collection',
                  progress: pct / 100,
                  valueLabel: '${pct.toStringAsFixed(0)}%',
                  caption:
                      '${d.paidFlats} paid · ${d.partiallyPaidFlats} partial · ${d.pendingFlats} pending · ${d.overdueFlats} overdue',
                ),
                const SizedBox(height: 12),
                StatGrid(children: [
                  StatCard(
                    title: 'Assigned flats',
                    value: '${d.assignedFlatCount}',
                    icon: Icons.apartment_outlined,
                  ),
                  StatCard(
                    title: 'Collected',
                    value: moneyPaise(d.collectedPaise),
                    icon: Icons.payments_outlined,
                    accent: C.green,
                  ),
                  StatCard(
                    title: 'Outstanding',
                    value: moneyPaise(d.outstandingPaise),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  StatCard(
                    title: 'Fully paid',
                    value: '${d.paidFlats}',
                    icon: Icons.check_circle_outline_rounded,
                    accent: C.green,
                    caption: '${d.partiallyPaidFlats} partial',
                  ),
                ]),
                const SizedBox(height: 12),
                DetailCard(children: [
                  DetailRow('Due date', fmtIsoDate(c.dueDate)),
                  if (c.startDate != null)
                    DetailRow('Start date', fmtIsoDate(c.startDate)),
                  DetailRow('Partial payments',
                      c.allowPartialPayment ? 'Allowed' : 'Full amount only'),
                  if (c.paymentInstructions != null)
                    DetailRow('Instructions', c.paymentInstructions!),
                  if (c.description.isNotEmpty)
                    DetailRow('Description', c.description),
                ]),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SecondaryButton(
                      label: 'CSV / Excel',
                      icon: Icons.table_view_outlined,
                      busy: exporting,
                      expand: false,
                      onPressed: _exportCsv,
                    ),
                    SecondaryButton(
                      label: 'PDF report',
                      icon: Icons.picture_as_pdf_outlined,
                      busy: exporting,
                      expand: false,
                      onPressed: () => _exportPdf(bundle),
                    ),
                    if (c.status == 'ACTIVE') ...[
                      SecondaryButton(
                        label: 'Edit',
                        expand: false,
                        onPressed: () async {
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LiveEditCollectionPage(collection: c),
                            ),
                          );
                          if (ok == true && mounted) reload();
                        },
                      ),
                      SecondaryButton(
                        label: 'Close',
                        expand: false,
                        onPressed: _close,
                      ),
                      SecondaryButton(
                        label: 'Cancel',
                        expand: false,
                        onPressed: _cancel,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                const SectionTitle('Flat-wise details'),
                SearchField(
                  hint: 'Search flat or owner',
                  onSubmitted: (v) {
                    search = v.trim();
                    reload(resetPage: true);
                  },
                ),
                const SizedBox(height: 8),
                FilterBar(children: [
                  for (final s in const [
                    null,
                    'PAID',
                    'PARTIALLY_PAID',
                    'PENDING',
                    'OVERDUE',
                  ])
                    AppFilterChip(
                      label: s == null ? 'All' : _collectionStatusLabel(s),
                      selected: statusFilter == s,
                      onSelected: () {
                        statusFilter = s;
                        reload(resetPage: true);
                      },
                    ),
                ]),
                const SizedBox(height: 8),
                FilterBar(children: [
                  AppFilterChip(
                    label: 'All wings',
                    selected: wingFilter == null,
                    onSelected: () {
                      wingFilter = null;
                      reload(resetPage: true);
                    },
                  ),
                  for (final wing in bundle.wings)
                    AppFilterChip(
                      label: 'Wing ${wing.code}',
                      selected: wingFilter == wing.code,
                      onSelected: () {
                        wingFilter = wing.code;
                        reload(resetPage: true);
                      },
                    ),
                ]),
                ResultCount(bundle.charges.pagination.total, 'flat'),
                if (bundle.charges.items.isEmpty)
                  const EmptyState('No flats match these filters',
                      icon: Icons.apartment_outlined, compact: true)
                else
                  ...bundle.charges.items.map(
                    (row) => AppCard(
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveAdminCollectionChargePage(
                              collectionId: widget.collectionId,
                              charge: row,
                              allowPartial: c.allowPartialPayment,
                              collectionActive: c.status == 'ACTIVE',
                            ),
                          ),
                        );
                        if (mounted) reload();
                      },
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.flatLabel, style: T.bodyStrong),
                              Text(
                                '${row.ownerNameSnapshot} · ${humanizeStatus(row.occupancyStatusSnapshot)}',
                                style: T.caption,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(moneyPaise(row.outstandingPaise),
                                style: T.bodyStrong),
                            StatusBadge(row.status),
                          ],
                        ),
                        if (c.status == 'ACTIVE' &&
                            _canRemoveCollectionCharge(row))
                          IconButton(
                            tooltip: 'Remove unpaid flat',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final removed = await _removeUnpaidCollectionFlats(
                                context: context,
                                collectionId: widget.collectionId,
                                chargeIds: [row.id],
                                confirmTitle: 'Remove ${row.flatLabel}?',
                                successMessage:
                                    '${row.flatLabel} removed from the collection.',
                              );
                              if (removed && mounted) reload();
                            },
                          ),
                      ]),
                    ),
                  ),
                PaginationBar(
                  page: bundle.charges.pagination.page,
                  totalPages: bundle.charges.pagination.totalPages,
                  onPrevious: () {
                    page -= 1;
                    reload();
                  },
                  onNext: () {
                    page += 1;
                    reload();
                  },
                ),
                const SizedBox(height: 12),
                const SectionTitle('Payment history'),
                if (bundle.payments.items.isEmpty)
                  const EmptyState('No payments recorded yet',
                      icon: Icons.payments_outlined, compact: true)
                else
                  ...bundle.payments.items.map(
                    (p) => _CollectionPaymentCard(
                      payment: p,
                      onReceipt: _isSuccessfulPayment(p)
                          ? () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LiveCollectionReceiptPage(
                                    paymentId: p.id,
                                    resident: false,
                                  ),
                                ),
                              )
                          : null,
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

class _AdminCollectionBundle {
  const _AdminCollectionBundle({
    required this.collection,
    required this.dashboard,
    required this.charges,
    required this.payments,
    required this.wings,
  });
  final CollectionSummary collection;
  final CollectionDashboard dashboard;
  final Paged<CollectionCharge> charges;
  final Paged<CollectionPayment> payments;
  final List<WingSummary> wings;
}

class LiveAdminCollectionChargePage extends StatefulWidget {
  const LiveAdminCollectionChargePage({
    super.key,
    required this.collectionId,
    required this.charge,
    required this.allowPartial,
    required this.collectionActive,
  });
  final String collectionId;
  final CollectionCharge charge;
  final bool allowPartial;
  final bool collectionActive;

  @override
  State<LiveAdminCollectionChargePage> createState() =>
      _LiveAdminCollectionChargePageState();
}

class _LiveAdminCollectionChargePageState
    extends State<LiveAdminCollectionChargePage> {
  late CollectionCharge charge = widget.charge;
  bool busy = false;

  Future<void> _adjust() async {
    final amount = await promptTextDialog(
      context,
      title: 'Adjust assigned amount',
      message:
          'Enter a signed rupee delta (for example 500 or -200). Payments already recorded are not overwritten.',
      label: 'Delta (₹)',
      confirmLabel: 'Continue',
    );
    if (amount == null || !mounted) return;
    final negative = amount.trim().startsWith('-');
    final raw = negative ? amount.trim().substring(1) : amount.trim();
    final paise = parseRupeesToPaise(raw);
    if (paise == null || paise == 0) {
      showErrorSnack(context, 'Enter a non-zero rupee amount.');
      return;
    }
    final reason = await promptTextDialog(
      context,
      title: 'Reason for adjustment',
      label: 'Reason',
      confirmLabel: 'Save adjustment',
    );
    if (reason == null || reason.trim().length < 3 || !mounted) return;
    setState(() => busy = true);
    try {
      final updated = await ensureLiveRepositories(authSession!.api)
          .collections
          .adjustCharge(
            charge.id,
            deltaPaise: negative ? -paise : paise,
            reason: reason.trim(),
          );
      if (!mounted) return;
      setState(() => charge = updated);
      showSuccessSnack(context, 'Amount adjusted.');
    } catch (e) {
      if (mounted) showErrorSnack(context, collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _offline() async {
    final amountCtrl = TextEditingController(
      text: paiseToRupeeInput(charge.outstandingPaise),
    );
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record offline payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixText: '₹ ',
              ),
            ),
            TextFormField(
              controller: refCtrl,
              decoration: const InputDecoration(labelText: 'Reference number'),
            ),
            TextFormField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Record')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final paise = parseRupeesToPaise(amountCtrl.text);
    if (paise == null || paise <= 0) {
      showErrorSnack(context, 'Enter a valid amount.');
      return;
    }
    if (refCtrl.text.trim().isEmpty) {
      showErrorSnack(context, 'Enter a reference number.');
      return;
    }
    setState(() => busy = true);
    try {
      await ensureLiveRepositories(authSession!.api).collections.recordOffline(
            chargeId: charge.id,
            amountPaise: paise,
            paidAt: DateTime.now().toUtc().toIso8601String(),
            referenceNumber: refCtrl.text.trim(),
            notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          );
      if (!mounted) return;
      showSuccessSnack(context, 'Offline payment recorded.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorSnack(context, collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(charge.flatLabel)),
      body: ListView(
        padding: Sp.pagePadding,
        children: [
          DetailCard(children: [
            DetailRow('Owner', charge.ownerNameSnapshot),
            DetailRow('Occupancy', humanizeStatus(charge.occupancyStatusSnapshot)),
            DetailRow('Assigned', moneyPaise(charge.assignedAmountPaise)),
            DetailRow('Paid', moneyPaise(charge.amountPaidPaise)),
            DetailRow('Outstanding', moneyPaise(charge.outstandingPaise),
                emphasize: true),
            DetailRow(
              'Partial payment',
              widget.allowPartial ? 'Allowed' : 'Full amount only',
            ),
            DetailRow('Due', fmtIsoDate(charge.dueDate)),
            DetailRow('Status', '',
                valueWidget: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(charge.status),
                )),
          ]),
          if (widget.collectionActive) ...[
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Record offline payment',
              icon: Icons.payments_outlined,
              busy: busy,
              onPressed: charge.outstandingPaise <= 0 ? null : _offline,
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Adjust assigned amount',
              icon: Icons.tune_rounded,
              onPressed: busy ? null : _adjust,
            ),
            if (_canRemoveCollectionCharge(charge)) ...[
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Remove this unpaid flat',
                icon: Icons.delete_outline_rounded,
                onPressed: busy
                    ? null
                    : () async {
                        final removed = await _removeUnpaidCollectionFlats(
                          context: context,
                          collectionId: widget.collectionId,
                          chargeIds: [charge.id],
                          confirmTitle: 'Remove ${charge.flatLabel}?',
                          successMessage:
                              '${charge.flatLabel} removed from the collection.',
                        );
                        if (!removed || !mounted) return;
                        Navigator.pop(context, true);
                      },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Resident list of collections assigned to the selected flat.
class LiveOwnerCollectionsPage extends StatefulWidget {
  const LiveOwnerCollectionsPage({super.key, required this.canFinance});
  final bool canFinance;

  @override
  State<LiveOwnerCollectionsPage> createState() =>
      _LiveOwnerCollectionsPageState();
}

class _LiveOwnerCollectionsPageState extends State<LiveOwnerCollectionsPage> {
  late Future<List<CollectionCharge>> _future = _load();

  Future<List<CollectionCharge>> _load({bool force = false}) async {
    if (!widget.canFinance) {
      throw StateError('Financial access is not available for this account.');
    }
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final items =
        await ensureLiveRepositories(session.api).collections.listResident(force: force);
    final flatId = session.selectedResidentFlatId;
    if (flatId == null) return items;
    return items.where((row) => row.flatId == flatId).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canFinance) {
      return const EmptyState(
        'Financial access is not available for this account.',
        icon: Icons.lock_outline_rounded,
      );
    }
    return FutureBuilder<List<CollectionCharge>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 4, showHeader: true);
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            title: 'Could not load collections',
            onRetry: () => setState(() => _future = _load(force: true)),
          );
        }
        final rows = snap.data ?? const <CollectionCharge>[];
        final open = rows
            .where((r) => r.status != 'PAID' && r.status != 'CANCELLED')
            .toList();
        final due = open.fold<int>(0, (s, r) => s + r.outstandingPaise);
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            setState(() => _future = _load(force: true));
            await _future;
          },
          child: ListView(
            padding: Sp.pagePadding,
            children: [
              const PageHeader(
                'One-time collections',
                subtitle: 'Special charges for your flat, separate from maintenance',
              ),
              HeroMoneyCard(
                label: 'Outstanding collections',
                amount: moneyPaise(due),
                subtitle: open.isEmpty
                    ? 'Nothing due on special collections.'
                    : '${open.length} open ${open.length == 1 ? 'charge' : 'charges'}',
              ),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                const EmptyState(
                  'No special collections are assigned to this flat',
                  icon: Icons.celebration_outlined,
                )
              else
                ...rows.map(
                  (row) => AppCard(
                    onTap: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LiveOwnerCollectionChargePage(chargeId: row.id),
                        ),
                      );
                      if (mounted) {
                        setState(() => _future = _load(force: true));
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              row.collectionTitle ?? 'Collection',
                              style: T.bodyStrong,
                            ),
                          ),
                          StatusBadge(row.status),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          '${row.flatLabel} · due ${fmtIsoDate(row.dueDate)}',
                          style: T.caption,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Due ${moneyPaise(row.outstandingPaise)} of ${moneyPaise(row.assignedAmountPaise)}  ·  paid ${moneyPaise(row.amountPaidPaise)}',
                          style: T.secondary,
                        ),
                      ],
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

class LiveOwnerCollectionChargePage extends StatefulWidget {
  const LiveOwnerCollectionChargePage({super.key, required this.chargeId});
  final String chargeId;

  @override
  State<LiveOwnerCollectionChargePage> createState() =>
      _LiveOwnerCollectionChargePageState();
}

class _LiveOwnerCollectionChargePageState
    extends State<LiveOwnerCollectionChargePage> {
  late Future<_ResidentChargeBundle> _future = _load();
  bool paying = false;
  final amountCtrl = TextEditingController();

  Future<_ResidentChargeBundle> _load() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final charge = await repos.collections.residentCharge(widget.chargeId);
    final payments =
        await repos.collections.listResidentPayments(chargeId: widget.chargeId);
    return _ResidentChargeBundle(charge: charge, payments: payments.items);
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay(CollectionCharge charge) async {
    if (paying) return;
    if (charge.outstandingPaise <= 0) {
      showWarningSnack(context, 'This collection is already settled.');
      return;
    }
    int? amountPaise;
    if (charge.allowPartialPayment) {
      final typed = parseRupeesToPaise(amountCtrl.text);
      amountPaise = typed ?? charge.outstandingPaise;
      if (amountPaise <= 0 || amountPaise > charge.outstandingPaise) {
        showErrorSnack(context, 'Enter an amount up to the outstanding due.');
        return;
      }
    }
    setState(() => paying = true);
    try {
      final session = authSession!;
      final repos = ensureLiveRepositories(session.api);
      final order = await repos.collections.createPaymentOrder(
        charge.id,
        amountPaise: amountPaise,
      );
      if (!mounted) return;
      final PaymentSettlement settlement;
      if (isDemoPaymentProvider(order.order.provider)) {
        final choice = await openDemoPaymentCheckoutForOrder(
          context: context,
          order: order.order,
        );
        if (!mounted) return;
        if (choice == DemoPaymentChoice.cancelled) {
          showWarningSnack(context, 'Payment cancelled.');
          return;
        }
        if (choice == DemoPaymentChoice.failed) {
          try {
            await repos.collections.completeDemoPayment(
              orderId: order.order.orderId,
              outcome: 'failure',
            );
          } catch (_) {}
          if (!mounted) return;
          showErrorSnack(context, 'Demo payment failed (simulated).');
          setState(() => _future = _load());
          return;
        }
        settlement = await repos.collections.completeDemoPayment(
          orderId: order.order.orderId,
          outcome: 'success',
        );
      } else {
        final checkout = await openPaymentCheckout(
          context: context,
          order: _asCheckoutOrder(order),
          ownerName: session.profile?.name ?? charge.ownerNameSnapshot,
          ownerEmail: session.profile?.email ?? '',
          ownerPhone: session.profile?.phone,
        );
        if (!mounted) return;
        if (checkout.cancelled) {
          showWarningSnack(context, 'Payment cancelled.');
          return;
        }
        if (!checkout.isSuccess) {
          showErrorSnack(context, checkout.errorMessage ?? 'Payment failed');
          return;
        }
        settlement = await repos.collections.verifyPayment(
          orderId: checkout.orderId!,
          paymentId: checkout.paymentId!,
          signature: checkout.signature!,
        );
      }
      repos.invalidateAfterFinancialMutation();
      if (!mounted) return;
      if (settlement.receiptId != null) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LiveCollectionReceiptPage(
              receiptId: settlement.receiptId,
              resident: true,
            ),
          ),
        );
      } else {
        showSuccessSnack(context, 'Payment confirmed.');
      }
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) showErrorSnack(context, collectionErrorMessage(e));
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collection')),
      body: FutureBuilder<_ResidentChargeBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const LoadingView(label: 'Loading collection…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              title: 'Could not load this collection',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final bundle = snap.data!;
          final charge = bundle.charge;
          final collection = charge.collection;
          final canPay = charge.outstandingPaise > 0 &&
              (charge.collectionStatus ?? collection?.status) == 'ACTIVE';
          if (amountCtrl.text.isEmpty && charge.allowPartialPayment) {
            amountCtrl.text = paiseToRupeeInput(charge.outstandingPaise);
          }
          return Column(children: [
            Expanded(
              child: ListView(
                padding: Sp.pagePadding,
                children: [
                  Text(charge.collectionTitle ?? collection?.title ?? 'Collection',
                      style: T.h2),
                  const SizedBox(height: 4),
                  Text(
                    charge.collectionNumber ?? collection?.collectionNumber ?? '',
                    style: T.secondary,
                  ),
                  const SizedBox(height: 14),
                  HeroMoneyCard(
                    label: 'Amount due',
                    amount: moneyPaise(charge.outstandingPaise),
                    subtitle:
                        'Assigned ${moneyPaise(charge.assignedAmountPaise)} · paid ${moneyPaise(charge.amountPaidPaise)}',
                  ),
                  const SizedBox(height: 12),
                  DetailCard(children: [
                    DetailRow('Flat', charge.flatLabel),
                    DetailRow('Due date', fmtIsoDate(charge.dueDate)),
                    DetailRow('Status', '',
                        valueWidget: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusBadge(charge.status),
                        )),
                    if ((charge.collectionDescription ??
                            collection?.description) !=
                        null)
                      DetailRow(
                        'Description',
                        charge.collectionDescription ??
                            collection!.description,
                      ),
                    if ((charge.paymentInstructions ??
                            collection?.paymentInstructions) !=
                        null)
                      DetailRow(
                        'Instructions',
                        charge.paymentInstructions ??
                            collection!.paymentInstructions!,
                      ),
                    DetailRow(
                      'Partial payment',
                      charge.allowPartialPayment ? 'Allowed' : 'Full amount only',
                    ),
                  ]),
                  if (charge.allowPartialPayment && canPay) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount to pay (₹)',
                        prefixText: '₹ ',
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const SectionTitle('Payments'),
                  if (bundle.payments.isEmpty)
                    const EmptyState('No payments yet',
                        icon: Icons.payments_outlined, compact: true)
                  else
                    ...bundle.payments.map(
                      (p) => _CollectionPaymentCard(
                        payment: p,
                        onReceipt: _isSuccessfulPayment(p)
                            ? () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LiveCollectionReceiptPage(
                                      paymentId: p.id,
                                      resident: true,
                                    ),
                                  ),
                                )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (canPay)
              BottomActionBar(children: [
                PrimaryButton(
                  label: 'Pay collection',
                  icon: Icons.payments_outlined,
                  busy: paying,
                  onPressed: () => _pay(charge),
                ),
              ]),
          ]);
        },
      ),
    );
  }
}

class _ResidentChargeBundle {
  const _ResidentChargeBundle({required this.charge, required this.payments});
  final CollectionCharge charge;
  final List<CollectionPayment> payments;
}

class LiveCollectionReceiptPage extends StatefulWidget {
  const LiveCollectionReceiptPage({
    super.key,
    this.receiptId,
    this.paymentId,
    required this.resident,
  });
  final String? receiptId;
  final String? paymentId;
  final bool resident;

  @override
  State<LiveCollectionReceiptPage> createState() =>
      _LiveCollectionReceiptPageState();
}

class _LiveCollectionReceiptPageState extends State<LiveCollectionReceiptPage> {
  late Future<CollectionReceiptDetail> _future = _load();
  bool sharing = false;
  bool downloading = false;

  Future<CollectionReceiptDetail> _load() async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final collections = ensureLiveRepositories(session.api).collections;
    if (widget.receiptId != null) {
      return widget.resident
          ? collections.residentReceipt(widget.receiptId!)
          : collections.adminReceipt(widget.receiptId!);
    }
    if (widget.paymentId != null) {
      return widget.resident
          ? collections.residentPaymentReceipt(widget.paymentId!)
          : collections.adminPaymentReceipt(widget.paymentId!);
    }
    throw StateError('Receipt is not available.');
  }

  Future<void> _share(CollectionReceiptDetail detail) async {
    if (sharing) return;
    setState(() => sharing = true);
    try {
      await _shareBytes(
        bytes: base64Decode(detail.pdfBase64),
        filename: '${detail.receiptNumber}.pdf',
        mimeType: 'application/pdf',
        title: 'Receipt ${detail.receiptNumber}',
      );
    } catch (_) {
      if (mounted) showErrorSnack(context, 'Could not share the receipt.');
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  Future<void> _download(CollectionReceiptDetail detail) async {
    if (downloading) return;
    setState(() => downloading = true);
    try {
      final bytes = Uint8List.fromList(base64Decode(detail.pdfBase64));
      await Printing.layoutPdf(
        name: '${detail.receiptNumber}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (mounted) showErrorSnack(context, 'Could not open the receipt PDF.');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: FutureBuilder<CollectionReceiptDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const LoadingView(label: 'Loading receipt…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              title: 'Receipt not available yet',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final detail = snap.data!;
          return Column(children: [
            Expanded(
              child: ListView(
                padding: Sp.pagePadding,
                children: [
                  Center(
                    child: Column(children: [
                      const AppAvatar(
                          icon: Icons.check_rounded, color: C.green, size: 64),
                      const SizedBox(height: 14),
                      Text('Payment received', style: T.h2),
                      const SizedBox(height: 4),
                      Text(detail.receiptNumber, style: T.secondary),
                      const SizedBox(height: 14),
                      Text(moneyPaise(detail.amountPaise),
                          style: T.display.copyWith(color: C.green)),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  DetailCard(children: [
                    DetailRow('Collection', detail.collectionTitle),
                    DetailRow('Collection no.', detail.collectionNumber),
                    DetailRow('Paid at', fmtIsoDateTime(detail.paidAt)),
                    DetailRow('Method', humanizeStatus(detail.paymentMethod)),
                    DetailRow('Flat', detail.flatLabel),
                    DetailRow('Owner', detail.ownerName),
                    if (detail.transactionReference != null)
                      DetailRow('Reference', detail.transactionReference!),
                  ]),
                ],
              ),
            ),
            BottomActionBar(children: [
              PrimaryButton(
                label: 'Download Receipt',
                icon: Icons.download_outlined,
                busy: downloading,
                onPressed: () => _download(detail),
              ),
              SecondaryButton(
                label: 'Share PDF receipt',
                icon: Icons.ios_share_outlined,
                busy: sharing,
                onPressed: () => _share(detail),
              ),
            ]),
          ]);
        },
      ),
    );
  }
}
