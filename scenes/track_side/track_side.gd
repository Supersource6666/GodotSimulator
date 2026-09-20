extends Node3D
## Reference-inspired wheel measurement installation. Dimensions are illustrative.
const Batch := preload("res://assets/procedural/detail_batch.gd")
const MeasurementRig := preload("res://scenes/track_side/measurement_rig.gd")
var measurement: Node3D
const RAIL_X := 0.7525
const RAIL_TOP := 0.49
var camera: Camera3D
var wheels: Node3D
var lasers: Node3D
var labels: Node3D
var hud: CanvasLayer
var target := Vector3(0, 0.2, 0)
var yaw := 0.28
var pitch := 0.88
var distance := 6.8
var moving := false
var units := 0
var mats: Dictionary = {}

func _ready() -> void:
	_materials()
	_environment()
	_track()
	_equipment()
	_wheelset()
	camera = Camera3D.new()
	camera.name = "InspectionCamera"
	camera.near = 0.025
	camera.fov = 48
	add_child(camera)
	camera.current = true
	camera.cull_mask = 7
	_interface()
	measurement = MeasurementRig.new()
	measurement.name = "OpticalMeasurementRig"
	add_child(measurement)
	measurement.setup(self, wheels, lasers, hud)
	_view(2)
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		_smoke.call_deferred()
	if "--wli-batch" in OS.get_cmdline_user_args() or "--track-side-capture" in OS.get_cmdline_user_args() or "--wli-preview" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _materials() -> void:
	for entry in [["concrete", "aeb4b0", 0.96, 0.0], ["housing", "b6c4be", 0.7, 0.22],
		["edge", "738985", 0.65, 0.4], ["steel", "a3aeb3", 0.29, 0.8],
		["rust", "664e3c", 0.87, 0.45], ["dark", "252e34", 0.73, 0.3],
		["blue", "252aad", 0.26, 0.5], ["glass", "101b38", 0.13, 0.65],
		["cable", "171c20", 0.9, 0.0], ["yellow", "e4bd52", 0.65, 0.15],
		["wheel", "535d67", 0.3, 0.8]]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(entry[1])
		mat.roughness = entry[2]
		mat.metallic = entry[3]
		mats[entry[0]] = mat
	var concrete: StandardMaterial3D = mats.concrete
	var noise := FastNoiseLite.new()
	noise.frequency = 0.16
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.55, 0.56, 0.54), Color(0.87, 0.88, 0.85)])
	texture.color_ramp = ramp
	concrete.albedo_texture = texture
	concrete.uv1_triplanar = true
	concrete.uv1_scale = Vector3(3, 3, 3)
	var light := StandardMaterial3D.new()
	light.albedo_color = Color("718bff")
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats.light = light

func _environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_color = Color("b9c6cd")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d9e4f0")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("728ba1")
	sky_material.sky_horizon_color = Color("c3cdd2")
	sky.sky_material = sky_material
	env.sky = sky
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-53, -30, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	_box(self, "Ground", Vector3(0, -0.24, 0), Vector3(200, 0.15, 200), mats.concrete)

