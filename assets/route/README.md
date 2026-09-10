# Tokyo–Shinagawa railway alignment

Data © OpenStreetMap contributors, licensed under ODbL 1.0:
https://www.openstreetmap.org/copyright

The Overpass snapshot contains standard-gauge railways in the station corridor.
Run `node tests/build_track_route.cjs` from the project root to rebuild the
cached route. Only connected ways named 東海道新幹線 with no service tag are used;
the route connects track nodes near Tokyo and Shinagawa (170 nodes, about 6.7 km).
This is a visualization alignment, not a dispatcher-approved running path.

OSM does not provide a surveyed vertical rail profile here. The preview uses
an initial WGS84 ellipsoid height of 46 m, with bounded ±8 m visual surface
fitting against detailed tiles. Station canopies and photogrammetry offsets
can still require a surveyed profile / local calibration. Do not interpret
the current height as engineering-grade track elevation.
