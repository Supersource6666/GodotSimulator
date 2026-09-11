extends SceneTree

class OfflineCabHarness:
	extends "res://offline_journey.gd"

	func _ready() -> void:
		_setup_scene()
		route = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -1000.0)])
		distances = PackedFloat64Array([0.0, 1000.0])
		train = load("res://train_visual.gd").new()
		add_child(train)
		train.set_pose_source(Callable(self, "_route_pose_sample"))
		ready_for_trip = true
		_update_position()
		set_process(false)

func _initialize() -> void:
	call_deferred("_run")

func _lead_shell(train: Node3D) -> Node3D:
	for child in train.cars[0].get_children():
		if child.has_meta("model_path"):
			return child
	return null

func _run() -> void:
	var preview = load("res://journey.gd").new()
	root.add_child(preview)
	await process_frame
	await process_frame
	preview.set_process(false)
	var online_shell := _lead_shell(preview._train)
	assert(online_shell != null and online_shell.visible)
	preview._journey_distance = 1200.0
	preview._set_cab_view(true)
	assert(preview._cab_view and preview._cab_interior.visible)
	assert(is_equal_approx(preview._route_camera.near, 0.08))
	assert(is_equal_approx(preview._route_camera.fov, 64.0))
	assert(not online_shell.visible)
	assert(absf(preview._route_camera.global_basis.determinant() - 1.0) < 0.001)
	var cab_distance := minf(preview._journey_distance + preview.CAB_MILE_OFFSET_METERS, preview._total_route_distance)
	var cab_sample: Dictionary = preview._sample_route(cab_distance)
	var expected_ecef: Vector3 = preview._cartographic_to_ecef(cab_sample.lat, cab_sample.lon,
		preview._rail_height + preview.CAB_EYE_HEIGHT_METERS)
	var actual_ecef := Vector3(preview._route_georeference.ecefX, preview._route_georeference.ecefY,
		preview._route_georeference.ecefZ)
	assert(actual_ecef.distance_to(expected_ecef) < 1.0)
	assert(preview._trip_label.text.contains("驾驶室司机视角"))
	preview._set_cab_view(false)
	assert(not preview._cab_interior.visible and online_shell.visible)
	assert(is_equal_approx(preview._route_camera.near, 0.5))

	var offline := OfflineCabHarness.new()
	root.add_child(offline)
	await process_frame
	var offline_shell := _lead_shell(offline.train)
	assert(offline_shell != null and offline_shell.visible)
	offline._set_cab_view(true)
	assert(offline.cab_view and offline.cab_interior.visible)
	assert(is_equal_approx(offline.camera.position.y, offline.CAB_EYE_HEIGHT_M))
	assert(is_equal_approx(offline.camera.near, 0.08))
	assert(not offline_shell.visible)
	offline._set_cab_view(false)
	assert(not offline.cab_interior.visible and offline_shell.visible)
	preview.free()
	offline.free()
	print("CAB_VIEW_TEST PASS: online/offline toggle, cab pose, interior and lead shell visibility")
	quit(0)