import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/models/billing_models.dart';
import '../../app_core.dart';
import '../../ui/components.dart';

// Matches the HTML receipt template tokens.
const kReceiptNavy = Color(0xFF0F3A5F);
const kReceiptBlue = Color(0xFF1B5E8F);
const kReceiptInk = Color(0xFF1A2433);
const kReceiptMuted = Color(0xFF6B7787);
const kReceiptBorder = Color(0xFFDDE4EC);
const kReceiptTint = Color(0xFFF3F7FB);
const kReceiptGreen = Color(0xFF1E8E5A);
const kReceiptGreenBg = Color(0xFFE6F5ED);
const kReceiptPage = Color(0xFFE9EEF3);
const kReceiptHeaderFg = Colors.white;
const kReceiptNavyDark = kReceiptNavy;
const kReceiptRule = kReceiptBorder;

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

const _receiptShortMonths = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

DateTime? _receiptParseDate(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Compact flat token for filenames, e.g. `e303`.
String receiptFlatFileToken({
  String? wingCode,
  String? flatNumber,
  String? flatLabel,
}) {
  var wing = (wingCode ?? '').trim().toUpperCase();
  var number = (flatNumber ?? '').trim().toUpperCase();
  if (wing.isNotEmpty) {
    final prefix = '$wing-';
    while (number.startsWith(prefix)) {
      number = number.substring(prefix.length);
    }
    if (number.startsWith(wing) &&
        number.length > wing.length &&
        RegExp(r'^\d').hasMatch(number.substring(wing.length))) {
      number = number.substring(wing.length).replaceFirst(RegExp(r'^-+'), '');
    }
  }
  if (wing.isEmpty && number.isEmpty) {
    final label = (flatLabel ?? '').trim().toUpperCase();
    final match = RegExp(r'^([A-Z]+)\s*[-]?\s*([0-9A-Z]+)$').firstMatch(label);
    if (match != null) {
      wing = match.group(1)!;
      number = match.group(2)!;
    } else if (label.isNotEmpty) {
      return label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    }
  }
  final token = '$wing$number'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return token;
}

/// Paid months for filenames, e.g. `oct` or `oct-dec`.
String receiptMonthsFileToken({
  String? periodStart,
  String? periodEnd,
  String? paidAt,
}) {
  final start = _receiptParseDate(periodStart) ?? _receiptParseDate(paidAt);
  if (start == null) return '';
  final end = _receiptParseDate(periodEnd) ?? start;
  final startLabel = _receiptShortMonths[start.month - 1];
  final endLabel = _receiptShortMonths[end.month - 1];
  if (start.year == end.year && start.month == end.month) return startLabel;
  return '$startLabel-$endLabel';
}

/// Human PDF name like `e303 oct-dec.pdf` instead of opaque receipt numbers.
String receiptPdfFileName({
  String? wingCode,
  String? flatNumber,
  String? flatLabel,
  String? periodStart,
  String? periodEnd,
  String? paidAt,
  String fallback = 'receipt',
}) {
  final flat = receiptFlatFileToken(
    wingCode: wingCode,
    flatNumber: flatNumber,
    flatLabel: flatLabel,
  );
  final months = receiptMonthsFileToken(
    periodStart: periodStart,
    periodEnd: periodEnd,
    paidAt: paidAt,
  );
  // Hyphen keeps the name intact when sharing on Android/iOS.
  final stem = [
    if (flat.isNotEmpty) flat,
    if (months.isNotEmpty) months,
  ].join('-');
  final safe = (stem.isEmpty ? fallback : stem)
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .trim();
  return '$safe.pdf';
}

String receiptPdfFileNameFromBody(ReceiptBody receipt) => receiptPdfFileName(
      wingCode: receipt.wingCodeSnapshot,
      flatNumber: receipt.flatNumberSnapshot,
      flatLabel: receipt.flatLabel,
      periodStart: receipt.billingPeriodStart,
      periodEnd: receipt.billingPeriodEnd,
      paidAt: receipt.paidAt,
      fallback: receipt.receiptNumber,
    );

/// Writes bytes to a real temp file so share sheets keep the human PDF name
/// (XFile.fromData often falls back to a random name on Android).
Future<void> shareReceiptPdfBytes({
  required List<int> bytes,
  required String filename,
  String? text,
}) async {
  final fileName = filename.toLowerCase().endsWith('.pdf')
      ? filename
      : '$filename.pdf';
  final safeName = fileName
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-');
  final file = File('${Directory.systemTemp.path}/$safeName');
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  final label = safeName.replaceFirst(RegExp(r'\.pdf$'), '');
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: safeName,
        ),
      ],
      text: text ?? 'Receipt $label',
      subject: 'Receipt $label',
    ),
  );
}

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
    required this.onShare,
    this.printing = false,
    this.sharing = false,
  });

  final VoidCallback onPrint;
  final VoidCallback onShare;
  final bool printing;
  final bool sharing;

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
                  Icon(Icons.description_outlined, size: 16, color: kReceiptMuted),
                  SizedBox(width: 6),
                  Text(
                    'A4 Paper',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kReceiptInk,
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
                  Icon(Icons.verified_outlined, size: 14, color: kReceiptMuted),
                  SizedBox(width: 4),
                  Text(
                    'Verified record',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kReceiptMuted,
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
              onPressed: sharing ? null : onShare,
              style: FilledButton.styleFrom(
                backgroundColor: kReceiptNavy,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: sharing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_outlined, size: 16),
              label: const Text(
                'Share PDF',
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

  factory ReceiptSheet.fromBody(ReceiptBody receipt) {
    final period = receiptPeriodRange(
      receipt.billingPeriodStart,
      receipt.billingPeriodEnd,
    );
    return ReceiptSheet(
      // Always show the proposed society name on receipts until CHS is formed.
      societyName: kReceiptSocietyName,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kReceiptBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReceiptHeader(
            societyName: societyName,
            receiptNumber: receiptNumber,
            status: status,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MetaCard(
                  paidAt: paidAt,
                  method: method,
                  payer: payer,
                  flatLabel: flatLabel,
                  towards: towards,
                ),
                const SizedBox(height: 22),
                _ChargeTable(lines: lines, totalAmount: totalAmount),
                if ((billNumber ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _ReceiptRefs(billNumber: billNumber),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: _ReceiptFooter(societyName: societyName),
          ),
        ],
      ),
    );
  }
}

const _valueStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w700,
  height: 1.25,
  color: kReceiptInk,
);

const _labelStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w600,
  color: kReceiptMuted,
  height: 1.2,
);

