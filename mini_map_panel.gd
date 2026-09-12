extends PanelContainer
## Optional Google Maps Static API background with an always-available local route overlay.

const API_KEY_PATH := "res://google_maps_api_key.txt"
const ROUTE_PATH := "res://assets/route/tokyo_shinagawa_track.json"
const MAP_SIZE := Vector2(300, 185)
const MAP_ZOOM := 15
const MAP_CENTER_STEP_M := 500.0
const EARTH_RADIUS_M := 6371008.8

var allow_google_map := true
var route_geo := PackedVector2Array() # Vector2(longitude, latitude)
var route_distances := PackedFloat64Array()
var local_route_length_m := 0.0
var map_texture: TextureRect
var overlay: Control
var coordinate_label: Label
var map_status: Label
var request_node: HTTPRequest
var api_key := ""
var desired_cell := -1
var request_cell := -1
var map_center_geo := Vector2(139.767, 35.681)
var current_geo := map_center_geo
var current_heading := 180.0
var map_cache: Dictionary = {}


func _ready() -> void:
	_build_ui()
	if allow_google_map and FileAccess.file_exists(API_KEY_PATH):
		api_key = FileAccess.get_file_as_string(API_KEY_PATH).strip_edges()
	if not api_key.is_empty():
		request_node = HTTPRequest.new()
		request_node.name = "GoogleStaticMapRequest"
		request_node.timeout = 12.0
		request_node.request_completed.connect(_on_map_request_completed)
		add_child(request_node)
	else:
		map_status.text = "Google 底图未配置 · 本地线路模式"


func _build_ui() -> void:
	name = "MiniMapPanel"
	position = Vector2(20, 20)
	custom_minimum_size = Vector2(324, 269)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.07, 0.88)
	panel_style.border_color = Color(0.55, 0.66, 0.74, 0.75)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 11
	panel_style.content_margin_right = 11
	panel_style.content_margin_top = 9
	panel_style.content_margin_bottom = 9
	add_theme_stylebox_override("panel", panel_style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	var title := Label.new()
	title.text = "⌖  小地图 / GPS"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#f1f7fb"))
	column.add_child(title)
	var map_frame := Control.new()
	map_frame.name = "MapViewport"
	map_frame.custom_minimum_size = MAP_SIZE
	map_frame.clip_contents = true
	map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(map_frame)
	map_texture = TextureRect.new()
	map_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(map_texture)
	overlay = preload("res://mini_map_overlay.gd").new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(overlay)
	coordinate_label = Label.new()
	coordinate_label.text = "纬度：--\n经度：--"
	coordinate_label.add_theme_font_size_override("font_size", 14)
	coordinate_label.add_theme_color_override("font_color", Color("#f4f8fb"))
	column.add_child(coordinate_label)
	map_status = Label.new()
	map_status.text = "本地线路模式"
	map_status.add_theme_font_size_override("font_size", 11)
	map_status.add_theme_color_override("font_color", Color("#aebbc4"))
	column.add_child(map_status)


func configure(local_length_m: float) -> void:
	local_route_length_m = local_length_m
	if not FileAccess.file_exists(ROUTE_PATH):
		map_status.text = "线路坐标不可用"
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ROUTE_PATH))
	if not parsed is Dictionary or not parsed.get("points", []) is Array:
		map_status.text = "线路坐标无效"
		return
	route_geo.clear()
	for point in parsed.points:
		route_geo.append(Vector2(float(point.lon), float(point.lat)))
	_build_route_distances()
	set_mileage(0.0)


func _build_route_distances() -> void:
	route_distances.clear()
	if route_geo.is_empty():
		return
	route_distances.append(0.0)
	for index in range(1, route_geo.size()):
		route_distances.append(route_distances[-1] + _geo_distance(route_geo[index - 1], route_geo[index]))


