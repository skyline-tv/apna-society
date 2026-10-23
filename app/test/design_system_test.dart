import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apna_society/ui/components.dart';

void main() {
  testWidgets('OverlapHero keeps header text visible above a tall due card',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: OverlapHero(
              header: PineHeader(
                eyebrow: 'Good evening · Owner',
                title: 'Priya',
                subtitle: 'Monarch Solitaire A to E',
                bottomPadding: 28,
                child: Text('Flat E-303 · Wing E'),
              ),
              hero: SizedBox(
                height: 220,
                child: ColoredBox(
                  color: C.surface,
                  child: Center(child: Text('MAINTENANCE DUE')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Flat E-303 · Wing E'), findsOneWidget);
    expect(find.text('MAINTENANCE DUE'), findsOneWidget);
    final headerTop = tester.getTopLeft(find.text('Priya')).dy;
    final chipTop = tester.getTopLeft(find.text('Flat E-303 · Wing E')).dy;
    final cardTop = tester.getTopLeft(find.text('MAINTENANCE DUE')).dy;
    expect(headerTop, lessThan(chipTop));
    expect(chipTop, lessThan(cardTop));
  });

  testWidgets('PineHeader shows greeting, title and trailing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: PineHeader(
            eyebrow: 'Good morning',
            title: 'Ramesh',
            subtitle: 'Monarch Solitaire',
            trailing: Icon(Icons.notifications_outlined, color: Colors.white),
          ),
        ),
      ),
    );
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('Monarch Solitaire'), findsOneWidget);
  });

  testWidgets('QuickAccessGrid lays out four actions', (tester) async {
    var tapped = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: QuickAccessGrid(items: [
            QuickAccessItem(
              icon: Icons.receipt_long_outlined,
              label: 'Pay bill',
              onTap: () => tapped = 'pay',
            ),
            QuickAccessItem(
              icon: Icons.groups_outlined,
              label: 'Visitors',
              onTap: () => tapped = 'visitors',
            ),
            QuickAccessItem(
              icon: Icons.report_problem_outlined,
              label: 'Complaint',
              onTap: () => tapped = 'complaint',
            ),
            QuickAccessItem(
              icon: Icons.meeting_room_outlined,
              label: 'Facilities',
              onTap: () => tapped = 'facilities',
            ),
          ]),
        ),
      ),
    );
    expect(find.text('Pay bill'), findsOneWidget);
    expect(find.text('Visitors'), findsOneWidget);
    await tester.tap(find.text('Pay bill'));
    await tester.pump();
    expect(tapped, 'pay');
  });

  testWidgets('OtpBoxes accepts six digits', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: OtpBoxes(controller: controller),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(controller.text, '123456');
    expect(find.text('1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('CollectionBar shows labelled progress', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: CollectionBar(
            title: 'Occupancy',
            progress: 0.9,
            valueLabel: '90%',
            caption: '108 occupied',
          ),
        ),
      ),
    );
    expect(find.text('Occupancy'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('108 occupied'), findsOneWidget);
  });

  test('dayGreeting splits the day', () {
    expect(dayGreeting(DateTime(2026, 10, 23, 8)), 'Good morning');
    expect(dayGreeting(DateTime(2026, 10, 23, 14)), 'Good afternoon');
    expect(dayGreeting(DateTime(2026, 10, 23, 20)), 'Good evening');
  });
}