func _track() -> void:
	var root := _root("Track")
	_box(root, "BallastBed", Vector3(0, -0.06, 0), Vector3(4.5, 0.28, 24), mats.concrete)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4271
	for variant in range(4):
		var stone := SphereMesh.new()
		stone.radius = 1.0
		stone.height = 2.0
		stone.radial_segments = 5
		stone.rings = 2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = [Color("646b70"), Color("91999b"), Color("acafaa"), Color("7d807e")][variant]
		mat.roughness = 1.0
		stone.material = mat
		var poses: Array[Transform3D] = []
		for i in range(6200):
			var point := Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(0.04, 0.12), rng.randf_range(-12, 12))
			var scale3 := Vector3(rng.randf_range(0.035, 0.09), rng.randf_range(0.025, 0.06), rng.randf_range(0.04, 0.1))
			poses.append(Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf() * TAU, rng.randf())).scaled(scale3), point))
		Batch.batch(root, "Ballast_%d" % variant, stone, poses, 100)
	for index in range(-19, 20):
		var z := float(index) * 0.61
		# Leave a service opening underneath the optical measurement station.
		if absf(z) < 0.4:
			continue
		_box(root, "Sleeper", Vector3(0, 0.15, z), Vector3(2.65, 0.22, 0.24), mats.concrete)
		for side in [-1.0, 1.0]:
			_box(root, "RailPad", Vector3(side * RAIL_X, 0.278, z), Vector3(0.27, 0.034, 0.2), mats.dark)
			for offset in [-0.13, 0.13]:
				_box(root, "FasteningClip", Vector3(side * RAIL_X + offset, 0.305, z), Vector3(0.05, 0.045, 0.1), mats.rust)
				_cylinder(root, "Bolt", Vector3(side * RAIL_X + offset, 0.34, z), 0.018, 0.025, mats.steel)
	for side in [-1.0, 1.0]:
		var x: float = side * RAIL_X
		_box(root, "RailFoot", Vector3(x, 0.30, 0), Vector3(0.15, 0.025, 24), mats.rust)
		_box(root, "RailWeb", Vector3(x, 0.385, 0), Vector3(0.019, 0.15, 24), mats.rust)
		_box(root, "RailHead", Vector3(x, 0.465, 0), Vector3(0.07, 0.05, 24), mats.steel)
		_box(root, "PolishedRunningSurface", Vector3(x, RAIL_TOP + 0.001, 0), Vector3(0.058, 0.003, 24), mats.steel)

func _equipment() -> void:
	var root := _root("MeasurementStation")
	lasers = _root("StructuredLightPlanes")
	labels = _root("ComponentLabels")
	for rail_side in [-1.0, 1.0]:
		for sensor_side in [-1.0, 1.0]:
			var x: float = rail_side * RAIL_X + sensor_side * 0.39
			var unit := Node3D.new()
			unit.name = ("Left" if rail_side < 0 else "Right") + ("OuterSensor" if rail_side == sensor_side else "InnerSensor")
			unit.position = Vector3(x, 0, 0)
			root.add_child(unit)
			units += 1
			_box(unit, "ConcretePlinth", Vector3(0, 0.15, 0.28), Vector3(0.45, 0.28, 1.9), mats.concrete)
			_box(unit, "MountingPlate", Vector3(0, 0.30, 0.28), Vector3(0.39, 0.04, 1.8), mats.edge)
			_box(unit, "SensorEnclosure", Vector3(0, 0.405, 0.28), Vector3(0.32, 0.18, 1.7), mats.housing)
			_box(unit, "TopCover", Vector3(0, 0.505, 0.28), Vector3(0.35, 0.025, 1.75), mats.housing)
			for z in [0.72, 0.98]:
				var optical := Node3D.new()
				optical.name = "Laser" if z < 0.8 else "Camera"
				optical.position = Vector3(-sensor_side * 0.13, 0.565, z)
				unit.add_child(optical)
				optical.look_at(Vector3(rail_side * RAIL_X, 0.95, 0) if z < 0.8 else Vector3(rail_side * RAIL_X, 0.74, 0.40), Vector3.UP)
				_box(optical, "BlueOpticalModule", Vector3.ZERO, Vector3(0.15, 0.13, 0.15), mats.blue)
				_box(optical, "WindowFrame", Vector3(0, 0, -0.079), Vector3(0.12, 0.10, 0.015), mats.dark)
				_box(optical, "OpticalWindow", Vector3(0, 0, -0.088), Vector3(0.08, 0.065, 0.004), mats.glass)
				if z < 0.8:
					_box(optical, "LaserSlit", Vector3(0, 0, -0.091), Vector3(0.06, 0.008, 0.003), mats.light)
				else:
					var lens := _cylinder(optical, "CameraLens", Vector3(0, 0, -0.095), 0.026, 0.02, mats.steel)
					lens.rotation_degrees.x = 90
			for z in [-0.46, 0.46]:
				for dx in [-0.13, 0.13]:
					_cylinder(unit, "CoverScrew", Vector3(dx, 0.523, z), 0.009, 0.009, mats.steel)
			_box(unit, "WarningPlate", Vector3(0.02, 0.52, 0), Vector3(0.095, 0.006, 0.13), mats.yellow)
			for z in [-0.48, 0.48]:
				_cable(root, Vector3(x, 0.28, z), Vector3(x, 0.10, z + 0.18))
				_cable(root, Vector3(x, 0.10, z + 0.18), Vector3(rail_side * 1.65, 0.10, z + 0.18))
			_label("OUTER SENSOR" if rail_side == sensor_side else "INNER SENSOR", Vector3(x, 0.73, 0.68), 0.0022)
	for side in [-1.0, 1.0]:
		_box(root, "CableDuct", Vector3(side * 1.65, 0.12, -2), Vector3(0.15, 0.14, 5.5), mats.edge)
	_label("RAIL", Vector3(-RAIL_X, 0.67, -1.3), 0.003)
	_label("LASER", Vector3(1.23, 0.80, -0.5), 0.0025)
	_label("CAMERA", Vector3(1.23, 0.78, 0.30), 0.0025)

