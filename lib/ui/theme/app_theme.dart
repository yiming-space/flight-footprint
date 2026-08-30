import 'package:flutter/material.dart';

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

  /// Small breathing room after scrollable content. The shell reserves the
  /// bottom navigation bar's height, so content no longer needs a full bar's
  /// worth of extra padding at the end.
  static double bottomBarClearance(BuildContext context) {
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    return 16 + (systemBottom > 0 ? 4 : 0);
  }
}

abstract final class AppRadii {
  static const small = BorderRadius.all(Radius.circular(12));
  static const medium = BorderRadius.all(Radius.circular(20));
  static const large = BorderRadius.all(Radius.circular(28));
  static const pill = BorderRadius.all(Radius.circular(999));
}

abstract final class AppTextStyles {
  static const pageTitle = TextStyle(
    fontSize: 40,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    color: AppColors.textPrimary,
  );
  static const sectionTitle = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 16,
    height: 1.4,
    color: AppColors.textPrimary,
  );
  static const bodySecondary = TextStyle(
    fontSize: 16,
    height: 1.4,
    color: AppColors.textSecondary,
  );
  static const label = TextStyle(
    fontSize: 14,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );
  static const metric = TextStyle(
    fontSize: 48,
    height: 1,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.2,
    color: AppColors.textPrimary,
  );
}

abstract final class AppTheme {
  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.lime,
          brightness: Brightness.dark,
          surface: AppColors.surface,
        ).copyWith(
          primary: AppColors.lime,
          onPrimary: Colors.black,
          secondary: AppColors.purple,
          onSecondary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          outline: AppColors.border,
          error: AppColors.danger,
        );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      useMaterial3: true,
      fontFamily: 'PingFang SC',
      textTheme: const TextTheme(
        headlineLarge: AppTextStyles.pageTitle,
        titleLarge: AppTextStyles.sectionTitle,
        bodyLarge: AppTextStyles.body,
        bodyMedium: AppTextStyles.bodySecondary,
        labelLarge: AppTextStyles.label,
      ),
      dividerColor: AppColors.border,
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
