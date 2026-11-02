import 'package:apna_society/features/admin/admin_bill_detail_page.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paid admin bill details match the mockup on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: kBillDetailGround,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const AdminBillDetailIdentity(
                period: 'September 2026 - December 2026',
                flatLabel: 'A-101',
                billNumber: 'BILL-2026-000001',
                status: 'Paid',
              ),
              const SizedBox(height: 12),
              const AdminBillOutstandingHero(
                amount: '₹0.00',
                paid: '₹12,000.00',
                outstanding: '₹0.00',
                caption: 'All dues cleared',
                settled: true,
              ),
              const SizedBox(height: 12),
              const AdminBillMetaCard(
                lines: [
                  AdminBillMetaLine(
                    label: 'Period',
                    value: 'September 2026 - December 2026',
                  ),
                  AdminBillMetaLine(
                    label: 'Months',
                    value: '3 of 3 months paid',
                    chip: true,
                  ),
                  AdminBillMetaLine(label: 'Due date', value: '31 Dec 2026'),
                  AdminBillMetaLine(
                    label: 'Owner',
                    value: 'Unassigned',
                    italic: true,
                    actionLabel: 'Assign',
                  ),
                  AdminBillMetaLine(label: 'Flat type', value: '2BHK'),
                ],
              ),
              const SizedBox(height: 12),
              const AdminBillAmountCard(
                title: 'BREAKDOWN',
                lines: [
                  AdminBillAmountLine(
                    label: 'Monthly maintenance × 3',
                    value: '₹12,000.00',
                  ),
                  AdminBillAmountLine(
                    label: 'Original bill amount',
                    value: '₹12,000.00',
                  ),
                  AdminBillAmountLine(
                    label: 'Paid',
                    value: '-₹12,000.00',
                    tone: AdminBillAmountTone.credit,
                  ),
                  AdminBillAmountLine(
                    label: 'Accrued interest',
                    value: '₹0.00',
                  ),
                  AdminBillAmountLine(
                    label: 'Total payable',
                    value: '₹0.00',
                    tone: AdminBillAmountTone.total,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const AdminBillAmountCard(
                title: 'LATE-PAYMENT INTEREST',
                lines: [
                  AdminBillAmountLine(
                    label: 'Accrued interest',
                    value: '₹0.00',
                  ),
                  AdminBillAmountLine(label: 'Overdue days', value: '0'),
                  AdminBillAmountLine(
                    label: 'Annual rate',
                    value: '24% p.a.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AdminBillCollectSection(
                settled: true,
                busy: false,
                receiptLabel: 'Receipt',
                onReceipt: () {},
                onDownload: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('September 2026 - December 2026'), findsWidgets);
    expect(find.textContaining('BILL-2026-000001'), findsOneWidget);
    expect(find.text('Paid'), findsWidgets);
    expect(find.text('OUTSTANDING'), findsOneWidget);
    expect(find.text('All dues cleared'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Assign'), findsOneWidget);
    expect(find.text('Total payable'), findsOneWidget);
    expect(find.text('Accrued interest'), findsWidgets);
    await tester.scrollUntilVisible(find.text('This bill is settled.'), 240);
    await tester.pump();
    expect(find.text('This bill is settled.'), findsOneWidget);
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
  });

  testWidgets('open bill details keep collect actions on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminBillCollectSection(
            settled: false,
            busy: false,
            primaryLabel: 'Record offline payment',
            onPrimary: () {},
            secondaryLabel: 'Adjust bill',
            onSecondary: () {},
            tertiaryLabel: 'Cancel bill',
            onTertiary: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Record offline payment'), findsOneWidget);
    expect(find.text('Adjust bill'), findsOneWidget);
    expect(find.text('Cancel bill'), findsOneWidget);
    expect(find.text('This bill is settled.'), findsNothing);
  });
}
