# World country geometry

The app bundles Natural Earth 1:50m Admin 0 country geometry. Natural Earth
states that its vector and raster map data are public domain:
https://www.naturalearthdata.com/about/terms-of-use/

Official source GeoJSON:
https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson

The bundled geometry was compared feature-by-feature with the official source
on 2026-10-28. All 242 geometries and their order matched exactly. The bundle
retains only `ISO_A2_EH`, `ADMIN`, `CONTINENT`, and `REGION_UN` from the source;
coordinates were not changed. The source file SHA-256 is recorded in
`world-countries-50m.geo.json`.

Features whose ISO assignment is `-99` are left unassigned and are not used to
light a known country. Natural Earth 1:50m is generalized overview geometry;
small islands and detailed coastlines may be omitted. Its continent property
describes the country feature and is not a continent-boundary geometry for
transcontinental countries.
