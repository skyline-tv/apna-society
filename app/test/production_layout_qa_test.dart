import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apna_society/main.dart';
import 'package:apna_society/ui/components.dart';

/// Layout smoke checks at phone widths used in release QA.
/// These are widget tests — not physical-device or emulator runs.
void main() {
  const sizes = <(String, Size)>[
    ('small', Size(320, 568)),
    ('standard', Size(390, 844)),
    ('large', Size(430, 932)),
  ];

  for (final (label, size) in sizes) {
    testWidgets('LoginScreen lays out on $label phone without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(1.0)),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(OverflowBox), findsNothing);
    });

    testWidgets('FormScaffold + sticky CTA on $label with large text',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(1.3),
          ),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: FormScaffold(
              title: 'QA form',
              bottom: PrimaryButton(
                label: 'Continue',
                onPressed: () {},
              ),
              children: [
                const DetailHero(
                  title: 'Wing A · Flat 101',
                  subtitle: 'Owner occupied · 3 BHK · Floor 1',
                  badges: [
                    StatusBadge('Active'),
                    StatusBadge('Owner', tone: BadgeTone.info),
                  ],
                ),
                const SizedBox(height: 16),
                const ReviewSummary(
                  title: 'Review',
                  rows: [
                    ('Period', 'October 2026'),
                    ('Eligible flats', '140'),
                    ('Est. principal', '₹5,88,000'),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
                for (var i = 0; i < 6; i++)
                  ListTile(title: Text('Scroll row $i')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Continue'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Scroll row 5'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AppBottomNav fits five destinations on a narrow width',
      (tester) async {
    const size = Size(320, 640);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: size),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: const Center(child: Text('body')),
            bottomNavigationBar: AppBottomNav(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined), label: 'Home'),
                NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined), label: 'Bills'),
                NavigationDestination(
                    icon: Icon(Icons.groups_outlined), label: 'Visitors'),
                NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined), label: 'More'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Visitors'), findsOneWidget);
  });

  testWidgets('MetricBand and ToolDirectory tolerate narrow width',
      (tester) async {
    const size = Size(320, 700);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: size),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListView(
              padding: Sp.pagePadding,
              children: [
                MetricBand(items: const [
                  MetricItem('Active flats', '140'),
                  MetricItem('Vacant', '12'),
                  MetricItem('Occupied', '91%'),
                  MetricItem('Monthly', '₹5,88,000'),
                ]),
                const SizedBox(height: 16),
                ToolDirectory(
                  title: 'Operate',
                  links: [
                    ToolLink(
                      icon: Icons.apartment_outlined,
                      label: 'Find a flat with a long label that wraps',
                      subtitle: 'Occupancy, residents and rates',
                      onTap: () {},
                    ),
                    ToolLink(
                      icon: Icons.receipt_long_outlined,
                      label: 'Maintenance bills',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
