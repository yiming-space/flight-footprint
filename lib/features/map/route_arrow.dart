import 'dart:ui';

/// Builds the filled, concave-tail arrow used by every map renderer.
///
/// [direction] points toward the tip. The tail notch points back into the
/// arrow, producing a compact dart shape rather than a plain triangle.
Path routeArrowPath({
  required Offset center,
  required Offset direction,
  required double length,
}) {
  final distance = direction.distance;
  if (distance <= 0 || length <= 0) return Path();
  final tangent = direction / distance;
  final normal = Offset(-tangent.dy, tangent.dx);
  final halfLength = length / 2;
  final halfWidth = length * .36;
  final tip = center + tangent * halfLength;
  final upperTail = center - tangent * halfLength - normal * halfWidth;
  final notch = center - tangent * (length * .16);
  final lowerTail = center - tangent * halfLength + normal * halfWidth;
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(upperTail.dx, upperTail.dy)
    ..lineTo(notch.dx, notch.dy)
    ..lineTo(lowerTail.dx, lowerTail.dy)
    ..close();
}
