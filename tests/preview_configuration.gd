extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var preview = load("res://journey.gd").new()
	root.add_child(preview)
	await process_frame
	await process_frame
	preview.set_process(false)
	assert(preview.ROUTE_POINTS.size() > 100)
	assert(preview._total_route_distance > 6500.0 and preview._total_route_distance < 7000.0)
	assert(preview._train.ready_for_preview)
	assert(preview._train.wheels.size() == 4)
	assert(preview._route_camera.far <= 20000.0)
	assert(preview._tileset.forbid_holes)
	if preview._use_cesium_ion:
		assert(preview._tileset.ion_asset_id == (2275207 if preview._photorealistic else 1))
		assert((preview._buildings_tileset == null) == preview._photorealistic)
	var test_distances: Array[float] = [0.0, 2500.0, preview._total_route_distance]
	for step in range(1, int(preview._total_route_distance / 25.0)):
		test_distances.append(step * 25.0)
	for distance in test_distances:
		preview._update_route_position(distance)
		var geo = preview._route_georeference
		var actual_ecef := Vector3(geo.ecefX, geo.ecefY, geo.ecefZ)
		var sample = preview._sample_route(distance)
		var surface: Vector3 = preview._cartographic_to_ecef(sample.lat, sample.lon, preview._rail_height)
		assert(actual_ecef.distance_to(surface) > 100.0 and actual_ecef.distance_to(surface) < 115.0)
		assert(preview._route_camera.global_position.is_zero_approx())
		assert(absf(preview._route_camera.global_basis.determinant() - 1.0) < 0.001)
		var projected: Vector2 = preview._route_camera.unproject_position(preview._train.global_position)
		assert(not preview._route_camera.is_position_behind(preview._train.global_position))
		assert(root.get_visible_rect().has_point(projected))
		var basis: Basis = preview._route_georeference.get_initial_tx_ecef_to_engine().basis
		var train_ecef: Vector3 = actual_ecef + basis.inverse() * preview._train.global_position
		assert(train_ecef.distance_to(surface) < 1.5)
	var last = preview._sample_route(preview._total_route_distance + 1000.0)
	assert(is_equal_approx(float(last.lat), float(preview.ROUTE_POINTS[-1].lat)))
	assert(is_equal_approx(float(last.lon), float(preview.ROUTE_POINTS[-1].lon)))
	# Nodes alone must not count as a ready view. A textured surface in front
	# of the camera must count, while hidden/untextured/out-of-view meshes do not.
	assert(preview._measure_view_coverage() == 0)
	var test_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40.0, 40.0, 1.0)
	var mat := StandardMaterial3D.new()
	var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	mat.albedo_texture = ImageTexture.create_from_image(pixels)
	box.material = mat
	test_mesh.mesh = box
	test_mesh.set_meta("preview_geometric_error", 8.025475)
	preview._tileset.add_child(test_mesh)
	test_mesh.global_transform = preview._route_camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, -10))
	assert(preview._measure_view_coverage() == 9)
	preview._triangle_cache.clear()
	assert(preview._measure_view_coverage(false) == 0, "Cold acceleration structures must not release the train")
	while not preview._triangle_queue.is_empty():
		preview._prepare_triangle_cache()
	assert(preview._measure_view_coverage(false) == 9)
	box.size = Vector3(41.0, 41.0, 1.0)
	assert(preview._measure_view_coverage(false) == 0, "Changed mesh must invalidate acceleration data")
	while not preview._triangle_queue.is_empty():
		preview._prepare_triangle_cache()
	assert(preview._measure_view_coverage(false) == 9)
	var occluder := MeshInstance3D.new()
	occluder.mesh = box
	occluder.set_meta("preview_geometric_error", 64.203801)
	preview._tileset.add_child(occluder)
	occluder.global_transform = preview._route_camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, -5))
	if preview._photorealistic and preview._use_cesium_ion:
		assert(preview._measure_view_coverage() == 0, "Coarse foreground must block fine background")
	occluder.layers = 0
	assert(preview._measure_view_coverage() == 9)
	occluder.queue_free()
	test_mesh.set_meta("preview_geometric_error", 64.203801)
	if preview._photorealistic and preview._use_cesium_ion:
		assert(preview._measure_view_coverage() == 0)
		test_mesh.remove_meta("preview_geometric_error")
		assert(preview._measure_view_coverage() == 0)
	test_mesh.set_meta("preview_geometric_error", 8.025475)
	test_mesh.hide()
	assert(preview._measure_view_coverage() == 0)
	test_mesh.show()
	mat.albedo_texture = null
	assert(preview._measure_view_coverage() == 0)
	test_mesh.queue_free()
	preview._journey_started = true
	preview._paused = false
	preview._route_preloading = false
	preview._journey_distance = 2000.0
	preview._next_preload_distance = 100000.0
	preview._view_check_elapsed = 0.0
	preview._view_coverage = 6
	preview._process(0.1)
	assert(preview._journey_distance == 2000.0)
	preview._view_coverage = 7
	preview._process(0.1)
	assert(preview._journey_distance > 2000.0)
	print("PREVIEW_CONFIGURATION_PASS: connected track, train assembly, follow camera, endpoint and textured view coverage")
	quit()
