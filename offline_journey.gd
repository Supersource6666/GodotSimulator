extends Node3D
## Independent local-only scene: no Cesium, HTTP, token, or local web server.
## All finest-detail assets are resident before motion; native building BVH queries.

const MANIFEST := "res://offline_data/manifest.json"
const SPEED := 285.0 / 3.6
# 离线桥/轨视觉层：由参考工程的生成器最小适配而来。
const TRACK_GENERATOR_SCRIPT := preload("res://assets/procedural/track_generator.gd")
const BRIDGE_MANAGER_SCRIPT := preload("res://assets/procedural/bridge_manager.gd")
const CATENARY_GENERATOR_SCRIPT := preload("res://assets/procedural/catenary_generator.gd")
const CORRIDOR_SAMPLE_STEP := 2.0   # 更密的桥轨采样，保留平滑路径的小曲率变化
const CORRIDOR_GROUND_OFFSET := 8.0 # 桥面样本点到虚构地面的距离（米）
const TOWER_HEIGHT_M := 92.0        # 瞭望塔相机相对轨面的高度
const TOWER_REACH_M := 360.0        # 瞭望方向沿线路前视距离
const TRACKING_CAMERA_FORWARD_M := 100.0  # 沿实际轨道前方取相机机位，避免弯道切线偏离
const TRACKING_CAMERA_HEIGHT_M := 24.0    # 前侧方低机位，受阻时自动升高
const TRACKING_CAMERA_SIDE_M := 22.0
const TRACKING_CAMERA_LOOK_BACK_M := 8.0  # 跟踪视角相机回看的落点（相对列车锚点，向后）
const ROUTE_TANGENT_DELTA_M := 4.0  # 视觉采样(桥/轨/接触网)朝向的切线基线；±0.8m 太短会放大 1m 级点位抖动
var route := PackedVector3Array()
var distances := PackedFloat64Array()
var assets: Array = []
var pending: Array[String] = []
var loaded := 0
var requested := 0
var failed := false
var ready_for_trip := false
var paused := false
var loop_enabled := false   # --offline-loop：到达品川后自动回到东京继续循环运行
var loop_count := 0
var mileage := 0.0
var elapsed := 0.0
var max_process_ms := 0.0
var test_frames := 0
var camera: Camera3D
var train: Node3D
var label: Label
var panel: PanelContainer
var progress: ProgressBar
var started_ms := 0
var manifest: Dictionary
var memory_at_ready := 0
var frame_times: Array[float] = []
var previous_frame_us := 0
var corridor: Node3D
var vantages: Array[Dictionary] = []
var vantage := -1
var camera_guard := preload("res://camera_obstacle_guard.gd").new()
var camera_collisions_ready := false
var camera_collision_setup_started := false

func _ready() -> void:
	started_ms = Time.get_ticks_msec()
	loop_enabled = "--offline-loop" in OS.get_cmdline_user_args()
	_setup_scene()
	if not FileAccess.file_exists(MANIFEST):
		_fail("本地资源尚未制作，请先运行 build-offline.ps1。")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or not parsed.get("complete", false) or parsed.get("version") != 1:
		_fail("本地资源清单无效；不会回退到网络下载。")
		return
	manifest = parsed
	assets = manifest.get("assets", [])
	for point in manifest.get("route", []):
		if point.size() != 3:
			_fail("线路坐标损坏。")
			return
		route.append(Vector3(point[0], point[1], point[2]))
	if route.size() < 2 or assets.is_empty():
		_fail("本地线路或地形资源为空。")
		return
	route = preload("res://route_smoothing.gd").smooth(route)
	distances.append(0.0)
	for index in range(1, route.size()):
		# Horizontal chainage; visual DEM noise must not lengthen the trip.
		var difference := route[index] - route[index - 1]
		distances.append(distances[-1] + Vector2(difference.x, difference.z).length())
	for asset in assets:
		var relative: String = asset.get("path", "")
		if not relative.begins_with("offline_data/models/") or ".." in relative or ":" in relative or "\\" in relative:
			_fail("清单包含非本地路径，已拒绝加载。")
			return
		var file := FileAccess.open("res://" + relative, FileAccess.READ)
		if file == null or file.get_length() != int(asset.get("bytes", -1)):
			_fail("本地文件缺失或不完整：" + relative)
			return
		file.close()
	train = load("res://train_visual.gd").new()
	add_child(train)
	# 4 节编组需要按线路里程逐节定位（参考 train_demo_scene.gd 的编组跟随逻辑）。
	train.set_pose_source(Callable(self, "_route_pose_sample"))
	_update_position()
	_refresh_ui()
	# 桥/轨视觉层在首帧内构建（不阻塞资源异步加载）。
	_route_visual_setup.call_deferred()

