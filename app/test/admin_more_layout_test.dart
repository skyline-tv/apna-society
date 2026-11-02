import 'package:apna_society/api/models/society_models.dart';
import 'package:apna_society/features/admin/admin_more_page.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('society initials use the first letters of the name', () {
    expect(adminMoreInitials('Monarch Solitaire'), 'MS');
    expect(adminMoreInitials('Maple Grove Residences'), 'MG');
    expect(adminMoreLabel('guards'), 'Security guards');
    expect(adminMoreLabel('additional-services'), 'Additional services');
  });

  testWidgets('admin more hub matches the directory mockup on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminMoreHub(
            society: const SocietySummary(
              id: 's1',
              name: 'Monarch Solitaire',
              code: 'MONARCH',
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
              wings: [],
            ),
            onOpen: (_) {},
            onExport: () {},
            onSwitchSociety: () {},
            onSignOut: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Directory'), findsOneWidget);
    expect(find.text('Hub'), findsOneWidget);
    expect(find.text('People & Community'.toUpperCase()), findsOneWidget);
    expect(find.text('Residents'), findsOneWidget);
    expect(find.text('8 flats'), findsOneWidget);
    expect(find.text('Security guards'), findsOneWidget);
    expect(find.text('One-time collections'), findsOneWidget);
    expect(find.text('Additional services'), findsOneWidget);
    expect(find.text('Reports & analytics'), findsOneWidget);
    expect(find.text('Society settings'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Export'), 240);
    await tester.pump();
    expect(find.text('Export'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign Out Admin'), 240);
    await tester.pump();
    expect(find.text('Switch Society'), findsOneWidget);
    expect(find.text('Sign Out Admin'), findsOneWidget);
    expect(find.text('Audit trail & logs'), findsNothing);
  });
}
