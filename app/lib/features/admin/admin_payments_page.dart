import 'package:flutter/material.dart';

import '../../api/models/billing_models.dart';
import '../../api/models/common.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import 'admin_dashboard.dart';

const _kPayBrand800 = Color(0xFF153B69);
const _kPayBrand900 = Color(0xFF0E2747);
const _kPayBrand50 = Color(0xFFEEF4FC);
const _kPayBrand100 = Color(0xFFD9E7F8);
const _kPaySuccess = Color(0xFF0D894F);
const _kPaySuccessBg = Color(0xFFE7F7EF);
const _kPaySuccessBorder = Color(0xFFC2EED6);
const _kPayNeutral = Color(0xFF61677D);
const _kPayBorder = Color(0xFFE4E7F3);
const _kPayRose = Color(0xFFE11D48);
const _kPayRoseSoft = Color(0xFFFFF1F2);
const _kPayRoseBorder = Color(0xFFFECDD3);
const _kPayAmber = Color(0xFFD97706);
const _kPayAmberSoft = Color(0xFFFFFBEB);
const _kPayAmberBorder = Color(0xFFFDE68A);

bool adminPaymentIsOffline(String method) {
  switch (method.toUpperCase()) {
    case 'OFFLINE':
    case 'CASH':
    case 'CHEQUE':
    case 'NEFT':
    case 'BANK_TRANSFER':
      return true;
    default:
      return false;
  }
}

bool adminPaymentIsCancellable(PaymentSummary payment) {
  if (payment.status.toUpperCase() != 'SUCCESS') return false;
  if ((payment.gatewayOrderId ?? '').trim().isNotEmpty) return false;
  switch (payment.paymentMethod.toUpperCase()) {
    case 'OFFLINE':
    case 'CASH':
    case 'CHEQUE':
    case 'NEFT':
    case 'BANK_TRANSFER':
    case 'UPI':
      return true;
    default:
      return false;
  }
}

String adminPaymentMethodLabel(String method) {
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
    case 'NEFT':
      return 'NEFT';
    case 'BANK_TRANSFER':
      return 'Bank transfer';
    case 'DEMO':
      return 'Demo gateway';
    default:
      return humanizeStatus(method);
  }
}

String adminPaymentStatusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'SUCCESS':
      return 'Successful';
    case 'FAILED':
      return 'Failed';
    case 'REFUNDED':
      return 'Cancelled';
    case 'PENDING':
    case 'PROCESSING':
    case 'INITIATED':
      return 'Pending';
    default:
      return humanizeStatus(status);
  }
}

String adminPaymentCaption(PaymentSummary payment) {
  final ref = (payment.referenceNumber ?? '').trim();
  if (ref.isEmpty) return '';
  if (payment.paymentMethod.toUpperCase() == 'CHEQUE') return 'Cheque #$ref';
  return ref;
}

List<String> adminPaymentWings(Iterable<PaymentSummary> payments) {
  final seen = <String>{};
  final wings = <String>[];
  for (final payment in payments) {
    final wing = (payment.wingCodeSnapshot ?? '').trim();
    if (wing.isEmpty) continue;
    final key = wing.toUpperCase();
    if (seen.add(key)) wings.add(key);
  }
  wings.sort();
  return wings;
}

bool adminPaymentMatches(
  PaymentSummary payment, {
  required String query,
  String? wing,
  String? status,
  bool offlineOnly = false,
}) {
  if (wing != null &&
      (payment.wingCodeSnapshot ?? '').trim().toUpperCase() !=
          wing.toUpperCase()) {
    return false;
  }
  if (status != null && payment.status.toUpperCase() != status.toUpperCase()) {
    return false;
  }
  if (offlineOnly && !adminPaymentIsOffline(payment.paymentMethod)) {
    return false;
  }
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = [
    payment.displayFlat,
    payment.paymentNumber,
    payment.billNumber ?? '',
    payment.referenceNumber ?? '',
    payment.gatewayPaymentId ?? '',
    adminPaymentMethodLabel(payment.paymentMethod),
    payment.paymentMethod,
    payment.status,
  ].join(' ').toLowerCase();
  return hay.contains(q);
}

