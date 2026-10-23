import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
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
import 'live_additional_services_module.dart';

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
      case 'OFFLINE_PAYMENTS_DISABLED':
        return 'Offline collection recording is not enabled on the server.';
      case 'DEMO_PAYMENTS_DISABLED':
        return 'Payment simulation is not available while live payments are enabled.';
      case 'DEMO_PROVIDER_REQUIRED':
        return 'Payment simulation requires the mock payment provider.';
      case 'INVALID_GATEWAY_SIGNATURE':
        return 'Payment could not be verified. Contact the society office if money was deducted.';
      case 'NOT_BILL_OWNER':
        return 'Only the bill owner may pay this bill.';
      case 'RECEIPT_NOT_AVAILABLE':
        return 'A receipt is only available after the payment is confirmed.';
      case 'RECEIPT_ACCESS_DENIED':
      case 'PAYMENT_ACCESS_DENIED':
        return 'You do not have access to this receipt.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

List<Widget> _billBreakdownRows(Bill bill) {
  if (bill.lineItems.isNotEmpty) {
    return [
      for (final item in bill.lineItems)
        DetailRow(
          item.quantity > 1 ? '${item.name} × ${item.quantity}' : item.name,
          moneyPaise(item.amountPaise),
        ),
    ];
  }
  return [
    DetailRow('Monthly maintenance', moneyPaise(bill.baseAmountPaise)),
    if (bill.additionalServicesTotalPaise > 0)
      DetailRow(
          'Additional services', moneyPaise(bill.additionalServicesTotalPaise)),
  ];
}

String _periodLabel(Bill bill) {
  return maintenancePeriodLabel(
    startMonth: DateTime.tryParse(bill.billingPeriodStart) ?? DateTime.now(),
    monthsCovered: bill.numberOfMonths,
    periodEnd: DateTime.tryParse(bill.billingPeriodEnd),
  );
}

String _billStatusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'ISSUED':
      return 'Issued';
    case 'PARTIALLY_PAID':
      return 'Partially paid';
    case 'OVERDUE':
      return 'Overdue';
    case 'PAID':
      return 'Paid';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return humanizeStatus(status);
  }
}

String _paymentMethodLabel(String method) {
  switch (method.toUpperCase()) {
    case 'ONLINE':
    case 'RAZORPAY':
      return 'Online';
    case 'OFFLINE':
      return 'Offline';
    case 'CASH':
      return 'Cash';
    case 'CHEQUE':
      return 'Cheque';
    case 'UPI':
      return 'UPI';
    case 'BANK_TRANSFER':
    case 'NEFT':
      return 'Bank transfer';
    case 'DEMO':
      return 'Demo gateway';
    default:
      return humanizeStatus(method);
  }
}

bool _isOverdue(Bill bill) {
  if (bill.status == 'PAID' || bill.status == 'CANCELLED') return false;
  final due = DateTime.tryParse(bill.dueDate);
  return due != null && due.isBefore(DateTime.now());
}

bool _isSuccessfulPayment(PaymentSummary payment) =>
    payment.status.toUpperCase() == 'SUCCESS';

Future<void> _openPaymentReceipt(
  BuildContext context,
  PaymentSummary payment, {
  required bool resident,
}) async {
  if (!_isSuccessfulPayment(payment)) {
    showWarningSnack(context, 'Receipts are only available for successful payments.');
    return;
  }
  final session = authSession;
  if (session == null) {
    showErrorSnack(context, 'Not signed in.');
    return;
  }
  final receiptId = payment.receiptId;
  if (receiptId != null && receiptId.isNotEmpty) {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveReceiptPage(receiptId: receiptId, resident: resident),
      ),
    );
    return;
  }
  final billing = ensureLiveRepositories(session.api).billing;
  try {
    final detail = await billing.paymentReceipt(payment.id, resident: resident);
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveReceiptPage(
          receiptId: detail.receipt.id,
          resident: resident,
        ),
      ),
    );
    return;
  } catch (_) {
    // Fall through to the existing receipts list if the payment-receipt
    // route is not deployed yet.
  }
  try {
    final listed = resident
        ? await billing.listResidentReceipts(limit: 50)
        : await billing.listAdminReceipts(limit: 50);
    final match = listed.items.where((row) => row.paymentId == payment.id);
    if (match.isEmpty) {
      throw StateError('No confirmed receipt was found for this payment.');
    }
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LiveReceiptPage(receiptId: match.first.id, resident: resident),
      ),
    );
  } catch (e) {
    if (context.mounted) showErrorSnack(context, billingErrorMessage(e));
  }
}

Future<ReceiptDetail> _loadReceiptDetail(
  BuildContext context,
  PaymentSummary payment, {
  required bool resident,
}) async {
  final session = authSession;
  if (session == null) throw StateError('Not signed in.');
  final billing = ensureLiveRepositories(session.api).billing;
  if (payment.receiptId != null && payment.receiptId!.isNotEmpty) {
    return resident
        ? billing.residentReceipt(payment.receiptId!)
        : billing.adminReceipt(payment.receiptId!);
  }
  return billing.paymentReceipt(payment.id, resident: resident);
}

Future<void> _downloadReceiptPdf(ReceiptDetail detail) async {
  final bytes = Uint8List.fromList(base64Decode(detail.pdfBase64));
  await Printing.layoutPdf(
    name: '${detail.receipt.receiptNumber}.pdf',
    onLayout: (_) async => bytes,
  );
}

Future<void> _shareReceiptPdf(ReceiptDetail detail) async {
  final bytes = base64Decode(detail.pdfBase64);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: 'application/pdf',
          name: '${detail.receipt.receiptNumber}.pdf',
        ),
      ],
      text: 'Receipt ${detail.receipt.receiptNumber}',
    ),
  );
}

Future<PaymentSummary?> _latestSuccessfulPaymentForBill(
  Bill bill, {
  required bool resident,
}) async {
  final session = authSession;
  if (session == null) return null;
  final billing = ensureLiveRepositories(session.api).billing;
  final page = resident
      ? await billing.listResidentPayments(
          billId: bill.id, status: 'SUCCESS', limit: 5, force: true)
      : await billing.listAdminPayments(
          billId: bill.id, status: 'SUCCESS', limit: 5, force: true);
  if (page.items.isEmpty) return null;
  return page.items.first;
}

