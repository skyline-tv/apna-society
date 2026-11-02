import 'package:apna_society/api/models/billing_models.dart';
import 'package:apna_society/features/billing/receipt_document.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt helpers keep vacant owners and wing labels honest', () {
    expect(receiptPayerName('Unassigned'), '-');
    expect(receiptPayerName('Rahul Mehta'), 'Rahul Mehta');
    expect(
      receiptWingFlatLine(wingCode: 'A', flatNumber: '101'),
      'Wing A - Flat 101',
    );
    expect(
      receiptTowards(
        periodStart: '2026-10-01',
        periodEnd: '2026-12-31',
      ),
      'Monthly maintenance - 01 Oct 2026 - 31 Dec 2026',
    );
    expect(receiptMethodLabel('UPI'), 'UPI');
    expect(receiptMoneyPaise(1200000), 'Rs 12,000.00');
  });

  testWidgets('receipt sheet matches the A4 template on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const receipt = ReceiptBody(
      id: 'r1',
      receiptNumber: 'RCPT-2026-000001',
      billId: 'b1',
      paymentId: 'p1',
      flatId: 'f1',
      amountPaise: 1200000,
      paymentMethod: 'UPI',
      paidAt: '2026-10-27T10:00:00.000+05:30',
      generatedAt: '2026-10-27T10:00:00.000+05:30',
      ownerNameSnapshot: 'Unassigned',
      flatNumberSnapshot: '101',
      wingCodeSnapshot: 'A',
      societyNameSnapshot: 'Monarch Solitaire A to E',
      transactionReference: 'offline_PAY-2026-000001',
      billNumber: 'BILL-2026-000001',
      billingPeriodStart: '2026-10-01',
      billingPeriodEnd: '2026-12-31',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: kReceiptPage,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ReceiptActionBar(onPrint: () {}, onDownload: () {}),
              const SizedBox(height: 12),
              ReceiptSheet.fromBody(receipt),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('A4 Paper'), findsOneWidget);
    expect(find.text('Print (A4)'), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
    expect(find.text('Monarch Solitaire A to E'), findsWidgets);
    expect(find.text('RECEIPT'), findsOneWidget);
    expect(find.text('RCPT-2026-000001'), findsOneWidget);
    expect(find.text('SUCCESSFUL'), findsOneWidget);
    expect(find.text('PAYMENT DATE'), findsOneWidget);
    expect(find.text('27 Oct 2026'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Wing A - Flat 101'), findsOneWidget);
    expect(find.text('Base Maintenance Charges'), findsOneWidget);
    expect(find.text('Total Amount Paid'), findsOneWidget);
    expect(find.text('BILL-2026-000001'), findsOneWidget);
    expect(find.text('offline_PAY-2026-000001'), findsOneWidget);
    expect(
      find.text(
          'This is an authorized receipt for a confirmed payment, generated from verified society records.\nNo signature is required for digitally issued receipts.'),
      findsOneWidget,
    );
    expect(find.text('AUTHORIZED'), findsOneWidget);
    expect(find.text('Unassigned'), findsNothing);
  });
}
