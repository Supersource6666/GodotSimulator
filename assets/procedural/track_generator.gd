extends MeshInstance3D
## 程序化轨道生成器（离线版）
## 输入 samples：{point,forward,right,up,distance}；point 即道砟底/桥面顶基准。
## 已去除 TrackManager / 外部纹理依赖，仅依赖 set_custom_samples 输入。

const DEFAULT_RAIL_TEXTURE_PATH := ""
const DEFAULT_BALLAST_TEXTURE_PATH := ""
## Marked photo reference: light concrete slab, darker warm-grey concrete seats.
## These are lit albedo values, not a direct copy of screenshot pixel colors.
const SLAB_COLOR := Color(0.64, 0.63, 0.58)
const RAIL_SEAT_COLOR := Color(0.52, 0.51, 0.47)
const RAIL_COLOR := Color(0.14, 0.19, 0.23)
const DetailBatch := preload("res://assets/procedural/detail_batch.gd")

@export_range(0.5, 20.0, 0.5) var step_distance_m := 4.0
@export_range(0.5, 3.0, 0.001) var rail_gauge_m := 1.435
@export_range(0.02, 0.4, 0.01) var rail_head_width_m := 0.12
@export_range(0.04, 0.5, 0.01) var rail_height_m := 0.18
@export_range(0.4, 6.0, 0.1) var ballast_width_m := 3.6
@export_range(0.02, 0.5, 0.01) var ballast_height_m := 0.12
@export_range(0.0, 2.0, 0.01) var ground_clearance_m := 0.0
@export_range(0.1, 2.0, 0.05) var sleeper_spacing_m := 0.65
@export_range(0.5, 5.0, 0.1) var sleeper_length_m := 2.6
@export_range(0.05, 0.5, 0.01) var sleeper_width_m := 0.26
@export_range(0.02, 0.3, 0.01) var sleeper_height_m := 0.10
@export_range(0, 10000, 100) var max_sleeper_count := 1600
@export var rail_texture_path := DEFAULT_RAIL_TEXTURE_PATH
@export var ballast_texture_path := DEFAULT_BALLAST_TEXTURE_PATH
@export var build_on_ready := false
@export var use_instanced_sleepers := true
@export var ballastless := true
const RAIL_SEAT_WIDTH_M := 0.46
const SLEEPER_CHUNK_LENGTH_M := 250.0
var sleeper_instance_count := 0
var _sleeper_root: Node3D

var _custom_samples: Array[Dictionary] = []


func _ready() -> void:
	top_level = true
	if build_on_ready:
		await get_tree().process_frame
		generate_track_mesh()


func set_custom_samples(samples: Array[Dictionary]) -> void:
	_custom_samples = samples


static func offset_samples(samples: Array[Dictionary], lateral_m: float) -> Array[Dictionary]:
	# Offset in each sample's local frame, not a global translation on curves.
	# Preserve chainage so bridge piers and both tracks share route stations.
	var result: Array[Dictionary] = []
	for sample in samples:
		var shifted := sample.duplicate()
		shifted["point"] = (sample["point"] as Vector3) + (sample["right"] as Vector3) * lateral_m
		result.append(shifted)
	return result


func generate_track_mesh() -> void:
	var samples := _custom_samples
	sleeper_instance_count = 0
	if _sleeper_root != null:
		_sleeper_root.free()
		_sleeper_root = null
	if samples.size() < 2:
		push_warning("ProceduralTrackGenerator: not enough samples to build a track mesh.")
		mesh = null
		return

	var rail_material := _create_material(rail_texture_path, RAIL_COLOR, 0.7, 0.48)
	# Concrete slab and rail seats receive light/shadows instead of glowing
	# as an unshaded white strip. No extra image textures or network dependency.
	var ballast_material := _create_material("", SLAB_COLOR, 0.0, 0.9)
	var sleeper_material := _create_material("", RAIL_SEAT_COLOR, 0.0, 1.0)
	var array_mesh := ArrayMesh.new()

	_add_ballast_surface(array_mesh, samples, ballast_material)
	_add_rail_surface(array_mesh, samples, -rail_gauge_m * 0.5, rail_material)
	_add_rail_surface(array_mesh, samples, rail_gauge_m * 0.5, rail_material)
	if _sleeper_root != null:
		_sleeper_root.free()
		_sleeper_root = null
	if use_instanced_sleepers or ballastless:
		_build_instanced_sleepers(samples, sleeper_material)
	else:
		_add_sleeper_surface(array_mesh, samples, sleeper_material)

	mesh = array_mesh
	print_rich("[color=cyan]ProceduralTrackGenerator: built %d samples over %.1f m[/color]" % [
		samples.size(),
		samples[samples.size() - 1]["distance"] as float,
	])


