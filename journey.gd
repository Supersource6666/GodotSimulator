extends "res://main.gd"

# Main Tokaido Shinkansen stations, east to west.
var ROUTE_POINTS: Array = []

const EARTH_RADIUS_METERS := 6371008.8
const WGS84_SEMI_MAJOR_AXIS := 6378137.0
const WGS84_ECCENTRICITY_SQUARED := 0.00669437999014
const TRAIN_REFERENCE_SPEED_KMH := 285.0
const TRAIN_SPEED_METERS_PER_SECOND := TRAIN_REFERENCE_SPEED_KMH / 3.6
const DEFAULT_TIME_SCALE := 1.0
const CAMERA_HEIGHT_METERS := 65.0
const CAMERA_TRAILING_DISTANCE_METERS := 85.0
const CAMERA_LOOK_AHEAD_METERS := 8.0
const ROUTE_DIRECTION_SAMPLE_METERS := 12.0
const CAB_EYE_HEIGHT_METERS := 2.45
# 四节编组头车中心位于列车锚点前方 40.5 m；司机座椅再向车头方向约 12.5 m。
const CAB_MILE_OFFSET_METERS := 53.0
const CAB_LOOK_AHEAD_METERS := 100.0
const CAB_LOOK_DOWN_DEGREES := 9.0
# OSM supplies horizontal alignment, not surveyed rail elevation.
const DEFAULT_RAIL_ELLIPSOID_HEIGHT := 46.0
var _rail_height := DEFAULT_RAIL_ELLIPSOID_HEIGHT
var _train: Node3D
const MIN_INITIAL_LOAD_SECONDS := 8.0
const INITIAL_LOAD_STABLE_SECONDS := 5.0
const ROUTE_PRELOAD_INTERVAL_METERS := 500.0
const ROUTE_PRELOAD_MIN_SECONDS := 3.0
const ROUTE_PRELOAD_STABLE_SECONDS := 2.0
const TERRAIN_SCREEN_SPACE_ERROR := 1.0
const BUILDING_SCREEN_SPACE_ERROR := 2.0
const TERRAIN_SIMULTANEOUS_LOADS := 48
const BUILDING_SIMULTANEOUS_LOADS := 24
const PHOTOREALISTIC_ASSET_ID := 2275207
const MAX_NEAR_GEOMETRIC_ERROR_METERS := 8.1

var _route_georeference: CesiumGeoreference
var _origin_ecef := Vector3.ZERO
var _route_camera: Camera3D
var _cab_interior: Node3D
var _cab_view := false
var _buildings_tileset: Cesium3DTileset
var _trip_label: Label
var _progress_label: Label
var _progress_slider: HSlider
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
var _photorealistic := true
var _view_coverage := 0
var _view_check_elapsed := 1.0
var _view_ready_elapsed := 0.0
const REQUIRED_VIEW_SAMPLES := 7
const MAX_TRIANGLE_CACHE_ENTRIES := 256
var _triangle_cache: Dictionary = {}
var _triangle_queue: Array[WeakRef] = []
var _triangle_queued: Dictionary = {}
var _triangle_build_last_ms := 0.0
var _triangle_build_max_ms := 0.0
var _probe_last_ms := 0.0
var _probe_max_ms := 0.0
var _native_update_max_ms := 0.0
var _process_max_ms := 0.0


func _ready() -> void:
	_photorealistic = not ("--terrain-preview" in OS.get_cmdline_user_args())
	_build_route_distance_table()
	await super()
	_train = load("res://train_visual.gd").new()
	_train.name = "PreviewTrain"
	add_child(_train)
	if "--cab-view" in OS.get_cmdline_user_args():
		_set_cab_view(true)
	else:
		_update_route_position(0.0)
	print("Tokaido preview: Tokyo -> Shinagawa, distance=", roundi(_total_route_distance / 1000.0), " km")


