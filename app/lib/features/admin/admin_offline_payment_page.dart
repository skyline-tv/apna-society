import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models/billing_models.dart';
import '../../app_core.dart';
import '../../ui/components.dart';

const kOfflineCream = Color(0xFFF8F6F2);
const kOfflineNavy = Color(0xFF153B69);
const kOfflineNavy600 = Color(0xFF1B4982);
const kOfflineNavy50 = Color(0xFFF0F5FA);
const kOfflineNavy100 = Color(0xFFE1ECF5);
const kOfflineBorder = Color(0xFFE2DBD0);
const kOfflineMuted = Color(0xFF64748B);
const kOfflineInk = Color(0xFF1A1C1E);
const kOfflineAmber = Color(0xFFD97706);
const kOfflineAmberSoft = Color(0xFFFFFBEB);
const kOfflineAmberBorder = Color(0xFFFDE68A);
const kOfflineEmerald = Color(0xFF059669);
const kOfflineEmeraldSoft = Color(0xFFECFDF5);
const kOfflineEmeraldBorder = Color(0xFFA7F3D0);

class AdminOfflineMonthOption {
  const AdminOfflineMonthOption({
    required this.months,
    required this.label,
    required this.amount,
    required this.selected,
  });

  final int months;
  final String label;
  final String amount;
  final bool selected;
}

String adminOfflineMonthOptionLabel({
  required int months,
  required int pending,
}) {
  if (pending > 0 && months == pending) {
    return months == 1
        ? '1 month (Full settlement)'
        : '$months months (Full settlement)';
  }
  if (months == 12) return '12 months (Full year)';
  if (pending > 0 && months > pending) {
    final extra = months - pending;
    return extra == 1
        ? '$months months (1 advance)'
        : '$months months ($extra advances)';
  }
  return months == 1 ? '1 month' : '$months months';
}

String adminOfflineMonthsFieldText(int months) =>
    months == 1 ? '1 month' : '$months months';

String adminOfflineMonthsSelectedBadge(int months) =>
    months == 1 ? '1 month selected' : '$months months selected';

int? parseOfflineMonthsInput(String raw) {
  final trimmed = raw.trim();
  final direct = int.tryParse(trimmed);
  if (direct != null) {
    if (direct < 1 || direct > 12) return null;
    return direct;
  }
  final match = RegExp(r'^(\d{1,2})').firstMatch(trimmed);
  if (match == null) return null;
  final value = int.tryParse(match.group(1)!);
  if (value == null || value < 1 || value > 12) return null;
  return value;
}

bool isCompleteOfflineMonthsInput(String raw) {
  final trimmed = raw.trim();
  if (parseOfflineMonthsInput(trimmed) == null) return false;
  if (RegExp(r'^\d{2}$').hasMatch(trimmed)) return true;
  final single = int.tryParse(trimmed);
  return single != null && single >= 2 && single <= 9;
}

/// Digits only, and only values from 1 through 12.
class OfflineMonthsInputFormatter extends TextInputFormatter {
  const OfflineMonthsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (text.contains(RegExp(r'\D')) || text.length > 2) return oldValue;
    if (text.startsWith('0')) return oldValue;
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 12) return oldValue;
    return newValue;
  }
}

String adminOfflinePaymentDateLabel(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(n.year, n.month, n.day);
  final formatted = fmtDate(day);
  if (day == today) return 'Today, $formatted';
  return formatted;
}

List<AdminOfflineMonthOption> adminOfflineMonthOptions({
  required Bill bill,
  required int selected,
}) {
  final pending = billPendingMonths(bill);
  return [
    for (var months = 1; months <= 12; months++)
      AdminOfflineMonthOption(
        months: months,
        label: adminOfflineMonthOptionLabel(months: months, pending: pending),
        amount: moneyPaise(billEstimateForMonthsPaise(bill, months)),
        selected: months == selected,
      ),
  ];
}

class AdminOfflineBillCard extends StatelessWidget {
  const AdminOfflineBillCard({
    super.key,
    required this.billNumber,
    required this.flatLabel,
    required this.period,
    required this.principal,
    required this.interest,
    required this.monthsLabel,
    required this.amountDue,
  });

