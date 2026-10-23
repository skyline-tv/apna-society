import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────

/// ApnaSociety colour tokens.
///
/// Warm stone canvas, ink text, and a deep blue for actions. Semantic green,
/// amber and red stay limited to status (paid, warning, error).
class C {
  C._();

  // Brand
  static const blue = Color(0xFF1B4F8A);
  static const blueDark = Color(0xFF123A68);
  static const softBlue = Color(0xFF3D73B8);
  static const navy = Color(0xFF1C1917);
  static const charcoal = Color(0xFF44403C);

  // Neutrals
  static const bg = Color(0xFFF4F0EA);
  static const surface = Color(0xFFFFFCF8);
  static const surfaceAlt = Color(0xFFF7F4EE);
  static const line = Color(0xFFE6E1D6);
  static const lineStrong = Color(0xFFD4CFC3);
  static const muted = Color(0xFF78716C);
  static const faint = Color(0xFFA8A29E);
  static const chip = Color(0xFFE6EFF8);

  // Semantic
  static const green = Color(0xFF1F7A4D);
  static const amber = Color(0xFF9A6700);
  static const error = Color(0xFFB42318);
  static const greenSoft = Color(0xFFE5F4EC);
  static const amberSoft = Color(0xFFF8F0DE);
  static const errorSoft = Color(0xFFFBECEA);
  static const neutralSoft = Color(0xFFEFECE6);
}

/// Spacing scale (4pt grid).
class Sp {
  Sp._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Standard horizontal page gutter.
  static const double page = 20;

  /// Standard list/page padding.
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(20, 12, 20, 32);
  static const EdgeInsets listPadding = EdgeInsets.fromLTRB(16, 8, 16, 32);

  /// Width-aware page padding. Narrow phones get a tighter gutter; tablets
  /// keep the same visual inset because content is centered separately.
  static EdgeInsets pageInsets(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return const EdgeInsets.fromLTRB(12, 12, 12, 32);
    if (width < 600) return const EdgeInsets.fromLTRB(16, 12, 16, 32);
    return pagePadding;
  }
}

/// Centers page content on tablets without changing phone layouts.
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = 840,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Scales a child down when its intrinsic width exceeds the parent.
class ScaleToWidth extends StatelessWidget {
  const ScaleToWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

/// Corner radii.
class Rd {
  Rd._();
  static const double sm = 6;
  static const double md = 8; // dense chips
  static const double lg = 12; // inputs, buttons
  static const double xl = 16; // cards, dialogs, hero
  static const double xxl = 20; // bottom sheets, splash mark
  static const double pill = 999;
}

/// Icon sizes.
class Sz {
  Sz._();
  static const double iconSm = 16;
  static const double icon = 20;
  static const double iconLg = 24;
  static const double control = 48; // min touch target / button height
  static const double input = 52;
  static const double avatar = 40;
  static const double avatarLg = 56;
}

/// Typography scale. Weights are deliberately limited to 500 / 600 / 700 / 800.
class T {
  T._();
  static const display = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: C.navy,
      height: 1.15,
      letterSpacing: -0.4);
  static const h1 = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: C.navy,
      height: 1.2,
      letterSpacing: -0.2);
  static const h2 = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w700, color: C.navy, height: 1.25);
  static const h3 = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: C.navy, height: 1.3);
  static const title = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, color: C.navy, height: 1.3);
  static const body = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: C.charcoal,
      height: 1.45);
  static const bodyStrong = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w700, color: C.navy, height: 1.4);
  static const secondary = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500, color: C.muted, height: 1.4);
  static const caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: C.muted, height: 1.35);
  static const label = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: C.muted,
      letterSpacing: 0.6,
      height: 1.2);
  static const money = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: C.navy,
      fontFeatures: [FontFeature.tabularFigures()]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme
// ─────────────────────────────────────────────────────────────────────────────

OutlineInputBorder _inputBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(Rd.lg),
      borderSide: BorderSide(color: color, width: width),
    );

