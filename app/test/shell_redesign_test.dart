import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apna_society/main.dart';
import 'package:apna_society/ui/components.dart';

void main() {
  testWidgets('Login offers each role and keeps the OTP step on the same screen',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const LoginScreen()),
    );
    await tester.pump();

    expect(find.text('Login As'), findsOneWidget);
    expect(find.text('Flat Owner'), findsOneWidget);
    expect(find.text('Flat Tenant'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Security Guard'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);

    await tester.tap(find.text('Security Guard'));
    await tester.pump();

    expect(find.text('Send OTP'), findsOneWidget);
    expect(find.text('Verify & Login'), findsNothing);
  });

  testWidgets('Tool directory lists actions in one surface', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ToolDirectory(
            title: 'Operate',
            links: [
              ToolLink(
                icon: Icons.apartment_outlined,
                label: 'Find a flat',
                subtitle: 'Occupancy and residents',
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Find a flat'), findsOneWidget);
    expect(find.text('Occupancy and residents'), findsOneWidget);
    await tester.tap(find.text('Find a flat'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('Metric band shows compact figures', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: MetricBand(
            items: [
              MetricItem('Active flats', '140'),
              MetricItem('Vacant', '12'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('140'), findsOneWidget);
    expect(find.text('Vacant'), findsOneWidget);
  });

  testWidgets('Review summary and detail hero render hierarchy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                DetailHero(
                  title: 'A-101',
                  subtitle: 'Wing A · Floor 1',
                  badges: [StatusBadge('Owner occupied')],
                ),
                ReviewSummary(
                  title: 'About to create',
                  rows: [
                    ('Role', 'Owner'),
                    ('Name', 'Priya Sharma'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('A-101'), findsOneWidget);
    expect(find.text('ABOUT TO CREATE'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
  });
}
