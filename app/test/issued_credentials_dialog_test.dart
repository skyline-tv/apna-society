import 'dart:io';

import 'package:apna_society/ui/components.dart';
import 'package:apna_society/ui/issued_credentials_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('issuedCredentialsShareMessage', () {
    test('create message includes name, username and password once', () {
      final text = issuedCredentialsShareMessage(
        recipientName: 'Ramesh Patel',
        username: 'ramesh',
        temporaryPassword: 'TempPassw0rd!',
      );
      expect(text, contains('Apna Society — Login Credentials'));
      expect(text, contains('Hello Ramesh Patel,'));
      expect(text, contains('Your Apna Society account has been created.'));
      expect(text, contains('Username: ramesh'));
      expect(text, contains('Temporary Password: TempPassw0rd!'));
      expect(
        text,
        contains(
          'Please log in using these credentials and change your password after your first login.',
        ),
      );
      expect('TempPassw0rd!'.allMatches(text).length, 1);
    });

    test('reset message does not claim the account was created', () {
      final text = issuedCredentialsShareMessage(
        recipientName: 'Guard One',
        username: 'gate1',
        temporaryPassword: 'ResetPass1!',
        kind: IssuedCredentialsKind.reset,
      );
      expect(text, contains('A temporary password has been issued'));
      expect(text.contains('account has been created'), isFalse);
      expect(text, contains('Username: gate1'));
      expect(text, contains('Temporary Password: ResetPass1!'));
    });
  });

  group('IssuedCredentialsDialog', () {
    String? clipboardText;

    void mockClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments;
            if (args is Map) {
              clipboardText = args['text'] as String?;
            }
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboardText};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
    }

    Future<void> openDialog(
      WidgetTester tester, {
      IssuedCredentialsShareFn? share,
      IssuedCredentialsKind kind = IssuedCredentialsKind.created,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showIssuedCredentialsDialog(
                  context,
                  recipientName: 'Anita Shah',
                  username: 'anita',
                  temporaryPassword: 'OnceOnly9!',
                  kind: kind,
                  share: share ??
                      ({
                        required text,
                        required subject,
                        sharePositionOrigin,
                      }) async {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows credentials and share, copy, done actions',
        (tester) async {
      await openDialog(tester);
      expect(find.text('Credentials Created Successfully'), findsOneWidget);
      expect(find.text('anita'), findsOneWidget);
      expect(find.text('OnceOnly9!'), findsOneWidget);
      expect(find.text('Share Credentials'), findsOneWidget);
      expect(find.text('Copy Username'), findsOneWidget);
      expect(find.text('Copy Password'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('copy username and password use the clipboard only',
        (tester) async {
      mockClipboard(tester);
      await openDialog(tester);
      await tester.tap(find.text('Copy Username'));
      await tester.pump();
      expect(clipboardText, 'anita');
      await tester.tap(find.text('Copy Password'));
      await tester.pump();
      expect(clipboardText, 'OnceOnly9!');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('share reuses the issued password and does not regenerate',
        (tester) async {
      var shareCalls = 0;
      String? sharedText;
      await openDialog(
        tester,
        share: ({
          required text,
          required subject,
          sharePositionOrigin,
        }) async {
          shareCalls++;
          sharedText = text;
        },
      );
      await tester.tap(find.text('Share Credentials'));
      await tester.pump();
      expect(shareCalls, 1);
      expect(sharedText, contains('Hello Anita Shah,'));
      expect(sharedText, contains('Username: anita'));
      expect(sharedText, contains('Temporary Password: OnceOnly9!'));
      expect(find.text('OnceOnly9!'), findsOneWidget);

      await tester.tap(find.text('Share Credentials'));
      await tester.pump();
      expect(shareCalls, 2);
      expect(sharedText, contains('Temporary Password: OnceOnly9!'));
    });

    testWidgets('Done removes the plaintext from the tree', (tester) async {
      await openDialog(tester);
      expect(find.text('OnceOnly9!'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('OnceOnly9!'), findsNothing);
      expect(find.text('Credentials Created Successfully'), findsNothing);
    });
  });

  test('admin create and reset flows share in-memory credentials', () {
    for (final path in [
      'lib/features/residents/admin_residents_module.dart',
      'lib/features/guards/admin_guards_module.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('showIssuedCredentialsDialog'), isTrue, reason: path);
      expect(src.contains('I saved it'), isFalse, reason: path);
      expect(
        src.contains('IssuedCredentialsKind.reset'),
        isTrue,
        reason: path,
      );
    }
    final dialog =
        File('lib/ui/issued_credentials_dialog.dart').readAsStringSync();
    expect(dialog.contains('setPassword'), isFalse);
    expect(dialog.contains('.provision('), isFalse);
    expect(dialog.contains('passwordHash'), isFalse);
    expect(dialog.contains('refreshToken'), isFalse);
  });
}