/// Time-of-day greeting used on role dashboards.
String dayGreeting([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Soft fill that sits behind an [IconWell] for a given accent colour.
Color wellFill(Color color) {
  if (color == C.amber) return C.amberSoft;
  if (color == C.error) return C.errorSoft;
  if (color == C.green) return C.greenSoft;
  if (color == C.muted || color == C.faint) return C.neutralSoft;
  return C.chip;
}

ThemeData buildAppTheme() {
  final base =
      ColorScheme.fromSeed(seedColor: C.blue, brightness: Brightness.light);
  final scheme = base.copyWith(
    primary: C.blue,
    onPrimary: Colors.white,
    secondary: C.softBlue,
    surface: C.surface,
    onSurface: C.navy,
    onSurfaceVariant: C.muted,
    outline: C.line,
    outlineVariant: C.line,
    error: C.error,
    surfaceContainerHighest: C.neutralSoft,
    surfaceContainerLow: C.surfaceAlt,
  );
  const shape12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(Rd.lg)));

  const textTheme = TextTheme(
    displaySmall: T.display,
    headlineMedium: T.h1,
    headlineSmall: T.h2,
    titleLarge: T.h2,
    titleMedium: T.h3,
    titleSmall: T.title,
    bodyLarge: T.body,
    bodyMedium: T.body,
    bodySmall: T.secondary,
    labelLarge:
        TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.navy),
    labelMedium: T.caption,
    labelSmall: T.label,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: C.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      titleTextStyle: T.h3,
      iconTheme: IconThemeData(color: C.navy, size: Sz.iconLg),
      actionsIconTheme: IconThemeData(color: C.navy, size: Sz.iconLg),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: C.chip,
      indicatorShape: shape12,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: selected ? C.blue : C.faint,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
            color: selected ? C.blue : C.faint, size: Sz.iconLg);
      }),
      height: 64,
      elevation: 0,
      shadowColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: C.blue,
      unselectedLabelColor: C.muted,
      indicatorColor: C.blue,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: C.line,
      labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      overlayColor: WidgetStateProperty.all(C.chip.withValues(alpha: 0.6)),
      tabAlignment: TabAlignment.fill,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: _inputBorder(C.line),
      enabledBorder: _inputBorder(C.line),
      disabledBorder: _inputBorder(C.line),
      focusedBorder: _inputBorder(C.blue, 1.6),
      errorBorder: _inputBorder(C.error),
      focusedErrorBorder: _inputBorder(C.error, 1.6),
      labelStyle: const TextStyle(color: C.muted, fontWeight: FontWeight.w500),
      floatingLabelStyle:
          const TextStyle(color: C.blue, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: C.faint, fontWeight: FontWeight.w500),
      helperStyle: T.caption,
      helperMaxLines: 3,
      errorStyle: const TextStyle(
          color: C.error, fontWeight: FontWeight.w600, fontSize: 12),
      errorMaxLines: 3,
      prefixIconColor: C.muted,
      suffixIconColor: C.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: C.blue.withValues(alpha: 0.38),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(Sz.control, Sz.control),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: shape12,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: C.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(Sz.control, Sz.control),
        shape: shape12,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.blue,
        backgroundColor: C.surface,
        side: const BorderSide(color: C.blue),
        minimumSize: const Size(Sz.control, Sz.control),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: shape12,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: C.blue,
        minimumSize: const Size(Sz.control, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: shape12,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: C.navy,
        minimumSize: const Size(Sz.control, Sz.control),
        shape: shape12,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(shape12),
        side: WidgetStateProperty.all(const BorderSide(color: C.lineStrong)),
        minimumSize: WidgetStateProperty.all(const Size(0, Sz.control)),
        textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? C.chip : C.surface),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? C.blue : C.navy),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: C.surface,
      selectedColor: C.chip,
      disabledColor: C.neutralSoft,
      checkmarkColor: C.blue,
      showCheckmark: false,
      labelStyle: const TextStyle(
          fontWeight: FontWeight.w600, color: C.navy, fontSize: 12.5),
      secondaryLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700, color: C.blue, fontSize: 12.5),
      side: const BorderSide(color: C.line),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Rd.pill))),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: C.blue,
      textColor: C.navy,
      titleTextStyle: T.bodyStrong,
      subtitleTextStyle: T.secondary,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 10,
      horizontalTitleGap: 12,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Rd.lg))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.white : C.muted),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? C.blue : C.neutralSoft),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? C.blue : C.lineStrong),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? C.blue : Colors.transparent),
      side: const BorderSide(color: C.lineStrong, width: 1.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? C.blue : C.lineStrong),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: C.blue,
      linearTrackColor: C.neutralSoft,
      circularTrackColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.navy,
      contentTextStyle: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
      actionTextColor: const Color(0xFFC9D6F0),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.xl)),
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: T.h3,
      contentTextStyle: T.body,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.xxl))),
      showDragHandle: true,
      dragHandleColor: C.lineStrong,
      constraints: BoxConstraints(maxWidth: 640),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.md)),
      textStyle: T.bodyStrong,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(C.surface),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(shape12),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.xl)),
      headerBackgroundColor: C.navy,
      headerForegroundColor: Colors.white,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.xl)),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: C.error,
      textColor: Colors.white,
      textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
    dividerTheme: const DividerThemeData(color: C.line, thickness: 1, space: 1),
    dividerColor: C.line,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Status
// ─────────────────────────────────────────────────────────────────────────────

enum BadgeTone { success, warning, danger, neutral, info }

/// Maps a raw/labelled status string to a semantic tone.
BadgeTone toneForStatus(String status) {
  final s = status.toLowerCase().replaceAll(RegExp(r'[\s·_-]+'), ' ').trim();
  if (s.isEmpty) return BadgeTone.neutral;
  // Exact-first matches that would otherwise collide with substring rules.
  switch (s) {
    case 'not entered':
    case 'awaiting entry':
      return BadgeTone.warning;
    case 'free':
    case 'no slot':
    case 'none':
    case 'read':
    case 'ended':
    case 'exited':
    case 'archived':
    case 'cancelled':
    case 'canceled':
    case 'expired':
    case 'closed':
    case 'inactive':
    case 'terminated':
    case 'unknown type':
    case 'low':
    case 'guest':
      return BadgeTone.neutral;
  }
  const success = [
    'paid',
    'success',
    'active',
    'approved',
    'completed',
    'inside',
    'entered',
    'cleared',
    'resolved',
    'confirmed',
    'published',
    'present',
    'verified',
    'yes',
    'available',
    'allocated',
    'slot allocated',
    'linked user',
    'resident',
    'normal',
  ];
  const danger = [
    'overdue',
    'rejected',
    'denied',
    'bounced',
    'reversed',
    'failed',
    'failure',
    'absent',
    'urgent',
    'high',
    'critical',
    'no',
    'expiry passed',
    'unverified',
    'locked',
    'refunded',
    'occupied',
  ];
  const warning = [
    'pending',
    'awaiting',
    'partially',
    'partial',
    'issued',
    'open',
    'assigned',
    'in progress',
    'scheduled',
    'draft',
    'half day',
    'leave',
    'medium',
    'unread',
    'new',
    'needs approval',
    'otp active',
    'unpaid',
    'processing',
    'created',
    'initiated',
    'expires',
    'correction',
  ];
  bool hit(List<String> keys) =>
      keys.any((k) => RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(s));
  if (hit(const ['partial', 'partially', 'unpaid'])) return BadgeTone.warning;
  if (hit(success)) return BadgeTone.success;
  if (hit(danger)) return BadgeTone.danger;
  if (hit(warning)) return BadgeTone.warning;
  return BadgeTone.info;
}

