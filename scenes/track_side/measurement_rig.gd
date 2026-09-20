extends Node3D
## Synthetic structured-light acquisition; source numbers are scene calibration.
const RAY_COUNT := 512
const FULL_SIZE := Vector2i(1280, 1024)
const LIVE_SIZE := Vector2i(640, 512)
const CROP := Rect2i(240, 176, 800, 672)
const DEFAULT_ROOT := "C:/DoctorDegreeWork/LY/WLI-set/track_side_sim"
const HALF_WIDTH := 0.0009
var channels: Array[Dictionary] = []
var enabled := true
var saving := false
var multiline := true
var wheelset: Node3D
var scene_root: Node3D
var fan_root: Node3D
var panel: PanelContainer
var status: Label
var laser_button: Button
var pattern: OptionButton
var path_input: LineEdit
var sample_serial := 0
var elapsed := 0.0
var dirty := true
var previous_z := INF
var previous_visible := false
var beam_material: StandardMaterial3D
var blue_material: StandardMaterial3D
var white_material: StandardMaterial3D
var black_material: StandardMaterial3D
var last_directory := ""

func setup(scene: Node3D, wheels: Node3D, beams: Node3D, canvas: CanvasLayer) -> void:
	scene_root = scene
	wheelset = wheels
	fan_root = beams
	beam_material = _unshaded(Color(0.08, 0.25, 1.0, 0.10))
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blue_material = _unshaded(Color(0.12, 0.5, 1.0))
	white_material = _unshaded(Color.WHITE)
	black_material = _unshaded(Color.BLACK)
	for wheel in wheels.get_children():
		if wheel is MeshInstance3D:
			_collider(wheel, wheel.mesh.create_trimesh_shape(), 2)
			_black_copy(wheel)
		elif wheel.has_node("FlangedWheel"):
			var mesh: MeshInstance3D = wheel.get_node("FlangedWheel")
			var shape := mesh.mesh.create_trimesh_shape()
			shape.backface_collision = true
			_collider(mesh, shape, 2)
			_black_copy(mesh)
	for mesh in scene.get_node("Track").get_children():
		if mesh is MeshInstance3D and str(mesh.get_meta("part", "")) in ["RailHead", "RailWeb", "RailFoot", "Sleeper"]:
			_box_collider(mesh)
			_black_copy(mesh)
	for unit in scene.get_node("MeasurementStation").get_children():
		if not unit.has_node("Laser") or not unit.has_node("Camera"):
			continue
		for mesh in unit.get_children():
			if mesh is MeshInstance3D:
				_black_copy(mesh)
				if str(mesh.get_meta("part", "")) in ["ConcretePlinth", "SensorEnclosure", "TopCover"]:
					_box_collider(mesh)
		var laser: Node3D = unit.get_node("Laser")
		var lens: Node3D = unit.get_node("Camera")
		var source := laser.to_global(Vector3(0, 0, -0.095))
		var rail_side := -1.0 if unit.position.x < 0 else 1.0
		var viewport := SubViewport.new()
		viewport.name = str(unit.name) + "Capture"
		viewport.size = LIVE_SIZE
		viewport.world_3d = scene.get_world_3d()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.gui_disable_input = true
		add_child(viewport)
		var cam := Camera3D.new()
		cam.near = 0.008
		cam.far = 12.0
		cam.fov = 44.0
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.cull_mask = 8 | (16 << channels.size())
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		cam.environment = env
		viewport.add_child(cam)
		cam.global_transform = lens.global_transform
		cam.global_position = lens.to_global(Vector3(0, 0, -0.12))
		cam.current = true
		var fan := MeshInstance3D.new()
		fan.name = str(unit.name) + "LightPlanes"
		fan.layers = 2
		fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fan_root.add_child(fan)
		var stripe := MeshInstance3D.new()
		stripe.name = str(unit.name) + "SurfaceStripes"
		stripe.material_override = blue_material
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stripe)
		var monochrome := MeshInstance3D.new()
		monochrome.name = str(unit.name) + "FilteredStripes"
		monochrome.layers = 16 << channels.size()
		monochrome.material_override = white_material
		monochrome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(monochrome)
		channels.append({"id": str(unit.name), "source": source, "rail_side": rail_side,
			"fan": fan, "stripe": stripe, "filtered": monochrome, "viewport": viewport,
			"camera": cam, "hits": 0, "wheel_hits": 0, "slit": laser.get_node("LaserSlit"),
			"planes": [], "samples": []})
	_build_panel(canvas)

func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _black_copy(mesh: MeshInstance3D) -> void:
	var copy := MeshInstance3D.new()
	copy.name = "OpticalOccluder"
	copy.mesh = mesh.mesh
	copy.material_override = black_material
	copy.layers = 8
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.add_child(copy)

