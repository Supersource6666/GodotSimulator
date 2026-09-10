extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var preview = load("res://journey.gd").new()
	root.add_child(preview)
	await process_frame
	await process_frame
	preview.set_process(false)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file("res://tile_diagnostic/original.glb", state) == OK)
	var imported := document.generate_scene(state)
	var source: Mesh = imported.find_children("*", "MeshInstance3D", true, false)[0].mesh
	for index in range(48):
		var instance := MeshInstance3D.new()
		instance.mesh = source.duplicate()
		instance.set_meta("preview_geometric_error", 8.0)
		preview._tileset.add_child(instance)
		var center := instance.get_aabb().get_center()
		instance.global_transform = preview._route_camera.global_transform * Transform3D(Basis.IDENTITY, -center + Vector3(0, 0, -250 - index))
	var measurements: Array[float] = []
	var first_start := Time.get_ticks_usec()
	assert(preview._measure_view_coverage(false) == 0)
	var cold_probe_ms := (Time.get_ticks_usec() - first_start) / 1000.0
	var slices: Array[float] = []
	while not preview._triangle_queue.is_empty():
		var start := Time.get_ticks_usec()
		preview._prepare_triangle_cache()
		slices.append((Time.get_ticks_usec() - start) / 1000.0)
	slices.sort()
	for iteration in range(12):
		var start := Time.get_ticks_usec()
		preview._measure_view_coverage(false)
		measurements.append((Time.get_ticks_usec() - start) / 1000.0)
	var cold: float = measurements.pop_front()
	measurements.sort()
	print("COVERAGE_BENCHMARK ", JSON.stringify({"tiles":48,"cold_probe_ms":cold_probe_ms,"max_build_slice_ms":slices[-1],"median_build_slice_ms":slices[slices.size()/2],"warm_first_ms":cold,"warm_median_ms":measurements[5],"warm_max_ms":measurements[-1]}))
	imported.free()
	quit()
