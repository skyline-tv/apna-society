import 'dart:io';

import 'package:apna_society/features/guards/admin_guards_module.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hidden frontend modules', () {
    test('Admin and resident shells no longer route to removed modules', () {
      final mainSrc = File('lib/main.dart').readAsStringSync();
      for (final needle in [
        'LiveAdminComplaintsPage',
        'LiveResidentComplaintsPage',
        'LiveAdminFacilitiesPage',
        'LiveAdminFacilityBookingsPage',
        'LiveResidentFacilitiesPage',
        'LiveAdminStaffPage',
        'LiveAdminAttendancePage',
        'LiveAdminShiftsPage',
        "'complaints'",
        "'facilities'",
        "'facility-bookings'",
        "'staff'",
        "'attendance'",
        "'shifts'",
        'Staff directory',
        'Facility bookings',
      ]) {
        expect(mainSrc.contains(needle), isFalse, reason: needle);
      }
      expect(mainSrc.contains('LiveAdminGuardsPage'), isTrue);
      expect(mainSrc.contains('Security guards'), isTrue);
    });

    test('legacy AdminMorePage no longer lists removed modules', () {
      final moreSrc =
          File('lib/features/security/security_module.dart').readAsStringSync();
      for (final needle in [
        "label: 'Complaints'",
        "label: 'Staff HR'",
        "label: 'Attendance'",
        "label: 'Shifts'",
        "label: 'Facilities'",
        "label: 'Facility bookings'",
      ]) {
        expect(moreSrc.contains(needle), isFalse, reason: needle);
      }
      expect(moreSrc.contains("label: 'Security guards'"), isTrue);
    });

    test('notifications do not open complaint or facility screens', () {
      final src =
          File('lib/features/notifications/live_notifications_module.dart')
              .readAsStringSync();
      expect(src.contains('LiveResidentComplaintDetailPage'), isFalse);
      expect(src.contains('LiveResidentBookingDetailPage'), isFalse);
      expect(src.contains('live_complaints_module.dart'), isFalse);
      expect(src.contains('live_facilities_module.dart'), isFalse);
    });

    test('resident vehicles UI is read-only', () {
      final src = File('lib/features/vehicles/live_vehicles_module.dart')
          .readAsStringSync();
      expect(src.contains('LiveRegisterVehiclePage'), isFalse);
      expect(src.contains("label: const Text('Register')"), isFalse);
      expect(src.contains("child: const Text('Deactivate')"), isFalse);
      expect(src.contains('Save changes'), isFalse);
      expect(src.contains('LiveResidentVehiclesPage'), isTrue);
    });

    test('reports UI no longer exposes a Complaints tab', () {
      final src = File('lib/features/reports/live_reports_module.dart')
          .readAsStringSync();
      expect(src.contains("Tab(text: 'Complaints')"), isFalse);
      expect(src.contains('_complaintsTab'), isFalse);
    });
  });

  testWidgets('Add guard form requires name, mobile, email and username',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const LiveAdminGuardFormPage(),
      ),
    );
    await tester.pump();
    expect(find.text('Add security guard'), findsOneWidget);
    expect(find.text('Full name *'), findsOneWidget);
    expect(find.text('Mobile number *'), findsOneWidget);
    expect(find.text('Email *'), findsOneWidget);
    expect(find.text('Username *'), findsOneWidget);

    await tester.tap(find.text('Review & continue'));
    await tester.pump();
    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Mobile number is required.'), findsOneWidget);
    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Username is required.'), findsOneWidget);
  });
}
