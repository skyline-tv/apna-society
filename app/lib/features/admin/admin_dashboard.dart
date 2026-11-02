import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models/society_models.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../notifications/live_notifications_module.dart';

/// Visual tokens for the admin Overview mockup only.
class AdminDash {
  AdminDash._();

  static const surface = Color(0xFFF8F9FC);
  static const onSurface = Color(0xFF131B2E);
  static const onVariant = Color(0xFF43474F);
  static const primary = Color(0xFF00254C);
  static const primaryContainer = Color(0xFF153B69);
  static const onPrimary = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF325F9B);
  static const secondaryFixed = Color(0xFFD5E3FF);
  static const onSecondaryFixed = Color(0xFF001C3B);
  static const onSecondaryFixedVariant = Color(0xFF124782);
  static const container = Color(0xFFEAEDFF);
  static const containerLow = Color(0xFFF2F3FF);
  static const containerLowest = Color(0xFFFFFFFF);
  static const containerHigh = Color(0xFFE2E7FF);
  static const containerHighest = Color(0xFFDAE2FD);
  static const outline = Color(0xFF737780);
  static const outlineVariant = Color(0xFFC3C6D0);
  static const error = Color(0xFFBA1A1A);
  static const hairline = Color(0x66E2E7FF);
  static const cardShadow = Color(0x0D153B69);

  static const labelSm = TextStyle(
    fontSize: 10,
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: onVariant,
  );
  static const labelMd = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.24,
    color: onSurface,
  );
  static const bodySm = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    color: onVariant,
  );
  static const titleMd = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    color: onSurface,
  );
  static const headlineSm = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.09,
    color: onSurface,
  );
  static const headlineMd = TextStyle(
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: onSurface,
  );
  static const headlineLg = TextStyle(
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.36,
    color: onSurface,
  );
  static const displayLg = TextStyle(
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.9,
    color: onSurface,
  );
}

const _kShortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String adminDashMonthLabel([DateTime? now]) {
  final date = now ?? DateTime.now();
  return '${_kShortMonths[date.month - 1]} ${date.year}';
}

class AdminDashHeader extends StatelessWidget {
  const AdminDashHeader({
    super.key,
    required this.societyName,
    this.backLabel,
    this.onBack,
    this.onSocietyTap,
    this.onProfileTap,
  });

  final String societyName;
  final String? backLabel;
  final VoidCallback? onBack;
  final VoidCallback? onSocietyTap;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    final subpage = backLabel != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Material(
        color: AdminDash.surface.withValues(alpha: 0.94),
        elevation: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      if (subpage) ...[
                        _IconHit(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: onBack,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            backLabel!,
                            style: AdminDash.titleMd,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AdminDash.primary,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x2E00254C),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.apartment_rounded,
                            color: AdminDash.onPrimary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Material(
                            color: AdminDash.containerLow,
                            borderRadius: BorderRadius.circular(Rd.pill),
                            child: InkWell(
                              onTap: onSocietyTap,
                              borderRadius: BorderRadius.circular(Rd.pill),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SOCIETY',
                                            style: AdminDash.labelSm.copyWith(
                                              color: AdminDash.primary,
                                            ),
                                          ),
                                          Text(
                                            societyName,
                                            style: AdminDash.titleMd.copyWith(
                                              height: 1.15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.expand_more_rounded,
                                      size: 18,
                                      color: AdminDash.outline,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      const LiveNotificationBellButton(),
                      const SizedBox(width: 4),
                      _ProfileHit(onTap: onProfileTap),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AdminDash.hairline),
          ],
        ),
      ),
    );
  }
}

