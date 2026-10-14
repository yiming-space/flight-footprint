import 'package:flight_footprint/features/stats/aircraft_artwork.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const asset = 'assets/images/aircraft/a350-900-side-right-v3.png';

  test(
    'A350-900 artwork accepts only exact normalized model and brand forms',
    () {
      for (final type in [
        'A350-900',
        '  a350-900  ',
        'A350 - 900',
        'Airbus A350-900',
        ' AIRBUS   a350 - 900 ',
        '空客 A350-900',
        '空客A350-900',
        '空中客车 A350-900',
      ]) {
        expect(aircraftArtworkAssetFor(type), asset, reason: type);
      }
    },
  );

  test('other variants and unknown labels never borrow the A350-900 image', () {
    for (final type in [
      '',
      'UNKNOWN',
      'A350',
      'A350-900 ULR',
      'A350-900ULR',
      'A350-900-ULR',
      'A350-900 NEO',
      'UNKNOWN A350-900',
      'BOEING A350-900',
      'AIRBUSINESS A350-900',
      'A350-900 / A350-1000',
      'A320',
      'C919',
    ]) {
      expect(aircraftArtworkAssetFor(type), isNull, reason: type);
    }
  });

  test('A350-1000 has its own asset and never borrows the shorter model', () {
    const stretched = 'assets/images/aircraft/a350-1000-side-right-v1.png';
    for (final type in [
      'A350-1000',
      ' a350 - 1000 ',
      'Airbus A350-1000',
      '空客A350-1000',
    ]) {
      expect(aircraftArtworkAssetFor(type), stretched, reason: type);
    }
    expect(stretched, isNot(asset));
    for (final type in [
      'Boeing A350-1000',
      'UNKNOWN A350-1000',
      'A350-1000 / A350-900',
      'A350-1000F',
      'A350-1000 ULR',
    ]) {
      expect(aircraftArtworkAssetFor(type), isNull, reason: type);
    }
  });

  test(
    'A380-800 resolves independently and does not match unmade variants',
    () {
      const a380 = 'assets/images/aircraft/a380-800-side-right-v1.png';
      for (final type in [
        'A380-800',
        ' a380 - 800 ',
        'Airbus A380-800',
        '空客A380-800',
      ]) {
        expect(aircraftArtworkAssetFor(type), a380, reason: type);
      }
      expect(a380, isNot(asset));
      expect(a380, isNot(aircraftArtworkAssetFor('A350-1000')));
      for (final type in [
        'A380',
        'A380-900',
        'A380-800F',
        'A380plus',
        'Boeing A380-800',
        'UNKNOWN A380-800',
      ]) {
        expect(aircraftArtworkAssetFor(type), isNull, reason: type);
      }
    },
  );

  test(
    'A321LR resolves independently without borrowing other A321 variants',
    () {
      const lr = 'assets/images/aircraft/a321lr-side-right-v1.png';
      for (final type in ['A321LR', ' a321lr ', 'Airbus A321LR', '空客A321LR']) {
        expect(aircraftArtworkAssetFor(type), lr, reason: type);
      }
      expect(lr, isNot(asset));
      expect(lr, isNot(aircraftArtworkAssetFor('A321NEO')));
      for (final type in [
        'A321',
        'A321XLR',
        'Boeing A321LR',
        'UNKNOWN A321LR',
        'A321LR / A321NEO',
      ]) {
        expect(aircraftArtworkAssetFor(type), isNull, reason: type);
      }
    },
  );

  test(
    'classic A330-300 has its own asset and never resolves neo variants',
    () {
      const ceo = 'assets/images/aircraft/a330-300-side-right-v1.png';
      for (final type in [
        'A330-300',
        ' a330 - 300 ',
        'Airbus A330-300',
        '空客A330-300',
      ]) {
        expect(aircraftArtworkAssetFor(type), ceo, reason: type);
      }
      expect(ceo, isNot(asset));
      expect(ceo, isNot(aircraftArtworkAssetFor('A330-900NEO')));
      for (final type in [
        'A330',
        'A330-200',
        'A330-300P2F',
        'Boeing A330-300',
        'UNKNOWN A330-300',
        'A330-300 / A330-900NEO',
      ]) {
        expect(aircraftArtworkAssetFor(type), isNull, reason: type);
      }
    },
  );

  test('Boeing models resolve to distinct assets without crossing brands', () {
    const boeingAssets = {
      'B737 MAX 8': 'assets/images/aircraft/b737-max-8-side-right-v2.png',
      'B737 MAX 9': 'assets/images/aircraft/b737-max-9-side-right-v2.png',
      'B737-800': 'assets/images/aircraft/b737-800-side-right-v2.png',
      'B777-300ER': 'assets/images/aircraft/b777-300er-side-right-v1.png',
      'B787-8': 'assets/images/aircraft/b787-8-side-right-v1.png',
      'B787-10': 'assets/images/aircraft/b787-10-side-right-v1.png',
      'B787-9': 'assets/images/aircraft/b787-9-side-right-v1.png',
    };
    for (final model in boeingAssets.entries) {
      final label = model.key;
      for (final type in [
        label,
        label.toLowerCase(),
        'Boeing $label',
        'Boeing ${label.substring(1)}',
        '波音$label',
      ]) {
        expect(aircraftArtworkAssetFor(type), model.value, reason: type);
      }
      expect(aircraftArtworkAssetFor('Airbus $label'), isNull);
      expect(aircraftArtworkAssetFor('空客$label'), isNull);
    }
    for (final type in [
      'B777',
      'B777-300',
      'B777-200LR',
      'B787',
      'B737',
      'B737 MAX',
      'B737 MAX 8-200',
      'B737 MAX 10',
      'B737-900ER',
      'B737-800BCF',
      'B787-10 / B787-9',
      'UNKNOWN B787-10',
    ]) {
      expect(aircraftArtworkAssetFor(type), isNull, reason: type);
    }
    expect(boeingAssets.values.toSet(), hasLength(7));
    expect(boeingAssets.values, isNot(contains(asset)));
  });

  test('787-9 does not borrow the stretched 787-10 or match suffixes', () {
    final middle = aircraftArtworkAssetFor('B787-9');
    expect(middle, isNotNull);
    expect(middle, isNot(aircraftArtworkAssetFor('B787-10')));
    for (final type in [
      'B787-9F',
      'B787-9 ULR',
      'UNKNOWN B787-9',
      'Airbus B787-9',
      'B787-8 / B787-9',
    ]) {
      expect(aircraftArtworkAssetFor(type), isNull, reason: type);
    }
  });

  test('new Airbus models keep their exact independently generated assets', () {
    const assets = {
      'A320-200': 'assets/images/aircraft/a320-200-side-right-v2.png',
      'A321NEO': 'assets/images/aircraft/a321neo-side-right-v2.png',
      'A330-900NEO': 'assets/images/aircraft/a330-900neo-side-right-v2.png',
    };
    for (final model in assets.entries) {
      for (final label in [
        model.key,
        model.key.toLowerCase(),
        'Airbus ${model.key}',
        '空中客车${model.key}',
      ]) {
        expect(aircraftArtworkAssetFor(label), model.value, reason: label);
      }
      for (final label in [
        'Boeing ${model.key}',
        'Embraer ${model.key}',
        'UNKNOWN ${model.key}',
        '${model.key}F',
      ]) {
        expect(aircraftArtworkAssetFor(label), isNull, reason: label);
      }
    }
    expect(assets.values.toSet(), hasLength(3));
    for (final label in [
      'A320NEO',
      'A320-200 / A321NEO',
      'A321XLR',
      'A330-800NEO',
      'A330-900NEO / A330-300',
    ]) {
      expect(aircraftArtworkAssetFor(label), isNull, reason: label);
    }
  });

  test('E190-E2 has its own artwork and cannot cross-match brands or E1', () {
    const e2 = 'assets/images/aircraft/e190-e2-side-right-v1.png';
    for (final label in [
      'E190-E2',
      ' e190 - e2 ',
      'Embraer E190-E2',
      '巴西航空工业 E190-E2',
      '巴航E190-E2',
    ]) {
      expect(aircraftArtworkAssetFor(label), e2, reason: label);
    }
    for (final label in [
      'E190',
      'E190-E1',
      'E195-E2',
      'E190-E2F',
      'Airbus E190-E2',
      'Boeing E190-E2',
      'UNKNOWN E190-E2',
      'Embraer A350-900',
      '巴航B787-8',
    ]) {
      expect(aircraftArtworkAssetFor(label), isNull, reason: label);
    }
  });

  test('all sixteen models use separate asset files', () {
    const types = [
      'A320-200',
      'A321LR',
      'A321NEO',
      'A330-300',
      'A330-900NEO',
      'A350-900',
      'A350-1000',
      'A380-800',
      'B737 MAX 8',
      'B737 MAX 9',
      'B737-800',
      'B777-300ER',
      'B787-8',
      'B787-9',
      'B787-10',
      'E190-E2',
    ];
    final paths = types.map(aircraftArtworkAssetFor).toList();
    expect(paths, everyElement(isNotNull));
    expect(paths.toSet(), hasLength(16));
  });

  test('Hero identity is stable per collection key and separates variants', () {
    final tag = aircraftArtworkHeroTag('A350-900');
    expect(aircraftArtworkHeroTag('A350-900'), tag);
    expect(tag, isNot(aircraftArtworkHeroTag('A350-1000')));
    expect(tag, isNot(aircraftArtworkHeroTag('B777-300ER')));
    expect(tag, isNot('A350-900'));
  });
}
