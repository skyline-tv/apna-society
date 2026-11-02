import 'package:flutter/material.dart';

import '../../api/models/billing_models.dart';
import '../../app_core.dart';

const kBillDetailGround = Color(0xFFF8F9FC);
const kBillDetailNavy = Color(0xFF153B69);
const kBillDetailNavyDark = Color(0xFF0E2644);
const kBillDetailDeep = Color(0xFF0A1A2E);
const kBillDetailBorder = Color(0xFFE6EBF2);
const kBillDetailMuted = Color(0xFF64748B);
const kBillDetailInk = Color(0xFF0F172A);

enum AdminBillAmountTone { neutral, credit, total }

class AdminBillAmountLine {
  const AdminBillAmountLine({
    required this.label,
    required this.value,
    this.tone = AdminBillAmountTone.neutral,
  });

  final String label;
  final String value;
  final AdminBillAmountTone tone;
}

class AdminBillMetaLine {
  const AdminBillMetaLine({
    required this.label,
    required this.value,
    this.chip = false,
    this.italic = false,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String value;
  final bool chip;
  final bool italic;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class AdminBillDetailIdentity extends StatelessWidget {
  const AdminBillDetailIdentity({
    super.key,
    required this.period,
    required this.flatLabel,
    required this.billNumber,
    required this.status,
  });

  final String period;
  final String flatLabel;
  final String billNumber;
  final String status;

  @override
  Widget build(BuildContext context) {
    final paid = status.toUpperCase() == 'PAID';
    final overdue = status.toUpperCase() == 'OVERDUE';
    final cancelled = status.toUpperCase() == 'CANCELLED';
    final Color bg;
    final Color fg;
    final Color border;
    final Color dot;
    if (paid) {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF047857);
      border = const Color(0xFFA7F3D0);
      dot = const Color(0xFF10B981);
    } else if (overdue) {
      bg = const Color(0xFFFFF1F2);
      fg = const Color(0xFFE11D48);
      border = const Color(0xFFFECDD3);
      dot = const Color(0xFFE11D48);
    } else if (cancelled) {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF475569);
      border = kBillDetailBorder;
      dot = const Color(0xFF94A3B8);
    } else {
      bg = const Color(0xFFEFF6FF);
      fg = kBillDetailNavy;
      border = const Color(0xFFBFDBFE);
      dot = kBillDetailNavy;
    }
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: kBillDetailNavy.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: kBillDetailNavy.withValues(alpha: 0.15)),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: kBillDetailNavy,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  period,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kBillDetailInk,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$flatLabel  ·  $billNumber',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ],
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

class AdminBillOutstandingHero extends StatelessWidget {
  const AdminBillOutstandingHero({
    super.key,
    required this.amount,
    required this.paid,
    required this.outstanding,
    this.caption,
    this.settled = false,
  });

  final String amount;
  final String paid;
  final String outstanding;
  final String? caption;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBillDetailNavy, kBillDetailNavyDark, kBillDetailDeep],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33153B69),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OUTSTANDING',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: settled
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Paid:  ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      TextSpan(
                        text: paid,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Outstanding:  ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      TextSpan(
                        text: outstanding,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
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

class AdminBillSectionCard extends StatelessWidget {
  const AdminBillSectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class AdminBillMetaCard extends StatelessWidget {
  const AdminBillMetaCard({super.key, required this.lines});

  final List<AdminBillMetaLine> lines;

  @override
  Widget build(BuildContext context) {
    return AdminBillSectionCard(
      title: 'BILL',
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      lines[i].label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kBillDetailMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: lines[i].chip
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    lines[i].value,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF047857),
                                    ),
                                  ),
                                )
                              : Text(
                                  lines[i].value,
                                  textAlign: TextAlign.right,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontStyle: lines[i].italic
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                    color: lines[i].italic
                                        ? kBillDetailMuted
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                        ),
                        if (lines[i].actionLabel != null) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: lines[i].onAction,
                            style: TextButton.styleFrom(
                              foregroundColor: kBillDetailNavy,
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                            ),
                            child: Text(
                              lines[i].actionLabel!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminBillAmountCard extends StatelessWidget {
  const AdminBillAmountCard({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<AdminBillAmountLine> lines;

  @override
  Widget build(BuildContext context) {
    return AdminBillSectionCard(
      title: title,
      child: Column(
        children: [
          for (final line in lines)
            Padding(
              padding: EdgeInsets.only(
                top: line.tone == AdminBillAmountTone.total ? 10 : 4,
                bottom: 4,
              ),
              child: DecoratedBox(
                decoration: line.tone == AdminBillAmountTone.total
                    ? const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      )
                    : const BoxDecoration(),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: line.tone == AdminBillAmountTone.total ? 10 : 0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.label,
                          style: TextStyle(
                            fontSize: line.tone == AdminBillAmountTone.total
                                ? 14
                                : 13,
                            fontWeight: line.tone == AdminBillAmountTone.total
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: line.tone == AdminBillAmountTone.credit
                                ? const Color(0xFF047857)
                                : line.tone == AdminBillAmountTone.total
                                    ? kBillDetailInk
                                    : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          line.value,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: line.tone == AdminBillAmountTone.total
                                ? 16
                                : 13,
                            fontWeight: line.tone == AdminBillAmountTone.total
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: line.tone == AdminBillAmountTone.credit
                                ? const Color(0xFF047857)
                                : line.tone == AdminBillAmountTone.total
                                    ? kBillDetailNavy
                                    : const Color(0xFF1E293B),
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
  }
}

class AdminBillCollectSection extends StatelessWidget {
  const AdminBillCollectSection({
    super.key,
    required this.settled,
    required this.busy,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tertiaryLabel,
    this.onTertiary,
    this.receiptLabel,
    this.onReceipt,
    this.onDownload,
  });

  final bool settled;
  final bool busy;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? tertiaryLabel;
  final VoidCallback? onTertiary;
  final String? receiptLabel;
  final VoidCallback? onReceipt;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Collect & manage',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        if (settled)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFCBD5E1),
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: kBillDetailNavy.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: kBillDetailNavy,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This bill is settled.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'No further collection actions are required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: kBillDetailMuted),
                ),
                if (onReceipt != null || onDownload != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (onReceipt != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : onReceipt,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF334155),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: kBillDetailBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 14),
                            label: Text(
                              receiptLabel ?? 'Receipt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (onReceipt != null && onDownload != null)
                        const SizedBox(width: 10),
                      if (onDownload != null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy ? null : onDownload,
                            style: FilledButton.styleFrom(
                              backgroundColor: kBillDetailNavy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.download_outlined, size: 14),
                            label: const Text(
                              'Download PDF',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          )
        else ...[
          if (primaryLabel != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: kBillDetailNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(
                  primaryLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (secondaryLabel != null || tertiaryLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (secondaryLabel != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onSecondary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: const BorderSide(color: kBillDetailBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        secondaryLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (secondaryLabel != null && tertiaryLabel != null)
                  const SizedBox(width: 10),
                if (tertiaryLabel != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onTertiary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB42318),
                        side: const BorderSide(color: Color(0xFFFECDD3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        tertiaryLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class AdminBillCircleIconButton extends StatelessWidget {
  const AdminBillCircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF475569),
        side: const BorderSide(color: kBillDetailBorder),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBillDetailBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D153B69),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

List<AdminBillAmountLine> adminBillLineItemRows(Bill bill) {
  if (bill.lineItems.isNotEmpty) {
    return [
      for (final item in bill.lineItems)
        AdminBillAmountLine(
          label:
              item.quantity > 1 ? '${item.name} × ${item.quantity}' : item.name,
          value: moneyPaise(item.amountPaise),
        ),
    ];
  }
  return [
    AdminBillAmountLine(
      label: bill.numberOfMonths > 1
          ? 'Monthly maintenance × ${bill.numberOfMonths}'
          : 'Monthly maintenance',
      value: moneyPaise(bill.baseAmountPaise),
    ),
    if (bill.additionalServicesTotalPaise > 0)
      AdminBillAmountLine(
        label: 'Additional services',
        value: moneyPaise(bill.additionalServicesTotalPaise),
      ),
  ];
}