func _process(delta: float) -> void:
	var process_start := Time.get_ticks_usec()
	_prepare_triangle_cache()
	if not _use_cesium_ion:
		_serve_local_tile_requests()
	_elapsed += delta
	var loaded_tile_count := _get_loaded_tile_count()

	if _tileset != null and _route_camera != null and _route_georeference != null:
		var native_start := Time.get_ticks_usec()
		var camera_ecef_transform := _route_georeference.get_tx_engine_to_ecef() * _route_camera.global_transform
		_tileset.update_tileset(camera_ecef_transform)
		if _buildings_tileset != null:
			_buildings_tileset.update_tileset(camera_ecef_transform)
		_native_update_max_ms = maxf(_native_update_max_ms, (Time.get_ticks_usec() - native_start) / 1000.0)

	_view_check_elapsed += delta
	if _view_check_elapsed >= 1.0 and _route_camera != null:
		_view_check_elapsed = 0.0
		var probe_start := Time.get_ticks_usec()
		_view_coverage = _measure_view_coverage(false)
		if _update_rail_height():
			_update_route_position(_journey_distance)
		_probe_last_ms = (Time.get_ticks_usec() - probe_start) / 1000.0
		_probe_max_ms = maxf(_probe_max_ms, _probe_last_ms)
	if _view_coverage >= REQUIRED_VIEW_SAMPLES:
		_view_ready_elapsed += delta
	else:
		_view_ready_elapsed = 0.0

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
			and _view_ready_elapsed >= INITIAL_LOAD_STABLE_SECONDS
		)
		# Cesium can report initial loading complete as soon as a coarse ancestor is
		# visible. Wait until the high-detail tile set has remained stable so the
		# moving camera does not outrun refinement.
		var initial_load_finished := load_is_stable if _use_cesium_ion else (
			_tileset.is_initial_loading_finished() or loaded_tile_count > 0
		)
		if _elapsed >= 30.0 and loaded_tile_count == 0 and _use_cesium_ion:
			_status_label.text = "状态：尚未收到三维瓦片，等待数据；请检查 ion 资产权限和网络连接"
		if _use_cesium_ion and not load_is_stable:
			_status_label.text = "状态：等待近景细节（误差 ≤ 8.1 m：%d / 9，稳定 %.1f / 5 秒）" % [_view_coverage, _view_ready_elapsed]
		if initial_load_finished:
			_reported_loaded = true
			_journey_started = _use_cesium_ion
			if _progress_slider != null:
				_progress_slider.editable = _journey_started
			_status_label.text = "状态：近景细节达到门槛，开始预览" if _use_cesium_ion else "状态：本地回退样例已加载（无日本地形）"
			_status_label.modulate = Color(0.55, 1.0, 0.65)

	if _journey_started and not _paused and _journey_distance < _total_route_distance and _train != null and _train.ready_for_preview:
		if _view_coverage < REQUIRED_VIEW_SAMPLES:
			_status_label.text = "状态：近景细节不足，已停止前进，等待细节瓦片（%d / 9）" % _view_coverage
		elif _route_preloading:
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
		print("3D Tiles load progress: elapsed=", snapped(_elapsed, 0.1), "s tiles=", loaded_tile_count, " coverage=", _view_coverage, "/9 loaded=", _reported_loaded, " route_km=", snapped(_journey_distance / 1000.0, 0.1), " preloading=", _route_preloading)
		_next_progress_report += 5.0
	if "--demo-smoke-test" in OS.get_cmdline_user_args() and _elapsed >= 30.0:
		var has_current_view := _reported_loaded and _view_coverage >= REQUIRED_VIEW_SAMPLES
		print("DEMO_SMOKE_TEST_RESULT loaded=", has_current_view)
		get_tree().quit(0 if has_current_view else 2)


	_process_max_ms = maxf(_process_max_ms, (Time.get_ticks_usec() - process_start) / 1000.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if _journey_started:
					_paused = not _paused
					_status_label.text = "状态：已暂停" if _paused else "状态：运行中"
			KEY_R:
				_journey_distance = 0.0
				_journey_started = false
				if _progress_slider != null:
					_progress_slider.editable = false
				_reported_loaded = false
				_elapsed = 0.0
				_load_stable_elapsed = 0.0
				_view_ready_elapsed = 0.0
				_view_coverage = 0
				_view_check_elapsed = 1.0
				_last_loaded_tile_count = -1
				_paused = false
				_route_preloading = false
				_next_preload_distance = ROUTE_PRELOAD_INTERVAL_METERS
				_update_route_position(0.0)
				_status_label.text = "状态：已返回东京，等待起点瓦片稳定"
			KEY_C:
				_set_cab_view(not _cab_view)
			KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
				_time_scale = minf(_time_scale * 1.25, 1.0)
				_update_trip_label(_find_route_segment(_journey_distance))
			KEY_MINUS, KEY_KP_SUBTRACT:
				_time_scale = maxf(_time_scale / 1.25, 1.0)
				_update_trip_label(_find_route_segment(_journey_distance))


func _set_cab_view(enabled: bool) -> void:
	_cab_view = enabled
	if _cab_interior != null:
		_cab_interior.visible = enabled
	if _train != null and _train.has_method("set_cab_view"):
		_train.set_cab_view(enabled)
	if _route_camera != null:
		_route_camera.near = 0.08 if enabled else 0.5
		_route_camera.fov = 64.0 if enabled else 52.0
	_view_check_elapsed = 1.0
	_view_ready_elapsed = 0.0
	_update_route_position(_journey_distance)
	_update_trip_label(_find_route_segment(_journey_distance))
	if _status_label != null:
		_status_label.text = "状态：驾驶室司机视角" if enabled else "状态：轨道跟车视角"

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
		and _view_ready_elapsed >= ROUTE_PRELOAD_STABLE_SECONDS
		and _route_preload_elapsed >= ROUTE_PRELOAD_MIN_SECONDS
		and _route_preload_stable_elapsed >= ROUTE_PRELOAD_STABLE_SECONDS
	):
		_route_preloading = false
		_next_preload_distance += ROUTE_PRELOAD_INTERVAL_METERS
		_status_label.text = "状态：近景细节覆盖已恢复，继续预览"


