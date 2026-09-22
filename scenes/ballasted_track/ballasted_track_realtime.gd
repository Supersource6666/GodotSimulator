extends "res://scenes/ballasted_track/ballasted_track.gd"
## 8 km ballasted route driven by railway31dof.v1 or railway_ltd.v1.

const RouteProfile = preload("res://scenes/ballasted_track/ballasted_route_profile.gd")
const RealtimeReceiver = preload("res://scenes/ballasted_track/simulation_stream_receiver.gd")
const TrackComponents = preload("res://scenes/ballasted_track/track_components.gd")
const Batcher = preload("res://assets/procedural/detail_batch.gd")
const Pantograph = preload("res://scenes/travel/pantograph.gd")
const WaggonLivery = preload("res://scenes/ballasted_track/train/waggon_green_livery.gdshader")
const LocomotiveLivery = preload("res://scenes/ballasted_track/train/locomotive_livery.gdshader")
const TrainCarScene = preload("res://scenes/ballasted_track/train/train_car.tscn")
const WaggonScene = preload("res://scenes/ballasted_track/train/models/HXD3D_waggon.glb")
const SpeedChart = preload("res://scenes/ballasted_track/speed_chart.gd")
const OpenRailwayMapMiniMap = preload("res://shared/openrailwaymap_mini_map.gd")

const PROFILE_PATH := "res://scenes/ballasted_track/data/ping_duan_mian.csv"
const ROUTE_LENGTH_M := 8000.0
const PROFILE_START_Z := 18.0
const ROUTE_BUILD_START_M := -650.0
const TRACK_CENTERS := [-4.2, 0.0]
const TRAIN_TRACK_CENTER := -4.2
const CAR_BASE_HEIGHT_M := 1.991662
const CAR_SPACING_M := 26.3
const LOCOMOTIVE_TO_FIRST_COACH_M := 24.0
const COACH_COUNT := 18
const RAIL_GAUGE_HALF_M := 0.7535
const GEOMETRY_STEP_M := 2.0
const SLEEPER_SPACING_M := 0.6
const CATENARY_MAST_SPACING_M := 48.0
const CONTACT_WIRE_HEIGHT_M := 5.95
const MESSENGER_SUPPORT_HEIGHT_M := 7.18
const CATENARY_STAGGER_M := 0.20
const DETAIL_BALLAST_LENGTH_M := 600.0
const ROUTE_DETAIL_VISIBILITY_M := 900.0
const RAIL_INSTANCES_PER_CHUNK := 160
const SLEEPER_INSTANCES_PER_CHUNK := 400

@export var follow_realtime_train := true
@export_range(15.0, 150.0, 1.0) var follow_camera_lead_distance_m := 48.0
@export_range(0.0, 200.0, 1.0) var follow_camera_focus_behind_lead_m := 55.0
@export_range(0.0, 40.0, 1.0) var follow_camera_lateral_m := 12.0
@export_range(2.0, 30.0, 0.5) var follow_camera_height_m := 8.5
@export_range(0.01, 1.0, 0.01) var stream_smoothing_time_s := 0.10
@export_range(0.0, 0.5, 0.01) var maximum_stream_prediction_s := 0.12
@export_range(0.5, 100.0, 0.5) var stream_teleport_threshold_m := 12.0
@export var cab_eye_position := Vector3(-0.55, 1.82, -10.75)
@export_range(45.0, 100.0, 1.0) var cab_camera_fov := 68.0
@export_range(0.05, 1.0, 0.05) var cab_nose_clearance_m := 0.20
var route_profile
var simulation_stream: Node
var _route_error := ""
var _rail_segment_count := 0
var _route_sleeper_count := 0
var _catenary_mast_count := 0
var _catenary_wire_count := 0
var _pantograph: Node3D
var _lead_model_size := Vector3.ZERO
var _lead_model_bounds := AABB()
var _coach_model_size := Vector3.ZERO
var _latest_mileage_m := 0.0
var _display_mileage_m := 0.0
var _last_stream_receive_usec := 0
var _has_stream_state := false
var _target_stream_state: Dictionary = {}
var _shutdown_requested := false
var _cab_view_enabled := false
var _speed_chart
var _mini_map


func _ready() -> void:
	route_profile = RouteProfile.new()
	_route_error = route_profile.load_profile(PROFILE_PATH, ROUTE_LENGTH_M + 100.0, PROFILE_START_Z)
	if not _route_error.is_empty():
		push_error(_route_error)
		return
	print("BALLASTED_ROUTE_READY samples=%d mileage=%.3f..%.3f m length=%.1f m" % [
		route_profile.sample_count(), route_profile.first_mileage_m,
		route_profile.last_mileage_m, route_profile.distance_range_m()])
	_setup_train_consist()
	if "--stream-smoke-test" in OS.get_cmdline_user_args():
		_setup_realtime_stream()
		return
	super._ready()
	_setup_mini_map()
	_setup_speed_panel()
	_setup_locomotive_materials()
	_setup_waggon_livery()
	_setup_pantograph()
	_setup_realtime_stream()