Widget _billShortcutButton({
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
}) {
  return TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: C.navy,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

/// Shared bill row for admin and resident lists.
class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.bill,
    required this.onTap,
    this.showFlat = true,
    this.onRecordPayment,
    this.onDownloadReceipt,
    this.onShareReceipt,
  });
  final Bill bill;
  final VoidCallback onTap;
  final bool showFlat;
  final VoidCallback? onRecordPayment;
  final VoidCallback? onDownloadReceipt;
  final VoidCallback? onShareReceipt;

  @override
  Widget build(BuildContext context) {
    final due = billAmountDuePaise(bill);
    final settled = bill.status == 'PAID' || bill.status == 'CANCELLED';
    final tone = switch (bill.status) {
      'PAID' => C.green,
      'CANCELLED' => C.muted,
      'OVERDUE' => C.error,
      'PARTIALLY_PAID' => C.amber,
      _ => C.blue,
    };
    final hasShortcuts = onRecordPayment != null ||
        onDownloadReceipt != null ||
        onShareReceipt != null;
    return ListRow(
      onTap: onTap,
      leading:
          AppAvatar(icon: Icons.receipt_long_outlined, color: tone, size: 42),
      title: showFlat ? bill.flatLabel : _periodLabel(bill),
      subtitle: showFlat
          ? '${_periodLabel(bill)} · ${bill.billNumber}\n'
              '${_isOverdue(bill) ? 'Was due' : 'Due'} ${fmtIsoDate(bill.dueDate)}'
          : '${bill.billNumber}\n'
              '${_isOverdue(bill) ? 'Was due' : 'Due'} ${fmtIsoDate(bill.dueDate)}',
      badges: [StatusBadge(_billStatusLabel(bill.status))],
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(moneyPaise(settled ? bill.totalAmountPaise : due),
              style: T.money.copyWith(fontSize: 15)),
          Text(
            settled
                ? 'total'
                : bill.interestAccruedPaise > 0
                    ? 'incl. ${moneyPaise(bill.interestAccruedPaise)} interest'
                    : 'due',
            style: T.caption,
          ),
        ],
      ),
      showChevron: !hasShortcuts,
      footer: hasShortcuts
          ? Wrap(
              spacing: 0,
              runSpacing: 0,
              children: [
                if (onRecordPayment != null)
                  _billShortcutButton(
                    icon: Icons.payments_outlined,
                    label: 'Record',
                    onPressed: onRecordPayment!,
                  ),
                if (onDownloadReceipt != null)
                  _billShortcutButton(
                    icon: Icons.download_outlined,
                    label: 'Download',
                    onPressed: onDownloadReceipt!,
                  ),
                if (onShareReceipt != null)
                  _billShortcutButton(
                    icon: Icons.ios_share_outlined,
                    label: 'Share',
                    onPressed: onShareReceipt!,
                  ),
              ],
            )
          : null,
    );
  }
}

