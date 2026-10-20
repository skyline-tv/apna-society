import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/billing_models.dart';
import '../../api/models/common.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';
import 'demo_payment_checkout.dart';

String billingErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'TENANT_BILLING_DENIED':
      case 'GUARD_BILLING_DENIED':
        return 'Financial access is not available for this account.';
      case 'BILL_ALREADY_PAID':
        return 'This bill is already fully paid.';
      case 'BILL_CANCELLED':
        return 'This bill is cancelled.';
      case 'BILL_NOT_ADJUSTABLE':
        return 'This bill cannot be adjusted.';
      case 'BILL_HAS_PAYMENTS':
        return 'Cannot cancel a bill that already has payments.';
      case 'PAYMENTS_LIVE_DISABLED':
        return 'Online payments are not enabled on the server yet.';
      case 'INVALID_GATEWAY_SIGNATURE':
        return 'Payment could not be verified. Contact the society office if money was deducted.';
      case 'NOT_BILL_OWNER':
        return 'Only the bill owner may pay this bill.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

String _shortIso(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day}/${d.month}/${d.year}';
}

String _periodLabel(Bill bill) {
  return maintenancePeriodLabel(
    startMonth: DateTime.tryParse(bill.billingPeriodStart) ?? DateTime.now(),
    monthsCovered: bill.numberOfMonths,
    periodEnd: DateTime.tryParse(bill.billingPeriodEnd),
  );
}

// ─── Admin bills ─────────────────────────────────────────────────────────────

class LiveAdminBillsPage extends StatefulWidget {
  const LiveAdminBillsPage({super.key});

  @override
  State<LiveAdminBillsPage> createState() => _LiveAdminBillsPageState();
}

class _LiveAdminBillsPageState extends State<LiveAdminBillsPage> {
  String? statusFilter;
  String? wingFilter;
  int page = 1;
  late Future<_AdminBillsBundle> _future = _load();