func _collider(mesh: MeshInstance3D, shape: Shape3D, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = "LaserSurface"
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	mesh.add_child(body)

func _box_collider(mesh: MeshInstance3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = (mesh.mesh as BoxMesh).size
	_collider(mesh, shape, 1)

func _physics_process(delta: float) -> void:
	elapsed += delta
	if channels.is_empty() or not enabled:
		return
	if (dirty or previous_z != wheelset.position.z or previous_visible != wheelset.visible) and elapsed >= 0.10:
		_scan()
		elapsed = 0
		previous_z = wheelset.position.z
		previous_visible = wheelset.visible
		dirty = false

func _scan() -> void:
	var space := get_world_3d().direct_space_state
	var mask := 3 if wheelset.visible else 1
	for channel in channels:
		var source: Vector3 = channel.source
		var beam := SurfaceTool.new()
		beam.begin(Mesh.PRIMITIVE_TRIANGLES)
		beam.set_material(beam_material)
		var stripe := SurfaceTool.new()
		stripe.begin(Mesh.PRIMITIVE_TRIANGLES)
		var stripe_vertices := 0
		channel.hits = 0
		channel.wheel_hits = 0
		channel.samples = []
		channel.planes = []
		# All planes contain the emitter and the axle direction X. The center
		# plane passes through the axle at the nominal trigger pose (z = 0).
		var radial := Vector3(0, 0.95 - source.y, -source.z).normalized()
		var plane_count := 13 if multiline else 1
		for line_id in range(plane_count):
			var angle := (float(line_id) - (plane_count - 1) * 0.5) * 0.042
			var direction_yz := radial.rotated(Vector3.RIGHT, angle)
			var normal := Vector3.RIGHT.cross(direction_yz).normalized()
			channel.planes.append({"laser_id": line_id, "normal": _v(normal), "d": -normal.dot(source)})
			# Aim at a nominal 460 mm circular rim; actual first intersections
			# come from the full flanged triangle mesh, not this aiming circle.
			var offset := Vector3(0, source.y - 0.95, source.z)
			var b := offset.dot(direction_yz)
			var discriminant := b * b - (offset.length_squared() - 0.46 * 0.46)
			var travel := -b - sqrt(maxf(discriminant, 0.0001))
			var center := source + direction_yz * travel
			var previous: Dictionary = {}
			var last_endpoint := Vector3.ZERO
			for index in range(RAY_COUNT + 1):
				var aim := Vector3(channel.rail_side * 0.7525 + lerpf(-0.20, 0.20, float(index) / RAY_COUNT), center.y, center.z)
				var direction := (aim - source).normalized()
				var endpoint := source + direction * 1.6
				var query := PhysicsRayQueryParameters3D.create(source, endpoint, mask)
				query.hit_back_faces = true
				var hit := space.intersect_ray(query)
				if not hit.is_empty():
					endpoint = hit.position
					if hit.normal.dot(source - endpoint) < 0:
						hit.normal = -hit.normal
					channel.hits += 1
					var body: CollisionObject3D = hit.collider
					if body.collision_layer == 2 and body.get_parent().name == "FlangedWheel":
						channel.wheel_hits += 1
						channel.samples.append({"laser_id": line_id, "point": endpoint})
					if not previous.is_empty() and previous.collider_id == hit.collider_id and endpoint.distance_to(previous.position) < 0.008:
						var p: Vector3 = previous.position + previous.normal * 0.00003
						var q: Vector3 = endpoint + hit.normal * 0.00003
						var width: Vector3 = (q - p).normalized().cross(hit.normal).normalized() * HALF_WIDTH
						for point in [p - width, q - width, q + width, p - width, q + width, p + width]:
							stripe.add_vertex(point)
						stripe_vertices += 6
				if index > 0 and not hit.is_empty() and not previous.is_empty():
					for point in [source, last_endpoint, endpoint]:
						beam.add_vertex(point)
				last_endpoint = endpoint
				previous = hit
		channel.fan.mesh = beam.commit()
		channel.stripe.mesh = stripe.commit() if stripe_vertices > 0 else null
		channel.filtered.mesh = channel.stripe.mesh
		channel.counter.text = "%d planes / %d hits" % [plane_count, channel.wheel_hits]
	sample_serial += 1

func set_enabled(value: bool) -> void:
	enabled = value
	fan_root.visible = value
	for channel in channels:
		channel.stripe.visible = value
		channel.filtered.visible = value
		channel.slit.visible = value
		if not value:
			channel.counter.text = "Laser off"
	laser_button.text = "L  Laser ON" if value else "L  Laser OFF"
	dirty = true

func set_multiline(value: bool) -> void:
	multiline = value
	pattern.select(1 if value else 0)
	dirty = true

func toggle_panel() -> void:
	panel.visible = not panel.visible

func _build_panel(canvas: CanvasLayer) -> void:
	var layout := Control.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(layout)
	panel = PanelContainer.new()
	layout.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -434
	panel.offset_right = -16
	panel.offset_top = 16
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.07, 0.95)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	var title := Label.new()
	title.text = "WHEEL PROFILE / FILTERED CAMERAS"
	title.add_theme_font_size_override("font_size", 15)
	column.add_child(title)
	pattern = OptionButton.new()
	pattern.add_item("Single plane - Sensors 2018 layout")
	pattern.add_item("13 planes - WLI-Set style (simulation)")
	pattern.select(1)
	pattern.item_selected.connect(func(index: int) -> void:
		if not saving: set_multiline(index == 1))
	column.add_child(pattern)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	column.add_child(grid)
	for channel in channels:
		var card := VBoxContainer.new()
		grid.add_child(card)
		var caption := Label.new()
		caption.text = channel.id.replace("Sensor", "").replace("Outer", " / OUTER").replace("Inner", " / INNER").to_upper()
		caption.add_theme_font_size_override("font_size", 12)
		card.add_child(caption)
		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(192, 144)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture = channel.viewport.get_texture()
		card.add_child(image)
		var counter := Label.new()
		counter.add_theme_font_size_override("font_size", 10)
		counter.modulate = Color("85baf2")
		card.add_child(counter)
		channel.counter = counter
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	laser_button = Button.new()
	laser_button.text = "L  Laser ON"
	laser_button.pressed.connect(func() -> void:
		if not saving: set_enabled(not enabled))
	buttons.add_child(laser_button)
	for batch in [false, true]:
		var button := Button.new()
		button.text = "B  Batch" if batch else "P  Capture"
		button.pressed.connect(capture_dataset.bind(batch))
		buttons.add_child(button)
	path_input = LineEdit.new()
	path_input.text = DEFAULT_ROOT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wli-root="): path_input.text = arg.trim_prefix("--wli-root=")
	path_input.tooltip_text = "Synthetic output root; existing WLI-Set archives are preserved."
	column.add_child(path_input)
	status = Label.new()
	status.text = "1280x1024 -> 800x672 | G: single/multi\nCapture exports images, calibration and profiles."
	status.custom_minimum_size.x = 390
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 11)
	column.add_child(status)

