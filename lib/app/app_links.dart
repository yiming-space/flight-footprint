/// Public links used by the app and the release/update checker.
///
/// The URL can be supplied at build time with
/// `--dart-define=FLIGHT_FOOTPRINT_GITHUB_URL=...`. Keeping this as a
/// dart-define means forks can point to their own repository without editing
/// the application code. The official release build will set the value to the
/// project's public GitHub repository.
abstract final class AppLinks {
  static const githubRepositoryUrl = String.fromEnvironment(
    'FLIGHT_FOOTPRINT_GITHUB_URL',
    defaultValue: 'https://github.com/yiming-space/flight-footprint',
  );

  static Uri? get githubRepository {
    final raw = githubRepositoryUrl.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      return null;
    }
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    final parts = segments.toList(growable: false);
    if (parts.length < 2) return null;
    final repository = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    if (repository.isEmpty) return null;
    return Uri.https('github.com', '/${parts[0]}/$repository');
  }

  static ({String owner, String repository})? get githubRepositoryParts {
    final uri = githubRepository;
    if (uri == null) return null;
    final parts = uri.pathSegments;
    if (parts.length != 2) return null;
    return (owner: parts[0], repository: parts[1]);
  }

  static Uri? get githubUpdateManifest {
    final parts = githubRepositoryParts;
    if (parts == null) return null;
    return Uri.https(
      'raw.githubusercontent.com',
      '/${parts.owner}/${parts.repository}/main/update.json',
    );
  }
}
