import 'package:flutter/material.dart';

import '../../api/models/billing_models.dart';
import '../../app_core.dart';
import '../../ui/components.dart';

const kReceiptNavy = Color(0xFF0B3C68);
const kReceiptNavyDark = Color(0xFF00254C);
const kReceiptPage = Color(0xFFF7F9FA);
const kReceiptMuted = Color(0xFF94A3B8);
const kReceiptInk = Color(0xFF0F172A);
const kReceiptBorder = Color(0xFFE2E8F0);
const kReceiptRule = Color(0xFF94A3B8);

class ReceiptChargeLine {
  const ReceiptChargeLine({
    required this.particulars,
    required this.amount,
    this.period = '-',
  });

  final String particulars;
  final String period;
  final String amount;
}

String receiptPayerName(String? ownerName) {
  final name = (ownerName ?? '').trim();
  if (name.isEmpty || name == '-' || name.toLowerCase() == 'unassigned') {
    return '-';
  }
  return name;
}

String receiptWingFlatLine({String? wingCode, String? flatNumber, String? fallback}) {
  final labeled = (fallback ?? '').trim();
  final wing = (wingCode ?? '').trim().toUpperCase();
  var number = (flatNumber ?? '').trim().toUpperCase();
  if (wing.isNotEmpty && number.startsWith('$wing-')) {
    number = number.substring(wing.length + 1);
  }
  if (wing.isNotEmpty && number.isNotEmpty) return 'Wing $wing - Flat $number';
  if (labeled.isNotEmpty) return labeled;
  if (number.isNotEmpty) return 'Flat $number';
  if (wing.isNotEmpty) return 'Wing $wing';
  return '-';
}

String receiptPeriodRange(String? start, String? end) {
  if ((start ?? '').isEmpty) return '-';
  final left = fmtIsoDate(start);
  if ((end ?? '').isEmpty) return left;
  return '$left - ${fmtIsoDate(end)}';
}

String receiptTowards({
  required String? periodStart,
  required String? periodEnd,
  String? description,
}) {
  if ((description ?? '').trim().isNotEmpty) return description!.trim();
  final period = receiptPeriodRange(periodStart, periodEnd);
  if (period == '-') return 'Monthly maintenance';
  return 'Monthly maintenance - $period';
}

String receiptMoneyPaise(int paise) => moneyPaise(paise).replaceFirst('₹', 'Rs ');

