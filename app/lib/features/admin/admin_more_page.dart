import 'package:flutter/material.dart';

import '../../api/models/society_models.dart';
import 'admin_dashboard.dart';

const _kMoreBrand = Color(0xFF153B69);
const _kMoreBrand50 = Color(0xFFF0F5FA);
const _kMoreBrand100 = Color(0xFFE2ECF5);
const _kMoreBrand200 = Color(0xFFC5D9EC);
const _kMoreBorder = Color(0xFFE8EDF5);
const _kMoreMuted = Color(0xFF64748B);

class AdminMoreItem {
  const AdminMoreItem({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.iconBorder,
    this.badge,
    this.badgeBg,
    this.badgeFg,
    this.trailing,
    this.liveDot = false,
  });

  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final Color iconBorder;
  final String? badge;
  final Color? badgeBg;
  final Color? badgeFg;
  final String? trailing;
  final bool liveDot;
}

class AdminMoreSectionData {
  const AdminMoreSectionData({
    required this.title,
    required this.chip,
    required this.chipBg,
    required this.chipFg,
    required this.items,
  });

  final String title;
  final String chip;
  final Color chipBg;
  final Color chipFg;
  final List<AdminMoreItem> items;
}

String adminMoreInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'AS';
  if (parts.length == 1) {
    final word = parts.first;
    return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

String adminMoreLabel(String key) {
  for (final section in adminMoreSections()) {
    for (final item in section.items) {
      if (item.key == key) return item.label;
    }
  }
  return 'More';
}

List<AdminMoreSectionData> adminMoreSections({int? flatCount}) {
  final flatsBadge = flatCount == null ? null : '$flatCount flats';
  return [
    AdminMoreSectionData(
      title: 'People & Community',
      chip: '4 Modules',
      chipBg: _kMoreBrand50,
      chipFg: _kMoreBrand,
      items: [
        AdminMoreItem(
          key: 'residents',
          label: 'Residents',
          subtitle: 'Provision owners and tenants',
          icon: Icons.verified_user_outlined,
          iconBg: const Color(0xFFEFF6FF),
          iconFg: const Color(0xFF1D4F88),
          iconBorder: const Color(0xFFDBEAFE),
          badge: flatsBadge,
        ),
        const AdminMoreItem(
          key: 'guards',
          label: 'Security guards',
          subtitle: 'Provision gate logins & shifts',
          icon: Icons.shield_outlined,
          iconBg: Color(0xFFECFDF5),
          iconFg: Color(0xFF047857),
          iconBorder: Color(0xFFD1FAE5),
        ),
        const AdminMoreItem(
          key: 'visitors',
          label: 'Visitors',
          subtitle: 'Society-wide visitor records',
          icon: Icons.groups_outlined,
          iconBg: Color(0xFFEEF2FF),
          iconFg: Color(0xFF4F46E5),
          iconBorder: Color(0xFFE0E7FF),
        ),
        const AdminMoreItem(
          key: 'vehicles',
          label: 'Vehicles & parking',
          subtitle: 'Assign vehicles & bay slots',
          icon: Icons.directions_car_outlined,
          iconBg: Color(0xFFF0F9FF),
          iconFg: Color(0xFF0369A1),
          iconBorder: Color(0xFFE0F2FE),
        ),
      ],
    ),
    const AdminMoreSectionData(
      title: 'Operations & Billing',
      chip: 'Actions',
      chipBg: Color(0xFFFFFBEB),
      chipFg: Color(0xFFB45309),
      items: [
        AdminMoreItem(
          key: 'announcements',
          label: 'Announcements',
          subtitle: 'Publish notice to all flats',
          icon: Icons.campaign_outlined,
          iconBg: Color(0xFFF5F3FF),
          iconFg: Color(0xFF6D28D9),
          iconBorder: Color(0xFFEDE9FE),
        ),
        AdminMoreItem(
          key: 'collections',
          label: 'One-time collections',
          subtitle: 'Festival, repairs & ad-hoc charges',
          icon: Icons.receipt_long_outlined,
          iconBg: Color(0xFFF0FDFA),
          iconFg: Color(0xFF0F766E),
          iconBorder: Color(0xFFCCFBF1),
        ),
        AdminMoreItem(
          key: 'additional-services',
          label: 'Additional services',
          subtitle: 'Recurring charges on individual flats',
          icon: Icons.layers_outlined,
          iconBg: Color(0xFFFFF7ED),
          iconFg: Color(0xFFC2410C),
          iconBorder: Color(0xFFFFEDD5),
        ),
      ],
    ),
    const AdminMoreSectionData(
      title: 'Governance & Settings',
      chip: 'System',
      chipBg: Color(0xFFF1F5F9),
      chipFg: Color(0xFF475569),
      items: [
        AdminMoreItem(
          key: 'reports',
          label: 'Reports & analytics',
          subtitle: 'Collections, wing trends & defaulters',
          icon: Icons.bar_chart_rounded,
          iconBg: _kMoreBrand50,
          iconFg: _kMoreBrand,
          iconBorder: _kMoreBrand100,
          badge: 'Monthly',
          badgeBg: _kMoreBrand100,
          badgeFg: Color(0xFF0E2847),
        ),
        AdminMoreItem(
          key: 'settings',
          label: 'Society settings',
          subtitle: 'Wings, bank accounts, UPI & rules',
          icon: Icons.settings_outlined,
          iconBg: Color(0xFFF1F5F9),
          iconFg: Color(0xFF334155),
          iconBorder: Color(0xFFE2E8F0),
        ),
      ],
    ),
  ];
}

class AdminMoreHub extends StatelessWidget {
  const AdminMoreHub({
    super.key,
    required this.onOpen,
    required this.onExport,
    required this.onSwitchSociety,
    required this.onSignOut,
    this.society,
    this.dashboard,
    this.onRefresh,
  });

  final SocietySummary? society;
  final DashboardStats? dashboard;
  final ValueChanged<String> onOpen;
  final VoidCallback onExport;
  final VoidCallback onSwitchSociety;
  final VoidCallback onSignOut;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final flatCount = dashboard?.totals.flats;
    final sections = adminMoreSections(flatCount: flatCount);
    final child = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        AdminMoreHero(
          initials: adminMoreInitials(society?.name ?? 'Apna Society'),
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 24),
          AdminMoreSectionCard(
            section: sections[i],
            onOpen: onOpen,
          ),
        ],
        const SizedBox(height: 24),
        AdminMoreExportBanner(
          flatCount: flatCount,
          onExport: onExport,
        ),
        const SizedBox(height: 20),
        AdminMoreFooter(
          societyName: society?.name,
          societyCode: society?.code,
          onSwitchSociety: onSwitchSociety,
          onSignOut: onSignOut,
        ),
      ],
    );
    if (onRefresh == null) return child;
    return RefreshIndicator(
      color: AdminDash.primary,
      onRefresh: onRefresh!,
      child: child,
    );
  }
}

