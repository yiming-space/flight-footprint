import 'package:flutter/material.dart';

/// Semantic colors that follow the app's selected brightness.
///
/// Keep product colors here so the light theme can be art-directed as a whole
/// instead of leaving individual cards to carry their own unrelated hexes.
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.lime,
    required this.purple,
    required this.danger,
    required this.cardLavender,
    required this.cardBlue,
    required this.cardMint,
    required this.cardCoral,
    required this.cardYellow,
    required this.cardText,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color lime;
  final Color purple;
  final Color danger;
  final Color cardLavender;
  final Color cardBlue;
  final Color cardMint;
  final Color cardCoral;
  final Color cardYellow;
  final Color cardText;

  static const dark = AppThemeColors(
    background: Color(0xFF0B0E12),
    surface: Color(0xFF171B20),
    surfaceElevated: Color(0xFF1D2228),
    border: Color(0xFF30363D),
    textPrimary: Color(0xFFF5F6F7),
    textSecondary: Color(0xFFB2B6BC),
    textTertiary: Color(0xFF7E858D),
    lime: Color(0xFFA8E85C),
    purple: Color(0xFF9274FF),
    danger: Color(0xFFFF7A7A),
    cardLavender: Color(0xFFB9A9F2),
    cardBlue: Color(0xFF9CCFE6),
    cardMint: Color(0xFFA8D7AF),
    cardCoral: Color(0xFFE2B4D1),
    cardYellow: Color(0xFFE6DD79),
    cardText: Color(0xFF0B0E12),
  );

  static const light = AppThemeColors(
    // Cool white with a quiet sage undertone keeps the canvas bright without
    // turning the light mode into a beige filter. Color lives in the cards
    // and controls, while the map remains deliberately dark.
    background: Color(0xFFF6F8F5),
    surface: Color(0xFFFFFEFC),
    surfaceElevated: Color(0xFFEDF1EC),
    border: Color(0xFFD9E2DB),
    textPrimary: Color(0xFF17221B),
    textSecondary: Color(0xFF68766D),
    textTertiary: Color(0xFF929C95),
    // A muted sage is the light-mode signature: calm enough for chrome,
    // distinct enough to keep selected states and progress easy to scan.
    lime: Color(0xFF9BCB78),
    purple: Color(0xFF9A84D8),
    danger: Color(0xFFD78991),
    // Pastels borrow the reference's mint, lilac, powder blue, blush, and
    // butter notes, but keep enough value contrast for dark flight data.
    cardLavender: Color(0xFFD6CBEE),
    cardBlue: Color(0xFFC2DDE8),
    cardMint: Color(0xFFC6E2CF),
    cardCoral: Color(0xFFE9C3D5),
    cardYellow: Color(0xFFF1E4A6),
    cardText: Color(0xFF17221B),
  );

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? lime,
    Color? purple,
    Color? danger,
    Color? cardLavender,
    Color? cardBlue,
    Color? cardMint,
    Color? cardCoral,
    Color? cardYellow,
    Color? cardText,
  }) => AppThemeColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    lime: lime ?? this.lime,
    purple: purple ?? this.purple,
    danger: danger ?? this.danger,
    cardLavender: cardLavender ?? this.cardLavender,
    cardBlue: cardBlue ?? this.cardBlue,
    cardMint: cardMint ?? this.cardMint,
    cardCoral: cardCoral ?? this.cardCoral,
    cardYellow: cardYellow ?? this.cardYellow,
    cardText: cardText ?? this.cardText,
  );

  @override
  AppThemeColors lerp(covariant AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      cardLavender: Color.lerp(cardLavender, other.cardLavender, t)!,
      cardBlue: Color.lerp(cardBlue, other.cardBlue, t)!,
      cardMint: Color.lerp(cardMint, other.cardMint, t)!,
      cardCoral: Color.lerp(cardCoral, other.cardCoral, t)!,
      cardYellow: Color.lerp(cardYellow, other.cardYellow, t)!,
      cardText: Color.lerp(cardText, other.cardText, t)!,
    );
  }
}

extension AppThemeColorsContext on BuildContext {
  AppThemeColors get appColors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.dark;
}

