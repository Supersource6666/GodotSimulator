extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_test")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func pose(distance: float, offset: float = 0.0) -> Dictionary:
	var angle := distance / 500.0
	var forward := Vector3(sin(angle), 0, -cos(angle))
	return {"point": Vector3(500 * (1 - cos(angle)), offset, -500 * sin(angle)),
		"forward": forward, "right": forward.cross(Vector3.UP), "up": Vector3.UP, "distance": distance}

func _test() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a real rendering backend: headless MultiMesh readback is unavailable.")
		quit(1)
		return
	var track = load("res://assets/procedural/track_generator.gd").new()
	track.ballastless = false # Retain legacy mode coverage.
	root.add_child(track)
	var samples: Array[Dictionary] = []
	for distance in range(0, 1001, 5):
		samples.append(pose(distance))
	track.set_custom_samples(samples)
	var shifted: Array[Dictionary] = track.offset_samples(samples, -4.2)
	for index in samples.size():
		var difference: Vector3 = shifted[index].point - samples[index].point
		check(absf(difference.length() - 4.2) < 0.0001, "Parallel track center spacing")
		check(absf(difference.dot(samples[index].forward)) < 0.0001, "Parallel offset follows curve")
		check(shifted[index].point.y == samples[index].point.y, "Parallel rail height")
	var parallel = load("res://assets/procedural/track_generator.gd").new()
	root.add_child(parallel)
	parallel.set_custom_samples(shifted)
	parallel.generate_track_mesh()
	check(parallel.mesh.get_surface_count() == 3, "Parallel track needs bed and two rails")
	check(parallel.sleeper_instance_count == 3078, "Two independent rail seats per station")
	var seats: MultiMeshInstance3D = parallel._sleeper_root.get_child(0)
	check(seats.multimesh.mesh.material.albedo_color.is_equal_approx(Color(0.52, 0.51, 0.47)), "Red-box concrete rail-seat color")
	check(is_equal_approx(seats.multimesh.mesh.material.roughness, 1.0), "Reference rail-seat roughness")
	var slab_material: BaseMaterial3D = parallel.mesh.surface_get_material(0)
	check(slab_material.albedo_color.is_equal_approx(Color(0.64, 0.63, 0.58)), "Green-box concrete slab color")
	check(parallel.mesh.surface_get_material(1).albedo_color.is_equal_approx(Color(0.14, 0.19, 0.23)), "Blue-grey steel color")
	check(is_equal_approx(slab_material.roughness, 0.9), "Matte concrete slab roughness")
	check(parallel._sleeper_root.find_children("Fasteners_*", "", false, false).size() == 4, "Fastener batches missing")
	check(parallel._sleeper_root.find_children("SlabJoints_*", "", false, false).size() == 4, "Panel joints missing")
	check(slab_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "Slab retains lighting")
	var bridge = load("res://assets/procedural/bridge_manager.gd").new()
	var concrete: BaseMaterial3D = bridge._make_material(bridge.CONCRETE_COLOR)
	check(concrete.albedo_color.is_equal_approx(Color(0.32, 0.32, 0.32)), "Reference bridge concrete color")
	check(is_equal_approx(concrete.roughness, 0.88) and is_equal_approx(concrete.metallic, 0.01), "Reference bridge concrete PBR")
	bridge.free()
	check(is_equal_approx(seats.multimesh.mesh.size.x, 0.46), "Rail seats must not span the track gauge")
	var seat_a := seats.multimesh.get_instance_transform(0).origin
	var seat_b := seats.multimesh.get_instance_transform(1).origin
	check(absf(seat_a.distance_to(seat_b) - 1.435) < 0.0001, "Rail seats must sit below both rails")
	var slab: PackedVector3Array = parallel.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(absf(slab[2].distance_to(slab[3]) - 3.6) < 0.0001, "Slab must have full-width flat top")
	check(absf(slab[0].y - slab[1].y + 0.12) < 0.0001, "Slab thickness mismatch")
	parallel.free()
	track.generate_track_mesh()
	check(track.sleeper_instance_count == 1539, "Sleeper density must remain 0.65 m")
	check(track._sleeper_root.get_child_count() == 4, "Expected four spatial batches")
	var first: MultiMeshInstance3D = track._sleeper_root.get_child(0)
	var a := first.multimesh.get_instance_transform(0).origin + first.position
	var b := first.multimesh.get_instance_transform(1).origin + first.position
	check(absf(a.distance_to(b) - 0.65) < 0.001, "Sleeper spacing mismatch")
	check(absf(a.y - 0.17) < 0.0001, "Sleeper height mismatch")
	var rail_vertices: PackedVector3Array = track.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	check(absf(rail_vertices[0].y - 0.22) < 0.0001, "Rail foot must rest on sleepers")
	check(track.mesh.surface_get_material(0).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "Bed must receive lighting")
	track.generate_track_mesh()
	check(track.get_child_count() == 1, "Rebuild must not accumulate sleepers")
	var overhead = load("res://assets/procedural/catenary_generator.gd").new()
	root.add_child(overhead)
	overhead.build(1000.0, pose)
	check(overhead.mast_count == 20 and overhead.wire_segment_count == 300, "Overhead line count mismatch")
	for child in overhead._root.get_children():
		for index in child.multimesh.instance_count:
			var transform: Transform3D = child.multimesh.get_instance_transform(index)
			check(transform.is_finite() and transform.basis.determinant() > 0, "Invalid instance transform")
	for distance in range(1001):
		check(absf(overhead._wire_point(distance, pose, false).y - 6.1) < 0.0001, "Contact wire clearance mismatch")
	overhead.build(1000.0, pose)
	check(overhead.get_child_count() == 1, "Rebuild must not accumulate masts")
	track.free()
	overhead.free()
	if failures == 0:
		print("PROCEDURAL_DETAILS_PASS sleepers=1539 masts=20 wire_segments=300")
	quit(0 if failures == 0 else 1)
