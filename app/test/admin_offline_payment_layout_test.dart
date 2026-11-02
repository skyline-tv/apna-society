import 'package:apna_society/api/models/billing_models.dart';
import 'package:apna_society/features/admin/admin_offline_payment_page.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bill = Bill(
  id: 'b1',
  billNumber: 'BILL-2026-000025',
  flatId: 'f1',
  billingPeriodStart: '2026-09-01',
  billingPeriodEnd: '2026-12-01',
  numberOfMonths: 3,
  monthlyRatePaise: 400000,
  baseAmountPaise: 1200000,
  totalAmountPaise: 1200000,
  outstandingPrincipalPaise: 1200000,
  interestAccruedPaise: 0,
  totalPayablePaise: 1200000,
  amountPaidPaise: 0,
  dueDate: '2026-12-31',
  status: 'ISSUED',
  flatNumberSnapshot: '701',
  wingCodeSnapshot: 'A',
  flatTypeSnapshot: '2BHK',
  ownerNameSnapshot: 'Owner',
  ownerEmailSnapshot: 'owner@example.com',
);

void main() {
  test('month options describe settlement and advances', () {
    expect(
      adminOfflineMonthOptionLabel(months: 3, pending: 3),
      '3 months (Full settlement)',
    );
    expect(
      adminOfflineMonthOptionLabel(months: 4, pending: 3),
      '4 months (1 advance)',
    );
    expect(
      adminOfflineMonthOptionLabel(months: 12, pending: 3),
      '12 months (Full year)',
    );
    expect(adminOfflineMonthsFieldText(6), '6 months');
    expect(parseOfflineMonthsInput('6'), 6);
    expect(parseOfflineMonthsInput('6 months'), 6);
    expect(parseOfflineMonthsInput('12'), 12);
    expect(parseOfflineMonthsInput('0'), isNull);
    expect(parseOfflineMonthsInput('13'), isNull);
    expect(isCompleteOfflineMonthsInput('6'), isTrue);
    expect(isCompleteOfflineMonthsInput('1'), isFalse);
    expect(isCompleteOfflineMonthsInput('12'), isTrue);
    expect(
      const OfflineMonthsInputFormatter().formatEditUpdate(
        const TextEditingValue(text: '1'),
        const TextEditingValue(text: '13'),
      ).text,
      '1',
    );
    expect(
      const OfflineMonthsInputFormatter().formatEditUpdate(
        const TextEditingValue(text: '3'),
        const TextEditingValue(text: '12'),
      ).text,
      '12',
    );
    expect(
      adminOfflinePaymentDateLabel(
        DateTime(2026, 11, 2),
        now: DateTime(2026, 11, 2, 19),
      ),
      'Today, 02 Nov 2026',
    );
  });

  testWidgets('offline payment chrome matches the mockup on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final months = TextEditingController(text: '3 months');
    addTearDown(months.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: kOfflineCream,
          appBar: AppBar(
            backgroundColor: kOfflineCream,
            titleSpacing: 8,
            title: const Text(
              'Record offline payment',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            actions: const [AdminOfflineActiveBadge()],
          ),
          body: ListView(
            key: const Key('offline-body'),
            padding: const EdgeInsets.all(16),
            children: [
              const AdminOfflineBillCard(
                billNumber: 'BILL-2026-000025',
                flatLabel: 'A-701',
                period: 'September 2026 - December 2026',
                principal: '₹12,000.00',
                interest: '₹0.00',
                monthsLabel: '0 of 3 months paid · 3 pending',
                amountDue: '₹12,000.00',
              ),
              const SizedBox(height: 16),
              AdminOfflineMethodPills(
                methods: const [
                  ('CASH', 'Cash'),
                  ('CHEQUE', 'Cheque'),
                  ('NEFT', 'NEFT'),
                  ('UPI', 'UPI'),
                ],
                selected: 'CASH',
                onSelected: (_) {},
              ),
              const SizedBox(height: 16),
              AdminOfflineMonthsPicker(
                controller: months,
                selectedMonths: 3,
                expanded: true,
                options: adminOfflineMonthOptions(bill: _bill, selected: 3),
                preview: '₹12,000.00 · This bill: paid in full',
                caption:
                    'Choose how many months were received. Extra months beyond this bill are created and marked paid. Additional services on advance bills are included on the server.',
                onToggle: () {},
                onSelected: (_) {},
              ),
              const SizedBox(height: 16),
              AdminOfflineDateField(
                label: 'Today, 02 Nov 2026',
                onChange: () {},
              ),
            ],
          ),
          bottomNavigationBar: BottomActionBar(
            children: [
              PrimaryButton(
                label: 'Review & record',
                icon: Icons.check_rounded,
                color: kOfflineNavy,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Record offline payment'), findsOneWidget);
    expect(find.text('Active Bill'), findsOneWidget);
    expect(find.text('APPLYING TO'), findsOneWidget);
    expect(find.text('BILL-2026-000025'), findsOneWidget);
    expect(find.text('Outstanding principal'), findsOneWidget);
    expect(find.text('Accrued interest'), findsOneWidget);
    expect(find.text('AMOUNT DUE'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Cheque'), findsOneWidget);
    expect(find.text('NEFT'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('3 months (Full settlement)'), findsOneWidget);
    expect(find.textContaining('This bill: paid in full'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Change'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('offline-body')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Review & record'), findsOneWidget);
  });

  testWidgets('typing or picking months closes the list and shows 6 months',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const _MonthsPickerHarness(),
      ),
    );
    await tester.pump();
    expect(find.text('SUGGESTED TENURES'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '6');
    await tester.pump();
    expect(find.text('6 months'), findsOneWidget);
    expect(find.text('SUGGESTED TENURES'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('SUGGESTED TENURES'), findsOneWidget);
    await tester.tap(find.text('3 months (Full settlement)'));
    await tester.pump();
    expect(find.text('3 months'), findsOneWidget);
    expect(find.text('SUGGESTED TENURES'), findsNothing);
  });
}

class _MonthsPickerHarness extends StatefulWidget {
  const _MonthsPickerHarness();

  @override
  State<_MonthsPickerHarness> createState() => _MonthsPickerHarnessState();
}

class _MonthsPickerHarnessState extends State<_MonthsPickerHarness> {
  int monthsPaid = 3;
  bool open = true;
  late final controller =
      TextEditingController(text: adminOfflineMonthsFieldText(monthsPaid));

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _setMonths(int months) {
    setState(() {
      monthsPaid = months;
      open = false;
      controller.text = adminOfflineMonthsFieldText(months);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AdminOfflineMonthsPicker(
        controller: controller,
        selectedMonths: monthsPaid,
        expanded: open,
        options: adminOfflineMonthOptions(bill: _bill, selected: monthsPaid),
        preview: 'preview',
        caption: 'caption',
        onToggle: () => setState(() => open = !open),
        onSelected: _setMonths,
        onTap: () {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
          if (!open) setState(() => open = true);
        },
        onChanged: (value) {
          final parsed = parseOfflineMonthsInput(value);
          if (parsed != null && isCompleteOfflineMonthsInput(value)) {
            _setMonths(parsed);
          }
        },
      ),
    );
  }
}
