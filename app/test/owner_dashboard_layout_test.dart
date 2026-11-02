import 'package:apna_society/api/config/demo_environment.dart';
import 'package:apna_society/app_core.dart';
import 'package:apna_society/features/owner/owner_dashboard.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sizes = <(String, Size)>[
  ('320', Size(320, 568)),
  ('360', Size(360, 640)),
  ('375', Size(375, 667)),
  ('390', Size(390, 844)),
  ('414', Size(414, 896)),
  ('430', Size(430, 932)),
  ('600', Size(600, 960)),
  ('768', Size(768, 1024)),
  ('1024', Size(1024, 768)),
];

Widget _dashboard({bool demoBell = true}) {
  return Scaffold(
    backgroundColor: OwnerDash.surface,
    body: OwnerDashboardOverview(
      greeting: 'Good evening',
      roleLabel: 'Owner',
      firstName: 'Rahul',
      societyName: kSocietyName,
      flatTitle: 'Flat A-101 · Wing A',
      flatSubtitle: 'Floor 1 · Owner occupied',
      showBell: demoBell,
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
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget home, {
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: home,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('owner dashboard matches the resident portal mockup on a phone',
      (tester) async {
    await _pumpAt(tester, const Size(320, 800), _dashboard());
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

  for (final (label, size) in _sizes) {
    testWidgets('owner dashboard lays out at $label without overflow',
        (tester) async {
      await _pumpAt(tester, size, _dashboard());
      expect(tester.takeException(), isNull);
      expect(find.text('Rahul'), findsOneWidget);
      expect(find.text('View bills'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });
  }

  testWidgets('owner dashboard at 320 with large text and sample chip',
      (tester) async {
    DemoEnvironment.active.value = true;
    addTearDown(() => DemoEnvironment.active.value = false);
    await _pumpAt(
      tester,
      const Size(320, 568),
      _dashboard(),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text(DemoEnvironment.label), findsWidgets);
    expect(find.text('View collections'), findsOneWidget);
  });

  testWidgets('owner dashboard five-tab nav fits a 320-wide screen',
      (tester) async {
    await _pumpAt(
      tester,
      const Size(320, 568),
      Scaffold(
        body: const Center(child: Text('body')),
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
              icon: Icons.payments_outlined,
              selectedIcon: Icons.payments_rounded,
              label: 'Payments',
            ),
            OwnerDashNavItem(
              icon: Icons.celebration_outlined,
              selectedIcon: Icons.celebration_rounded,
              label: 'Collections',
            ),
            OwnerDashNavItem(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Collections'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