int adminPaymentSuccessTotalPaise(Iterable<PaymentSummary> payments) {
  return payments.fold<int>(0, (sum, payment) {
    if (payment.status.toUpperCase() != 'SUCCESS') return sum;
    return sum + payment.amountPaise;
  });
}

class AdminPaymentsHeader extends StatelessWidget {
  const AdminPaymentsHeader({
    super.key,
    required this.onRecord,
    this.subtitle = 'Payments across the society',
  });

  final VoidCallback onRecord;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payments Ledger',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kPayBrand900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: _kPayNeutral,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: TextButton.icon(
            onPressed: onRecord,
            style: TextButton.styleFrom(
              foregroundColor: _kPayBrand800,
              backgroundColor: _kPayBrand50,
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: _kPayBrand100),
              ),
            ),
            icon: const Icon(Icons.add, size: 14),
            label: const Text(
              'Record',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminPaymentsMetrics extends StatelessWidget {
  const AdminPaymentsMetrics({
    super.key,
    required this.shownCount,
    required this.successTotal,
  });

  final int shownCount;
  final String successTotal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final w = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: w,
              child: _MetricCard(
                value: '$shownCount',
                label: 'Shown transactions',
                valueColor: _kPayBrand900,
                dotColor: const Color(0xFF3B82F6),
              ),
            ),
            SizedBox(
              width: w,
              child: _MetricCard(
                value: successTotal,
                label: 'Successful total',
                valueColor: _kPaySuccess,
                dotColor: const Color(0xFF10B981),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.dotColor,
  });

  final String value;
  final String label;
  final Color valueColor;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPayBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D153B69),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: valueColor,
                height: 1.1,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _kPayNeutral,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdminPaymentsCancelTip extends StatelessWidget {
  const AdminPaymentsCancelTip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xB3EEF4FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPayBrand100),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Color(0xFF255E9C)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Long-press an office payment to cancel it if it was recorded by mistake.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A4778),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminPaymentsSearchBar extends StatelessWidget {
  const AdminPaymentsSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPayBorder),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AdminDash.onSurface,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search flat (e.g. A-102), txn ID, or mode...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              IconButton(
                tooltip: 'Filters',
                visualDensity: VisualDensity.compact,
                onPressed: onFilter,
                icon: const Icon(Icons.filter_alt_outlined, size: 16),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AdminPaymentsFilterChips extends StatelessWidget {
  const AdminPaymentsFilterChips({
    super.key,
    required this.wings,
    required this.counts,
    required this.selectedWing,
    required this.statusFilter,
    required this.offlineOnly,
    required this.onSelectAll,
    required this.onSelectWing,
    required this.onToggleSuccessful,
    required this.onToggleOffline,
  });

  final List<String> wings;
  final Map<String, int> counts;
  final String? selectedWing;
  final String? statusFilter;
  final bool offlineOnly;
  final VoidCallback onSelectAll;
  final ValueChanged<String> onSelectWing;
  final VoidCallback onToggleSuccessful;
  final VoidCallback onToggleOffline;

  @override
  Widget build(BuildContext context) {
    final allSelected =
        selectedWing == null && statusFilter == null && !offlineOnly;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            label: 'All (${counts['ALL'] ?? 0})',
            selected: allSelected,
            onTap: onSelectAll,
          ),
          for (final wing in wings) ...[
            const SizedBox(width: 6),
            _Chip(
              label: 'Wing $wing (${counts[wing] ?? 0})',
              selected: selectedWing == wing,
              onTap: () => onSelectWing(wing),
            ),
          ],
          const SizedBox(width: 6),
          _Chip(
            label: 'Successful',
            selected: statusFilter == 'SUCCESS',
            success: true,
            onTap: onToggleSuccessful,
          ),
          const SizedBox(width: 6),
          _Chip(
            label: 'Offline Only',
            selected: offlineOnly,
            onTap: onToggleOffline,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.success = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final selectedFill = success ? _kPaySuccessBg : _kPayBrand800;
    final selectedFg = success ? _kPaySuccess : Colors.white;
    final unselectedFg = success ? _kPaySuccess : const Color(0xFF475569);
    return Material(
      color: selected
          ? (success ? _kPaySuccessBg : selectedFill)
          : Colors.white,
      borderRadius: BorderRadius.circular(Rd.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.pill),
            border: Border.all(
              color: selected
                  ? (success ? _kPaySuccessBorder : _kPayBrand800)
                  : (success ? const Color(0xCCA7F3D0) : _kPayBorder),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (success) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? selectedFg : unselectedFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminPaymentCard extends StatelessWidget {
  const AdminPaymentCard({
    super.key,
    required this.payment,
    required this.onTap,
    this.onLongPress,
  });

  final PaymentSummary payment;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final status = payment.status.toUpperCase();
    final successful = status == 'SUCCESS';
    final (icon, bg, border, fg) = switch (status) {
      'SUCCESS' => (
          Icons.check_rounded,
          _kPaySuccessBg,
          _kPaySuccessBorder,
          _kPaySuccess,
        ),
      'FAILED' => (
          Icons.close_rounded,
          _kPayRoseSoft,
          _kPayRoseBorder,
          _kPayRose,
        ),
      'REFUNDED' => (
          Icons.undo_rounded,
          AdminDash.container,
          AdminDash.outlineVariant,
          AdminDash.outline,
        ),
      _ => (
          Icons.hourglass_top_rounded,
          _kPayAmberSoft,
          _kPayAmberBorder,
          _kPayAmber,
        ),
    };
    final flat = payment.displayFlat.isEmpty ? '—' : payment.displayFlat;
    final amountColor = successful ? _kPaySuccess : AdminDash.onSurface;
    final meta = [
      payment.paymentNumber,
      adminPaymentMethodLabel(payment.paymentMethod),
      if ((payment.billNumber ?? '').isNotEmpty) payment.billNumber!,
      if ((payment.paidAt ?? '').isNotEmpty) fmtIsoDateTime(payment.paidAt),
    ].join(' • ');
    final caption = adminPaymentCaption(payment);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kPayBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D153B69),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                ),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            flat,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AdminDash.onSurface,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    moneyPaise(payment.amountPaise),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: amountColor,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: _kPayNeutral,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: border),
                          ),
                          child: Text(
                            adminPaymentStatusLabel(status),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                        ),
                        if (caption.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              caption,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showAdminPaymentStatusSheet(
  BuildContext context, {
  required String? selected,
  required ValueChanged<String?> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AdminDash.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payment status',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AdminDash.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              for (final item in const [
                (null, 'All statuses'),
                ('SUCCESS', 'Successful'),
                ('FAILED', 'Failed'),
                ('REFUNDED', 'Cancelled'),
                ('PENDING', 'Pending'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.$2, style: AdminDash.titleMd),
                  trailing: selected == item.$1
                      ? const Icon(Icons.check_rounded, color: _kPayBrand800)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelect(item.$1);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class AdminRecordBillSheet extends StatelessWidget {
  const AdminRecordBillSheet({super.key, required this.loader});

  final Future<Paged<Bill>> Function() loader;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: FutureBuilder<Paged<Bill>>(
          future: loader(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Could not load open bills.',
                  style: AdminDash.bodySm.copyWith(color: AdminDash.error),
                ),
              );
            }
            final unpaid = (snap.data?.items ?? [])
                .where((bill) =>
                    bill.status != 'PAID' && bill.status != 'CANCELLED')
                .toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Record payment',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AdminDash.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose an open bill to record an offline collection.',
                  style: TextStyle(fontSize: 12, color: _kPayNeutral),
                ),
                const SizedBox(height: 12),
                if (unpaid.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No open bills to collect against.',
                      style: TextStyle(color: _kPayNeutral),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: unpaid.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final bill = unpaid[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            bill.flatLabel,
                            style: AdminDash.titleMd,
                          ),
                          subtitle: Text(
                            '${bill.billNumber} · ${moneyPaise(billAmountDuePaise(bill))} due',
                            style: AdminDash.bodySm,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pop(context, bill),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