({Color bg, Color fg}) badgeColors(BadgeTone tone) {
  switch (tone) {
    case BadgeTone.success:
      return (bg: C.greenSoft, fg: C.green);
    case BadgeTone.warning:
      return (bg: C.amberSoft, fg: C.amber);
    case BadgeTone.danger:
      return (bg: C.errorSoft, fg: C.error);
    case BadgeTone.neutral:
      return (bg: C.neutralSoft, fg: C.muted);
    case BadgeTone.info:
      return (bg: C.chip, fg: C.blue);
  }
}

/// Human-friendly status text: `PARTIALLY_PAID` → `Partially paid`.
String humanizeStatus(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return t;
  // Already formatted (contains lowercase letters) → keep as is.
  if (t.contains(RegExp(r'[a-z]'))) return t;
  final words = t.toLowerCase().split(RegExp(r'[_\s]+'));
  final first = words.first;
  final rest = words.skip(1).join(' ');
  final cap =
      first.isEmpty ? '' : '${first[0].toUpperCase()}${first.substring(1)}';
  return rest.isEmpty ? cap : '$cap $rest';
}

/// Compact pill used for statuses, categories and small facts.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.tone, this.icon});
  final String status;
  final BadgeTone? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = badgeColors(tone ?? toneForStatus(status));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: colors.bg, borderRadius: BorderRadius.circular(Rd.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: colors.fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            humanizeStatus(status),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              height: 1.2,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Small coloured dot + label (e.g. legends, inline state).
class DotLabel extends StatelessWidget {
  const DotLabel(this.label, {super.key, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: T.caption),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Surfaces
// ─────────────────────────────────────────────────────────────────────────────

/// Standard elevated surface. Padding defaults to none so callers can compose
/// `ListTile`s; pass [padding] for free-form content.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
    this.radius = Rd.xl,
    this.accent = false,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    Widget content =
        padding == null ? child : Padding(padding: padding!, child: child);
    if (accent) {
      content = Stack(children: [
        content,
        const Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: ColoredBox(color: C.blue, child: SizedBox(width: 4)),
        ),
      ]);
    }
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color ?? C.surface,
        borderRadius: shape,
        border: Border.all(color: borderColor ?? C.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: shape,
                onTap: onTap,
                onLongPress: onLongPress,
                child: content,
              ),
            ),
    );
  }
}

/// Circular avatar with text (initials/code) or icon.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.text,
    this.icon,
    this.color = C.blue,
    this.size = Sz.avatar,
    this.square = false,
  }) : assert(text != null || icon != null);
  final String? text;
  final IconData? icon;
  final Color color;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(Rd.lg) : null,
      ),
      child: icon != null
          ? Icon(icon, color: color, size: size * 0.5)
          : Text(
              text!,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: text!.length > 2 ? size * 0.3 : size * 0.38,
              ),
            ),
    );
  }
}

/// Initials for an avatar: "Priya Sharma" → "PS".
String initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// Consistent list item: leading avatar/icon, title, subtitle, badges,
/// optional trailing and chevron.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.badges = const [],
    this.footer,
    this.onTap,
    this.onLongPress,
    this.showChevron,
    this.dense = false,
    this.margin,
    this.unread = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> badges;
  final Widget? footer;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool? showChevron;
  final bool dense;
  final EdgeInsetsGeometry? margin;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final chevron = showChevron ?? (onTap != null && trailing == null);
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      margin: margin,
      accent: unread,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: T.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!,
                      style: T.secondary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                ],
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: badges),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (chevron)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right_rounded, color: C.faint),
            ),
        ]),
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ]),
    );
  }
}

/// Key metric card.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color = C.blue,
    this.accent,
    this.onTap,
    this.caption,
  });
  final String title, value;
  final IconData icon;
  final Color color;
  final Color? accent;
  final VoidCallback? onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? color;
    return AppCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(),
                style: T.label.copyWith(color: C.faint, letterSpacing: 0.8),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: C.navy,
                      height: 1.1,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(caption!,
                  style: T.caption.copyWith(color: C.faint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        IconWell(icon: icon, color: tint, size: 36),
      ]),
    );
  }
}

