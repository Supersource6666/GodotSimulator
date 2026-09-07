extends "res://main.gd"

# Main Tokaido Shinkansen stations, east to west.
const ROUTE_POINTS := [
	{"name": "东京", "lat": 35.681236, "lon": 139.767125},
	{"name": "品川", "lat": 35.628471, "lon": 139.738760},
]

const EARTH_RADIUS_METERS := 6371008.8
const WGS84_SEMI_MAJOR_AXIS := 6378137.0
const WGS84_ECCENTRICITY_SQUARED := 0.00669437999014
const TRAIN_REFERENCE_SPEED_KMH := 285.0
const TRAIN_SPEED_METERS_PER_SECOND := TRAIN_REFERENCE_SPEED_KMH / 3.6
const DEFAULT_TIME_SCALE := 1.0
const CAMERA_HEIGHT_METERS := 200.0
const CAMERA_TRAILING_DISTANCE_METERS := 200.0
const CAMERA_LOOK_AHEAD_METERS := 200.0
const ROUTE_DIRECTION_SAMPLE_METERS := 1500.0
const MIN_INITIAL_LOAD_SECONDS := 8.0
const INITIAL_LOAD_STABLE_SECONDS := 5.0
const ROUTE_PRELOAD_INTERVAL_METERS := 500.0
const ROUTE_PRELOAD_MIN_SECONDS := 3.0
const ROUTE_PRELOAD_STABLE_SECONDS := 2.0

var _route_georeference: CesiumGeoreference
var _origin_ecef := Vector3.ZERO
var _route_camera: Camera3D
var _buildings_tileset: Cesium3DTileset
var _trip_label: Label
var _progress_bar: ProgressBar
var _route_segment_lengths: Array[float] = []
var _total_route_distance := 0.0
var _journey_distance := 0.0
var _time_scale := DEFAULT_TIME_SCALE
var _journey_started := false
var _paused := false
var _last_loaded_tile_count := -1
var _load_stable_elapsed := 0.0
var _next_preload_distance := ROUTE_PRELOAD_INTERVAL_METERS
var _route_preloading := false
var _route_preload_elapsed := 0.0
var _route_preload_stable_elapsed := 0.0
var _route_preload_last_tile_count := -1


func _ready() -> void:
	_build_route_distance_table()
	await super()
	_update_route_position(0.0)
	print("Tokaido preview: Tokyo -> Shinagawa, distance=", roundi(_total_route_distance / 1000.0), " km")


