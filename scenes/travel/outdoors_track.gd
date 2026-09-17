extends "res://assets/procedural/track_generator.gd"
## Photo reference: low bevelled concrete seats and paired curved spring clips.
## Seat origin is slab top; sleeper_height_m includes the 14 mm rubber pad.
var fastener_instance_count := 0

func _build_instanced_sleepers(samples: Array[Dictionary], _material: Material) -> void:
	_sleeper_root = Node3D.new()
	_sleeper_root.name = "OutdoorsRailSeatSystem"
	add_child(_sleeper_root)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.55, 0.56, 0.55)
	concrete.roughness = 0.9
	var seats: Array[Transform3D] = []
	var distance := 0.0
	while distance < float(samples[-1].distance):
		var sample := _interpolate_sample(samples, distance)
		var frame := Basis(sample.right, sample.up, -sample.forward)
		for side: float in [-1.0, 1.0]:
			var center: Vector3 = sample.point + sample.up * (ground_clearance_m + ballast_height_m) + sample.right * (side * rail_gauge_m * 0.5)
			seats.append(Transform3D(frame, center))
		distance += sleeper_spacing_m
	sleeper_instance_count = seats.size()
	fastener_instance_count = seats.size()
	_add_track_batch(_sleeper_root, "RailSeats", seats, concrete, _rail_seat_mesh())
	_build_fasteners(_sleeper_root, seats)
	_build_slab_joints(samples)

func _add_rail_surface(array_mesh: ArrayMesh, samples: Array[Dictionary], center_offset: float, _material: Material) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(samples.size() - 1):
		var a: Vector3 = samples[i].point
		var b: Vector3 = samples[i + 1].point
		var frame := Basis(samples[i].right, samples[i].up, -samples[i].forward)
		var foot := (a + b) * 0.5 + frame.x * center_offset + frame.y * (ground_clearance_m + ballast_height_m + sleeper_height_m)
		for section in [Vector3(0.15, 0.03, 0.015), Vector3(0.018, 0.08, 0.07), Vector3(0.07, 0.05, 0.135)]:
			_append_box(vertices, normals, uvs, indices, foot + frame.y * section.z, frame.x, frame.y, frame.z, Vector3(section.x, section.y, a.distance_to(b)))
	var steel := _create_material("", Color(0.32, 0.34, 0.36), 0.75, 0.35)
	_commit_surface(array_mesh, vertices, normals, uvs, indices, steel)

func _build_fasteners(root: Node3D, seats: Array[Transform3D]) -> void:
	# One shared, vertex-coloured assembly per seat; all four rails use it.
	# Local y=0 is the underside of the rail foot, not the rail head.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Color(0.065, 0.075, 0.08)
	var spring := Color(0.18, 0.19, 0.17)
	var bolt := Color(0.33, 0.34, 0.30)
	var insulation := Color(0.22, 0.23, 0.20)
	var pad := BoxMesh.new()
	pad.size = Vector3(0.19, 0.014, 0.28)
	_fastener_part(st, pad, Transform3D(Basis.IDENTITY, Vector3(0, -0.007, 0)), dark)
	for side: float in [-1.0, 1.0]:
		var shoulder := BoxMesh.new()
		shoulder.size = Vector3(0.09, 0.045, 0.19)
		_fastener_part(st, shoulder, Transform3D(Basis.IDENTITY, Vector3(side * 0.145, 0.0085, 0)), dark)
		var block := BoxMesh.new()
		block.size = Vector3(0.032, 0.014, 0.15)
		_fastener_part(st, block, Transform3D(Basis.IDENTITY, Vector3(side * 0.079, 0.031, 0)), insulation)
		var washer := CylinderMesh.new()
		washer.top_radius = 0.024
		washer.bottom_radius = 0.024
		washer.height = 0.008
		washer.radial_segments = 12
		washer.rings = 1
		_fastener_part(st, washer, Transform3D(Basis.IDENTITY, Vector3(side * 0.153, 0.043, 0)), bolt)
		var nut := CylinderMesh.new()
		nut.top_radius = 0.017
		nut.bottom_radius = 0.017
		nut.height = 0.024
		nut.radial_segments = 6
		nut.rings = 1
		_fastener_part(st, nut, Transform3D(Basis.IDENTITY, Vector3(side * 0.153, 0.059, 0)), bolt)
		# Bent spring-steel clip: two toes bear on the insulated rail foot.
		var points := PackedVector3Array([
			Vector3(side * 0.067, 0.042, -0.056),
			Vector3(side * 0.105, 0.074, -0.065),
			Vector3(side * 0.178, 0.079, -0.050),
			Vector3(side * 0.19, 0.067, 0),
			Vector3(side * 0.178, 0.079, 0.050),
			Vector3(side * 0.105, 0.074, 0.065),
			Vector3(side * 0.067, 0.042, 0.056)])
		_append_spring(st, points, spring)
		var stud := CylinderMesh.new()
		stud.top_radius = 0.009
		stud.bottom_radius = 0.009
		stud.height = 0.012
		stud.radial_segments = 10
		stud.rings = 1
		_fastener_part(st, stud, Transform3D(Basis.IDENTITY, Vector3(side * 0.153, 0.077, 0)), dark)
	var assembly := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.72
	material.metallic = 0.25
	assembly.surface_set_material(0, material)
	for start in range(0, seats.size(), 128):
		var count := mini(128, seats.size() - start)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = assembly
		mm.instance_count = count
		for j in range(count):
			var seat := seats[start + j]
			var frame := seat.basis.orthonormalized()
			mm.set_instance_transform(j, Transform3D(frame, seat.origin + frame.y * sleeper_height_m))
		var instance := MultiMeshInstance3D.new()
		instance.name = 'Fasteners_%d' % start
		instance.multimesh = mm
		instance.visibility_range_end = 100.0
		instance.visibility_range_end_margin = 20.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	print('[Travel] fasteners: assemblies=%d (4 rails, shared mesh, 100 m range)' % seats.size())


