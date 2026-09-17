extends Node3D
## Reference-inspired static double-track ballastless railway scene.

const TrackGenerator := preload("res://scenes/ballastless_track/reference_track.gd")
const DetailBatch := preload("res://assets/procedural/detail_batch.gd")

const ROUTE_LENGTH := 1200.0
const ROUTE_START_Z := 55.0
const TRACK_OFFSET := 3.25
const DECK_WIDTH := 14.0
const DECK_TOP := 0.55
const MAST_SPACING := 50.0

var _camera: Camera3D
var _info_panel: Control
var _track_nodes: Array[MeshInstance3D] = []
var _mast_count := 0
var _wire_count := 0


func _ready() -> void:
	_build_environment()
	_build_viaduct()
	_build_tracks()
	_build_safety_barriers()
	_build_catenary()
	_build_landscape()
	_build_camera()
	_build_interface()
	_info_panel.hide()
	if "--reference-capture" in OS.get_cmdline_user_args():
		_capture_reference.call_deferred()
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_finish_smoke_test")


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "ClearSkyEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("1677c8")
	sky_material.sky_horizon_color = Color("a9d0eb")
	sky_material.ground_bottom_color = Color("52634f")
	sky_material.ground_horizon_color = Color("b6c7c1")
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("c6d4dc")
	environment.fog_light_energy = 0.55
	environment.fog_density = 0.00075
	environment.fog_height = -3.0
	environment.fog_height_density = 0.0
	environment.fog_sky_affect = 0.08
	world.environment = environment
	add_child(world)

	var sunlight := DirectionalLight3D.new()
	sunlight.name = "Sunlight"
	sunlight.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sunlight.light_color = Color("fff4db")
	sunlight.light_energy = 0.95
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 350.0
	sunlight.directional_shadow_fade_start = 0.8
	add_child(sunlight)


func _build_viaduct() -> void:
	var root := Node3D.new()
	root.name = "Viaduct"
	add_child(root)
	_add_box(root, "BridgeDeck", Vector3(0.0, DECK_TOP - 0.28, ROUTE_START_Z - ROUTE_LENGTH * 0.5),
		Vector3(DECK_WIDTH, 0.56, ROUTE_LENGTH + 12.0), _material(Color("7a7f80"), 0.96))
	_add_box(root, "CentralWalkway", Vector3(0.0, DECK_TOP + 0.075, ROUTE_START_Z - ROUTE_LENGTH * 0.5),
		Vector3(3.25, 0.15, ROUTE_LENGTH), _material(Color("999e9f"), 0.93))
	for side in [-1.0, 1.0]:
		_add_box(root, "InnerDrain_%s" % ("L" if side < 0 else "R"),
			Vector3(side * 1.78, DECK_TOP + 0.045, ROUTE_START_Z - ROUTE_LENGTH * 0.5),
			Vector3(0.22, 0.09, ROUTE_LENGTH), _material(Color("4c5558"), 0.9))
		_add_box(root, "Parapet_%s" % ("L" if side < 0 else "R"),
			Vector3(side * 6.75, DECK_TOP + 0.48, ROUTE_START_Z - ROUTE_LENGTH * 0.5),
			Vector3(0.38, 0.96, ROUTE_LENGTH), _material(Color("81898b"), 0.95))


func _build_tracks() -> void:
	var root := Node3D.new()
	root.name = "BallastlessDoubleTrack"
	add_child(root)
	for side in [-1.0, 1.0]:
		var track: MeshInstance3D = TrackGenerator.new()
		track.name = "LeftTrack" if side < 0 else "RightTrack"
		track.ballastless = true
		track.ballast_width_m = 3.0
		track.ballast_height_m = 0.18
		track.sleeper_height_m = 0.10
		track.sleeper_spacing_m = 0.625
		track.rail_height_m = 0.18
		track.rail_head_width_m = 0.115
		track.ground_clearance_m = 0.02
		root.add_child(track)
		track.set_custom_samples(_straight_samples(side * TRACK_OFFSET))
		track.generate_track_mesh()
		_track_nodes.append(track)