func _build_route_distance_table() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/route/tokyo_shinagawa_track.json"))
	assert(data is Dictionary and data.get("points", []).size() > 2, "Missing connected railway route")
	ROUTE_POINTS = data.points
	_route_segment_lengths.clear()
	_total_route_distance = 0.0
	for index in range(ROUTE_POINTS.size() - 1):
		var distance := _haversine_distance(ROUTE_POINTS[index], ROUTE_POINTS[index + 1])
		_route_segment_lengths.append(distance)
		_total_route_distance += distance


func _measure_view_coverage(allow_build: bool = true) -> int:
	# A node can be hidden, outside the frustum, or only an untextured ancestor.
	# Probe actual textured triangles across the view, without physics bodies.
	var viewport_size := get_viewport().get_visible_rect().size
	var covered: Array[bool] = []
	var nearest: Array[float] = []
	var missing_geometry := false
	var ray_ends: Array[Vector3] = []
	for y in ([0.56, 0.7, 0.84] if _cab_view else [0.3, 0.5, 0.7]):
		for x in [0.25, 0.5, 0.75]:
			covered.append(false)
			nearest.append(INF)
			ray_ends.append(_route_camera.global_position + _route_camera.project_ray_normal(viewport_size * Vector2(x, y)) * 2500.0)
	for tile in _tileset.get_children():
		if not tile is MeshInstance3D or not tile.is_visible_in_tree() or tile.mesh == null:
			continue
		if (tile.layers & _route_camera.cull_mask) == 0:
			continue
		var detailed := true
		if _photorealistic and _use_cesium_ion:
			var geometric_error := float(tile.get_meta("preview_geometric_error", INF))
			detailed = is_finite(geometric_error) and geometric_error <= MAX_NEAR_GEOMETRIC_ERROR_METERS
		var textured := false
		for index in tile.mesh.get_surface_count():
			var material = tile.get_active_material(index)
			if material is BaseMaterial3D and material.get_texture(BaseMaterial3D.TEXTURE_ALBEDO) != null:
				textured = true
				break
		var inverse: Transform3D = tile.global_transform.affine_inverse()
		var begin: Vector3 = inverse * _route_camera.global_position
		var bounds: AABB = tile.get_aabb()
		var triangles: TriangleMesh
		for index in ray_ends.size():
			var end: Vector3 = inverse * ray_ends[index]
			if bounds.intersects_segment(begin, end) == null:
				continue
			if triangles == null:
				triangles = _get_triangle_mesh(tile.mesh, allow_build)
			if triangles == null:
				missing_geometry = true
				continue
			var hit := triangles.intersect_segment(begin, end)
			if hit.is_empty():
				continue
			var hit_distance: float = (tile.global_transform * hit.position).distance_squared_to(_route_camera.global_position)
			if hit_distance < nearest[index]:
				nearest[index] = hit_distance
				covered[index] = detailed and textured
	# An uncached foreground surface may occlude a fine background. Fail closed
	# while its BVH is being prepared, rather than releasing the train early.
	return 0 if missing_geometry else covered.count(true)


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
	var behind_sample := _sample_route(maxf(distance - ROUTE_DIRECTION_SAMPLE_METERS, 0.0))
	var ecef_to_engine_basis := _route_georeference.get_initial_tx_ecef_to_engine().basis
	var ground_ecef := _cartographic_to_ecef(float(sample.lat), float(sample.lon), _rail_height)
	var elevated_ecef := _cartographic_to_ecef(float(sample.lat), float(sample.lon), 1000.0)
	var ahead_ecef := _cartographic_to_ecef(float(ahead_sample.lat), float(ahead_sample.lon), _rail_height)
	var behind_ecef := _cartographic_to_ecef(float(behind_sample.lat), float(behind_sample.lon), _rail_height)
	var ground_position := ecef_to_engine_basis * (ground_ecef - _origin_ecef)
	var elevated_position := ecef_to_engine_basis * (elevated_ecef - _origin_ecef)

	# This plugin selects tiles at the georeference origin rather than the
	# supplied camera position. Keep the camera at zero and move that origin.
	var surface_up := (elevated_position - ground_position).normalized()
	var route_forward := (ecef_to_engine_basis * (ahead_ecef - behind_ecef)).slide(surface_up).normalized()
	if route_forward.is_zero_approx():
		route_forward = (-_route_camera.global_basis.z).slide(surface_up).normalized()
	var camera_position: Vector3
	var view_target: Vector3
	var camera_surface_up := surface_up
	if _cab_view:
		var cab_distance := clampf(distance + CAB_MILE_OFFSET_METERS, 0.0, _total_route_distance)
		var cab_sample := _sample_route(cab_distance)
		var cab_ahead_sample := _sample_route(minf(cab_distance + ROUTE_DIRECTION_SAMPLE_METERS, _total_route_distance))
		var cab_behind_sample := _sample_route(maxf(cab_distance - ROUTE_DIRECTION_SAMPLE_METERS, 0.0))
		var cab_ground_ecef := _cartographic_to_ecef(float(cab_sample.lat), float(cab_sample.lon), _rail_height)
		var cab_up_ecef := _cartographic_to_ecef(float(cab_sample.lat), float(cab_sample.lon), _rail_height + 1000.0)
		var cab_ahead_ecef := _cartographic_to_ecef(float(cab_ahead_sample.lat), float(cab_ahead_sample.lon), _rail_height)
		var cab_behind_ecef := _cartographic_to_ecef(float(cab_behind_sample.lat), float(cab_behind_sample.lon), _rail_height)
		var cab_ground_position := ecef_to_engine_basis * (cab_ground_ecef - _origin_ecef)
		camera_surface_up = (ecef_to_engine_basis * (cab_up_ecef - cab_ground_ecef)).normalized()
		var cab_forward := (ecef_to_engine_basis * (cab_ahead_ecef - cab_behind_ecef)).slide(camera_surface_up).normalized()
		if cab_forward.is_zero_approx():
			cab_forward = route_forward
		camera_position = cab_ground_position + camera_surface_up * CAB_EYE_HEIGHT_METERS
		var target_distance := minf(cab_distance + CAB_LOOK_AHEAD_METERS, _total_route_distance)
		if target_distance > cab_distance + 0.1:
			var target_sample := _sample_route(target_distance)
			var target_height := CAB_EYE_HEIGHT_METERS - tan(deg_to_rad(CAB_LOOK_DOWN_DEGREES)) * (target_distance - cab_distance)
			var target_ecef := _cartographic_to_ecef(float(target_sample.lat), float(target_sample.lon), _rail_height + target_height)
			view_target = ecef_to_engine_basis * (target_ecef - _origin_ecef)
		else:
			view_target = camera_position + cab_forward * CAB_LOOK_AHEAD_METERS \
				- camera_surface_up * tan(deg_to_rad(CAB_LOOK_DOWN_DEGREES)) * CAB_LOOK_AHEAD_METERS
	else:
		var camera_sample := _sample_route(maxf(distance - CAMERA_TRAILING_DISTANCE_METERS, 0.0))
		camera_position = ecef_to_engine_basis * (_cartographic_to_ecef(camera_sample.lat, camera_sample.lon, _rail_height) - _origin_ecef)
		if distance < CAMERA_TRAILING_DISTANCE_METERS:
			camera_position -= route_forward * (CAMERA_TRAILING_DISTANCE_METERS - distance)
		camera_position += surface_up * CAMERA_HEIGHT_METERS
		view_target = ground_position + route_forward * CAMERA_LOOK_AHEAD_METERS
	var view_direction := (view_target - camera_position).normalized()
	var camera_right := view_direction.cross(camera_surface_up).normalized()
	var camera_up := camera_right.cross(view_direction).normalized()
	var camera_ecef := _origin_ecef + ecef_to_engine_basis.inverse() * camera_position
	_route_georeference.ecefX = camera_ecef.x
	_route_georeference.ecefY = camera_ecef.y
	_route_georeference.ecefZ = camera_ecef.z
	_route_camera.global_position = Vector3.ZERO
	_route_camera.global_basis = Basis(camera_right, camera_up, -view_direction)
	if _train != null:
		_train.global_position = ground_position - camera_position
		_train.global_basis = Basis(route_forward.cross(surface_up).normalized(), surface_up, -route_forward).orthonormalized()
	_update_trip_label(int(sample.segment))


