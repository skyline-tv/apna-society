import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth/auth_session.dart';
import '../../api/config/api_config.dart';
import '../../api/config/demo_environment.dart';
import '../../ui/components.dart';
import '../../ui/demo_chrome.dart';

const kSelectSocietyRoute = '/select-society';
const kLoginRoute = '/login';

/// Shared canvas for society pick and sign-in so the two steps feel like one flow.
const kAuthCanvas = Color(0xFFF8F7FB);
const kAuthSubtle = Color(0xFFF1F4F9);

enum SocietyKind {
  live,
  demo,
}

extension SocietyKindX on SocietyKind {
  bool get isDemo => this == SocietyKind.demo;

  String get title => switch (this) {
        SocietyKind.live => 'Monarch Solitaire (A to E)',
        SocietyKind.demo => 'Demo Society',
      };

  String get subtitle => switch (this) {
        SocietyKind.live => 'Live Society Database',
        SocietyKind.demo => 'Sample walkthrough & simulated data',
      };

  String get proceedHint => switch (this) {
        SocietyKind.live => 'Step 2 next',
        SocietyKind.demo => 'Demo ready',
      };
}

SocietyKind societyKindFromRouteArgs(Object? args) =>
    args is SocietyKind ? args : SocietyKind.live;

Route<void> unsignedInRoute() => MaterialPageRoute<void>(
      builder: (_) => const SocietySelectionScreen(),
    );

/// Compact step pill + optional circular back, shared by society pick and sign-in.
class AuthStepBar extends StatelessWidget {
  const AuthStepBar({
    super.key,
    required this.label,
    this.onBack,
  });