func _make_sample(point: Vector3, tangent: Vector3, up_axis: Vector3, distance: float) -> Dictionary:
	var up := up_axis.normalized()
	var forward := tangent - up * tangent.dot(up)
	if forward.length_squared() <= 0.000001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	if right.length_squared() <= 0.000001:
		right = Vector3.RIGHT
	return {
		"point": point,
		"forward": forward,
		"right": right,
		"up": up,
		"distance": distance,
	}


func _add_ballast_surface(array_mesh: ArrayMesh, samples: Array[Dictionary], material: Material) -> void:
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var half_width := ballast_width_m * 0.5
	var top_half_width := half_width if ballastless else half_width * 0.72
	var top_y := ballast_height_m
	var shoulder_y := 0.0

	for sample in samples:
		var up := sample["up"] as Vector3
		var point := (sample["point"] as Vector3) + up * ground_clearance_m
		var right := sample["right"] as Vector3
		var distance := sample["distance"] as float
		var base_index := vertices.size()
		var left_shoulder := point - right * half_width + up * shoulder_y
		var left_top := point - right * top_half_width + up * top_y
		var right_top := point + right * top_half_width + up * top_y
		var right_shoulder := point + right * half_width + up * shoulder_y
		if ballastless:
			# Separate side/top normals keep concrete slab edges crisp.
			vertices.append_array([left_shoulder, left_top, left_top, right_top, right_top, right_shoulder])
			normals.append_array([-right, -right, up, up, right, right])
			uvs.append_array([Vector2.ZERO, Vector2.UP, Vector2.ZERO, Vector2.RIGHT, Vector2.UP, Vector2.ZERO])
			if base_index >= 6:
				_stitch_strip(indices, base_index - 6, base_index, 6)
			continue
		vertices.append_array([left_shoulder, left_top, right_top, right_shoulder])
		normals.append_array([up, up, up, up])
		uvs.append_array([
			Vector2(0.0, distance / 4.0),
			Vector2(0.18, distance / 4.0),
			Vector2(0.82, distance / 4.0),
			Vector2(1.0, distance / 4.0),
		])
		if base_index >= 4:
			_stitch_strip(indices, base_index - 4, base_index, 4)

	_commit_surface(array_mesh, vertices, normals, uvs, indices, material)


func _add_rail_surface(array_mesh: ArrayMesh, samples: Array[Dictionary], center_offset: float, material: Material) -> void:
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var half_head := rail_head_width_m * 0.5
	var half_foot := rail_head_width_m * 0.85
	var web_half := rail_head_width_m * 0.20
	var foot_fillet_h := rail_height_m * 0.12
	var web_lower_h := rail_height_m * 0.42
	var web_upper_h := rail_height_m * 0.78
	var head_fillet_h := rail_height_m * 0.92
	var profile := [
		Vector2(-half_foot, 0.0),
		Vector2(half_foot, 0.0),
		Vector2(half_foot, foot_fillet_h),
		Vector2(web_half, web_lower_h),
		Vector2(web_half, web_upper_h),
		Vector2(half_head, head_fillet_h),
		Vector2(half_head, rail_height_m),
		Vector2(-half_head, rail_height_m),
		Vector2(-half_head, head_fillet_h),
		Vector2(-web_half, web_upper_h),
		Vector2(-web_half, web_lower_h),
		Vector2(-half_foot, foot_fillet_h),
	]

	var profile_size := profile.size()
	var profile_normals_2d: PackedVector2Array = []
	profile_normals_2d.resize(profile_size)
	for i in range(profile_size):
		var prev: Vector2 = profile[(i - 1 + profile_size) % profile_size]
		var curr: Vector2 = profile[i]
		var next: Vector2 = profile[(i + 1) % profile_size]
		var in_dir := (curr - prev).normalized()
		var out_dir := (next - curr).normalized()
		var bisector := (in_dir + out_dir).normalized()
		# 旋转 90° 取外法线（CCW）
		profile_normals_2d[i] = Vector2(bisector.y, -bisector.x)

	for sample in samples:
		var up := sample["up"] as Vector3
		var point := (sample["point"] as Vector3) + up * ground_clearance_m
		var right := sample["right"] as Vector3
		var distance := sample["distance"] as float
		var center := point + right * center_offset + up * (ballast_height_m + sleeper_height_m)
		var base_index := vertices.size()
		for pi in range(profile_size):
			var local: Vector2 = profile[pi]
			var n2d: Vector2 = profile_normals_2d[pi]
			vertices.append(center + right * local.x + up * local.y)
			normals.append((right * n2d.x + up * n2d.y).normalized())
			uvs.append(Vector2(inverse_lerp(-half_foot, half_foot, local.x), distance / 6.0))
		if base_index >= profile_size:
			_stitch_strip(indices, base_index - profile_size, base_index, profile_size)

	_commit_surface(array_mesh, vertices, normals, uvs, indices, material)


