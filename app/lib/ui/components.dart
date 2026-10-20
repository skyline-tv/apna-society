import 'package:flutter/material.dart';

/// Monarch Solitaire visual tokens.
class C {
  static const blue = Color(0xFF1E4DB7); // Deep royal blue
  static const softBlue = Color(0xFF5B8DEF); // Soft accent
  static const navy = Color(0xFF14284A); // Dark navy text
  static const charcoal = Color(0xFF2D3748);
  static const bg = Color(0xFFF5F7FB); // Very light cool grey
  static const surface = Colors.white;
  static const green = Color(0xFF1F9D6C);
  static const amber = Color(0xFFD97706);
  static const error = Color(0xFFC44536);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE6EAF2);
  static const chip = Color(0xFFEEF3FF);
}

ThemeData buildAppTheme() {
  final base =
      ColorScheme.fromSeed(seedColor: C.blue, brightness: Brightness.light);
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.copyWith(
      primary: C.blue,
      secondary: C.softBlue,
      surface: C.surface,
      error: C.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.navy,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: C.chip,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? C.blue : C.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? C.blue : C.muted, size: 22);
      }),
      height: 68,
      elevation: 2,
      shadowColor: Colors.black12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.blue, width: 1.4)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.error)),
      labelStyle: const TextStyle(color: C.muted),
      hintStyle: const TextStyle(color: C.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.navy,
        side: const BorderSide(color: C.line),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: C.chip,
      selectedColor: C.blue.withValues(alpha: 0.14),
      labelStyle: const TextStyle(
          fontWeight: FontWeight.w700, color: C.navy, fontSize: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: C.line)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: C.surface,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      showDragHandle: true,
    ),
    dividerColor: C.line,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg;
    Color fg;
    switch (s) {
      case 'paid':
      case 'success':
      case 'active':
      case 'approved':
      case 'completed':
      case 'inside':
      case 'cleared':
      case 'cheque · cleared':
        bg = const Color(0xFFE8F7F0);
        fg = C.green;
      case 'overdue':
      case 'inactive':
      case 'rejected':
      case 'denied':
      case 'bounced':
      case 'reversed':
      case 'cheque · bounced':
        bg = const Color(0xFFFDECEC);
        fg = C.error;
      case 'cancelled':
      case 'expired':
        bg = const Color(0xFFF3F4F6);
        fg = C.muted;
      case 'pending':
      case 'pending_approval':
      case 'awaiting_owner':
      case 'pending owner approval':
      case 'cheque recorded':
      case 'cheque · pending':
      default:
        bg = const Color(0xFFFFF7E8);
        fg = C.amber;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(),
          style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3)),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard(
      {super.key, required this.child, this.padding, this.margin, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.line),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A14284A), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
          borderRadius: BorderRadius.circular(18), onTap: onTap, child: card),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color = C.blue,
    this.accent,
  });
  final String title, value;
  final IconData icon;
  final Color color;
  final Color? accent;
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: (accent ?? color).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: accent ?? color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: C.navy)),
          const SizedBox(height: 3),
          Text(title,
              style: const TextStyle(
                  fontSize: 11, color: C.muted, fontWeight: FontWeight.w600)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: C.navy))),
          if (action != null) action!,
        ],
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: C.chip, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, size: 30, color: C.muted),
            ),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: C.muted, fontWeight: FontWeight.w600, height: 1.35)),
          ]),
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 28,
              height: 28,
              child:
                  CircularProgressIndicator(strokeWidth: 2.6, color: C.blue)),
          const SizedBox(height: 12),
          Text(label,
              style:
                  const TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
        ]),
      );
}

class InfoNote extends StatelessWidget {
  const InfoNote(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: C.chip, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: C.blue, size: 18),
          const SizedBox(width: 9),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: C.navy,
                      fontSize: 11,
                      height: 1.45,
                      fontWeight: FontWeight.w600))),
        ]),
      );
}

class QuickActionTile extends StatelessWidget {
  const QuickActionTile(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: C.chip, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: C.blue, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: C.navy,
                      fontSize: 13))),
          const Icon(Icons.chevron_right_rounded, color: C.muted),
        ]),
      );
}

class HeroMoneyCard extends StatelessWidget {
  const HeroMoneyCard({
    super.key,
    required this.label,
    required this.amount,
    this.subtitle,
    this.child,
  });
  final String label;
  final String amount;
  final String? subtitle;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: C.navy,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
                color: Color(0x3314284A), blurRadius: 18, offset: Offset(0, 8))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFFC9D6F0),
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(amount,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.05)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: const TextStyle(
                    color: Color(0xFFC9D6F0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
          if (child != null) ...[const SizedBox(height: 16), child!],
        ]),
      );
}