  final String label;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kAuthSubtle,
                borderRadius: BorderRadius.circular(Rd.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: C.softBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.caption.copyWith(
                        color: C.blue,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onBack != null) ...[
          const SizedBox(width: 12),
          Material(
            color: kAuthSubtle,
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('auth-step-back'),
              customBorder: const CircleBorder(),
              onTap: onBack,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.arrow_back_rounded, size: 20, color: C.blue),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class SocietySelectionScreen extends StatefulWidget {
  const SocietySelectionScreen({super.key});

  @override
  State<SocietySelectionScreen> createState() => _SocietySelectionScreenState();
}

class _SocietySelectionScreenState extends State<SocietySelectionScreen> {
  SocietyKind selected = SocietyKind.live;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (DemoEnvironment.active.value) {
      selected = SocietyKind.demo;
    }
  }

  Future<void> _applyEnvironment(SocietyKind kind) async {
    if (kind.isDemo) {
      await DemoEnvironment.persist(true);
      replaceAuthSession(config: DemoEnvironment.config());
      return;
    }
    await DemoEnvironment.persist(false);
    replaceAuthSession(config: ApiConfig.fromEnvironment());
  }

  Future<void> _proceed() async {
    if (busy) return;
    setState(() {
      error = null;
      busy = true;
    });
    try {
      await _applyEnvironment(selected);
      if (!mounted) return;
      setState(() => busy = false);
      await Navigator.of(context).pushNamed(
        kLoginRoute,
        arguments: selected,
      );
      if (!mounted) return;
      // Successful sign-in removes this route with an authenticated session.
      // Do not swap back to the live API in that case — it wiped demo logins.
      if (authSession?.isAuthenticated == true) return;
      if (DemoEnvironment.active.value) {
        await DemoEnvironment.persist(false);
        replaceAuthSession(config: ApiConfig.fromEnvironment());
      }
    } catch (e) {
      await DemoEnvironment.persist(false);
      replaceAuthSession(config: ApiConfig.fromEnvironment());
      if (!mounted) return;
      setState(() {
        error = 'Could not open that society. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _select(SocietyKind kind) {
    if (busy) return;
    setState(() {
      selected = kind;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: kAuthCanvas,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                // Padding lives inside the min-height box so two society
                // cards fit the viewport. Padding on the scroll view itself
                // made the page always taller than the screen.
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthStepBar(
                            label: 'Step 1 of 2 • Select Society',
                            onBack: canPop
                                ? () => Navigator.of(context).maybePop()
                                : null,
                          ),
                          const SizedBox(height: 16),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: _HeroMark(),
                          ),
                          const SizedBox(height: 16),
                          const Text('Select Society', style: T.h1),
                          const SizedBox(height: 6),
                          Text(
                            'Choose your society to proceed to sign in.',
                            style: T.body.copyWith(
                              color: C.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            container: true,
                            explicitChildNodes: true,
                            child: Column(
                              children: [
                                _SocietyOptionCard(
                                  kind: SocietyKind.live,
                                  selected: selected == SocietyKind.live,
                                  enabled: !busy,
                                  onTap: () => _select(SocietyKind.live),
                                ),
                                const SizedBox(height: 12),
                                _SocietyOptionCard(
                                  kind: SocietyKind.demo,
                                  selected: selected == SocietyKind.demo,
                                  enabled: !busy,
                                  onTap: () => _select(SocietyKind.demo),
                                ),
                              ],
                            ),
                          ),
                          InlineError(error),
                          const Spacer(),
                          const SizedBox(height: 16),
                          _SelectedBanner(kind: selected),
                          const SizedBox(height: 12),
                          _ProceedButton(
                            busy: busy,
                            societyName: selected.title,
                            onPressed: _proceed,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => showContactSkyLineSheet(context),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: C.blue,
                                disabledBackgroundColor: Colors.white,
                                elevation: 1,
                                shadowColor: C.navy.withValues(alpha: 0.12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(Rd.lg),
                                ),
                              ),
                              icon: const Icon(Icons.support_agent_rounded,
                                  size: 18),
                              label: const Text('Contact Us'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Powered by SkyLine Tech Ventures',
                            textAlign: TextAlign.center,
                            style: T.caption.copyWith(
                              color: C.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroMark extends StatelessWidget {
  const _HeroMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: C.blue,
        borderRadius: BorderRadius.circular(Rd.xl),
        boxShadow: [
          BoxShadow(
            color: C.blue.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 28),
    );
  }
}

class _SocietyOptionCard extends StatelessWidget {
  const _SocietyOptionCard({
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SocietyKind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = kind == SocietyKind.live;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: kind.title,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Rd.xl),
          border: Border.all(
            color: selected ? C.blue : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: C.navy.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('society-option-${kind.name}'),
            borderRadius: BorderRadius.circular(Rd.xl),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  IconWell(
                    icon: live
                        ? Icons.apartment_rounded
                        : Icons.science_outlined,
                    color: live ? C.blue : C.softBlue,
                    fill: live ? C.chip : kAuthSubtle,
                    size: 48,
                    iconSize: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: live
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(kind.title, style: T.title),
                              const SizedBox(height: 2),
                              Text(kind.subtitle, style: T.secondary),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(kind.title, style: T.title),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: C.chip,
                                      borderRadius: BorderRadius.circular(Rd.pill),
                                    ),
                                    child: Text(
                                      'Auto-filled',
                                      style: T.caption.copyWith(
                                        color: C.blue,
                                        letterSpacing: 0,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(kind.subtitle, style: T.secondary),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.key_rounded,
                                      size: 14, color: C.softBlue),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Auto-filled demo credentials',
                                      style: T.caption.copyWith(
                                        color: C.softBlue,
                                        letterSpacing: 0,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? C.blue : C.neutralSoft,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: selected ? Colors.white : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedBanner extends StatelessWidget {
  const _SelectedBanner({required this.kind});

  final SocietyKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kAuthSubtle,
        borderRadius: BorderRadius.circular(Rd.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, size: 16, color: C.blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: T.caption.copyWith(
                  color: C.muted,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  const TextSpan(text: 'Selected: '),
                  TextSpan(
                    text: kind.title,
                    style: T.caption.copyWith(
                      color: C.blue,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            kind.proceedHint,
            style: T.secondary.copyWith(
              color: C.softBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProceedButton extends StatelessWidget {
  const _ProceedButton({
    required this.busy,
    required this.societyName,
    required this.onPressed,
  });

  final bool busy;
  final String societyName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        key: const Key('proceed-to-sign-in'),
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: C.blueDark,
          disabledBackgroundColor: C.blueDark.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.lg),
          ),
        ),
        child: busy
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Loading $societyName...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Proceed to Sign In'),
                          TextSpan(
                            text: '  (Step 2)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
      ),
    );
  }
}