func _process(delta: float) -> void:
	if not _use_cesium_ion:
		_serve_local_tile_requests()
	_elapsed += delta
	var loaded_tile_count := _get_loaded_tile_count()

	if _tileset != null and _route_camera != null and _route_georeference != null:
		var camera_ecef_transform := _route_georeference.get_tx_engine_to_ecef() * _route_camera.global_transform
		_tileset.update_tileset(camera_ecef_transform)
		if _buildings_tileset != null:
			_buildings_tileset.update_tileset(camera_ecef_transform)

	if loaded_tile_count != _last_loaded_tile_count:
		_last_loaded_tile_count = loaded_tile_count
		_load_stable_elapsed = 0.0
	elif loaded_tile_count > 0:
		_load_stable_elapsed += delta

	if _tileset != null and not _reported_loaded:
		if _status_label != null and _use_cesium_ion:
			_status_label.text = "状态：正在加载东京地形… %d 个 Tile（连续稳定 %.1f / %.1f 秒后发车）" % [
				loaded_tile_count,
				minf(_load_stable_elapsed, INITIAL_LOAD_STABLE_SECONDS),
				INITIAL_LOAD_STABLE_SECONDS
			]
		var load_is_stable := (
			loaded_tile_count > 0
			and _elapsed >= MIN_INITIAL_LOAD_SECONDS
			and _load_stable_elapsed >= INITIAL_LOAD_STABLE_SECONDS
		)
		var initial_load_finished := _tileset.is_initial_loading_finished() or load_is_stable
		if initial_load_finished:
			_reported_loaded = true
			_journey_started = _use_cesium_ion
			_status_label.text = "状态：东京地形加载完成，列车已发车" if _use_cesium_ion else "状态：本地回退样例已加载（无日本地形）"
			_status_label.modulate = Color(0.55, 1.0, 0.65)

	if _journey_started and not _paused and _journey_distance < _total_route_distance:
		if _route_preloading:
			_update_route_preload_wait(delta, loaded_tile_count)
		else:
			_journey_distance = minf(
				_journey_distance + TRAIN_SPEED_METERS_PER_SECOND * _time_scale * delta,
				_total_route_distance
			)
			_update_route_position(_journey_distance)
			if _journey_distance >= _next_preload_distance and _journey_distance < _total_route_distance:
				_begin_route_preload_wait(loaded_tile_count)
			if is_equal_approx(_journey_distance, _total_route_distance):
				_paused = true
				_status_label.text = "状态：已抵达品川站；按 R 可重新预览"

	if "--demo-smoke-test" in OS.get_cmdline_user_args() and _elapsed >= _next_progress_report:
		print("3D Tiles load progress: elapsed=", snapped(_elapsed, 0.1), "s tiles=", loaded_tile_count, " loaded=", _reported_loaded, " route_km=", snapped(_journey_distance / 1000.0, 0.1), " preloading=", _route_preloading)
		_next_progress_report += 5.0
	if "--demo-smoke-test" in OS.get_cmdline_user_args() and _elapsed >= 30.0:
		print("DEMO_SMOKE_TEST_RESULT loaded=", _reported_loaded)
		get_tree().quit(0 if _reported_loaded else 2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if _journey_started:
					_paused = not _paused
					_status_label.text = "状态：已暂停" if _paused else "状态：运行中"
			KEY_R:
				_journey_distance = 0.0
				_paused = false
				_route_preloading = false
				_next_preload_distance = ROUTE_PRELOAD_INTERVAL_METERS
				_update_route_position(0.0)
				_status_label.text = "状态：已从东京重新出发"
			KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
				_time_scale = minf(_time_scale * 1.25, 1.0)
				_update_trip_label(_find_route_segment(_journey_distance))
			KEY_MINUS, KEY_KP_SUBTRACT:
				_time_scale = maxf(_time_scale / 1.25, 1.0)
				_update_trip_label(_find_route_segment(_journey_distance))


func _begin_route_preload_wait(loaded_tile_count: int) -> void:
	_route_preloading = true
	_route_preload_elapsed = 0.0
	_route_preload_stable_elapsed = 0.0
	_route_preload_last_tile_count = loaded_tile_count
	_status_label.text = "状态：正在加载前方地形…"


func _update_route_preload_wait(delta: float, loaded_tile_count: int) -> void:
	_route_preload_elapsed += delta
	if loaded_tile_count != _route_preload_last_tile_count:
		_route_preload_last_tile_count = loaded_tile_count
		_route_preload_stable_elapsed = 0.0
	else:
		_route_preload_stable_elapsed += delta
	_status_label.text = "状态：沿线地形预加载中… %d 个 Tile（稳定 %.1f / %.1f 秒）" % [
		loaded_tile_count,
		minf(_route_preload_stable_elapsed, ROUTE_PRELOAD_STABLE_SECONDS),
		ROUTE_PRELOAD_STABLE_SECONDS
	]
	if (
		loaded_tile_count > 0
		and _route_preload_elapsed >= ROUTE_PRELOAD_MIN_SECONDS
		and _route_preload_stable_elapsed >= ROUTE_PRELOAD_STABLE_SECONDS
	):
		_route_preloading = false
		_next_preload_distance += ROUTE_PRELOAD_INTERVAL_METERS
		_status_label.text = "状态：前方地形已就绪，继续运行"


func _build_route_distance_table() -> void:
	_route_segment_lengths.clear()
	_total_route_distance = 0.0
	for index in range(ROUTE_POINTS.size() - 1):
		var distance := _haversine_distance(ROUTE_POINTS[index], ROUTE_POINTS[index + 1])
		_route_segment_lengths.append(distance)
		_total_route_distance += distance


func _haversine_distance(from_point: Dictionary, to_point: Dictionary) -> float:
	var lat_1 := deg_to_rad(float(from_point.lat))
	var lat_2 := deg_to_rad(float(to_point.lat))
	var delta_lat := lat_2 - lat_1
	var delta_lon := deg_to_rad(float(to_point.lon) - float(from_point.lon))
	var a := sin(delta_lat * 0.5) ** 2 + cos(lat_1) * cos(lat_2) * sin(delta_lon * 0.5) ** 2
	return EARTH_RADIUS_METERS * 2.0 * atan2(sqrt(a), sqrt(1.0 - a))


func _find_route_segment(distance: float) -> int:
	var remaining := distance
	for index in range(_route_segment_lengths.size()):
		if remaining <= _route_segment_lengths[index]:
			return index
		remaining -= _route_segment_lengths[index]
	return _route_segment_lengths.size() - 1


func _update_route_position(distance: float) -> void:
	var sample := _sample_route(distance)
	var ahead_sample := _sample_route(minf(distance + ROUTE_DIRECTION_SAMPLE_METERS, _total_route_distance))
	var ecef_to_engine_basis := _route_georeference.get_initial_tx_ecef_to_engine().basis
	var ground_ecef := _cartographic_to_ecef(float(sample.lat), float(sample.lon), 0.0)
	var elevated_ecef := _cartographic_to_ecef(float(sample.lat), float(sample.lon), 1000.0)
	var ahead_ecef := _cartographic_to_ecef(float(ahead_sample.lat), float(ahead_sample.lon), 0.0)
	var ground_position := ecef_to_engine_basis * (ground_ecef - _origin_ecef)
	var elevated_position := ecef_to_engine_basis * (elevated_ecef - _origin_ecef)
	var ahead_position := ecef_to_engine_basis * (ahead_ecef - _origin_ecef)

	# This preview is only 6.4 km long, so a fixed Tokyo origin and physical
	# camera motion are precise and keep all loaded tile transforms unchanged.
	# Constructing the orthonormal basis explicitly prevents endpoint flips.
	var surface_up := (elevated_position - ground_position).normalized()
	var route_forward := (ahead_position - ground_position).slide(surface_up).normalized()
	if route_forward.is_zero_approx():
		route_forward = -_route_camera.global_basis.z
	var camera_position := ground_position + surface_up * CAMERA_HEIGHT_METERS - route_forward * CAMERA_TRAILING_DISTANCE_METERS
	var view_target := ground_position + route_forward * CAMERA_LOOK_AHEAD_METERS
	var view_direction := (view_target - camera_position).normalized()
	var camera_right := view_direction.cross(surface_up).normalized()
	var camera_up := camera_right.cross(view_direction).normalized()
	_route_camera.global_position = camera_position
	_route_camera.global_basis = Basis(camera_right, camera_up, -view_direction)
	_update_trip_label(int(sample.segment))


func _sample_route(distance: float) -> Dictionary:
	var remaining := distance
	var segment_index := 0
	for index in range(_route_segment_lengths.size()):
		segment_index = index
		if remaining <= _route_segment_lengths[index]:
			break
		remaining -= _route_segment_lengths[index]
	var segment_length: float = _route_segment_lengths[segment_index]
	var t := clampf(remaining / segment_length, 0.0, 1.0)
	var from_point: Dictionary = ROUTE_POINTS[segment_index]
	var to_point: Dictionary = ROUTE_POINTS[segment_index + 1]
	return {
		"lat": lerpf(float(from_point.lat), float(to_point.lat), t),
		"lon": lerpf(float(from_point.lon), float(to_point.lon), t),
		"segment": segment_index,
	}


func _cartographic_to_ecef(latitude: float, longitude: float, height: float) -> Vector3:
	var lat := deg_to_rad(latitude)
	var lon := deg_to_rad(longitude)
	var sin_lat := sin(lat)
	var prime_vertical_radius := WGS84_SEMI_MAJOR_AXIS / sqrt(1.0 - WGS84_ECCENTRICITY_SQUARED * sin_lat * sin_lat)
	var ecef := Vector3(
		(prime_vertical_radius + height) * cos(lat) * cos(lon),
		(prime_vertical_radius + height) * cos(lat) * sin(lon),
		(prime_vertical_radius * (1.0 - WGS84_ECCENTRICITY_SQUARED) + height) * sin_lat
	)
	return ecef


func _update_trip_label(segment_index: int) -> void:
	if _trip_label == null:
		return
	_trip_label.text = "区间：%s → %s\n里程：%.1f / %.1f km    速度：%.0f km/h    时间压缩：%.1f×" % [
		ROUTE_POINTS[segment_index].name,
		ROUTE_POINTS[segment_index + 1].name,
		_journey_distance / 1000.0,
		_total_route_distance / 1000.0,
		TRAIN_REFERENCE_SPEED_KMH,
		_time_scale
	]
	if _progress_bar != null:
		_progress_bar.value = 100.0 * _journey_distance / _total_route_distance


func _create_cesium_scene() -> void:
	_route_georeference = CesiumGeoreference.new()
	_route_georeference.name = "CesiumGeoreference"
	_route_georeference.latitude = float(ROUTE_POINTS[0].lat)
	_route_georeference.longitude = float(ROUTE_POINTS[0].lon)
	_route_georeference.altitude = 0.0
	_origin_ecef = _cartographic_to_ecef(float(ROUTE_POINTS[0].lat), float(ROUTE_POINTS[0].lon), 0.0)
	_route_georeference.origin_type = CesiumGeoreference.OriginType.CartographicOrigin
	_route_georeference.rotation_degrees.x = -90.0
	add_child(_route_georeference)

	_tileset = Cesium3DTileset.new()
	_tileset.name = "Cesium3DTileset"
	if _use_cesium_ion:
		_tileset.data_source = Cesium3DTileset.CesiumDataSource.FromCesiumIon
		_tileset.ion_asset_id = 1
		var bing_overlay := CesiumIonRasterOverlay.new()
		bing_overlay.name = "BingMapsAerialImagery"
		bing_overlay.key = "Overlay0"
		bing_overlay.asset_id = 2
		_tileset.add_child(bing_overlay)
	else:
		_tileset.data_source = Cesium3DTileset.CesiumDataSource.FromUrl
		_tileset.url = _sample_tileset_url()
	_tileset.maximum_screen_space_error = 8.0
	_tileset.maximum_simultaneous_tile_loads = 8
	_tileset.preload_ancestors = true
	_tileset.preload_siblings = true
	_tileset.create_physics_meshes = false
	_tileset.show_hierarchy = true
	_tileset.rotation_degrees.x = 90.0
	_route_georeference.add_child(_tileset)

	if _use_cesium_ion:
		# Japan 3D Buildings is derived from MLIT PLATEAU and hosted by Cesium; it
		# avoids the unavailable Google Photorealistic endpoint.
		_buildings_tileset = Cesium3DTileset.new()
		_buildings_tileset.name = "JapanPLATEAU3DBuildings"
		_buildings_tileset.data_source = Cesium3DTileset.CesiumDataSource.FromCesiumIon
		_buildings_tileset.ion_asset_id = 2602291
		_buildings_tileset.maximum_screen_space_error = 12.0
		_buildings_tileset.maximum_simultaneous_tile_loads = 4
		_buildings_tileset.preload_ancestors = true
		_buildings_tileset.preload_siblings = false
		_buildings_tileset.create_physics_meshes = false
		_buildings_tileset.show_hierarchy = false
		_buildings_tileset.rotation_degrees.x = 90.0
		_route_georeference.add_child(_buildings_tileset)

	_route_camera = Camera3D.new()
	_route_camera.name = "RouteCamera"
	_route_camera.position = Vector3(0.0, CAMERA_HEIGHT_METERS, CAMERA_TRAILING_DISTANCE_METERS)
	_route_camera.near = 5.0
	_route_camera.far = 35358652.0
	_route_camera.fov = 52.0
	_route_camera.current = true
	add_child(_route_camera)
	_route_camera.look_at(Vector3(0.0, 0.0, -1800.0), Vector3.UP)


func _create_help_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "JourneyUI"
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 7)
	margin.add_child(text_box)
	var title := Label.new()
	title.text = "东海道新干线预览 · 东京 → 品川"
	title.add_theme_font_size_override("font_size", 20)
	text_box.add_child(title)
	_trip_label = Label.new()
	text_box.add_child(_trip_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = true
	_progress_bar.custom_minimum_size = Vector2(480.0, 20.0)
	text_box.add_child(_progress_bar)
	var instructions := Label.new()
	instructions.text = "Space：暂停/继续    R：重新预览东京 → 品川    时间压缩：固定 1×\n视角：沿线低空 200 m    数据：" + ("Cesium World Terrain + Bing Aerial + Japan PLATEAU 3D Buildings" if _use_cesium_ion else "CesiumGS 本地回退样例")
	text_box.add_child(instructions)
	_status_label = Label.new()
	_status_label.text = "状态：正在加载东京站附近地形…" if _use_cesium_ion else "状态：正在加载本地样例（需要 Token 才能显示日本地形）"
	_status_label.modulate = Color(1.0, 0.85, 0.45)
	text_box.add_child(_status_label)
	_update_trip_label(0)
