import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/config/demo_environment.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../notifications/live_notifications_module.dart';

/// Tokens for the resident home mockup (navy hero, cool ground, sky-pill nav).
class OwnerDash {
  OwnerDash._();

  static const navy = Color(0xFF153B69);
  static const surface = Color(0xFFF6F8FB);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const labelOnNavy = Color(0xFFBFDBFE);
  static const societyOnNavy = Color(0xE6BFDBFE);
  static const greeting = Color(0xFFCBD5E1);
  static const tileBorder = Color(0xCCE2E8F0);
  static const advisoryFill = Color(0xCCEFF6FF);
  static const advisoryLine = Color(0xFFDBEAFE);
  static const overdueFill = Color(0xFFFFF1F2);
  static const overdueInk = Color(0xFFE11D48);
  static const overdueLine = Color(0xFFFECDD3);
  static const pendingFill = Color(0xFFFFFBEB);
  static const pendingInk = Color(0xFFB45309);
  static const settledFill = Color(0xFFECFDF5);
  static const settledInk = Color(0xFF047857);
  static const sampleFill = Color(0xFFFEF3C7);
  static const sampleInk = Color(0xFF78350F);
  static const skyWell = Color(0xFFE0F2FE);
  static const amberWell = Color(0xFFFFFBEB);
  static const amberIcon = Color(0xFFB45309);
  static const indigoWell = Color(0xFFEEF2FF);
  static const indigoIcon = Color(0xFF4338CA);
  static const tealWell = Color(0xFFF0FDFA);
  static const tealIcon = Color(0xFF0F766E);
  static const navActiveWell = Color(0xFFE0F2FE);
  static const navIdle = Color(0xFF94A3B8);
  static const contentMax = 840.0;

  static Size sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static double textScaleOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1);

  static bool isCompact(BuildContext context) {
    final size = sizeOf(context);
    return size.width < 360 || size.shortestSide < 360 || textScaleOf(context) > 1.2;
  }

  static bool isWide(BuildContext context) => sizeOf(context).width >= 720;

  static EdgeInsets pageInsets(BuildContext context) {
    final width = sizeOf(context).width;
    if (width < 360) return const EdgeInsets.fromLTRB(12, 12, 12, 28);
    if (width < 600) return const EdgeInsets.fromLTRB(16, 16, 16, 32);
    return const EdgeInsets.fromLTRB(24, 20, 24, 40);
  }

  static EdgeInsets headerInsets(BuildContext context) {
    final size = sizeOf(context);
    final bottom = size.shortestSide < 500 ? 16.0 : 24.0;
    if (size.width < 360) return EdgeInsets.fromLTRB(16, 6, 16, bottom);
    if (size.width < 600) return EdgeInsets.fromLTRB(20, 8, 20, bottom);
    return EdgeInsets.fromLTRB(24, 10, 24, bottom);
  }

  static double headerRadius(BuildContext context) =>
      sizeOf(context).width < 360 ? 24 : 32;

  static int quickColumns(BuildContext context, int count) {
    if (count <= 1) return 1;
    final width = sizeOf(context).width;
    final scale = textScaleOf(context);
    if (width >= 720 && scale <= 1.2) return 4;
    if (width < 360 || scale > 1.2) return 2;
    return 4;
  }
}

class OwnerDashQuickItem {
  const OwnerDashQuickItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconColor,
    required this.wellColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;
  final Color wellColor;
}