func _setup_realtime_stream() -> void:
	simulation_stream = RealtimeReceiver.new()
	simulation_stream.name = "SimulationStreamReceiver"
	add_child(simulation_stream)
	simulation_stream.attach_train(get_node_or_null("Train") as Node3D)
	simulation_stream.state_received.connect(_on_simulation_state)
func _setup_speed_panel() -> void:
	var layer := get_node_or_null("SceneInterface") as CanvasLayer
	if layer == null:
		return
	_speed_chart = SpeedChart.new()
	_speed_chart.name = "RealtimeSpeedChart"
	_speed_chart.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed_chart.offset_left = -450.0
	_speed_chart.offset_top = -240.0
	_speed_chart.offset_right = -20.0
	_speed_chart.offset_bottom = -20.0
	layer.add_child(_speed_chart)


func _setup_mini_map() -> void:
	var layer := get_node_or_null("SceneInterface") as CanvasLayer
	if layer == null:
		return
	_mini_map = OpenRailwayMapMiniMap.new()
	layer.add_child(_mini_map)
	_mini_map.set_route_distance(0.0)

func _coach_type(number: int) -> String:
	if number <= 8:
		return "YZ25T"
	if number == 9:
		return "CA25T"
	if number == 10:
		return "RW25T"
	return "YW25T"


func _setup_train_consist() -> void:
	var train_root := get_node_or_null("Train") as Node3D
	if train_root == null or train_root.get_node_or_null("LeadCar") == null:
		return
	var lead := train_root.get_node("LeadCar") as Node3D
	lead.set_meta("consist_offset_m", 0.0)
	lead.set_meta("vehicle_type", "HXD3D")
	for number in range(1, COACH_COUNT + 1):
		var coach_type := _coach_type(number)
		var coach := TrainCarScene.instantiate() as Node3D
		coach.name = "Coach_%02d_%s" % [number, coach_type]
		coach.set_meta("coach_number", number)
		coach.set_meta("vehicle_type", coach_type)
		coach.set_meta("consist_offset_m",
			LOCOMOTIVE_TO_FIRST_COACH_M + float(number - 1) * CAR_SPACING_M)
		train_root.add_child(coach)
		var running_gear := coach.get_node_or_null("RunningGear") as Node3D
		if running_gear != null:
			running_gear.visible = false
		var model_mount := coach.get_node_or_null("ModelMount") as Node3D
		var model := WaggonScene.instantiate() as Node3D
		model.name = "Model"
		model.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(2.715, 2.784, 3.209)),
			Vector3(0.0, -1.784686, 0.0))
		model_mount.add_child(model)
		for side in [-1.0, 1.0]:
			var marking := Label3D.new()
			marking.name = "CoachMarking_%s" % ("L" if side < 0.0 else "R")
			marking.text = "%02d  %s" % [number, coach_type]
			marking.font_size = 64
			marking.pixel_size = 0.0045
			marking.modulate = Color("e8c83b")
			marking.outline_modulate = Color("173121")
			marking.outline_size = 8
			marking.no_depth_test = false
			marking.position = Vector3(side * 1.558, 0.02, 0.0)
			marking.rotation.y = -side * PI * 0.5
			coach.add_child(marking)
	print("BALLASTED_CONSIST_READY locomotive=1 coaches=18 YZ=8 CA=1 RW=1 YW=8")

func _setup_waggon_livery() -> void:
	var train_root := get_node_or_null("Train") as Node3D
	if train_root == null:
		return
	var surface_count := 0
	for coach in train_root.get_children():
		if not (coach is Node3D) or not coach.has_meta("coach_number"):
			continue
		var material := ShaderMaterial.new()
		material.shader = WaggonLivery
		var model_mount := coach.get_node_or_null("ModelMount") as Node3D
		for candidate in model_mount.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := candidate as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			mesh_instance.material_override = material
			surface_count += mesh_instance.mesh.get_surface_count()
	print("BALLASTED_WAGGON_LIVERY_READY coaches=", COACH_COUNT,
		" surfaces=", surface_count)
func _adjust_locomotive_color(color: Color, saturation_scale: float,
		value_scale: float) -> Color:
	return Color.from_hsv(color.h, clampf(color.s * saturation_scale, 0.0, 1.0),
		clampf(color.v * value_scale, 0.0, 1.0), color.a)


