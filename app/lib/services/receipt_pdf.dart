import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class _Kv {
  const _Kv(this.label, this.value, {this.total = false});
  final String label;
  final String value;
  final bool total;
}

/// Official society payment receipt (A4, brand blue).
/// Issued in the society's name — no product branding.
class ReceiptPdf {
  ReceiptPdf._();

  static const societyName = 'Monarch Solitaire A to E';
  static const brandBlue = PdfColor.fromInt(0xFF1B4F8A);
  static const muted = PdfColor.fromInt(0xFF6B726E);
  static const ink = PdfColor.fromInt(0xFF1A1A18);
  static const rule = PdfColor.fromInt(0xFFD6E0EA);

  static String money(int value) =>
      'Rs ${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  static String shortDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const m = [
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
      'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
  }

  static String periodLabel(String? periodStart, int? months,
      {String? periodEnd}) {
    final d = DateTime.tryParse(periodStart ?? '');
    if (d == null) return '-';
    const m = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    String name(DateTime x) => '${m[x.month - 1]} ${x.year}';
    final n = (months ?? 1) < 1 ? 1 : (months ?? 1);
    if (n <= 1) return name(DateTime(d.year, d.month));
    final end = DateTime.tryParse(periodEnd ?? '');
    final endMonth = end != null
        ? DateTime(end.year, end.month)
        : DateTime(d.year, d.month + n - 1);
    // ASCII hyphen only - Helvetica in pdf package cannot draw en-dash (U+2013).
    return '${name(DateTime(d.year, d.month))} - ${name(endMonth)}';
  }

  static String methodLabel(Map<String, dynamic> payment) {
    final method = payment['method'] as String? ?? '';
    if (method == 'Cheque') {
      final cs = payment['cheque_status'] as String? ?? 'Pending';
      if (cs == 'Pending') return 'Cheque Recorded';
      return 'Cheque - $cs';
    }
    return method.isEmpty ? '-' : method;
  }

  static String _flatLabel(Map<String, dynamic> source) {
    final flat = '${source['flat_number'] ?? ''}'.trim();
    final building = '${source['building'] ?? ''}'.trim();
    if (flat.isNotEmpty && building.isNotEmpty) return '$flat - $building';
    if (flat.isNotEmpty) return flat;
    if (building.isNotEmpty) return building;
    return '-';
  }

  static String _statusLabel(String? status) {
    if (status == 'reversed') return 'REVERSED';
    return 'SUCCESSFUL';
  }

  static String displayPayer(String? ownerName, String flatLabel) {
    final name = (ownerName ?? '').trim();
    if (name.isEmpty || name == '-' || name.toLowerCase() == 'unassigned') {
      return 'Owner of $flatLabel';
    }
    return name;
  }

  static Future<Uint8List> buildBytes({
    required Map<String, dynamic> payment,
    required Map<String, dynamic> bill,
  }) async {
    final receipt = payment['receipt_number'] as String? ?? '-';
    final billNo = (bill['bill_number'] as String?)?.isNotEmpty == true
        ? bill['bill_number'] as String
        : 'AS-BILL-${bill['id']}';
    final amount = payment['amount'] as int? ?? bill['amount'] as int? ?? 0;
    final months = bill['months_covered'] as int? ?? 1;
    final method = methodLabel(payment);
    final isCheque = (payment['method'] as String?) == 'Cheque';
    final remarks = payment['remarks'] as String?;
    final collector = payment['collected_by_name'] as String?;
    final status = payment['status'] as String? ?? '';
    final period = periodLabel(bill['period_start'] as String?, months,
        periodEnd: bill['period_end'] as String?);
    final principal = (payment['principal_amount'] as int?) ?? amount;
    final interest = (payment['interest_amount'] as int?) ?? 0;
    final maintenance = bill['maintenance_amount'] as int?;
    final other = bill['other_charges_total'] as int?;

    final breakdown = <_Kv>[];
    final billed = (maintenance ?? 0) + ((other ?? 0) > 0 ? other! : 0);
    final paidInFull = billed == 0 || principal >= billed;
    if (paidInFull && maintenance != null) {
      breakdown.add(_Kv('Base maintenance', money(maintenance)));
      if (other != null && other > 0) {
        breakdown.add(_Kv('Additional services', money(other)));
      }
    } else {
      breakdown.add(_Kv('Applied to principal', money(principal)));
    }
    if (interest > 0) {
      breakdown.add(_Kv('Interest', money(interest)));
    }
    breakdown.add(_Kv('Total amount paid', money(amount), total: true));

    final refs = <_Kv>[
      _Kv('Bill number', billNo),
    ];
    if (collector != null && collector.isNotEmpty) {
      refs.add(_Kv('Collected by', collector));
    }
    if (isCheque) {
      refs.add(_Kv('Cheque number', '${payment['cheque_number'] ?? '-'}'));
      refs.add(_Kv('Cheque date', shortDate(payment['cheque_date'] as String?)));
      refs.add(_Kv('Bank name', '${payment['bank_name'] ?? '-'}'));
      refs.add(_Kv('Cheque status', '${payment['cheque_status'] ?? 'Pending'}'));
    }
    if (remarks != null && remarks.isNotEmpty) {
      refs.add(_Kv('Remarks', remarks));
    }

    return _render(
      receiptNumber: receipt,
      status: _statusLabel(status),
      paidAt: shortDate(payment['paid_at'] as String?),
      method: method,
      payer: displayPayer(bill['owner_name'] as String?, _flatLabel(bill)),
      flatLabel: _flatLabel(bill),
      towards: period == '-'
          ? 'Monthly maintenance'
          : 'Monthly maintenance - $period',
      breakdown: breakdown,
      refs: refs,
    );
  }

  static Future<Uint8List> buildBatchBytes({
    required Map<String, dynamic> batch,
    required List<Map<String, dynamic>> allocations,
  }) async {
    final receipt = batch['receipt_number'] as String? ?? '-';
    final total = batch['total_amount'] as int? ?? 0;
    final principal = batch['total_principal'] as int? ?? 0;
    final interest = batch['total_interest'] as int? ?? 0;
    final billsSettled = batch['bills_settled'] as int? ?? allocations.length;
    final method = methodLabel(batch);
    final isCheque = (batch['method'] as String?) == 'Cheque';
    final remarks = batch['remarks'] as String?;
    final collector = batch['collected_by_name'] as String?;

    final breakdown = <_Kv>[
      _Kv('Applied to principal', money(principal)),
      if (interest > 0) _Kv('Interest', money(interest)),
      _Kv('Total amount paid', money(total), total: true),
    ];
    final refs = <_Kv>[
      _Kv('Bills settled', '$billsSettled'),
    ];
    if (collector != null && collector.isNotEmpty) {
      refs.add(_Kv('Collected by', collector));
    }
    if (isCheque) {
      refs.add(_Kv('Cheque number', '${batch['cheque_number'] ?? '-'}'));
      refs.add(_Kv('Cheque date', shortDate(batch['cheque_date'] as String?)));
      refs.add(_Kv('Bank name', '${batch['bank_name'] ?? '-'}'));
      refs.add(_Kv('Cheque status', '${batch['cheque_status'] ?? 'Pending'}'));
    }
    if (remarks != null && remarks.isNotEmpty) {
      refs.add(_Kv('Remarks', remarks));
    }

    return _render(
      receiptNumber: receipt,
      status: 'SUCCESSFUL',
      paidAt: shortDate(batch['paid_at'] as String?),
      method: method,
      payer: displayPayer(batch['owner_name'] as String?, _flatLabel(batch)),
      flatLabel: _flatLabel(batch),
      towards: 'Settlement of outstanding maintenance',
      breakdown: breakdown,
      refs: refs,
      extra: [
        pw.SizedBox(height: 14),
        pw.Text('Bill-wise allocation (oldest first)',
            style: pw.TextStyle(
                font: pw.Font.helveticaBold(), fontSize: 10, color: ink)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: const pw.BorderSide(color: rule, width: 0.4),
            bottom: const pw.BorderSide(color: rule, width: 0.4),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(2.2),
            2: const pw.FlexColumnWidth(1.1),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(1.1),
          },
          children: [
            pw.TableRow(children: [
              _cell('Bill', bold: true),
              _cell('Period', bold: true),
              _cell('Principal', bold: true, align: pw.TextAlign.right),
              _cell('Interest', bold: true, align: pw.TextAlign.right),
              _cell('Total', bold: true, align: pw.TextAlign.right),
            ]),
            ...allocations.map((a) {
              final billNo = (a['bill_number'] as String?)?.isNotEmpty == true
                  ? a['bill_number'] as String
                  : 'AS-BILL-${a['bill_ids']}';
              final p = a['principal_amount'] as int? ?? 0;
              final i = a['interest_amount'] as int? ?? 0;
              final t = a['amount'] as int? ?? (p + i);
              return pw.TableRow(children: [
                _cell(billNo),
                _cell(periodLabel(
                  a['period_start'] as String?,
                  a['months_covered'] as int?,
                  periodEnd: a['period_end'] as String?,
                )),
                _cell(money(p), align: pw.TextAlign.right),
                _cell(money(i), align: pw.TextAlign.right),
                _cell(money(t), align: pw.TextAlign.right),
              ]);
            }),
          ],
        ),
      ],
    );
  }

  static Future<Uint8List> _render({
    required String receiptNumber,
    required String status,
    required String paidAt,
    required String method,
    required String payer,
    required String flatLabel,
    required String towards,
    required List<_Kv> breakdown,
    required List<_Kv> refs,
    List<pw.Widget> extra = const [],
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: rule, width: 0.8),
            ),
            padding: const pw.EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Text(societyName,
                          style: pw.TextStyle(
                              font: pw.Font.timesBold(),
                              fontSize: 16,
                              color: brandBlue)),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('RECEIPT',
                            style: pw.TextStyle(
                                font: pw.Font.helveticaBold(),
                                fontSize: 8,
                                letterSpacing: 1.6,
                                color: brandBlue)),
                        pw.SizedBox(height: 2),
                        pw.Text(receiptNumber,
                            style: pw.TextStyle(
                                font: pw.Font.timesBold(), fontSize: 13)),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: brandBlue, width: 0.8),
                          ),
                          child: pw.Text(status,
                              style: pw.TextStyle(
                                  font: pw.Font.helveticaBold(),
                                  fontSize: 8,
                                  letterSpacing: 1.2,
                                  color: brandBlue)),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Container(height: 1, color: brandBlue),
                pw.SizedBox(height: 12),
                pw.Row(children: [
                  pw.Expanded(child: _meta('Payment date', paidAt)),
                  pw.Expanded(child: _meta('Payment method', method)),
                ]),
                pw.SizedBox(height: 16),
                pw.Text('RECEIVED WITH THANKS FROM',
                    style: pw.TextStyle(
                        font: pw.Font.helvetica(),
                        fontSize: 8,
                        letterSpacing: 1.2,
                        color: muted)),
                pw.SizedBox(height: 4),
                pw.Text(payer,
                    style: pw.TextStyle(
                        font: pw.Font.timesBold(), fontSize: 20, color: ink)),
                pw.SizedBox(height: 4),
                pw.Text('Wing / Flat $flatLabel',
                    style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: 11,
                        color: brandBlue)),
                pw.SizedBox(height: 14),
                _meta('Towards', towards),
                pw.SizedBox(height: 10),
                ...breakdown.map(_breakdownRow),
                pw.SizedBox(height: 12),
                ..._refGrid(refs),
                ...extra,
                pw.SizedBox(height: 28),
                pw.Text(
                  'This is an authorized receipt for a confirmed payment, generated from verified society records.',
                  style: pw.TextStyle(
                      font: pw.Font.helvetica(), fontSize: 9, color: muted),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'No signature is required for digitally issued receipts.',
                      style: pw.TextStyle(
                          font: pw.Font.helvetica(), fontSize: 9, color: muted),
                    ),
                    pw.Container(
                      width: 170,
                      padding: const pw.EdgeInsets.only(top: 6),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                            top: pw.BorderSide(color: rule, width: 0.6)),
                      ),
                      child: pw.Text(
                        'AUTHORIZED - $societyName',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            font: pw.Font.helvetica(),
                            fontSize: 8,
                            letterSpacing: 0.6,
                            color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _meta(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label.toUpperCase(),
              style: pw.TextStyle(
                  font: pw.Font.helvetica(),
                  fontSize: 8,
                  letterSpacing: 1.1,
                  color: muted)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              style: pw.TextStyle(
                  font: pw.Font.helveticaBold(), fontSize: 11, color: ink)),
        ],
      );

  static pw.Widget _breakdownRow(_Kv row) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: rule, width: 0.4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(row.label,
              style: pw.TextStyle(
                  font: row.total ? pw.Font.helveticaBold() : pw.Font.helvetica(),
                  fontSize: row.total ? 12 : 11,
                  color: row.total ? brandBlue : ink)),
          pw.Text(row.value,
              style: pw.TextStyle(
                  font: row.total ? pw.Font.timesBold() : pw.Font.helveticaBold(),
                  fontSize: row.total ? 16 : 11,
                  color: row.total ? brandBlue : ink)),
        ],
      ),
    );
  }

  static List<pw.Widget> _refGrid(List<_Kv> refs) {
    final widgets = <pw.Widget>[];
    for (var i = 0; i < refs.length; i += 2) {
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _meta(refs[i].label, refs[i].value)),
            if (i + 1 < refs.length)
              pw.Expanded(child: _meta(refs[i + 1].label, refs[i + 1].value))
            else
              pw.Expanded(child: pw.SizedBox()),
          ],
        ),
      ));
    }
    return widgets;
  }

  static pw.Widget _cell(String text,
          {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
              font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
              fontSize: 8,
              color: ink),
        ),
      );

  static Future<void> preview(
      {required Map<String, dynamic> payment,
      required Map<String, dynamic> bill}) async {
    final bytes = await buildBytes(payment: payment, bill: bill);
    await Printing.layoutPdf(
        name: fileName(payment['receipt_number'] as String? ?? 'receipt'),
        onLayout: (_) async => bytes);
  }

  static Future<void> share(
      {required Map<String, dynamic> payment,
      required Map<String, dynamic> bill}) async {
    final bytes = await buildBytes(payment: payment, bill: bill);
    await Printing.sharePdf(
        bytes: bytes,
        filename: fileName(payment['receipt_number'] as String? ?? 'receipt'));
  }

  static Future<void> shareBatch({
    required Map<String, dynamic> batch,
    required List<Map<String, dynamic>> allocations,
  }) async {
    final bytes = await buildBatchBytes(batch: batch, allocations: allocations);
    await Printing.sharePdf(
        bytes: bytes,
        filename: fileName(batch['receipt_number'] as String? ?? 'batch'));
  }

  static Future<void> previewBatch({
    required Map<String, dynamic> batch,
    required List<Map<String, dynamic>> allocations,
  }) async {
    final bytes = await buildBatchBytes(batch: batch, allocations: allocations);
    await Printing.layoutPdf(
        name: fileName(batch['receipt_number'] as String? ?? 'batch'),
        onLayout: (_) async => bytes);
  }

  static String fileName(String receipt) {
    final safe = receipt.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'Monarch_Solitaire_A_to_E_Receipt_$safe.pdf';
  }
}
