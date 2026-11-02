import 'package:flutter/material.dart';

import '../../api/models/resident_home_context.dart';
import '../../api/models/society_models.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import 'admin_dashboard.dart';

String compactRupees(int value) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  if (abs >= 10000000) {
    final n = abs / 10000000;
    final body = n.truncateToDouble() == n ? '${n.toInt()}' : n.toStringAsFixed(1);
    return '$sign₹${body}Cr';
  }
  if (abs >= 100000) {
    final n = abs / 100000;
    final body = n.truncateToDouble() == n ? '${n.toInt()}' : n.toStringAsFixed(1);
    return '$sign₹${body}L';
  }
  if (abs >= 1000) {
    return '$sign₹${(abs / 1000).round()}k';
  }
  return money(value);
}

String occupancyChipLabel(String status) {
  switch (status.toUpperCase()) {
    case 'TENANT_OCCUPIED':
      return 'Tenant';
    case 'VACANT':
      return 'Vacant';
    case 'OWNER_OCCUPIED':
      return 'Owner';
    default:
      return occupancyStatusLabel(status);
  }
}

String unitMark(String? wingCode) {
  final code = (wingCode ?? '').trim();
  if (code.isEmpty) return '?';
  return code.length <= 2 ? code.toUpperCase() : code.substring(0, 1).toUpperCase();
}

String unitNumber(FlatSummary flat) {
  final label = flat.label;
  final i = label.lastIndexOf('-');
  if (i >= 0 && i < label.length - 1) return label.substring(i + 1);
  return flat.number;
}