func _sample_route(distance: float) -> Dictionary:
	var remaining := clampf(distance, 0.0, _total_route_distance)
	var segment_index := 0
	for index in range(_route_segment_lengths.size()):
		segment_index = index
		if remaining <= _route_segment_lengths[index]:
			break
		if index < _route_segment_lengths.size() - 1:
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


func _update_trip_label(_segment_index: int) -> void:
	if _trip_label == null:
		return
	_trip_label.text = "区间：%s → %s\n里程：%.1f / %.1f km    速度：%.0f km/h    时间压缩：%.1f×\n视角：%s" % [
		"东京",
		"品川",
		_journey_distance / 1000.0,
		_total_route_distance / 1000.0,
		TRAIN_REFERENCE_SPEED_KMH,
		_time_scale,
		"驾驶室司机视角" if _cab_view else "轨道跟车视角"
	]
	if _progress_label != null:
		_progress_label.text = '%d m / %d m' % [roundi(_journey_distance), roundi(_total_route_distance)]
	if _progress_slider != null:
		_progress_slider.set_value_no_signal(100.0 * _journey_distance / _total_route_distance)


func _seek_to_progress(percent: float) -> void:
	if not _journey_started or _total_route_distance <= 0.0:
		return
	_journey_distance = clampf(percent, 0.0, 100.0) * _total_route_distance / 100.0
	_route_preloading = false
	_next_preload_distance = minf(
		(floorf(_journey_distance / ROUTE_PRELOAD_INTERVAL_METERS) + 1.0) * ROUTE_PRELOAD_INTERVAL_METERS,
		_total_route_distance
	)
	_view_check_elapsed = 1.0
	_view_ready_elapsed = 0.0
	if is_equal_approx(_journey_distance, _total_route_distance):
		_paused = true
	_update_route_position(_journey_distance)
	_update_trip_label(_find_route_segment(_journey_distance))
	if _status_label != null:
		_status_label.text = '状态：已跳转到 %.1f km' % (_journey_distance / 1000.0)


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
		_tileset.ion_asset_id = PHOTOREALISTIC_ASSET_ID if _photorealistic else 1
		if not _photorealistic:
			var bing_overlay := CesiumIonRasterOverlay.new()
			bing_overlay.name = "BingMapsAerialImagery"
			bing_overlay.key = "Overlay0"
			bing_overlay.asset_id = 2
			_tileset.add_child(bing_overlay)
	else:
		_tileset.data_source = Cesium3DTileset.CesiumDataSource.FromUrl
		_tileset.url = _sample_tileset_url()
	# Low SSE values request finer terrain geometry and higher-resolution raster
	# tiles. The former 8 px setting was visibly coarse at a height of only 200 m.
	_tileset.maximum_screen_space_error = TERRAIN_SCREEN_SPACE_ERROR
	_tileset.maximum_simultaneous_tile_loads = 8 if _photorealistic else TERRAIN_SIMULTANEOUS_LOADS
	_tileset.preload_ancestors = true
	_tileset.forbid_holes = true
	_tileset.preload_siblings = true
	_tileset.create_physics_meshes = false
	_tileset.show_hierarchy = true
	_tileset.rotation_degrees.x = 90.0
	_route_georeference.add_child(_tileset)

	if _use_cesium_ion and not _photorealistic:
		# Japan 3D Buildings is derived from MLIT PLATEAU and hosted by Cesium; it
		# avoids the unavailable Google Photorealistic endpoint.
		_buildings_tileset = Cesium3DTileset.new()
		_buildings_tileset.name = "JapanPLATEAU3DBuildings"
		_buildings_tileset.data_source = Cesium3DTileset.CesiumDataSource.FromCesiumIon
		_buildings_tileset.ion_asset_id = 2602291
		_buildings_tileset.maximum_screen_space_error = BUILDING_SCREEN_SPACE_ERROR
		_buildings_tileset.maximum_simultaneous_tile_loads = BUILDING_SIMULTANEOUS_LOADS
		_buildings_tileset.preload_ancestors = true
		_buildings_tileset.forbid_holes = true
		_buildings_tileset.preload_siblings = false
		_buildings_tileset.create_physics_meshes = false
		_buildings_tileset.show_hierarchy = false
		_buildings_tileset.rotation_degrees.x = 90.0
		_route_georeference.add_child(_buildings_tileset)

	_route_camera = Camera3D.new()
	_route_camera.name = "RouteCamera"
	_route_camera.position = Vector3(0.0, CAMERA_HEIGHT_METERS, CAMERA_TRAILING_DISTANCE_METERS)
	_route_camera.near = 0.5
	# A globe-sized far plane with a sub-meter near plane degenerates float
	# frustum planes. Only the local railway corridor is needed in this view.
	_route_camera.far = 20000.0
	_route_camera.fov = 52.0
	_route_camera.current = true
	add_child(_route_camera)
	_cab_interior = load("res://cab_interior.gd").new()
	_cab_interior.name = "CabInterior"
	_cab_interior.visible = false
	_route_camera.add_child(_cab_interior)
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
	var instructions := Label.new()
	var source_name := "Google Photorealistic 3D Tiles" if _photorealistic else "World Terrain + Bing Aerial + PLATEAU"
	instructions.text = "Space：暂停/继续    R：重新预览    C：切换驾驶室视角    时间压缩：固定 1×\n外部视角：高 65 m / 后方 85 m    数据：" + (source_name if _use_cesium_ion else "CesiumGS 本地回退样例")
	text_box.add_child(instructions)
	var attribution := LinkButton.new()
	attribution.text = "轨道 © OpenStreetMap contributors (ODbL)"
	attribution.uri = "https://www.openstreetmap.org/copyright"
	text_box.add_child(attribution)
	_status_label = Label.new()
	_status_label.text = "状态：正在加载东京站附近地形…" if _use_cesium_ion else "状态：正在加载本地样例（需要 Token 才能显示日本地形）"
	_status_label.modulate = Color(1.0, 0.85, 0.45)
	text_box.add_child(_status_label)
	var progress_track := VBoxContainer.new()
	progress_track.name = 'JourneyProgressTrack'
	progress_track.anchor_left = 0.08
	progress_track.anchor_top = 1.0
	progress_track.anchor_right = 0.92
	progress_track.anchor_bottom = 1.0
	progress_track.offset_top = -72.0
	progress_track.offset_bottom = -16.0
	canvas.add_child(progress_track)
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override('font_size', 17)
	_progress_label.add_theme_color_override('font_color', Color.WHITE)
	_progress_label.add_theme_color_override('font_outline_color', Color.BLACK)
	_progress_label.add_theme_constant_override('outline_size', 4)
	progress_track.add_child(_progress_label)
	_progress_slider = HSlider.new()
	_progress_slider.min_value = 0.0
	_progress_slider.max_value = 100.0
	_progress_slider.step = 0.1
	_progress_slider.editable = false
	_progress_slider.custom_minimum_size = Vector2(0.0, 28.0)
	_progress_slider.tooltip_text = '拖动或点击以跳转运行进度'
	_progress_slider.value_changed.connect(_seek_to_progress)
	progress_track.add_child(_progress_slider)
	_update_trip_label(0)


