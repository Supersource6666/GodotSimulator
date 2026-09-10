extends Node3D
## 离线预览列车视觉：4 节编组（参考 E:/game_project/train/scripts/train_demo_scene.gd，
## 即首尾 train1.glb + 2 节中间车厢 train2.glb，尾车反向，车厢中心距 27 m）。
## 每节车由车体 + 前/后转向架 + 轮对组成，整列车逐帧沿线路里程点贴轨放置。

const HEAD_MODEL_PATH := "res://assets/train/train1.glb"
const MIDDLE_MODEL_PATH := "res://assets/train/train2.glb"
const BOGIE_MODEL_PATH := "res://assets/train/bogie0720.glb"
const WHEEL_MODEL_PATH := "res://assets/train/wheelset0720.glb"

const CONSIST_CAR_COUNT := 4
const CAR_CENTER_SPACING_M := 27.0  # 车厢模型实测长约 26.8 m；27 m 中心距使车端间隙缩至约 0.2 m，编组更紧凑
const BODY_SCALE := Vector3(0.86, 0.9, 1.0)
const BODY_FLOOR_Y := 0.33          # 车体下沿低于轮心约 0.10 m（轮高 0.86，轮心 0.43），裙板遮住约 62% 车轮；保持轮轨接触不变。
const BOGIE_HALF_SPACING_M := 8.5   # 转向架距车厢中心的距离
const BOGIE_SIZE := Vector3(2.5, 0.75, 4.0)
const BOGIE_BOTTOM_Y := 0.65
const WHEEL_SIZE := Vector3(2.2, 0.86, 0.86)
const WHEEL_AXLE_HALF_M := 1.25
const BODY_BRIGHTNESS_SCALE := 0.78 # Only bright neutral body paint, not the city.
const BODY_MIN_ROUGHNESS := 0.42
const BODY_MAX_SPECULAR := 0.35

var cars: Array[Node3D] = []
var wheels: Array[Node3D] = []
var ready_for_preview := false
var pose_provider := Callable()
var anchor_distance := 0.0
var _car_mile_offsets: Array[float] = []
var _model_templates: Dictionary = {}


func _ready() -> void:
	_build_consist()
	ready_for_preview = cars.size() == CONSIST_CAR_COUNT and wheels.size() == CONSIST_CAR_COUNT * 4
	print("TRAIN_READY cars=", cars.size(), " wheels=", wheels.size(),
		" spacing_m=", CAR_CENTER_SPACING_M,
		" consist_span_m=", (CONSIST_CAR_COUNT - 1) * CAR_CENTER_SPACING_M,
		" models=", _model_templates.size())


func _process(_delta: float) -> void:
	if cars.is_empty() or not pose_provider.is_valid():
		return
	_apply_route_poses()

func _exit_tree() -> void:
	# GLTF template nodes are detached, so SceneTree cannot free them for us.
	# Car duplicates retain their own references to the shared mesh resources.
	for template in _model_templates.values():
		if is_instance_valid(template):
			template.free()
	_model_templates.clear()


func set_pose_source(provider: Callable) -> void:
	pose_provider = provider


func set_anchor_distance(distance: float) -> void:
	anchor_distance = distance


func _build_consist() -> void:
	# 首尾驾驶车，中间两辆；只反转尾车车壳，保持轮对贴轨姿态。
	var front_offset := float(CONSIST_CAR_COUNT - 1) * 0.5 * CAR_CENTER_SPACING_M
	for index in range(CONSIST_CAR_COUNT):
		var mile_offset := front_offset - CAR_CENTER_SPACING_M * float(index)
		_car_mile_offsets.append(mile_offset)
		var car := Node3D.new()
		car.name = "Car%d" % (index + 1)
		add_child(car)
		var is_tail := index == CONSIST_CAR_COUNT - 1
		_add_body(car, HEAD_MODEL_PATH if index == 0 or is_tail else MIDDLE_MODEL_PATH, is_tail)
		_add_running_gear(car)
		cars.append(car)


func _add_body(car: Node3D, path: String, reversed: bool = false) -> void:
	var body := _new_model(path)
	if body == null:
		return
	car.add_child(body)
	body.scale = BODY_SCALE
	body.set_meta("model_path", path)
	if reversed:
		body.rotate_y(PI)
	# Recenter after rotation, including asymmetric nose/body bounds.
	var bounds := visual_bounds(body, car)
	body.position += Vector3(-bounds.get_center().x, BODY_FLOOR_Y - bounds.position.y, -bounds.get_center().z)