class AdminMoreHero extends StatelessWidget {
  const AdminMoreHero({
    super.key,
    required this.initials,
  });

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Directory',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AdminDash.onSurface,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 8),
                  _SoftBadge(
                    label: 'Hub',
                    bg: _kMoreBrand50,
                    fg: _kMoreBrand,
                    border: Color(0xCCC5D9EC),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'People, operations and governance',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _kMoreMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: const Color(0xFF1E293B),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Society',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdminMoreSectionCard extends StatelessWidget {
  const AdminMoreSectionCard({
    super.key,
    required this.section,
    required this.onOpen,
  });

  final AdminMoreSectionData section;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                section.title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _kMoreMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _SoftBadge(
              label: section.chip,
              bg: section.chipBg,
              fg: section.chipFg,
              pill: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kMoreBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A153B69),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < section.items.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                AdminMoreLinkTile(
                  item: section.items[i],
                  onTap: () => onOpen(section.items[i].key),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class AdminMoreLinkTile extends StatelessWidget {
  const AdminMoreLinkTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  final AdminMoreItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.iconBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: item.iconBorder),
                ),
                child: Icon(item.icon, size: 20, color: item.iconFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.label,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AdminDash.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.liveDot) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        if (item.badge != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: _SoftBadge(
                              label: item.badge!,
                              bg: item.badgeBg ?? const Color(0xFFF1F5F9),
                              fg: item.badgeFg ?? const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kMoreMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (item.trailing != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: Text(
                    item.trailing!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminMoreExportBanner extends StatelessWidget {
  const AdminMoreExportBanner({
    super.key,
    required this.onExport,
    this.flatCount,
  });

  final int? flatCount;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final subtitle = flatCount == null
        ? 'Collections, dues and payment reports'
        : 'Reports for all $flatCount flats';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E2847), _kMoreBrand],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.table_chart_outlined,
                        size: 16, color: Color(0xFFA7F3D0)),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'EXPORT REPORTS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Color(0xFFA7F3D0),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Society data ledger',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xCCE2ECF5),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: FilledButton.icon(
              onPressed: onExport,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _kMoreBrand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text(
                'Export',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminMoreFooter extends StatelessWidget {
  const AdminMoreFooter({
    super.key,
    required this.onSwitchSociety,
    required this.onSignOut,
    this.societyName,
    this.societyCode,
  });

  final String? societyName;
  final String? societyCode;
  final VoidCallback onSwitchSociety;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            TextButton.icon(
              onPressed: onSwitchSociety,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF475569),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: 14),
              label: const Text(
                'Switch Society',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
            TextButton.icon(
              onPressed: onSignOut,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE11D48),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.logout_rounded, size: 14),
              label: const Text(
                'Sign Out Admin',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
        if ((societyName ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [
              societyName!,
              if ((societyCode ?? '').isNotEmpty) societyCode!,
            ].join(' · '),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94A3B8),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const Text(
          'Apna Society · SkyLine Tech',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({
    required this.label,
    required this.bg,
    required this.fg,
    this.border,
    this.pill = false,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color? border;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(pill ? 999 : 6),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