const _refStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w700,
  color: kReceiptNavy,
);

class _ReceiptHeader extends StatelessWidget {
  const _ReceiptHeader({
    required this.societyName,
    required this.receiptNumber,
    required this.status,
  });

  final String societyName;
  final String receiptNumber;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: kReceiptNavy,
        border: Border(
          bottom: BorderSide(color: kReceiptBlue, width: 4),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: LayoutBuilder(builder: (context, constraints) {
        final stacked =
            !constraints.hasBoundedWidth || constraints.maxWidth < 480;
        final title = Text(
          societyName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: kReceiptHeaderFg,
            height: 1.2,
          ),
        );
        final rcpt = Column(
          crossAxisAlignment:
              stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            const Text(
              'RECEIPT',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: Color(0xFFA9C4DB),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              receiptNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kReceiptHeaderFg,
              ),
            ),
            const SizedBox(height: 10),
            _StatusBadge(status: status),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 16),
              rcpt,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            Flexible(child: rcpt),
          ],
        );
      }),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: kReceiptGreenBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: kReceiptGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            status.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kReceiptGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.paidAt,
    required this.method,
    required this.payer,
    required this.flatLabel,
    required this.towards,
  });

  final String paidAt;
  final String method;
  final String payer;
  final String flatLabel;
  final String towards;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kReceiptTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kReceiptBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(builder: (context, constraints) {
        final stacked =
            !constraints.hasBoundedWidth || constraints.maxWidth < 480;
        final dateCell = _MetaCell(label: 'PAYMENT DATE', value: paidAt);
        final methodCell = _MetaCell(label: 'PAYMENT METHOD', value: method);
        final nameCell = _MetaCell(label: 'NAME', value: payer);
        final flatCell = _MetaCell(
          label: 'WING / FLAT NO',
          value: flatLabel,
          valueColor: kReceiptBlue,
        );
        final towardsCell = _MetaCell(
          label: 'TOWARDS',
          value: towards,
          valueStyle: _valueStyle.copyWith(fontSize: 14),
        );
        if (stacked) {
          return Column(
            children: [
              dateCell,
              methodCell,
              nameCell,
              flatCell,
              towardsCell,
            ],
          );
        }
        return Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: dateCell),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: kReceiptBorder,
                  ),
                  Expanded(child: methodCell),
                ],
              ),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: nameCell),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: kReceiptBorder,
                  ),
                  Expanded(child: flatCell),
                ],
              ),
            ),
            towardsCell,
          ],
        );
      }),
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueStyle,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kReceiptBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _labelStyle),
          const SizedBox(height: 5),
          Text(
            value,
            style: (valueStyle ?? _valueStyle).copyWith(
              color: valueColor ?? (valueStyle ?? _valueStyle).color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRefs extends StatelessWidget {
  const _ReceiptRefs({this.billNumber});

  final String? billNumber;

  @override
  Widget build(BuildContext context) {
    final bill = (billNumber ?? '').trim();
    if (bill.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kReceiptBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BILL NUMBER', style: _labelStyle),
          const SizedBox(height: 5),
          Text(bill, style: _refStyle),
        ],
      ),
    );
  }
}