func _setup_locomotive_materials() -> void:
	var lead := get_node_or_null("Train/LeadCar") as Node3D
	var model_mount := lead.get_node_or_null("ModelMount") as Node3D if lead != null else null
	if model_mount == null:
		return
	var surface_count := 0
	var adjusted_materials := {}
	var textured_livery_materials := 0
	for candidate in model_mount.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var source_id := source.get_instance_id()
			if adjusted_materials.has(source_id):
				mesh_instance.set_surface_override_material(surface,
					adjusted_materials[source_id])
				surface_count += 1
				continue
			var material_name := source.resource_name.to_lower()
			var material := source.duplicate() as StandardMaterial3D
			if material_name.contains("green") or material_name.contains("livery"):
				if material.albedo_texture != null:
					var livery := ShaderMaterial.new()
					livery.shader = LocomotiveLivery
					livery.set_shader_parameter("albedo_texture", material.albedo_texture)
					textured_livery_materials += 1
					adjusted_materials[source_id] = livery
					mesh_instance.set_surface_override_material(surface, livery)
					surface_count += 1
					continue
				else:
					material.albedo_color = _adjust_locomotive_color(
						material.albedo_color, 1.28, 0.78)
				material.roughness = minf(material.roughness, 0.38)
				material.metallic = maxf(material.metallic, 0.18)
			elif material_name.contains("glass"):
				material.albedo_color = _adjust_locomotive_color(
					material.albedo_color, 1.12, 0.72)
				material.roughness = 0.10
			elif material_name.contains("roof") or material_name.contains("steel"):
				material.albedo_color = _adjust_locomotive_color(
					material.albedo_color, 1.05, 0.82)
				material.roughness = maxf(material.roughness, 0.42)
			else:
				material.albedo_color = _adjust_locomotive_color(
					material.albedo_color, 1.08, 0.86)
			adjusted_materials[source_id] = material
			mesh_instance.set_surface_override_material(surface, material)
			surface_count += 1
	print("BALLASTED_LOCOMOTIVE_MATERIAL_READY surfaces=", surface_count,
		" unique_materials=", adjusted_materials.size(),
		" textured_livery_materials=", textured_livery_materials)

func _on_simulation_state(state: Dictionary) -> void:
	_target_stream_state = state.duplicate()
	_last_stream_receive_usec = Time.get_ticks_usec()
	if not _has_stream_state:
		_display_mileage_m = float(state.get("mileage_m", route_profile.first_mileage_m))
		_has_stream_state = true
	if _speed_chart != null:
		_speed_chart.add_sample(float(state.get("t", 0.0)),
			float(state.get("speed_m_s", 0.0)))


func _update_cab_camera(train_root: Node3D) -> void:
	if _camera == null or train_root == null:
		return
	var lead := train_root.get_node_or_null("LeadCar") as Node3D
	if lead == null:
		return
	var body := lead.get_node_or_null("ModelMount") as Node3D
	var camera_pose := body.global_transform if body != null else lead.global_transform
	var eye_local := cab_eye_position
	if _lead_model_bounds.size.z > 0.0:
		var front_face_z := _lead_model_bounds.position.z
		eye_local.z = minf(eye_local.z, front_face_z - cab_nose_clearance_m)
	var eye := camera_pose * eye_local
	var up := camera_pose.basis.y.normalized()
	var forward := (-camera_pose.basis.z).normalized()
	_camera.near = 0.04
	_camera.fov = cab_camera_fov
	_camera.global_position = eye
	_camera.look_at(eye + forward * 45.0 + up * 0.15, up)


