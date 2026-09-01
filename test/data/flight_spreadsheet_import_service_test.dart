import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flight_footprint/data/airport_catalog.dart';
import 'package:flight_footprint/data/flight_spreadsheet_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final airports = AirportCatalog.fromJsonString(
    '{"SZX":[113.8,22.6,"Shenzhen Baoan International Airport",'
    '"Shenzhen","CN","ZGSZ","large_airport",true,"CN-44",[]],'
    '"XMN":[118.1,24.5,"Xiamen Gaoqi International Airport",'
    '"Xiamen","CN","ZSAM","large_airport",true,"CN-35",[]]}',
  );

  test('parses the Umetrip CSV headers and infers an overnight arrival', () {
    final source = [
      '日期,航空公司,航班号,出发城市,出发时间,到达城市,到达时间,里程数,客票号,客票状态',
      '2026-08-28,深圳航空,ZH1234,深圳,23:40,厦门,01:20,520,781234,已出票',
    ].join('\n');
    final result = FlightSpreadsheetImportService(airports: airports).parse(
      bytes: utf8.encode(source),
      fileName: '行程记录.csv',
      now: DateTime(2026, 8, 28, 12),
    );

    expect(result.sheetName, 'CSV');
    expect(result.rows, hasLength(1));
    expect(result.issues, isEmpty);
    final flight = result.rows.single.flight;
    expect(flight.departureIata, 'SZX');
    expect(flight.arrivalIata, 'XMN');
    expect(flight.departedAt, DateTime(2026, 8, 28, 23, 40));
    expect(flight.arrivedAt, DateTime(2026, 8, 29, 1, 20));
    expect(flight.durationMinutes, 100);
    expect(flight.distanceKm, 520);
    expect(flight.note, isNull);
    expect(result.rows.single.departureAirportName, '深圳宝安T3');
    expect(result.rows.single.arrivalAirportName, '厦门高崎');
  });

  test('parses in the background without changing the import result', () async {
    final source = [
      '日期,航空公司,航班号,出发城市,出发时间,到达城市,到达时间',
      '2026-08-28,深圳航空,ZH1234,深圳,23:40,厦门,01:20',
    ].join('\n');
    final result = await FlightSpreadsheetImportService(airports: airports)
        .parseInBackground(
          bytes: utf8.encode(source),
          fileName: '行程记录.csv',
          now: DateTime(2026, 8, 28, 12),
        );

    expect(result.rows, hasLength(1));
    expect(result.issues, isEmpty);
    expect(result.rows.single.flight.departureIata, 'SZX');
    expect(result.rows.single.flight.arrivalIata, 'XMN');
  });

  test('reads an xlsx workbook with inline strings', () {
    final workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="行程" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';
    final relationships =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''';
    final sheet = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>日期</t></is></c><c r="B1" t="inlineStr"><is><t>航空公司</t></is></c><c r="C1" t="inlineStr"><is><t>航班号</t></is></c><c r="D1" t="inlineStr"><is><t>出发城市</t></is></c><c r="E1" t="inlineStr"><is><t>出发时间</t></is></c><c r="F1" t="inlineStr"><is><t>到达城市</t></is></c><c r="G1" t="inlineStr"><is><t>到达时间</t></is></c></row>
    <row r="2"><c r="A2" t="inlineStr"><is><t>2026-08-28</t></is></c><c r="B2" t="inlineStr"><is><t>深圳航空</t></is></c><c r="C2" t="inlineStr"><is><t>ZH1234</t></is></c><c r="D2" t="inlineStr"><is><t>深圳</t></is></c><c r="E2" t="inlineStr"><is><t>23:40</t></is></c><c r="F2" t="inlineStr"><is><t>厦门</t></is></c><c r="G2" t="inlineStr"><is><t>01:20</t></is></c></row>
  </sheetData>
</worksheet>''';
    final archive = Archive()
      ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
      ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', relationships))
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet));
    final bytes = ZipEncoder().encode(archive)!;
    final result = FlightSpreadsheetImportService(airports: airports).parse(
      bytes: bytes,
      fileName: '行程记录.xlsx',
      now: DateTime(2026, 8, 28, 12),
    );

    expect(result.sheetName, '行程');
    expect(result.rows, hasLength(1));
    expect(result.rows.single.flight.arrivedAt, DateTime(2026, 8, 29, 1, 20));
    expect(result.rows.single.flight.durationMinutes, 100);
  });

  test('reports invalid rows without importing them', () {
    final source = [
      '日期,航空公司,航班号,出发城市,出发时间,到达城市,到达时间',
      '2026-08-28,深圳航空,,深圳,23:40,不存在,01:20',
    ].join('\n');
    final result = FlightSpreadsheetImportService(airports: airports)
        .parse(bytes: utf8.encode(source), fileName: '行程记录.csv');
    expect(result.rows, isEmpty);
    expect(result.issues, hasLength(1));
    expect(result.issues.single.rowNumber, 2);
    expect(result.issues.single.message, contains('航班号为空'));
    expect(result.issues.single.message, contains('找不到到达城市'));
  });

  test('parses Chinese date text and ignores ticket columns', () {
    final source = [
      '日期,航空公司,航班号,出发城市,出发时间,到达城市,到达时间,里程数,客票号,客票状态',
      '2026年7月5日,深圳航空,ZH128,深圳,22:05,厦门,02:15,520公里,--,已使用',
    ].join('\n');
    final result = FlightSpreadsheetImportService(airports: airports).parse(
      bytes: utf8.encode(source),
      fileName: '行程记录.csv',
      now: DateTime(2026, 7, 1),
    );
    expect(result.rows, hasLength(1));
    final flight = result.rows.single.flight;
    expect(flight.departedAt, DateTime(2026, 7, 5, 22, 5));
    expect(flight.arrivedAt, DateTime(2026, 7, 6, 2, 15));
    expect(flight.durationMinutes, 250);
    expect(flight.note, isNull);
  });

  test(
    'resolves a Chinese airport name that is more specific than its city',
    () {
      final catalog = AirportCatalog.fromJsonString(
        '{"TYN":[112.628,37.746,"Taiyuan Wusu International Airport",'
        '"Taiyuan","CN","ZBYN","large_airport",true,"CN-14",[]],'
        '"SZX":[113.8,22.6,"Shenzhen Baoan International Airport",'
        '"Shenzhen","CN","ZGSZ","large_airport",true,"CN-44",[]]}',
      );
      final source = [
        '日期,航空公司,航班号,出发城市,出发时间,到达城市,到达时间',
        '2026-07-04,海南航空,HU7776,太原武宿,22:25,深圳宝安,01:20',
      ].join('\n');
      final result = FlightSpreadsheetImportService(airports: catalog).parse(
        bytes: utf8.encode(source),
        fileName: '行程记录.csv',
        now: DateTime(2026, 7, 1),
      );

      expect(result.issues, isEmpty);
      expect(result.rows.single.flight.departureIata, 'TYN');
      expect(result.rows.single.flight.arrivalIata, 'SZX');
    },
  );
}