class _ReceiptFooter extends StatelessWidget {
  const _ReceiptFooter({required this.societyName});

  final String societyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kReceiptBorder)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final stacked =
            !constraints.hasBoundedWidth || constraints.maxWidth < 480;
        final note = const Text(
          'This is an authorized receipt for a confirmed payment, generated from verified society records.\nNo signature is required for digitally issued receipts.',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.6,
            color: kReceiptMuted,
          ),
        );
        final authorized = Column(
          crossAxisAlignment:
              stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            const Text(
              'AUTHORIZED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kReceiptGreen,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              societyName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: stacked ? TextAlign.left : TextAlign.right,
              style: const TextStyle(
                fontSize: 8.5,
                color: kReceiptMuted,
              ),
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              note,
              const SizedBox(height: 14),
              authorized,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: note),
            const SizedBox(width: 16),
            authorized,
          ],
        );
      }),
    );
  }
}

class _ChargeTable extends StatelessWidget {
  const _ChargeTable({required this.lines, required this.totalAmount});

  final List<ReceiptChargeLine> lines;
  final String totalAmount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact =
          !constraints.hasBoundedWidth || constraints.maxWidth < 480;
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kReceiptBorder),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: kReceiptNavy,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: compact
                  ? const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'PARTICULARS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _headStyle,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'AMOUNT',
                          textAlign: TextAlign.right,
                          style: _headStyle,
                        ),
                      ],
                    )
                  : const Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text('#', style: _headStyle),
                        ),
                        Expanded(
                          flex: 5,
                          child: Text(
                            'PARTICULARS / CHARGE DESCRIPTION',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _headStyle,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: Text(
                            'PERIOD / TENURE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _headStyle,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'AMOUNT',
                          textAlign: TextAlign.right,
                          style: _headStyle,
                        ),
                      ],
                    ),
            ),
            ...lines.asMap().entries.map((entry) {
              final line = entry.value;
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: compact
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${entry.key + 1}. ${line.particulars}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: kReceiptInk,
                                    height: 1.25,
                                  ),
                                ),
                                if (line.period.trim().isNotEmpty &&
                                    line.period != '-') ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    line.period,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: kReceiptMuted,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            line.amount,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kReceiptInk,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kReceiptInk,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Text(
                              line.particulars,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kReceiptInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: Text(
                              line.period,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kReceiptInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            line.amount,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kReceiptInk,
                            ),
                          ),
                        ],
                      ),
              );
            }),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: const BoxDecoration(
                color: kReceiptTint,
                border: Border(top: BorderSide(color: kReceiptBorder)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TOTAL AMOUNT PAID',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kReceiptNavy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      totalAmount,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kReceiptNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

const _headStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  color: Colors.white,
);
