extends Control
## Fixed Zhengzhou-south corridor overlay for the OpenRailwayMap mini map.

const TILE_SIZE := 256.0
const MAP_ZOOM := 9
const ROUTE_LENGTH_M := 50000.0

# Vector2(longitude, latitude). Station coordinates are from OpenStreetMap.
var route_points := PackedVector2Array([
	Vector2(113.6536663, 34.7475076), # Zhengzhou
	Vector2(113.6635, 34.7310),
	Vector2(113.6784178, 34.7118061), # Wulibao
	Vector2(113.6960, 34.6900),
	Vector2(113.7409481, 34.6551972), # Xiaolizhuang
	Vector2(113.7750, 34.5850),
	Vector2(113.7905797, 34.4973369),
	Vector2(113.7692387, 34.3835787),
	Vector2(113.7656003, 34.2964464), # about 50 km south of Zhengzhou
])

var stations := [
	{"name": "郑州站", "geo": Vector2(113.6536663, 34.7475076)},
	{"name": "五里堡", "geo": Vector2(113.6784178, 34.7118061)},
	{"name": "小李庄", "geo": Vector2(113.7409481, 34.6551972)},
]

var center_geo := Vector2(113.704, 34.522)
var progress_m := 0.0


func set_progress(distance_m: float) -> void:
	progress_m = clampf(distance_m, 0.0, ROUTE_LENGTH_M)
	queue_redraw()


func _draw() -> void:
	var screen_route := PackedVector2Array()
	for point in route_points:
		screen_route.append(_project(point))
	if screen_route.size() >= 2:
		draw_polyline(screen_route, Color(0.02, 0.03, 0.04, 0.82), 6.0, true)
		draw_polyline(screen_route, Color("ff5a36"), 2.8, true)

	for station in stations:
		var station_position := _project(station.geo)
		draw_circle(station_position, 5.0, Color(0.04, 0.08, 0.10, 0.92))
		draw_circle(station_position, 2.8, Color("fff5d6"))
		draw_string(ThemeDB.fallback_font, station_position + Vector2(7.0, -5.0),
			String(station.name), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color.WHITE)

	var train_geo := _route_geo_at_distance(progress_m)
	var marker := _project(train_geo)
	draw_circle(marker + Vector2(1.2, 1.6), 8.5, Color(0, 0, 0, 0.5))
	draw_circle(marker, 7.0, Color("36d8ff"))
	draw_circle(marker, 2.8, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(8.0, 17.0), "0001  京广铁路",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("fff2cf"))
	draw_string(ThemeDB.fallback_font, Vector2(8.0, size.y - 8.0), "郑州站 → 南向 50 km",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("e9f2f5"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.72, 0.82, 0.86, 0.78), false, 1.0)


func _route_geo_at_distance(distance_m: float) -> Vector2:
	if route_points.size() < 2:
		return center_geo
	var segment_lengths := PackedFloat32Array()
	var total_length := 0.0
	for index in range(route_points.size() - 1):
		var length := _project(route_points[index]).distance_to(_project(route_points[index + 1]))
		segment_lengths.append(length)
		total_length += length
	var target := clampf(distance_m / ROUTE_LENGTH_M, 0.0, 1.0) * total_length
	for index in range(segment_lengths.size()):
		if target <= segment_lengths[index]:
			return route_points[index].lerp(route_points[index + 1],
				target / maxf(segment_lengths[index], 0.001))
		target -= segment_lengths[index]
	return route_points[route_points.size() - 1]


func _project(geo: Vector2) -> Vector2:
	var world_size := TILE_SIZE * pow(2.0, MAP_ZOOM)
	return _mercator(geo, world_size) - _mercator(center_geo, world_size) + size * 0.5


func _mercator(geo: Vector2, world_size: float) -> Vector2:
	var latitude := clampf(geo.y, -85.05112878, 85.05112878)
	var sin_latitude := sin(deg_to_rad(latitude))
	return Vector2(
		(geo.x + 180.0) / 360.0 * world_size,
		(0.5 - log((1.0 + sin_latitude) / (1.0 - sin_latitude)) / (4.0 * PI)) * world_size
	)
