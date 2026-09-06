import 'flight.dart';

typedef AirportSearchText = String Function(String iataCode);

/// Pure query state for the flight list. UI-specific labels stay out of this
/// class so it can be reused by the page and tested without Flutter bindings.
class FlightQuery {
  const FlightQuery({this.text = '', this.airline, this.aircraftType});

  final String text;
  final String? airline;
  final String? aircraftType;

  bool get isEmpty =>
      text.trim().isEmpty && airline == null && aircraftType == null;

  FlightQuery copyWith({
    String? text,
    Object? airline = _unset,
    Object? aircraftType = _unset,
  }) => FlightQuery(
    text: text ?? this.text,
    airline: identical(airline, _unset) ? this.airline : airline as String?,
    aircraftType: identical(aircraftType, _unset)
        ? this.aircraftType
        : aircraftType as String?,
  );

  bool matches(Flight flight, {AirportSearchText? airportText}) {
    if (airline != null && _normalize(flight.airline) != _normalize(airline)) {
      return false;
    }
    if (aircraftType != null &&
        _normalize(flight.aircraftType) != _normalize(aircraftType)) {
      return false;
    }
    final tokens = _tokens(text);
    if (tokens.isEmpty) return true;
    final airportValues = <String>[
      flight.departureIata,
      flight.arrivalIata,
      if (airportText != null) airportText(flight.departureIata),
      if (airportText != null) airportText(flight.arrivalIata),
    ];
    final searchable = _normalize(
      [
        ...airportValues,
        flight.airline ?? '',
        flight.aircraftType ?? '',
        flight.flightNumber ?? '',
      ].join(' '),
    );
    return tokens.every(searchable.contains);
  }

  static List<String> _tokens(String value) =>
      _normalize(value)
          .split(' ')
          .where((token) => token.isNotEmpty)
          .toList(growable: false);

  static String _normalize(Object? value) =>
      value?.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ??
      '';
}

const _unset = Object();
