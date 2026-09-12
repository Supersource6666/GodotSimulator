extends Control
## Draws the local railway alignment and a directional train marker over the map.

const MAP_ZOOM := 15
const TILE_SIZE := 256.0

var route_geo := PackedVector2Array() # Vector2(longitude, latitude)
var center_geo := Vector2(139.767, 35.681)
var train_geo := center_geo
var heading_degrees := 180.0
var has_google_map := false


func set_map_data(points: PackedVector2Array, center: Vector2, train_position: Vector2,
		heading: float, google_map_visible: bool) -> void:
	route_geo = points
	center_geo = center
	train_geo = train_position
	heading_degrees = heading
	has_google_map = google_map_visible
	queue_redraw()


func _draw() -> void:
	if not has_google_map:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#17222c"))
		_draw_grid()
	if route_geo.size() >= 2:
		var screen_route := PackedVector2Array()
		for point in route_geo:
			screen_route.append(_project(point))
		draw_polyline(screen_route, Color(0.02, 0.03, 0.04, 0.8), 6.0, true)
		draw_polyline(screen_route, Color("#43d7ff"), 3.0, true)
	var marker := _project(train_geo)
	draw_circle(marker + Vector2(1.5, 2.0), 10.0, Color(0, 0, 0, 0.45))
	draw_circle(marker, 9.0, Color("#ff4057"))
	draw_circle(marker, 4.0, Color.WHITE)
	var direction := Vector2(sin(deg_to_rad(heading_degrees)), -cos(deg_to_rad(heading_degrees)))
	var side := direction.rotated(PI * 0.5)
	var arrow := PackedVector2Array([
		marker + direction * 18.0,
		marker - direction * 6.0 + side * 7.0,
		marker - direction * 2.0,
		marker - direction * 6.0 - side * 7.0,
	])
	draw_colored_polygon(arrow, Color("#1b4cff"))
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]),
		Color.WHITE, 1.5, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.7, 0.82, 0.9, 0.7), false, 1.0)


func _draw_grid() -> void:
	for x in range(0, int(size.x) + 1, 32):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.3, 0.42, 0.5, 0.18))
	for y in range(0, int(size.y) + 1, 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.3, 0.42, 0.5, 0.18))


func _project(geo: Vector2) -> Vector2:
	var world_size := TILE_SIZE * pow(2.0, MAP_ZOOM)
	var point_world := _mercator(geo, world_size)
	var center_world := _mercator(center_geo, world_size)
	return point_world - center_world + size * 0.5


func _mercator(geo: Vector2, world_size: float) -> Vector2:
	var latitude := clampf(geo.y, -85.05112878, 85.05112878)
	var sin_latitude := sin(deg_to_rad(latitude))
	return Vector2(
		(geo.x + 180.0) / 360.0 * world_size,
		(0.5 - log((1.0 + sin_latitude) / (1.0 - sin_latitude)) / (4.0 * PI)) * world_size
	)
