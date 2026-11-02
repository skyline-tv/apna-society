import 'package:apna_society/api/models/society_models.dart';
import 'package:apna_society/features/admin/admin_dashboard.dart';
import 'package:apna_society/main.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatGrid lays out inside a ListView without unbounded height',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            children: const [
              StatGrid(children: [
                StatCard(
                  title: 'Total flats',
                  value: '140',
                  icon: Icons.apartment_outlined,
                  caption: '5 wings',
                ),
                StatCard(
                  title: 'Occupied',
                  value: '98',
                  icon: Icons.groups_outlined,
                  caption: '42 vacant',
                ),
                StatCard(
                  title: 'This month',
                  value: '₹5,88,000',
                  icon: Icons.payments_outlined,
                  caption: 'Maintenance',
                ),
                StatCard(
                  title: 'Occupancy',
                  value: '70%',
                  icon: Icons.pie_chart_outline_rounded,
                  caption: '140 active',
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('TOTAL FLATS'), findsOneWidget);
    expect(find.text('OCCUPANCY'), findsOneWidget);
    expect(find.text('140'), findsOneWidget);
  });

  testWidgets('AdminHome shows an error state instead of a blank screen',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const AdminHome(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Could not load dashboard'), findsOneWidget);
    expect(find.text('Try again'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
  });

  testWidgets('admin overview matches the dashboard mockup on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: AdminDash.surface,
          body: AdminDashboardOverview(
            society: const SocietySummary(
              id: 's1',
              name: 'Maple Grove Residences',
              code: 'MAPLE_GROVE_DEMO',
              timezone: 'Asia/Kolkata',
              currency: 'INR',
              maintenanceDayOfMonth: 1,
              isActive: true,
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
            dashboard: const DashboardStats(
              totals: DashboardTotals(
                wings: 2,
                flats: 8,
                activeFlats: 8,
                inactiveFlats: 0,
                ownerOccupiedFlats: 3,
                tenantOccupiedFlats: 1,
                vacantFlats: 4,
                twoBhkCount: 6,
                threeBhkCount: 2,
                monthlyMaintenanceTotal: 34000,
              ),
              wings: [
                DashboardWingStats(
                  id: 'w1',
                  code: 'A',
                  name: 'Wing A',
                  flatCount: 4,
                  activeFlats: 4,
                  inactiveFlats: 0,
                  ownerOccupiedFlats: 2,
                  tenantOccupiedFlats: 1,
                  vacantFlats: 1,
                  twoBhkCount: 3,
                  threeBhkCount: 1,
                  monthlyMaintenanceTotal: 17000,
                ),
                DashboardWingStats(
                  id: 'w2',
                  code: 'B',
                  name: 'Wing B',
                  flatCount: 4,
                  activeFlats: 4,
                  inactiveFlats: 0,
                  ownerOccupiedFlats: 1,
                  tenantOccupiedFlats: 0,
                  vacantFlats: 3,
                  twoBhkCount: 3,
                  threeBhkCount: 1,
                  monthlyMaintenanceTotal: 17000,
                ),
              ],
            ),
            onOpenFlats: () {},
            onOpenBills: () {},
            onOpenPayments: () {},
            onOpenResidents: () {},
            onOpenGuards: () {},
            onOpenAnnouncements: () {},
            onOpenCollections: () {},
            onOpenReports: () {},
            onOpenSettings: () {},
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Maple Grove Residences'), findsOneWidget);
    expect(find.text('MAPLE_GROVE_DEMO'), findsOneWidget);
    expect(find.text('Active Hub'), findsOneWidget);
    expect(find.text('Occupancy Health'), findsOneWidget);
    expect(find.text('50%'), findsWidgets);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Create bill'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Operate'), 240);
    await tester.pump();
    expect(find.text('Operate'), findsOneWidget);
    expect(find.text('Find a flat'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Wings Breakdown'), 240);
    await tester.pump();
    expect(find.text('Wings Breakdown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
