import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apna_society/main.dart';
import 'package:apna_society/ui/components.dart';

/// Layout smoke checks at the widths listed in the responsive QA brief.
/// These are widget tests — not physical-device or emulator runs.
void main() {
  const sizes = <(String, Size)>[
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

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget home, {
    double textScale = 1,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          viewInsets: viewInsets,
        ),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  for (final (label, size) in sizes) {
    testWidgets('LoginScreen lays out at $label without overflow',
        (tester) async {
      await pumpAt(tester, size, const LoginScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('FormScaffold + sticky CTA at $label with large text',
        (tester) async {
      await pumpAt(
        tester,
        size,
        FormScaffold(
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
        textScale: 1.3,
      );
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

    testWidgets('Shared cards grids and rows at $label', (tester) async {
      await pumpAt(
        tester,
        size,
        Scaffold(
          body: ListView(
            padding: Sp.pagePadding,
            children: [
              const PineHeader(
                eyebrow: 'Good morning',
                title: 'Admin',
                subtitle: 'Monarch Solitaire',
              ),
              const SizedBox(height: 12),
              const StatGrid(children: [
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
              const SizedBox(height: 16),
              MetricBand(items: const [
                MetricItem('Active flats', '140'),
                MetricItem('Vacant', '12'),
                MetricItem('Occupied', '91%'),
                MetricItem('Monthly', '₹5,88,000'),
              ]),
              const SizedBox(height: 16),
              QuickAccessGrid(items: [
                QuickAccessItem(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Residents',
                  onTap: () {},
                ),
                QuickAccessItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Create bill',
                  onTap: () {},
                ),
                QuickAccessItem(
                  icon: Icons.campaign_outlined,
                  label: 'Notice',
                  onTap: () {},
                ),
                QuickAccessItem(
                  icon: Icons.assessment_outlined,
                  label: 'Reports',
                  onTap: () {},
                ),
              ]),
              const SizedBox(height: 16),
              const DetailCard(
                title: 'Credentials',
                children: [
                  DetailRow('Username', 'ramesh.owner'),
                  DetailRow('Temporary Password', 'Abcd#1234'),
                  DetailRow(
                    'Very long label that should wrap',
                    'A value long enough to wrap on a 320-pixel phone',
                  ),
                ],
              ),
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
                ],
              ),
              const SizedBox(height: 16),
              ScaleToWidth(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'a',
                        label: Text('Owner Occupied'),
                        icon: Icon(Icons.home_outlined)),
                    ButtonSegment(
                        value: 'b',
                        label: Text('Tenant Occupied'),
                        icon: Icon(Icons.person_pin_circle_outlined)),
                  ],
                  selected: const {'a'},
                  onSelectionChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('TOTAL FLATS'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Residents'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Residents'), findsOneWidget);
    });
  }

  testWidgets('AppBottomNav fits five destinations on a narrow width',
      (tester) async {
    const size = Size(320, 640);
    await pumpAt(
      tester,
      size,
      Scaffold(
        body: const Center(child: Text('body')),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined), label: 'Overview'),
            NavigationDestination(
                icon: Icon(Icons.apartment_outlined), label: 'Flats'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined), label: 'Bills'),
            NavigationDestination(
                icon: Icon(Icons.payments_outlined), label: 'Payments'),
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined), label: 'More'),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('confirmDialog fits a 320-wide screen', (tester) async {
    const size = Size(320, 568);
    await pumpAt(
      tester,
      size,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => confirmDialog(
              context,
              title: 'Reject a visitor with a long name?',
              message:
                  'The guard will be told immediately. The visitor stays outside.',
              confirmLabel: 'REJECT',
              cancelLabel: 'Cancel',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('REJECT'), findsOneWidget);
  });

  testWidgets('FormScaffold remains usable with a keyboard inset',
      (tester) async {
    const size = Size(320, 568);
    await pumpAt(
      tester,
      size,
      FormScaffold(
        title: 'New visitor',
        bottom: PrimaryButton(label: 'Send for approval', onPressed: () {}),
        children: [
          TextFormField(
            decoration: const InputDecoration(labelText: 'Visitor name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            decoration: const InputDecoration(labelText: 'Purpose'),
            maxLines: 3,
          ),
        ],
      ),
      viewInsets: const EdgeInsets.only(bottom: 280),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Send for approval'), findsOneWidget);
  });
}
