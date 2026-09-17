extends "res://assets/procedural/track_generator.gd"
## Local photo-reference details; other modules keep their existing track.

func generate_track_mesh() -> void:
	super.generate_track_mesh()
	mesh.surface_set_material(0, _concrete())
	for surface in [1, 2]:
		mesh.surface_set_material(surface, _create_material("", Color("493022"), 0.45, 0.62))


func _build_instanced_sleepers(samples: Array[Dictionary], _material: Material) -> void:
	_sleeper_root = Node3D.new()
	_sleeper_root.name = "RailSeatBatches"
	add_child(_sleeper_root)
	var seat := CylinderMesh.new()
	seat.radial_segments = 4
	seat.top_radius = 0.22
	seat.bottom_radius = 0.31
	seat.height = sleeper_height_m
	seat.material = _concrete()
	var plate := BoxMesh.new()
	plate.size = Vector3(0.30, 0.014, 0.24)
	plate.material = _create_material("", Color("242b2b"), 0.25, 0.85)
	var clip := _clip_mesh()
	var cap := BoxMesh.new()
	cap.size = Vector3(rail_head_width_m * 0.9, 0.006, 5.0)
	cap.material = _create_material("", Color("8e9697"), 0.8, 0.3)
	for chunk in range(0, int(float(samples[-1].distance)), 100):
		var seats: Array[Transform3D] = []
		var plates: Array[Transform3D] = []
		var clips: Array[Transform3D] = []
		var heads: Array[Transform3D] = []
		for i in range(int(100.0 / sleeper_spacing_m)):
			var d := float(chunk) + i * sleeper_spacing_m
			var sample := _interpolate_sample(samples, d)
			for side in [-1.0, 1.0]:
				var p: Vector3 = sample.point + Vector3(float(side) * rail_gauge_m * 0.5, ground_clearance_m + ballast_height_m, 0)
				seats.append(Transform3D(Basis(Vector3.UP, PI / 4.0), p + Vector3(0, sleeper_height_m * 0.5, 0)))
				plates.append(Transform3D(Basis.IDENTITY, p + Vector3(0, sleeper_height_m - 0.007, 0)))
				clips.append(Transform3D(Basis.IDENTITY, p + Vector3(0, sleeper_height_m, 0)))
				sleeper_instance_count += 1
		for d in range(chunk, chunk + 100, 5):
			var sample := _interpolate_sample(samples, float(d) + 2.5)
			for side in [-1.0, 1.0]:
				heads.append(Transform3D(Basis.IDENTITY, sample.point + Vector3(float(side) * rail_gauge_m * 0.5, ground_clearance_m + ballast_height_m + sleeper_height_m + rail_height_m, 0)))
		DetailBatch.batch(_sleeper_root, "TaperedSeats_%d" % chunk, seat, seats, 0)
		DetailBatch.batch(_sleeper_root, "RubberPads_%d" % chunk, plate, plates, 0)
		DetailBatch.batch(_sleeper_root, "YellowSpringClips_%d" % chunk, clip, clips, 0)
		DetailBatch.batch(_sleeper_root, "PolishedRailHeads_%d" % chunk, cap, heads, 0)
	_build_slab_joints(samples)


func _clip_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var points: Array[Vector3] = []
		for i in range(17):
			var a := float(i) / 16.0 * PI * 1.7
			points.append(Vector3(float(side) * (0.115 + 0.043 * sin(a)), 0.025 + 0.026 * sin(a * 0.58), 0.077 * cos(a)))
		for i in range(points.size() - 1):
			var axis := (points[i + 1] - points[i]).normalized()
			var u := axis.cross(Vector3.UP).normalized()
			var v := axis.cross(u).normalized()
			for j in range(6):
				var a := TAU * j / 6.0
				var b := TAU * (j + 1) / 6.0
				var n1 := u * cos(a) + v * sin(a)
				var n2 := u * cos(b) + v * sin(b)
				var verts := [points[i] + n1 * 0.009, points[i + 1] + n1 * 0.009, points[i] + n2 * 0.009, points[i] + n2 * 0.009, points[i + 1] + n1 * 0.009, points[i + 1] + n2 * 0.009]
				for vertex in verts:
					surface.add_vertex(vertex)
	surface.generate_normals()
	surface.set_material(_create_material("", Color("e4b83d"), 0.3, 0.5))
	return surface.commit()


func _concrete() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = 41
	noise.frequency = 0.16
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color("8b8c85"))
	ramp.set_color(1, Color("c3c4bc"))
	texture.color_ramp = ramp
	var material := _create_material("", Color.WHITE, 0, 0.96)
	material.albedo_texture = texture
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 2.0
	return material