/// Two-up grid of [StatCard]s with consistent gutters.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.columns = 2});
  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      var cols = columns;
      final width = constraints.maxWidth;
      if (width < 360 && columns > 1) {
        cols = 1;
      } else if (width >= 840 && columns == 2 && children.length >= 4) {
        cols = 4;
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final slice = children.sublist(
            i, i + cols > children.length ? children.length : i + cols);
        // IntrinsicHeight bounds the row so CrossAxisAlignment.stretch is safe
        // inside a ListView (unbounded max height). IndexedStack still lays out
        // offstage tabs, so this must not throw on AdminHome.
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) const SizedBox(width: 10),
                Expanded(
                    child:
                        j < slice.length ? slice[j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ));
        if (i + cols < children.length) rows.add(const SizedBox(height: 10));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    });
  }
}

/// Tinted rounded square used next to metrics, list rows and quick actions.
class IconWell extends StatelessWidget {
  const IconWell({
    super.key,
    required this.icon,
    this.color = C.blue,
    this.size = 36,
    this.iconSize,
    this.fill,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;
  final Color? fill;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ?? wellFill(color),
          borderRadius: BorderRadius.circular(Rd.lg),
        ),
        child: Icon(icon, color: color, size: iconSize ?? size * 0.5),
      );
}

/// Coloured greeting band used on owner, tenant and guard homes.
class PineHeader extends StatelessWidget {
  const PineHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
    this.child,
    this.color = C.blue,
    this.bottomPadding = 20,
  });

  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;
  final Color color;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final onPine = color.computeLuminance() < 0.45;
    final titleColor = onPine ? Colors.white : C.navy;
    final mute = onPine ? Colors.white.withValues(alpha: 0.62) : C.muted;
    final inset = Sp.pageInsets(context);
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.fromLTRB(inset.left, 16, inset.right, bottomPadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (eyebrow != null && eyebrow!.isNotEmpty) ...[
                Text(eyebrow!,
                    style: T.caption
                        .copyWith(color: mute, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
              ],
              Text(title,
                  style: T.h1.copyWith(color: titleColor, fontSize: 20),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    style: T.secondary.copyWith(color: mute),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        if (child != null) ...[const SizedBox(height: 14), child!],
      ]),
    );
  }
}

/// Stacks [hero] over the bottom of [header] (banking-style overlap).
class OverlapHero extends StatelessWidget {
  const OverlapHero({
    super.key,
    required this.header,
    required this.hero,
    this.overlap = 36,
    this.sidePadding = 20,
  });

  final Widget header;
  final Widget hero;
  final double overlap;
  final double sidePadding;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.sizeOf(context).width < 360 ? 12.0 : sidePadding;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            header,
            Positioned(
              left: pad,
              right: pad,
              bottom: -overlap,
              child: hero,
            ),
          ],
        ),
        SizedBox(height: overlap + 12),
      ],
    );
  }
}

/// One destination in a [QuickAccessGrid].
class QuickAccessItem {
  const QuickAccessItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = C.blue,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}

/// Four-up (or two-up on a 320-width phone) quick-action tiles.
class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({super.key, required this.items});

  final List<QuickAccessItem> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 360 ? 4 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += columns) {
          final end = i + columns > items.length ? items.length : i + columns;
          final slice = items.sublist(i, end);
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: 8),
                Expanded(
                  child: j < slice.length
                      ? _QuickAccessTile(item: slice[j])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ));
          if (end < items.length) rows.add(const SizedBox(height: 8));
        }
        return Column(children: rows);
      });
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({required this.item});
  final QuickAccessItem item;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: item.onTap,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(children: [
          IconWell(icon: item.icon, color: item.color, size: 40),
          const SizedBox(height: 8),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.caption.copyWith(color: C.navy, height: 1.2),
          ),
        ]),
      );
}

/// Labelled progress used on the admin dashboard (collections / occupancy).
class CollectionBar extends StatelessWidget {
  const CollectionBar({
    super.key,
    required this.title,
    required this.progress,
    this.valueLabel,
    this.caption,
  });

  final String title;
  final double progress;
  final String? valueLabel;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: T.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (valueLabel != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                valueLabel!,
                style: T.bodyStrong.copyWith(color: C.blue),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(Rd.pill),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 8,
            color: C.blue,
            backgroundColor: C.neutralSoft,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 10),
          Text(caption!, style: T.caption),
        ],
      ]),
    );
  }
}

/// Six-box OTP chrome around a text controller. Digits stay live/API-backed.
class OtpBoxes extends StatelessWidget {
  const OtpBoxes({
    super.key,
    required this.controller,
    this.length = 6,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final digits = value.text;
        return Column(children: [
          Row(
            children: [
              for (var i = 0; i < length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _OtpCell(
                    filled: i < digits.length,
                    char: i < digits.length ? digits[i] : '',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: autofocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            maxLength: length,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(length),
            ],
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: const InputDecoration(
              hintText: 'Enter OTP',
              counterText: '',
            ),
          ),
        ]);
      },
    );
  }
}

class _OtpCell extends StatelessWidget {
  const _OtpCell({required this.filled, required this.char});
  final bool filled;
  final String char;

  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(
            color: filled ? C.blue : C.line,
            width: filled ? 2 : 1.4,
          ),
        ),
        child: Text(
          filled ? char : '·',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: filled ? C.blue : C.faint,
          ),
        ),
      );
}