func _straight_samples(x_offset: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var step := 5.0
	var distance := 0.0
	while distance <= ROUTE_LENGTH:
		samples.append({
			"point": Vector3(x_offset, DECK_TOP, ROUTE_START_Z - distance),
			"forward": Vector3.FORWARD,
			"right": Vector3.RIGHT,
			"up": Vector3.UP,
			"distance": distance,
		})
		distance += step
	return samples


func _build_safety_barriers() -> void:
	var root := Node3D.new()
	root.name = "SafetyRailings"
	add_child(root)
	var steel := _material(Color("26383f"), 0.68, 0.35)
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3.ONE
	beam_mesh.material = steel
	var poses: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 6.72
		for distance in range(0, int(ROUTE_LENGTH) + 1, 4):
			var z := ROUTE_START_Z - float(distance)
			poses.append(DetailBatch.beam(Vector3(x, 1.03, z), Vector3(x, 2.02, z), 0.055, 0.055))
		for height in [1.45, 1.92]:
			poses.append(DetailBatch.beam(Vector3(x, height, ROUTE_START_Z),
				Vector3(x, height, ROUTE_START_Z - ROUTE_LENGTH), 0.06, 0.07))
	DetailBatch.batch(root, "DarkSteelRailings", beam_mesh, poses, 900.0)


func _build_catenary() -> void:
	var root := Node3D.new()
	root.name = "OverheadCatenary"
	add_child(root)
	var white_steel := _material(Color("e2e8e8"), 0.7, 0.22)
	var dark_wire := _material(Color("202931"), 0.82, 0.25)
	var insulator_mat := _material(Color("6f3b2f"), 0.88)
	var steel_mesh := BoxMesh.new()
	steel_mesh.size = Vector3.ONE
	steel_mesh.material = white_steel
	var wire_mesh := BoxMesh.new()
	wire_mesh.size = Vector3.ONE
	wire_mesh.material = dark_wire
	var insulator_mesh := CylinderMesh.new()
	insulator_mesh.top_radius = 1.0
	insulator_mesh.bottom_radius = 1.0
	insulator_mesh.height = 1.0
	insulator_mesh.radial_segments = 8
	insulator_mesh.material = insulator_mat
	var steel_poses: Array[Transform3D] = []
	var wire_poses: Array[Transform3D] = []
	var insulator_poses: Array[Transform3D] = []

	for distance in range(0, int(ROUTE_LENGTH) + 1, int(MAST_SPACING)):
		var z := ROUTE_START_Z - float(distance)
		for side in [-1.0, 1.0]:
			var mast_x: float = float(side) * 5.7
			steel_poses.append(DetailBatch.beam(Vector3(mast_x, DECK_TOP + 0.48, z),
				Vector3(mast_x, 8.55, z), 0.17, 0.21))
			steel_poses.append(DetailBatch.beam(Vector3(mast_x, 8.25, z),
				Vector3(side * 2.55, 7.55, z), 0.095))
			steel_poses.append(DetailBatch.beam(Vector3(mast_x, 7.35, z),
				Vector3(side * 2.55, 7.55, z), 0.075))
			var insulator_a := Vector3(side * 4.55, 8.0, z)
			var insulator_b := Vector3(side * 4.05, 7.88, z)
			insulator_poses.append(DetailBatch.beam(insulator_a, insulator_b, 0.13))
			for ring in range(8):
				var center := insulator_a.lerp(insulator_b, float(ring) / 7.0)
				insulator_poses.append(DetailBatch.beam(center - (insulator_b - insulator_a).normalized() * 0.012, center + (insulator_b - insulator_a).normalized() * 0.012, 0.19))
			steel_poses.append(DetailBatch.beam(Vector3(mast_x, 8.5, z), Vector3(float(side) * 7.0, 8.5, z), 0.07))
			steel_poses.append(DetailBatch.beam(Vector3(float(side) * TRACK_OFFSET, 7.55, z), Vector3(float(side) * TRACK_OFFSET + _wire_stagger(float(distance)), 6.72, z), 0.045))
			_add_box(root, "MastFoot_%d_%s" % [distance, str(side)], Vector3(mast_x, 0.85, z), Vector3(0.7, 0.6, 0.85), _material(Color("b4b6b1"), 0.95))
		_mast_count += 2

	var segment_step := 10.0
	var distance := 0.0
	while distance < ROUTE_LENGTH:
		var next := minf(distance + segment_step, ROUTE_LENGTH)
		for side in [-1.0, 1.0]:
			var track_x: float = float(side) * TRACK_OFFSET
			var contact_a := Vector3(track_x + _wire_stagger(distance), 6.72, ROUTE_START_Z - distance)
			var contact_b := Vector3(track_x + _wire_stagger(next), 6.72, ROUTE_START_Z - next)
			var messenger_a := Vector3(track_x, _messenger_height(distance), ROUTE_START_Z - distance)
			var messenger_b := Vector3(track_x, _messenger_height(next), ROUTE_START_Z - next)
			wire_poses.append(DetailBatch.beam(contact_a, contact_b, 0.024))
			wire_poses.append(DetailBatch.beam(messenger_a, messenger_b, 0.018))
			wire_poses.append(DetailBatch.beam(contact_a, messenger_a, 0.012))
			_wire_count += 3
		distance = next
	for side in [-1.0, 1.0]:
		for x_offset in [5.95, 6.28]:
			wire_poses.append(DetailBatch.beam(Vector3(side * x_offset, 8.72, ROUTE_START_Z),
				Vector3(side * x_offset, 8.72, ROUTE_START_Z - ROUTE_LENGTH), 0.018))
			_wire_count += 1
	DetailBatch.batch(root, "WhiteMastsAndArms", steel_mesh, steel_poses, 1500.0)
	DetailBatch.batch(root, "ContactMessengerAndFeederWires", wire_mesh, wire_poses, 1500.0)
	DetailBatch.batch(root, "BrownInsulators", insulator_mesh, insulator_poses, 900.0)


func _wire_stagger(distance: float) -> float:
	var span := floori(distance / MAST_SPACING)
	var phase := fposmod(distance, MAST_SPACING) / MAST_SPACING
	var direction := -1.0 if span % 2 == 0 else 1.0
	return lerpf(direction * 0.16, -direction * 0.16, phase)


func _messenger_height(distance: float) -> float:
	var phase := fposmod(distance, MAST_SPACING) / MAST_SPACING
	return 7.62 - 0.32 * 4.0 * phase * (1.0 - phase)


func _build_landscape() -> void:
	var root := Node3D.new()
	root.name = "DistantCountryside"
	add_child(root)
	_add_box(root, "Ground", Vector3(0.0, -5.35, ROUTE_START_Z - ROUTE_LENGTH * 0.46),
		Vector3(520.0, 0.3, ROUTE_LENGTH * 1.15), _material(Color("70825a"), 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var field_colors := [Color("7f8f57"), Color("9d8b58"), Color("697b4e"), Color("a28354")]
	for index in range(42):
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * rng.randf_range(22.0, 210.0)
		var z := rng.randf_range(ROUTE_START_Z - ROUTE_LENGTH, ROUTE_START_Z + 40.0)
		_add_box(root, "Field_%02d" % index, Vector3(x, -5.12, z),
			Vector3(rng.randf_range(20.0, 70.0), 0.08, rng.randf_range(25.0, 90.0)),
			_material(field_colors[index % field_colors.size()], 1.0))
	var building_materials := [
		_material(Color("d8d2c4"), 0.95), _material(Color("b8c5c8"), 0.95),
		_material(Color("d1b6a1"), 0.95), _material(Color("aec3ce"), 0.95),
	]
	var roof_material := _material(Color("476371"), 0.9, 0.15)
	for index in range(72):
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * rng.randf_range(16.0, 115.0)
		var z := rng.randf_range(ROUTE_START_Z - ROUTE_LENGTH, 20.0)
		var width := rng.randf_range(4.0, 10.0)
		var depth := rng.randf_range(5.0, 13.0)
		var height := rng.randf_range(2.8, 6.0)
		_add_box(root, "House_%02d" % index, Vector3(x, -5.0 + height * 0.5, z),
			Vector3(width, height, depth), building_materials[index % building_materials.size()])
		_add_box(root, "Roof_%02d" % index, Vector3(x, -4.95 + height, z),
			Vector3(width + 0.5, 0.25, depth + 0.6), roof_material)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ReferenceCamera"
	_camera.position = Vector3(0.0, 2.25, 45.0)
	_camera.fov = 67.0
	_camera.near = 0.08
	_camera.far = 2200.0
	add_child(_camera)
	_camera.rotation_degrees.x = 10.5
	_camera.current = true


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SceneInterface"
	add_child(layer)
	_info_panel = PanelContainer.new()
	_info_panel.position = Vector2(24.0, 22.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.07, 0.09, 0.78)
	style.border_color = Color(0.55, 0.74, 0.82, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_info_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_info_panel)
	var text := Label.new()
	text.text = "无砟轨道静态展示\n双线高架 · 1200 m · 接触网\nF1 隐藏说明   R 重置视角   Esc 返回"
	text.add_theme_font_size_override("font_size", 16)
	text.add_theme_color_override("font_color", Color("e9f4f7"))
	_info_panel.add_child(text)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_info_panel.visible = not _info_panel.visible
		KEY_R:
			_build_camera_reset()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://app/local.tscn")


func _build_camera_reset() -> void:
	_camera.position = Vector3(0.0, 2.25, 45.0)
	_camera.rotation_degrees.x = 10.5


func _finish_smoke_test() -> void:
	await get_tree().process_frame
	var ok := _track_nodes.size() == 2 and _mast_count >= 40 and _wire_count >= 700
	for track in _track_nodes:
		ok = ok and track.mesh != null and track.sleeper_instance_count > 3000
	ok = ok and get_node_or_null("Viaduct/BridgeDeck") != null
	ok = ok and get_node_or_null("OverheadCatenary/ContactMessengerAndFeederWires") != null
	print("BALLASTLESS_TRACK_SMOKE ", "PASS" if ok else "FAIL",
		" tracks=", _track_nodes.size(), " masts=", _mast_count, " wires=", _wire_count)
	get_tree().quit(0 if ok else 1)


func _capture_reference() -> void:
	for frame in range(40):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("res://scenes/ballastless_track/preview.png")
	print("REFERENCE_CAPTURE ", error_string(error))
	get_tree().quit(0 if error == OK else 1)


func _add_box(parent: Node3D, title: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.position = center
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
