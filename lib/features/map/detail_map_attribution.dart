import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_strings.dart';
import '../../ui/theme/app_theme.dart';

/// Keep the required credit readable without covering the flight artwork.
class DetailMapAttribution extends StatelessWidget {
  const DetailMapAttribution({super.key, this.bottomOffset = 8});
  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final light = Theme.of(context).brightness == Brightness.light;
    return Align(
      alignment: Alignment.bottomLeft,
      child: SafeArea(
        top: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, bottomOffset),
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: light
                  ? colors.textSecondary
                  : AppColors.detailMapNightLabel,
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
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
            child: Text(
              '© OpenMapTiles · © OpenStreetMap',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w400,
                shadows: [
                  Shadow(
                    color: light ? Colors.white : AppColors.detailMapNightWater,
                    offset: const Offset(0, .5),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
