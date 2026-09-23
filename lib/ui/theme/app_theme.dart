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
    required this.surfaceDeep,
    required this.iceTint,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.lime,
    required this.onPrimary,
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
  final Color surfaceDeep;
  final Color iceTint;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color lime;
  final Color onPrimary;
  final Color purple;
  final Color danger;
  final Color cardLavender;
  final Color cardBlue;
  final Color cardMint;
  final Color cardCoral;
  final Color cardYellow;
  final Color cardText;

  static const dark = AppThemeColors(
    // 暗夜绿：以中性近黑承载大面积内容，只让绿和紫承担语义强调。
    background: Color(0xFF0B0E12),
    surface: Color(0xFF171B20),
    surfaceElevated: Color(0xFF22282E),
    surfaceDeep: Color(0xFF11161C),
    iceTint: Color(0xFF293522),
    textPrimary: Color(0xFFF5F6F7),
    border: Color(0xFF303832),
    textSecondary: Color(0xFFA6ADB5),
    textTertiary: Color(0xFF737C86),
    lime: Color(0xFFA8E85C),
    onPrimary: Color(0xFF0B0E12),
    purple: Color(0xFF9274FF),
    danger: Color(0xFFFF7A7A),
    // Dark cards share one elevated surface. The old five-color card rhythm
    // remains available to Ice White through its own light values.
    cardLavender: Color(0xFF22282E),
    cardBlue: Color(0xFF22282E),
    cardMint: Color(0xFF22282E),
    cardCoral: Color(0xFF22282E),
    cardYellow: Color(0xFF22282E),
    cardText: Color(0xFFF5F6F7),
  );

  static const light = AppThemeColors(
    // Ice White uses a quiet warm page, crisp white cards, and a cool gray
    // navigation layer. Accent color is reserved for interaction states.
    background: Color(0xFFF4F4F0),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFE5EDF8),
    surfaceDeep: Color(0xFFE3E8EE),
    iceTint: Color(0xFFDCE8F7),
    border: Color(0xFFD5DDE6),
    textPrimary: Color(0xFF24324F),
    textSecondary: Color(0xFF596579),
    textTertiary: Color(0xFF687487),
    // The supplied palette replaces the former deep indigo action color.
    // Dark ink remains the foreground so the lighter blue stays readable.
    lime: Color(0xFF78A2D2),
    onPrimary: Color(0xFF24324F),
    purple: Color(0xFF78A2D2),
    danger: Color(0xFFC47F88),
    cardLavender: Color(0xFFFFFFFF),
    cardBlue: Color(0xFFFFFFFF),
    cardMint: Color(0xFFFFFFFF),
    cardCoral: Color(0xFFFFFFFF),
    cardYellow: Color(0xFFFFFFFF),
    cardText: Color(0xFF24324F),
  );

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceDeep,
    Color? iceTint,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? lime,
    Color? onPrimary,
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
    surfaceDeep: surfaceDeep ?? this.surfaceDeep,
    iceTint: iceTint ?? this.iceTint,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    lime: lime ?? this.lime,
    onPrimary: onPrimary ?? this.onPrimary,
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
      surfaceDeep: Color.lerp(surfaceDeep, other.surfaceDeep, t)!,
      iceTint: Color.lerp(iceTint, other.iceTint, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
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
  static const surfaceElevated = Color(0xFF22282E);
  static const border = Color(0xFF303832);
  static const textPrimary = Color(0xFFF5F6F7);
  static const textSecondary = Color(0xFFA6ADB5);
  static const textTertiary = Color(0xFF737C86);
  static const lime = Color(0xFFA8E85C);
  static const purple = Color(0xFF9274FF);
  static const routePurple = Color(0xFFA39AD6);
  static const routePurpleDeep = Color(0xFF6E648F);
  static const flightArrival = Color(0xFF7B66B5);
  static const mapBlueDeep = Color(0xFF6F8FB5);
  static const mapLavender = Color(0xFF8E82B9);
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
    final platform = Theme.of(context).platform;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= 840 &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);
    if (isDesktop) return lg;

    final systemBottom = MediaQuery.paddingOf(context).bottom;
    final safeBottom = systemBottom > bottomBarBottomMinimum
        ? systemBottom
        : bottomBarBottomMinimum;
    return bottomBarHeight + sm + safeBottom + md;
  }
}

abstract final class AppMotion {
  static const control = Duration(milliseconds: 180);
  static const selection = Duration(milliseconds: 260);
  static const short = Duration(milliseconds: 120);
}

abstract final class AppShadows {
  static List<BoxShadow> card(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    if (isLight) return const <BoxShadow>[];
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: .18),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
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
          onPrimary: colors.onPrimary,
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
