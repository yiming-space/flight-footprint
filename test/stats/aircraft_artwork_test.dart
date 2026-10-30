import 'package:flight_footprint/features/stats/aircraft_artwork.dart';
import 'package:flutter_test/flutter_test.dart';

const _specificAssets = {
  'A320-200': 'assets/images/aircraft/a320-200-side-right-v2.webp',
  'A321LR': 'assets/images/aircraft/a321lr-side-right-v1.webp',
  'A321NEO': 'assets/images/aircraft/a321neo-side-right-v2.webp',
  'A330-300': 'assets/images/aircraft/a330-300-side-right-v1.webp',
  'A330-900NEO': 'assets/images/aircraft/a330-900neo-side-right-v2.webp',
  'A350-900': 'assets/images/aircraft/a350-900-side-right-v3.webp',
  'A350-1000': 'assets/images/aircraft/a350-1000-side-right-v1.webp',
  'A380-800': 'assets/images/aircraft/a380-800-side-right-v1.webp',
  'B737 MAX 8': 'assets/images/aircraft/b737-max-8-side-right-v2.webp',
  'B737 MAX 9': 'assets/images/aircraft/b737-max-9-side-right-v2.webp',
  'B737-800': 'assets/images/aircraft/b737-800-side-right-v2.webp',
  'B777-300ER': 'assets/images/aircraft/b777-300er-side-right-v1.webp',
  'B787-8': 'assets/images/aircraft/b787-8-side-right-v1.webp',
  'B787-9': 'assets/images/aircraft/b787-9-side-right-v1.webp',
  'B787-10': 'assets/images/aircraft/b787-10-side-right-v1.webp',
  'E190-E2': 'assets/images/aircraft/e190-e2-side-right-v1.webp',
};

