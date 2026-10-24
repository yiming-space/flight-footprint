import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';

void main() {
  test(
    'light palette keeps text and action labels readable on its surfaces',
    () {
      final theme = AppTheme.light();
      final colors = theme.extension<AppThemeColors>()!;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
      }

      for (final surface in [
        colors.background,
        colors.surface,
        colors.surfaceElevated,
        colors.cardLavender,
        colors.cardBlue,
        colors.cardMint,
        colors.cardCoral,
        colors.cardYellow,
      ]) {
        for (final ink in [
          colors.textPrimary,
          colors.textSecondary,
          colors.textTertiary,
          colors.lime,
          colors.purple,
        ]) {
          expect(contrast(ink, surface), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        contrast(colors.onPrimary, colors.actionFill),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  test('light and dark themes expose distinct semantic palettes', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    final lightColors = light.extension<AppThemeColors>()!;
    final darkColors = dark.extension<AppThemeColors>()!;

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
    expect(lightColors.textPrimary, isNot(darkColors.textPrimary));
    expect(lightColors.surface, isNot(darkColors.surface));
  });

  testWidgets('semantic palette follows the active theme', (tester) async {
    late AppThemeColors colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            colors = context.appColors;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(colors.background, AppThemeColors.light.background);
    expect(colors.textPrimary, AppThemeColors.light.textPrimary);
  });
}