func _update_rail_height() -> bool:
	if _train == null or _tileset == null:
		return false
	# Probe near the rail datum, not from the sky: station roofs and towers must
	# not lift the train onto rooftops. This is a visual fit, not a survey profile.
	var up := _train.global_basis.y
	var begin := _train.global_position + up * 8.0
	var end := _train.global_position - up * 8.0
	var best_offset := INF
	for tile in _tileset.get_children():
		if not tile is MeshInstance3D or not tile.is_visible_in_tree() or tile.mesh == null:
			continue
		if float(tile.get_meta("preview_geometric_error", INF)) > MAX_NEAR_GEOMETRIC_ERROR_METERS:
			continue
		var inverse: Transform3D = tile.global_transform.affine_inverse()
		if tile.get_aabb().intersects_segment(inverse * begin, inverse * end) == null:
			continue
		var triangles: TriangleMesh = _get_triangle_mesh(tile.mesh, false)
		if triangles == null:
			continue
		var hit := triangles.intersect_segment(inverse * begin, inverse * end)
		if not hit.is_empty():
			var offset: float = (tile.global_transform * hit.position - _train.global_position).dot(up)
			if absf(offset) < absf(best_offset):
				best_offset = offset
	if not is_finite(best_offset) or absf(best_offset) < 0.1:
		return false
	_rail_height = clampf(_rail_height + best_offset, DEFAULT_RAIL_ELLIPSOID_HEIGHT - 8.0, DEFAULT_RAIL_ELLIPSOID_HEIGHT + 8.0)
	return true