func _build_instanced_sleepers(samples: Array[Dictionary], material: Material) -> void:
	_sleeper_root = Node3D.new()
	_sleeper_root.name = "RailSeatBatches" if ballastless else "SleeperBatches"
	add_child(_sleeper_root)
	var box := BoxMesh.new()
	box.size = Vector3(RAIL_SEAT_WIDTH_M if ballastless else sleeper_length_m, sleeper_height_m, sleeper_width_m)
	box.material = material
	var total_length := float(samples[-1]["distance"])
	var spacing := maxf(sleeper_spacing_m, 0.1)
	var poses: Array[Transform3D] = []
	var fasteners: ArrayMesh = _make_fastener_mesh() if ballastless else null
	var chunk := 0
	for index in range(int(floor(total_length / spacing)) + 1):
		var distance := index * spacing
		var next_chunk := int(distance / SLEEPER_CHUNK_LENGTH_M)
		if next_chunk != chunk:
			DetailBatch.batch(_sleeper_root, "Sleepers_%d" % chunk, box, poses, 850.0)
			if ballastless:
				DetailBatch.batch(_sleeper_root, "Fasteners_%d" % chunk, fasteners, poses, 250.0)
			poses.clear()
			chunk = next_chunk
		var sample := _interpolate_sample(samples, distance)
		var up: Vector3 = sample["up"]
		var center: Vector3 = sample["point"] + up * (ground_clearance_m + ballast_height_m + sleeper_height_m * 0.5)
		var offsets := [-rail_gauge_m * 0.5, rail_gauge_m * 0.5] if ballastless else [0.0]
		for offset in offsets:
			poses.append(Transform3D(Basis(sample["right"], up, -sample["forward"]), center + (sample["right"] as Vector3) * float(offset)))
			sleeper_instance_count += 1
	DetailBatch.batch(_sleeper_root, "Sleepers_%d" % chunk, box, poses, 850.0)
	if ballastless:
		DetailBatch.batch(_sleeper_root, "Fasteners_%d" % chunk, fasteners, poses, 250.0)
		_build_slab_joints(samples)


func _make_fastener_mesh() -> ArrayMesh:
	# One shared visual assembly per rail seat: sole plate, clips and bolt heads.
	# Plate top stays at the existing rail-foot height.
	var result := ArrayMesh.new()
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var top := sleeper_height_m * 0.5
	_append_box(vertices, normals, uvs, indices, Vector3(0, top - 0.009, 0),
		Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.38, 0.018, 0.23))
	for side in [-1.0, 1.0]:
		for along in [-0.065, 0.065]:
			_append_box(vertices, normals, uvs, indices, Vector3(side * 0.135, top + 0.025, along),
				Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.105, 0.028, 0.035))
		_append_box(vertices, normals, uvs, indices, Vector3(side * 0.18, top + 0.032, 0),
			Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.035, 0.055, 0.035))
	_commit_surface(result, vertices, normals, uvs, indices, _create_material("", Color(0.12, 0.115, 0.10), 0.55, 0.65))
	return result


func _build_slab_joints(samples: Array[Dictionary]) -> void:
	# Surface joint strips approximate panel boundaries without shifting rail height.
	var joint := BoxMesh.new()
	joint.size = Vector3(ballast_width_m, 0.003, 0.025)
	joint.material = _create_material("", Color(0.27, 0.26, 0.23), 0.0, 1.0)
	var poses: Array[Transform3D] = []
	var chunk := 0
	var total := float(samples[-1].distance)
	for index in range(1, int(total / 6.5) + 1):
		var distance := index * 6.5
		var next_chunk := int(distance / SLEEPER_CHUNK_LENGTH_M)
		if next_chunk != chunk:
			DetailBatch.batch(_sleeper_root, "SlabJoints_%d" % chunk, joint, poses, 600.0)
			poses.clear()
			chunk = next_chunk
		var sample := _interpolate_sample(samples, distance)
		var center: Vector3 = sample.point + sample.up * (ground_clearance_m + ballast_height_m + 0.0015)
		poses.append(Transform3D(Basis(sample.right, sample.up, -sample.forward), center))
	DetailBatch.batch(_sleeper_root, "SlabJoints_%d" % chunk, joint, poses, 600.0)