func _apply_visual_state(state: Dictionary) -> void:
	_latest_mileage_m = float(state.get("mileage_m", route_profile.first_mileage_m))
	if _mini_map != null:
		_mini_map.set_route_distance(_latest_mileage_m - route_profile.first_mileage_m)
	var train_root := get_node_or_null("Train") as Node3D
	if train_root != null:
		var car_index := 0
		for car in train_root.get_children():
			if not (car is Node3D):
				continue
			var default_offset := float(car_index) * CAR_SPACING_M
			var car_mileage := _latest_mileage_m - float(car.get_meta(
				"consist_offset_m", default_offset))
			var track_pose: Transform3D = route_profile.pose_at_mileage(
				car_mileage, TRAIN_TRACK_CENTER, CAR_BASE_HEIGHT_M)
			(car as Node3D).global_transform = track_pose
			car_index += 1
	if _cab_view_enabled:
		_update_cab_camera(train_root)
	elif follow_realtime_train and _camera != null:
		var camera_pose: Transform3D = route_profile.pose_at_mileage(
			_latest_mileage_m + follow_camera_lead_distance_m,
			TRAIN_TRACK_CENTER + follow_camera_lateral_m,
			CAR_BASE_HEIGHT_M + follow_camera_height_m)
		var focus_pose: Transform3D = route_profile.pose_at_mileage(
			_latest_mileage_m - follow_camera_focus_behind_lead_m,
			TRAIN_TRACK_CENTER, CAR_BASE_HEIGHT_M)
		_camera.near = 0.2
		_camera.fov = 50.0
		_camera.global_position = camera_pose.origin
		_camera.look_at(focus_pose.origin + Vector3.UP * 1.2, Vector3.UP)
	if _info_panel != null and _info_panel.get_child_count() > 0:
		var label := _info_panel.get_child(0) as Label
		if label != null:
			var stream_mode := "LTD" if state.get("schema", "") == "railway_ltd.v1" else "31DOF"
			var view_mode := "CAB" if _cab_view_enabled else "CHASE"
			label.text = "Ballasted Track / REALTIME %s / %s\nMileage %.3f m  Speed %.1f km/h  Seq %d\nC or 6: cab view    V: speed panel" % [
				stream_mode, view_mode, _latest_mileage_m,
				float(state.get("speed_m_s", 0.0)) * 3.6, int(state.get("seq", -1))]
	if not _shutdown_requested and "--camera-smoke-test" in OS.get_cmdline_user_args() and int(state.get("seq", -1)) >= 10:
		var lead_pose: Transform3D = route_profile.pose_at_mileage(
			_latest_mileage_m, TRAIN_TRACK_CENTER, CAR_BASE_HEIGHT_M)
		var camera_clearance := _camera.global_position.distance_to(lead_pose.origin) if _camera != null else 0.0
		var lead_car := train_root.get_child(0) as Node3D if train_root != null and train_root.get_child_count() > 0 else null
		var orientation_dot := (-lead_car.global_transform.basis.z).dot(-lead_pose.basis.z) if lead_car != null else -1.0
		var camera_ok := (camera_clearance > 35.0 and camera_clearance < 90.0
			and orientation_dot > 0.999)
		_shutdown_requested = true
		print("BALLASTED_CAMERA_SMOKE ", "PASS" if camera_ok else "FAIL",
			" clearance_m=", camera_clearance, " orientation_dot=", orientation_dot)
		_clean_shutdown.call_deferred(0 if camera_ok else 1)
	elif not _shutdown_requested and "--stream-smoke-test" in OS.get_cmdline_user_args() and int(state.get("seq", -1)) >= 10:
		_shutdown_requested = true
		print("BALLASTED_STREAM_SMOKE PASS seq=", int(state.get("seq", -1)),
			" mileage=", _latest_mileage_m)
		_clean_shutdown.call_deferred(0)


func _route_point(distance_m: float, lateral_m: float, height_m: float) -> Vector3:
	return route_profile.pose_at_distance(distance_m, lateral_m, height_m).origin


