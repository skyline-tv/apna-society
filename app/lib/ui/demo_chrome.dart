import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/config/demo_environment.dart';
import '../app_core.dart';
import 'components.dart';

/// Overlays a compact [Sample] chip. Does not push the app below a full-width bar.
class DemoModeOverlay extends StatelessWidget {
  const DemoModeOverlay({
    super.key,
    required this.child,
    required this.onOpen,
  });

  final Widget child;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DemoEnvironment.active,
      builder: (context, demo, _) {
        if (!demo) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              top: 0,
              right: 8,
              child: SafeArea(
                bottom: false,
                left: false,
                child: Material(
                  color: C.amberSoft,
                  elevation: 1,
                  shadowColor: C.navy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Rd.pill),
                  child: InkWell(
                    key: const Key('demo-sample-chip'),
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(Rd.pill),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        DemoEnvironment.label,
                        style: TextStyle(
                          color: C.amber,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.2,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showDemoInfoSheet(
  BuildContext context, {
  required Future<void> Function() onLeave,
  void Function(DemoAccount account)? onUseAccount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _DemoInfoSheet(
      onLeave: onLeave,
      onUseAccount: onUseAccount,
    ),
  );
}

Future<void> showContactSkyLineSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _ContactSkyLineSheet(),
  );
}

class _DemoInfoSheet extends StatelessWidget {
  const _DemoInfoSheet({
    required this.onLeave,
    this.onUseAccount,
  });

  final Future<void> Function() onLeave;
  final void Function(DemoAccount account)? onUseAccount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sample society', style: T.title),
          const SizedBox(height: 6),
          const Text(
            'Fictional Maple Grove Residences data for a walkthrough. Payments are simulated. Nothing here is a live society.',
            style: T.secondary,
          ),
          if (onUseAccount != null) ...[
            const SizedBox(height: 14),
            for (final account in DemoEnvironment.accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(account.role, style: T.bodyStrong),
                subtitle: Text(account.username),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () {
                  onUseAccount!(account);
                  Navigator.pop(context);
                },
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'Visitor OTP ${DemoEnvironment.visitorOtp}  ·  Login OTP ${DemoEnvironment.loginOtp}',
            style: T.caption,
          ),
          const SizedBox(height: 16),
          SecondaryButton(
            label: 'Contact us',
            icon: Icons.mail_outline_rounded,
            onPressed: () => showContactSkyLineSheet(context),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await onLeave();
            },
            child: const Text('Leave sample'),
          ),
        ],
      ),
    );
  }
}

class _ContactSkyLineSheet extends StatelessWidget {
  const _ContactSkyLineSheet();

  Future<void> _copy(BuildContext context, String value, String done) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    showSuccessSnack(context, done);
  }

  Future<void> _shareEnquiry(BuildContext context) async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Hi SkyLine Tech Ventures,\n\n'
            'I would like to use Apna Society in our residential society.\n\n'
            'Email: $kSupportEmail\n'
            'Web: $kSupportWebsite\n',
        subject: 'Apna Society — enquiry',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Contact SkyLine', style: T.title),
          const SizedBox(height: 6),
          const Text(
            'Want Apna Society for your society? Write to us and we will get back to you.',
            style: T.secondary,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline_rounded, color: C.blue),
            title: const Text('Email', style: T.caption),
            subtitle: const Text(kSupportEmail, style: T.bodyStrong),
            trailing: IconButton(
              tooltip: 'Copy email',
              onPressed: () =>
                  _copy(context, kSupportEmail, 'Email copied'),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
            onTap: () => _copy(context, kSupportEmail, 'Email copied'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language_rounded, color: C.blue),
            title: const Text('Website', style: T.caption),
            subtitle: const Text(kSupportWebsiteLabel, style: T.bodyStrong),
            trailing: IconButton(
              tooltip: 'Copy website',
              onPressed: () =>
                  _copy(context, kSupportWebsite, 'Website copied'),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
            onTap: () => _copy(context, kSupportWebsite, 'Website copied'),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Share enquiry',
            icon: Icons.send_outlined,
            onPressed: () => _shareEnquiry(context),
          ),
        ],
      ),
    );
  }
}