/// Compact inline statistic (value over label) for summary strips.
class MiniStat extends StatelessWidget {
  const MiniStat(this.label, this.value, {super.key, this.tone, this.onTap});
  final String label;
  final String value;
  final BadgeTone? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = tone == null ? C.navy : badgeColors(tone!).fg;
    return AppCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontSize: 18,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        const SizedBox(height: 3),
        Text(label,
            style: T.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Horizontal strip of [MiniStat]s that wraps on narrow screens.
class MiniStatStrip extends StatelessWidget {
  const MiniStatStrip({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth >= 520 ? 4 : 2;
        return StatGrid(columns: perRow, children: children);
      });
}

/// Dark hero card for the single most important amount on a screen.
class HeroMoneyCard extends StatelessWidget {
  const HeroMoneyCard({
    super.key,
    required this.label,
    required this.amount,
    this.subtitle,
    this.child,
    this.trailing,
  });
  final String label;
  final String amount;
  final String? subtitle;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: C.navy,
          borderRadius: BorderRadius.circular(Rd.xl),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(label.toUpperCase(),
                  style: const TextStyle(
                      color: Color(0xFFD6D1C7),
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(amount,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: const TextStyle(
                    color: Color(0xFFD6D1C7),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500)),
          ],
          if (child != null) ...[const SizedBox(height: 16), child!],
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Text & headers
// ─────────────────────────────────────────────────────────────────────────────

/// In-content page header (title + optional subtitle + trailing action).
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.h3),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: T.secondary),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      );
}

/// Section heading with optional trailing action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.subtitle});
  final String title;
  final Widget? action;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.h3),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: T.caption),
              ],
            ]),
          ),
          if (action != null) action!,
        ]),
      );
}

/// Small uppercase label used above form groups.
class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(text.toUpperCase(), style: T.label),
      );
}

/// Key / value row for detail screens.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value,
      {super.key, this.valueWidget, this.emphasize = false, this.labelWidth});
  final String label;
  final String value;
  final Widget? valueWidget;
  final bool emphasize;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final valueChild = valueWidget ??
        Text(
          value.isEmpty ? '—' : value,
          style: emphasize ? T.bodyStrong.copyWith(fontSize: 15) : T.bodyStrong,
        );
    final screenWidth = MediaQuery.sizeOf(context).width;
    // Avoid LayoutBuilder here: scrollable AlertDialogs measure intrinsics.
    if (screenWidth < 340 && labelWidth == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: T.caption),
            const SizedBox(height: 2),
            valueChild,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: labelWidth ?? (screenWidth < 360 ? 96.0 : 128.0),
          child: Text(label, style: T.caption),
        ),
        const SizedBox(width: 8),
        Expanded(child: valueChild),
      ]),
    );
  }
}

/// Grouped detail rows inside a card with optional heading.
class DetailCard extends StatelessWidget {
  const DetailCard(
      {super.key, this.title, required this.children, this.margin});
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => AppCard(
        margin: margin,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(title!.toUpperCase(), style: T.label),
            ),
          ],
          ...children,
        ]),
      );
}

/// Settings / profile style row (icon + title + value/trailing).
class KeyValueTile extends StatelessWidget {
  const KeyValueTile({
    super.key,
    required this.title,
    this.value,
    this.icon,
    this.trailing,
    this.onTap,
    this.leading,
  });
  final String title;
  final String? value;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12)
          ] else if (icon != null) ...[
            AppAvatar(icon: icon, size: 36, square: true),
            const SizedBox(width: 12),
          ],
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.caption),
              if (value != null) ...[
                const SizedBox(height: 2),
                Text(
                  value!.isEmpty ? '—' : value!,
                  style: T.bodyStrong,
                ),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (onTap != null && trailing == null)
            const Icon(Icons.chevron_right_rounded, color: C.faint),
        ]),
      );
}

/// Grouped settings rows in one card separated by dividers.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
              child: Text(title!.toUpperCase(), style: T.label),
            ),
          AppCard(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                children[i],
              ],
            ]),
          ),
        ],
      );
}

/// Row inside [SettingsGroup].
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.value,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });
  final String title;
  final String? value;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? C.error : C.navy;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: destructive ? C.error : C.blue),
          const SizedBox(width: 12),
        ],
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.bodyStrong.copyWith(color: fg)),
            if (value != null && value!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(value!, style: T.secondary),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        if (onTap != null && trailing == null)
          const Icon(Icons.chevron_right_rounded, color: C.faint),
      ]),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// States: empty / loading / info
// ─────────────────────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.message, {
    super.key,
    this.icon = Icons.inbox_outlined,
    this.title,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });
  final String message;
  final IconData icon;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 360 ? 16 : 32,
            vertical: compact ? 20 : 40,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                  color: C.chip, borderRadius: BorderRadius.circular(Rd.xl)),
              child: Icon(icon, size: compact ? 22 : 28, color: C.blue),
            ),
            SizedBox(height: compact ? 10 : 16),
            if (title != null) ...[
              Text(title!, textAlign: TextAlign.center, style: T.h3),
              const SizedBox(height: 6),
            ],
            Text(message,
                textAlign: TextAlign.center,
                style: T.secondary.copyWith(height: 1.45)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.6)),
            const SizedBox(height: 14),
            Text(label, textAlign: TextAlign.center, style: T.caption),
          ]),
        ),
      );
}

