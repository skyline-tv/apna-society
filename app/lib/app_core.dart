import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'data/local_database.dart';
import 'services/late_interest.dart';
import 'ui/components.dart';

final db = LocalDatabase();

/// Debounces rapid UI events (search typing) to avoid query storms.
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 350)]);
  final Duration delay;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Fixed demo OTP for local presentation (no SMS gateway).
const kDemoOtp = '123456';
const kDemoAdminMobile = '9876500001';

/// A-101 owner (tenant-occupied flat) — financial access only.
const kDemoOwnerMobile = '9876510032';

/// A-101 active tenant — residential access only.
const kDemoTenantMobile = '9876510101';

/// A-102 owner-occupied flat — full owner access.
const kDemoOwnerOccupiedMobile = '9876510033';
const kDemoGuardMobile = '9876500099';

/// Product / app name (launcher & product branding) — do not rename for society branding.
const kAppName = 'ApnaSociety';

/// Official residential society name shown across demo screens.
const kSocietyName = 'Monarch Solitaire A to E';
const kSocietyAddress = 'Monarch Solitaire A to E Residential Society';
const kAppTagline = 'Simplifying Society Management.';
const kBuildingA = 'Monarch Solitaire A';
const kBuildingB = 'Monarch Solitaire B';
const kBuildingC = 'Monarch Solitaire C';
const kBuildingD = 'Monarch Solitaire D';
const kBuildingE = 'Monarch Solitaire E';

/// All wings in the society (used for admin flat/vehicle mapping).
const kAllBuildings = [
  kBuildingA,
  kBuildingB,
  kBuildingC,
  kBuildingD,
  kBuildingE
];

/// Source art (landscape). Prefer [kAppIconAsset] for square UI / launcher use.
const kLogoAsset = 'assets/icons/icon.png';
const kAppIconAsset = 'assets/icons/app_icon.png';

const kMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats a whole-rupee integer with Indian digit grouping
/// (e.g. `588000` → `₹5,88,000`).
///
/// Used for society maintenance rates and other whole-rupee inventory totals.
String money(int value) {
  final sign = value < 0 ? '-' : '';
  return '$sign₹${_indianGroupedDigits(value.abs())}';
}

/// Formats integer paise from backend-v2 into a rupee display string.
///
/// Division is integer-only for the rupee part; the remainder is shown as
/// two decimal places. Settlement math stays on the server.
/// Thousands grouping for the rupee whole part stays western (`1,234.56`)
/// so live billing/report paise displays remain unchanged.
String moneyPaise(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final fraction = abs % 100;
  final whole = rupees.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
  return '$sign₹$whole.${fraction.toString().padLeft(2, '0')}';
}

/// Indian numbering: last group of 3 digits, then groups of 2.
String _indianGroupedDigits(int absolute) {
  final digits = absolute.toString();
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) parts.insert(0, head);
  return '${parts.join(',')},$last3';
}

String monthName(DateTime date) => '${kMonths[date.month - 1]} ${date.year}';

/// Inclusive prepaid coverage: start month through (start + months - 1).
/// Examples: Oct 2026 x 1 → "October 2026"; Oct 2026 x 3 → "October 2026 - December 2026".
String maintenancePeriodLabel({
  required DateTime startMonth,
  required int monthsCovered,
  DateTime? periodEnd,
}) {
  final start = DateTime(startMonth.year, startMonth.month);
  final months = monthsCovered < 1 ? 1 : monthsCovered;
  if (months <= 1) return monthName(start);
  final end = periodEnd != null
      ? DateTime(periodEnd.year, periodEnd.month)
      : DateTime(start.year, start.month + months - 1);
  return '${monthName(start)} - ${monthName(end)}';
}

String shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day.toString().padLeft(2, '0')} ${kMonths[d.month - 1].substring(0, 3)} ${d.year}';
}

Widget billDetailLine(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(color: C.muted, fontSize: 12))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: C.navy, fontSize: 13))),
      ]),
    );