func _get_triangle_mesh(mesh: Mesh, allow_build: bool = false) -> TriangleMesh:
	var id := mesh.get_instance_id()
	if _triangle_cache.has(id):
		_triangle_cache[id].used = Time.get_ticks_msec()
		return _triangle_cache[id].triangles
	if bool(mesh.get_meta("preview_bvh_ready", false)):
		return _build_triangle_entry(mesh)
	if allow_build:
		return _build_triangle_entry(mesh)
	if not _triangle_queued.has(id) and _triangle_queue.size() < MAX_TRIANGLE_CACHE_ENTRIES:
		_triangle_queued[id] = true
		_triangle_queue.append(weakref(mesh))
	return null


func _build_triangle_entry(mesh: Mesh) -> TriangleMesh:
	var id := mesh.get_instance_id()
	var triangles := mesh.generate_triangle_mesh()
	if triangles == null:
		return null
	if _triangle_cache.size() >= MAX_TRIANGLE_CACHE_ENTRIES:
		var oldest_id: int = _triangle_cache.keys()[0]
		for key in _triangle_cache:
			if _triangle_cache[key].used < _triangle_cache[oldest_id].used:
				oldest_id = key
		_triangle_cache.erase(oldest_id)
	_triangle_cache[id] = {"mesh": weakref(mesh), "triangles": triangles, "used": Time.get_ticks_msec()}
	var invalidator := _invalidate_triangle_cache.bind(id)
	if not mesh.changed.is_connected(invalidator):
		mesh.changed.connect(invalidator, CONNECT_ONE_SHOT)
	return triangles