/// Subtle pulsing placeholder block.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;
  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
              color: C.neutralSoft,
              borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

/// Skeleton list used as a first-load placeholder for list screens.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.items = 5, this.showHeader = false});
  final int items;
  final bool showHeader;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: Sp.pagePadding,
        children: [
          if (showHeader) ...[
            const SkeletonBox(width: 180, height: 22),
            const SizedBox(height: 18),
          ],
          for (var i = 0; i < items; i++)
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const SkeletonBox(width: 40, height: 40, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 160, height: 14),
                        SizedBox(height: 8),
                        SkeletonBox(width: 220, height: 12),
                        SizedBox(height: 10),
                        SkeletonBox(width: 80, height: 18, radius: 999),
                      ]),
                ),
              ]),
            ),
        ],
      );
}

enum NoteTone { info, warning, success, danger }

/// Low-emphasis contextual note.
class InfoNote extends StatelessWidget {
  const InfoNote(this.message,
      {super.key, this.tone = NoteTone.info, this.icon});
  final String message;
  final NoteTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, ic) = switch (tone) {
      NoteTone.info => (C.chip, C.blue, Icons.info_outline_rounded),
      NoteTone.warning => (C.amberSoft, C.amber, Icons.warning_amber_rounded),
      NoteTone.success => (C.greenSoft, C.green, Icons.check_circle_outline),
      NoteTone.danger => (C.errorSoft, C.error, Icons.error_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Rd.lg)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? ic, color: fg, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: C.navy,
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Inline form-level error text.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InfoNote(message!, tone: NoteTone.danger),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────────────────────

/// Navigational action row with icon, label and chevron.
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color = C.blue,
    this.trailing,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color color;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : 0.55,
        child: AppCard(
          onTap: enabled ? onTap : null,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            AppAvatar(icon: icon, color: color, size: 38, square: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: T.bodyStrong),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: T.caption),
                    ],
                  ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            const Icon(Icons.chevron_right_rounded, color: C.faint),
          ]),
        ),
      );
}

/// Compact navigational tile. Prefer [ToolDirectory] for hubs.
class ServiceTile extends StatelessWidget {
  const ServiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = C.blue,
    this.badge,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final String? badge;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(children: [
          AppAvatar(icon: icon, color: color, size: 32, square: true),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: T.bodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            StatusBadge(badge!),
          ],
        ]),
      );
}

/// One tappable destination inside a [ToolDirectory].
class ToolLink {
  const ToolLink({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
}

/// Grouped list of tools. One surface, hairline separators, no icon grid.
class ToolDirectory extends StatelessWidget {
  const ToolDirectory({super.key, this.title, required this.links});

  final String? title;
  final List<ToolLink> links;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) SectionTitle(title!),
      AppCard(
        margin: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52, endIndent: 12),
            InkWell(
              onTap: links[i].onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(children: [
                  AppAvatar(icon: links[i].icon, size: 32, square: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(links[i].label, style: T.bodyStrong),
                        if (links[i].subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(links[i].subtitle!, style: T.caption),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: C.faint),
                ]),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// Compact figures in one surface. Wraps to two columns on a phone.
class MetricItem {
  const MetricItem(this.label, this.value, {this.onTap, this.valueColor});

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? valueColor;
}

class MetricBand extends StatelessWidget {
  const MetricBand({super.key, required this.items});

  final List<MetricItem> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 560 ? items.length.clamp(1, 4) : 2;
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += columns) {
          final end = i + columns > items.length ? items.length : i + columns;
          final slice = items.sublist(i, end);
          rows.add(IntrinsicHeight(
            child: Row(children: [
              for (var j = 0; j < slice.length; j++) ...[
                if (j > 0) const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: _MetricCell(item: slice[j])),
              ],
            ]),
          ));
          if (end < items.length) rows.add(const Divider(height: 1));
        }
        return AppCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          child: Column(children: rows),
        );
      });
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.item});
  final MetricItem item;

  @override
  Widget build(BuildContext context) {
    final cell = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            item.value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: item.valueColor ?? C.navy,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(item.label,
            style: T.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
    if (item.onTap == null) return cell;
    return InkWell(onTap: item.onTap, child: cell);
  }
}

/// Identity block for detail screens: avatar, title, subtitle, status chips.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.badges = const [],
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> badges;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: T.h1,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!,
                        style: T.secondary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: badges),
          ],
        ],
      );
}

/// Key/value checklist shown before a destructive or irreversible submit.
class ReviewSummary extends StatelessWidget {
  const ReviewSummary({
    super.key,
    this.title = 'Review',
    required this.rows,
    this.note,
  });

  final String title;
  final List<(String, String)> rows;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailCard(
            title: title,
            children: [
              for (final row in rows) DetailRow(row.$1, row.$2),
            ],
          ),
          if (note != null && note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            InfoNote(note!),
          ],
        ],
      );
}

/// Scaffold for forms: keyboard dismiss, scroll body, sticky primary action.
///
/// Uses the default [Scaffold.resizeToAvoidBottomInset] so the sticky bar
/// rides above the keyboard. Extra list padding keeps the focused field
/// scrollable clear of the action bar on small phones.
class FormScaffold extends StatelessWidget {
  const FormScaffold({
    super.key,
    required this.title,
    required this.children,
    this.formKey,
    this.bottom,
    this.actions,
    this.padding,
  });

