import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';

/// Keep the required credit readable without covering the flight artwork.
class DetailMapAttribution extends StatelessWidget {
  const DetailMapAttribution({super.key, required this.topOffset});
  final double topOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Align(
      alignment: Alignment.topLeft,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, topOffset + 38, 76, 0),
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: const StadiumBorder(),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              builder: (context) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final source in const [
                      ('OpenFreeMap', 'https://openfreemap.org/'),
                      ('© OpenMapTiles', 'https://openmaptiles.org/'),
                      (
                        '© OpenStreetMap contributors',
                        'https://www.openstreetmap.org/copyright',
                      ),
                    ])
                      ListTile(
                        title: Text(source.$1),
                        onTap: () => launchUrl(
                          Uri.parse(source.$2),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.strings.t('close')),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text(
              '© OpenMapTiles · © OpenStreetMap',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ),
      ),
    );
  }
}