class OwnerDashNavItem {
  const OwnerDashNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class OwnerDashboardOverview extends StatelessWidget {
  const OwnerDashboardOverview({
    super.key,
    required this.greeting,
    required this.roleLabel,
    required this.firstName,
    required this.societyName,
    required this.flatTitle,
    required this.flatSubtitle,
    required this.showBell,
    required this.quickItems,
    required this.onRefresh,
    this.maintenanceCard,
    this.collectionsCard,
    this.fallbackCard,
    this.showOfflineNotice = false,
    this.below = const [],
  });

  final String greeting;
  final String roleLabel;
  final String firstName;
  final String societyName;
  final String flatTitle;
  final String flatSubtitle;
  final bool showBell;
  final List<OwnerDashQuickItem> quickItems;
  final Future<void> Function() onRefresh;
  final Widget? maintenanceCard;
  final Widget? collectionsCard;
  final Widget? fallbackCard;
  final bool showOfflineNotice;
  final List<Widget> below;

  @override
  Widget build(BuildContext context) {
    final insets = OwnerDash.pageInsets(context);
    return ColoredBox(
      color: OwnerDash.surface,
      child: RefreshIndicator(
        color: OwnerDash.navy,
        onRefresh: onRefresh,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            OwnerDashHeader(
              greeting: greeting,
              roleLabel: roleLabel,
              firstName: firstName,
              societyName: societyName,
              flatTitle: flatTitle,
              flatSubtitle: flatSubtitle,
              showBell: showBell,
            ),
            ConstrainedContent(
              maxWidth: OwnerDash.contentMax,
              child: Padding(
                padding: insets,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heroCards(context),
                    if (showOfflineNotice) ...[
                      const OwnerDashAdvisory(kOfficePaymentMessage),
                      const SizedBox(height: 16),
                    ],
                    ...below,
                    if (quickItems.isNotEmpty)
                      OwnerDashQuickAccess(items: quickItems),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCards(BuildContext context) {
    final maintenance = maintenanceCard;
    final collections = collectionsCard;
    final fallback = fallbackCard;
    if (OwnerDash.isWide(context) &&
        maintenance != null &&
        collections != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: maintenance),
              const SizedBox(width: 16),
              Expanded(child: collections),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (maintenance != null) ...[
          maintenance,
          const SizedBox(height: 16),
        ],
        if (collections != null) ...[
          collections,
          const SizedBox(height: 16),
        ],
        if (fallback != null) ...[
          fallback,
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class OwnerDashHeader extends StatelessWidget {
  const OwnerDashHeader({
    super.key,
    required this.greeting,
    required this.roleLabel,
    required this.firstName,
    required this.societyName,
    required this.flatTitle,
    required this.flatSubtitle,
    required this.showBell,
  });

  final String greeting;
  final String roleLabel;
  final String firstName;
  final String societyName;
  final String flatTitle;
  final String flatSubtitle;
  final bool showBell;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Material(
        color: OwnerDash.navy,
        elevation: 8,
        shadowColor: const Color(0x40153B69),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(OwnerDash.headerRadius(context)),
        ),
        child: SafeArea(
          bottom: false,
          child: ConstrainedContent(
            maxWidth: OwnerDash.contentMax,
            child: Padding(
              padding: OwnerDash.headerInsets(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${greeting.toUpperCase()} · ${roleLabel.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: OwnerDash.isCompact(context) ? 10 : 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.4,
                                color: OwnerDash.greeting,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              firstName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: OwnerDash.isCompact(context) ? 22 : 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.15,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              societyName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: OwnerDash.societyOnNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<bool>(
                        valueListenable: DemoEnvironment.active,
                        builder: (context, demo, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (demo) ...[
                                const OwnerDashSampleChip(),
                                const SizedBox(width: 8),
                              ],
                              if (showBell)
                                const LiveNotificationBellButton(onPine: true),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: OwnerDash.isCompact(context) ? 14 : 20),
                  Container(
                    padding: EdgeInsets.all(OwnerDash.isCompact(context) ? 12 : 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: OwnerDash.isCompact(context) ? 36 : 40,
                          height: OwnerDash.isCompact(context) ? 36 : 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.apartment_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                flatTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                flatSubtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

class OwnerDashSampleChip extends StatelessWidget {
  const OwnerDashSampleChip({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = OwnerDash.isCompact(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 4),
      decoration: BoxDecoration(
        color: OwnerDash.sampleFill,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        DemoEnvironment.label,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: OwnerDash.sampleInk,
        ),
      ),
    );
  }
}

class OwnerDashAmountCard extends StatelessWidget {
  const OwnerDashAmountCard({
    super.key,
    required this.label,
    required this.amount,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.badge,
    this.badgeTone = BadgeTone.danger,
    this.loading = false,
  });

  final String label;
  final String amount;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final String? badge;
  final BadgeTone badgeTone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final compact = OwnerDash.isCompact(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: OwnerDash.navy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x331E293B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14153B69),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: OwnerDash.labelOnNavy,
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else if (badge != null)
                OwnerDashStatusChip(label: badge!, tone: badgeTone),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: compact ? 26 : 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.05,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: OwnerDash.labelOnNavy,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: OwnerDash.navy,
                disabledBackgroundColor: Colors.white,
                elevation: 0,
                minimumSize: Size.fromHeight(compact ? 44 : 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(actionIcon, size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      actionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerDashStatusChip extends StatelessWidget {
  const OwnerDashStatusChip({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, line) = switch (tone) {
      BadgeTone.danger => (
          OwnerDash.overdueFill,
          OwnerDash.overdueInk,
          OwnerDash.overdueLine,
        ),
      BadgeTone.warning => (
          OwnerDash.pendingFill,
          OwnerDash.pendingInk,
          const Color(0xFFFDE68A),
        ),
      BadgeTone.success => (
          OwnerDash.settledFill,
          OwnerDash.settledInk,
          const Color(0xFFA7F3D0),
        ),
      _ => (
          Colors.white.withValues(alpha: 0.12),
          Colors.white,
          Colors.white.withValues(alpha: 0.2),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: line),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class OwnerDashAdvisory extends StatelessWidget {
  const OwnerDashAdvisory(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final compact = OwnerDash.isCompact(context);
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: OwnerDash.advisoryFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OwnerDash.advisoryLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: OwnerDash.navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerDashQuickAccess extends StatelessWidget {
  const OwnerDashQuickAccess({super.key, required this.items});

  final List<OwnerDashQuickItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Text(
            'Quick access',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: OwnerDash.ink,
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final columns = OwnerDash.quickColumns(context, items.length);
            final gap = OwnerDash.isCompact(context) ? 8.0 : 10.0;
            final rows = <Widget>[];
            for (var i = 0; i < items.length; i += columns) {
              final end =
                  i + columns > items.length ? items.length : i + columns;
              final slice = items.sublist(i, end);
              rows.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) SizedBox(width: gap),
                      Expanded(
                        child: j < slice.length
                            ? _QuickTile(item: slice[j])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              );
              if (end < items.length) rows.add(SizedBox(height: gap));
            }
            return Column(children: rows);
          },
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.item});

  final OwnerDashQuickItem item;

  @override
  Widget build(BuildContext context) {
    final compact = OwnerDash.isCompact(context);
    final well = compact ? 40.0 : 44.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.fromLTRB(6, compact ? 10 : 14, 6, compact ? 10 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OwnerDash.tileBorder),
          ),
          child: Column(
            children: [
              Container(
                width: well,
                height: well,
                decoration: BoxDecoration(
                  color: item.wellColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.iconColor, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OwnerDashBottomNav extends StatelessWidget {
  const OwnerDashBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<OwnerDashNavItem> items;

  @override
  Widget build(BuildContext context) {
    final compact = OwnerDash.isCompact(context) || items.length >= 5;
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: Color(0xCCE2E8F0)),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(compact ? 4 : 8, 6, compact ? 4 : 8, 6),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavHit(
                        item: items[i],
                        selected: selectedIndex == i,
                        compact: compact,
                        onTap: () => onDestinationSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavHit extends StatelessWidget {
  const _NavHit({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final OwnerDashNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = selected ? OwnerDash.navy : OwnerDash.navIdle;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                horizontal: selected ? (compact ? 8 : 16) : 4,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: selected ? OwnerDash.navActiveWell : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 20,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? OwnerDash.navy : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