  final String title;
  final List<Widget> children;
  final GlobalKey<FormState>? formKey;
  final Widget? bottom;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final base =
        (padding ?? Sp.pageInsets(context)).resolve(Directionality.of(context));
    // Leave room to scroll the last field above the sticky bar (button +
    // bar padding + home-indicator zone). Keyboard inset is handled by the
    // Scaffold shrinking the body when the IME opens.
    final listPadding = base.copyWith(
      bottom: base.bottom + (bottom == null ? 0 : 96),
    );
    final body = ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: listPadding,
      children: children,
    );
    final formBody = formKey == null
        ? body
        : Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: body,
          );
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      resizeToAvoidBottomInset: true,
      body: KeyboardDismissOnTap(
        child: ConstrainedContent(child: formBody),
      ),
      bottomNavigationBar:
          bottom == null ? null : BottomActionBar(children: [bottom!]),
    );
  }
}

/// Primary action first, secondary actions as a compact tool list.
class ActionRail extends StatelessWidget {
  const ActionRail({
    super.key,
    this.primary,
    this.secondary = const [],
    this.busy = false,
  });

  final ToolLink? primary;
  final List<ToolLink> secondary;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (primary != null) ...[
            PrimaryButton(
              label: primary!.label,
              icon: primary!.icon,
              busy: busy,
              onPressed: busy ? null : primary!.onTap,
            ),
            if (primary!.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(primary!.subtitle!, style: T.caption),
            ],
            const SizedBox(height: 12),
          ],
          for (final link in secondary)
            QuickActionTile(
              icon: link.icon,
              label: link.label,
              subtitle: link.subtitle,
              enabled: !busy,
              onTap: link.onTap,
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      );
}

/// Bottom navigation with a hairline, used by every role shell.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: C.line)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: destinations,
        ),
      );
}

/// Full-width primary button with built-in busy state (prevents double taps).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.color,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final Color? color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: Colors.white))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
                child:
                    Text(label, overflow: TextOverflow.ellipsis, maxLines: 1)),
          ]);
    final button = FilledButton(
      onPressed: busy ? null : onPressed,
      style: color == null
          ? null
          : FilledButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: color!.withValues(alpha: 0.4)),
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Full-width secondary (outlined) button with busy state.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.destructive = false,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool destructive;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? C.error : C.blue;
    final child = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
                child:
                    Text(label, overflow: TextOverflow.ellipsis, maxLines: 1)),
          ]);
    final button = OutlinedButton(
      onPressed: busy ? null : onPressed,
      style: destructive
          ? OutlinedButton.styleFrom(
              foregroundColor: C.error,
              side: BorderSide(color: C.error.withValues(alpha: 0.4)))
          : null,
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Pinned bottom action area for forms (sits above the keyboard / safe area).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: C.surface,
          border: Border(top: BorderSide(color: C.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ]),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Filters, search, pagination
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontally scrolling row of filter chips with consistent spacing.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding ?? EdgeInsets.zero,
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ]),
      );
}

/// Selectable pill used in [FilterBar].
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        avatar: icon == null
            ? null
            : Icon(icon, size: 16, color: selected ? C.blue : C.muted),
        selected: selected,
        onSelected: (_) => onSelected(),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? C.blue : C.navy,
          fontSize: 12.5,
        ),
        side: BorderSide(
            color: selected ? C.blue.withValues(alpha: 0.35) : C.line),
      );
}

/// Standard search input.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
  });
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    Widget field(bool hasText) => TextField(
          controller: controller,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            suffixIcon: hasText
                ? IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      controller?.clear();
                      onChanged?.call('');
                      onClear?.call();
                    },
                  )
                : null,
          ),
        );
    if (controller == null) return field(false);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller!,
      builder: (_, v, __) => field(v.text.isNotEmpty),
    );
  }
}

/// Results-count line used under filters.
class ResultCount extends StatelessWidget {
  const ResultCount(this.count, this.noun, {super.key});
  final int count;
  final String noun;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '$count ${count == 1 ? noun : '${noun}s'}',
          style: T.caption.copyWith(color: C.faint),
        ),
      );
}

/// Previous / next pagination row.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });
  final int page;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            tooltip: 'Previous page',
            onPressed: page <= 1 ? null : onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Page $page of $totalPages', style: T.caption),
          ),
          IconButton.outlined(
            tooltip: 'Next page',
            onPressed: page >= totalPages ? null : onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Read-only input-styled field that opens a picker on tap.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = Icons.calendar_today_outlined,
    this.helper,
    this.onClear,
    this.enabled = true,
  });
  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData icon;
  final String? helper;
  final VoidCallback? onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: InputDecorator(
          isEmpty: value == null || value!.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            enabled: enabled,
            prefixIcon: Icon(icon),
            suffixIcon: onClear != null && (value ?? '').isNotEmpty
                ? IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClear,
                  )
                : const Icon(Icons.expand_more_rounded),
          ),
          child: Text(
            value ?? '',
            style: T.bodyStrong,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

/// Time input backed by a text controller in `HH:mm`, opened via time picker.
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool enabled;

  TimeOfDay _parse() {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(controller.text.trim());
    if (m == null) return TimeOfDay.now();
    final h = int.tryParse(m.group(1)!) ?? 0;
    final min = int.tryParse(m.group(2)!) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: min.clamp(0, 59));
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, v, _) => PickerField(
          label: label,
          value: v.text,
          helper: helper,
          enabled: enabled,
          icon: Icons.schedule_outlined,
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: _parse(),
            );
            if (picked == null) return;
            controller.text =
                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          },
        ),
      );
}

