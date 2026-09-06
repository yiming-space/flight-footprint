import 'package:flutter_test/flutter_test.dart';
import 'package:flight_footprint/features/map/map_models.dart';

void main() {
  test('map labels do not preserve Chinese line-break opportunities', () {
    expect(normalizedMapLabel('哥\n伦\n比\n亚'), '哥伦比亚');
    expect(normalizedMapLabel('胡 志 明 市', countryCode: 'VN'), '胡志明市');
    expect(normalizedMapLabel('开\u200B普\u200B敦'), '开普敦');
  });

  test('Latin map labels keep readable word spacing', () {
    expect(normalizedMapLabel('New\nYork'), 'New York');
  });
}
