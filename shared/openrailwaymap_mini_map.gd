extends PanelContainer
## OpenRailwayMap view of railway route 0001 through the south Zhengzhou hub.

const Overlay = preload("res://shared/openrailwaymap_overlay.gd")
const MAP_SIZE := Vector2(344.0, 244.0)
const TILE_SIZE := 256.0
const MAP_ZOOM := 9
const MAP_CENTER := Vector2(113.704, 34.522)
const TILE_URL := "https://tiles.openrailwaymap.org/standard/%d/%d/%d.png"
const USER_AGENT := "GodotSimulator-OpenRailwayMap/1.0"

var _map_view: Control
var _tile_layer: Control
var _overlay: Control
var _status: Label
var _request: HTTPRequest
var _pending_tiles: Array[Dictionary] = []
var _active_tile: Dictionary = {}
var _request_failures := 0


func _ready() -> void:
	_build_ui()
	_build_tiles()
	_request = HTTPRequest.new()
	_request.name = "OpenRailwayMapTileRequest"
	_request.timeout = 6.0
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_request_next_tile()


func _build_ui() -> void:
	name = "OpenRailwayMapMiniMap"
	position = Vector2(18.0, 18.0)
	custom_minimum_size = Vector2(368.0, 326.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.055, 0.94)
	style.border_color = Color(0.52, 0.72, 0.78, 0.82)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 11.0
	style.content_margin_right = 11.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	var title := Label.new()
	title.text = "线路小地图  ·  郑州枢纽南段"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("f3f8fa"))
	column.add_child(title)

	_map_view = Control.new()
	_map_view.name = "MapViewport"
	_map_view.custom_minimum_size = MAP_SIZE
	_map_view.clip_contents = true
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_map_view)
	var backdrop := ColorRect.new()
	backdrop.color = Color("e6e1d4")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(backdrop)
	_tile_layer = Control.new()
	_tile_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(_tile_layer)
	_overlay = Overlay.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(_overlay)

	_status = Label.new()
	_status.text = "正在加载 OpenRailwayMap…"
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color("b9c7cc"))
	column.add_child(_status)
	var attribution := Label.new()
	attribution.text = "© OpenStreetMap contributors · OpenRailwayMap CC-BY-SA 2.0"
	attribution.add_theme_font_size_override("font_size", 10)
	attribution.add_theme_color_override("font_color", Color("91a3aa"))
	column.add_child(attribution)


func _build_tiles() -> void:
	var world_size := TILE_SIZE * pow(2.0, MAP_ZOOM)
	var center_world := _mercator(MAP_CENTER, world_size)
	var top_left := center_world - MAP_SIZE * 0.5
	var first_x := floori(top_left.x / TILE_SIZE)
	var first_y := floori(top_left.y / TILE_SIZE)
	var last_x := floori((top_left.x + MAP_SIZE.x) / TILE_SIZE)
	var last_y := floori((top_left.y + MAP_SIZE.y) / TILE_SIZE)
	for tile_y in range(first_y, last_y + 1):
		for tile_x in range(first_x, last_x + 1):
			var texture_rect := TextureRect.new()
			texture_rect.name = "Tile_%d_%d" % [tile_x, tile_y]
			texture_rect.position = Vector2(tile_x, tile_y) * TILE_SIZE - top_left
			texture_rect.size = Vector2.ONE * TILE_SIZE
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tile_layer.add_child(texture_rect)
			_pending_tiles.append({"x": tile_x, "y": tile_y, "view": texture_rect})


func set_route_distance(distance_m: float) -> void:
	if _overlay != null:
		_overlay.set_progress(distance_m)


func _request_next_tile() -> void:
	if _request == null or not _active_tile.is_empty():
		return
	if _pending_tiles.is_empty():
		_status.text = "OpenRailwayMap · 0001 京广铁路 · 南向 50 km"
		return
	_active_tile = _pending_tiles.pop_front()
	var url := TILE_URL % [MAP_ZOOM, _active_tile.x, _active_tile.y]
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: image/png"])
	var error := _request.request(url, headers)
	if error != OK:
		_request_failures += 1
		_active_tile.clear()
		_handle_failure()


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	var completed := _active_tile
	_active_tile = {}
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image := Image.new()
		if image.load_png_from_buffer(body) == OK:
			(completed.view as TextureRect).texture = ImageTexture.create_from_image(image)
			_request_failures = 0
	elif response_code == 429:
		_pending_tiles.clear()
		_status.text = "OpenRailwayMap 请求受限 · 已停止加载"
		return
	else:
		_request_failures += 1
	_handle_failure()


func _handle_failure() -> void:
	if _request_failures >= 3:
		_pending_tiles.clear()
		_status.text = "地图服务暂不可用 · 显示本地线路示意"
		return
	_request_next_tile()


func _mercator(geo: Vector2, world_size: float) -> Vector2:
	var latitude := clampf(geo.y, -85.05112878, 85.05112878)
	var sin_latitude := sin(deg_to_rad(latitude))
	return Vector2(
		(geo.x + 180.0) / 360.0 * world_size,
		(0.5 - log((1.0 + sin_latitude) / (1.0 - sin_latitude)) / (4.0 * PI)) * world_size
	)
