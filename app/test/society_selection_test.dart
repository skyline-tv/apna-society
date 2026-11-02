import 'package:apna_society/api/config/demo_environment.dart';
import 'package:apna_society/features/auth/society_selection_screen.dart';
import 'package:apna_society/main.dart';
import 'package:apna_society/ui/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DemoEnvironment.active.value = false;
  });

  tearDown(() {
    DemoEnvironment.active.value = false;
  });

  Future<void> pumpFlow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const SocietySelectionScreen(),
        routes: {
          kLoginRoute: (context) => LoginScreen(
                society: societyKindFromRouteArgs(
                  ModalRoute.of(context)?.settings.arguments,
                ),
              ),
        },
      ),
    );
    await tester.pump();
  }

  testWidgets('footer is on screen and the page does not scroll on a phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpFlow(tester);

    final footer = find.text('Powered by SkyLine Tech Ventures');
    expect(footer, findsOneWidget);
    expect(tester.getRect(footer).bottom, lessThanOrEqualTo(844));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);
  });

  testWidgets('shows live and demo societies with live selected',
      (tester) async {
    await pumpFlow(tester);

    expect(find.text('Step 1 of 2 • Select Society'), findsOneWidget);
    expect(find.text('Select Society'), findsOneWidget);
    expect(find.text('Monarch Solitaire (A to E)'), findsWidgets);
    expect(find.text('Live Society Database'), findsOneWidget);
    expect(find.text('Demo Society'), findsOneWidget);
    expect(find.text('Auto-filled'), findsOneWidget);
    expect(find.text('Sample walkthrough & simulated data'), findsOneWidget);
    expect(find.text('Contact Us'), findsOneWidget);
    expect(find.text('Powered by SkyLine Tech Ventures'), findsOneWidget);
    expect(find.text('Step 2 next'), findsOneWidget);
    expect(find.text('Demo ready'), findsNothing);
  });

  testWidgets('selecting demo updates the selected banner', (tester) async {
    await pumpFlow(tester);

    await tester.tap(find.byKey(const Key('society-option-demo')));
    await tester.pump();

    expect(find.text('Demo ready'), findsOneWidget);
    expect(find.text('Step 2 next'), findsNothing);
    expect(find.textContaining('Selected:'), findsOneWidget);
  });

  testWidgets('proceed on live society opens sign-in for Monarch',
      (tester) async {
    await pumpFlow(tester);

    await tester.tap(find.byKey(const Key('proceed-to-sign-in')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(find.textContaining('Monarch Solitaire'), findsWidgets);
    expect(find.text('Try a sample society'), findsNothing);
  });

  testWidgets('proceed on demo society opens sign-in with filled credentials',
      (tester) async {
    await pumpFlow(tester);

    await tester.tap(find.byKey(const Key('society-option-demo')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('proceed-to-sign-in')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(); // post-frame demo fill

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Demo Society'), findsWidgets);
    expect(find.text('demo_admin'), findsOneWidget);
    expect(find.text('DEMO MODE'), findsOneWidget);
    expect(find.textContaining('Demo Mode:'), findsOneWidget);
    expect(find.text('Sign in to Demo'), findsOneWidget);
    expect(find.text('Admin'), findsWidgets);
    expect(DemoEnvironment.active.value, isTrue);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('login-role-owner')));
    await tester.pump();
    expect(find.text('demo_owner'), findsOneWidget);
  });
}
