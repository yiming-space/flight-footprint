import 'package:flutter_test/flutter_test.dart';

import 'package:flight_footprint/app/app_links.dart';

void main() {
  test('official link is a canonical GitHub repository URL', () {
    expect(
      AppLinks.githubRepository?.toString(),
      'https://github.com/yiming-space/flight-footprint',
    );
    expect(
      AppLinks.githubUpdateManifest?.toString(),
      'https://raw.githubusercontent.com/yiming-space/flight-footprint/main/update.json',
    );
  });
}
