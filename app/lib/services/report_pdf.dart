import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Society financial report PDFs for Monarch Solitaire A to E (admin only).
class ReportPdf {
  ReportPdf._();

  static const societyName = 'Monarch Solitaire A to E';
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
    // ASCII hyphen only — Helvetica in pdf package cannot draw en-dash (U+2013).
    return '${name(DateTime(d.year, d.month))} - ${name(endMonth)}';
  }

  static int daysOverdue(String? dueDate, String status) {
    if (status != 'overdue' && status != 'pending') return 0;
    final due = DateTime.tryParse(dueDate ?? '');
    if (due == null) return 0;
    final today = DateTime.now();
    final dueDay = DateTime(due.year, due.month, due.day);
    final nowDay = DateTime(today.year, today.month, today.day);
    if (!nowDay.isAfter(dueDay)) return 0;
    return nowDay.difference(dueDay).inDays;
  }

  static Future<pw.Document> buildTableReport({
    required String title,
    required String filtersLabel,
    required List<String> columns,
    required List<List<String>> rows,
    required Map<String, String> summary,
    String? periodNote,
  }) async {
    final logo = await _logo();
    final generated = DateTime.now();
    final genLabel =
        '${generated.day.toString().padLeft(2, '0')}-${generated.month.toString().padLeft(2, '0')}-${generated.year}';

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4, // portrait
        margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Container(width: 28, height: 28, child: pw.Image(logo)),
                  pw.SizedBox(width: 8),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(societyName,
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text(title,
                          style: pw.TextStyle(
                              fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.Text(genLabel,
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.7),
            pw.SizedBox(height: 4),
            pw.Text(filtersLabel,
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
            if (periodNote != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(periodNote,
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800)),
            ],
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Column(children: [
          pw.Divider(thickness: 0.4),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(societyName,
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey600)),
              pw.Text('${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey600)),
            ],
          ),
        ]),
        build: (context) {
          final widgets = <pw.Widget>[];
          if (summary.isNotEmpty) {
            widgets.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF5F7FB),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: summary.entries
                      .map((e) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2),
                            child: pw.Text('${e.key}: ${e.value}',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ))
                      .toList(),
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
          }
          if (rows.isEmpty) {
            widgets.add(pw.Center(
                child: pw.Text('No records for the selected filters.',
                    style: const pw.TextStyle(fontSize: 10))));
          } else {
            widgets.add(
              pw.TableHelper.fromTextArray(
                headers: columns,
                data: rows,
                headerStyle: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E4DB7)),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                headerAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(
                    horizontal: 4, vertical: 3),
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 0.35),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                oddRowDecoration:
                    const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F7FB)),
              ),
            );
          }
          return widgets;
        },
      ),
    );
    return doc;
  }

  static Future<void> previewBytes(Uint8List bytes, String name) async {
    await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
  }

  static Future<void> shareBytes(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<Uint8List> paidReportPdf({
    required List<Map<String, dynamic>> records,
    required String filtersLabel,
    required Map<String, int> totals,
  }) async {
    final rows = records.map((r) {
      final method = r['payment_method'] as String? ?? '-';
      final chequeNo = r['cheque_number'] as String?;
      final chequeStatus = r['cheque_status'] as String?;
      String methodLabel = method;
      if (method == 'Cheque') {
        final statusBit = (chequeStatus == null || chequeStatus == 'Pending')
            ? 'Recorded'
            : chequeStatus;
        methodLabel = chequeNo != null && chequeNo.isNotEmpty
            ? 'Chq $chequeNo ($statusBit)'
            : 'Cheque ($statusBit)';
      }
      return [
        '${r['flat_number'] ?? ''}',
        periodLabel(r['period_start'] as String?, r['months_covered'] as int?,
            periodEnd: r['period_end'] as String?),
        money(r['amount'] as int? ?? 0),
        methodLabel,
        shortDate(r['paid_at'] as String?),
        '${r['receipt_number'] ?? '-'}',
      ];
    }).toList();
    final doc = await buildTableReport(
      title: 'Paid Bills',
      filtersLabel: filtersLabel,
      columns: const [
        'Flat',
        'Period',
        'Amount',
        'Method',
        'Paid on',
        'Receipt',
      ],
      rows: rows,
      summary: {
        'Paid bills': '${totals['paidCount'] ?? rows.length}',
        'Total collection': money(totals['collected'] ?? 0),
      },
    );
    return doc.save();
  }

  static Future<Uint8List> unpaidReportPdf({
    required List<Map<String, dynamic>> records,
    required String filtersLabel,
    required Map<String, int> totals,
    required String title,
  }) async {
    final rows = records.map((r) {
      final status = r['status'] as String? ?? 'pending';
      final amount = r['amount'] as int? ?? 0;
      final interest = r['interest_outstanding'] as int? ?? 0;
      final totalDue = r['total_outstanding'] as int? ?? (amount + interest);
      final odMonths = r['overdue_months'] as int? ?? 0;
      return [
        '${r['flat_number'] ?? ''}',
        periodLabel(r['period_start'] as String?, r['months_covered'] as int?,
            periodEnd: r['period_end'] as String?),
        money(amount),
        money(interest),
        money(totalDue),
        status == 'overdue' || odMonths > 0 ? 'OVERDUE' : 'UNPAID',
      ];
    }).toList();
    final doc = await buildTableReport(
      title: title,
      filtersLabel: filtersLabel,
      columns: const [
        'Flat',
        'Period',
        'Amount',
        'Interest',
        'Total',
        'Status',
      ],
      rows: rows,
      summary: {
        'Unpaid bills': '${totals['unpaidCount'] ?? rows.length}',
        'Total outstanding': money(totals['outstanding'] ?? 0),
        'Overdue bills': '${totals['overdueCount'] ?? 0}',
      },
    );
    return doc.save();
  }

  static Future<Uint8List> collectionReportPdf({
    required List<Map<String, dynamic>> allRows,
    required String filtersLabel,
    required Map<String, int> totals,
  }) async {
    final rows = allRows.map((r) {
      final status = (r['status'] as String? ?? '').toUpperCase();
      return [
        '${r['flat_number'] ?? ''}',
        _wing(r['building'] as String?),
        periodLabel(r['period_start'] as String?, r['months_covered'] as int?,
            periodEnd: r['period_end'] as String?),
        money(r['amount'] as int? ?? 0),
        status,
        '${r['receipt_number'] ?? '-'}',
      ];
    }).toList();
    final doc = await buildTableReport(
      title: 'Collection Report',
      filtersLabel: filtersLabel,
      columns: const [
        'Flat',
        'Wing',
        'Period',
        'Amount',
        'Status',
        'Receipt',
      ],
      rows: rows,
      summary: {
        'Bills': '${totals['rowCount'] ?? rows.length}',
        'Collected': money(totals['collected'] ?? 0),
        'Outstanding': money(totals['outstanding'] ?? 0),
      },
    );
    return doc.save();
  }

  static Future<Uint8List> flatStatementPdf({
    required String building,
    required String flatNumber,
    required String ownerName,
    required String flatType,
    required List<Map<String, dynamic>> records,
    required Map<String, int> totals,
  }) async {
    final rows = records.map((r) {
      final status = r['status'] as String? ?? '';
      return [
        periodLabel(r['period_start'] as String?, r['months_covered'] as int?,
            periodEnd: r['period_end'] as String?),
        money(r['amount'] as int? ?? 0),
        status.toUpperCase(),
        shortDate(r['paid_at'] as String?),
        '${r['receipt_number'] ?? '-'}',
      ];
    }).toList();
    final doc = await buildTableReport(
      title: 'Flat Statement',
      filtersLabel: '$flatNumber · $ownerName · $flatType',
      periodNote: 'Outstanding: ${money(totals['outstanding'] ?? 0)}',
      columns: const [
        'Period',
        'Amount',
        'Status',
        'Paid on',
        'Receipt',
      ],
      rows: rows,
      summary: {
        'Bills': '${totals['rowCount'] ?? rows.length}',
        'Collected': money(totals['collected'] ?? 0),
        'Outstanding': money(totals['outstanding'] ?? 0),
      },
    );
    return doc.save();
  }

  static String _wing(String? building) {
    if (building == null || building.isEmpty) return '-';
    return building.replaceFirst('Monarch Solitaire ', '');
  }

  static String fileName(String kind) {
    final t = DateTime.now();
    final stamp =
        '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}_${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';
    return 'Monarch_Solitaire_A_to_E_${kind}_$stamp.pdf';
  }
}