func _fastener_part(st: SurfaceTool, mesh: PrimitiveMesh, pose: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		st.set_color(color)
		st.set_normal((pose.basis * normals[index]).normalized())
		st.add_vertex(pose * vertices[index])


func _track_box(frame: Basis, center: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis(frame.x * size.x, frame.y * size.y, frame.z * size.z), center)


func _add_track_batch(parent: Node3D, label: String, transforms: Array[Transform3D], material: Material, shared_mesh: Mesh = null) -> void:
	# Spatial chunks keep the full 25 km alignment from rendering at once.
	for start in range(0, transforms.size(), 512):
		var count := mini(512, transforms.size() - start)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mm.mesh = shared_mesh if shared_mesh != null else box
		mm.instance_count = count
		for j in range(count):
			mm.set_instance_transform(j, transforms[start + j])
		var instance := MultiMeshInstance3D.new()
		instance.name = '%s_%d' % [label, start]
		instance.multimesh = mm
		instance.material_override = material
		if label in ['Guardrails', 'ContactWires', 'Insulators']:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if label == 'RailSeats':
			instance.visibility_range_end = 240.0
			instance.visibility_range_end_margin = 40.0
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(instance)


func _rail_seat_mesh() -> ArrayMesh:
	# Octagonal rings: base lip, sloped shoulders, bevel and flat bearing surface.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for section in [Vector4(0.32, 0.19, 0.0, 0.035),
			Vector4(0.32, 0.19, 0.018, 0.035),
			Vector4(0.225, 0.155, sleeper_height_m - 0.032, 0.035),
			Vector4(0.207, 0.145, sleeper_height_m - 0.014, 0.025)]:
		var x: float = section.x
		var z: float = section.y
		var y: float = section.z
		var bevel: float = section.w
		rings.append(PackedVector3Array([
			Vector3(-x + bevel, y, -z), Vector3(x - bevel, y, -z),
			Vector3(x, y, -z + bevel), Vector3(x, y, z - bevel),
			Vector3(x - bevel, y, z), Vector3(-x + bevel, y, z),
			Vector3(-x, y, z - bevel), Vector3(-x, y, -z + bevel)]))
	for r in range(rings.size() - 1):
		for i in range(8):
			var j := (i + 1) % 8
			_seat_triangle(st, rings[r][i], rings[r + 1][i], rings[r + 1][j])
			_seat_triangle(st, rings[r][i], rings[r + 1][j], rings[r][j])
	for i in range(8):
		var j := (i + 1) % 8
		_seat_triangle(st, Vector3(0, sleeper_height_m - 0.014, 0), rings[-1][j], rings[-1][i])
		_seat_triangle(st, Vector3.ZERO, rings[0][i], rings[0][j])
	return st.commit()


func _seat_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot uses clockwise front faces.
	var normal := (b - a).cross(c - a).normalized()
	for vertex in [a, c, b]:
		st.set_normal(normal)
		st.add_vertex(vertex)


func _append_spring(st: SurfaceTool, controls: PackedVector3Array, color: Color) -> void:
	# Sweep one continuous round rod along a Catmull-Rom centreline.
	var path := PackedVector3Array()
	for i in range(controls.size() - 1):
		for step in range(6):
			path.append(controls[i].cubic_interpolate(controls[i + 1],
				controls[maxi(0, i - 1)], controls[mini(controls.size() - 1, i + 2)], float(step) / 6.0))
	path.append(controls[-1])
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in range(path.size()):
		var tangent := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var across := tangent.cross(Vector3.UP).normalized()
		var vertical := across.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for j in range(8):
			var angle := TAU * float(j) / 8.0
			var normal := across * cos(angle) + vertical * sin(angle)
			ring.append(path[i] + normal * 0.009)
			ring_normals.append(normal)
		rings.append(ring)
		normals.append(ring_normals)
	for i in range(path.size() - 1):
		for j in range(8):
			var k := (j + 1) % 8
			for index in [Vector2i(i, j), Vector2i(i, k), Vector2i(i + 1, k),
					Vector2i(i, j), Vector2i(i + 1, k), Vector2i(i + 1, j)]:
				st.set_color(color)
				st.set_normal(normals[index.x][index.y])
				st.add_vertex(rings[index.x][index.y])
	for end in [0, path.size() - 1]:
		var normal := (path[0] - path[1]).normalized() if end == 0 else (path[-1] - path[-2]).normalized()
		for j in range(8):
			var k := (j + 1) % 8
			var cap := [path[end], rings[end][k], rings[end][j]] if end == 0 else [path[end], rings[end][j], rings[end][k]]
			for vertex in cap:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(vertex)
