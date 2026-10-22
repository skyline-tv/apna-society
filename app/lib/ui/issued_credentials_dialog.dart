import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'components.dart';

/// Why the one-time password is on screen: new account vs admin reset.
enum IssuedCredentialsKind { created, reset }

/// Builds the native share-sheet body from in-memory credentials only.
///
/// Never pass hashes, refresh tokens, or a stored password. Share uses the
/// same plaintext already shown — it must not trigger another generate.
String issuedCredentialsShareMessage({
  required String recipientName,
  required String username,
  required String temporaryPassword,
  IssuedCredentialsKind kind = IssuedCredentialsKind.created,
}) {
  final name = recipientName.trim().isEmpty ? 'there' : recipientName.trim();
  final intro = kind == IssuedCredentialsKind.created
      ? 'Your Apna Society account has been created.'
      : 'A temporary password has been issued for your Apna Society account.';
  return 'Apna Society — Login Credentials\n'
      '\n'
      'Hello $name,\n'
      '\n'
      '$intro\n'
      '\n'
      'Username: $username\n'
      'Temporary Password: $temporaryPassword\n'
      '\n'
      'Please log in using these credentials and change your password after your first login.';
}

String issuedCredentialsDialogTitle(IssuedCredentialsKind kind) {
  return kind == IssuedCredentialsKind.created
      ? 'Credentials Created Successfully'
      : 'Temporary Password Issued';
}

const issuedCredentialsShareSubject = 'Apna Society — Login Credentials';

typedef IssuedCredentialsShareFn = Future<void> Function({
  required String text,
  required String subject,
  Rect? sharePositionOrigin,
});

Future<void> shareIssuedCredentials({
  required String text,
  required String subject,
  Rect? sharePositionOrigin,
}) {
  return SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: subject,
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

/// Modal shown only when a temporary password was just generated.
///
/// Closes with [Done]; the widget (and its plaintext) leave the tree.
Future<void> showIssuedCredentialsDialog(
  BuildContext context, {
  required String recipientName,
  required String username,
  required String temporaryPassword,
  IssuedCredentialsKind kind = IssuedCredentialsKind.created,
  IssuedCredentialsShareFn? share,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => IssuedCredentialsDialog(
      recipientName: recipientName,
      username: username,
      temporaryPassword: temporaryPassword,
      kind: kind,
      share: share ?? shareIssuedCredentials,
    ),
  );
}

class IssuedCredentialsDialog extends StatefulWidget {
  const IssuedCredentialsDialog({
    super.key,
    required this.recipientName,
    required this.username,
    required this.temporaryPassword,
    this.kind = IssuedCredentialsKind.created,
    this.share = shareIssuedCredentials,
  });

  final String recipientName;
  final String username;
  final String temporaryPassword;
  final IssuedCredentialsKind kind;
  final IssuedCredentialsShareFn share;

  @override
  State<IssuedCredentialsDialog> createState() =>
      _IssuedCredentialsDialogState();
}

class _IssuedCredentialsDialogState extends State<IssuedCredentialsDialog> {
  var _sharing = false;

  String get _shareText => issuedCredentialsShareMessage(
        recipientName: widget.recipientName,
        username: widget.username,
        temporaryPassword: widget.temporaryPassword,
        kind: widget.kind,
      );

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await widget.share(
        text: _shareText,
        subject: issuedCredentialsShareSubject,
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      if (mounted) {
        showErrorSnack(context, 'Could not open the share sheet.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copy(String value, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showSuccessSnack(context, successMessage);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(issuedCredentialsDialogTitle(widget.kind)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailRow('Username', widget.username, emphasize: true),
            DetailRow(
              'Temporary Password',
              widget.temporaryPassword,
              emphasize: true,
            ),
            const SizedBox(height: 12),
            const InfoNote(
              'This password is shown only once. Share it securely. '
              'The user must change it after login. It is never stored in '
              'lists or logs.',
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Share Credentials',
              icon: Icons.share_outlined,
              busy: _sharing,
              onPressed: _share,
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Copy Username',
              icon: Icons.copy_outlined,
              onPressed: _sharing
                  ? null
                  : () => _copy(widget.username, 'Username copied.'),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Copy Password',
              icon: Icons.key_outlined,
              onPressed: _sharing
                  ? null
                  : () => _copy(
                        widget.temporaryPassword,
                        'Temporary password copied.',
                      ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sharing ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