func _route_visual_setup() -> void:
	if corridor == null:
		_build_offline_corridor()
	_build_vantages()
	if "--offline-tower" in OS.get_cmdline_user_args() and not vantages.is_empty():
		vantage = 0
	if vantage >= 0:
		_update_position()

func _setup_scene() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#c3d9e8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Clear daylight: no atmospheric veil or blue ambient wash over imagery.
	environment.ambient_light_color = Color.WHITE
	# Keep the fill low: uniform 0.45 white fill was flattening the aerial
	# imagery into a milky grey. Lower fill restores shadow contrast.
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	# Mild post-process contrast/saturation to cut the flat, hazed look of the
	# orthoimagery. This only restores tonal range; it adds no real detail.
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.1
	environment.adjustment_saturation = 1.06
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450
	add_child(sun)
	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = 2400.0
	camera.fov = 48.0
	camera.current = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(555, 220)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.07, 0.8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 18)
	column.add_child(label)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 20)
	column.add_child(progress)
	var credits := AcceptDialog.new()
	credits.name = "DataCredits"
	credits.title = "数据来源与说明"
	credits.dialog_text = "本地数据：国土交通省 PLATEAU／国土地理院（加工）／© OpenStreetMap contributors\n航空影像 + 城市建筑模型；不是 Google 实景摄影测量。轨道高度为可视化估计。"
	add_child(credits)
	var about := Button.new()
	about.text = "数据来源与说明（F1）"
	about.pressed.connect(func(): credits.popup_centered())
	column.add_child(about)

func _load_step() -> void:
	while pending.size() < 4 and requested < assets.size():
		var path: String = "res://" + str(assets[requested].path)
		if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
			_fail("本地模型导入失败：" + path + "\n请运行 build-offline.ps1 完成 Godot 导入。")
			return
		pending.append(path)
		requested += 1
	for path in pending:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail("本地模型加载失败：" + path)
			return
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			if packed == null:
				_fail("本地文件不是场景：" + path)
				return
			var instance := packed.instantiate()
			add_child(instance)
			if not path.get_file().begins_with("ground_"):
				camera_guard.add_buildings(instance)
			for mesh in instance.find_children("*", "MeshInstance3D", true, false):
				mesh.visibility_range_end = 1800.0
				mesh.visibility_range_end_margin = 150.0
				for surface in mesh.mesh.get_surface_count():
					var material = mesh.mesh.surface_get_material(surface)
					if material is BaseMaterial3D:
						material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			pending.erase(path)
			loaded += 1
			break # Budget one scene instantiation per frame; no frame-spanning loop.
	if loaded == assets.size() and train.ready_for_preview:
		if not camera_collisions_ready:
			if not camera_collision_setup_started:
				camera_collision_setup_started = true
				_finish_camera_collision_setup()
			return
		ready_for_trip = true
		_update_position()
		memory_at_ready = OS.get_static_memory_usage()
		print("OFFLINE_READY assets=", loaded, " route_m=", distances[-1],
			" startup_ms=", Time.get_ticks_msec() - started_ms,
			" static_memory_bytes=", memory_at_ready,
			" network_nodes=", find_children("*", "HTTPRequest", true, false).size())
		if "--offline-capture" in OS.get_cmdline_user_args():
			mileage = _capture_mileage()
			paused = true
			_update_position()
	_refresh_ui()

func _finish_camera_collision_setup() -> void:
	# Allow the physics server to register the final building colliders.
	await get_tree().physics_frame
	await get_tree().physics_frame
	camera_collisions_ready = true
	print("CAMERA_COLLIDERS_READY meshes=", camera_guard.collision_meshes,
		" max_build_ms=", camera_guard.max_collider_build_ms)

# ══════════════════════════════════════════
# 离线桥/轨视觉层（无 Cesium、无物理地形射线）
# ══════════════════════════════════════════

