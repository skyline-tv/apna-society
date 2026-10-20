import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apna_society/main.dart';
import 'package:apna_society/ui/components.dart';

void main() {
  testWidgets('Login screen shows society branding and tagline',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const LoginScreen(),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Monarch Solitaire'), findsWidgets);
    expect(
        find.textContaining('Simplifying Society Management'), findsOneWidget);
    expect(find.text('Login As'), findsOneWidget);
  });
}
