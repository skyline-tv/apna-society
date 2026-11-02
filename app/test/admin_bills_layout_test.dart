import 'package:apna_society/api/models/billing_models.dart';
import 'package:apna_society/features/admin/admin_bills_page.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin bills chrome matches the mockup on a phone', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const overdue = Bill(
      id: 'b1',
      billNumber: 'MS-2026-021',
      flatId: 'f1',
      billingPeriodStart: '2026-02-01',
      billingPeriodEnd: '2026-02-28',
      numberOfMonths: 1,
      monthlyRatePaise: 450000,
      baseAmountPaise: 450000,
      totalAmountPaise: 485000,
      outstandingPrincipalPaise: 450000,
      interestAccruedPaise: 35000,
      interestOutstandingPaise: 35000,
      totalPayablePaise: 485000,
      amountPaidPaise: 0,
      dueDate: '2026-02-10',
      status: 'OVERDUE',
      flatNumberSnapshot: '101',
      wingCodeSnapshot: 'A',
      flatTypeSnapshot: '2BHK',
      ownerNameSnapshot: 'Dr. Rajesh Varma',
      ownerEmailSnapshot: 'rajesh@example.com',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminBillsHero(
                payableLabel: 'Total payable',
                payable: '₹1,81,653.16',
                principal: '₹1,68,500.00',
                interest: '₹13,153.16',
                billCount: 40,
                periodLabel: 'Feb 2026',
                generateLabel: 'Generate bills',
                onGenerate: () {},
              ),
              const SizedBox(height: 12),
              const AdminBillsCollectionsCard(
                percent: 3.44,
                collected: '₹6,000.00',
                billed: '₹1,74,500.00',
              ),
              const SizedBox(height: 12),
              const AdminBillsKpiGrid(
                collected: '₹6,000.00',
                collectedCaption: '1 flat received',
                overdueCount: 31,
                paidCount: 1,
                pendingCount: 9,
                accruedLabel: 'Accrued interest',
                accrued: '₹13,153.16',
              ),
              const SizedBox(height: 12),
              AdminBillsServicesLink(onTap: () {}),
              const SizedBox(height: 12),
              AdminBillsDirectoryHeader(total: 40, onSort: () {}),
              const SizedBox(height: 8),
              AdminBillsStatusChips(selected: null, onSelect: (_) {}),
              const SizedBox(height: 8),
              AdminBillsWingChips(
                wings: const [
                  BillingWingTotal(
                    wingCode: 'A',
                    billedPaise: 100,
                    collectedPaise: 10,
                    outstandingPrincipalPaise: 90,
                    billCount: 4,
                  ),
                ],
                selected: null,
                onSelect: (_) {},
              ),
              const SizedBox(height: 12),
              AdminBillCard(
                bill: overdue,
                onOpen: () {},
                onRecordPayment: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('TOTAL PAYABLE'), findsOneWidget);
    expect(find.text('Generate bills'), findsOneWidget);
    expect(find.text('Collections'), findsOneWidget);
    expect(find.text('Accrued interest'), findsOneWidget);
    expect(find.text('Additional services'), findsOneWidget);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('All wings'), findsOneWidget);
    expect(find.text('Dr. Rajesh Varma'), findsOneWidget);
    expect(find.text('Overdue'), findsWidgets);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('View'), findsNothing);
  });

  testWidgets('paid bill cards keep receipt and hide record payment',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const paid = Bill(
      id: 'b2',
      billNumber: 'MS-2026-022',
      flatId: 'f1',
      billingPeriodStart: '2026-02-01',
      billingPeriodEnd: '2026-02-28',
      numberOfMonths: 1,
      monthlyRatePaise: 450000,
      baseAmountPaise: 450000,
      totalAmountPaise: 450000,
      outstandingPrincipalPaise: 0,
      interestAccruedPaise: 0,
      amountPaidPaise: 450000,
      dueDate: '2026-02-10',
      status: 'PAID',
      flatNumberSnapshot: '101',
      wingCodeSnapshot: 'A',
      flatTypeSnapshot: '2BHK',
      ownerNameSnapshot: 'Dr. Rajesh Varma',
      ownerEmailSnapshot: 'rajesh@example.com',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminBillCard(
            bill: paid,
            onOpen: () {},
            onRecordPayment: () {},
            onReceipt: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Record'), findsNothing);
    expect(find.text('Receipt'), findsOneWidget);
  });
}