func _add_route_ribbon(name_text: String, center_m: float, half_width_m: float,
		height_m: float, step_m: float, material: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance := ROUTE_BUILD_START_M
	while distance < ROUTE_LENGTH_M:
		var following := minf(distance + step_m, ROUTE_LENGTH_M)
		var left_a := _route_point(distance, center_m - half_width_m, height_m)
		var right_a := _route_point(distance, center_m + half_width_m, height_m)
		var left_b := _route_point(following, center_m - half_width_m, height_m)
		var right_b := _route_point(following, center_m + half_width_m, height_m)
		for point in [left_a, right_a, right_b, left_a, right_b, left_b]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(point)
		distance = following
	surface.set_material(material)
	var mesh := MeshInstance3D.new()
	mesh.name = name_text
	mesh.mesh = surface.commit()
	add_child(mesh)
	return mesh


func _ground() -> void:
	_add_route_ribbon("RouteGround", -2.1, 45.0, -0.23, 8.0, _ground_material())
	_add_route_ribbon("MaintenancePath", 3.6, 0.75, -0.08, 3.0, _ground_material(true))
	_add_route_ribbon("SlopedBallastFormation", -2.1, 4.8, 0.27, 1.0, _mineral("414442", 110))


func _batch_route_chunks(title: String, mesh: Mesh, poses: Array[Transform3D],
		instances_per_chunk: int, mark_fastening := false) -> void:
	var start := 0
	var chunk_index := 0
	while start < poses.size():
		var chunk: Array[Transform3D] = []
		chunk.assign(poses.slice(start, mini(start + instances_per_chunk, poses.size())))
		var instance := Batcher.batch(self, "%s_%03d" % [title, chunk_index], mesh, chunk,
			ROUTE_DETAIL_VISIBILITY_M)
		if mark_fastening and instance != null:
			instance.set_meta("fastening_assembly", true)
		start += instances_per_chunk
		chunk_index += 1


func _tracks() -> void:
	var rust := _mineral("583829", 65)
	var polished := _material(Color("a0a8aa"), 0.26, 0.8)
	var sleeper_mesh := TrackComponents.sleeper()
	var fastening_mesh := TrackComponents.fastening()
	for center in TRACK_CENTERS:
		for rail_side in [-1.0, 1.0]:
			var lateral: float = center + rail_side * RAIL_GAUGE_HALF_M
			var foot_poses: Array[Transform3D] = []
			var web_poses: Array[Transform3D] = []
			var head_poses: Array[Transform3D] = []
			var surface_poses: Array[Transform3D] = []
			var distance := ROUTE_BUILD_START_M
			while distance < ROUTE_LENGTH_M:
				var following := minf(distance + GEOMETRY_STEP_M, ROUTE_LENGTH_M)
				foot_poses.append(Batcher.beam(_route_point(distance, lateral, 0.515),
					_route_point(following, lateral, 0.515), 0.15, 0.026))
				web_poses.append(Batcher.beam(_route_point(distance, lateral, 0.58),
					_route_point(following, lateral, 0.58), 0.018, 0.12))
				head_poses.append(Batcher.beam(_route_point(distance, lateral, 0.665),
					_route_point(following, lateral, 0.665), 0.073, 0.046))
				surface_poses.append(Batcher.beam(_route_point(distance, lateral, 0.69),
					_route_point(following, lateral, 0.69), 0.069, 0.005))
				_rail_segment_count += 1
				distance = following
			var unit_box := BoxMesh.new()
			unit_box.size = Vector3.ONE
			unit_box.material = rust
			_batch_route_chunks("CurvedRailFoot", unit_box, foot_poses, RAIL_INSTANCES_PER_CHUNK)
			_batch_route_chunks("CurvedRailWeb", unit_box, web_poses, RAIL_INSTANCES_PER_CHUNK)
			_batch_route_chunks("CurvedRailHead", unit_box, head_poses, RAIL_INSTANCES_PER_CHUNK)
			var surface_box := BoxMesh.new()
			surface_box.size = Vector3.ONE
			surface_box.material = polished
			_batch_route_chunks("CurvedRunningSurface", surface_box, surface_poses, RAIL_INSTANCES_PER_CHUNK)
		var sleepers: Array[Transform3D] = []
		var fastenings: Array[Transform3D] = []
		var sleeper_distance := ROUTE_BUILD_START_M
		while sleeper_distance <= ROUTE_LENGTH_M:
			var sleeper_pose: Transform3D = route_profile.pose_at_distance(sleeper_distance, center, 0.0)
			sleepers.append(sleeper_pose)
			for rail_side in [-1.0, 1.0]:
				fastenings.append(route_profile.pose_at_distance(
					sleeper_distance, center + rail_side * RAIL_GAUGE_HALF_M, 0.0))
			_route_sleeper_count += 1
			sleeper_distance += SLEEPER_SPACING_M
		_batch_route_chunks("RouteConcreteSleepers", sleeper_mesh, sleepers,
			SLEEPER_INSTANCES_PER_CHUNK)
		_batch_route_chunks("RouteFastenings", fastening_mesh, fastenings,
			SLEEPER_INSTANCES_PER_CHUNK * 2, true)


func _ballast() -> void:
	_add_route_ribbon("ContinuousBallastBed", -2.1, 4.75, 0.34, 0.8, _mineral("555b59", 120))
	var meshes: Array[ArrayMesh] = []
	for index in range(8):
		meshes.append(_stone(index))
	var buckets: Array = []
	for index in range(8):
		buckets.append([])
	var distance := 0.0
	var detail_step := 0.22
	while distance < DETAIL_BALLAST_LENGTH_M:
		var lateral := -6.85
		while lateral <= 2.65:
			var center_distance := minf(absf(lateral), absf(lateral + 4.2))
			var tie_distance := absf(fposmod(distance + 0.3, SLEEPER_SPACING_M) - 0.3)
			if not (center_distance < 1.31 and tie_distance < 0.145):
				var radius := rng.randf_range(0.035, 0.065)
				var pose: Transform3D = route_profile.pose_at_distance(
					distance + rng.randf_range(-0.08, 0.08), lateral + rng.randf_range(-0.08, 0.08), 0.34)
				pose.basis = pose.basis * Basis.from_euler(Vector3(
					rng.randf_range(-0.7, 0.7), rng.randf() * TAU, rng.randf_range(-0.7, 0.7)))
				pose.basis = pose.basis.scaled(Vector3(radius, radius, radius))
				buckets[rng.randi_range(0, 7)].append(pose)
				stone_count += 1
			lateral += detail_step
		distance += detail_step
	for index in range(8):
		var poses: Array[Transform3D] = []
		poses.assign(buckets[index])
		Batcher.batch(self, "RouteBallast_%d" % index, meshes[index], poses, 700)


func _catenary_stagger(distance_m: float, track_index: int) -> float:
	var span := floori(distance_m / CATENARY_MAST_SPACING_M)
	var phase := fposmod(distance_m, CATENARY_MAST_SPACING_M) / CATENARY_MAST_SPACING_M
	var direction := -1.0 if (span + track_index) % 2 == 0 else 1.0
	return lerpf(direction * CATENARY_STAGGER_M, -direction * CATENARY_STAGGER_M, phase)


func _messenger_height(distance_m: float) -> float:
	var phase := fposmod(distance_m, CATENARY_MAST_SPACING_M) / CATENARY_MAST_SPACING_M
	return MESSENGER_SUPPORT_HEIGHT_M - 0.34 * 4.0 * phase * (1.0 - phase)


func _catenary_point(distance_m: float, track_center: float, height_m: float,
		stagger_m := 0.0) -> Vector3:
	return _route_point(distance_m, track_center + stagger_m, height_m)


func _catenary() -> void:
	var root := Node3D.new()
	root.name = "DetailedOverheadCatenary"
	add_child(root)
	var galvanized := _material(Color("69777b"), 0.72, 0.42)
	var dark_wire := _material(Color("242a2c"), 0.78, 0.52)
	var copper_wire := _material(Color("54443a"), 0.68, 0.48)
	var ceramic := _material(Color("76513e"), 0.88, 0.05)
	var concrete := _material(Color("92958f"), 0.96, 0.0)
	var steel_mesh := BoxMesh.new()
	steel_mesh.size = Vector3.ONE
	steel_mesh.material = galvanized
	var wire_mesh := CylinderMesh.new()
	wire_mesh.top_radius = 1.0
	wire_mesh.bottom_radius = 1.0
	wire_mesh.height = 1.0
	wire_mesh.radial_segments = 6
	wire_mesh.rings = 0
	wire_mesh.material = copper_wire
	var auxiliary_wire_mesh := CylinderMesh.new()
	auxiliary_wire_mesh.top_radius = 1.0
	auxiliary_wire_mesh.bottom_radius = 1.0
	auxiliary_wire_mesh.height = 1.0
	auxiliary_wire_mesh.radial_segments = 6
	auxiliary_wire_mesh.rings = 0
	auxiliary_wire_mesh.material = dark_wire
	var insulator_mesh := CylinderMesh.new()
	insulator_mesh.top_radius = 1.0
	insulator_mesh.bottom_radius = 1.0
	insulator_mesh.height = 1.0
	insulator_mesh.radial_segments = 10
	insulator_mesh.rings = 0
	insulator_mesh.material = ceramic
	var foundation_mesh := BoxMesh.new()
	foundation_mesh.size = Vector3.ONE
	foundation_mesh.material = concrete
	var steel_poses: Array[Transform3D] = []
	var wire_poses: Array[Transform3D] = []
	var auxiliary_wire_poses: Array[Transform3D] = []
	var insulator_poses: Array[Transform3D] = []
	var foundation_poses: Array[Transform3D] = []

	var mast_distance := ROUTE_BUILD_START_M
	while mast_distance <= ROUTE_LENGTH_M:
		for track_index in range(TRACK_CENTERS.size()):
			var track_center: float = TRACK_CENTERS[track_index]
			var mast_lateral := track_center - 2.65 if track_index == 0 else track_center + 2.85
			var foundation: Transform3D = route_profile.pose_at_distance(mast_distance, mast_lateral, 0.13)
			foundation.basis = foundation.basis.scaled(Vector3(0.78, 0.5, 0.92))
			foundation_poses.append(foundation)
			# Twin uprights, horizontal ties and alternating diagonals form a readable lattice mast.
			for side in [-1.0, 1.0]:
				steel_poses.append(Batcher.beam(
					_route_point(mast_distance, mast_lateral + side * 0.14, 0.36),
					_route_point(mast_distance, mast_lateral + side * 0.14, 8.65), 0.065, 0.085))
			for section in range(9):
				var low := 0.55 + float(section) * 0.88
				var high := low + 0.88
				var sign := -1.0 if section % 2 == 0 else 1.0
				steel_poses.append(Batcher.beam(
					_route_point(mast_distance, mast_lateral + sign * 0.14, low),
					_route_point(mast_distance, mast_lateral - sign * 0.14, high), 0.032))
				steel_poses.append(Batcher.beam(
					_route_point(mast_distance, mast_lateral - 0.14, high),
					_route_point(mast_distance, mast_lateral + 0.14, high), 0.028))
			var stagger := _catenary_stagger(mast_distance, track_index)
			var contact := _catenary_point(mast_distance, track_center,
				CONTACT_WIRE_HEIGHT_M, stagger)
			var registration := _catenary_point(mast_distance, track_center, 6.34, stagger)
			var upper_base := _route_point(mast_distance, mast_lateral, 7.88)
			var lower_base := _route_point(mast_distance, mast_lateral, 6.82)
			var arm_outer := registration.lerp(upper_base, 0.18) + Vector3.UP * 0.28
			steel_poses.append(Batcher.beam(upper_base, arm_outer, 0.055, 0.075))
			steel_poses.append(Batcher.beam(lower_base, registration, 0.065, 0.08))
			steel_poses.append(Batcher.beam(arm_outer, registration, 0.038))
			steel_poses.append(Batcher.beam(registration, contact, 0.026))
			# Porcelain rod plus skirts on both cantilever arms.
			for pair in [[upper_base, arm_outer], [lower_base, registration]]:
				var a: Vector3 = pair[0]
				var b: Vector3 = pair[1]
				var direction := (b - a).normalized()
				var middle := a.lerp(b, 0.28)
				insulator_poses.append(Batcher.beam(middle - direction * 0.23,
					middle + direction * 0.23, 0.075))
				for skirt in range(6):
					var center := middle + direction * lerpf(-0.20, 0.20, float(skirt) / 5.0)
					insulator_poses.append(Batcher.beam(center - direction * 0.012,
						center + direction * 0.012, 0.13))
			_catenary_mast_count += 1
		mast_distance += CATENARY_MAST_SPACING_M

	for track_index in range(TRACK_CENTERS.size()):
		var track_center: float = TRACK_CENTERS[track_index]
		var distance := ROUTE_BUILD_START_M
		while distance < ROUTE_LENGTH_M:
			var following := minf(distance + 6.0, ROUTE_LENGTH_M)
			var stagger_a := _catenary_stagger(distance, track_index)
			var stagger_b := _catenary_stagger(following, track_index)
			var contact_a := _catenary_point(distance, track_center,
				CONTACT_WIRE_HEIGHT_M, stagger_a)
			var contact_b := _catenary_point(following, track_center,
				CONTACT_WIRE_HEIGHT_M, stagger_b)
			var messenger_a := _catenary_point(distance, track_center,
				_messenger_height(distance), stagger_a * 0.35)
			var messenger_b := _catenary_point(following, track_center,
				_messenger_height(following), stagger_b * 0.35)
			wire_poses.append(Batcher.beam(contact_a, contact_b, 0.017, 0.022))
			wire_poses.append(Batcher.beam(messenger_a, messenger_b, 0.013))
			# Six-metre droppers visually carry the contact wire from the messenger.
			wire_poses.append(Batcher.beam(contact_a, messenger_a, 0.0065))
			_catenary_wire_count += 3
			distance = following

	# Feeder and return conductors follow the outside of each mast row.
	for track_index in range(TRACK_CENTERS.size()):
		var track_center: float = TRACK_CENTERS[track_index]
		var mast_lateral := track_center - 2.65 if track_index == 0 else track_center + 2.85
		var distance := ROUTE_BUILD_START_M
		while distance < ROUTE_LENGTH_M:
			var following := minf(distance + 12.0, ROUTE_LENGTH_M)
			auxiliary_wire_poses.append(Batcher.beam(
				_route_point(distance, mast_lateral, 8.35),
				_route_point(following, mast_lateral, 8.35), 0.014))
			auxiliary_wire_poses.append(Batcher.beam(
				_route_point(distance, mast_lateral, 5.15),
				_route_point(following, mast_lateral, 5.15), 0.012))
			distance = following

	_batch_route_chunks("CatenaryFoundations", foundation_mesh, foundation_poses, 24)
	_batch_route_chunks("LatticeMastsAndCantilevers", steel_mesh, steel_poses, 420)
	_batch_route_chunks("ContactMessengerDroppers", wire_mesh, wire_poses, 480)
	_batch_route_chunks("FeederAndReturnWires", auxiliary_wire_mesh, auxiliary_wire_poses, 160)
	_batch_route_chunks("PorcelainInsulators", insulator_mesh, insulator_poses, 360)
	print("BALLASTED_CATENARY_READY masts=", _catenary_mast_count,
		" wire_elements=", _catenary_wire_count)


func _setup_pantograph() -> void:
	var train_root := get_node_or_null("Train") as Node3D
	if train_root == null:
		return
	var vehicle := train_root.get_node_or_null("LeadCar") as Node3D
	if vehicle == null:
		return
	var model_mount := vehicle.get_node_or_null("ModelMount") as Node3D
	if model_mount == null:
		return
	var bounds := AABB()
	var first := true
	for candidate in model_mount.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var part_name := mesh_instance.name.to_lower()
		var built_in_pantograph := part_name.contains("panto") or part_name.contains("pantograph")
		if built_in_pantograph or part_name.contains("insulator_ridge"):
			mesh_instance.visible = false
			continue
		# Nested GLB nodes may not be inside the tree during the parent's _ready().
		# Compose their local transforms explicitly instead of reading global_transform.
		var relative := mesh_instance.transform
		var ancestor := mesh_instance.get_parent() as Node3D
		while ancestor != null and ancestor != vehicle:
			relative = ancestor.transform * relative
			ancestor = ancestor.get_parent() as Node3D
		if ancestor != vehicle:
			continue
		var local_bounds: AABB = relative * mesh_instance.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
	if first:
		return
	var roof_height := bounds.position.y + bounds.size.y
	_lead_model_bounds = bounds
	_lead_model_size = bounds.size
	var first_coach := train_root.get_node_or_null("Coach_01_YZ25T") as Node3D
	if first_coach != null:
		var coach_mount := first_coach.get_node_or_null("ModelMount") as Node3D
		var coach_bounds := AABB()
		var coach_first := true
		for candidate in coach_mount.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := candidate as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var relative := mesh_instance.transform
			var ancestor := mesh_instance.get_parent() as Node3D
			while ancestor != null and ancestor != first_coach:
				relative = ancestor.transform * relative
				ancestor = ancestor.get_parent() as Node3D
			if ancestor != first_coach:
				continue
			var local_bounds: AABB = relative * mesh_instance.get_aabb()
			coach_bounds = local_bounds if coach_first else coach_bounds.merge(local_bounds)
			coach_first = false
		_coach_model_size = coach_bounds.size
	_pantograph = Pantograph.new()
	_pantograph.name = "RoofPantograph"
	vehicle.add_child(_pantograph)
	_pantograph.position = Vector3(0.0, roof_height + 0.025, -4.0)
	var required_height := CONTACT_WIRE_HEIGHT_M - CAR_BASE_HEIGHT_M - _pantograph.position.y
	_pantograph.configure(clampf(required_height, 0.75, 2.55))
	print("BALLASTED_PANTOGRAPH_READY roof=", roof_height,
		" raised_height=", _pantograph.raised_height)

func _verges() -> void:
	var root := Node3D.new()
	root.name = "NaturalRailwayVerges"
	add_child(root)

func _process(delta: float) -> void:
	if _has_stream_state:
		var packet_age_s := float(Time.get_ticks_usec() - _last_stream_receive_usec) / 1000000.0
		var prediction_age_s := minf(packet_age_s, maximum_stream_prediction_s)
		var target_mileage := float(_target_stream_state.get("mileage_m", _display_mileage_m))
		var target_speed := float(_target_stream_state.get("speed_m_s", 0.0))
		var predicted_mileage := target_mileage + target_speed * prediction_age_s
		if absf(predicted_mileage - _display_mileage_m) >= stream_teleport_threshold_m:
			_display_mileage_m = predicted_mileage
		else:
			# Preserve continuous physical motion between 1 kHz packets; only the
			# small phase error is smoothed, so smoothing never replaces velocity.
			if packet_age_s <= maximum_stream_prediction_s:
				_display_mileage_m += target_speed * delta
			var correction := 1.0 - exp(-delta / maxf(stream_smoothing_time_s, 0.001))
			_display_mileage_m += (predicted_mileage - _display_mileage_m) * correction
		var visual_state := _target_stream_state.duplicate()
		visual_state["mileage_m"] = _display_mileage_m
		_apply_visual_state(visual_state)
	if _camera == null:
		return
	super._process(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_C or key_event.keycode == KEY_6:
				_cab_view_enabled = not _cab_view_enabled
				if _speed_chart != null:
					_speed_chart.set_cab_view(_cab_view_enabled)
				if _cab_view_enabled:
					_update_cab_camera(get_node_or_null("Train") as Node3D)
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_V:
				if _speed_chart != null:
					_speed_chart.visible = not _speed_chart.visible
				get_viewport().set_input_as_handled()
				return
	super._unhandled_input(event)


func _finish_smoke_test() -> void:
	await get_tree().process_frame
	var curve_pose: Transform3D = route_profile.pose_at_distance(2000.0)
	var ok: bool = _route_error.is_empty() and route_profile.sample_count() > 30000
	ok = ok and _rail_segment_count > 15000 and _route_sleeper_count > 25000
	ok = ok and stone_count > 80000
	ok = ok and absf(curve_pose.origin.x) > 1.0
	ok = ok and get_node_or_null("ContinuousBallastBed") != null
	ok = ok and simulation_stream != null
	ok = ok and _speed_chart != null
	ok = ok and _mini_map != null
	ok = ok and _catenary_mast_count > 300 and _catenary_wire_count > 7000
	ok = ok and _pantograph != null
	ok = ok and _lead_model_size.distance_to(Vector3(3.1008, 4.3011, 20.8490)) < 0.05
	ok = ok and _coach_model_size.distance_to(Vector3(3.0997, 4.4291, 25.4978)) < 0.05
	var train_root := get_node_or_null("Train") as Node3D
	var type_counts := {"YZ25T": 0, "CA25T": 0, "RW25T": 0, "YW25T": 0}
	if train_root != null:
		for vehicle in train_root.get_children():
			var vehicle_type := String(vehicle.get_meta("vehicle_type", ""))
			if type_counts.has(vehicle_type):
				type_counts[vehicle_type] += 1
	ok = ok and train_root != null and train_root.get_child_count() == COACH_COUNT + 1
	ok = ok and type_counts.YZ25T == 8 and type_counts.CA25T == 1
	ok = ok and type_counts.RW25T == 1 and type_counts.YW25T == 8
	print("BALLASTED_ROUTE_SMOKE ", "PASS" if ok else "FAIL",
		" route_samples=", route_profile.sample_count(), " rail_segments=", _rail_segment_count,
		" sleepers=", _route_sleeper_count, " stones=", stone_count,
		" curve_x_at_2km=", curve_pose.origin.x)
	await _clean_shutdown(0 if ok else 1)


func _clean_shutdown(exit_code: int) -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)