  Future<_AdminBillsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final bills = await repos.billing.listAdminBills(
      force: force,
      query: ListBillsQuery(
        status: statusFilter,
        wingCode: wingFilter,
        page: page,
        limit: 30,
      ),
    );
    final summary = await repos.billing.summary(force: force);
    return _AdminBillsBundle(bills: bills, summary: summary);
  }

  void reload({bool resetPage = false}) {
    if (resetPage) page = 1;
    setState(() => _future = _load(force: true));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminBillsBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const LoadingView(label: 'Loading bills…');
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            title: 'Could not load bills',
            onRetry: () => reload(resetPage: true),
          );
        }
        final bundle = snap.data!;
        final bills = bundle.bills.items;
        final summary = bundle.summary;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async => reload(resetPage: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(children: [
                Expanded(
                  child: StatCard(
                    title: 'Billed',
                    value: moneyPaise(summary.totalBilledPaise),
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    title: 'Collected',
                    value: moneyPaise(summary.totalCollectedPaise),
                    icon: Icons.payments_outlined,
                    accent: C.green,
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: StatCard(
                    title: 'Outstanding',
                    value: moneyPaise(summary.totalOutstandingPrincipalPaise),
                    icon: Icons.pending_actions_outlined,
                    accent: C.amber,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    title: 'Interest',
                    value: moneyPaise(summary.totalAccruedInterestPaise),
                    icon: Icons.percent,
                    accent: C.error,
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              QuickActionTile(
                icon: Icons.auto_awesome,
                label: 'Generate bills',
                onTap: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LiveGenerateBillsPage()),
                  );
                  if (ok == true && mounted) reload(resetPage: true);
                },
              ),
              QuickActionTile(
                icon: Icons.refresh,
                label: 'Refresh interest',
                onTap: () async {
                  try {
                    final session = authSession!;
                    final result = await ensureLiveRepositories(session.api)
                        .billing
                        .refreshInterest();
                    ensureLiveRepositories(session.api)
                        .invalidateAfterFinancialMutation();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Updated interest on ${result.updated} bills'),
                      backgroundColor: C.green,
                    ));
                    reload();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(billingErrorMessage(e)),
                      backgroundColor: C.error,
                    ));
                  }
                },
              ),
              QuickActionTile(
                icon: Icons.preview_outlined,
                label: 'Eligible flats',
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LiveEligibleFlatsPage()),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in const [
                    null,
                    'ISSUED',
                    'PARTIALLY_PAID',
                    'OVERDUE',
                    'PAID',
                    'CANCELLED',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s ?? 'All'),
                        selected: statusFilter == s,
                        onSelected: (_) {
                          statusFilter = s;
                          reload(resetPage: true);
                        },
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All wings'),
                      selected: wingFilter == null,
                      onSelected: (_) {
                        wingFilter = null;
                        reload(resetPage: true);
                      },
                    ),
                  ),
                  for (final w in summary.wingWise)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(w.wingCode),
                        selected: wingFilter == w.wingCode,
                        onSelected: (_) {
                          wingFilter = w.wingCode;
                          reload(resetPage: true);
                        },
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              Text('${bundle.bills.pagination.total} bills',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: C.navy, fontSize: 12)),
              const SizedBox(height: 8),
              if (bills.isEmpty)
                const EmptyState('No bills match these filters')
              else
                ...bills.map((bill) => AppCard(
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveAdminBillDetailPage(billId: bill.id),
                          ),
                        );
                        if (mounted) reload();
                      },
                      child: ListTile(
                        title: Text(
                          '${bill.billNumber} · ${bill.flatNumberSnapshot}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: C.navy),
                        ),
                        subtitle: Text(
                          '${_periodLabel(bill)}\n'
                          'Due ${_shortIso(bill.dueDate)} · '
                          '${moneyPaise(billAmountDuePaise(bill))} due',
                          style: const TextStyle(
                              color: C.muted, fontSize: 12, height: 1.35),
                        ),
                        isThreeLine: true,
                        trailing: StatusBadge(bill.status.toLowerCase()),
                      ),
                    )),
              if (bundle.bills.pagination.totalPages > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: page <= 1
                          ? null
                          : () {
                              page -= 1;
                              reload();
                            },
                      child: const Text('Previous'),
                    ),
                    Text('Page ${bundle.bills.pagination.page} of ${bundle.bills.pagination.totalPages}'),
                    TextButton(
                      onPressed: page >= bundle.bills.pagination.totalPages
                          ? null
                          : () {
                              page += 1;
                              reload();
                            },
                      child: const Text('Next'),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminBillsBundle {
  const _AdminBillsBundle({required this.bills, required this.summary});
  final Paged<Bill> bills;
  final BillingSummary summary;
}

class LiveGenerateBillsPage extends StatefulWidget {
  const LiveGenerateBillsPage({super.key});
  @override
  State<LiveGenerateBillsPage> createState() => _LiveGenerateBillsPageState();
}

class _LiveGenerateBillsPageState extends State<LiveGenerateBillsPage> {
  DateTime periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int months = 1;
  bool busy = false;
  String? error;

  Future<void> generate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final result = await ensureLiveRepositories(session.api).billing.generateBills(
            billingPeriodStart: periodStart.toUtc().toIso8601String(),
            numberOfMonths: months,
          );
      ensureLiveRepositories(session.api).invalidateAfterFinancialMutation();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bills generated'),
          content: Text(
            'Created ${result.createdCount} · Skipped ${result.skippedCount} · '
            'Conflicts ${result.conflictCount}\n'
            'Total billed ${moneyPaise(result.totalBilledPaise)}',
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = billingErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate bills')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const InfoNote(
            'Bills are created only for occupied flats with an active owner. '
            'Vacant and unassigned flats are skipped by the server.',
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Billing period start'),
            subtitle: Text(
                '${periodStart.year}-${periodStart.month.toString().padLeft(2, '0')}-01'),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: periodStart,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => periodStart =
                            DateTime(picked.year, picked.month, 1));
                      }
                    },
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 month')),
              ButtonSegment(value: 3, label: Text('3 months')),
            ],
            selected: {months},
            onSelectionChanged: busy
                ? null
                : (s) => setState(() => months = s.first),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!,
                style: const TextStyle(
                    color: C.error, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : generate,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text('Generate on server'),
          ),
        ],
      ),
    );
  }
}

