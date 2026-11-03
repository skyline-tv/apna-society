import 'dart:async';

import 'package:flutter/material.dart';

import 'data/local_database.dart';
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

/// Product / app name (launcher & product branding) — do not rename for society branding.
const kAppName = 'ApnaSociety';

/// Public SkyLine contact used on login and in the sample-society sheet.
const kSupportEmail = 'info@skylinetv.in';
const kSupportWebsite = 'https://skylinetv.in';
const kSupportWebsiteLabel = 'skylinetv.in';

/// Official residential society name shown across demo screens.
const kSocietyName = 'Monarch Solitaire A to E';
const kSocietyAddress = 'Monarch Solitaire A to E Residential Society';
const kAppTagline = 'Simplifying Society Management.';

/// First publish: residents cannot pay in-app. Admin records cash or cheque.
const kResidentOnlinePaymentsEnabled = false;

/// Incoming visitor call-style full-screen (ringtone, lock-screen takeover,
/// [IncomingVisitorPage]). Code stays; flip to true to restore.
const kIncomingVisitorFullScreenEnabled = false;

const kOfficePaymentMessage =
    'Online payment is not available yet. Please pay cash or cheque at the society office. Your receipt will appear here after the admin records the offline payment.';

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
        const BrandLogo(size: 34, radius: 10),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: C.navy,
                      height: 1.2)),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: C.muted,
                        fontWeight: FontWeight.w600,
                        height: 1.2)),
            ],
          ),
        ),
      ],
    );
