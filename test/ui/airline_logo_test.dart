import 'dart:async';
import 'dart:ui' as ui;

import 'package:flight_footprint/ui/widgets/airline_logo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('unknown IATA code stays local and keeps badge dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(host(const AirlineLogo(iataCode: 'ZZ')));

    expect(find.text('ZZ'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(AirlineLogo)), const Size.square(36));
  });

  testWidgets('malformed input never becomes a remote image URL', (
    tester,
  ) async {
    for (final code in [null, '', '../CA', 'CCA', 'C A', '汉字']) {
      await tester.pumpWidget(host(AirlineLogo(iataCode: code)));
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.flight_rounded), findsOneWidget);
    }
  });

  testWidgets('known code displays original image with contain fit', (
    tester,
  ) async {
    final provider = MemoryImage(
      Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        0x00,
        0x00,
        0x00,
        0x0d,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1f,
        0x15,
        0xc4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0b,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9c,
        0x63,
        0x60,
        0x00,
        0x02,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x7a,
        0x5e,
        0xab,
        0x3f,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4e,
        0x44,
        0xae,
        0x42,
        0x60,
        0x82,
      ]),
    );
    await tester.pumpWidget(
      host(AirlineLogo(iataCode: ' ca ', imageProvider: provider)),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.color, isNull);
    expect(image.image, provider);
    expect(find.byType(ClipOval), findsOneWidget);
    // Keep the full rectangular image safely inside the circular plate.
    expect(tester.getSize(find.byType(Image)).width, lessThan(36 * .7072));
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo plate is circular at custom size', (tester) async {
    await tester.pumpWidget(host(const AirlineLogo(iataCode: 'ZZ', size: 48)));

    final plate = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(AirlineLogo),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((plate.decoration as BoxDecoration).shape, BoxShape.circle);
    expect(tester.getSize(find.byType(ClipOval)), const Size.square(48));
    expect(find.text('ZZ'), findsOneWidget);
  });

  testWidgets('failed image falls back to code without affecting layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const AirlineLogo(iataCode: 'HU', imageProvider: _FailedImage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('HU'), findsOneWidget);
    expect(tester.getSize(find.byType(AirlineLogo)), const Size.square(36));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports actual image color after a frame', (tester) async {
    final provider = _DeferredImage();
    final reported = <Color>[];
    SchedulerPhase? deliveredPhase;
    await tester.pumpWidget(
      host(
        AirlineLogo(
          iataCode: 'CA',
          imageProvider: provider,
          onColorResolved: (color) {
            reported.add(color);
            deliveredPhase = SchedulerBinding.instance.schedulerPhase;
          },
        ),
      ),
    );
    provider.result.complete(
      await tester.runAsync(() => _solidImageInfo(const Color(0xFFDC1E28))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(reported, [const Color(0xFFDC1E28)]);
    expect(deliveredPhase, SchedulerPhase.postFrameCallbacks);
    expect(tester.takeException(), isNull);
  });

  testWidgets('code changes discard color from the old image', (tester) async {
    final first = _DeferredImage();
    final second = _DeferredImage();
    final reported = <Color>[];
    await tester.pumpWidget(
      host(
        AirlineLogo(
          iataCode: 'CA',
          imageProvider: first,
          onColorResolved: reported.add,
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        AirlineLogo(
          iataCode: 'HU',
          imageProvider: second,
          onColorResolved: reported.add,
        ),
      ),
    );
    first.result.complete(
      await tester.runAsync(() => _solidImageInfo(const Color(0xFFDC1E28))),
    );
    second.result.complete(
      await tester.runAsync(() => _solidImageInfo(const Color(0xFF1450DC))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(reported, [const Color(0xFF1450DC)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed logo cannot report a late image color', (tester) async {
    final provider = _DeferredImage();
    final reported = <Color>[];
    await tester.pumpWidget(
      host(
        AirlineLogo(
          iataCode: 'CA',
          imageProvider: provider,
          onColorResolved: reported.add,
        ),
      ),
    );
    await tester.pumpWidget(host(const SizedBox.shrink()));
    provider.result.complete(
      await tester.runAsync(() => _solidImageInfo(const Color(0xFFDC1E28))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(reported, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<ImageInfo> _solidImageInfo(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return ImageInfo(image: await picture.toImage(4, 4));
  } finally {
    picture.dispose();
  }
}

class _DeferredImage extends ImageProvider<_DeferredImage> {
  final result = Completer<ImageInfo>();

  @override
  Future<_DeferredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _DeferredImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(result.future);
}

class _FailedImage extends ImageProvider<_FailedImage> {
  const _FailedImage();

  @override
  Future<_FailedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FailedImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(StateError('Simulated offline image')),
  );
}