String receiptMethodLabel(String method) {
  switch (method.toUpperCase()) {
    case 'ONLINE':
    case 'RAZORPAY':
      return 'Online';
    case 'OFFLINE':
      return 'Cash / offline';
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

class ReceiptActionBar extends StatelessWidget {
  const ReceiptActionBar({
    super.key,
    required this.onPrint,
    required this.onDownload,
    this.printing = false,
    this.downloading = false,
  });

  final VoidCallback onPrint;
  final VoidCallback onDownload;
  final bool printing;
  final bool downloading;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: kReceiptBorder),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 16, color: Color(0xFF64748B)),
                  SizedBox(width: 6),
                  Text(
                    'A4 Paper',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined, size: 14, color: Color(0xFF64748B)),
                  SizedBox(width: 4),
                  Text(
                    'Verified record',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: printing ? null : onPrint,
              style: OutlinedButton.styleFrom(
                foregroundColor: kReceiptNavy,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              icon: printing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined, size: 16),
              label: const Text(
                'Print (A4)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.icon(
              onPressed: downloading ? null : onDownload,
              style: FilledButton.styleFrom(
                backgroundColor: kReceiptNavy,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: downloading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: const Text(
                'Download PDF',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ReceiptSheet extends StatelessWidget {
  const ReceiptSheet({
    super.key,
    required this.societyName,
    required this.receiptNumber,
    required this.status,
    required this.paidAt,
    required this.method,
    required this.payer,
    required this.flatLabel,
    required this.towards,
    required this.lines,
    required this.totalAmount,
    this.billNumber,
    this.transactionReference,
  });

  final String societyName;
  final String receiptNumber;
  final String status;
  final String paidAt;
  final String method;
  final String payer;
  final String flatLabel;
  final String towards;
  final List<ReceiptChargeLine> lines;
  final String totalAmount;
  final String? billNumber;
  final String? transactionReference;

  factory ReceiptSheet.fromBody(ReceiptBody receipt) {
    final period = receiptPeriodRange(
      receipt.billingPeriodStart,
      receipt.billingPeriodEnd,
    );
    return ReceiptSheet(
      societyName: (receipt.societyNameSnapshot ?? '').trim().isEmpty
          ? kSocietyName
          : receipt.societyNameSnapshot!,
      receiptNumber: receipt.receiptNumber,
      status: 'SUCCESSFUL',
      paidAt: fmtIsoDate(receipt.paidAt),
      method: receiptMethodLabel(receipt.paymentMethod),
      payer: receiptPayerName(receipt.ownerNameSnapshot),
      flatLabel: receiptWingFlatLine(
        wingCode: receipt.wingCodeSnapshot,
        flatNumber: receipt.flatNumberSnapshot,
        fallback: receipt.flatLabel,
      ),
      towards: receiptTowards(
        periodStart: receipt.billingPeriodStart,
        periodEnd: receipt.billingPeriodEnd,
      ),
      lines: [
        ReceiptChargeLine(
          particulars: 'Base Maintenance Charges',
          period: period,
          amount: receiptMoneyPaise(receipt.amountPaise),
        ),
      ],
      totalAmount: receiptMoneyPaise(receipt.amountPaise),
      billNumber: receipt.billNumber,
      transactionReference: receipt.transactionReference,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3394A3B8),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          border: Border.all(color: kReceiptBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    societyName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kReceiptNavy,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                    const Text(
                      'RECEIPT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: kReceiptNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      receiptNumber,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kReceiptInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: kReceiptNavy),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                          color: kReceiptNavy,
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: Color(0xCC94A3B8)),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              final date = _MetaBlock(
                label: 'PAYMENT DATE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paidAt, style: _valueStyle),
                    const SizedBox(height: 4),
                    Text(payer, style: _valueStyle),
                    const SizedBox(height: 4),
                    Text(
                      flatLabel,
                      style: _valueStyle.copyWith(color: kReceiptNavy),
                    ),
                  ],
                ),
              );
              final methodBlock = _MetaBlock(
                label: 'PAYMENT METHOD',
                child: Text(method, style: _valueStyle),
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    date,
                    const SizedBox(height: 16),
                    methodBlock,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: date),
                  const SizedBox(width: 24),
                  Expanded(child: methodBlock),
                ],
              );
            }),
            const SizedBox(height: 18),
            _MetaBlock(
              label: 'TOWARDS',
              child: Text(towards, style: _valueStyle),
            ),
            const SizedBox(height: 16),
            _ChargeTable(lines: lines, totalAmount: totalAmount),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              final bill = billNumber == null || billNumber!.isEmpty
                  ? null
                  : _MetaBlock(
                      label: 'BILL NUMBER',
                      child: Text(billNumber!, style: _refStyle),
                    );
              final txn =
                  transactionReference == null || transactionReference!.isEmpty
                      ? null
                      : _MetaBlock(
                          label: 'TRANSACTION REFERENCE',
                          child: Text(transactionReference!, style: _refStyle),
                        );
              if (bill == null && txn == null) return const SizedBox.shrink();
              if (stacked || txn == null || bill == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bill != null) bill,
                    if (bill != null && txn != null) const SizedBox(height: 12),
                    if (txn != null) txn,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: bill),
                  const SizedBox(width: 24),
                  Expanded(child: txn),
                ],
              );
            }),
            const SizedBox(height: 48),
            LayoutBuilder(builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              final note = const Text(
                'This is an authorized receipt for a confirmed payment, generated from verified society records.\nNo signature is required for digitally issued receipts.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: Color(0xFF64748B),
                ),
              );
              final authorized = Column(
                crossAxisAlignment: stacked
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Container(
                    width: stacked ? double.infinity : 180,
                    height: 1,
                    color: const Color(0xFFCBD5E1),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'AUTHORIZED',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    societyName.toUpperCase(),
                    textAlign: stacked ? TextAlign.left : TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    note,
                    const SizedBox(height: 20),
                    authorized,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: note),
                  const SizedBox(width: 16),
                  authorized,
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

const _valueStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w700,
  color: kReceiptInk,
);

const _refStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w700,
  color: kReceiptInk,
);

class _MetaBlock extends StatelessWidget {
  const _MetaBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: kReceiptMuted,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _ChargeTable extends StatelessWidget {
  const _ChargeTable({required this.lines, required this.totalAmount});

  final List<ReceiptChargeLine> lines;
  final String totalAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: kReceiptBorder),
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: const Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('#', textAlign: TextAlign.center, style: _headStyle),
                ),
                SizedBox(width: 8),
                Expanded(flex: 5, child: Text('Particulars', style: _headStyle)),
                SizedBox(width: 8),
                Expanded(flex: 4, child: Text('Period / Tenure', style: _headStyle)),
                SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: Text('Amount', textAlign: TextAlign.right, style: _headStyle),
                ),
              ],
            ),
          ),
          ...lines.asMap().entries.map((entry) {
            final line = entry.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${entry.key + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: Text(
                      line.particulars,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: kReceiptInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      line.period,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 84,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        line.amount,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kReceiptInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: kReceiptBorder)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Amount Paid',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: kReceiptNavy,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      totalAmount,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kReceiptNavy,
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

const _headStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.6,
  color: Color(0xFF334155),
);
