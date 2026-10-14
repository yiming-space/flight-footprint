/// Model-specific artwork is opt-in: unknown types never borrow a different
/// aircraft's outline. Manufacturer prefixes cannot cross-match brands.
String? aircraftArtworkAssetFor(String type) {
  final normalized = type
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*-\s*'), '-');
  final airbusPrefix = RegExp(r'^(?:AIRBUS\s+|空中客车\s*|空客\s*)');
  if (airbusPrefix.hasMatch(normalized)) {
    return _airbusArtwork[normalized.replaceFirst(airbusPrefix, '')];
  }
  final boeingPrefix = RegExp(r'^(?:BOEING\s+|波音\s*)');
  if (boeingPrefix.hasMatch(normalized)) {
    final model = normalized.replaceFirst(boeingPrefix, '');
    return _boeingArtwork[model] ?? _boeingArtwork['B$model'];
  }
  final embraerPrefix = RegExp(r'^(?:EMBRAER\s+|巴西航空工业\s*|巴航\s*)');
  if (embraerPrefix.hasMatch(normalized)) {
    return _embraerArtwork[normalized.replaceFirst(embraerPrefix, '')];
  }
  return _airbusArtwork[normalized] ??
      _boeingArtwork[normalized] ??
      _embraerArtwork[normalized];
}

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
