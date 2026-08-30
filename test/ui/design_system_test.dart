import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flight_footprint/ui/widgets/app_widgets.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: child),
  );

  testWidgets('primary button has an accessible label and touch target', (
    tester,
  ) async {
    await tester.pumpWidget(host(const PrimaryButton(label: '保存航段')));
    expect(find.text('保存航段'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSemantics(find.text('保存航段')),
      matchesSemantics(label: '保存航段', isButton: true, hasEnabledState: true),
    );
  });

  testWidgets('segmented control changes selection', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => AppSegmentedControl(
            labels: const ['全部', '2026', '2025'],
            selectedIndex: selected,
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );
    await tester.tap(find.text('2026'));
    expect(selected, 1);
  });

  testWidgets('bottom navigation exposes four destinations and add action', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AppBottomNav(
          current: AppNavDestination.home,
          onDestinationSelected: (_) {},
          onAdd: () {},
        ),
      ),
    );
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('航迹'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('empty state communicates title and message', (tester) async {
    await tester.pumpWidget(
      host(const EmptyState(title: '还没有航段', message: '记录一次飞行，开始绘制你的地图')),
    );
    expect(find.text('还没有航段'), findsOneWidget);
    expect(find.text('记录一次飞行，开始绘制你的地图'), findsOneWidget);
  });
}