func _build_offline_corridor() -> void:
	if corridor != null:
		return
	corridor = Node3D.new()
	corridor.name = "OfflineCorridorVisual"
	add_child(corridor)
	var samples := _build_route_samples()
	if samples.size() < 2:
		push_warning("Offline corridor: 路线样本不足，跳过桥/轨视觉层。")
		return
	var track = TRACK_GENERATOR_SCRIPT.new()
	track.name = "MainTrack"
	corridor.add_child(track)
	track.set_custom_samples(samples)
	track.generate_track_mesh()
	# Keep the train route fixed; place the other line on its left.
	var parallel = TRACK_GENERATOR_SCRIPT.new()
	parallel.name = "ParallelTrack"
	corridor.add_child(parallel)
	parallel.set_custom_samples(TRACK_GENERATOR_SCRIPT.offset_samples(samples, -4.2))
	parallel.generate_track_mesh()
	var bridge = BRIDGE_MANAGER_SCRIPT.new()
	corridor.add_child(bridge)
	bridge.virtual_ground_offset_m = CORRIDOR_GROUND_OFFSET
	# space_state = null → 桥生成器自动走“虚构地面”分支，不做物理射线。
	# A 12 m deck centered between the tracks leaves 2.1 m outside each bed.
	bridge.build_bridge(TRACK_GENERATOR_SCRIPT.offset_samples(samples, -2.1), distances[-1], corridor, null)
	var overhead = CATENARY_GENERATOR_SCRIPT.new()
	corridor.add_child(overhead)
	overhead.build(distances[-1], _route_pose_sample)


func _build_route_samples() -> Array[Dictionary]:
	# point 为桥面（道砟底）位置：轨面 = 桥面 + 道砟厚 + 钢轨高 = route.y。
	var probe = TRACK_GENERATOR_SCRIPT.new()
	var deck_lift := float(probe.ballast_height_m) + float(probe.sleeper_height_m) + float(probe.rail_height_m)
	probe.free()
	var total := distances[-1]
	var count := int(floor(total / CORRIDOR_SAMPLE_STEP)) + 1
	var samples: Array[Dictionary] = []
	for index in range(count):
		var distance := float(index) * CORRIDOR_SAMPLE_STEP
		samples.append(_route_pose_sample(minf(total, distance), -deck_lift))
	if samples.is_empty() or float(samples[samples.size() - 1]["distance"]) < total - 0.1:
		samples.append(_route_pose_sample(total, -deck_lift))
	return samples


func _route_pose_sample(distance: float, vertical_offset: float) -> Dictionary:
	var p := sample(distance)
	var p_front := sample(clampf(distance + ROUTE_TANGENT_DELTA_M, 0.0, distances[-1]))
	var p_back := sample(clampf(distance - ROUTE_TANGENT_DELTA_M, 0.0, distances[-1]))
	var up := Vector3.UP
	var tangent := p_front - p_back
	var forward := tangent - up * tangent.dot(up)
	if forward.length_squared() <= 0.000001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	if right.length_squared() <= 0.000001:
		right = Vector3.RIGHT
	return {
		"point": p + up * vertical_offset,
		"forward": forward,
		"right": right,
		"up": up,
		"distance": distance,
	}


func _capture_mileage() -> float:
	if vantage >= 0 and vantage < vantages.size():
		return float(vantages[vantage]["anchor"])
	return minf(1200.0, distances[-1])


# ── 塔架瞭望视角 ─────────────────────────

func _build_vantages() -> void:
	vantages.clear()
	var total := distances[-1]
	if total < 2400.0:
		return
	# 正向（东京→品川方向）与反向各找一个较直的区段中点。
	var forward_anchor := _find_straight_center(400.0, total - TOWER_REACH_M)
	var backward_anchor := _find_straight_center(TOWER_REACH_M, total - 400.0)
	vantages.append(_make_vantage(forward_anchor, 1.0, "东京→品川方向"))
	vantages.append(_make_vantage(backward_anchor, -1.0, "品川→东京方向"))


func _find_straight_center(from_dist: float, to_dist: float) -> float:
	var best := (from_dist + to_dist) * 0.5
	var best_score := -1.0
	var scan := from_dist
	while scan <= to_dist:
		var score := _heading_at(scan + 40.0).dot(_heading_at(scan + TOWER_REACH_M - 40.0))
		if score > best_score:
			best_score = score
			best = scan + TOWER_REACH_M * 0.5
		scan += 200.0
	return clampf(best, 0.0, distances[-1])


func _heading_at(distance: float) -> Vector3:
	var clamped := clampf(distance, 0.0, distances[-1])
	var delta := minf(40.0, maxf(1.0, distances[-1] * 0.01))
	var heading := sample(clamped + delta) - sample(maxf(0.0, clamped - delta))
	heading.y = 0.0
	return heading.normalized() if heading.length_squared() > 0.000001 else Vector3.FORWARD


