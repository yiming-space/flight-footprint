import 'package:flutter/material.dart';

import '../../ui/navigation/card_flip_route.dart';

/// Keeps the collection's vertical flip and existing route keys unchanged.
Route<T> aircraftFlipRoute<T>({
  required BuildContext context,
  required Rect sourceRect,
  Size? frontSize,
  required Widget front,
  required WidgetBuilder builder,
}) => cardFlipRoute<T>(
  context: context,
  sourceRect: sourceRect,
  frontSize: frontSize,
  front: front,
  builder: builder,
  flipAxis: Axis.vertical,
  keyPrefix: 'aircraft-flip',
);
