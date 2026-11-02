import 'package:apna_society/api/models/billing_models.dart';
import 'package:apna_society/features/admin/admin_payments_page.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cash = PaymentSummary(
    id: 'p1',
    paymentNumber: 'PAY-2026-000002',
    billId: 'b1',
    amountPaise: 200000,
    allocatedToPrincipalPaise: 200000,
    allocatedToInterestPaise: 0,
    paymentMethod: 'CASH',
    status: 'SUCCESS',
    paidAt: '2026-04-18T10:00:00.000Z',
    billNumber: 'BILL-2026-000010',
    wingCodeSnapshot: 'A',
    flatNumberSnapshot: '102',
    referenceNumber: null,
  );

  test('payment search matches flat, txn and mode', () {
    expect(
      adminPaymentMatches(cash, query: 'a-102'),
      isTrue,
    );
    expect(
      adminPaymentMatches(cash, query: 'pay-2026-000002'),
      isTrue,
    );
    expect(
      adminPaymentMatches(cash, query: 'cash'),
      isTrue,
    );
    expect(
      adminPaymentMatches(cash, query: 'upi'),
      isFalse,
    );
    expect(
      adminPaymentMatches(cash, query: '', wing: 'B'),
      isFalse,
    );
    expect(
      adminPaymentMatches(cash, query: '', status: 'SUCCESS', offlineOnly: true),
      isTrue,
    );
  });

  test('only successful office payments can be cancelled', () {
    expect(adminPaymentIsCancellable(cash), isTrue);
    expect(
      adminPaymentIsCancellable(PaymentSummary(
        id: 'p2',
        paymentNumber: 'PAY-2026-000003',
        billId: 'b1',
        amountPaise: 200000,
        allocatedToPrincipalPaise: 200000,
        allocatedToInterestPaise: 0,
        paymentMethod: 'UPI',
        status: 'SUCCESS',
        gatewayOrderId: 'order_live_1',
      )),
      isFalse,
    );
    expect(
      adminPaymentIsCancellable(PaymentSummary(
        id: 'p3',
        paymentNumber: 'PAY-2026-000004',
        billId: 'b1',
        amountPaise: 200000,
        allocatedToPrincipalPaise: 200000,
        allocatedToInterestPaise: 0,
        paymentMethod: 'CASH',
        status: 'REFUNDED',
      )),
      isFalse,
    );
  });

  testWidgets('admin payments chrome matches the mockup on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminPaymentsHeader(onRecord: () {}),
              const SizedBox(height: 12),
              const AdminPaymentsMetrics(
                shownCount: 5,
                successTotal: '₹18,000.00',
              ),
              const SizedBox(height: 12),
              const AdminPaymentsCancelTip(),
              const SizedBox(height: 12),
              AdminPaymentsSearchBar(
                controller: TextEditingController(),
                onChanged: (_) {},
                onClear: () {},
                onFilter: () {},
              ),
              const SizedBox(height: 10),
              AdminPaymentsFilterChips(
                wings: const ['A', 'B'],
                counts: const {'ALL': 5, 'A': 3, 'B': 2},
                selectedWing: null,
                statusFilter: null,
                offlineOnly: false,
                onSelectAll: () {},
                onSelectWing: (_) {},
                onToggleSuccessful: () {},
                onToggleOffline: () {},
              ),
              const SizedBox(height: 12),
              AdminPaymentCard(payment: cash, onTap: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Payments Ledger'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Shown transactions'), findsOneWidget);
    expect(find.text('Successful total'), findsOneWidget);
    expect(
      find.text(
          'Long-press an office payment to cancel it if it was recorded by mistake.'),
      findsOneWidget,
    );
    expect(find.text('All (5)'), findsOneWidget);
    expect(find.text('Wing A (3)'), findsOneWidget);
    expect(find.text('Successful'), findsWidgets);
    expect(find.text('A-102'), findsOneWidget);
    expect(find.text('Cash collected'), findsOneWidget);
  });
}