func _add_sleeper_surface(array_mesh: ArrayMesh, samples: Array[Dictionary], material: Material) -> void:
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var indices: PackedInt32Array = []
	var total_length := samples[samples.size() - 1]["distance"] as float
	var distance := 0.0
	var effective_spacing := sleeper_spacing_m
	if max_sleeper_count > 0:
		effective_spacing = maxf(effective_spacing, total_length / float(max_sleeper_count))

	while distance <= total_length:
		var sample := _interpolate_sample(samples, distance)
		_append_box(
			vertices,
			normals,
			uvs,
			indices,
			sample["point"] as Vector3 + (sample["up"] as Vector3) * (ground_clearance_m + ballast_height_m + sleeper_height_m * 0.5),
			sample["right"] as Vector3,
			sample["up"] as Vector3,
			sample["forward"] as Vector3,
			Vector3(sleeper_length_m, sleeper_height_m, sleeper_width_m)
		)
		distance += effective_spacing

	_commit_surface(array_mesh, vertices, normals, uvs, indices, material)


func _interpolate_sample(samples: Array[Dictionary], distance: float) -> Dictionary:
	if distance <= 0.0:
		return samples[0]

	if distance >= float(samples[-1]["distance"]):
		return samples[-1]
	var low := 0
	var high := samples.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if float(samples[middle]["distance"]) < distance:
			low = middle
		else:
			high = middle
	var a := samples[low]
	var b := samples[high]
	var weight := inverse_lerp(float(a["distance"]), float(b["distance"]), distance)
	var point := (a["point"] as Vector3).lerp(b["point"] as Vector3, weight)
	var tangent := (a["forward"] as Vector3).lerp(b["forward"] as Vector3, weight).normalized()
	var up := (a["up"] as Vector3).lerp(b["up"] as Vector3, weight).normalized()
	return _make_sample(point, tangent, up, distance)


func _stitch_strip(indices: PackedInt32Array, previous_base: int, current_base: int, vertex_count: int) -> void:
	for offset in range(vertex_count):
		var next_offset := (offset + 1) % vertex_count
		indices.append(previous_base + offset)
		indices.append(current_base + offset)
		indices.append(previous_base + next_offset)
		indices.append(previous_base + next_offset)
		indices.append(current_base + offset)
		indices.append(current_base + next_offset)


func _append_box(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	center: Vector3,
	right: Vector3,
	up: Vector3,
	forward: Vector3,
	size: Vector3
) -> void:
	var half_right := right * size.x * 0.5
	var half_up := up * size.y * 0.5
	var half_forward := forward * size.z * 0.5
	var corners := [
		center - half_right - half_up - half_forward,
		center + half_right - half_up - half_forward,
		center + half_right + half_up - half_forward,
		center - half_right + half_up - half_forward,
		center - half_right - half_up + half_forward,
		center + half_right - half_up + half_forward,
		center + half_right + half_up + half_forward,
		center - half_right + half_up + half_forward,
	]
	var faces := [
		[0, 1, 2, 3, -forward],
		[5, 4, 7, 6, forward],
		[4, 0, 3, 7, -right],
		[1, 5, 6, 2, right],
		[3, 2, 6, 7, up],
		[4, 5, 1, 0, -up],
	]
	for face in faces:
		var base_index := vertices.size()
		var normal := face[4] as Vector3
		vertices.append_array([
			corners[face[0] as int],
			corners[face[1] as int],
			corners[face[2] as int],
			corners[face[3] as int],
		])
		normals.append_array([normal, normal, normal, normal])
		uvs.append_array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		indices.append_array([
			base_index,
			base_index + 1,
			base_index + 2,
			base_index,
			base_index + 2,
			base_index + 3,
		])


func _commit_surface(
	array_mesh: ArrayMesh,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	material: Material
) -> void:
	if vertices.is_empty() or indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_material(array_mesh.get_surface_count() - 1, material)


func _create_material(texture_path: String, fallback_color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = fallback_color
	material.metallic = metallic
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path) as Texture2D
		material.texture_repeat = true
	return material
