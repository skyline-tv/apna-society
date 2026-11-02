import 'package:flutter/material.dart';

import '../../api/models/billing_models.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import 'admin_dashboard.dart';

const _kBillBrand950 = Color(0xFF09182D);
const _kBillBrand900 = Color(0xFF0F2746);
const _kBillBrand800 = Color(0xFF153B69);
const _kBillBrand600 = Color(0xFF1B4A89);
const _kBillBrand500 = Color(0xFF2B65AF);
const _kBillBrand100 = Color(0xFFDCE8F8);
const _kBillBrand50 = Color(0xFFF0F5FC);
const _kBillEmerald = Color(0xFF059669);
const _kBillEmeraldSoft = Color(0xFFECFDF5);
const _kBillEmeraldBorder = Color(0xFFA7F3D0);
const _kBillRose = Color(0xFFE11D48);
const _kBillRoseSoft = Color(0xFFFFF1F2);
const _kBillRoseBorder = Color(0xFFFECDD3);
const _kBillAmber = Color(0xFFD97706);
const _kBillAmberSoft = Color(0xFFFFFBEB);
const _kBillAmberBorder = Color(0xFFFDE68A);

String shortBillDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = parsed.toLocal();
  return '${d.day} ${months[d.month - 1]}';
}

class AdminBillsHero extends StatelessWidget {
  const AdminBillsHero({
    super.key,
    required this.payableLabel,
    required this.payable,
    required this.principal,
    required this.interest,
    required this.billCount,
    required this.periodLabel,
    required this.generateLabel,
    required this.onGenerate,
  });