class AdminFlatsSearchBar extends StatelessWidget {
  const AdminFlatsSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onTune,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onTune;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Material(
          color: AdminDash.containerLowest,
          borderRadius: BorderRadius.circular(16),
          elevation: 0,
          shadowColor: AdminDash.cardShadow,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: AdminDash.cardShadow,
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      color: AdminDash.outline, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      textInputAction: TextInputAction.search,
                      style: AdminDash.bodySm.copyWith(
                        fontSize: 14,
                        height: 20 / 14,
                        color: AdminDash.onSurface,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search flat, resident, or wing...',
                        hintStyle: AdminDash.bodySm.copyWith(
                          color: AdminDash.outline.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (hasText)
                    IconButton(
                      tooltip: 'Clear',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  Material(
                    color: AdminDash.containerLow,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onTune,
                      borderRadius: BorderRadius.circular(12),
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.tune_rounded,
                          size: 20,
                          color: AdminDash.secondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AdminFlatsWingChips extends StatelessWidget {
  const AdminFlatsWingChips({
    super.key,
    required this.wings,
    required this.selectedWingId,
    required this.onSelect,
  });

  final List<WingSummary> wings;
  final String? selectedWingId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _WingChip(
            label: 'All Wings',
            selected: selectedWingId == null,
            onTap: () => onSelect(null),
          ),
          for (final wing in wings) ...[
            const SizedBox(width: 8),
            _WingChip(
              label: '${wing.name} (${wing.flatCount})',
              selected: selectedWingId == wing.id,
              onTap: () => onSelect(wing.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _WingChip extends StatelessWidget {
  const _WingChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AdminDash.primary : AdminDash.containerLow,
      borderRadius: BorderRadius.circular(Rd.pill),
      elevation: selected ? 2 : 0,
      shadowColor: const Color(0x2E00254C),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: AdminDash.labelMd.copyWith(
              color: selected ? AdminDash.onPrimary : AdminDash.onVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminFlatsStatusRow extends StatelessWidget {
  const AdminFlatsStatusRow({
    super.key,
    required this.selected,
    required this.unitCount,
    required this.onSelect,
  });

  final String selected;
  final int unitCount;
  final ValueChanged<String> onSelect;

  static const _filters = [
    ('all', 'All'),
    ('owner', 'Owner'),
    ('tenant', 'Tenant'),
    ('vacant', 'Vacant'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _filters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _StatusChip(
                    label: _filters[i].$2,
                    selected: selected == _filters[i].$1,
                    onTap: () => onSelect(_filters[i].$1),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AdminDash.secondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$unitCount unit${unitCount == 1 ? '' : 's'}',
              style: AdminDash.labelMd.copyWith(color: AdminDash.onVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AdminDash.secondary : AdminDash.containerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            label.toUpperCase(),
            style: AdminDash.labelSm.copyWith(
              color: selected ? AdminDash.onPrimary : AdminDash.onVariant,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminFlatsSummaryStrip extends StatelessWidget {
  const AdminFlatsSummaryStrip({super.key, required this.totals});

  final DashboardTotals totals;

  @override
  Widget build(BuildContext context) {
    final occupied = totals.ownerOccupiedFlats + totals.tenantOccupiedFlats;
    final occRate =
        totals.flats == 0 ? 0 : (occupied * 100 / totals.flats).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminDash.containerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AdminDash.cardShadow,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCell(
              label: 'Occupied',
              value: '$occupied',
              caption: '$occRate% total',
              captionColor: AdminDash.secondary,
              valueColor: AdminDash.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCell(
              label: 'Vacant',
              value: '${totals.vacantFlats}',
              caption: totals.vacantFlats == 0 ? 'None' : 'Ready',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCell(
              label: 'Dues Run',
              value: compactRupees(totals.monthlyMaintenanceTotal),
              caption:
                  '${totals.flats} unit${totals.flats == 1 ? '' : 's'}',
              valueColor: AdminDash.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.caption,
    this.valueColor = AdminDash.onSurface,
    this.captionColor = AdminDash.outline,
  });

  final String label;
  final String value;
  final String caption;
  final Color valueColor;
  final Color captionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AdminDash.containerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: AdminDash.labelSm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AdminDash.headlineSm.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            caption,
            style: AdminDash.labelSm.copyWith(
              color: captionColor,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class AdminFlatUnitCard extends StatelessWidget {
  const AdminFlatUnitCard({
    super.key,
    required this.flat,
    required this.onTap,
  });

  final FlatSummary flat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = flat.occupancyStatus.toUpperCase();
    final tenant = status == 'TENANT_OCCUPIED';
    final vacant = status == 'VACANT';
    final mark = unitMark(flat.wingCode);
    final number = unitNumber(flat);
    final wing = flat.wingName ??
        (flat.wingCode == null ? 'Wing' : 'Wing ${flat.wingCode}');
    final occupant = _occupantLine(flat, vacant: vacant, tenant: tenant);
    final extra = _extraChip(flat, vacant: vacant);

    final Color tileBg;
    final Color markColor;
    final Color numberColor;
    if (vacant) {
      tileBg = AdminDash.container;
      markColor = AdminDash.outline;
      numberColor = AdminDash.onSurface;
    } else if (tenant) {
      tileBg = AdminDash.secondaryFixed.withValues(alpha: 0.5);
      markColor = AdminDash.secondary;
      numberColor = AdminDash.onSecondaryFixed;
    } else {
      tileBg = AdminDash.containerHigh;
      markColor = AdminDash.secondary;
      numberColor = AdminDash.primary;
    }

    return Material(
      color: AdminDash.containerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      mark,
                      style: AdminDash.labelSm.copyWith(
                        color: markColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      number,
                      style: AdminDash.titleMd.copyWith(
                        color: numberColor,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Flat ${flat.label}',
                      style: AdminDash.titleMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _OccupancyPill(status: status),
                    const SizedBox(height: 2),
                    Text(
                      '$wing • Floor ${flat.floor} • ${flatTypeLabel(flat.flatType)}',
                      style: AdminDash.bodySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    occupant,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              money(flat.maintenanceRate),
                              style: AdminDash.headlineSm.copyWith(
                                color: AdminDash.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AdminDash.outline,
                        ),
                      ],
                    ),
                    Text(
                      vacant ? 'base charge' : 'per month',
                      style: AdminDash.labelSm.copyWith(
                        color: AdminDash.outline,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                    if (extra != null) ...[
                      const SizedBox(height: 8),
                      extra,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _occupantLine(
    FlatSummary flat, {
    required bool vacant,
    required bool tenant,
  }) {
    if (tenant && (flat.activeTenant?.name.trim().isNotEmpty ?? false)) {
      return _PersonLine(
        icon: Icons.group_outlined,
        text: flat.activeTenant!.name.trim(),
      );
    }
    if (!vacant && (flat.activeOwner?.name.trim().isNotEmpty ?? false)) {
      return _PersonLine(
        icon: Icons.person_outline,
        text: flat.activeOwner!.name.trim(),
      );
    }
    if (vacant && (flat.activeOwner?.name.trim().isNotEmpty ?? false)) {
      return _PersonLine(
        icon: Icons.badge_outlined,
        text: 'Owner: ${flat.activeOwner!.name.trim()}',
        muted: true,
      );
    }
    return const _PersonLine(
      icon: Icons.vpn_key_outlined,
      text: 'No occupant allotted',
      italic: true,
      muted: true,
    );
  }

  Widget? _extraChip(FlatSummary flat, {required bool vacant}) {
    if (!flat.isActive) {
      return const _MetaChip(label: 'Inactive', muted: true);
    }
    if (vacant) {
      return const _MetaChip(label: '+ Assign', accent: true);
    }
    final parking = flat.parking;
    if (parking != null && parking.hasParking) {
      final slot = parking.slotLabel?.trim();
      return _MetaChip(
        label: (slot != null && slot.isNotEmpty) ? slot : 'Parking',
      );
    }
    return null;
  }
}

class _OccupancyPill extends StatelessWidget {
  const _OccupancyPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tenant = status == 'TENANT_OCCUPIED';
    final vacant = status == 'VACANT';
    final bg = vacant
        ? AdminDash.containerHigh
        : tenant
            ? AdminDash.secondaryFixed
            : AdminDash.container;
    final fg = vacant
        ? AdminDash.onVariant
        : tenant
            ? AdminDash.onSecondaryFixedVariant
            : AdminDash.primary;
    final dot = vacant ? AdminDash.outline : AdminDash.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Rd.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            occupancyChipLabel(status),
            style: AdminDash.labelSm.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonLine extends StatelessWidget {
  const _PersonLine({
    required this.icon,
    required this.text,
    this.muted = false,
    this.italic = false,
  });

  final IconData icon;
  final String text;
  final bool muted;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AdminDash.outline),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (italic ? AdminDash.bodySm : AdminDash.titleMd).copyWith(
              fontSize: italic ? 13 : 13,
              height: 18 / 13,
              fontWeight: italic ? FontWeight.w400 : FontWeight.w600,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              color: muted ? AdminDash.outline : AdminDash.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    this.accent = false,
    this.muted = false,
  });

  final String label;
  final bool accent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? AdminDash.containerHigh : AdminDash.containerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AdminDash.labelSm.copyWith(
          color: muted
              ? AdminDash.onVariant
              : accent
                  ? AdminDash.secondary
                  : AdminDash.secondary,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class AdminFlatsEmpty extends StatelessWidget {
  const AdminFlatsEmpty({super.key, required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AdminDash.containerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AdminDash.containerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.domain_disabled_outlined,
                    color: AdminDash.secondary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('No Flats Found', style: AdminDash.titleMd),
                const SizedBox(height: 4),
                Text(
                  "We couldn't find any unit matching your filter or query.",
                  textAlign: TextAlign.center,
                  style: AdminDash.bodySm,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onReset,
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminDash.container,
                    foregroundColor: AdminDash.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Reset Filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> showAdminFlatsTuneSheet(
  BuildContext context, {
  required String activeFilter,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AdminDash.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('More filters',
                  style: AdminDash.headlineSm.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final item in const [
                ('all', 'All units'),
                ('active', 'Active only'),
                ('inactive', 'Inactive only'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.$2, style: AdminDash.titleMd),
                  trailing: activeFilter == item.$1
                      ? const Icon(Icons.check_rounded, color: AdminDash.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, item.$1),
                ),
            ],
          ),
        ),
      );
    },
  );
}
