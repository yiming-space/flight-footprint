import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/data/airport_localization.dart';
import 'package:flight_footprint/domain/airport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('great-circle distance is zero at the same point', () {
    final distance = AirportCatalog.greatCircleDistanceKm(
      const Airport(
        iataCode: 'A',
        longitude: 121.8,
        latitude: 31.1,
        name: 'A',
        city: 'A',
        countryCode: 'CN',
      ),
      const Airport(
        iataCode: 'B',
        longitude: 121.8,
        latitude: 31.1,
        name: 'B',
        city: 'B',
        countryCode: 'CN',
      ),
    );
    expect(distance, closeTo(0, 0.000001));
  });

  test('great-circle distance approximates Shanghai to Beijing', () {
    final distance = AirportCatalog.haversineDistanceKm(
      fromLatitude: 31.1434,
      fromLongitude: 121.8052,
      toLatitude: 40.0799,
      toLongitude: 116.6031,
    );
    expect(distance, closeTo(1099, 15));
  });

  test('catalog normalizes IATA lookups', () {
    final catalog = AirportCatalog.fromJsonString(
      '{"PVG":[121.8,31.1,"Shanghai Pudong","Shanghai","CN"]}',
    );
    expect(catalog.findByIata(' pvg ')?.city, 'Shanghai');
  });

  test('catalog keeps source metadata and searches airport aliases', () {
    final catalog = AirportCatalog.fromJsonString(
      '{"XMN":[118.127454,24.543889,"Xiamen Gaoqi International Airport",'
      '"Xiamen","CN","ZSAM","large_airport",true,"CN-35",'
      '["厦门高崎国际机场"]]}',
    );
    final airport = catalog.findByIata('XMN');
    expect(airport?.icaoCode, 'ZSAM');
    expect(airport?.type, 'large_airport');
    expect(airport?.scheduledService, isTrue);
    expect(airport?.isoRegion, 'CN-35');
    expect(airport?.keywords, contains('厦门高崎国际机场'));
    expect(catalog.search('高崎').map((item) => item.iataCode), contains('XMN'));
    expect(localizedAirportName(airport!), '厦门高崎国际机场');
    expect(localizedAirportDisplayName(airport), '厦门机场');
    expect(localizedAirportCardName(airport), '厦门高崎');
  });

  test('compact airport display stays Chinese when the city is unmapped', () {
    final airport = const Airport(
      iataCode: 'ZZZ',
      longitude: 0,
      latitude: 0,
      name: 'Example Airport',
      city: 'Example City',
      countryCode: 'ZZ',
      keywords: ['示例机场'],
    );
    expect(localizedAirportDisplayName(airport), '示例机场');
  });

  test('city search returns separate airports for the same city', () {
    final catalog = AirportCatalog.fromJsonString(
      '{"PEK":[116.596702,40.077349,"Beijing Capital", "Beijing", "CN",'
      '"ZBAA","large_airport",true,"CN-11",["北京"]],'
      '"PKX":[116.413967,39.501289,"Beijing Daxing", "Beijing", "CN",'
      '"ZBAD","large_airport",true,"CN-11",["北京"]]}',
    );
    final codes = catalog.search('北京', limit: 10).map((item) => item.iataCode);
    expect(codes, containsAll(<String>['PEK', 'PKX']));
  });

  test('country search returns a country and all of its airports', () {
    final catalog = AirportCatalog.fromJsonString(
      '{"PEK":[116.596702,40.077349,"Beijing Capital", "Beijing", "CN",'
      '"ZBAA","large_airport",true,"CN-11",[]],'
      '"PKX":[116.413967,39.501289,"Beijing Daxing", "Beijing", "CN",'
      '"ZBAD","large_airport",true,"CN-11",[]],'
      '"SZX":[113.8,22.6,"Shenzhen Baoan", "Shenzhen", "CN",'
      '"ZGSZ","large_airport",true,"CN-44",[]],'
      '"LAX":[-118.4,33.9,"Los Angeles International", "Los Angeles", "US",'
      '"KLAX","large_airport",true,"US-CA",[]]}',
    );

    expect(catalog.findCountry('中国')?.code, 'CN');
    expect(catalog.findCountry('China')?.code, 'CN');
    expect(catalog.findCountry('US')?.name, '美国');
    expect(
      catalog.airportsForCountry('CN').map((airport) => airport.iataCode),
      containsAll(<String>['PEK', 'PKX', 'SZX']),
    );
    expect(catalog.searchCountries('美国').single.airportCount, 1);
  });

  test('search matches a specific Chinese airport name against its record', () {
    final catalog = AirportCatalog.fromJsonString(
      '{"TYN":[112.628,37.746,"Taiyuan Wusu International Airport",'
      '"Taiyuan","CN","ZBYN","large_airport",true,"CN-14",[]]}',
    );
    expect(catalog.search('太原武宿').first.iataCode, 'TYN');
  });

  test('record cards keep the specific airport name and terminal', () {
    const airport = Airport(
      iataCode: 'SZX',
      longitude: 113.8,
      latitude: 22.6,
      name: 'Shenzhen Baoan International Airport',
      city: 'Shenzhen',
      countryCode: 'CN',
    );
    expect(localizedAirportCardName(airport), '深圳宝安T3');
  });

  test(
    'flight cards split long foreign airport names into city and landmark',
    () {
      const airport = Airport(
        iataCode: 'JNB',
        longitude: 28.2,
        latitude: -26.1,
        name: 'O. R. Tambo International Airport',
        city: 'Johannesburg',
        countryCode: 'ZA',
      );
      expect(localizedAirportCardDisplayName(airport), '约翰内斯堡\n坦博');
    },
  );

  test('short airport card names stay on one line', () {
    const airport = Airport(
      iataCode: 'SZX',
      longitude: 113.8,
      latitude: 22.6,
      name: 'Shenzhen Baoan International Airport',
      city: 'Shenzhen',
      countryCode: 'CN',
    );
    expect(localizedAirportCardDisplayName(airport), '深圳宝安T3');
  });

  test('airport cards keep city-only international names readable', () {
    const airport = Airport(
      iataCode: 'HKG',
      longitude: 113.9185,
      latitude: 22.308,
      name: 'Hong Kong International Airport',
      city: 'Hong Kong',
      countryCode: 'HK',
    );
    expect(localizedAirportCardName(airport), '香港国际T1');
  });

  test('airport cards remove source suffixes and parenthesized codes', () {
    const airport = Airport(
      iataCode: 'DYG',
      longitude: 110.443,
      latitude: 29.102,
      name: 'Zhangjiajie Hehua International Airport',
      city: 'Zhangjiajie',
      countryCode: 'CN',
      keywords: ['张家界荷花国际机场，荷花'],
    );
    expect(localizedAirportCardName(airport), '张家界荷花');
    expect(localizedCountryFlag('CN'), '🇨🇳');
  });

  test('airport picker fallback keeps the real English airport name', () {
    const airport = Airport(
      iataCode: 'ZZZ',
      longitude: 0,
      latitude: 0,
      name: 'Example International Airport',
      city: 'Example City',
      countryCode: 'ZZ',
    );
    expect(localizedAirportName(airport), 'Example International Airport（ZZZ）');
    expect(localizedAirportCardName(airport), 'Example International Airport');
  });
}