  final String billNumber;
  final String flatLabel;
  final String period;
  final String principal;
  final String interest;
  final String monthsLabel;
  final String amountDue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOfflineBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14153B69),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kOfflineNavy, kOfflineNavy600],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'APPLYING TO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            billNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF5F5F4)),
                const SizedBox(height: 4),
                _MetaRow(label: 'Flat Unit', value: flatLabel, bold: true),
                _MetaRow(label: 'Period', value: period),
                _MetaRow(label: 'Outstanding principal', value: principal),
                _MetaRow(label: 'Accrued interest', value: interest),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Months',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: kOfflineAmberSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: kOfflineAmberBorder),
                          ),
                          child: Text(
                            monthsLabel,
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kOfflineAmber,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F6F3),
              border: Border(
                top: BorderSide(color: Color(0xFFE7E5E4)),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'AMOUNT DUE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: Color(0xFF57534E),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amountDue,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: kOfflineNavy,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminOfflineMethodPills extends StatelessWidget {
  const AdminOfflineMethodPills({
    super.key,
    required this.methods,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final List<(String, String)> methods;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'PAYMENT RECEIVED VIA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
            Text(
              'Mode',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < methods.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _MethodPill(
                  label: methods[i].$2,
                  selected: selected == methods[i].$1,
                  onTap: enabled ? () => onSelected(methods[i].$1) : null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MethodPill extends StatelessWidget {
  const _MethodPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kOfflineNavy : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kOfflineNavy : kOfflineBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminOfflineMonthsPicker extends StatelessWidget {
  const AdminOfflineMonthsPicker({
    super.key,
    required this.controller,
    required this.selectedMonths,
    required this.expanded,
    required this.options,
    required this.preview,
    required this.caption,
    required this.onToggle,
    required this.onSelected,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    this.enabled = true,
  });

  final TextEditingController controller;
  final int selectedMonths;
  final bool expanded;
  final List<AdminOfflineMonthOption> options;
  final String preview;
  final String caption;
  final VoidCallback onToggle;
  final ValueChanged<int> onSelected;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'MONTHS PAID',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
            Flexible(
              child: Text(
                adminOfflineMonthsSelectedBadge(selectedMonths),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kOfflineNavy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            const OfflineMonthsInputFormatter(),
          ],
          textInputAction: TextInputAction.done,
          onTap: onTap,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: '1 to 12',
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(
              Icons.calendar_month_outlined,
              color: Color(0xFF94A3B8),
              size: 18,
            ),
            suffixIcon: IconButton(
              tooltip: expanded ? 'Hide suggestions' : 'Show suggestions',
              onPressed: enabled ? onToggle : null,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: const Color(0xFF94A3B8),
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kOfflineBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kOfflineBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kOfflineNavy, width: 1.5),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kOfflineBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SUGGESTED TENURES',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'SETTLEMENT VALUE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF5F5F4)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 192),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFF5F5F4)),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return Material(
                        color: option.selected ? kOfflineNavy : Colors.white,
                        child: InkWell(
                          canRequestFocus: false,
                          onTap:
                              enabled ? () => onSelected(option.months) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                if (option.selected) ...[
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    option.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: option.selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: option.selected
                                          ? Colors.white
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  option.amount,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: option.selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontFamily: 'monospace',
                                    color: option.selected
                                        ? Colors.white
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kOfflineEmeraldSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kOfflineEmeraldBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: kOfflineEmerald,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF064E3B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: Color(0xFF57534E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdminOfflineDateField extends StatelessWidget {
  const AdminOfflineDateField({
    super.key,
    required this.label,
    required this.onChange,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onChange;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAYMENT DATE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? onChange : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kOfflineBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                    color: kOfflineNavy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kOfflineNavy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminOfflineLabeledField extends StatelessWidget {
  const AdminOfflineLabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

InputDecoration adminOfflineInputDecoration({
  String? hintText,
  Widget? prefixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: Colors.white,
    prefixIcon: prefixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kOfflineBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kOfflineBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kOfflineNavy, width: 1.5),
    ),
  );
}

class AdminOfflineActiveBadge extends StatelessWidget {
  const AdminOfflineActiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kOfflineNavy50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kOfflineNavy100),
      ),
      child: const Text(
        'Active Bill',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: kOfflineNavy,
        ),
      ),
    );
  }
}