func _add_running_gear(car: Node3D) -> void:
	for bogie_z in [-BOGIE_HALF_SPACING_M, BOGIE_HALF_SPACING_M]:
		var bogie := _new_model(BOGIE_MODEL_PATH)
		if bogie == null:
			return
		car.add_child(bogie)
		bogie.rotation.y = -PI / 2.0
		_fit(bogie, BOGIE_SIZE, Vector3(0, BOGIE_BOTTOM_Y, bogie_z), car)
		for axle in [-WHEEL_AXLE_HALF_M, WHEEL_AXLE_HALF_M]:
			var wheel := _new_model(WHEEL_MODEL_PATH)
			if wheel == null:
				return
			car.add_child(wheel)
			wheel.rotation.y = -PI / 2.0
			_fit(wheel, WHEEL_SIZE, Vector3(0, 0, bogie_z + axle), car)
			wheels.append(wheel)


func _new_model(path: String) -> Node3D:
	var template: Node3D = _model_templates.get(path)
	if template == null:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) != OK:
			push_error("Train model failed to load: " + path)
			return null
		template = document.generate_scene(state) as Node3D
		if template == null:
			push_error("Train model produced no scene: " + path)
			return null
		if path == HEAD_MODEL_PATH or path == MIDDLE_MODEL_PATH:
			_soften_body_materials(template)
		_model_templates[path] = template
	# 共享网格资源：duplicate 只复制节点，mesh/material 资源保持共享。
	return template.duplicate(true) as Node3D


func _soften_body_materials(model: Node3D) -> void:
	# Override copies on the body template, then share them across car instances.
	# Never mutate source mesh materials or GLB files; running gear stays unchanged.
	var copies: Dictionary = {}
	var nodes: Array[Node] = [model]
	nodes.append_array(model.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if not node is MeshInstance3D or node.mesh == null:
			continue
		for surface in node.mesh.get_surface_count():
			var source = node.get_active_material(surface)
			if not source is BaseMaterial3D:
				continue
			var color: Color = source.albedo_color
			var low := minf(color.r, minf(color.g, color.b))
			var high := maxf(color.r, maxf(color.g, color.b))
			var is_paint := low >= 0.45 and high - low <= 0.15
			var is_glass: bool = source.resource_name.begins_with("M_07") or source.resource_name.begins_with("M_08") or source.resource_name.begins_with("M_09")
			var key: int = source.get_instance_id()
			if not copies.has(key):
				var material := source.duplicate() as BaseMaterial3D
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				material.refraction_enabled = false
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				material.metallic = 0.0
				material.roughness = 0.48
				material.metallic_specular = BODY_MAX_SPECULAR
				material.clearcoat_enabled = false
				if is_paint:
					material.albedo_color = Color(0.78, 0.78, 0.78, 1.0)
					material.roughness = BODY_MIN_ROUGHNESS
					material.clearcoat_enabled = true
					material.clearcoat = 0.18
					material.clearcoat_roughness = 0.35
				elif is_glass:
					# Opaque tinted glazing: these exterior models have no finished interior.
					material.albedo_color = Color(0.075, 0.105, 0.13, color.a)
					material.roughness = 0.18
					material.metallic_specular = 0.5
				elif high < 0.015:
					material.roughness = 0.85
					material.metallic_specular = 0.15
				elif color.r > color.g * 2.0 and color.r > color.b * 2.0:
					material.albedo_color = Color(0.80, 0.03, 0.025, 1.0)
				material.albedo_color.a = 1.0
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				copies[key] = material
			node.set_surface_override_material(surface, copies[key])


func _fit(model: Node3D, size: Vector3, bottom: Vector3, parent: Node3D) -> void:
	var bounds := visual_bounds(model, parent)
	var mount := Node3D.new()
	parent.add_child(mount)
	model.reparent(mount)
	mount.scale = size / bounds.size
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	mount.position = bottom


func visual_bounds(model: Node3D, reference: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	var ref_inverse := reference.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local_bounds: AABB = ref_inverse * mesh_node.global_transform * mesh_node.get_aabb()
		combined = local_bounds if first else combined.merge(local_bounds)
		first = false
	return combined


func _apply_route_poses() -> void:
	var root_basis := global_transform.basis
	var root_position := global_transform.origin
	var root_inv_basis := root_basis.transposed()
	var count := cars.size()
	for index in range(count):
		var distance := maxf(anchor_distance + _car_mile_offsets[index], 0.0)
		var pose: Dictionary = pose_provider.call(distance, 0.0)
		if pose.is_empty():
			continue
		var point: Vector3 = pose.point
		var forward: Vector3 = pose.forward
		var up: Vector3 = pose.up
		var right := forward.cross(up).normalized()
		if right.length_squared() <= 0.000001:
			right = Vector3.RIGHT
		var world_basis := Basis(right, up, -forward).orthonormalized()
		var car := cars[index]
		car.position = root_inv_basis * (point - root_position)
		car.basis = (root_inv_basis * world_basis).orthonormalized()
