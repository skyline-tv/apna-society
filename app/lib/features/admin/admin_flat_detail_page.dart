import 'package:flutter/material.dart';

import '../../api/models/admin_user_models.dart';
import '../../api/models/billing_models.dart';
import '../../api/models/resident_home_context.dart';
import '../../api/models/society_models.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../residents/admin_residents_module.dart';
import 'admin_dashboard.dart';
import 'admin_flats_page.dart';

const _kNavy = Color(0xFF153B69);
const _kBadgeBlue = Color(0xFFDBE7F5);
const _kBorder = Color(0xFFE2E8F0);
const _kMuted = Color(0xFF64748B);
const _kAmberBg = Color(0xFFFFFBEB);
const _kAmberFg = Color(0xFF92400E);
const _kAmberBorder = Color(0xFFFDE68A);
const _kEmeraldBg = Color(0xFFECFDF5);
const _kEmeraldFg = Color(0xFF047857);
const _kEmeraldBorder = Color(0xFFA7F3D0);
const _kSlateBg = Color(0xFFF1F5F9);
const _kSlateFg = Color(0xFF334155);

String adminFlatParkingLabel(FlatParking? parking) {
  if (parking == null || !parking.hasParking) return 'No parking';
  final slot = parking.slotLabel?.trim();
  if (slot == null || slot.isEmpty) return 'Allocated';
  return 'Slot $slot';
}

class AdminFlatIdentity extends StatelessWidget {
  const AdminFlatIdentity({super.key, required this.flat});

  final FlatSummary flat;

