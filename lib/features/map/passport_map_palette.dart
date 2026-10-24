import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// Land color used by the transparent flight-passport map artwork.
///
/// Continent exploration cards use this same color for their unlocked state so
/// the world map and its individual stamps share one palette.
Color passportMapLandFill({required bool light}) => light
    ? Color.lerp(AppThemeColors.light.actionFill, const Color(0xFFC0C7CD), .55)!
    : const Color(0xAD6C8291);