func _v(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func capture_dataset(batch: bool = false, explicit_directory: String = "") -> bool:
	if saving or DisplayServer.get_name() == "headless":
		return false
	saving = true
	var old_moving: bool = scene_root.moving
	var old_position := wheelset.position
	var old_visible := wheelset.visible
	var old_enabled := enabled
	var old_pattern := multiline
	scene_root.moving = false
	wheelset.visible = true
	set_enabled(true)
	var root := path_input.text.strip_edges()
	if root.is_empty(): root = DEFAULT_ROOT
	var directory := explicit_directory
	if directory.is_empty():
		directory = root.path_join(Time.get_datetime_string_from_system().replace(":", "-") + "_%d" % Time.get_ticks_msec())
	var ok := true
	for folder in ["raw_1280", "sensor", "calibration", "geometry"]:
		var error := DirAccess.make_dir_recursive_absolute(directory.path_join(folder))
		if error != OK:
			status.text = "Cannot create output: " + error_string(error)
			ok = false
			break
	var manifest := {"schema": 1, "provenance": "GODOT_SYNTHETIC_NOT_REAL_WLI_SET",
		"unit": "metre", "crop_xywh": [240, 176, 800, 672],
		"papers": ["10.3390/s18124296", "10.1038/s41597-024-03288-y"],
		"plane_count_note": "13 is a local simulation setting, not a published calibration value",
		"pixel_convention": "integer pixel indices denote pixel centers; OpenCV camera axes x-right y-down z-forward",
		"records": []}
	var variants: Array = [false, true] if batch else [multiline]
	var offsets: Array = [-0.025, 0.0, 0.025] if batch else [wheelset.position.z]
	if ok:
		for channel in channels: channel.viewport.size = FULL_SIZE
		for mode in variants:
			if not ok: break
			set_multiline(mode)
			for index in range(offsets.size()):
				wheelset.position.z = offsets[index]
				dirty = true
				for frame in range(12): await get_tree().physics_frame
				for frame in range(3): await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var prefix := ("multi" if mode else "single") + "_%02d" % index
				status.text = "Capturing " + prefix + "..."
				for channel in channels:
					var id := prefix + "_" + str(channel.id)
					var image: Image = channel.viewport.get_texture().get_image()
					image.convert(Image.FORMAT_L8)
					var error := image.save_png(directory.path_join("raw_1280/" + id + ".png"))
					if error == OK:
						error = image.get_region(CROP).save_png(directory.path_join("sensor/" + id + ".png"))
					var cam: Camera3D = channel.camera
					var projection := cam.get_camera_projection()
					var basis := cam.global_basis
					var cx := FULL_SIZE.x * 0.5 - CROP.position.x - 0.5
					var cy := FULL_SIZE.y * 0.5 - CROP.position.y - 0.5
					var calibration := {"status": "EXACT_SIMULATION_CAMERA_AND_PLANES",
						"id": id, "channel": channel.id, "mode": "multi" if mode else "single",
						"size_wh": [800, 672], "full_size_wh": [1280, 1024], "crop_xywh": [240, 176, 800, 672],
						"K": [[projection.x.x * 640, 0, cx], [0, projection.y.y * 512, cy], [0, 0, 1]],
						"distortion": [0, 0, 0, 0, 0],
						"R_camera_to_world": [[basis.x.x, -basis.y.x, -basis.z.x], [basis.x.y, -basis.y.y, -basis.z.y], [basis.x.z, -basis.y.z, -basis.z.z]],
						"t_camera_to_world_m": _v(cam.global_position), "laser_source_m": _v(channel.source),
						"planes_world": channel.planes, "wheel_center_m": [channel.rail_side * 0.7525, 0.95, wheelset.position.z],
						"axial_sign": channel.rail_side, "scan": sample_serial,
						"stripe_width_m": HALF_WIDTH * 2.0, "render_surface_offset_m": 0.00003}
					var projected: Array = []
					for sample in channel.samples:
						var point: Vector3 = sample.point
						if cam.is_position_behind(point): continue
						var pixel := cam.unproject_position(point) - Vector2(CROP.position) - Vector2(0.5, 0.5)
						if pixel.x >= -10 and pixel.y >= -10 and pixel.x < 810 and pixel.y < 682:
							projected.append([pixel.x, pixel.y, sample.laser_id, point.x, point.y, point.z])
					var truth: Array = []
					for point in wheelset.get_node("RightWheel").get_meta("profile_xr"):
						truth.append([point.x * 1000, point.y * 1000])
					var geometry := {"usage": "Ground truth for evaluation and simulated laser-ID correspondence only; not reconstructed coordinates",
						"columns": ["u", "v", "laser_id", "world_x_m", "world_y_m", "world_z_m"],
						"samples": projected, "reference_profile_xr_mm": truth}
					ok = error == OK and _save_json(directory.path_join("calibration/" + id + ".json"), calibration) and _save_json(directory.path_join("geometry/" + id + ".json"), geometry)
					if not ok:
						status.text = "Capture write failed: " + id
						break
					manifest.records.append({"id": id, "channel": channel.id, "mode": calibration.mode, "wheel_z_m": wheelset.position.z})
				if not ok: break
	if ok:
		ok = _save_json(directory.path_join("manifest.json"), manifest)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("scene_preview.png"))
	for channel in channels: channel.viewport.size = LIVE_SIZE
	wheelset.position = old_position
	wheelset.visible = old_visible
	set_multiline(old_pattern)
	set_enabled(old_enabled)
	if ok:
		status.text = "Extracting image centerlines and profiles..."
		ok = await _postprocess(directory)
	if ok:
		last_directory = directory
		status.text = "Saved images + profiles:\n" + directory
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("scene_preview.png"))
		print("WLI_OUTPUT ", directory)
	scene_root.moving = old_moving
	saving = false
	return ok

func _save_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func _postprocess(directory: String) -> bool:
	var python := OS.get_environment("LOCALAPPDATA").path_join("miniconda3/python.exe")
	if not FileAccess.file_exists(python): python = "python"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wli-python="): python = arg.trim_prefix("--wli-python=")
	var script := ProjectSettings.globalize_path("res://tools/track_side_reconstruct.py")
	var pid := OS.create_process(python, PackedStringArray([script, "--dataset", ProjectSettings.globalize_path(directory)]), false)
	if pid < 0:
		status.text = "Images saved; Python could not start. Run tools/track_side_reconstruct.py manually."
		return false
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.25).timeout
	var result_path := directory.path_join("processing_result.json")
	if not FileAccess.file_exists(result_path):
		status.text = "Images saved; extraction failed. See processing_error.txt in the output directory."
		return false
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
	if not result is Dictionary or not result.get("success", false):
		status.text = "Images saved; profile validation failed. See processing_result.json."
		return false
	return true