  @override
  Widget build(BuildContext context) {
    final vacant = flat.occupancyStatus.toUpperCase() == 'VACANT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _kBadgeBlue,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x99BFDBFE)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  unitNumber(flat),
                  style: const TextStyle(
                    color: _kNavy,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    flat.label,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AdminDash.onSurface,
                      letterSpacing: -0.4,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${flat.wingName ?? (flat.wingCode == null ? 'Wing' : 'Wing ${flat.wingCode}')} · Floor ${flat.floor} · ${flatTypeLabel(flat.flatType)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _kMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              label: occupancyChipLabel(flat.occupancyStatus),
              bg: vacant ? _kAmberBg : AdminDash.container,
              fg: vacant ? _kAmberFg : AdminDash.primary,
              border: vacant ? _kAmberBorder : AdminDash.outlineVariant,
            ),
            _StatusChip(
              label: flat.isActive ? 'Active' : 'Inactive',
              bg: flat.isActive ? _kEmeraldBg : _kSlateBg,
              fg: flat.isActive ? _kEmeraldFg : _kSlateFg,
              border: flat.isActive ? _kEmeraldBorder : _kBorder,
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
    required this.bg,
    required this.fg,
    required this.border,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class AdminFlatOverviewCard extends StatelessWidget {
  const AdminFlatOverviewCard({super.key, required this.flat});

  final FlatSummary flat;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FLAT OVERVIEW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          _SpecRow(
            label: 'Monthly maintenance',
            value: money(flat.maintenanceRate),
            emphasize: true,
          ),
          const Divider(height: 28, color: Color(0xFFF1F5F9)),
          _SpecRow(label: 'Type', value: flatTypeLabel(flat.flatType)),
          const Divider(height: 28, color: Color(0xFFF1F5F9)),
          _SpecRow(label: 'Floor', value: '${flat.floor}'),
          const Divider(height: 28, color: Color(0xFFF1F5F9)),
          _SpecRow(
            label: 'Parking',
            value: adminFlatParkingLabel(flat.parking),
            muted: adminFlatParkingLabel(flat.parking) == 'No parking',
          ),
          if ((flat.notes ?? '').trim().isNotEmpty) ...[
            const Divider(height: 28, color: Color(0xFFF1F5F9)),
            _SpecRow(label: 'Notes', value: flat.notes!.trim()),
          ],
        ],
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _kMuted,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasize ? 16 : 14,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: muted ? _kMuted : AdminDash.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class AdminFlatResidentCard extends StatelessWidget {
  const AdminFlatResidentCard({
    super.key,
    required this.role,
    required this.icon,
    required this.emptyText,
    this.resident,
    this.actionLabel,
    this.onAction,
  });

  final String role;
  final IconData icon;
  final String emptyText;
  final ResidentSummary? resident;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final person = resident;
    return _WhiteCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kSlateBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: person == null
                ? Icon(icon, size: 20, color: const Color(0xFF475569))
                : Center(
                    child: Text(
                      initialsOf(person.name),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _kNavy,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                Text(
                  person == null ? emptyText : person.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (person != null && person.displayContact.isNotEmpty)
                  Text(
                    person.displayContact,
                    style: const TextStyle(fontSize: 12, color: _kMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: onAction == null
                    ? const Color(0xFF94A3B8)
                    : _kNavy,
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            )
          else if (person == null)
            const Text(
              '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminFlatOccupancyStep extends StatelessWidget {
  const AdminFlatOccupancyStep({
    super.key,
    required this.busy,
    this.label,
    this.caption,
    this.icon,
    this.onPressed,
  });

  final bool busy;
  final String? label;
  final String? caption;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Next occupancy step',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AdminDash.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Vacant → owner → tenant → owner → vacant',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _kMuted,
          ),
        ),
        const SizedBox(height: 12),
        if (label == null)
          const _EmptyHint(
            icon: Icons.lock_clock_outlined,
            message: 'No occupancy change is available in this state',
          )
        else
          FilledButton(
            onPressed: busy ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: _kNavy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _kNavy.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(icon ?? Icons.person_add_alt_1_outlined, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (caption != null) ...[
          const SizedBox(height: 8),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
        ],
      ],
    );
  }
}

class AdminFlatRecurringCard extends StatelessWidget {
  const AdminFlatRecurringCard({
    super.key,
    required this.baseMaintenance,
    required this.additionalPaise,
    required this.totalPaise,
  });

  final int baseMaintenance;
  final int additionalPaise;
  final int totalPaise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Billing & services',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AdminDash.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RECURRING MONTHLY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 12),
              _SpecRow(
                label: 'Base maintenance',
                value: money(baseMaintenance),
              ),
              const SizedBox(height: 10),
              _SpecRow(
                label: 'Additional monthly charges',
                value: moneyPaise(additionalPaise),
              ),
              const Divider(height: 24, color: Color(0xFFF1F5F9)),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total recurring',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AdminDash.onSurface,
                      ),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        moneyPaise(totalPaise),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kNavy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdminFlatAddServiceTile extends StatelessWidget {
  const AdminFlatAddServiceTile({
    super.key,
    required this.enabled,
    required this.subtitle,
    required this.onTap,
  });

  final bool enabled;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kSlateBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, size: 20, color: _kSlateFg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add additional service',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? AdminDash.onSurface
                            : AdminDash.outline,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: _kMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminFlatServiceCard extends StatelessWidget {
  const AdminFlatServiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.active,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String amount;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFEFF6FF) : _kSlateBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_parking_outlined,
                  size: 20,
                  color: active ? _kNavy : _kMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminDash.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _kMuted),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$amount/month',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AdminDash.onSurface,
                    ),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminFlatBillCard extends StatelessWidget {
  const AdminFlatBillCard({super.key, required this.bill, required this.onTap});

  final Bill bill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final settled = bill.outstandingPrincipalPaise <= 0 &&
        bill.status.toUpperCase() == 'PAID';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.billNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminDash.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fmtIsoDate(bill.billingPeriodStart)}  •  ${humanizeStatus(bill.status)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: settled ? _kEmeraldFg : _kMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 108),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        moneyPaise(bill.totalAmountPaise),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AdminDash.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: settled ? _kEmeraldBg : AdminDash.container,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        settled
                            ? 'Settled'
                            : 'Due ${moneyPaise(billAmountDuePaise(bill))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: settled ? _kEmeraldFg : AdminDash.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminFlatHistoryCard extends StatelessWidget {
  const AdminFlatHistoryCard({super.key, required this.item});

  final AdminOccupancyHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final active = item.status.toUpperCase() == 'ACTIVE';
    final owner = item.role.toUpperCase() == 'OWNER';
    return _WhiteCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: active ? _kEmeraldBg : _kSlateBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              owner ? Icons.home_outlined : Icons.person_pin_circle_outlined,
              size: 20,
              color: active ? _kEmeraldFg : _kMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.userName ?? item.userId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminDash.onSurface,
                  ),
                ),
                if ((item.userEmail ?? '').isNotEmpty)
                  Text(
                    item.userEmail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _kMuted),
                  ),
                Text(
                  '${occupancyDateLabel(item.startsAt)}${item.endsAt == null ? ' → present' : ' → ${occupancyDateLabel(item.endsAt!)}'}',
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
                if ((item.endReason ?? '').isNotEmpty)
                  Text(
                    'Reason: ${item.endReason}',
                    style: const TextStyle(fontSize: 12, color: _kMuted),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _StatusChip(
                      label: owner ? 'Owner' : 'Tenant',
                      bg: AdminDash.container,
                      fg: _kNavy,
                      border: AdminDash.outlineVariant,
                    ),
                    _StatusChip(
                      label: humanizeStatus(item.status),
                      bg: active ? _kEmeraldBg : _kSlateBg,
                      fg: active ? _kEmeraldFg : _kSlateFg,
                      border: active ? _kEmeraldBorder : _kBorder,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminFlatEmptyHint extends StatelessWidget {
  const AdminFlatEmptyHint({
    super.key,
    required this.message,
    this.mark,
    this.icon,
  });

  final String message;
  final String? mark;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return _EmptyHint(message: message, mark: mark, icon: icon);
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message, this.mark, this.icon});

  final String message;
  final String? mark;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xCCEFF6FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            alignment: Alignment.center,
            child: mark != null
                ? Text(
                    mark!,
                    style: const TextStyle(
                      color: _kNavy,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  )
                : Icon(icon ?? Icons.inbox_outlined, size: 20, color: _kNavy),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _kMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xE6E2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A153B69),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AdminFlatSectionTitle extends StatelessWidget {
  const AdminFlatSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AdminDash.onSurface,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class AdminFlatDetailBody extends StatelessWidget {
  const AdminFlatDetailBody({
    super.key,
    required this.flat,
    required this.history,
    required this.services,
    required this.bills,
    required this.busy,
    this.ownerActionLabel,
    this.onOwnerAction,
    this.tenantActionLabel,
    this.onTenantAction,
    this.occupancyStepLabel,
    this.occupancyStepCaption,
    this.occupancyStepIcon,
    this.onOccupancyStep,
    required this.onAddService,
    required this.onOpenService,
    required this.onOpenBill,
  });

  final FlatSummary flat;
  final AdminOccupancyHistory history;
  final List<AdditionalService> services;
  final List<Bill> bills;
  final bool busy;
  final String? ownerActionLabel;
  final VoidCallback? onOwnerAction;
  final String? tenantActionLabel;
  final VoidCallback? onTenantAction;
  final String? occupancyStepLabel;
  final String? occupancyStepCaption;
  final IconData? occupancyStepIcon;
  final VoidCallback? onOccupancyStep;
  final VoidCallback onAddService;
  final ValueChanged<AdditionalService> onOpenService;
  final ValueChanged<Bill> onOpenBill;

  @override
  Widget build(BuildContext context) {
    final status = flat.occupancyStatus.toUpperCase();
    final extra = services
        .where((s) => s.isActive)
        .fold<int>(0, (sum, s) => sum + s.monthlyTotalPaise);
    final recurringPaise = (flat.maintenanceRate * 100) + extra;
    final activeCount = activeAdditionalServiceCount(services);
    final atCap = !canAddActiveAdditionalService(services);
    final activeServices = services.where((s) => s.isActive).toList();
    final inactiveServices = services.where((s) => !s.isActive).toList();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        AdminFlatIdentity(flat: flat),
        const SizedBox(height: 20),
        AdminFlatOverviewCard(flat: flat),
        const SizedBox(height: 24),
        const AdminFlatSectionTitle('Who lives here'),
        const SizedBox(height: 12),
        AdminFlatResidentCard(
          role: 'Owner',
          icon: Icons.home_outlined,
          emptyText: 'No owner allotted',
          resident: flat.activeOwner,
          actionLabel: ownerActionLabel,
          onAction: onOwnerAction,
        ),
        const SizedBox(height: 12),
        AdminFlatResidentCard(
          role: 'Tenant',
          icon: Icons.person_pin_circle_outlined,
          emptyText: status == 'OWNER_OCCUPIED'
              ? 'Owner occupied · no tenant'
              : 'No active tenant',
          resident: flat.activeTenant,
          actionLabel: tenantActionLabel,
          onAction: onTenantAction,
        ),
        const SizedBox(height: 24),
        AdminFlatOccupancyStep(
          busy: busy,
          label: occupancyStepLabel,
          caption: occupancyStepCaption,
          icon: occupancyStepIcon,
          onPressed: onOccupancyStep,
        ),
        const SizedBox(height: 24),
        AdminFlatRecurringCard(
          baseMaintenance: flat.maintenanceRate,
          additionalPaise: extra,
          totalPaise: recurringPaise,
        ),
        const SizedBox(height: 24),
        AdminFlatSectionTitle(
          'Additional Services — $activeCount/$kMaxActiveAdditionalServicesPerFlat',
        ),
        const SizedBox(height: 12),
        if (atCap) ...[
          const InfoNote(kAdditionalServiceLimitMessage, tone: NoteTone.warning),
          const SizedBox(height: 10),
        ],
        AdminFlatAddServiceTile(
          enabled: !atCap,
          subtitle: atCap
              ? kAdditionalServiceLimitMessage
              : 'Parking or other recurring charges for this flat',
          onTap: onAddService,
        ),
        if (services.isEmpty)
          const AdminFlatEmptyHint(
            message: 'No additional services on this flat',
            mark: 'P',
          )
        else ...[
          const SizedBox(height: 12),
          ...activeServices.asMap().entries.map((entry) {
            final n = entry.key + 1;
            final service = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminFlatServiceCard(
                title: 'Service $n: ${service.name}',
                subtitle: 'Qty ${service.quantity}',
                amount: moneyPaise(service.monthlyTotalPaise),
                active: true,
                onTap: () => onOpenService(service),
              ),
            );
          }),
          ...inactiveServices.map(
            (service) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminFlatServiceCard(
                title: service.name,
                subtitle: 'Inactive · Qty ${service.quantity}',
                amount: moneyPaise(service.monthlyTotalPaise),
                active: false,
                onTap: () => onOpenService(service),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const AdminFlatSectionTitle('Billing history'),
        const SizedBox(height: 12),
        if (bills.isEmpty)
          const AdminFlatEmptyHint(
            message: 'No bills generated for this flat yet',
            icon: Icons.receipt_long_outlined,
          )
        else
          ...bills.map(
            (bill) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminFlatBillCard(
                bill: bill,
                onTap: () => onOpenBill(bill),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const AdminFlatSectionTitle('Occupancy history'),
        if (history.items.isEmpty)
          const AdminFlatEmptyHint(
            message: 'No occupancy history yet',
            icon: Icons.history_rounded,
          )
        else
          ...history.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminFlatHistoryCard(item: item),
            ),
          ),
        ],
      ),
    );
  }
}