func set_mileage(mileage_m: float) -> void:
	if route_distances.size() < 2 or local_route_length_m <= 0.0:
		return
	var clamped_mileage := clampf(mileage_m, 0.0, local_route_length_m)
	current_geo = _geo_at_mileage(clamped_mileage)
	var before := _geo_at_mileage(maxf(0.0, clamped_mileage - 12.0))
	var after := _geo_at_mileage(minf(local_route_length_m, clamped_mileage + 12.0))
	current_heading = _bearing(before, after)
	coordinate_label.text = "纬度：%.6f° %s\n经度：%.6f° %s    方位：%05.1f°" % [
		absf(current_geo.y), "N" if current_geo.y >= 0.0 else "S",
		absf(current_geo.x), "E" if current_geo.x >= 0.0 else "W", current_heading]
	var max_cell := maxi(0, roundi(local_route_length_m / MAP_CENTER_STEP_M))
	var cell := clampi(roundi(clamped_mileage / MAP_CENTER_STEP_M), 0, max_cell)
	if cell != desired_cell:
		desired_cell = cell
		map_center_geo = _geo_at_mileage(minf(cell * MAP_CENTER_STEP_M, local_route_length_m))
		_select_or_request_map(cell)
	_refresh_overlay()


func _select_or_request_map(cell: int) -> void:
	if map_cache.has(cell):
		map_texture.texture = map_cache[cell]
		map_status.text = "Google Maps · 线路每 500 m 更新底图"
		return
	map_texture.texture = null
	if request_node == null:
		return
	if request_cell >= 0:
		return
	_request_map(cell)


func _request_map(cell: int) -> void:
	request_cell = cell
	var center := _geo_at_mileage(minf(cell * MAP_CENTER_STEP_M, local_route_length_m))
	var url := "https://maps.googleapis.com/maps/api/staticmap?center=%.7f,%.7f&zoom=%d&size=%dx%d&scale=1&maptype=roadmap&format=png&language=zh-CN&region=JP&key=%s" % [
		center.y, center.x, MAP_ZOOM, int(MAP_SIZE.x), int(MAP_SIZE.y), api_key]
	map_status.text = "正在加载 Google Maps…"
	var error := request_node.request(url, PackedStringArray(["Accept: image/png"]))
	if error != OK:
		request_cell = -1
		map_status.text = "Google 底图加载失败 · 本地线路模式"


func _on_map_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	var completed_cell := request_cell
	request_cell = -1
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image := Image.new()
		var load_error := image.load_png_from_buffer(body)
		if load_error != OK:
			load_error = image.load_jpg_from_buffer(body)
		if load_error == OK:
			var texture := ImageTexture.create_from_image(image)
			map_cache[completed_cell] = texture
			if completed_cell == desired_cell:
				map_texture.texture = texture
				map_status.text = "Google Maps · 线路每 500 m 更新底图"
				_refresh_overlay()
		else:
			map_status.text = "Google 底图响应无效 · 本地线路模式"
	else:
		map_status.text = "Google 底图加载失败 · 本地线路模式"
	if desired_cell != completed_cell and not map_cache.has(desired_cell):
		_request_map(desired_cell)


func _refresh_overlay() -> void:
	if overlay == null:
		return
	overlay.set_map_data(route_geo, map_center_geo, current_geo, current_heading,
		map_texture != null and map_texture.texture != null)


func _geo_at_mileage(mileage_m: float) -> Vector2:
	if route_distances.size() < 2:
		return Vector2.ZERO
	var target := clampf(mileage_m / local_route_length_m, 0.0, 1.0) * route_distances[-1]
	var low := 0
	var high := route_distances.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if target > route_distances[middle]:
			low = middle
		else:
			high = middle
	var length := maxf(route_distances[low + 1] - route_distances[low], 0.001)
	return route_geo[low].lerp(route_geo[low + 1], (target - route_distances[low]) / length)


func _geo_distance(from: Vector2, to: Vector2) -> float:
	var latitude_a := deg_to_rad(from.y)
	var latitude_b := deg_to_rad(to.y)
	var delta_latitude := latitude_b - latitude_a
	var delta_longitude := deg_to_rad(to.x - from.x)
	var value := sin(delta_latitude * 0.5) ** 2 + cos(latitude_a) * cos(latitude_b) * sin(delta_longitude * 0.5) ** 2
	return EARTH_RADIUS_M * 2.0 * atan2(sqrt(value), sqrt(maxf(0.0, 1.0 - value)))


func _bearing(from: Vector2, to: Vector2) -> float:
	var latitude_a := deg_to_rad(from.y)
	var latitude_b := deg_to_rad(to.y)
	var delta_longitude := deg_to_rad(to.x - from.x)
	var y := sin(delta_longitude) * cos(latitude_b)
	var x := cos(latitude_a) * sin(latitude_b) - sin(latitude_a) * cos(latitude_b) * cos(delta_longitude)
	return fposmod(rad_to_deg(atan2(y, x)) + 360.0, 360.0)