class _IconHit extends StatelessWidget {
  const _IconHit({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 22, color: AdminDash.onVariant),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _ProfileHit extends StatelessWidget {
  const _ProfileHit({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Account',
      child: Material(
        color: AdminDash.primaryContainer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.person_rounded,
              size: 18,
              color: AdminDash.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDashBottomNav extends StatelessWidget {
  const AdminDashBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _items = <(IconData, String)>[
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.domain_outlined, 'Flats'),
    (Icons.receipt_long_outlined, 'Bills'),
    (Icons.account_balance_wallet_outlined, 'Payments'),
    (Icons.grid_view_outlined, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminDash.surface.withValues(alpha: 0.94),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: AdminDash.hairline),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: _NavItem(
                          icon: _items[i].$1,
                          label: _items[i].$2,
                          selected: selectedIndex == i,
                          onTap: () => onDestinationSelected(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AdminDash.primary : AdminDash.onVariant;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdminDash.labelMd.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminDashboardOverview extends StatelessWidget {
  const AdminDashboardOverview({
    super.key,
    required this.society,
    required this.dashboard,
    required this.onOpenFlats,
    required this.onOpenBills,
    required this.onOpenPayments,
    required this.onOpenResidents,
    required this.onOpenGuards,
    required this.onOpenAnnouncements,
    required this.onOpenCollections,
    required this.onOpenReports,
    required this.onOpenSettings,
    required this.onRefresh,
  });

  final SocietySummary society;
  final DashboardStats dashboard;
  final VoidCallback onOpenFlats;
  final VoidCallback onOpenBills;
  final VoidCallback onOpenPayments;
  final VoidCallback onOpenResidents;
  final VoidCallback onOpenGuards;
  final VoidCallback onOpenAnnouncements;
  final VoidCallback onOpenCollections;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final totals = dashboard.totals;
    final occupied = totals.ownerOccupiedFlats + totals.tenantOccupiedFlats;
    final occRate =
        totals.flats == 0 ? 0 : (occupied * 100 / totals.flats).round();
    return RefreshIndicator(
      color: AdminDash.primary,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _GreetingBlock(
            society: society,
            wings: totals.wings,
            onMonthTap: onOpenBills,
          ),
          const SizedBox(height: 16),
          _MetricGrid(
            flats: totals.flats,
            wings: totals.wings,
            occupied: occupied,
            vacant: totals.vacantFlats,
            monthTotal: totals.monthlyMaintenanceTotal,
            occupancyPercent: occRate,
            activeFlats: totals.activeFlats,
            onOpenFlats: onOpenFlats,
            onOpenBills: onOpenBills,
          ),
          const SizedBox(height: 8),
          _OccupancyHealth(
            totals: totals,
            occupancyPercent: occRate,
          ),
          const SizedBox(height: 16),
          _SectionHead(
            title: 'Quick Actions',
            meta: 'Frequent Tasks',
          ),
          const SizedBox(height: 4),
          _QuickActions(
            onResidents: onOpenResidents,
            onGuards: onOpenGuards,
            onCreateBill: onOpenBills,
            onNotice: onOpenAnnouncements,
          ),
          const SizedBox(height: 16),
          const _SectionHead(title: 'Operate', meta: '7 Modules'),
          const SizedBox(height: 4),
          _OperateCard(
            onFindFlat: onOpenFlats,
            onBills: onOpenBills,
            onPayments: onOpenPayments,
            onCollections: onOpenCollections,
            onGuards: onOpenGuards,
            onAnnouncements: onOpenAnnouncements,
            onReports: onOpenReports,
          ),
          const SizedBox(height: 16),
          _SectionHead(
            title: 'Wings Breakdown',
            actionLabel: 'Society Directory',
            onAction: onOpenSettings,
          ),
          const SizedBox(height: 4),
          _WingsCard(wings: dashboard.wings, onTap: onOpenFlats),
        ],
      ),
    );
  }
}

class _GreetingBlock extends StatelessWidget {
  const _GreetingBlock({
    required this.society,
    required this.wings,
    required this.onMonthTap,
  });

  final SocietySummary society;
  final int wings;
  final VoidCallback onMonthTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AdminDash.secondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${dayGreeting()}, Admin'.toUpperCase(),
                style: AdminDash.labelMd.copyWith(
                  color: AdminDash.onVariant,
                  letterSpacing: 0.6,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Material(
              color: AdminDash.container,
              borderRadius: BorderRadius.circular(Rd.pill),
              child: InkWell(
                onTap: onMonthTap,
                borderRadius: BorderRadius.circular(Rd.pill),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        adminDashMonthLabel(),
                        style: AdminDash.labelSm.copyWith(
                          color: AdminDash.onVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: AdminDash.onVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    society.name,
                    style: AdminDash.headlineLg,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$wings Wing${wings == 1 ? '' : 's'}',
                        style: AdminDash.bodySm.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AdminDash.outlineVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        society.code.toUpperCase(),
                        style: AdminDash.labelSm.copyWith(
                          color: AdminDash.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AdminDash.secondaryFixed,
                borderRadius: BorderRadius.circular(Rd.pill),
              ),
              child: Text(
                society.isActive ? 'Active Hub' : 'Inactive',
                style: AdminDash.labelSm.copyWith(
                  color: AdminDash.onSecondaryFixed,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.flats,
    required this.wings,
    required this.occupied,
    required this.vacant,
    required this.monthTotal,
    required this.occupancyPercent,
    required this.activeFlats,
    required this.onOpenFlats,
    required this.onOpenBills,
  });

  final int flats;
  final int wings;
  final int occupied;
  final int vacant;
  final int monthTotal;
  final int occupancyPercent;
  final int activeFlats;
  final VoidCallback onOpenFlats;
  final VoidCallback onOpenBills;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 8.0;
        final tileW = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: tileW,
              child: _MetricTile(
                label: 'Total Flats',
                value: '$flats',
                caption: '$wings wing${wings == 1 ? '' : 's'} configured',
                icon: Icons.apartment_outlined,
                iconBg: AdminDash.container,
                iconColor: AdminDash.primary,
                onTap: onOpenFlats,
              ),
            ),
            SizedBox(
              width: tileW,
              child: _MetricTile(
                label: 'Occupied',
                value: '$occupied',
                caption: '$vacant flat${vacant == 1 ? '' : 's'} vacant',
                icon: Icons.group_outlined,
                iconBg: AdminDash.secondaryFixed,
                iconColor: AdminDash.onSecondaryFixedVariant,
                onTap: onOpenFlats,
              ),
            ),
            SizedBox(
              width: tileW,
              child: _MetricTile(
                label: 'This Month',
                value: money(monthTotal),
                caption: 'Maintenance dues',
                icon: Icons.payments_outlined,
                iconBg: AdminDash.containerHigh,
                iconColor: AdminDash.primaryContainer,
                valueStyle: AdminDash.headlineMd,
                onTap: onOpenBills,
              ),
            ),
            SizedBox(
              width: tileW,
              child: _MetricTile(
                label: 'Occupancy',
                value: '$occupancyPercent%',
                caption: '$activeFlats active records',
                icon: Icons.donut_large_outlined,
                iconBg: AdminDash.secondaryFixed,
                iconColor: AdminDash.onSecondaryFixed,
                valueStyle: AdminDash.displayLg.copyWith(
                  color: AdminDash.secondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.valueStyle,
    this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final TextStyle? valueStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AdminDash.labelSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: valueStyle ?? AdminDash.displayLg),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: AdminDash.bodySm.copyWith(fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _OccupancyHealth extends StatelessWidget {
  const _OccupancyHealth({
    required this.totals,
    required this.occupancyPercent,
  });

  final DashboardTotals totals;
  final int occupancyPercent;

  @override
  Widget build(BuildContext context) {
    final flats = totals.flats;
    final owner = totals.ownerOccupiedFlats;
    final tenant = totals.tenantOccupiedFlats;
    final vacant = totals.vacantFlats;
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Occupancy Health',
                        style: AdminDash.titleMd,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: AdminDash.container,
                        borderRadius: BorderRadius.circular(Rd.pill),
                      ),
                      child: Text(
                        'LIVE',
                        style: AdminDash.labelSm
                            .copyWith(color: AdminDash.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$occupancyPercent%',
                style: AdminDash.headlineSm.copyWith(
                  color: AdminDash.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SegmentBar(
            owner: owner,
            tenant: tenant,
            vacant: vacant,
            total: flats,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _LegendChip(
                color: AdminDash.primary,
                label: '$owner Owner',
              ),
              _LegendChip(
                color: AdminDash.secondary,
                label: '$tenant Tenant',
              ),
              _LegendChip(
                color: AdminDash.containerHighest,
                label: '$vacant Vacant',
                muted: true,
              ),
              _CountChip(label: '${totals.twoBhkCount} × 2 BHK'),
              _CountChip(label: '${totals.threeBhkCount} × 3 BHK'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.owner,
    required this.tenant,
    required this.vacant,
    required this.total,
  });

  final int owner;
  final int tenant;
  final int vacant;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AdminDash.container,
        borderRadius: BorderRadius.circular(Rd.pill),
        border: Border.all(color: AdminDash.container),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Rd.pill),
        child: total <= 0
            ? const SizedBox.expand()
            : Row(
                children: [
                  if (owner > 0)
                    Flexible(
                      flex: owner,
                      child: Container(color: AdminDash.primary),
                    ),
                  if (tenant > 0)
                    Flexible(
                      flex: tenant,
                      child: Container(color: AdminDash.secondary),
                    ),
                  if (vacant > 0)
                    Flexible(
                      flex: vacant,
                      child: Container(color: AdminDash.containerHighest),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
    this.muted = false,
  });

  final Color color;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AdminDash.container,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AdminDash.labelMd.copyWith(
              color: muted ? AdminDash.onVariant : AdminDash.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AdminDash.containerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AdminDash.labelMd.copyWith(
          color: AdminDash.onVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.title,
    this.meta,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? meta;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AdminDash.headlineSm.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (meta != null)
          Text(
            meta!.toUpperCase(),
            style: AdminDash.labelSm,
          ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AdminDash.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel!,
              style: AdminDash.labelMd.copyWith(
                color: AdminDash.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onResidents,
    required this.onGuards,
    required this.onCreateBill,
    required this.onNotice,
  });

  final VoidCallback onResidents;
  final VoidCallback onGuards;
  final VoidCallback onCreateBill;
  final VoidCallback onNotice;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.person_add_alt_1_outlined, 'Residents', onResidents),
      (Icons.shield_outlined, 'Guards', onGuards),
      (Icons.receipt_outlined, 'Create bill', onCreateBill),
      (Icons.campaign_outlined, 'Notice', onNotice),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: _QuickTile(
              icon: items[i].$1,
              label: items[i].$2,
              onTap: items[i].$3,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AdminDash.container,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AdminDash.primary),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AdminDash.labelMd,
          ),
        ],
      ),
    );
  }
}

class _OperateCard extends StatelessWidget {
  const _OperateCard({
    required this.onFindFlat,
    required this.onBills,
    required this.onPayments,
    required this.onCollections,
    required this.onGuards,
    required this.onAnnouncements,
    required this.onReports,
  });

  final VoidCallback onFindFlat;
  final VoidCallback onBills;
  final VoidCallback onPayments;
  final VoidCallback onCollections;
  final VoidCallback onGuards;
  final VoidCallback onAnnouncements;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String, VoidCallback)>[
      (
        Icons.domain_outlined,
        'Find a flat',
        'Occupancy, residents and rates',
        onFindFlat
      ),
      (
        Icons.request_quote_outlined,
        'Maintenance bills',
        'Generate, adjust and collect',
        onBills
      ),
      (
        Icons.account_balance_wallet_outlined,
        'Payments',
        'Recent collections and receipts',
        onPayments
      ),
      (
        Icons.celebration_outlined,
        'One-time collections',
        'Festival, repair and special charges',
        onCollections
      ),
      (
        Icons.badge_outlined,
        'Security guards',
        'Create and manage gate logins',
        onGuards
      ),
      (
        Icons.volume_up_outlined,
        'Announcements',
        'Publish a notice',
        onAnnouncements
      ),
      (
        Icons.assessment_outlined,
        'Reports',
        'Collections and outstanding dues',
        onReports
      ),
    ];
    return _DashCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AdminDash.hairline,
              ),
            _OperateRow(
              icon: rows[i].$1,
              title: rows[i].$2,
              subtitle: rows[i].$3,
              onTap: rows[i].$4,
            ),
          ],
        ],
      ),
    );
  }
}

class _OperateRow extends StatelessWidget {
  const _OperateRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AdminDash.container,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: AdminDash.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AdminDash.titleMd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: AdminDash.bodySm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AdminDash.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _WingsCard extends StatelessWidget {
  const _WingsCard({required this.wings, required this.onTap});

  final List<DashboardWingStats> wings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (wings.isEmpty) {
      return _DashCard(
        child: Text(
          'No wings configured yet',
          style: AdminDash.bodySm.copyWith(fontWeight: FontWeight.w500),
        ),
      );
    }
    return _DashCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < wings.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AdminDash.hairline,
              ),
            _WingRow(wing: wings[i], index: i, onTap: onTap),
          ],
        ],
      ),
    );
  }
}

