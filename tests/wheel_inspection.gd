extends SceneTree

class Harness:
	extends "res://offline_journey.gd"

	func _ready() -> void:
		_setup_scene()
		route = PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -1000)])
		distances = PackedFloat64Array([0.0, 1000.0])
		train = load("res://train_visual.gd").new()
		add_child(train)
		train.set_pose_source(Callable(self, "_route_pose_sample"))
		ready_for_trip = true
		loading_overlay.finish()
		mini_map.hide()
		mileage = 100.0
		_build_offline_corridor()
		_update_position()
		set_process(false)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe := preload("res://wheel_inspection.gd").new()
	var straight := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -100)])
	assert(is_zero_approx(probe.measure(Vector3(0, 0, -50), straight).lateral_mm))
	assert(absf(probe.measure(Vector3(0.012, 0, -50), straight).lateral_mm - 12.0) < 0.001)
	assert(absf(probe.measure(Vector3(-0.007, 2, -50), straight).lateral_mm + 7.0) < 0.001)
	assert(probe.measure(Vector3.ZERO, PackedVector3Array()).is_empty())
	var diagonal := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, -100)])
	var diagonal_right := Vector3(1, 0, 1).normalized()
	assert(absf(probe.measure(Vector3(50, 0, -50) + diagonal_right * 0.01, diagonal).lateral_mm - 10.0) < 0.02)
	var preview := Harness.new()
	root.add_child(preview)
	await process_frame
	var shell: Node3D
	for child in preview.train.cars[0].get_children():
		if child.has_meta("model_path"):
			shell = child
	assert(shell != null and shell.visible)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_5
	preview._unhandled_key_input(key)
	assert(preview.wheel_view and not preview.cab_view)
	assert(not shell.visible and preview.train.wheels[0].is_visible_in_tree())
	assert(not preview.cab_interior.visible and not preview.cab_speedometer.visible)
	assert(preview.wheel_readout.get_parent().visible and preview.wheel_light.visible)
	assert(is_equal_approx(preview.camera.near, 0.03))
	var bottom: Vector3 = preview.train.wheels[0].get_parent().global_position
	assert(preview.camera.is_position_in_frustum(bottom + Vector3.UP * 0.43))
	assert(preview.wheel_readout.text.contains("+0.0 mm"))
	preview._seek_to_progress(50.0)
	var updated: Vector3 = preview.train.wheels[0].get_parent().global_position
	assert(updated.distance_to(bottom) > 300.0)
	assert(preview.camera.is_position_in_frustum(updated + Vector3.UP * 0.43))
	if "--wheel-capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://wheel-preview.png") == OK)
	for index in [0, 1, 2, 3]:
		preview._set_view(4)
		preview._set_view(index)
		assert(not preview.wheel_view)
		assert(not preview.wheel_readout.get_parent().visible and not preview.wheel_light.visible)
		assert(shell.visible == (index != 3))
		assert(preview.cab_view == (index == 3))
	preview._set_view(4)
	key.keycode = KEY_V
	preview._unhandled_key_input(key)
	assert(not preview.wheel_view and shell.visible)
	preview.free()
	print("WHEEL_INSPECTION_TEST PASS: signed offsets, camera framing, seek sync, view transitions")
	quit(0)