/// Shared payment row for admin and resident lists.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, this.onTap, this.onLongPress});
  final PaymentSummary payment;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final status = p.status.toUpperCase();
    final flat = p.displayFlat;
    final (tone, icon, label) = switch (status) {
      'SUCCESS' => (C.green, Icons.check_circle_outline, 'Successful'),
      'FAILED' => (C.error, Icons.error_outline_rounded, 'Failed'),
      'REFUNDED' => (C.muted, Icons.undo_rounded, 'Refunded'),
      'PENDING' || 'PROCESSING' || 'INITIATED' => (
          C.amber,
          Icons.hourglass_top_rounded,
          'Pending'
        ),
      _ => (C.amber, Icons.payments_outlined, humanizeStatus(p.status)),
    };
    final details = [
      if (flat.isNotEmpty) p.paymentNumber,
      _paymentMethodLabel(p.paymentMethod),
      if (p.billNumber != null) p.billNumber!,
      if (p.paidAt != null) fmtIsoDateTime(p.paidAt),
    ].join(' · ');
    return ListRow(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: AppAvatar(icon: icon, color: tone, size: 42),
      title: flat.isNotEmpty ? flat : p.paymentNumber,
      subtitle: details +
          (p.referenceNumber == null ? '' : '\nRef ${p.referenceNumber}'),
      badges: [
        StatusBadge(label,
            tone: status == 'SUCCESS'
                ? BadgeTone.success
                : status == 'FAILED'
                    ? BadgeTone.danger
                    : status == 'REFUNDED'
                        ? BadgeTone.neutral
                        : BadgeTone.warning),
      ],
      trailing: Text(moneyPaise(p.amountPaise),
          style: T.money.copyWith(fontSize: 15, color: tone)),
      showChevron: onTap != null,
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

// ─── Admin bills ─────────────────────────────────────────────────────────────

class LiveAdminBillsPage extends StatefulWidget {
  const LiveAdminBillsPage({super.key});

  @override
  State<LiveAdminBillsPage> createState() => _LiveAdminBillsPageState();
}

class _LiveAdminBillsPageState extends State<LiveAdminBillsPage> {
  String? statusFilter;
  String? wingFilter;
  String? occupancyFilter;
  bool? ownerAssignedFilter;
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
        occupancyStatus: occupancyFilter,
        ownerAssigned: ownerAssignedFilter,
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

  Future<void> _generate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LiveGenerateBillsPage()),
    );
    if (ok == true && mounted) reload(resetPage: true);
  }

  Future<void> _openBill(Bill bill) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAdminBillDetailPage(billId: bill.id),
      ),
    );
    if (mounted) reload();
  }

  Future<void> _recordPayment(Bill bill) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LiveOfflinePaymentPage(bill: bill)),
    );
    if (ok == true && mounted) reload();
  }

  Future<void> _runReceiptAction(
    Bill bill,
    Future<void> Function(ReceiptDetail detail) action,
  ) async {
    try {
      final payment = await _latestSuccessfulPaymentForBill(bill, resident: false);
      if (!mounted) return;
      if (payment == null) {
        showWarningSnack(context, 'No receipt yet for ${bill.flatLabel}.');
        return;
      }
      final detail = await _loadReceiptDetail(context, payment, resident: false);
      if (!mounted) return;
      await action(detail);
    } catch (e) {
      if (mounted) showErrorSnack(context, billingErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminBillsBundle>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
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
        final pagination = bundle.bills.pagination;
        final collectedPct = summary.collectionPercentage.clamp(0, 100);
        return RefreshIndicator(
          color: C.blue,
          onRefresh: () async {
            reload(resetPage: true);
            await _future;
          },
          child: ListView(
            padding: Sp.pagePadding,
            children: [
              HeroMoneyCard(
                label: 'Total payable',
                amount: moneyPaise(billingSummaryPayablePaise(summary)),
                subtitle:
                    'Principal ${moneyPaise(summary.totalOutstandingPrincipalPaise)}'
                    ' · Interest ${moneyPaise(summary.totalAccruedInterestPaise)}'
                    ' · ${summary.billCount} bills',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: C.navy),
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Generate bills'),
                ),
              ),
              const SizedBox(height: 12),
              CollectionBar(
                title: 'Collections',
                progress: collectedPct / 100,
                valueLabel: '${collectedPct.toStringAsFixed(0)}%',
                caption:
                    '${moneyPaise(summary.totalCollectedPaise)} collected of ${moneyPaise(summary.totalBilledPaise)} billed',
              ),
              const SizedBox(height: 12),
              MiniStatStrip(children: [
                MiniStat('Collected', moneyPaise(summary.totalCollectedPaise),
                    tone: BadgeTone.success),
                MiniStat('Overdue bills', '${summary.overdueBills}',
                    tone: BadgeTone.danger),
                MiniStat('Paid bills', '${summary.paidBills}',
                    tone: BadgeTone.success),
                MiniStat('Accrued interest',
                    moneyPaise(summary.totalAccruedInterestPaise)),
              ]),
              const SizedBox(height: 10),
              QuickActionTile(
                icon: Icons.local_parking_outlined,
                label: 'Additional services',
                subtitle: 'Recurring charges on individual flats',
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LiveAdditionalServicesPage()),
                ),
              ),
              const SizedBox(height: 14),
              const SectionTitle('Bills'),
              FilterBar(children: [
                for (final s in const [
                  null,
                  'ISSUED',
                  'OVERDUE',
                  'PAID',
                ])
                  AppFilterChip(
                    label: s == null ? 'All' : _billStatusLabel(s),
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
                for (final w in summary.wingWise)
                  AppFilterChip(
                    label: 'Wing ${w.wingCode}',
                    selected: wingFilter == w.wingCode,
                    onSelected: () {
                      wingFilter = w.wingCode;
                      reload(resetPage: true);
                    },
                  ),
              ]),
              ResultCount(pagination.total, 'bill'),
              if (bills.isEmpty)
                EmptyState(
                  'No bills match these filters',
                  icon: Icons.receipt_long_outlined,
                  actionLabel: 'Clear filters',
                  onAction: () {
                    statusFilter = null;
                    wingFilter = null;
                    occupancyFilter = null;
                    ownerAssignedFilter = null;
                    reload(resetPage: true);
                  },
                )
              else
                ...bills.map((bill) {
                  final open =
                      bill.status != 'PAID' && bill.status != 'CANCELLED';
                  final hasReceipt = bill.amountPaidPaise > 0;
                  return _BillRow(
                    bill: bill,
                    onTap: () => _openBill(bill),
                    onRecordPayment:
                        open ? () => _recordPayment(bill) : null,
                    onDownloadReceipt: hasReceipt
                        ? () => _runReceiptAction(bill, _downloadReceiptPdf)
                        : null,
                    onShareReceipt: hasReceipt
                        ? () => _runReceiptAction(bill, _shareReceiptPdf)
                        : null,
                  );
                }),
              PaginationBar(
                page: pagination.page,
                totalPages: pagination.totalPages,
                onPrevious: () {
                  page -= 1;
                  reload();
                },
                onNext: () {
                  page += 1;
                  reload();
                },
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
  bool reviewing = false;
  String? error;
  List<EligibleFlat>? _eligible;
  bool _loadingEligible = false;

  String get _periodLabel {
    if (months == 1) return monthName(periodStart);
    final end = DateTime(periodStart.year, periodStart.month + months - 1, 1);
    return '${monthName(periodStart)} – ${monthName(end)}';
  }

  Future<void> _openReview() async {
    setState(() {
      error = null;
      reviewing = true;
      _loadingEligible = true;
      _eligible = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final rows = await ensureLiveRepositories(session.api)
          .billing
          .eligibleFlats(force: true);
      if (!mounted) return;
      setState(() {
        _eligible = rows;
        _loadingEligible = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = billingErrorMessage(e);
        _loadingEligible = false;
        reviewing = false;
      });
    }
  }

  Future<void> generate() async {
    final rows = _eligible ?? const <EligibleFlat>[];
    final ok = await confirmDialog(
      context,
      title: 'Create bills now?',
      message:
          'The server will create bills for $_periodLabel across ${rows.length} configured ${rows.length == 1 ? 'flat' : 'flats'}, including vacant and unassigned flats.',
      confirmLabel: 'Create bills',
      icon: Icons.auto_awesome_outlined,
    );
    if (!ok || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final result =
          await ensureLiveRepositories(session.api).billing.generateBills(
                billingPeriodStart: periodStart.toUtc().toIso8601String(),
                numberOfMonths: months,
              );
      ensureLiveRepositories(session.api).invalidateAfterFinancialMutation();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.check_circle_outline_rounded,
              color: C.green, size: 32),
          title: const Text('Bills generated'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DetailRow('Created', '${result.createdCount}', labelWidth: 100),
            DetailRow('Skipped', '${result.skippedCount}', labelWidth: 100),
            DetailRow('Conflicts', '${result.conflictCount}', labelWidth: 100),
            DetailRow('Total billed', moneyPaise(result.totalBilledPaise),
                labelWidth: 100, emphasize: true),
            DetailRow('Due date', fmtIsoDate(result.dueDate), labelWidth: 100),
          ]),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
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
    final rows = _eligible;
    final monthlyTotal = rows == null
        ? 0
        : rows.fold<int>(
            0,
            (sum, f) =>
                sum +
                (f.recurringMonthlyTotalPaise ??
                    f.monthlyRatePaise + f.recurringAdditionalPaise));
    final estimated = monthlyTotal * months;

    return FormScaffold(
      title: reviewing ? 'Review & create' : 'Generate bills',
      actions: reviewing
          ? [
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                          reviewing = false;
                          error = null;
                        }),
                child: const Text('Edit'),
              ),
            ]
          : null,
      bottom: PrimaryButton(
        label: reviewing ? 'Create bills on server' : 'Preview eligible flats',
        icon: reviewing ? Icons.auto_awesome_outlined : Icons.preview_outlined,
        busy: busy || _loadingEligible,
        onPressed: reviewing
            ? (rows == null || rows.isEmpty || _loadingEligible
                ? null
                : generate)
            : _openReview,
      ),
      children: reviewing
          ? [
              if (_loadingEligible)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: LoadingView(label: 'Loading eligible flats…'),
                )
              else ...[
                ReviewSummary(
                  title: 'Billing run',
                  rows: [
                    ('Period', _periodLabel),
                    ('Months', '$months'),
                    ('Eligible flats', '${rows?.length ?? 0}'),
                    (
                      'Est. principal',
                      rows == null ? '—' : moneyPaise(estimated)
                    ),
                  ],
                  note:
                      'Estimate uses current monthly rates plus active additional services × months. The server remains the source of truth for totals, proration and conflicts.',
                ),
                const SizedBox(height: 16),
                SectionTitle('Billable flats',
                    subtitle: 'Every configured flat, including vacant and unassigned'),
                if (rows == null || rows.isEmpty)
                  const EmptyState(
                    'No eligible flats for billing',
                    icon: Icons.apartment_outlined,
                    compact: true,
                  )
                else
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < rows.length && i < 12; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 56, endIndent: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(children: [
                            AppAvatar(
                                text: rows[i].wingCode, square: true, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                rows[i].label,
                                style: T.bodyStrong,
                              ),
                            ),
                            Text(moneyPaise(rows[i].monthlyRatePaise),
                                style: T.money.copyWith(fontSize: 13)),
                          ]),
                        ),
                      ],
                      if (rows.length > 12)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Text(
                            '+ ${rows.length - 12} more flats',
                            style: T.caption,
                          ),
                        ),
                    ]),
                  ),
                InlineError(error),
              ],
            ]
          : [
              const InfoNote(
                'Bills are created for every configured flat. Occupancy, owner assignment and active status do not exclude a flat. Additional services that apply to the period are included automatically.',
              ),
              const SizedBox(height: 20),
              const FormSectionLabel('Billing period'),
              PickerField(
                label: 'Period start',
                icon: Icons.calendar_month_outlined,
                value: monthName(periodStart),
                enabled: !busy,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: periodStart,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    helpText: 'Select billing month',
                  );
                  if (picked != null) {
                    setState(() =>
                        periodStart = DateTime(picked.year, picked.month, 1));
                  }
                },
              ),
              const SizedBox(height: 16),
              const FormSectionLabel('Months covered'),
              ScaleToWidth(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 month')),
                    ButtonSegment(value: 3, label: Text('3 months')),
                  ],
                  selected: {months},
                  onSelectionChanged:
                      busy ? null : (s) => setState(() => months = s.first),
                ),
              ),
              const SizedBox(height: 12),
              Text('Selected: $_periodLabel', style: T.secondary),
              InlineError(error),
            ],
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
      appBar: AppBar(title: const Text('Billable flats')),
      body: FutureBuilder<List<EligibleFlat>>(
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
          final rows = snap.data ?? [];
          Future<void> refresh() async {
            setState(() => _future = _load(force: true));
            await _future;
          }

          if (rows.isEmpty) {
            return _emptyScrollable(
                const EmptyState('No configured flats found',
                    icon: Icons.apartment_outlined),
                refresh);
          }
          final total = rows.fold<int>(0, (sum, f) => sum + f.monthlyRatePaise);
          return RefreshIndicator(
            color: C.blue,
            onRefresh: refresh,
            child: ListView.builder(
              padding: Sp.pagePadding,
              itemCount: rows.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MiniStatStrip(children: [
                      MiniStat('Flats', '${rows.length}'),
                      MiniStat('Monthly total', moneyPaise(total)),
                    ]),
                  );
                }
                final f = rows[i - 1];
                return ListRow(
                  leading: AppAvatar(text: f.wingCode, square: true),
                  title: f.label,
                  subtitle:
                      '${f.flatType} · ${humanizeStatus(f.occupancyStatus)}'
                      '${f.ownerAssigned ? '' : ' · Unassigned'}'
                      '${f.recurringAdditionalPaise > 0 ? ' · Extra ${moneyPaise(f.recurringAdditionalPaise)}' : ''}',
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(moneyPaise(f.monthlyRatePaise),
                          style: T.money.copyWith(fontSize: 14)),
                      Text('per month', style: T.caption),
                    ],
                  ),
                  showChevron: false,
                );
              },
            ),
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
    final currentAdjustPaise = bill.totalAmountPaise - bill.baseAmountPaise;
    final ctrl =
        TextEditingController(text: paiseToRupeeInput(currentAdjustPaise));
    String? fieldError;
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          scrollable: true,
          title: const Text('Adjust bill'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Base amount ${moneyPaise(bill.baseAmountPaise)}. Enter the adjustment in rupees; use a minus sign for a discount.',
              style: T.secondary,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[-\d.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Adjustment (₹)',
                prefixText: '₹ ',
                errorText: fieldError,
                helperText: 'Server sets total = base + adjustment',
              ),
              onChanged: (_) {
                if (fieldError != null) setLocal(() => fieldError = null);
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final raw = ctrl.text.trim();
                final negative = raw.startsWith('-');
                final parsed =
                    parseRupeesToPaise(negative ? raw.substring(1) : raw);
                if (parsed == null) {
                  setLocal(() => fieldError = 'Enter a valid rupee amount.');
                  return;
                }
                Navigator.pop(ctx, negative ? -parsed : parsed);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
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
      showSuccessSnack(context, 'Bill adjusted.');
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, billingErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancel(Bill bill) async {
    final reason = await promptTextDialog(
      context,
      title: 'Cancel this bill?',
      message:
          '${bill.billNumber} for ${bill.flatLabel} will be marked cancelled. This cannot be undone.',
      label: 'Reason',
      confirmLabel: 'Cancel bill',
      cancelLabel: 'Keep bill',
      required: true,
      minLength: 3,
      destructive: true,
      maxLines: 2,
    );
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
      showAppSnack(context, 'Bill cancelled.', tone: SnackTone.warning);
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, billingErrorMessage(e));
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
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
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
          final due = billAmountDuePaise(bill);
          final open = bill.status != 'CANCELLED' && bill.status != 'PAID';
          final adjustPaise = bill.totalAmountPaise - bill.baseAmountPaise;
          return RefreshIndicator(
            color: C.blue,
            onRefresh: () async {
              setState(() => _future = _load(force: true));
              await _future;
            },
            child: ListView(
              padding: Sp.pagePadding,
              children: [
                _BillHeader(bill: bill),
                const SizedBox(height: 16),
                HeroMoneyCard(
                  label: open ? 'Amount due' : (bill.status == 'PAID' ? 'Outstanding' : 'Bill total'),
                  amount: moneyPaise(
                      bill.status == 'CANCELLED' ? bill.totalAmountPaise : due),
                  subtitle: open
                      ? 'Principal ${moneyPaise(bill.outstandingPrincipalPaise)} · Interest ${moneyPaise(bill.interestOutstandingPaise ?? interest.accruedInterestPaise)}'
                      : bill.status == 'PAID'
                          ? 'Paid ${moneyPaise(bill.amountPaidPaise)} · Outstanding ${moneyPaise(0)}'
                          : 'Paid ${moneyPaise(bill.amountPaidPaise)}',
                ),
                const SizedBox(height: 14),
                DetailCard(title: 'Bill', children: [
                  DetailRow('Period', _periodLabel(bill)),
                  DetailRow('Due date', fmtIsoDate(bill.dueDate)),
                  DetailRow('Owner', bill.ownerNameSnapshot),
                  DetailRow('Flat type', bill.flatTypeSnapshot),
                ]),
                DetailCard(title: 'Breakdown', children: [
                  ..._billBreakdownRows(bill),
                  if (adjustPaise != 0)
                    DetailRow('Adjustment',
                        '${adjustPaise < 0 ? '−' : '+'}${moneyPaise(adjustPaise.abs())}'),
                  DetailRow('Original bill amount',
                      moneyPaise(bill.totalAmountPaise),
                      emphasize: true),
                  DetailRow('Paid', moneyPaise(bill.amountPaidPaise)),
                  DetailRow('Outstanding principal',
                      moneyPaise(bill.outstandingPrincipalPaise)),
                  DetailRow('Accrued interest',
                      moneyPaise(interest.accruedInterestPaise)),
                  DetailRow('Interest paid',
                      moneyPaise(bill.interestPaidPaise)),
                  DetailRow('Interest outstanding',
                      moneyPaise(bill.interestOutstandingPaise ??
                          (open ? interest.accruedInterestPaise : 0))),
                  DetailRow('Total payable',
                      moneyPaise(due),
                      emphasize: true),
                ]),
                DetailCard(title: 'Late-payment interest', children: [
                  DetailRow('Accrued interest',
                      moneyPaise(interest.accruedInterestPaise),
                      emphasize: true),
                  DetailRow('Overdue days', '${interest.overdueDays}'),
                  DetailRow('Annual rate',
                      '${interest.annualInterestRatePercent}% p.a.'),
                  DetailRow('As of', fmtIsoDate(interest.asOf)),
                ]),
                if (interest.segments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const SectionTitle('Interest segments'),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Column(children: [
                      for (var i = 0; i < interest.segments.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${fmtIsoDate(interest.segments[i].from)} → ${fmtIsoDate(interest.segments[i].to)}',
                                        style: T.bodyStrong),
                                    const SizedBox(height: 2),
                                    Text(
                                        '${interest.segments[i].days} days on ${moneyPaise(interest.segments[i].principalPaise)}',
                                        style: T.caption),
                                  ]),
                            ),
                            Text(moneyPaise(interest.segments[i].interestPaise),
                                style: T.money.copyWith(fontSize: 14)),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                const SectionTitle('Collect & manage'),
                if (!open && bill.amountPaidPaise > 0)
                  const EmptyState('This bill is settled. No further actions.',
                      icon: Icons.lock_outline_rounded, compact: true)
                else
                  ActionRail(
                    busy: busy,
                    primary: open
                        ? ToolLink(
                            icon: Icons.payments_outlined,
                            label: 'Record offline payment',
                            subtitle: 'Cash, cheque or bank transfer received',
                            onTap: () => _offline(bill),
                          )
                        : null,
                    secondary: [
                      if (open)
                        ToolLink(
                          icon: Icons.tune_rounded,
                          label: 'Adjust bill',
                          subtitle: 'Charge or discount against the base',
                          onTap: () => _adjust(bill),
                        ),
                      if (bill.status != 'CANCELLED' &&
                          bill.amountPaidPaise == 0)
                        ToolLink(
                          icon: Icons.cancel_outlined,
                          label: 'Cancel bill',
                          subtitle: 'Only before any payment is recorded',
                          onTap: () => _cancel(bill),
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

class _BillHeader extends StatelessWidget {
  const _BillHeader({required this.bill});
  final Bill bill;
  @override
  Widget build(BuildContext context) => DetailHero(
        title: _periodLabel(bill),
        subtitle:
            '${bill.flatLabel} · ${bill.billNumber}',
        leading: const AppAvatar(
            icon: Icons.receipt_long_outlined, size: Sz.avatarLg, square: true),
        badges: [
          StatusBadge(_billStatusLabel(bill.status)),
          if (_isOverdue(bill) && bill.status != 'OVERDUE')
            const StatusBadge('Past due date', tone: BadgeTone.danger),
        ],
      );
}

class _BillDetailBundle {
  const _BillDetailBundle({
    required this.bill,
    required this.interest,
    this.payments = const [],
  });
  final Bill bill;
  final InterestBreakdown interest;
  final List<PaymentSummary> payments;
}

class LiveOfflinePaymentPage extends StatefulWidget {
  const LiveOfflinePaymentPage({super.key, required this.bill});
  final Bill bill;
  @override
  State<LiveOfflinePaymentPage> createState() => _LiveOfflinePaymentPageState();
}

class _LiveOfflinePaymentPageState extends State<LiveOfflinePaymentPage> {
  final _form = GlobalKey<FormState>();
  final reference = TextEditingController();
  final notes = TextEditingController();
  late final amount = TextEditingController(
      text: paiseToRupeeInput(billAmountDuePaise(widget.bill)));
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
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    final amountPaise = parseRupeesToPaise(amount.text)!;
    final ok = await confirmDialog(
      context,
      title: 'Record ${moneyPaise(amountPaise)}?',
      message:
          'Offline payment for ${widget.bill.billNumber} with reference “${reference.text.trim()}” will be recorded on the server.',
      confirmLabel: 'Record payment',
      icon: Icons.payments_outlined,
    );
    if (!ok || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final idempotencyKey =
          'offline-${widget.bill.id}-${reference.text.trim()}-$amountPaise';
      final result = await ensureLiveRepositories(session.api)
          .billing
          .recordOfflinePayment(
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
      showSuccessSnack(
          context,
          result.alreadySettled
              ? 'Payment already settled.'
              : 'Offline payment recorded.');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = billingErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return FormScaffold(
      title: 'Record offline payment',
      formKey: _form,
      bottom: PrimaryButton(
        label: 'Review & record',
        icon: Icons.check_rounded,
        busy: busy,
        onPressed: submit,
      ),
      children: [
        ReviewSummary(
          title: 'Applying to',
          rows: [
            ('Bill', bill.billNumber),
            ('Flat', bill.flatLabel),
            ('Period', _periodLabel(bill)),
            (
              'Outstanding principal',
              moneyPaise(bill.outstandingPrincipalPaise)
            ),
            (
              'Accrued interest',
              moneyPaise(bill.interestAccruedPaise)
            ),
            (
              'Amount due',
              moneyPaise(billAmountDuePaise(bill))
            ),
          ],
        ),
        const SizedBox(height: 8),
        const FormSectionLabel('Payment received'),
        TextFormField(
          controller: amount,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Amount received (₹) *',
            prefixText: '₹ ',
            helperText:
                'Defaults to principal plus current overdue interest. The server recalculates interest at settlement.',
          ),
          validator: (v) {
            final paise = parseRupeesToPaise(v ?? '');
            if (paise == null) return 'Enter a valid rupee amount.';
            if (paise <= 0) return 'Amount must be greater than zero.';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: reference,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Reference number *',
            hintText: 'Cheque no., UTR or receipt book no.',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Reference number is required.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: notes,
          enabled: !busy,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => busy ? null : submit(),
          decoration: const InputDecoration(
            labelText: 'Notes',
            alignLabelWithHint: true,
          ),
        ),
        InlineError(error),
      ],
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

  Future<void> _refresh() async {
    setState(() => _future = _load(force: true));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paged<PaymentSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 6, showHeader: true);
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            onRetry: () => setState(() => _future = _load(force: true)),
          );
        }
        final rows = snap.data?.items ?? [];
        if (rows.isEmpty) {
          return _emptyScrollable(
              const EmptyState('No payments recorded yet',
                  icon: Icons.payments_outlined),
              _refresh);
        }
        final successTotal = rows
            .where((p) => p.status.toUpperCase() == 'SUCCESS')
            .fold<int>(0, (s, p) => s + p.amountPaise);
        return RefreshIndicator(
          color: C.blue,
          onRefresh: _refresh,
          child: ListView.builder(
            padding: Sp.pagePadding,
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PageHeader('Payments',
                          subtitle: 'Latest 50 payments across the society'),
                      MiniStatStrip(children: [
                        MiniStat('Shown', '${rows.length}'),
                        MiniStat('Successful total', moneyPaise(successTotal),
                            tone: BadgeTone.success),
                      ]),
                      const SizedBox(height: 8),
                      Text('Long-press a successful payment to refund it.',
                          style: T.caption.copyWith(color: C.faint)),
                      const SizedBox(height: 10),
                    ]);
              }
              final p = rows[i - 1];
              return _PaymentRow(
                payment: p,
                onTap: () => _showPayment(p),
                onLongPress: p.status == 'SUCCESS' ? () => _refund(p) : null,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showPayment(PaymentSummary p) async {
    await showAppSheet<void>(
      context,
      title: p.paymentNumber,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailRow('Amount', moneyPaise(p.amountPaise), emphasize: true),
          DetailRow('To principal', moneyPaise(p.allocatedToPrincipalPaise)),
          DetailRow('To interest', moneyPaise(p.allocatedToInterestPaise)),
          DetailRow('Method', _paymentMethodLabel(p.paymentMethod)),
          DetailRow('Status', '',
              valueWidget: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(p.status))),
          DetailRow('Paid at', fmtIsoDateTime(p.paidAt)),
          if (p.displayFlat.isNotEmpty) DetailRow('Flat', p.displayFlat),
          if (p.billNumber != null) DetailRow('Bill', p.billNumber!),
          if (p.referenceNumber != null)
            DetailRow('Reference', p.referenceNumber!),
          if (p.gatewayPaymentId != null)
            DetailRow('Gateway payment', p.gatewayPaymentId!),
          if (_isSuccessfulPayment(p)) ...[
            const SizedBox(height: 14),
            PrimaryButton(
              label: 'Download Receipt',
              icon: Icons.download_outlined,
              onPressed: () {
                Navigator.pop(ctx);
                _openPaymentReceipt(context, p, resident: false);
              },
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Refund payment',
              icon: Icons.undo_rounded,
              destructive: true,
              onPressed: () {
                Navigator.pop(ctx);
                _refund(p);
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refund(PaymentSummary payment) async {
    final reason = await promptTextDialog(
      context,
      title: 'Refund ${moneyPaise(payment.amountPaise)}?',
      message:
          'Payment ${payment.paymentNumber} will be marked refunded on the server. This cannot be undone.',
      label: 'Reason',
      confirmLabel: 'Refund',
      required: true,
      minLength: 3,
      destructive: true,
      maxLines: 2,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      final session = authSession!;
      await ensureLiveRepositories(session.api)
          .billing
          .refundPayment(payment.id, reason: reason);
      ensureLiveRepositories(session.api).invalidateAfterFinancialMutation();
      if (!mounted) return;
      showAppSnack(context, 'Payment refunded.', tone: SnackTone.warning);
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, billingErrorMessage(e));
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
  String _filter = 'open'; // open | all

  Future<Paged<Bill>> _load({bool force = false}) async {
    if (!widget.canFinance) {
      throw StateError('Financial access is not available for this account.');
    }
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    return ensureLiveRepositories(session.api).billing.listResidentBills(
        force: force, query: const ListBillsQuery(limit: 50));
  }

  Future<void> _refresh() async {
    setState(() => _future = _load(force: true));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canFinance) {
      return const EmptyState(
          'Financial access is not available for this account.',
          icon: Icons.lock_outline_rounded);
    }
    return FutureBuilder<Paged<Bill>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            title: 'Could not load bills',
            onRetry: () => setState(() => _future = _load(force: true)),
          );
        }
        final all = snap.data?.items ?? [];
        if (all.isEmpty) {
          return _emptyScrollable(
              const EmptyState('No bills found for your flats yet',
                  icon: Icons.receipt_long_outlined),
              _refresh);
        }
        final open = all
            .where((b) => b.status != 'PAID' && b.status != 'CANCELLED')
            .toList();
        final duePaise = open.fold<int>(0, (s, b) => s + billAmountDuePaise(b));
        final overdue = open.where(_isOverdue).length;
        final rows = _filter == 'open' ? open : all;
        return RefreshIndicator(
          color: C.blue,
          onRefresh: _refresh,
          child: ListView(
            padding: Sp.pagePadding,
            children: [
              if (open.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: InfoNote(
                    'No prepaid balance. Pay 3 months in advance if your society offers a discount.',
                    tone: NoteTone.success,
                  ),
                ),
              HeroMoneyCard(
                label: 'Total outstanding',
                amount: moneyPaise(duePaise),
                subtitle: open.isEmpty
                    ? 'All bills are settled.'
                    : '${open.length} open ${open.length == 1 ? 'bill' : 'bills'}'
                        '${overdue > 0 ? ' · $overdue overdue' : ''}',
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilterBar(children: [
                    AppFilterChip(
                      label: 'Open (${open.length})',
                      selected: _filter == 'open',
                      onSelected: () => setState(() => _filter = 'open'),
                    ),
                    AppFilterChip(
                      label: 'All (${all.length})',
                      selected: _filter == 'all',
                      onSelected: () => setState(() => _filter = 'all'),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              if (rows.isEmpty)
                const EmptyState('No open bills. You’re all caught up.',
                    icon: Icons.check_circle_outline_rounded, compact: true)
              else
                ...rows.map((bill) => _BillRow(
                      bill: bill,
                      showFlat: true,
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LiveOwnerBillDetailPage(billId: bill.id),
                          ),
                        );
                        if (mounted) {
                          setState(() => _future = _load(force: true));
                        }
                      },
                    )),
            ],
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
    final payments = await repos.billing.listResidentPayments(
      billId: widget.billId,
      force: force,
      limit: 50,
    );
    return _BillDetailBundle(
      bill: bill,
      interest: interest,
      payments: payments.items,
    );
  }

  Future<void> _pay(Bill bill) async {
    if (paying) return;
    if (billAmountDuePaise(bill) <= 0) {
      showWarningSnack(context, 'This bill is already settled.');
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
          showWarningSnack(context, 'Payment cancelled.');
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
          showErrorSnack(context, 'Demo payment failed (simulated).');
          setState(() => _future = _load(force: true));
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
          showWarningSnack(context, 'Payment cancelled.');
          return;
        }
        if (!checkout.isSuccess) {
          showErrorSnack(context, checkout.errorMessage ?? 'Payment failed');
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
        showSuccessSnack(context, 'Payment verified. Receipt is ready.');
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LiveReceiptPage(
                receiptId: settlement.receiptId!, resident: true),
          ),
        );
      } else {
        showInfoSnack(
            context,
            settlement.alreadySettled
                ? 'Payment already settled. Refreshing…'
                : 'Payment submitted. Waiting for final settlement — pull to refresh.');
      }
      setState(() => _future = _load(force: true));
    } catch (e) {
      if (!mounted) return;
      showErrorSnack(context, billingErrorMessage(e));
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
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
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
          final payments = snap.data!.payments;
          final due = billAmountDuePaise(bill);
          final payable = due > 0 && bill.status != 'CANCELLED';
          final open = bill.status != 'PAID' && bill.status != 'CANCELLED';
          final successful = payments.where(_isSuccessfulPayment).toList();
          final adjustPaise = bill.totalAmountPaise - bill.baseAmountPaise;
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                color: C.blue,
                onRefresh: () async {
                  setState(() => _future = _load(force: true));
                  await _future;
                },
                child: ListView(
                  padding: Sp.pagePadding,
                  children: [
                    _BillHeader(bill: bill),
                    const SizedBox(height: 16),
                    HeroMoneyCard(
                      label: open ? 'Amount due' : 'Outstanding',
                      amount: moneyPaise(
                          bill.status == 'CANCELLED' ? bill.totalAmountPaise : due),
                      subtitle: open
                          ? 'Principal ${moneyPaise(bill.outstandingPrincipalPaise)} · Interest ${moneyPaise(bill.interestOutstandingPaise ?? interest.accruedInterestPaise)}'
                          : bill.status == 'PAID'
                              ? 'Paid ${moneyPaise(bill.amountPaidPaise)} · Outstanding ${moneyPaise(0)}'
                              : 'Paid ${moneyPaise(bill.amountPaidPaise)}',
                    ),
                    const SizedBox(height: 14),
                    DetailCard(title: 'Bill', children: [
                      DetailRow('Period', _periodLabel(bill)),
                      DetailRow('Due date', fmtIsoDate(bill.dueDate)),
                      DetailRow('Flat',
                          bill.flatLabel),
                      DetailRow('Bill number', bill.billNumber),
                      DetailRow('Status', '',
                          valueWidget: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(_billStatusLabel(bill.status)))),
                    ]),
                    DetailCard(title: 'Breakdown', children: [
                      ..._billBreakdownRows(bill),
                      if (adjustPaise != 0)
                        DetailRow('Adjustment',
                            '${adjustPaise < 0 ? '−' : '+'}${moneyPaise(adjustPaise.abs())}'),
                      DetailRow('Original bill amount',
                          moneyPaise(bill.totalAmountPaise),
                          emphasize: true),
                      DetailRow(
                          'Paid so far', moneyPaise(bill.amountPaidPaise)),
                      DetailRow('Outstanding principal',
                          moneyPaise(bill.outstandingPrincipalPaise)),
                      DetailRow('Accrued interest',
                          moneyPaise(interest.accruedInterestPaise)),
                      DetailRow('Interest paid',
                          moneyPaise(bill.interestPaidPaise)),
                      DetailRow('Interest outstanding',
                          moneyPaise(bill.interestOutstandingPaise ??
                              (open ? interest.accruedInterestPaise : 0))),
                      DetailRow('Outstanding',
                          moneyPaise(due),
                          emphasize: true),
                    ]),
                    if (payments.isNotEmpty)
                      DetailCard(title: 'Payments', children: [
                        for (final payment in payments) ...[
                          DetailRow(
                            payment.paymentNumber,
                            '${moneyPaise(payment.amountPaise)} · ${_paymentMethodLabel(payment.paymentMethod)}',
                          ),
                          DetailRow(
                            'Status',
                            '',
                            valueWidget: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(
                                _isSuccessfulPayment(payment)
                                    ? 'SUCCESSFUL'
                                    : payment.status,
                              ),
                            ),
                          ),
                          if (payment.paidAt != null)
                            DetailRow('Paid at', fmtIsoDateTime(payment.paidAt)),
                          if (_isSuccessfulPayment(payment))
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 8),
                              child: SecondaryButton(
                                label: 'Download Receipt',
                                icon: Icons.download_outlined,
                                onPressed: () => _openPaymentReceipt(
                                  context,
                                  payment,
                                  resident: true,
                                ),
                              ),
                            ),
                        ],
                      ]),
                    if (open)
                      DetailCard(title: 'Late-payment interest', children: [
                        DetailRow('Accrued interest',
                            moneyPaise(interest.accruedInterestPaise),
                            emphasize: true),
                        DetailRow('Overdue days', '${interest.overdueDays}'),
                        DetailRow('Annual rate',
                            '${interest.annualInterestRatePercent}% p.a.'),
                      ]),
                    const InfoNote(
                      'Interest accrues automatically after the due date. '
                      'The society server calculates simple daily interest. '
                      'This app never recalculates interest locally.',
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (payable || successful.isNotEmpty)
              BottomActionBar(children: [
                if (payable)
                  PrimaryButton(
                    label: 'Pay ${moneyPaise(due)}',
                    icon: Icons.lock_outline_rounded,
                    busy: paying,
                    onPressed: () => _pay(bill),
                  ),
                if (successful.isNotEmpty)
                  PrimaryButton(
                    label: 'Download Receipt',
                    icon: Icons.download_outlined,
                    onPressed: () => _openPaymentReceipt(
                      context,
                      successful.first,
                      resident: true,
                    ),
                  ),
              ]),
          ]);
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

  Future<void> _refresh() async {
    setState(() => _future = _load(force: true));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canFinance) {
      return const EmptyState(
          'Financial access is not available for this account.',
          icon: Icons.lock_outline_rounded);
    }
    return FutureBuilder<Paged<PaymentSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SkeletonList(items: 5, showHeader: true);
        }
        if (snap.hasError) {
          return LoadFailure(
            error: snap.error!,
            onRetry: () => setState(() => _future = _load(force: true)),
          );
        }
        final rows = snap.data?.items ?? [];
        if (rows.isEmpty) {
          return _emptyScrollable(
              const EmptyState('No payment history yet',
                  icon: Icons.payments_outlined),
              _refresh);
        }
        final paidTotal = rows
            .where((p) => p.status.toUpperCase() == 'SUCCESS')
            .fold<int>(0, (s, p) => s + p.amountPaise);
        return RefreshIndicator(
          color: C.blue,
          onRefresh: _refresh,
          child: ListView.builder(
            padding: Sp.pagePadding,
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MiniStatStrip(children: [
                    MiniStat('Payments', '${rows.length}'),
                    MiniStat('Paid (successful)', moneyPaise(paidTotal),
                        tone: BadgeTone.success),
                  ]),
                );
              }
              final p = rows[i - 1];
              return _PaymentRow(
                payment: p,
                onTap: () => showAppSheet<void>(
                  context,
                  title: p.paymentNumber,
                  builder: (ctx) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailRow('Amount', moneyPaise(p.amountPaise),
                          emphasize: true),
                      DetailRow('To principal',
                          moneyPaise(p.allocatedToPrincipalPaise)),
                      DetailRow('To interest',
                          moneyPaise(p.allocatedToInterestPaise)),
                      DetailRow('Method', _paymentMethodLabel(p.paymentMethod)),
                      DetailRow('Status', '',
                          valueWidget: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(p.status))),
                      DetailRow('Paid at', fmtIsoDateTime(p.paidAt)),
                      if (p.displayFlat.isNotEmpty)
                        DetailRow('Flat', p.displayFlat),
                      if (p.billNumber != null) DetailRow('Bill', p.billNumber!),
                      if (p.referenceNumber != null)
                        DetailRow('Reference', p.referenceNumber!),
                      if (_isSuccessfulPayment(p)) ...[
                        const SizedBox(height: 14),
                        PrimaryButton(
                          label: 'Download Receipt',
                          icon: Icons.download_outlined,
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openPaymentReceipt(context, p, resident: true);
                          },
                        ),
                      ],
                    ],
                  ),
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
  bool _sharing = false;
  bool _downloading = false;

  Future<ReceiptDetail> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final billing = ensureLiveRepositories(session.api).billing;
    return widget.resident
        ? billing.residentReceipt(widget.receiptId, force: force)
        : billing.adminReceipt(widget.receiptId, force: force);
  }

  Future<void> _share(ReceiptDetail detail) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = base64Decode(detail.pdfBase64);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: 'application/pdf',
              name: '${detail.receipt.receiptNumber}.pdf',
            ),
          ],
          text: 'Receipt ${detail.receipt.receiptNumber}',
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not share the receipt.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _download(ReceiptDetail detail) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = Uint8List.fromList(base64Decode(detail.pdfBase64));
      await Printing.layoutPdf(
        name: '${detail.receipt.receiptNumber}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not open the receipt PDF.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: FutureBuilder<ReceiptDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
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
                      Text(r.receiptNumber, style: T.secondary),
                      const SizedBox(height: 14),
                      Text(moneyPaise(r.amountPaise),
                          style: T.display.copyWith(color: C.blue)),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  DetailCard(children: [
                    DetailRow('Paid at', fmtIsoDateTime(r.paidAt)),
                    DetailRow('Method', _paymentMethodLabel(r.paymentMethod)),
                    DetailRow('Flat',
                        r.flatLabel),
                    DetailRow('Owner', r.ownerNameSnapshot),
                    DetailRow('Status', '',
                        valueWidget: const Align(
                          alignment: Alignment.centerLeft,
                          child: StatusBadge('SUCCESSFUL',
                              tone: BadgeTone.success),
                        )),
                    if (r.transactionReference != null)
                      DetailRow('Reference', r.transactionReference!),
                    DetailRow('Generated', fmtIsoDateTime(r.generatedAt)),
                  ]),
                ],
              ),
            ),
            BottomActionBar(children: [
              PrimaryButton(
                label: 'Download Receipt',
                icon: Icons.download_outlined,
                busy: _downloading,
                onPressed: () => _download(detail),
              ),
              SecondaryButton(
                label: 'Share PDF receipt',
                icon: Icons.ios_share_outlined,
                busy: _sharing,
                onPressed: () => _share(detail),
              ),
            ]),
          ]);
        },
      ),
    );
  }
}
