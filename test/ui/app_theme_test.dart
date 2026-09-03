import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';

void main() {
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