func _make_vantage(anchor_distance: float, look_dir: float, vantage_name: String) -> Dictionary:
	var anchor := clampf(anchor_distance, 0.0, distances[-1])
	var base := sample(anchor)
	var target := sample(clampf(anchor + look_dir * TOWER_REACH_M, 0.0, distances[-1]))
	return {
		"name": vantage_name,
		"anchor": anchor,
		"pos": base + Vector3.UP * TOWER_HEIGHT_M,
		"target": target,
	}


func _process(delta: float) -> void:
	if failed:
		return
	var before := Time.get_ticks_usec()
	elapsed += delta
	if not ready_for_trip:
		_load_step()
	else:
		if not paused:
			var previous_mileage := mileage
			mileage = minf(mileage + SPEED * delta, distances[-1])
			_update_position(delta)
			if camera_guard.blocked:
				# No clear view: stop at the last valid train pose, not inside
				# an obstacle. Space retries, V can select another view.
				mileage = previous_mileage
				paused = true
				_update_position()
				camera_guard.blocked = true
			if mileage >= distances[-1]:
				if loop_enabled:
					# 循环模式：到达品川后自动回到东京起点，持续运行。
					mileage = 0.0
					loop_count += 1
					_update_position()
				else:
					paused = true
		test_frames += 1
		if test_frames > 10 and previous_frame_us > 0:
			# Engine delta may be smoothed to the vsync interval. Use the
			# monotonic wall clock to expose real stalls in benchmark results.
			frame_times.append((before - previous_frame_us) / 1000.0)
		previous_frame_us = before
		if "--offline-test" in OS.get_cmdline_user_args() and test_frames % 3 == 0:
			_test_position(minf((test_frames / 3 - 1) * 100.0, distances[-1]))
		if "--offline-capture" in OS.get_cmdline_user_args() and test_frames == 60:
			capture()
		if "--demo-smoke-test" in OS.get_cmdline_user_args() and test_frames >= 120:
			print("OFFLINE_SMOKE PASS")
			get_tree().quit(0)
		if "--offline-benchmark" in OS.get_cmdline_user_args() and mileage >= distances[-1]:
			frame_times.sort()
			print("OFFLINE_BENCHMARK PASS frame_median_ms=", frame_times[frame_times.size() / 2],
				" frame_p95_ms=", frame_times[int(frame_times.size() * 0.95)],
				" frame_max_ms=", frame_times[-1], " moving_script_max_ms=", max_process_ms,
				" video_memory_bytes=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
			get_tree().quit(0)
		_refresh_ui()
		max_process_ms = maxf(max_process_ms, (Time.get_ticks_usec() - before) / 1000.0)

func sample(distance: float) -> Vector3:
	distance = clampf(distance, 0.0, distances[-1])
	var index := 0
	var high := distances.size() - 1
	while high - index > 1:
		var middle := (index + high) / 2
		if distance > distances[middle]:
			index = middle
		else:
			high = middle
	var fraction := (distance - distances[index]) / maxf(distances[index + 1] - distances[index], 0.001)
	return route[index].lerp(route[index + 1], fraction)

func _update_position(delta: float = 0.0) -> void:
	var point := sample(mileage)
	var heading := sample(mileage + 12) - sample(mileage - 12)
	heading.y = 0
	heading = heading.normalized()
	train.position = point
	train.look_at(point + heading, Vector3.UP)
	train.anchor_distance = mileage
	if vantage >= 0 and vantage < vantages.size():
		var v: Dictionary = vantages[vantage]
		if not camera_collisions_ready or camera_guard.clear_view(get_world_3d().direct_space_state,
				v["pos"], PackedVector3Array([v["target"] + Vector3.UP * 3.0])):
			camera_guard.blocked = false
			camera_guard.initialized = false
			camera.position = v["pos"] as Vector3
			camera.look_at(v["target"] as Vector3, Vector3.UP)
			return
		# An obstructed tower view falls back to the protected tracking view.
		vantage = -1
	var target := sample(mileage - TRACKING_CAMERA_LOOK_BACK_M) + Vector3.UP * 2.5
	if camera_collisions_ready:
		var spacing: float = train.CAR_CENTER_SPACING_M
		var front := float(train.CONSIST_CAR_COUNT - 1) * 0.5 * spacing
		var targets := PackedVector3Array()
		for index in range(train.CONSIST_CAR_COUNT):
			targets.append(sample(mileage + front - spacing * float(index)) + Vector3.UP * 3.0)
		camera.position = camera_guard.resolve(get_world_3d().direct_space_state, sample, mileage,
			targets, camera.position, delta, TRACKING_CAMERA_FORWARD_M, TRACKING_CAMERA_HEIGHT_M, TRACKING_CAMERA_SIDE_M)
	else:
		var pose := _route_pose_sample(mileage + TRACKING_CAMERA_FORWARD_M, TRACKING_CAMERA_HEIGHT_M)
		camera.position = pose.point + pose.right * TRACKING_CAMERA_SIDE_M
	var aim: Vector3 = camera_guard.aim_target if camera_guard.partial_view else target
	var direction := (aim - camera.position).normalized()
	# A fully shortened camera may look straight down at the route endpoint.
	camera.look_at(aim, heading if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP)

func _refresh_ui() -> void:
	var status := "整段资源已就绪" if ready_for_trip else "本地资源准备中，列车等待"
	if paused:
		status = "已暂停" if mileage < distances[-1] else "已到达品川"
	elif loop_enabled:
		status = "循环运行中（第 %d 圈）" % (loop_count + 1)
	var view_text := "跟踪视角"
	if camera_guard.blocked:
		status = "建筑遮挡，已停止前进；Space 重试 / V 换视角"
	elif camera_guard.adjusted:
		view_text = "跟踪视角（建筑避障）"
	if camera_guard.partial_view:
		view_text = "跟踪视角（部分车厢经过遮挡物）"
	if ready_for_trip and vantage >= 0 and vantage < vantages.size():
		view_text = "瞭望：" + str(vantages[vantage]["name"])
	var loop_text := "循环：开" if loop_enabled else "循环：关"
	label.text = "东海道新干线 · 东京 → 品川 · 本地版\n里程：%.2f / %.2f km    速度：285 km/h\n范围：轨道两侧各 500 m    航空影像：Z18\n资源：%d / %d    状态：%s    循环：%s\n视角：%s\nSpace：暂停/继续    R：重新预览    V：切换瞭望视角    L：切换循环\n无需网络／无需 Cesium Token（命令行加 --offline-loop 启动即循环）" % [mileage / 1000, distances[-1] / 1000, loaded, assets.size(), status, loop_text, view_text]
	progress.value = 100.0 * mileage / distances[-1] if ready_for_trip else 100.0 * loaded / max(1, assets.size())

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F1:
		get_node("DataCredits").popup_centered()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_G and event.ctrl_pressed and event.shift_pressed and not event.alt_pressed and not event.meta_pressed:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()
		return
	if not ready_for_trip:
		return
	if event.keycode == KEY_SPACE:
		paused = not paused
	elif event.keycode == KEY_R:
		mileage = 0.0
		paused = false
		_update_position()
	elif event.keycode == KEY_V:
		vantage += 1
		if vantage >= vantages.size():
			vantage = -1
		_update_position()
	elif event.keycode == KEY_L:
		loop_enabled = not loop_enabled
		if loop_enabled and mileage >= distances[-1]:
			mileage = 0.0
			loop_count = 0
			paused = false
		_update_position()

func _fail(message: String) -> void:
	failed = true
	label.text = "本地加载停止\n" + message
	push_error(message)
	if "--offline-test" in OS.get_cmdline_user_args() or "--demo-smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit(1)

func _test_position(distance: float) -> void:
	mileage = distance
	paused = true
	_update_position()
	if camera_guard.blocked:
		_fail("建筑遮挡：没有安全相机机位，里程 " + str(distance))
		return
	if not camera.is_position_in_frustum(train.position + Vector3.UP * 2):
		_fail("列车离开视锥")
		return
	var covered := false
	for item in assets:
		if item.kind == "ground":
			var lo: Array = item.min
			var hi: Array = item.max
			if train.position.x >= lo[0] and train.position.x <= hi[0] and train.position.z >= lo[2] and train.position.z <= hi[2]:
				covered = true
				break
	if not covered:
		_fail("线路地面资源存在缺口")
		return
	if distance >= distances[-1]:
		frame_times.sort()
		print("OFFLINE_ROUTE_TEST PASS route_m=", distances[-1], " positions_every_m=100",
			" moving_script_max_ms=", max_process_ms, " assets=", loaded,
			" frame_median_ms=", frame_times[frame_times.size() / 2],
			" camera_query_max_ms=", camera_guard.max_query_ms)
		get_tree().quit(0)

func capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://offline-preview.png")
	print("OFFLINE_CAPTURE ", error, " moving_script_max_ms=", max_process_ms,
		" video_memory_bytes=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	get_tree().quit(0)
