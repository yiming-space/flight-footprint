# Airport time zone index

`assets/data/airport-timezones.json` is an offline IATA-to-IANA zone index
derived on 2026-10-22 from the OpenFlights airport-only snapshot:

- Source: https://github.com/jpatokal/openflights/blob/master/data/airports.dat
- Data format and license: https://openflights.org/data.php
- Imported: 5,515 airport codes with a named IANA zone.

Only the airport code and named zone are retained. The snapshot's numerical
UTC offset and DST indicator are deliberately discarded; dated offset rules
come from the `timezone` package's IANA database. The airport-zone snapshot is
not a live service. Missing or ambiguous airport assignments must remain
unknown rather than being inferred from country or device time zone.

This index supports local-time input and display. It does not reinterpret or
rewrite historical saved flight instants.
