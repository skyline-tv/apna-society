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
}