func _wheelset() -> void:
	wheels = _root("DemonstrationWheelset")
	var axle := _cylinder(wheels, "Axle", Vector3(0, RAIL_TOP + 0.46, 0), 0.072, 2.14, mats.wheel)
	axle.rotation_degrees.z = 90
	for side in [-1.0, 1.0]:
		var wheel := Node3D.new()
		wheel.name = "LeftWheel" if side < 0 else "RightWheel"
		wheel.position = Vector3(side * RAIL_X, RAIL_TOP + 0.46, 0)
		wheels.add_child(wheel)
		# Revolved cross-section: inner flange, tapered tread, recessed web and hub.
		var profile: Array[Vector2] = [Vector2(-0.087, 0.10), Vector2(-0.087, 0.47), Vector2(-0.072, 0.49), Vector2(-0.052, 0.49), Vector2(-0.033, 0.462), Vector2(0.075, 0.455), Vector2(0.086, 0.435), Vector2(0.086, 0.345), Vector2(0.026, 0.315), Vector2(0.018, 0.16), Vector2(0.10, 0.13), Vector2(0.10, 0.075), Vector2(-0.087, 0.075), Vector2(-0.087, 0.10)]
		wheel.set_meta("profile_xr", profile)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(mats.wheel)
		for j in range(profile.size() - 1):
			for i in range(256):
				var a := TAU * i / 256.0
				var b := TAU * (i + 1) / 256.0
				var p := profile[j]
				var q := profile[j + 1]
				var vertices := [Vector3(p.x * side, cos(a) * p.y, sin(a) * p.y), Vector3(q.x * side, cos(a) * q.y, sin(a) * q.y), Vector3(q.x * side, cos(b) * q.y, sin(b) * q.y), Vector3(p.x * side, cos(b) * p.y, sin(b) * p.y)]
				for k in ([0, 1, 2, 0, 2, 3] if side > 0 else [0, 2, 1, 0, 3, 2]):
					surface.add_vertex(vertices[k])
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "FlangedWheel"
		mesh.mesh = surface.commit()
		wheel.add_child(mesh)

func _interface() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 22)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.09, 0.90)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = "TRACK SIDE  /  WHEEL MEASUREMENT"
	title.add_theme_font_size_override("font_size", 19)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	for mode in [1, 2]:
		var button := Button.new()
		button.text = "1  Installation" if mode == 1 else "2  Wheel profile"
		button.pressed.connect(_view.bind(mode))
		row.add_child(button)
	var hint := Label.new()
	hint.text = "Drag RMB: orbit   Wheel: zoom   R: reset\nW: wheelset   L: laser on/off   T: labels\nSpace: wheel pass   C: cameras   P: capture   B: dataset   G: single/multi\nF1: interface   Esc: menu"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color("b8c9d4")
	column.add_child(hint)

