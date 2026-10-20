import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Payment receipt PDF for admin cash / cheque collections.
class ReceiptPdf {
  ReceiptPdf._();

  static const societyName = 'Monarch Solitaire A to E';
  static const societyAddress = 'Monarch Solitaire A to E Residential Society';
  static const logoAsset = 'assets/icons/app_icon.png';

  static Future<pw.MemoryImage?> _logo() async {
    try {
      final data = await rootBundle.load(logoAsset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

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
      return 'Cheque · $cs';
    }
    return method.isEmpty ? '-' : method;
  }

  static Future<Uint8List> buildBytes({
    required Map<String, dynamic> payment,
    required Map<String, dynamic> bill,
  }) async {
    final logo = await _logo();
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

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(children: [
              if (logo != null)
                pw.Container(width: 48, height: 48, child: pw.Image(logo)),
              if (logo != null) pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(societyName,
                          style: pw.TextStyle(
                              fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.Text(societyAddress,
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.grey700)),
                    ]),
              ),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('PAYMENT RECEIPT',
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF1E4DB7))),
                    pw.Text(receipt, style: const pw.TextStyle(fontSize: 9)),
                  ]),
            ]),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF5F7FB),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Amount received',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700)),
                    pw.SizedBox(height: 4),
                    pw.Text(money(amount),
                        style: pw.TextStyle(
                            fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(status == 'reversed' ? 'REVERSED' : 'PAID',
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: status == 'reversed'
                                ? PdfColors.red700
                                : PdfColors.green800)),
                  ]),
            ),
            pw.SizedBox(height: 16),
            _line('Receipt number', receipt),
            _line('Bill number', billNo),
            _line('Flat',
                '${bill['flat_number'] ?? '-'} · ${bill['building'] ?? ''}'),
            _line('Owner', '${bill['owner_name'] ?? '-'}'),
            _line(
                'Maintenance Period',
                periodLabel(bill['period_start'] as String?, months,
                    periodEnd: bill['period_end'] as String?)),
            _line('Prepaid months', '$months'),
            if ((bill['maintenance_amount'] as int?) != null)
              _line('Maintenance subtotal',
                  money(bill['maintenance_amount'] as int)),
            if ((bill['other_charges_total'] as int?) != null &&
                (bill['other_charges_total'] as int) > 0)
              _line('Other Charges total',
                  money(bill['other_charges_total'] as int)),
            _line('Principal collected',
                money((payment['principal_amount'] as int?) ?? amount)),
            if (((payment['interest_amount'] as int?) ?? 0) > 0)
              _line('Late interest collected',
                  money(payment['interest_amount'] as int)),
            _line('Payment method', method),
            _line('Payment date', shortDate(payment['paid_at'] as String?)),
            if (isCheque) ...[
              _line('Cheque number', '${payment['cheque_number'] ?? '-'}'),
              _line(
                  'Cheque date', shortDate(payment['cheque_date'] as String?)),
              _line('Bank name', '${payment['bank_name'] ?? '-'}'),
              _line(
                  'Cheque status', '${payment['cheque_status'] ?? 'Pending'}'),
            ],
            if (collector != null && collector.isNotEmpty)
              _line('Collected by', collector),
            if (remarks != null && remarks.isNotEmpty)
              _line('Remarks', remarks),
            pw.Spacer(),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 6),
            pw.Text(
              '$societyName · Official collection receipt · Generated locally',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _line(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 7),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 130,
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700))),
          pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold))),
        ]),
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

  /// Batch receipt with bill-wise allocation breakdown (oldest → newest).
  static Future<Uint8List> buildBatchBytes({
    required Map<String, dynamic> batch,
    required List<Map<String, dynamic>> allocations,
  }) async {
    final logo = await _logo();
    final receipt = batch['receipt_number'] as String? ?? '-';
    final total = batch['total_amount'] as int? ?? 0;
    final principal = batch['total_principal'] as int? ?? 0;
    final interest = batch['total_interest'] as int? ?? 0;
    final billsSettled = batch['bills_settled'] as int? ?? allocations.length;
    final method = methodLabel(batch);
    final isCheque = (batch['method'] as String?) == 'Cheque';
    final remarks = batch['remarks'] as String?;
    final collector = batch['collected_by_name'] as String?;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Row(children: [
            if (logo != null)
              pw.Container(width: 48, height: 48, child: pw.Image(logo)),
            if (logo != null) pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(societyName,
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text(societyAddress,
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey700)),
                  ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('SETTLEMENT RECEIPT',
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF1E4DB7))),
              pw.Text(receipt, style: const pw.TextStyle(fontSize: 9)),
            ]),
          ]),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF5F7FB),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Total amount received',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text(money(total),
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Principal ${money(principal)} · Interest ${money(interest)} · $billsSettled bill(s)',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700),
                  ),
                ]),
          ),
          pw.SizedBox(height: 16),
          _line('Receipt number', receipt),
          _line('Flat',
              '${batch['flat_number'] ?? '-'} · ${batch['building'] ?? ''}'),
          _line('Owner', '${batch['owner_name'] ?? '-'}'),
          _line('Payment method', method),
          _line('Payment date', shortDate(batch['paid_at'] as String?)),
          if (isCheque) ...[
            _line('Cheque number', '${batch['cheque_number'] ?? '-'}'),
            _line('Cheque date', shortDate(batch['cheque_date'] as String?)),
            _line('Bank name', '${batch['bank_name'] ?? '-'}'),
            _line('Cheque status', '${batch['cheque_status'] ?? 'Pending'}'),
          ],
          if (collector != null && collector.isNotEmpty)
            _line('Collected by', collector),
          if (remarks != null && remarks.isNotEmpty) _line('Remarks', remarks),
          pw.SizedBox(height: 12),
          pw.Text('Bill-wise allocation (oldest first)',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.1),
              4: const pw.FlexColumnWidth(1.1),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF2F8)),
                children: [
                  _cell('Bill', bold: true),
                  _cell('Period', bold: true),
                  _cell('Principal', bold: true, align: pw.TextAlign.right),
                  _cell('Interest', bold: true, align: pw.TextAlign.right),
                  _cell('Total', bold: true, align: pw.TextAlign.right),
                ],
              ),
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
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Text(
            '$societyName · Outstanding settlement receipt · Generated locally',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _cell(String text,
          {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );

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