List<Map<String, dynamic>> billOtherChargesOf(dynamic bill) {
  final raw = bill is Map
      ? bill['other_charges_json']
      : bill.data['other_charges_json'];
  if (raw is String) return LocalDatabase.parseOtherChargesJson(raw);
  if (raw is List) {
    try {
      return LocalDatabase.parseOtherChargesJson(jsonEncode(raw));
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

int billMaintenanceAmountOf(dynamic bill) {
  final data = bill is Map ? bill : bill.data as Map;
  final stored = data['maintenance_amount'] as int?;
  if (stored != null && stored > 0) return stored;
  final unit = data['unit_amount'] as int? ?? 0;
  final months = data['months_covered'] as int? ?? 1;
  final amount = data['amount'] as int? ?? 0;
  final other = data['other_charges_total'] as int? ?? 0;
  if (other > 0 && amount >= other) return amount - other;
  if (unit > 0) return unit * months;
  return amount;
}

int billOtherChargesTotalOf(dynamic bill) {
  final data = bill is Map ? bill : bill.data as Map;
  final stored = data['other_charges_total'] as int?;
  if (stored != null) return stored;
  return billOtherChargesOf(bill)
      .fold<int>(0, (s, c) => s + (c['amount'] as int? ?? 0));
}

/// Maintenance + other-charges breakdown lines for bill UIs.
List<Widget> billAmountBreakdownLines(dynamic bill) {
  final months = (bill is Map
          ? bill['months_covered']
          : bill.data['months_covered']) as int? ??
      1;
  final unit =
      (bill is Map ? bill['unit_amount'] : bill.data['unit_amount']) as int? ??
          0;
  final maint = billMaintenanceAmountOf(bill);
  final otherTotal = billOtherChargesTotalOf(bill);
  final charges = billOtherChargesOf(bill);
  final grand =
      (bill is Map ? bill['amount'] : bill.read<int>('amount')) as int;
  return [
    billDetailLine('Monthly maintenance', money(unit)),
    billDetailLine('Prepaid months', '$months'),
    billDetailLine('Maintenance subtotal', money(maint)),
    if (charges.isNotEmpty) ...[
      const SizedBox(height: 4),
      const Text('Other Charges',
          style: TextStyle(
              fontWeight: FontWeight.w800, color: C.navy, fontSize: 12)),
      const SizedBox(height: 4),
      ...charges.map((c) => billDetailLine(
          '${c['description']}', money(c['amount'] as int? ?? 0))),
      billDetailLine('Other Charges total', money(otherTotal)),
    ] else if (otherTotal > 0)
      billDetailLine('Other Charges total', money(otherTotal)),
    billDetailLine('Original bill total', money(grand)),
  ];
}

List<Widget> billInterestBreakdownLines(BillInterestSummary s,
    {bool paid = false}) {
  final due = s.dueDate == null ? '—' : shortDate(s.dueDate!.toIso8601String());
  return [
    const SizedBox(height: 4),
    const Text('Late payment interest',
        style: TextStyle(
            fontWeight: FontWeight.w800, color: C.navy, fontSize: 12)),
    const SizedBox(height: 4),
    billDetailLine('Due date', due),
    billDetailLine('Overdue months', '${s.overdueMonths}'),
    billDetailLine('Annual interest rate',
        '${s.annualRatePercent.toStringAsFixed(0)}% (monthly ${s.monthlyRatePercent.toStringAsFixed(2)}%)'),
    billDetailLine(paid ? 'Interest collected' : 'Accumulated interest',
        money(paid ? s.interestPaid : s.interestOutstanding)),
    if (!paid) ...[
      billDetailLine('Principal outstanding', money(s.principalOutstanding)),
      billDetailLine('Total outstanding', money(s.totalOutstanding)),
    ],
  ];
}

/// Loads interest and returns maintenance + interest display lines.
Future<List<Widget>> billFullBreakdownLines(dynamic bill) async {
  final id = bill is Map ? bill['id'] as int : bill.read<int>('id') as int;
  final status =
      bill is Map ? bill['status'] as String : bill.read<String>('status');
  final summary = await db.billInterestSummary(id);
  return [
    ...billAmountBreakdownLines(bill),
    ...billInterestBreakdownLines(summary, paid: status == 'paid'),
    if (status != 'paid' && summary.interestOutstanding > 0)
      billDetailLine('Total payable now', money(summary.totalOutstanding)),
  ];
}

/// Shared Monarch Solitaire / ApnaSociety brand mark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40, this.radius = 12});
  final double size;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: Colors.white,
          child: Image.asset(
            kAppIconAsset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              kLogoAsset,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: C.blue,
                alignment: Alignment.center,
                child: Icon(Icons.apartment_rounded,
                    color: Colors.white, size: size * 0.55),
              ),
            ),
          ),
        ),
      );
}

Widget brandAppBarTitle({required String title, String? subtitle}) => Row(
      children: [
        const BrandLogo(size: 36, radius: 10),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: C.navy)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11,
                        color: C.muted,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
