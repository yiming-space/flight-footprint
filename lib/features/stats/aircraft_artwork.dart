/// Prefer existing model-specific artwork, then a representative from the same
/// aircraft family. This is presentation-only: collection keys and flight data
/// retain the recorded model. Unknown labels and conflicting brands do not match.
String? aircraftArtworkAssetFor(String type) {
  var model = type.trim().toUpperCase();
  String? brand;
  for (final prefix in _artworkBrandPrefixes) {
    final match = prefix.pattern.firstMatch(model);
    if (match == null) continue;
    brand = prefix.brand;
    model = model.substring(match.end);
    break;
  }
  model = _compactArtworkModel(model)
      .replaceFirst(RegExp(r'(?:FAMILY|系列)$'), '');
  model = _artworkAliases[model] ?? model;
  if (RegExp(r'^(?:737|747|757|767|777|787)').hasMatch(model)) {
    model = 'B$model';
  } else if (brand == 'embraer' &&
      RegExp(r'^(?:170|175|190|195)').hasMatch(model)) {
    model = 'E$model';
  }

  final exact = _exactArtwork[model];
  if (exact != null) {
    return brand == null || brand == exact.brand ? exact.asset : null;
  }
  for (final family in _artworkFamilies) {
    if ((brand == null || brand == family.brand) &&
        family.pattern.hasMatch(model)) {
      return family.asset;
    }
  }
  return null;
}

String _compactArtworkModel(String value) =>
    value.replaceAll(RegExp(r'[\s-]'), '');

final _artworkBrandPrefixes = [
  (brand: 'airbus', pattern: RegExp(r'^(?:AIRBUS\s+|空中客车\s*|空客\s*)')),
  (brand: 'boeing', pattern: RegExp(r'^(?:BOEING\s+|波音\s*)')),
  (brand: 'embraer', pattern: RegExp(r'^(?:EMBRAER\s+|巴西航空工业\s*|巴航\s*)')),
  (brand: 'comac', pattern: RegExp(r'^(?:COMAC\s+|中国商飞\s*|商飞\s*)')),
];

final _exactArtwork = {
  for (final entry in _airbusArtwork.entries)
    _compactArtworkModel(entry.key): (brand: 'airbus', asset: entry.value),
  for (final entry in _boeingArtwork.entries)
    _compactArtworkModel(entry.key): (brand: 'boeing', asset: entry.value),
  for (final entry in _embraerArtwork.entries)
    _compactArtworkModel(entry.key): (brand: 'embraer', asset: entry.value),
};

// Common provider designators, plus the previous ARJ21 name. These aliases only
// choose artwork; they never rewrite or merge a user's recorded aircraft types.
const _artworkAliases = {
  'A19N': 'A319NEO',
  'A20N': 'A320NEO',
  'A21N': 'A321NEO',
  'BCS1': 'A220100',
  'BCS3': 'A220300',
  'CS100': 'A220100',
  'CS300': 'A220300',
  'A332': 'A330200',
  'A333': 'A330300',
  'A338': 'A330800',
  'A339': 'A330900NEO',
  'A359': 'A350900',
  'A35K': 'A3501000',
  'A388': 'A380800',
  'B738': 'B737800',
  'B739': 'B737900',
  'B37M': 'B737MAX7',
  'B38M': 'B737MAX8',
  'B39M': 'B737MAX9',
  'B744': 'B747400',
  'B748': 'B7478',
  'B752': 'B757200',
  'B753': 'B757300',
  'B762': 'B767200',
  'B763': 'B767300',
  'B764': 'B767400',
  'B77W': 'B777300ER',
  'B77L': 'B777200LR',
  'B772': 'B777200',
  'B773': 'B777300',
  'B788': 'B7878',
  'B789': 'B7879',
  'B78X': 'B78710',
  'E290': 'E190E2',
  'E295': 'E195E2',
  'ARJ21': 'C909',
  'ARJ21700': 'C909700',
  'ARJ21700ER': 'C909ER',
  'ARJ21700STD': 'C909STD',
};

