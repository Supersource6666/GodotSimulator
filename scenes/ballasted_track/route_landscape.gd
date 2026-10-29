extends Node3D
## Camera-local, deterministic scenery along the measured route. No editor plugin required.
const Plants = preload("res://scenes/ballasted_track/vegetation.gd")
const Batch = preload("res://assets/procedural/detail_batch.gd")
const CHUNK_M := 64.0
var profile
var start_m := -650.0
var end_m := 8000.0
var view_distance := 420.0
var density := 1.0
var meshes: Array[Mesh] = []
var centers: Dictionary = {}
var chunks: Dictionary = {}
var ground_material: Material
var rng := RandomNumberGenerator.new()

func configure(route, tree: Mesh, shrub: Mesh) -> void:
	profile = route
	var generator := Plants.new()
	generator.rng.seed = 20261027
	generator.leaf_density = 0.65
	generator.summer_palette = true
	for i in range(6):
		var replacement := tree if i < 3 else shrub
		meshes.append(replacement if replacement != null else generator._plant_mesh(i))
	meshes.append(generator._grass_mesh())
	generator.free()
	ground_material = ShaderMaterial.new()
	ground_material.shader = preload("res://scenes/ballasted_track/verge_ground.gdshader")
	for index in range(int(floor(start_m / CHUNK_M)), int(ceil(end_m / CHUNK_M))):
		centers[index] = profile.pose_at_distance((index + 0.5) * CHUNK_M).origin

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		refresh(camera.global_position)

func refresh(camera_position: Vector3, budget: int = 2) -> void:
	var pending: Array[int] = []
	for index in centers:
		var distance: float = (centers[index] as Vector3).distance_to(camera_position)
		if distance < view_distance and not chunks.has(index):
			pending.append(index)
		elif distance > view_distance + CHUNK_M * 2.0 and chunks.has(index):
			chunks[index].queue_free()
			chunks.erase(index)
	pending.sort_custom(func(a: int, b: int) -> bool:
		return centers[a].distance_squared_to(camera_position) < centers[b].distance_squared_to(camera_position))
	for i in range(mini(budget, pending.size())):
		_build_chunk(pending[i])

func _bank_height(lateral: float, distance: float) -> float:
	var edge := maxf(lateral - 5.0, 0.0) if lateral > 0 else maxf(-lateral - 8.5, 0.0)
	return -0.22 + minf(edge * 0.10, 2.0) * (0.75 + 0.25 * sin(distance * 0.018))

func _build_chunk(index: int) -> void:
	rng.seed = 20261027 + index * 7919
	var root := Node3D.new()
	root.name = "Landscape_%d" % index
	add_child(root)
	chunks[index] = root
	var begin := maxf(index * CHUNK_M, start_m)
	var end := minf((index + 1) * CHUNK_M, end_m)
	var buckets: Array = []
	for i in range(7): buckets.append([])
	for side in [-1.0, 1.0]:
		for layer in range(3):
			var count := int([18, 13, 11][layer] * density)
			for i in range(count):
				var distance := rng.randf_range(begin, end)
				var lateral: float = side * rng.randf_range([7.5, 16.0, 27.0][layer], [10.0, 23.0, 40.0][layer])
				if side < 0: lateral -= 3.5
				var pose: Transform3D = profile.pose_at_distance(distance, lateral, _bank_height(lateral, distance))
				# Existing LY building and apron are world-aligned at the route origin.
				if pose.origin.x < -6.0 and pose.origin.x > -32.0 and pose.origin.z > -28.0 and pose.origin.z < 8.0:
					continue
				var variant := rng.randi_range(3, 5) if layer == 0 or (layer == 1 and i % 2 == 0) else rng.randi_range(0, 2)
				var scale := rng.randf_range(0.65, 1.25)
				if layer == 1 and variant >= 3: scale *= 1.8
				pose.basis = pose.basis.rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.1), scale))
				buckets[variant].append(pose)
		for i in range(int(420 * density)):
			var distance := rng.randf_range(begin, end)
			var lateral: float = side * rng.randf_range(4.8, 12.0) - (3.5 if side < 0 else 0.0)
			var pose: Transform3D = profile.pose_at_distance(distance, lateral, _bank_height(lateral, distance))
			if pose.origin.x < -6.0 and pose.origin.x > -32.0 and pose.origin.z > -28.0 and pose.origin.z < 8.0: continue
			pose.basis = pose.basis.rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.8))
			buckets[6].append(pose)
		_build_bank(root, begin, end, side)
	for i in range(7):
		var poses: Array[Transform3D] = []
		poses.assign(buckets[i])
		var instance := Batch.batch(root, "Foliage_%d" % i, meshes[i], poses, 155.0 if i == 6 else view_distance)
		if instance != null and i == 6:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_bank(root: Node3D, begin: float, end: float, side: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance := begin
	while distance < end:
		var next := minf(distance + 8.0, end)
		for strip in range(8):
			var a := side * (5.0 + strip * 5.0) - (3.5 if side < 0 else 0.0)
			var b := a + side * 5.0
			var points: Array[Vector3] = []
			for coord in [Vector2(distance, a), Vector2(distance, b), Vector2(next, a), Vector2(next, b)]:
				points.append(profile.pose_at_distance(coord.x, coord.y, _bank_height(coord.y, coord.x)).origin)
			for vertex in ([0, 2, 1, 1, 2, 3] if side > 0 else [0, 1, 2, 1, 3, 2]):
				st.add_vertex(points[vertex])
		distance = next
	st.generate_normals()
	st.set_material(ground_material)
	var bank := MeshInstance3D.new()
	bank.name = "GrassyBank"
	bank.mesh = st.commit()
	root.add_child(bank)
