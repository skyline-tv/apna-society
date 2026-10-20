import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/local_database.dart';

/// Builds and shares a print-ready Monarch Solitaire maintenance bill PDF.
class BillPdf {
  BillPdf._();

  static const societyName = 'Monarch Solitaire A to E';
  static const societyAddress = 'Monarch Solitaire A to E Residential Society';
  static const logoAsset = 'assets/icons/app_icon.png';

  static Future<pw.MemoryImage?> _logoImage() async {
    try {
      final data = await rootBundle.load(logoAsset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static pw.TableRow _amountRow(String label, String value,
          {bool bold = false}) =>
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal),
                textAlign: pw.TextAlign.right),
          ),
        ],
      );

  static String money(int value) =>
      'Rs ${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  static String monthName(DateTime date) {
    const months = [
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
    return '${months[date.month - 1]} ${date.year}';
  }

  static String shortDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')} ${monthName(d).split(' ').first.substring(0, 3)} ${d.year}';
  }

  static String billingPeriodLabel({
    required String periodStart,
    required String periodEnd,
    required int monthsCovered,
  }) {
    final start = DateTime.tryParse(periodStart) ?? DateTime.now();
    final months = monthsCovered < 1 ? 1 : monthsCovered;
    if (months <= 1) return monthName(start);
    final end = DateTime.tryParse(periodEnd);
    final endMonth = end != null
        ? DateTime(end.year, end.month)
        : DateTime(start.year, start.month + months - 1);
    // ASCII hyphen only - Helvetica in pdf package cannot draw en-dash (U+2013).
    return '${monthName(start)} - ${monthName(endMonth)}';
  }

  static String fileName({
    required String flatNumber,
    required String periodStart,
  }) {
    final start = DateTime.tryParse(periodStart) ?? DateTime.now();
    final flat = flatNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final month = monthName(start).replaceAll(' ', '_');
    return 'Monarch_Solitaire_A_to_E_Bill_${flat}_$month.pdf';
  }

  static Future<pw.Document> build({
    required String billNumber,
    required String issueDate,
    required String dueDate,
    required String periodStart,
    required String periodEnd,
    required int monthsCovered,
    required int unitAmount,
    required int maintenanceAmount,
    required int otherChargesTotal,
    required List<Map<String, dynamic>> otherCharges,
    required int totalAmount,
    required String ownerName,
    required String building,
    required String flatNumber,
    required String mobile,
    required String status,
    String? paymentDate,
    String? transactionRef,
    String? remarks,
    String? address,
  }) async {
    final doc = pw.Document();
    final periodLabel = billingPeriodLabel(
      periodStart: periodStart,
      periodEnd: periodEnd,
      monthsCovered: monthsCovered,
    );
    final statusLabel = status.toUpperCase();
    final addr =
        (address == null || address.isEmpty) ? societyAddress : address;
    final logo = await _logoImage();

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                  width: 150,
                  child: pw.Text(k,
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700))),
              pw.Expanded(
                  child: pw.Text(v,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold))),
            ],
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(10),
                      border:
                          pw.Border.all(color: PdfColors.grey300, width: 0.6),
                    ),
                    child: pw.ClipRRect(
                      horizontalRadius: 10,
                      verticalRadius: 10,
                      child: pw.Image(logo, fit: pw.BoxFit.cover),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(societyName.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromInt(0xFF173B78))),
                      pw.SizedBox(height: 2),
                      pw.Text('Society Maintenance Bill',
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(addr,
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1.2, color: PdfColor.fromInt(0xFF2458C5)),
            pw.SizedBox(height: 12),
            pw.Text('Bill Information',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF173B78))),
            pw.SizedBox(height: 6),
            kv('Bill Number', billNumber),
            kv('Bill Issue Date', shortDate(issueDate)),
            kv('Due Date', shortDate(dueDate)),
            kv('Maintenance Period', periodLabel),
            kv('Prepaid Months', '$monthsCovered'),
            if (remarks != null && remarks.isNotEmpty) kv('Remarks', remarks),
            pw.SizedBox(height: 14),
            pw.Text('Flat Owner Information',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF173B78))),
            pw.SizedBox(height: 6),
            kv('Owner Name', ownerName),
            kv('Building / Wing', building),
            kv('Flat Number', flatNumber),
            kv('Registered Mobile', mobile),
            pw.SizedBox(height: 14),
            pw.Text('Charges Details',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF173B78))),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2)
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF2458C5)),
                  children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Description',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                color: PdfColors.white))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Amount',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                color: PdfColors.white),
                            textAlign: pw.TextAlign.right)),
                  ],
                ),
                _amountRow('Monthly Maintenance', money(unitAmount)),
                _amountRow('Prepaid Months', '$monthsCovered'),
                _amountRow('Maintenance Subtotal', money(maintenanceAmount),
                    bold: true),
                if (otherCharges.isNotEmpty) ...[
                  for (final c in otherCharges)
                    _amountRow('${c['description']}',
                        money((c['amount'] as int?) ?? 0)),
                  _amountRow('Other Charges Total', money(otherChargesTotal),
                      bold: true),
                ],
                _amountRow('Original Bill Total', money(totalAmount),
                    bold: true),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Text('Payment Information',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF173B78))),
            pw.SizedBox(height: 6),
            kv('Payment Status', statusLabel),
            if (status == 'paid') ...[
              kv('Payment Date', shortDate(paymentDate)),
              kv('Transaction Reference', transactionRef ?? '-'),
            ],
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            pw.Text('This is a computer-generated maintenance bill.',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.Text('Please pay by the due date.',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.Text('Society name: $societyName.',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text('Generated via ApnaSociety · Demo copy',
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
          ],
        ),
      ),
    );
    return doc;
  }

  static Map<String, dynamic> _amounts(Map<String, dynamic> bill) {
    final months = (bill['months_covered'] as int?) ?? 1;
    final unit = (bill['unit_amount'] as int?) ?? 0;
    final other = LocalDatabase.parseOtherChargesJson(
        bill['other_charges_json'] as String?);
    final otherTotal = (bill['other_charges_total'] as int?) ??
        other.fold<int>(0, (s, c) => s + (c['amount'] as int? ?? 0));
    final maint = (bill['maintenance_amount'] as int?) ??
        ((unit > 0
            ? unit * months
            : ((bill['amount'] as int?) ?? 0) - otherTotal));
    return {
      'months': months,
      'unit': unit,
      'other': other,
      'otherTotal': otherTotal,
      'maint': maint < 0 ? 0 : maint,
      'total': bill['amount'] as int,
    };
  }

  static Future<void> share({
    required Map<String, dynamic> bill,
    String? paymentDate,
    String? transactionRef,
    String? address,
  }) async {
    final periodStart = bill['period_start'] as String;
    final flatNumber = bill['flat_number'] as String;
    final a = _amounts(bill);
    final doc = await build(
      billNumber: (bill['bill_number'] as String?)?.isNotEmpty == true
          ? bill['bill_number'] as String
          : 'AS-BILL-${bill['id']}',
      issueDate: (bill['issue_date'] as String?) ??
          (bill['created_at'] as String? ?? ''),
      dueDate: bill['due_date'] as String,
      periodStart: periodStart,
      periodEnd: bill['period_end'] as String,
      monthsCovered: a['months'] as int,
      unitAmount: a['unit'] as int,
      maintenanceAmount: a['maint'] as int,
      otherChargesTotal: a['otherTotal'] as int,
      otherCharges: (a['other'] as List).cast<Map<String, dynamic>>(),
      totalAmount: a['total'] as int,
      ownerName: bill['owner_name'] as String,
      building: bill['building'] as String? ?? '-',
      flatNumber: flatNumber,
      mobile: bill['mobile'] as String? ?? '-',
      status: bill['status'] as String,
      paymentDate: paymentDate,
      transactionRef: transactionRef,
      remarks: bill['remarks'] as String?,
      address: address,
    );
    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName(flatNumber: flatNumber, periodStart: periodStart),
    );
  }

  static Future<void> preview({
    required Map<String, dynamic> bill,
    String? paymentDate,
    String? transactionRef,
    String? address,
  }) async {
    final periodStart = bill['period_start'] as String;
    final a = _amounts(bill);
    await Printing.layoutPdf(
      name: fileName(
          flatNumber: bill['flat_number'] as String, periodStart: periodStart),
      onLayout: (format) async {
        final doc = await build(
          billNumber: (bill['bill_number'] as String?)?.isNotEmpty == true
              ? bill['bill_number'] as String
              : 'AS-BILL-${bill['id']}',
          issueDate: (bill['issue_date'] as String?) ??
              (bill['created_at'] as String? ?? ''),
          dueDate: bill['due_date'] as String,
          periodStart: periodStart,
          periodEnd: bill['period_end'] as String,
          monthsCovered: a['months'] as int,
          unitAmount: a['unit'] as int,
          maintenanceAmount: a['maint'] as int,
          otherChargesTotal: a['otherTotal'] as int,
          otherCharges: (a['other'] as List).cast<Map<String, dynamic>>(),
          totalAmount: a['total'] as int,
          ownerName: bill['owner_name'] as String,
          building: bill['building'] as String? ?? '-',
          flatNumber: bill['flat_number'] as String,
          mobile: bill['mobile'] as String? ?? '-',
          status: bill['status'] as String,
          paymentDate: paymentDate,
          transactionRef: transactionRef,
          remarks: bill['remarks'] as String?,
          address: address,
        );
        return doc.save();
      },
    );
  }
}
