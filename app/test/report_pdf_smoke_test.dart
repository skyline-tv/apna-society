import 'package:flutter_test/flutter_test.dart';
import 'package:apna_society/services/report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('report PDFs generate non-empty bytes for empty datasets', () async {
    final paid = await ReportPdf.paidReportPdf(
      records: const [],
      filtersLabel: 'All periods · All wings · Paid only',
      totals: const {'paidCount': 0, 'collected': 0, 'billed': 0},
    );
    final unpaid = await ReportPdf.unpaidReportPdf(
      records: const [],
      filtersLabel: 'test',
      totals: const {
        'unpaidCount': 0,
        'outstanding': 0,
        'overdueCount': 0,
        'overdueAmount': 0
      },
      title: 'Unpaid Bills Report',
    );
    final overdue = await ReportPdf.unpaidReportPdf(
      records: const [],
      filtersLabel: 'Overdue only',
      totals: const {
        'unpaidCount': 0,
        'outstanding': 0,
        'overdueCount': 0,
        'overdueAmount': 0
      },
      title: 'Overdue Bills Report',
    );
    final collection = await ReportPdf.collectionReportPdf(
      allRows: const [],
      filtersLabel: 'test',
      totals: const {
        'rowCount': 0,
        'billed': 0,
        'collected': 0,
        'outstanding': 0
      },
    );
    final flat = await ReportPdf.flatStatementPdf(
      building: 'Monarch Solitaire A',
      flatNumber: '101',
      ownerName: 'Demo',
      flatType: '3 BHK',
      records: const [],
      totals: const {
        'rowCount': 0,
        'billed': 0,
        'collected': 0,
        'outstanding': 0
      },
    );

    expect(paid.length, greaterThan(100));
    expect(unpaid.length, greaterThan(100));
    expect(overdue.length, greaterThan(100));
    expect(collection.length, greaterThan(100));
    expect(flat.length, greaterThan(100));
  });

  test('days overdue is zero before due date', () {
    final tomorrow =
        DateTime.now().add(const Duration(days: 1)).toIso8601String();
    expect(ReportPdf.daysOverdue(tomorrow, 'pending'), 0);
    expect(ReportPdf.daysOverdue(tomorrow, 'overdue'), 0);
  });
}