  final String payableLabel;
  final String payable;
  final String principal;
  final String interest;
  final int billCount;
  final String periodLabel;
  final String generateLabel;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBillBrand950, _kBillBrand900, _kBillBrand800],
        ),
        border: Border.all(color: _kBillBrand800.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2609182D),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -40,
            bottom: -40,
            child: Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBillBrand500.withValues(alpha: 0.10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        payableLabel.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AdminDash.labelSm.copyWith(
                          color: const Color(0xB3DCE8F8),
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(Rd.pill),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            'Billing Period: $periodLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AdminDash.labelSm.copyWith(
                              color: const Color(0xFFDCE8F8),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    payable,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Principal $principal · Interest $interest · $billCount bills',
                  style: AdminDash.bodySm.copyWith(
                    color: const Color(0xD9CBD5E1),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: onGenerate,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _kBillBrand950,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        generateLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminBillsCollectionsCard extends StatelessWidget {
  const AdminBillsCollectionsCard({
    super.key,
    required this.percent,
    required this.collected,
    required this.billed,
  });

  final num percent;
  final String collected;
  final String billed;

  @override
  Widget build(BuildContext context) {
    final shown = percent.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminDash.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.donut_large, size: 18, color: _kBillBrand600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Collections',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminDash.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kBillBrand50,
                    borderRadius: BorderRadius.circular(Rd.pill),
                    border: Border.all(color: _kBillBrand100),
                  ),
                  child: Text(
                    '${shown.toStringAsFixed(0)}% Completed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdminDash.labelSm.copyWith(
                      color: _kBillBrand800,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(Rd.pill),
            child: LinearProgressIndicator(
              value: (shown / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: const Color(0xFFF1F5F9),
              color: _kBillBrand500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AdminDash.labelMd.copyWith(
                      color: AdminDash.outline,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      TextSpan(
                        text: collected,
                        style: const TextStyle(
                          color: AdminDash.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' collected'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AdminDash.labelMd.copyWith(
                      color: AdminDash.outline,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      const TextSpan(text: 'Target: '),
                      TextSpan(
                        text: billed,
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: ' billed'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdminBillsKpiGrid extends StatelessWidget {
  const AdminBillsKpiGrid({
    super.key,
    required this.collected,
    required this.collectedCaption,
    required this.overdueCount,
    required this.paidCount,
    required this.pendingCount,
    required this.accruedLabel,
    required this.accrued,
  });

  final String collected;
  final String collectedCaption;
  final int overdueCount;
  final int paidCount;
  final int pendingCount;
  final String accruedLabel;
  final String accrued;

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
              child: _KpiCard(
                label: 'Collected',
                value: collected,
                caption: collectedCaption,
                valueColor: _kBillEmerald,
                captionColor: const Color(0xFF047857),
                captionBg: _kBillEmeraldSoft,
                captionBorder: _kBillEmeraldBorder,
                icon: Icons.check_circle_outline,
                iconBg: _kBillEmeraldSoft,
                iconColor: _kBillEmerald,
                iconBorder: _kBillEmeraldBorder,
              ),
            ),
            SizedBox(
              width: w,
              child: _KpiCard(
                label: 'Overdue bills',
                value: '$overdueCount',
                caption: overdueCount > 0 ? 'Action required' : 'None overdue',
                valueColor: _kBillRose,
                captionColor: const Color(0xFFBE123C),
                captionBg: _kBillRoseSoft,
                captionBorder: _kBillRoseBorder,
                icon: Icons.warning_amber_rounded,
                iconBg: _kBillRoseSoft,
                iconColor: _kBillRose,
                iconBorder: _kBillRoseBorder,
              ),
            ),
            SizedBox(
              width: w,
              child: _KpiCard(
                label: 'Paid bills',
                value: '$paidCount',
                caption: '$pendingCount pending review',
                icon: Icons.receipt_long_outlined,
                iconBg: _kBillBrand50,
                iconColor: _kBillBrand600,
                iconBorder: _kBillBrand100,
              ),
            ),
            SizedBox(
              width: w,
              child: _KpiCard(
                label: accruedLabel,
                value: accrued,
                caption: 'Late penalties',
                icon: Icons.trending_up_rounded,
                iconBg: _kBillAmberSoft,
                iconColor: _kBillAmber,
                iconBorder: _kBillAmberBorder,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.iconBorder,
    this.valueColor = AdminDash.onSurface,
    this.captionColor = AdminDash.outline,
    this.captionBg,
    this.captionBorder,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Color iconBorder;
  final Color valueColor;
  final Color captionColor;
  final Color? captionBg;
  final Color? captionBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminDash.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AdminDash.labelMd.copyWith(
                    color: AdminDash.outline,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: iconBorder),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: valueColor,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: captionBg ?? Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: captionBorder == null
                  ? null
                  : Border.all(color: captionBorder!),
            ),
            child: Text(
              caption,
              style: AdminDash.labelSm.copyWith(
                color: captionColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                fontSize: 10.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminBillsServicesLink extends StatelessWidget {
  const AdminBillsServicesLink({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminDash.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kBillBrand50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBillBrand100),
                ),
                child: const Text(
                  'P',
                  style: TextStyle(
                    color: _kBillBrand800,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Additional services',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminDash.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Recurring charges on individual flats',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AdminDash.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AdminDash.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminBillsDirectoryHeader extends StatelessWidget {
  const AdminBillsDirectoryHeader({
    super.key,
    required this.total,
    required this.onSort,
  });

  final int total;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Bills',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AdminDash.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$total total',
            style: AdminDash.labelMd.copyWith(color: AdminDash.outline),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton.icon(
          onPressed: onSort,
          style: TextButton.styleFrom(
            foregroundColor: _kBillBrand800,
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: const Icon(Icons.filter_list_rounded, size: 16),
          label: const Text(
            'Sort',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class AdminBillsStatusChips extends StatelessWidget {
  const AdminBillsStatusChips({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final String? selected;
  final ValueChanged<String?> onSelect;

  static const _items = <(String?, String)>[
    (null, 'All'),
    ('ISSUED', 'Issued'),
    ('OVERDUE', 'Overdue'),
    ('PAID', 'Paid'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Pill(
              label: _items[i].$2,
              selected: selected == _items[i].$1,
              filled: true,
              onTap: () => onSelect(_items[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminBillsWingChips extends StatelessWidget {
  const AdminBillsWingChips({
    super.key,
    required this.wings,
    required this.selected,
    required this.onSelect,
  });

  final List<BillingWingTotal> wings;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Pill(
            label: 'All wings',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final wing in wings) ...[
            const SizedBox(width: 8),
            _Pill(
              label: 'Wing ${wing.wingCode}',
              selected: selected == wing.wingCode,
              onTap: () => onSelect(wing.wingCode),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final selectedFill = filled ? _kBillBrand800 : _kBillBrand100;
    final selectedFg = filled ? Colors.white : _kBillBrand900;
    return Material(
      color: selected ? selectedFill : Colors.white,
      borderRadius: BorderRadius.circular(Rd.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.pill),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: filled ? 16 : 14,
            vertical: filled ? 6 : 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.pill),
            border: Border.all(
              color: selected
                  ? (filled ? _kBillBrand800 : const Color(0xFFBFD7F3))
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? selectedFg : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminBillCard extends StatelessWidget {
  const AdminBillCard({
    super.key,
    required this.bill,
    required this.onOpen,
    this.onReceipt,
    this.onRecordPayment,
  });

  final Bill bill;
  final VoidCallback onOpen;
  final VoidCallback? onReceipt;
  final VoidCallback? onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final status = bill.status.toUpperCase();
    final paid = status == 'PAID';
    final due = billAmountDuePaise(bill);
    final interest = bill.interestOutstandingPaise ??
        (bill.interestAccruedPaise < bill.interestPaidPaise
            ? 0
            : bill.interestAccruedPaise - bill.interestPaidPaise);
    final (pillBg, pillFg, pillBorder) = switch (status) {
      'PAID' => (_kBillEmeraldSoft, const Color(0xFF047857), _kBillEmeraldBorder),
      'OVERDUE' => (_kBillRoseSoft, const Color(0xFFBE123C), _kBillRoseBorder),
      'CANCELLED' => (
          AdminDash.container,
          AdminDash.outline,
          AdminDash.outlineVariant
        ),
      _ => (_kBillAmberSoft, const Color(0xFFB45309), _kBillAmberBorder),
    };
    final owner = bill.ownerNameSnapshot.trim().isEmpty
        ? 'Unassigned'
        : bill.ownerNameSnapshot.trim();
    final meta = paid
        ? 'Bill #${bill.billNumber}'
        : 'Bill #${bill.billNumber} · Due ${shortBillDate(bill.dueDate)}';

    final showReceipt = paid && onReceipt != null;
    final canRecord = onRecordPayment != null &&
        status != 'PAID' &&
        status != 'CANCELLED';
    final actionLabel = showReceipt
        ? 'Receipt'
        : canRecord
            ? 'Record'
            : 'View';
    final actionIcon = showReceipt
        ? Icons.receipt_outlined
        : canRecord
            ? Icons.payments_outlined
            : Icons.arrow_forward_rounded;
    final action = showReceipt
        ? onReceipt!
        : canRecord
            ? onRecordPayment!
            : onOpen;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminDash.hairline),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kBillBrand50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBillBrand100),
                    ),
                    child: FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          bill.flatLabel,
                          style: const TextStyle(
                            color: _kBillBrand800,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          owner,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AdminDash.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          meta,
                          style: AdminDash.labelSm.copyWith(
                            color: AdminDash.outline,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (bill.numberOfMonths > 1) ...[
                          const SizedBox(height: 2),
                          Text(
                            billMonthsProgressLabel(bill),
                            style: AdminDash.labelSm.copyWith(
                              color: AdminDash.outline,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 92),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(Rd.pill),
                        border: Border.all(color: pillBorder),
                      ),
                      child: Text(
                        _statusLabel(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: pillFg,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          paid ? 'Amount:' : 'Payable:',
                          style: AdminDash.labelMd.copyWith(
                            color: AdminDash.outline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          moneyPaise(paid ? bill.totalAmountPaise : due),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AdminDash.onSurface,
                          ),
                        ),
                        if (!paid && interest > 0)
                          Text(
                            '(incl. ${moneyPaise(interest)} int)',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _kBillRose,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: TextButton(
                      onPressed: action,
                      style: TextButton.styleFrom(
                        foregroundColor: _kBillBrand800,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(actionIcon, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'ISSUED':
        return 'Issued';
      case 'PARTIALLY_PAID':
        return 'Partial';
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
}

Future<void> showAdminBillsFilterSheet(
  BuildContext context, {
  required String? occupancyFilter,
  required bool? ownerAssignedFilter,
  required void Function(String? occupancy, bool? ownerAssigned) onApply,
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
                'More filters',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AdminDash.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Occupancy', style: AdminDash.labelMd),
              for (final item in const [
                (null, 'All occupancies'),
                ('OWNER_OCCUPIED', 'Owner occupied'),
                ('TENANT_OCCUPIED', 'Tenant occupied'),
                ('VACANT', 'Vacant'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.$2, style: AdminDash.titleMd),
                  trailing: occupancyFilter == item.$1
                      ? const Icon(Icons.check_rounded, color: _kBillBrand800)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onApply(item.$1, ownerAssignedFilter);
                  },
                ),
              const Text('Owner assignment', style: AdminDash.labelMd),
              for (final item in const [
                (null, 'All assignments'),
                (true, 'Owner assigned'),
                (false, 'Unassigned'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.$2, style: AdminDash.titleMd),
                  trailing: ownerAssignedFilter == item.$1
                      ? const Icon(Icons.check_rounded, color: _kBillBrand800)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onApply(occupancyFilter, item.$1);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