func _view(mode: int) -> void:
	moving = false
	wheels.position.z = 0
	wheels.visible = mode == 2
	measurement.set_enabled(true)
	labels.visible = mode == 1
	target = Vector3(0, 0.23, 0) if mode == 1 else Vector3(RAIL_X, 0.73, 0)
	yaw = 0.13 if mode == 1 else 0.20
	pitch = 0.93 if mode == 1 else 0.17
	distance = 4.6 if mode == 1 else 2.9
	_update_camera()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)
	camera.h_offset = 0.45

func _unhandled_input(event: InputEvent) -> void:
	if measurement != null and measurement.saving:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006, 0.06, 1.48)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1.2, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(18, distance * 1.1)
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_R: _view(1)
			KEY_2: _view(2)
			KEY_W: wheels.visible = not wheels.visible
			KEY_L: measurement.set_enabled(not measurement.enabled)
			KEY_C: measurement.toggle_panel()
			KEY_P: measurement.capture_dataset(false)
			KEY_B: measurement.capture_dataset(true)
			KEY_G: measurement.set_multiline(not measurement.multiline)
			KEY_T: labels.visible = not labels.visible
			KEY_F1: hud.visible = not hud.visible
			KEY_SPACE:
				moving = not moving
				wheels.visible = true
			KEY_ESCAPE: get_tree().change_scene_to_file("res://app/local.tscn")

func _process(delta: float) -> void:
	if moving:
		wheels.position.z += delta * 0.45
		if wheels.position.z > 2.0:
			wheels.position.z = -2.0
		for child in wheels.get_children():
			if child is Node3D and child.name != "Axle":
				child.rotation.x += delta * 0.45 / 0.46

func _root(title: String) -> Node3D:
	var node := Node3D.new()
	node.name = title
	add_child(node)
	return node

func _box(parent: Node3D, title: String, center: Vector3, size3: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size3
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.name = title
	node.set_meta("part", title)
	node.mesh = mesh
	node.position = center
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, title: String, center: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.name = title
	node.set_meta("part", title)
	node.mesh = mesh
	node.position = center
	parent.add_child(node)
	return node

func _cable(parent: Node3D, start: Vector3, end: Vector3) -> void:
	var box := _box(parent, "Conduit", Vector3.ZERO, Vector3.ONE, mats.cable)
	box.transform = Batch.beam(start, end, 0.026)

func _label(text: String, point: Vector3, scale2: float) -> void:
	var label := Label3D.new()
	label.layers = 4
	label.text = text
	label.position = point
	label.font_size = 30
	label.pixel_size = scale2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("e6f5ff")
	label.outline_modulate = Color("172b38")
	label.outline_size = 8
	labels.add_child(label)

func _smoke() -> void:
	_view(2)
	for frame in range(12):
		await get_tree().physics_frame
	var ok: bool = measurement.channels.size() == 4 and lasers.get_child_count() == 4
	var wheel_samples := 0
	for channel in measurement.channels:
		wheel_samples += int(channel.wheel_hits)
		ok = ok and channel.wheel_hits > 0 and channel.stripe.mesh != null
		ok = ok and channel.viewport.world_3d == get_world_3d()
		ok = ok and channel.viewport.get_camera_3d() == channel.camera
		ok = ok and channel.camera.cull_mask & 8 != 0
	ok = ok and get_viewport().get_camera_3d() == camera
	measurement.set_enabled(false)
	for channel in measurement.channels:
		ok = ok and not channel.stripe.visible and not channel.slit.visible
	ok = ok and not lasers.visible
	measurement.set_enabled(true)
	wheels.position.z = 2.0
	for frame in range(12):
		await get_tree().physics_frame
	for channel in measurement.channels:
		ok = ok and channel.wheel_hits == 0
	_view(1)
	for frame in range(6):
		await get_tree().physics_frame
	for channel in measurement.channels:
		ok = ok and channel.wheel_hits == 0
	print("TRACK_SIDE_SMOKE ", "PASS" if ok else "FAIL", " cameras=", measurement.channels.size(), " wheel_samples=", wheel_samples)
	get_tree().quit(0 if ok else 1)

func _capture() -> void:
	for frame in range(12):
		await get_tree().physics_frame
	var ok: bool = await measurement.capture_dataset("--wli-batch" in OS.get_cmdline_user_args())
	print("WLI_DATASET ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