class LiveEligibleFlatsPage extends StatefulWidget {
  const LiveEligibleFlatsPage({super.key});
  @override
  State<LiveEligibleFlatsPage> createState() => _LiveEligibleFlatsPageState();
}

class _LiveEligibleFlatsPageState extends State<LiveEligibleFlatsPage> {
  late Future<List<EligibleFlat>> _future = _load();

  Future<List<EligibleFlat>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .billing
        .eligibleFlats(force: force);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eligible flats')),
      body: FutureBuilder<List<EligibleFlat>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const LoadingView(label: 'Loading eligible flats…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const EmptyState('No eligible flats for billing');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final f = rows[i];
              return AppCard(
                child: ListTile(
                  title: Text('${f.number} · ${f.wingCode}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${f.flatType} · ${f.occupancyStatus}\n'
                    '${moneyPaise(f.monthlyRatePaise)}/mo',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LiveAdminBillDetailPage extends StatefulWidget {
  const LiveAdminBillDetailPage({super.key, required this.billId});
  final String billId;
  @override
  State<LiveAdminBillDetailPage> createState() =>
      _LiveAdminBillDetailPageState();
}

class _LiveAdminBillDetailPageState extends State<LiveAdminBillDetailPage> {
  late Future<_BillDetailBundle> _future = _load();
  bool busy = false;

  Future<_BillDetailBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final bill = await repos.billing.adminBill(widget.billId, force: force);
    final interest =
        await repos.billing.adminInterest(widget.billId, force: force);
    return _BillDetailBundle(bill: bill, interest: interest);
  }

  Future<void> _adjust(Bill bill) async {
    final ctrl = TextEditingController(text: '0');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adjust bill (paise)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'adjustmentsPaise (integer)',
            helperText: 'Server sets total = base + adjustments',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || !mounted) return;
    setState(() => busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .billing
          .adjustBill(bill.id, adjustmentsPaise: value);
      ensureLiveRepositories(session.api)
          .invalidateAfterFinancialMutation(billId: bill.id);
      if (!mounted) return;
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(billingErrorMessage(e)),
        backgroundColor: C.error,
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancel(Bill bill) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel bill'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Cancel bill'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => busy = true);
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .billing
          .cancelBill(bill.id, reason: reason);
      ensureLiveRepositories(session.api)
          .invalidateAfterFinancialMutation(billId: bill.id);
      if (!mounted) return;
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(billingErrorMessage(e)),
        backgroundColor: C.error,
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _offline(Bill bill) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveOfflinePaymentPage(bill: bill),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _future = _load(force: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill details')),
      body: FutureBuilder<_BillDetailBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const LoadingView(label: 'Loading bill…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final bill = snap.data!.bill;
          final interest = snap.data!.interest;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(bill.billNumber,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: C.navy)),
              Text('${bill.flatNumberSnapshot} · ${bill.wingCodeSnapshot}',
                  style: const TextStyle(color: C.muted)),
              const SizedBox(height: 12),
              billDetailLine('Period', _periodLabel(bill)),
              billDetailLine('Status', bill.status),
              billDetailLine('Owner', bill.ownerNameSnapshot),
              billDetailLine('Due date', _shortIso(bill.dueDate)),
              billDetailLine('Base amount', moneyPaise(bill.baseAmountPaise)),
              billDetailLine('Total', moneyPaise(bill.totalAmountPaise)),
              billDetailLine(
                  'Outstanding principal',
                  moneyPaise(bill.outstandingPrincipalPaise)),
              billDetailLine(
                  'Accrued interest (server)',
                  moneyPaise(interest.accruedInterestPaise)),
              billDetailLine(
                  'Amount due', moneyPaise(billAmountDuePaise(bill))),
              billDetailLine('Paid', moneyPaise(bill.amountPaidPaise)),
              billDetailLine(
                  'Overdue days', '${interest.overdueDays}'),
              billDetailLine(
                  'Annual rate',
                  '${interest.annualInterestRatePercent}%'),
              const SizedBox(height: 8),
              const SectionTitle('Interest segments'),
              const SizedBox(height: 8),
              if (interest.segments.isEmpty)
                const EmptyState('No interest segments')
              else
                ...interest.segments.map((s) => AppCard(
                      child: ListTile(
                        title: Text(
                            '${_shortIso(s.from)} → ${_shortIso(s.to)}'),
                        subtitle: Text(
                          '${s.days} days · Principal ${moneyPaise(s.principalPaise)} · '
                          'Interest ${moneyPaise(s.interestPaise)}',
                        ),
                      ),
                    )),
              const SizedBox(height: 16),
              if (bill.status != 'CANCELLED' && bill.status != 'PAID') ...[
                QuickActionTile(
                  icon: Icons.tune,
                  label: 'Adjust bill',
                  onTap: busy ? () {} : () => _adjust(bill),
                ),
                QuickActionTile(
                  icon: Icons.payments_outlined,
                  label: 'Record offline payment',
                  onTap: busy ? () {} : () => _offline(bill),
                ),
              ],
              if (bill.status != 'CANCELLED' && bill.amountPaidPaise == 0)
                QuickActionTile(
                  icon: Icons.cancel_outlined,
                  label: 'Cancel bill',
                  onTap: busy ? () {} : () => _cancel(bill),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BillDetailBundle {
  const _BillDetailBundle({required this.bill, required this.interest});
  final Bill bill;
  final InterestBreakdown interest;
}

class LiveOfflinePaymentPage extends StatefulWidget {
  const LiveOfflinePaymentPage({super.key, required this.bill});
  final Bill bill;
  @override
  State<LiveOfflinePaymentPage> createState() => _LiveOfflinePaymentPageState();
}

class _LiveOfflinePaymentPageState extends State<LiveOfflinePaymentPage> {
  final reference = TextEditingController();
  final notes = TextEditingController();
  late final amount = TextEditingController(
      text: '${widget.bill.outstandingPrincipalPaise}');
  bool busy = false;
  String? error;

  @override
  void dispose() {
    reference.dispose();
    notes.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final amountPaise = int.tryParse(amount.text.trim());
    if (amountPaise == null || amountPaise <= 0) {
      setState(() => error = 'Enter amount in paise (positive integer).');
      return;
    }
    if (reference.text.trim().isEmpty) {
      setState(() => error = 'Reference number is required.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final idempotencyKey =
          'offline-${widget.bill.id}-${reference.text.trim()}-$amountPaise';
      final result =
          await ensureLiveRepositories(session.api).billing.recordOfflinePayment(
                billId: widget.bill.id,
                amountPaise: amountPaise,
                paidAt: DateTime.now().toUtc().toIso8601String(),
                referenceNumber: reference.text.trim(),
                notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                idempotencyKey: idempotencyKey,
              );
      ensureLiveRepositories(session.api)
          .invalidateAfterFinancialMutation(billId: widget.bill.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.alreadySettled
            ? 'Payment already settled.'
            : 'Offline payment recorded.'),
        backgroundColor: C.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = billingErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline payment')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.bill.billNumber,
              style: const TextStyle(fontWeight: FontWeight.w900, color: C.navy)),
          Text(
              'Outstanding principal ${moneyPaise(widget.bill.outstandingPrincipalPaise)}',
              style: const TextStyle(color: C.muted)),
          const SizedBox(height: 16),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount (paise)',
              helperText: 'Must match server settlement rules',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reference,
            decoration: const InputDecoration(labelText: 'Reference number'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!,
                style: const TextStyle(
                    color: C.error, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text('Record offline payment'),
          ),
        ],
      ),
    );
  }
}

class LiveAdminPaymentsPage extends StatefulWidget {
  const LiveAdminPaymentsPage({super.key});
  @override
  State<LiveAdminPaymentsPage> createState() => _LiveAdminPaymentsPageState();
}

class _LiveAdminPaymentsPageState extends State<LiveAdminPaymentsPage> {
  late Future<Paged<PaymentSummary>> _future = _load();

  Future<Paged<PaymentSummary>> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .billing
        .listAdminPayments(force: force, limit: 50);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<PaymentSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const LoadingView(label: 'Loading payments…');
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            onRetry: () => setState(() => _future = _load(force: true)),
          );
        }
        final rows = snap.data?.items ?? [];
        if (rows.isEmpty) return const EmptyState('No payments yet');
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            setState(() => _future = _load(force: true));
            await _future;
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final p = rows[i];
              return AppCard(
                child: ListTile(
                  title: Text(p.paymentNumber,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${p.paymentMethod} · ${moneyPaise(p.amountPaise)}\n'
                    '${p.paidAt == null ? '—' : _shortIso(p.paidAt!)}'
                    '${p.referenceNumber == null ? '' : ' · ${p.referenceNumber}'}',
                  ),
                  isThreeLine: true,
                  trailing: StatusBadge(p.status.toLowerCase()),
                  onLongPress: p.status == 'SUCCESS'
                      ? () => _refund(p)
                      : null,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _refund(PaymentSummary payment) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund payment'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .billing
          .refundPayment(payment.id, reason: reason);
      ensureLiveRepositories(session.api).invalidateAfterFinancialMutation();
      if (!mounted) return;
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(billingErrorMessage(e)),
        backgroundColor: C.error,
      ));
    }
  }
}

// ─── Owner billing ───────────────────────────────────────────────────────────

class LiveOwnerBillsPage extends StatefulWidget {
  const LiveOwnerBillsPage({super.key, required this.canFinance});
  final bool canFinance;
  @override
  State<LiveOwnerBillsPage> createState() => _LiveOwnerBillsPageState();
}

class _LiveOwnerBillsPageState extends State<LiveOwnerBillsPage> {
  late Future<Paged<Bill>> _future = _load();

  Future<Paged<Bill>> _load({bool force = false}) async {
    if (!widget.canFinance) {
      throw StateError('Financial access is not available for this account.');
    }
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .billing
        .listResidentBills(force: force, query: const ListBillsQuery(limit: 50));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canFinance) {
      return const EmptyState('Financial access is not available for this account.');
    }
    return FutureBuilder<Paged<Bill>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const LoadingView(label: 'Loading your bills…');
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            title: 'Could not load bills',
            onRetry: () => setState(() => _future = _load(force: true)),
          );
        }
        final rows = snap.data?.items ?? [];
        if (rows.isEmpty) return const EmptyState('No bills found for your flats yet');
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            setState(() => _future = _load(force: true));
            await _future;
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final bill = rows[i];
              return AppCard(
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveOwnerBillDetailPage(billId: bill.id),
                    ),
                  );
                  if (mounted) {
                    setState(() => _future = _load(force: true));
                  }
                },
                child: ListTile(
                  title: Text(bill.billNumber,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${bill.flatNumberSnapshot} · ${_periodLabel(bill)}\n'
                    'Due ${_shortIso(bill.dueDate)} · ${moneyPaise(billAmountDuePaise(bill))}',
                  ),
                  isThreeLine: true,
                  trailing: StatusBadge(bill.status.toLowerCase()),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class LiveOwnerBillDetailPage extends StatefulWidget {
  const LiveOwnerBillDetailPage({super.key, required this.billId});
  final String billId;
  @override
  State<LiveOwnerBillDetailPage> createState() =>
      _LiveOwnerBillDetailPageState();
}

class _LiveOwnerBillDetailPageState extends State<LiveOwnerBillDetailPage> {
  late Future<_BillDetailBundle> _future = _load();
  bool paying = false;

  Future<_BillDetailBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final bill = await repos.billing.residentBill(widget.billId, force: force);
    final interest =
        await repos.billing.residentInterest(widget.billId, force: force);
    return _BillDetailBundle(bill: bill, interest: interest);
  }

  Future<void> _pay(Bill bill) async {
    if (paying) return;
    if (bill.outstandingPrincipalPaise <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This bill has no outstanding principal.'),
        backgroundColor: C.amber,
      ));
      return;
    }
    setState(() => paying = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final repos = ensureLiveRepositories(session.api);
      final order = await repos.billing.createPaymentOrder(bill.id);
      final profile = session.profile;
      if (!mounted) return;

      final PaymentSettlement settlement;
      if (isDemoPaymentProvider(order.order.provider)) {
        // Demo: UI chooses outcome; backend settles. No client HMAC/secret.
        final choice = await openDemoPaymentCheckout(
          context: context,
          order: order,
        );
        if (!mounted) return;
        if (choice == DemoPaymentChoice.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment cancelled.'),
            backgroundColor: C.amber,
          ));
          return;
        }
        if (choice == DemoPaymentChoice.failed) {
          try {
            await repos.billing.completeDemoPayment(
              orderId: order.order.orderId,
              outcome: 'failure',
              billId: bill.id,
            );
          } catch (_) {
            // Server marks FAILED and may throw DEMO_PAYMENT_FAILED — expected.
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Demo payment failed (simulated).'),
            backgroundColor: C.error,
          ));
          return;
        }
        settlement = await repos.billing.completeDemoPayment(
          orderId: order.order.orderId,
          outcome: 'success',
          billId: bill.id,
        );
      } else {
        final checkout = await openPaymentCheckout(
          context: context,
          order: order,
          ownerName: profile?.name ?? bill.ownerNameSnapshot,
          ownerEmail: profile?.email ?? bill.ownerEmailSnapshot,
          ownerPhone: profile?.phone,
        );
        if (!mounted) return;
        if (checkout.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment cancelled.'),
            backgroundColor: C.amber,
          ));
          return;
        }
        if (!checkout.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(checkout.errorMessage ?? 'Payment failed'),
            backgroundColor: C.error,
          ));
          return;
        }
        // Live path: settlement only after backend verify — never from UI alone.
        settlement = await repos.billing.verifyPayment(
          orderId: checkout.orderId!,
          paymentId: checkout.paymentId!,
          signature: checkout.signature!,
          billId: bill.id,
        );
      }
      repos.invalidateAfterFinancialMutation(billId: bill.id);
      if (!mounted) return;
      if (settlement.receiptId != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment verified. Receipt is available.'),
          backgroundColor: C.green,
        ));
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LiveReceiptPage(receiptId: settlement.receiptId!, resident: true),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(settlement.alreadySettled
              ? 'Payment already settled. Refreshing…'
              : 'Payment submitted. Waiting for final settlement — pull to refresh.'),
          backgroundColor: C.blue,
        ));
      }
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(billingErrorMessage(e)),
        backgroundColor: C.error,
      ));
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill details')),
      body: FutureBuilder<_BillDetailBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const LoadingView(label: 'Loading bill…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final bill = snap.data!.bill;
          final interest = snap.data!.interest;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(bill.billNumber,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: C.navy)),
                Text('${bill.flatNumberSnapshot} · ${_periodLabel(bill)}',
                    style: const TextStyle(color: C.muted)),
                const SizedBox(height: 16),
                HeroMoneyCard(
                  label: 'AMOUNT DUE',
                  amount: moneyPaise(billAmountDuePaise(bill)),
                  subtitle:
                      'Principal ${moneyPaise(bill.outstandingPrincipalPaise)} · '
                      'Interest ${moneyPaise(interest.accruedInterestPaise)}',
                ),
                const SizedBox(height: 14),
                billDetailLine('Status', bill.status),
                billDetailLine('Due date', _shortIso(bill.dueDate)),
                billDetailLine('Overdue days', '${interest.overdueDays}'),
                billDetailLine(
                    'Annual interest rate',
                    '${interest.annualInterestRatePercent}% (server)'),
                billDetailLine('Paid so far', moneyPaise(bill.amountPaidPaise)),
                const SizedBox(height: 12),
                const InfoNote(
                  'Interest is calculated by the server (24% p.a. simple daily interest). '
                  'This screen never recalculates interest locally.',
                ),
                const SizedBox(height: 16),
                if (bill.outstandingPrincipalPaise > 0 &&
                    bill.status != 'CANCELLED')
                  FilledButton(
                    onPressed: paying ? null : () => _pay(bill),
                    child: paying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : Text(
                            'Pay ${moneyPaise(bill.outstandingPrincipalPaise)} (principal)'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LiveOwnerPaymentsPage extends StatefulWidget {
  const LiveOwnerPaymentsPage({super.key, required this.canFinance});
  final bool canFinance;
  @override
  State<LiveOwnerPaymentsPage> createState() => _LiveOwnerPaymentsPageState();
}

class _LiveOwnerPaymentsPageState extends State<LiveOwnerPaymentsPage> {
  late Future<Paged<PaymentSummary>> _future = _load();

  Future<Paged<PaymentSummary>> _load({bool force = false}) async {
    if (!widget.canFinance) {
      throw StateError('Financial access is not available for this account.');
    }
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api)
        .billing
        .listResidentPayments(force: force, limit: 50);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canFinance) {
      return const EmptyState('Financial access is not available for this account.');
    }
    return FutureBuilder<Paged<PaymentSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const LoadingView(label: 'Loading payment history…');
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            onRetry: () => setState(() => _future = _load(force: true)),
          );
        }
        final rows = snap.data?.items ?? [];
        if (rows.isEmpty) return const EmptyState('No payment history yet');
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            setState(() => _future = _load(force: true));
            await _future;
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final p = rows[i];
              return AppCard(
                child: ListTile(
                  title: Text(p.paymentNumber,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${p.paymentMethod} · ${moneyPaise(p.amountPaise)}\n'
                    'Status ${p.status}'
                    '${p.paidAt == null ? '' : ' · ${_shortIso(p.paidAt!)}'}',
                  ),
                  isThreeLine: true,
                  trailing: StatusBadge(p.status.toLowerCase()),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class LiveReceiptPage extends StatefulWidget {
  const LiveReceiptPage({
    super.key,
    required this.receiptId,
    required this.resident,
  });
  final String receiptId;
  final bool resident;
  @override
  State<LiveReceiptPage> createState() => _LiveReceiptPageState();
}

class _LiveReceiptPageState extends State<LiveReceiptPage> {
  late Future<ReceiptDetail> _future = _load();

  Future<ReceiptDetail> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final billing = ensureLiveRepositories(session.api).billing;
    return widget.resident
        ? billing.residentReceipt(widget.receiptId, force: force)
        : billing.adminReceipt(widget.receiptId, force: force);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: FutureBuilder<ReceiptDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const LoadingView(label: 'Loading receipt…');
          }
          if (snap.hasError) {
            return LoadFailure(
              error: snap.error!,
              title: 'Receipt not available yet',
              onRetry: () => setState(() => _future = _load(force: true)),
            );
          }
          final detail = snap.data!;
          final r = detail.receipt;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(r.receiptNumber,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: C.navy)),
              const SizedBox(height: 12),
              billDetailLine('Amount', moneyPaise(r.amountPaise)),
              billDetailLine('Method', r.paymentMethod),
              billDetailLine('Paid at', _shortIso(r.paidAt)),
              billDetailLine('Flat', '${r.wingCodeSnapshot} · ${r.flatNumberSnapshot}'),
              billDetailLine('Owner', r.ownerNameSnapshot),
              if (r.transactionReference != null)
                billDetailLine('Reference', r.transactionReference!),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final bytes = base64Decode(detail.pdfBase64);
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [
                        XFile.fromData(
                          Uint8List.fromList(bytes),
                          mimeType: 'application/pdf',
                          name: '${r.receiptNumber}.pdf',
                        ),
                      ],
                      text: 'Receipt ${r.receiptNumber}',
                    ),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Share server PDF'),
              ),
            ],
          );
        },
      ),
    );
  }
}

