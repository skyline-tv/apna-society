import 'package:flutter_test/flutter_test.dart';
import 'package:apna_society/services/receipt_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receipt PDF generates for cash and cheque', () async {
    final cash = await ReceiptPdf.buildBytes(
      payment: {
        'receipt_number': 'MS-RCP-TEST-1',
        'amount': 12000,
        'method': 'Cash',
        'status': 'success',
        'paid_at': DateTime.now().toIso8601String(),
        'collected_by_name': 'Society Admin',
        'remarks': 'Office collection',
      },
      bill: {
        'id': 1,
        'bill_number': 'AS-BILL-1001',
        'flat_number': 'A-101',
        'building': 'Monarch Solitaire A',
        'owner_name': 'Demo Owner',
        'period_start': DateTime(2026, 4, 1).toIso8601String(),
        'months_covered': 3,
        'amount': 12000,
      },
    );
    final cheque = await ReceiptPdf.buildBytes(
      payment: {
        'receipt_number': 'MS-RCP-TEST-2',
        'amount': 15000,
        'method': 'Cheque',
        'status': 'success',
        'paid_at': DateTime.now().toIso8601String(),
        'cheque_number': 'CHQ123',
        'cheque_date': DateTime.now().toIso8601String(),
        'bank_name': 'Demo Bank',
        'cheque_status': 'Pending',
        'collected_by_name': 'Society Admin',
      },
      bill: {
        'id': 2,
        'bill_number': 'AS-BILL-1002',
        'flat_number': 'A-103',
        'building': 'Monarch Solitaire A',
        'owner_name': 'Owner',
        'period_start': DateTime(2026, 4, 1).toIso8601String(),
        'months_covered': 3,
        'amount': 15000,
      },
    );
    expect(cash.length, greaterThan(100));
    expect(cheque.length, greaterThan(100));
    expect(
        ReceiptPdf.methodLabel(
            {'method': 'Cheque', 'cheque_status': 'Pending'}),
        'Cheque Recorded');
  });
}
