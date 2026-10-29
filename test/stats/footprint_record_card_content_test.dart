import 'package:flight_footprint/data/backup_codec.dart';
import 'package:flight_footprint/domain/visited_place.dart';
import 'package:flight_footprint/features/stats/footprint_record_card_content.dart';
import 'package:flight_footprint/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/core/localization/app_strings.dart';

Widget _host(VisitedPlace place, String language) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.dark(),
  home: Scaffold(body: FootprintRecordCardContent(place: place)),
);

VisitedPlace _place(FootprintRecordSource source) => VisitedPlace(
  id: 'p1',
  name: '上海',
  latitude: 31.2,
  longitude: 121.5,
  visitedAt: DateTime.utc(2025, 1, 1),
  createdAt: DateTime.utc(2025, 1, 1),
  updatedAt: DateTime.utc(2025, 1, 1),
  source: source,
);

void main() {
  testWidgets('shows manual, photo, and unknown source labels in Chinese', (
    tester,
  ) async {
    for (final entry in [
      (FootprintRecordSource.manual, '手动添加'),
      (FootprintRecordSource.photo, '照片导入'),
      (FootprintRecordSource.unknown, '来源未知'),
    ]) {
      await tester.pumpWidget(_host(_place(entry.$1), 'zh'));
      expect(find.textContaining(entry.$2), findsOneWidget);
    }
  });

  testWidgets('shows matching English source labels', (tester) async {
    for (final entry in [
      (FootprintRecordSource.manual, 'Manually added'),
      (FootprintRecordSource.photo, 'Imported from photos'),
      (FootprintRecordSource.unknown, 'Source unknown'),
    ]) {
      await tester.pumpWidget(_host(_place(entry.$1), 'en'));
      expect(find.textContaining(entry.$2), findsOneWidget);
    }
  });

  testWidgets('legacy backup record is labeled source unknown', (tester) async {
    final old = BackupCodec.decode(
      '{"format":"flight-footprint-backup","version":1,"flights":[],"visitedPlaces":['
      '{"id":"legacy","name":"上海","latitude":31.2,"longitude":121.5,'
      '"visitedAt":"2025-01-01T00:00:00Z","createdAt":"2025-01-01T00:00:00Z",'
      '"updatedAt":"2025-01-01T00:00:00Z"}]}',
    ).visitedPlaces.single;
    await tester.pumpWidget(_host(old, 'zh'));
    expect(find.textContaining('来源未知'), findsOneWidget);
    expect(old.source, FootprintRecordSource.unknown);
  });
}