void main() {
  test('all sixteen specific assets retain priority and separate files', () {
    for (final entry in _specificAssets.entries) {
      expect(
        aircraftArtworkAssetFor(entry.key),
        entry.value,
        reason: entry.key,
      );
      expect(aircraftArtworkAssetFor(entry.key.toLowerCase()), entry.value);
    }
    expect(_specificAssets.values.toSet(), hasLength(16));
  });

  test(
    'spacing and matching manufacturer prefixes preserve specific artwork',
    () {
      final expected = _specificAssets['A350-900'];
      for (final label in [
        '  a350 - 900  ',
        ' AIRBUS   a350 - 900 ',
        '空客A350-900',
        '空中客车 A350-900',
      ]) {
        expect(aircraftArtworkAssetFor(label), expected, reason: label);
      }
      expect(
        aircraftArtworkAssetFor('Boeing 737MAX9'),
        _specificAssets['B737 MAX 9'],
      );
      expect(
        aircraftArtworkAssetFor('波音 787 - 10'),
        _specificAssets['B787-10'],
      );
      expect(
        aircraftArtworkAssetFor('巴航 E190 - E2'),
        _specificAssets['E190-E2'],
      );
    },
  );

  test('known passenger variants fall back only within their family', () {
    const families = {
      'A318': 'a320-family-side-right-v1.webp',
      'A319-115': 'a320-family-side-right-v1.webp',
      'A320-214': 'a320-family-side-right-v1.webp',
      'A321-231': 'a321-family-side-right-v1.webp',
      'A319NEO': 'a320neo-family-side-right-v2.webp',
      'A320-251N': 'a320neo-family-side-right-v2.webp',
      'A321XLR': 'a321neo-side-right-v2.webp',
      'A321-271NX': 'a321neo-side-right-v2.webp',
      'A330-200': 'a330-family-side-right-v1.webp',
      'A330-800': 'a330-900neo-side-right-v2.webp',
      'A350-900 ULR': 'a350-900-side-right-v3.webp',
      'A350系列': 'a350-900-side-right-v3.webp',
      'A380': 'a380-800-side-right-v1.webp',
      '737 NG': 'b737-family-side-right-v1.webp',
      'B737-900ER': 'b737-family-side-right-v1.webp',
      '737 MAX 10': 'b737-max-8-side-right-v2.webp',
      'B737 MAX 8-200': 'b737-max-8-side-right-v2.webp',
      'B777-200LR': 'b777-300er-side-right-v1.webp',
      'B777 FAMILY': 'b777-300er-side-right-v1.webp',
      'B787': 'b787-9-side-right-v1.webp',
      'E175': 'ejet-e1-family-side-right-v1.webp',
      'Embraer 190 LR': 'ejet-e1-family-side-right-v1.webp',
      'E195-E2': 'e190-e2-side-right-v1.webp',
    };
    for (final entry in families.entries) {
      expect(
        aircraftArtworkAssetFor(entry.key),
        'assets/images/aircraft/${entry.value}',
        reason: entry.key,
      );
    }
  });

  test(
    'number-only model labels resolve through anchored manufacturer families',
    () {
      const known = {
        '737-800': 'b737-800-side-right-v2.webp',
        '737800': 'b737-800-side-right-v2.webp',
        '737': 'b737-family-side-right-v1.webp',
        '737NG': 'b737-family-side-right-v1.webp',
        '320-200': 'a320-200-side-right-v2.webp',
        '320200': 'a320-200-side-right-v2.webp',
        '320': 'a320-family-side-right-v1.webp',
        'Airbus 320-214': 'a320-family-side-right-v1.webp',
        'Airbus 320-251N': 'a320neo-family-side-right-v2.webp',
        'Boeing 737MAX9': 'b737-max-9-side-right-v2.webp',
        '350-900': 'a350-900-side-right-v3.webp',
        '3501000': 'a350-1000-side-right-v1.webp',
        '330-300': 'a330-300-side-right-v1.webp',
        '380': 'a380-800-side-right-v1.webp',
        '220-300': 'a220-family-side-right-v2.webp',
        '738': 'b737-800-side-right-v2.webp',
        '359': 'a350-900-side-right-v3.webp',
      };
      for (final entry in known.entries) {
        expect(
          aircraftArtworkAssetFor(entry.key),
          'assets/images/aircraft/${entry.value}',
          reason: entry.key,
        );
      }
    },
  );

  test(
    'new mainstream families resolve to their independent side profiles',
    () {
      const families = {
        'Airbus A320neo': 'a320neo-family-side-right-v2.webp',
        'A220-100': 'a220-family-side-right-v2.webp',
        'A220-300': 'a220-family-side-right-v2.webp',
        'B747-400': 'b747-family-side-right-v1.webp',
        'Boeing 747-8I': 'b747-family-side-right-v1.webp',
        'B757-300': 'b757-family-side-right-v1.webp',
        'B767-300ER': 'b767-family-side-right-v1.webp',
        '中国商飞C919': 'c919-family-side-right-v1.webp',
        'COMAC C909': 'c909-family-side-right-v1.webp',
        'ARJ21-700ER': 'c909-family-side-right-v1.webp',
        'E190-E1': 'ejet-e1-family-side-right-v1.webp',
      };
      for (final entry in families.entries) {
        expect(
          aircraftArtworkAssetFor(entry.key),
          'assets/images/aircraft/${entry.value}',
          reason: entry.key,
        );
      }
      expect(families.values.toSet(), hasLength(8));
    },
  );

  test('core family labels have four independent representatives', () {
    const families = {
      'A330': 'a330-family-side-right-v1.webp',
      'A321': 'a321-family-side-right-v1.webp',
      'A320': 'a320-family-side-right-v1.webp',
      'B737': 'b737-family-side-right-v1.webp',
    };
    for (final entry in families.entries) {
      final expected = 'assets/images/aircraft/${entry.value}';
      for (final label in [
        entry.key,
        '${entry.key} FAMILY',
        '${entry.key}系列',
      ]) {
        expect(aircraftArtworkAssetFor(label), expected, reason: label);
      }
      final brand = entry.key.startsWith('A') ? '空客' : '波音';
      expect(aircraftArtworkAssetFor('$brand${entry.key}'), expected);
    }
    expect(families.values.toSet(), hasLength(4));
    expect(aircraftArtworkAssetFor('737'), aircraftArtworkAssetFor('B737'));
    expect(
      aircraftArtworkAssetFor('A321'),
      isNot(aircraftArtworkAssetFor('A320')),
    );
  });

  test(
    'provider designators respect specific priority and family boundaries',
    () {
      const aliases = {
        'A20N': 'A320NEO',
        'A21N': 'A321NEO',
        'BCS3': 'A220-300',
        'A332': 'A330-200',
        'A338': 'A330-800',
        'A359': 'A350-900',
        'A35K': 'A350-1000',
        'B738': 'B737-800',
        'B38M': 'B737 MAX 8',
        'B39M': 'B737 MAX 9',
        'B744': 'B747-400',
        'B752': 'B757-200',
        'B763': 'B767-300',
        'B77W': 'B777-300ER',
        'B78X': 'B787-10',
        'E290': 'E190-E2',
        'E295': 'E195-E2',
        'CS100': 'A220-100',
        'ARJ21': 'C909',
      };
      for (final entry in aliases.entries) {
        expect(
          aircraftArtworkAssetFor(entry.key),
          isNotNull,
          reason: entry.key,
        );
        expect(
          aircraftArtworkAssetFor(entry.key),
          aircraftArtworkAssetFor(entry.value),
          reason: entry.key,
        );
      }
    },
  );

  test('engine generations do not borrow each other\'s representatives', () {
    for (final pair in [
      ('A320', 'A320neo'),
      ('A321', 'A321neo'),
      ('A330-200', 'A330-800'),
      ('B737-900ER', 'B737 MAX 10'),
      ('E190', 'E190-E2'),
    ]) {
      expect(
        aircraftArtworkAssetFor(pair.$1),
        isNot(aircraftArtworkAssetFor(pair.$2)),
      );
    }
  });

  test('unknowns, unsupported shapes, mixed labels and brand conflicts stay neutral', () {
    for (final label in [
      '',
      'UNKNOWN',
      'UNKNOWN A350-900',
      'A320ISH',
      'B737XYZ',
      'AIRBUSINESS A350-900',
      'A350-900 / A350-1000',
      'B787-8 / B787-9',
      'A350-900 NEO',
      'A350-1000F',
      'A380-900',
      'A330-300P2F',
      'B737-800BCF',
      'B787-9 ULR',
      'A220-900',
      'B747-900',
      'C929',
      'ATR72',
      'CRJ900',
      'BOEING A350-900',
      'Airbus B787',
      'Embraer A320neo',
      'Boeing C919',
      'COMAC B737',
      '73700',
      '737XYZ',
      '3200',
      '320ISH',
      'Flight 737',
      'N737800',
      'Airbus 737',
      'Boeing 320',
      '3509000',
      'Flight 737',
      'N737800',
      '空客E190',
      '波音BCS3',
    ]) {
      expect(aircraftArtworkAssetFor(label), isNull, reason: label);
    }
  });

  test(
    'real device labels and manufacturer customer codes use family artwork',
    () {
      const examples = {
        '空客321-231（sl）': 'a321-family-side-right-v1.webp',
        '空客 A321-231 (SL)': 'a321-family-side-right-v1.webp',
        'AIRBUS321-231（sharklets）': 'a321-family-side-right-v1.webp',
        '波音737－8L9（中型）': 'b737-family-side-right-v1.webp',
        '737-87l（wl）': 'b737-family-side-right-v1.webp',
        'Boeing737-8MG': 'b737-family-side-right-v1.webp',
        '空客330-343': 'a330-family-side-right-v1.webp',
        '空客350-941': 'a350-900-side-right-v3.webp',
        '波音777-36N': 'b777-300er-side-right-v1.webp',
        '波音737-800（WL）': 'b737-800-side-right-v2.webp',
      };
      for (final entry in examples.entries) {
        expect(
          aircraftArtworkAssetFor(entry.key),
          'assets/images/aircraft/${entry.value}',
          reason: entry.key,
        );
      }
      expect(aircraftArtworkAssetFor('波音321-231（SL）'), isNull);
      expect(aircraftArtworkAssetFor('空客321-231 / 737-800'), isNull);
    },
  );

  test('shared family artwork does not share collection Hero identities', () {
    expect(
      aircraftArtworkAssetFor('B767-200'),
      aircraftArtworkAssetFor('B767-300ER'),
    );
    expect(
      aircraftArtworkHeroTag('B767-200'),
      isNot(aircraftArtworkHeroTag('B767-300ER')),
    );
    expect(
      aircraftArtworkHeroTag('A350-900'),
      aircraftArtworkHeroTag('A350-900'),
    );
  });
}
