import 'package:apna_society/api/config/demo_environment.dart';
import 'package:apna_society/app_core.dart';
import 'package:apna_society/main.dart';
import 'package:apna_society/ui/components.dart';
import 'package:apna_society/ui/demo_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    DemoEnvironment.active.value = false;
  });

  testWidgets('demo overlay is a compact Sample chip, not a full-width bar',
      (tester) async {
    DemoEnvironment.active.value = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DemoModeOverlay(
          onOpen: () {},
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('DEMO MODE — SAMPLE DATA'), findsNothing);
    expect(find.byKey(const Key('demo-sample-chip')), findsOneWidget);
    expect(find.text('Sample'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('monarch login shows live step chrome without sample entry',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const LoginScreen()),
    );
    await tester.pump();

    expect(find.text('Try a sample society'), findsNothing);
    expect(find.text('Contact us'), findsNothing);
    expect(find.text('Explore sample data'), findsNothing);
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Societies'), findsOneWidget);
    expect(find.text('Change Society'), findsOneWidget);
    expect(find.text('Powered by SkyLine Tech Ventures'), findsOneWidget);
    expect(find.textContaining('Sign In'), findsOneWidget);
  });

  testWidgets('contact sheet shows SkyLine email and website', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContactSkyLineSheet(context),
              child: const Text('open-contact'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-contact'));
    await tester.pumpAndSettle();

    expect(find.text('Contact SkyLine'), findsOneWidget);
    expect(find.text(kSupportEmail), findsWidgets);
    expect(find.text(kSupportWebsiteLabel), findsOneWidget);
    expect(find.text('Share enquiry'), findsOneWidget);
  });
}