func _invalidate_triangle_cache(id: int) -> void:
	var mesh := instance_from_id(id) as Mesh
	if mesh != null:
		mesh.set_meta("preview_bvh_ready", false)
	_triangle_cache.erase(id)


func _prepare_triangle_cache() -> void:
	# One cold BVH per frame, never a whole batch during the one-second probe.
	# A single very large mesh can still exceed the frame budget; timings expose it.
	_triangle_build_last_ms = 0.0
	if not _triangle_queue.is_empty():
		var queued: WeakRef = _triangle_queue.pop_front()
		var mesh := queued.get_ref() as Mesh
		if mesh != null:
			_triangle_queued.erase(mesh.get_instance_id())
			if not _triangle_cache.has(mesh.get_instance_id()):
				var start := Time.get_ticks_usec()
				_build_triangle_entry(mesh)
				_triangle_build_last_ms = (Time.get_ticks_usec() - start) / 1000.0
				_triangle_build_max_ms = maxf(_triangle_build_max_ms, _triangle_build_last_ms)
	if Engine.get_process_frames() % 120 == 0:
		for id in _triangle_cache.keys():
			if _triangle_cache[id].mesh.get_ref() == null:
				_triangle_cache.erase(id)
		# Dead weak references cannot reveal their old ID. Bound the pending set
		# by rebuilding it from still-live queue items during periodic pruning.
		_triangle_queued.clear()
		for queued in _triangle_queue:
			var mesh := queued.get_ref() as Mesh
			if mesh != null:
				_triangle_queued[mesh.get_instance_id()] = true