class _WingRow extends StatelessWidget {
  const _WingRow({
    required this.wing,
    required this.index,
    required this.onTap,
  });

  final DashboardWingStats wing;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = index.isEven;
    final mark = wing.code.trim().isEmpty
        ? '?'
        : (wing.code.length <= 2
            ? wing.code.toUpperCase()
            : wing.code.substring(0, 1).toUpperCase());
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    primary ? AdminDash.primaryContainer : AdminDash.secondary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (primary
                            ? AdminDash.primaryContainer
                            : AdminDash.secondary)
                        .withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                mark,
                style: AdminDash.headlineSm.copyWith(
                  color: AdminDash.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wing.name,
                    style: AdminDash.titleMd.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${wing.activeFlats} active',
                        style: AdminDash.bodySm.copyWith(
                          color: AdminDash.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AdminDash.outlineVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        '${wing.vacantFlats} vacant',
                        style: AdminDash.bodySm.copyWith(
                          color: AdminDash.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(wing.monthlyMaintenanceTotal),
                  style: AdminDash.titleMd.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'per month',
                  style: AdminDash.labelSm.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashCard extends StatelessWidget {
  const _DashCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: AdminDash.containerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminDash.hairline),
        boxShadow: const [
          BoxShadow(
            color: AdminDash.cardShadow,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: body,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}