final _artworkFamilies = [
  (
    brand: 'airbus',
    pattern: RegExp(r'^A220(?:100|300)?$'),
    asset: 'assets/images/aircraft/a220-family-side-right-v2.png',
  ),
  (
    brand: 'airbus',
    pattern: RegExp(r'^A321(?:NEO(?:LR|XLR)?|N|[12]\d{2}NX?|LR|XLR)$'),
    asset: 'assets/images/aircraft/a321neo-side-right-v2.png',
  ),
  (
    brand: 'airbus',
    pattern: RegExp(r'^A(?:319|320)(?:NEO|N|[12]\d{2}N)$'),
    asset: 'assets/images/aircraft/a320neo-family-side-right-v2.png',
  ),
  (
    brand: 'airbus',
    pattern: RegExp(r'^A(?:318|319|320|321)(?:[12]\d{2}|CEO)?$'),
    asset: 'assets/images/aircraft/a320-200-side-right-v2.png',
  ),
  (
    brand: 'airbus',
    pattern: RegExp(r'^A330(?:NEO|(?:800|900)(?:NEO)?)$'),
    asset: 'assets/images/aircraft/a330-900neo-side-right-v2.png',
  ),
  (
    brand: 'airbus',
    pattern: RegExp(r'^A330(?:(?:200|300)(?:CEO)?|CEO)?$'),
    asset: 'assets/images/aircraft/a330-300-side-right-v1.png',
  ),
  (
    brand: 'airbus',
    pattern: RegExp(r'^A350(?:900(?:ULR)?)?$'),
    asset: 'assets/images/aircraft/a350-900-side-right-v3.png',
  ),
  (
    brand: 'airbus',
    pattern: RegExp(r'^A380(?:800)?$'),
    asset: 'assets/images/aircraft/a380-800-side-right-v1.png',
  ),
  (
    brand: 'boeing',
    pattern: RegExp(r'^B737MAX(?:[789]|10|8200)?$'),
    asset: 'assets/images/aircraft/b737-max-8-side-right-v2.png',
  ),
  (
    brand: 'boeing',
    pattern: RegExp(r'^B737(?:NG|[678]00|900(?:ER)?)?$'),
    asset: 'assets/images/aircraft/b737-800-side-right-v2.png',
  ),
  (
    brand: 'boeing',
    pattern: RegExp(r'^B747(?:[1234]00|8(?:I|INTERCONTINENTAL)?)?$'),
    asset: 'assets/images/aircraft/b747-family-side-right-v1.png',
  ),
  (
    brand: 'boeing',
    pattern: RegExp(r'^B757(?:[23]00)?$'),
    asset: 'assets/images/aircraft/b757-family-side-right-v1.png',
  ),
  (
    brand: 'boeing',
    pattern: RegExp(r'^B767(?:[234]00(?:ER)?)?$'),
    asset: 'assets/images/aircraft/b767-family-side-right-v1.png',
  ),
  (
    brand: 'boeing',
    pattern: RegExp(r'^B777(?:200(?:ER|LR)?|300(?:ER)?)?$'),
    asset: 'assets/images/aircraft/b777-300er-side-right-v1.png',
  ),
  (
    brand: 'boeing',
    pattern: RegExp(r'^B787(?:8|9|10)?$'),
    asset: 'assets/images/aircraft/b787-9-side-right-v1.png',
  ),
  (
    brand: 'embraer',
    pattern: RegExp(r'^E(?:190|195)E2$'),
    asset: 'assets/images/aircraft/e190-e2-side-right-v1.png',
  ),
  (
    brand: 'embraer',
    pattern: RegExp(r'^E(?:170|175|190|195)(?:E1|STD|LR|AR)?$'),
    asset: 'assets/images/aircraft/ejet-e1-family-side-right-v1.png',
  ),
  (
    brand: 'comac',
    pattern: RegExp(r'^C919(?:100|STD|ER)?$'),
    asset: 'assets/images/aircraft/c919-family-side-right-v1.png',
  ),
  (
    brand: 'comac',
    pattern: RegExp(r'^C909(?:700|STD|ER)?$'),
    asset: 'assets/images/aircraft/c909-family-side-right-v1.png',
  ),
];

const _airbusArtwork = {
  'A320-200': 'assets/images/aircraft/a320-200-side-right-v2.png',
  'A321LR': 'assets/images/aircraft/a321lr-side-right-v1.png',
  'A321NEO': 'assets/images/aircraft/a321neo-side-right-v2.png',
  'A330-300': 'assets/images/aircraft/a330-300-side-right-v1.png',
  'A330-900NEO': 'assets/images/aircraft/a330-900neo-side-right-v2.png',
  'A350-900': 'assets/images/aircraft/a350-900-side-right-v3.png',
  'A350-1000': 'assets/images/aircraft/a350-1000-side-right-v1.png',
  'A380-800': 'assets/images/aircraft/a380-800-side-right-v1.png',
};

const _boeingArtwork = {
  'B737 MAX 8': 'assets/images/aircraft/b737-max-8-side-right-v2.png',
  'B737 MAX 9': 'assets/images/aircraft/b737-max-9-side-right-v2.png',
  'B737-800': 'assets/images/aircraft/b737-800-side-right-v2.png',
  'B777-300ER': 'assets/images/aircraft/b777-300er-side-right-v1.png',
  'B787-8': 'assets/images/aircraft/b787-8-side-right-v1.png',
  'B787-10': 'assets/images/aircraft/b787-10-side-right-v1.png',
  'B787-9': 'assets/images/aircraft/b787-9-side-right-v1.png',
};

const _embraerArtwork = {
  'E190-E2': 'assets/images/aircraft/e190-e2-side-right-v1.png',
};

String aircraftArtworkHeroTag(String key) => 'aircraft-exhibit-$key';