/// Semantic palette shared by every Flight Footprint surface.
abstract final class AppColors {
  static const background = Color(0xFF0B0E12);
  static const surface = Color(0xFF171B20);
  static const surfaceElevated = Color(0xFF1D2228);
  static const border = Color(0xFF30363D);
  static const textPrimary = Color(0xFFF5F6F7);
  static const textSecondary = Color(0xFFB2B6BC);
  static const textTertiary = Color(0xFF7E858D);
  static const lime = Color(0xFFA8E85C);
  static const purple = Color(0xFF9274FF);
  static const danger = Color(0xFFFF7A7A);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 40.0;
  static const page = 20.0;
  static const cardGap = 14.0;
  static const section = 28.0;
  static const bottomBarHeight = 84.0;
  static const bottomBarBottomMinimum = 10.0;

  /// Space that lets the last item scroll clear of the floating navigation
  /// bar. The shell extends the body behind the bar so the bar can float over
  /// content; the scroll view therefore needs to reserve that overlap itself.
  static double bottomBarClearance(BuildContext context) {
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    final safeBottom = systemBottom > bottomBarBottomMinimum
        ? systemBottom
        : bottomBarBottomMinimum;
    return bottomBarHeight + sm + safeBottom + md;
  }
}

abstract final class AppRadii {
  static const small = BorderRadius.all(Radius.circular(18));
  static const medium = BorderRadius.all(Radius.circular(28));
  static const large = BorderRadius.all(Radius.circular(44));
  static const pill = BorderRadius.all(Radius.circular(999));
}

/// The app's shared shape language. Superellipse corners keep large surfaces
/// soft and intentional in the same visual family as iOS cards and controls.
abstract final class AppShapes {
  static const small = RoundedSuperellipseBorder(borderRadius: AppRadii.small);
  static const medium = RoundedSuperellipseBorder(
    borderRadius: AppRadii.medium,
  );
  static const large = RoundedSuperellipseBorder(borderRadius: AppRadii.large);
  static const pill = RoundedSuperellipseBorder(borderRadius: AppRadii.pill);
  static const sheet = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(44)),
  );
}

abstract final class AppTextStyles {
  static const pageTitle = TextStyle(
    fontSize: 40,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
  );
  static const sectionTitle = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(fontSize: 16, height: 1.4);
  static const bodySecondary = TextStyle(fontSize: 16, height: 1.4);
  static const label = TextStyle(
    fontSize: 14,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );
  static const metric = TextStyle(
    fontSize: 48,
    height: 1,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.2,
  );
}

abstract final class AppTheme {
  static ThemeData dark() => _build(AppThemeColors.dark, Brightness.dark);

  static ThemeData light() => _build(AppThemeColors.light, Brightness.light);

  static ThemeData _build(AppThemeColors colors, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.lime,
          brightness: brightness,
          surface: colors.surface,
        ).copyWith(
          primary: colors.lime,
          onPrimary: colors.cardText,
          secondary: colors.purple,
          onSecondary: brightness == Brightness.dark
              ? Colors.white
              : colors.cardText,
          surface: colors.surface,
          surfaceContainerHighest: colors.surfaceElevated,
          onSurface: colors.textPrimary,
          onSurfaceVariant: colors.textSecondary,
          outline: colors.border,
          error: colors.danger,
          surfaceTint: Colors.transparent,
        );
    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      useMaterial3: true,
      fontFamily: 'PingFang SC',
      extensions: [colors],
      textTheme: TextTheme(
        headlineLarge: AppTextStyles.pageTitle.copyWith(
          color: colors.textPrimary,
        ),
        titleLarge: AppTextStyles.sectionTitle.copyWith(
          color: colors.textPrimary,
        ),
        bodyLarge: AppTextStyles.body.copyWith(color: colors.textPrimary),
        bodyMedium: AppTextStyles.bodySecondary.copyWith(
          color: colors.textSecondary,
        ),
        labelLarge: AppTextStyles.label.copyWith(color: colors.textSecondary),
      ),
      dividerColor: colors.border,
      // InkSparkle can paint outside a rounded InkWell's visual surface when
      // the nearest Material is the page scaffold. Keep the press state quiet
      // so card corners never flash on tap; selected states still animate via
      // their own widgets.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
