import 'package:apna_society/api/models/admin_user_models.dart';
import 'package:apna_society/api/models/billing_models.dart';
import 'package:apna_society/api/models/common.dart' as api;
import 'package:apna_society/api/models/society_models.dart';
import 'package:apna_society/features/admin/admin_flat_detail_page.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parking label stays honest when no slot exists', () {
    expect(adminFlatParkingLabel(null), 'No parking');
    expect(adminFlatParkingLabel(const FlatParking(hasParking: false)),
        'No parking');
    expect(
      adminFlatParkingLabel(
        const FlatParking(hasParking: true, slotLabel: 'B-12'),
      ),
      'Slot B-12',
    );
  });

  testWidgets('vacant flat details match the mockup on a phone', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const vacant = FlatSummary(
      id: 'f1',
      societyId: 's1',
      wingId: 'w1',
      number: 'A-101',
      floor: 1,
      position: 1,
      flatType: '2BHK',
      maintenanceRate: 4000,
      isActive: true,
      occupancyStatus: 'VACANT',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      wingCode: 'A',
      wingName: 'Wing A',
    );
    const paid = Bill(
      id: 'b1',
      billNumber: 'BILL-2026-000001',
      flatId: 'f1',
      billingPeriodStart: '2026-10-01',
      billingPeriodEnd: '2026-10-31',
      numberOfMonths: 1,
      monthlyRatePaise: 400000,
      baseAmountPaise: 400000,
      totalAmountPaise: 1200000,
      outstandingPrincipalPaise: 0,
      interestAccruedPaise: 0,
      amountPaidPaise: 1200000,
      dueDate: '2026-10-10',
      status: 'PAID',
      flatNumberSnapshot: '101',
      wingCodeSnapshot: 'A',
      flatTypeSnapshot: '2BHK',
      ownerNameSnapshot: '',
      ownerEmailSnapshot: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminFlatDetailBody(
            flat: vacant,
            history: const AdminOccupancyHistory(
              flatId: 'f1',
              occupancyStatus: 'VACANT',
              items: [],
              pagination: api.Page(page: 1, limit: 20, total: 0, totalPages: 0),
            ),
            services: const [],
            bills: const [paid],
            busy: false,
            ownerActionLabel: 'Add',
            onOwnerAction: () {},
            occupancyStepLabel: 'Assign owner',
            occupancyStepCaption: 'Pick an owner account for this flat',
            occupancyStepIcon: Icons.person_add_alt_1_outlined,
            onOccupancyStep: () {},
            onAddService: () {},
            onOpenService: (_) {},
            onOpenBill: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('A-101'), findsOneWidget);
    expect(find.text('101'), findsOneWidget);
    expect(find.text('Wing A · Floor 1 · 2 BHK'), findsOneWidget);
    expect(find.text('Vacant'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('FLAT OVERVIEW'), findsOneWidget);
    expect(find.text('Monthly maintenance'), findsOneWidget);
    expect(find.text('₹4,000'), findsWidgets);
    expect(find.text('No parking'), findsOneWidget);
    expect(find.text('Who lives here'), findsOneWidget);
    expect(find.text('No owner allotted'), findsOneWidget);
    expect(find.text('No active tenant'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Next occupancy step'), findsOneWidget);
    expect(find.text('Assign owner'), findsOneWidget);
    expect(find.text('Pick an owner account for this flat'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Billing & services'), 240);
    await tester.pump();
    expect(find.text('RECURRING MONTHLY'), findsOneWidget);
    expect(find.text('Total recurring'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Additional Services — 0/10'), 240);
    await tester.pump();
    expect(find.text('Add additional service'), findsOneWidget);
    expect(find.text('No additional services on this flat'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Billing history'), 240);
    await tester.pump();
    expect(find.text('BILL-2026-000001'), findsOneWidget);
    expect(find.text('Settled'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('No occupancy history yet'), 240);
    await tester.pump();
    expect(find.text('Occupancy history'), findsOneWidget);
    expect(find.text('No occupancy history yet'), findsOneWidget);
    expect(find.text('Audit trail & logs'), findsNothing);
  });

  testWidgets('owner occupied flat shows assign tenant on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const occupied = FlatSummary(
      id: 'f1',
      societyId: 's1',
      wingId: 'w1',
      number: 'A-101',
      floor: 1,
      position: 1,
      flatType: '2BHK',
      maintenanceRate: 4000,
      isActive: true,
      occupancyStatus: 'OWNER_OCCUPIED',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      wingCode: 'A',
      wingName: 'Wing A',
      activeOwner: ResidentSummary(
        id: 'u1',
        name: 'Rahul Mehta',
        email: 'rahul@example.com',
        role: 'OWNER',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminFlatDetailBody(
            flat: occupied,
            history: const AdminOccupancyHistory(
              flatId: 'f1',
              occupancyStatus: 'OWNER_OCCUPIED',
              items: [
                AdminOccupancyHistoryItem(
                  id: 'h1',
                  userId: 'u1',
                  role: 'OWNER',
                  status: 'ACTIVE',
                  startsAt: '2026-01-15T00:00:00.000Z',
                  userName: 'Rahul Mehta',
                  userEmail: 'rahul@example.com',
                ),
              ],
              pagination: api.Page(page: 1, limit: 20, total: 1, totalPages: 1),
            ),
            services: const [
              AdditionalService(
                id: 's1',
                societyId: 's1',
                flatId: 'f1',
                name: 'Covered parking',
                monthlyChargePaise: 150000,
                quantity: 1,
                monthlyTotalPaise: 150000,
                effectiveFrom: '2026-01-01T00:00:00.000Z',
                isActive: true,
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            ],
            bills: const [],
            busy: false,
            tenantActionLabel: 'Add',
            onTenantAction: () {},
            occupancyStepLabel: 'Assign tenant',
            occupancyStepCaption: 'Residential access moves to the tenant',
            occupancyStepIcon: Icons.group_add_outlined,
            onOccupancyStep: () {},
            onAddService: () {},
            onOpenService: (_) {},
            onOpenBill: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Owner'), findsWidgets);
    expect(find.text('Rahul Mehta'), findsWidgets);
    expect(find.text('Assign tenant'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Service 1: Covered parking'), 240);
    await tester.pump();
    expect(find.text('Service 1: Covered parking'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Occupancy history'), 240);
    await tester.pump();
    expect(find.text('No occupancy history yet'), findsNothing);
  });
}
