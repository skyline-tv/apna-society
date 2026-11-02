import 'package:apna_society/app_core.dart';
import 'package:apna_society/features/owner/owner_dashboard.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('owner dashboard matches the resident portal mockup on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: OwnerDash.surface,
          body: OwnerDashboardOverview(
            greeting: 'Good evening',
            roleLabel: 'Owner',
            firstName: 'Rahul',
            societyName: kSocietyName,
            flatTitle: 'Flat A-101 · Wing A',
            flatSubtitle: 'Floor 1 · Owner occupied',
            showBell: true,
            showOfflineNotice: true,
            maintenanceCard: OwnerDashAmountCard(
              label: 'Maintenance due',
              amount: '₹21,546.77',
              subtitle: '4 open bills · 3 overdue · ₹4,000/mo',
              badge: 'Overdue',
              actionLabel: 'View bills',
              actionIcon: Icons.receipt_long_outlined,
              onAction: () {},
            ),
            collectionsCard: OwnerDashAmountCard(
              label: 'One-time collections',
              amount: '₹3,000.00',
              subtitle: '2 open charges · 2 overdue',
              badge: 'Overdue',
              actionLabel: 'View collections',
              actionIcon: Icons.celebration_outlined,
              onAction: () {},
            ),
            quickItems: [
              OwnerDashQuickItem(
                icon: Icons.receipt_long_outlined,
                label: 'Bills',
                iconColor: OwnerDash.navy,
                wellColor: OwnerDash.skyWell,
                onTap: () {},
              ),
              OwnerDashQuickItem(
                icon: Icons.celebration_outlined,
                label: 'Collections',
                iconColor: OwnerDash.amberIcon,
                wellColor: OwnerDash.amberWell,
                onTap: () {},
              ),
              OwnerDashQuickItem(
                icon: Icons.groups_outlined,
                label: 'Visitors',
                iconColor: OwnerDash.indigoIcon,
                wellColor: OwnerDash.indigoWell,
                onTap: () {},
              ),
              OwnerDashQuickItem(
                icon: Icons.directions_car_outlined,
                label: 'Vehicles',
                iconColor: OwnerDash.tealIcon,
                wellColor: OwnerDash.tealWell,
                onTap: () {},
              ),
            ],
            onRefresh: () async {},
          ),
          bottomNavigationBar: OwnerDashBottomNav(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            items: const [
              OwnerDashNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Home',
              ),
              OwnerDashNavItem(
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long_rounded,
                label: 'Bills',
              ),
              OwnerDashNavItem(
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups_rounded,
                label: 'Visitors',
              ),
              OwnerDashNavItem(
                icon: Icons.grid_view_outlined,
                selectedIcon: Icons.grid_view_rounded,
                label: 'More',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('GOOD EVENING · OWNER'), findsOneWidget);
    expect(find.text('Rahul'), findsOneWidget);
    expect(find.text(kSocietyName), findsOneWidget);
    expect(find.text('Flat A-101 · Wing A'), findsOneWidget);
    expect(find.text('Floor 1 · Owner occupied'), findsOneWidget);
    expect(find.text('MAINTENANCE DUE'), findsOneWidget);
    expect(find.text('₹21,546.77'), findsOneWidget);
    expect(find.text('View bills'), findsOneWidget);
    expect(find.text('ONE-TIME COLLECTIONS'), findsOneWidget);
    expect(find.text('View collections'), findsOneWidget);
    expect(find.textContaining('Online payment is not available yet'),
        findsOneWidget);
    expect(find.text('Quick access'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Vehicles'), 240);
    await tester.pump();
    expect(find.text('Vehicles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
