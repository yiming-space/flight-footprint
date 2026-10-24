import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/route_arrow.dart';

void main() {
  test('route arrow has a concave tail and follows its direction', () {
    final path = routeArrowPath(
      center: const Offset(16, 16),
      direction: const Offset(1, 0),
      length: 28,
    );

    expect(path.contains(const Offset(4, 16)), isFalse);
    expect(path.contains(const Offset(16, 16)), isTrue);
    expect(path.contains(const Offset(29, 16)), isTrue);

    final upward = routeArrowPath(
      center: const Offset(16, 16),
      direction: const Offset(0, -1),
      length: 28,
    );
    expect(upward.contains(const Offset(16, 3)), isTrue);
    expect(upward.contains(const Offset(16, 28)), isFalse);
  });
}