/// Stepper for small integer quantities with large touch targets.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
        child: Row(children: [
          Expanded(child: Text('$value', style: T.bodyStrong)),
          IconButton(
            tooltip: 'Decrease',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            tooltip: 'Increase',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
      );
}

/// Dismiss keyboard when tapping outside inputs.
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      );
}

/// Parses a rupee string (`1234`, `1,234.50`) into integer paise.
/// Returns null when invalid. Money math stays integer-only.
int? parseRupeesToPaise(String input) {
  final t = input.replaceAll(',', '').replaceAll('₹', '').trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final rupees = int.tryParse(m.group(1)!);
  if (rupees == null) return null;
  final fracRaw = m.group(2) ?? '0';
  final frac = int.parse(fracRaw.padRight(2, '0'));
  return rupees * 100 + frac;
}

/// Formats integer paise as an editable rupee string (`123456` → `1234.56`).
String paiseToRupeeInput(int paise) {
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final frac = abs % 100;
  final sign = paise < 0 ? '-' : '';
  return frac == 0
      ? '$sign$rupees'
      : '$sign$rupees.${frac.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Feedback: snackbars, dialogs, sheets
// ─────────────────────────────────────────────────────────────────────────────

enum SnackTone { neutral, success, error, warning, info }

void showAppSnack(
  BuildContext context,
  String message, {
  SnackTone tone = SnackTone.neutral,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final (bg, icon) = switch (tone) {
    SnackTone.neutral => (C.navy, null),
    SnackTone.success => (C.green, Icons.check_circle_outline_rounded),
    SnackTone.error => (C.error, Icons.error_outline_rounded),
    SnackTone.warning => (C.amber, Icons.warning_amber_rounded),
    SnackTone.info => (C.blue, Icons.info_outline_rounded),
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: bg,
      duration: Duration(seconds: tone == SnackTone.error ? 5 : 3),
      content: Row(children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(message)),
      ]),
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel, textColor: Colors.white, onPressed: onAction)
          : null,
    ));
}

void showSuccessSnack(BuildContext context, String message) =>
    showAppSnack(context, message, tone: SnackTone.success);
void showErrorSnack(BuildContext context, String message) =>
    showAppSnack(context, message, tone: SnackTone.error);
void showInfoSnack(BuildContext context, String message) =>
    showAppSnack(context, message, tone: SnackTone.info);
void showWarningSnack(BuildContext context, String message) =>
    showAppSnack(context, message, tone: SnackTone.warning);

/// Confirmation dialog. Returns true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      icon: icon == null
          ? null
          : Icon(icon, color: destructive ? C.error : C.blue, size: 32),
      title: Text(title),
      content: message == null ? null : Text(message),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: C.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Text prompt dialog. Returns null when cancelled; otherwise the trimmed text
/// (may be empty when [required] is false).
Future<String?> promptTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? message,
  String? hint,
  String? initialValue,
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
  bool required = false,
  int minLength = 0,
  int maxLines = 1,
  bool destructive = false,
  TextInputType? keyboardType,
}) async {
  final ctrl = TextEditingController(text: initialValue ?? '');
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        scrollable: true,
        title: Text(title),
        actionsOverflowAlignment: OverflowBarAlignment.end,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (message != null) ...[
            Text(message, style: T.secondary),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              hintText: hint,
              errorText: error,
            ),
            onChanged: (_) {
              if (error != null) setLocal(() => error = null);
            },
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(cancelLabel)),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: C.error)
                : null,
            onPressed: () {
              final t = ctrl.text.trim();
              if (required && t.isEmpty) {
                setLocal(() => error = 'This field is required.');
                return;
              }
              if (t.isNotEmpty && t.length < minLength) {
                setLocal(() => error = 'Enter at least $minLength characters.');
                return;
              }
              Navigator.pop(ctx, t);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return result;
}

/// Standard modal bottom sheet wrapper with safe-area and scroll support.
Future<R?> showAppSheet<R>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  String? title,
}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final inset = Sp.pageInsets(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(inset.left, 4, inset.right, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(title, style: T.h3),
                const SizedBox(height: 14),
              ],
              builder(ctx),
            ],
          ),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Date/time display helpers (shared across modules)
// ─────────────────────────────────────────────────────────────────────────────

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

/// `12 Mar 2026`
String fmtDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')} ${_kShortMonths[l.month - 1]} ${l.year}';
}

/// `12 Mar 2026, 14:05`
String fmtDateTime(DateTime d) {
  final l = d.toLocal();
  return '${fmtDate(l)}, ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Parses an ISO string and formats as date. Returns `—` for null/empty.
String fmtIsoDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : fmtDate(d);
}

/// Parses an ISO string and formats as date + time. Returns `—` for null/empty.
String fmtIsoDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : fmtDateTime(d);
}

/// `yyyy-MM-dd` (date-only API strings) → `12 Mar 2026`; passthrough otherwise.
String fmtYmd(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return fmtDate(DateTime(d.year, d.month, d.day));
}
