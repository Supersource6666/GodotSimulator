extends SceneTree
## Run with --headless --script res://scenes/ballasted_track/test_keyboard_control.gd
## -- --stream-smoke-test --dispatch=ballasted_track
const Driver = preload("res://scenes/ballasted_track/keyboard_train_driver.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var driver := Driver.new()
	check(is_equal_approx(driver.speed_mps * 3.6, 154.0), "Initial speed is 154 km/h")
	check(is_equal_approx(driver.maximum_speed_mps * 3.6, 160.0), "Keyboard limit is 160 km/h")
	driver.advance(1.0, true, false)
	check(is_equal_approx(driver.speed_mps * 3.6, 160.0), "W caps initial motion at 160 km/h")
	driver.speed_mps = 0.0
	driver.mileage_m = 0.0
	for i in range(60):
		driver.advance(1.0 / 60.0, true, false)
	check(absf(driver.speed_mps - 15.0) < 0.0001, "W accelerates from rest")
	check(absf(driver.mileage_m - 7.5) < 0.0001, "Acceleration distance")
	driver.advance(1.0, false, false)
	check(driver.speed_mps < 15.0 and driver.speed_mps > 14.9, "Release coasts")
	var before := driver.speed_mps
	driver.advance(1.0, true, true)
	check(driver.speed_mps < before, "S has priority over W")
	driver.advance(100.0, false, true)
	check(driver.speed_mps == 0.0, "Braking stops without reversing")
	var stopped_at := driver.mileage_m
	driver.advance(1.0, false, true)
	check(driver.mileage_m == stopped_at, "Stopped train stays stopped")
	driver.advance(1000.0, true, false)
	check(is_equal_approx(driver.speed_mps, driver.maximum_speed_mps), "Speed limit")
	driver.end_mileage_m = driver.mileage_m + 1.0
	driver.advance(1.0, true, false)
	check(driver.mileage_m == driver.end_mileage_m and driver.speed_mps == 0.0, "Route end stop")

	var dispatch = load("res://app/dispatch/dispatch_console.tscn").instantiate()
	root.add_child(dispatch)
	check(dispatch._input_source_option != null, "Dispatch input selector exists")
	dispatch._input_source_option.select(1)
	dispatch._read_plan_from_ui()
	check(dispatch._plan.get("input_source") == "keyboard", "Dispatch stores keyboard selection")
	var context := root.get_node("DispatchContext")
	context._plan = dispatch._plan.duplicate(true)
	dispatch._write_plan_to_ui()
	check(dispatch._input_source_option.selected == 1, "Dispatch restores keyboard selection")
	dispatch._on_reset()
	check(dispatch._input_source_option.selected == 0, "Dispatch reset defaults to UDP")
	dispatch.queue_free()
	await process_frame

	var scene = load("res://scenes/ballasted_track/scene.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.simulation_stream.set_process(false)
	check(scene._input_source == "keyboard", "Scene receives dispatch input source")
	check(is_equal_approx(scene._keyboard_driver.speed_mps * 3.6, 154.0), "Scene starts keyboard at 154 km/h")
	check(is_equal_approx(scene._keyboard_driver.maximum_speed_mps * 3.6, 160.0), "Dispatch does not override keyboard cap")
	if scene._source_option == null:
		var layer := CanvasLayer.new()
		layer.name = "SceneInterface"
		scene.add_child(layer)
		scene._setup_speed_panel()
		scene._setup_input_controls()
	check(scene._source_option.selected == 1, "Runtime selector matches dispatch")
	var initial_mileage: float = scene._display_mileage_m
	for i in range(60):
		scene._step_keyboard_control(1.0 / 60.0, true, false)
	check(scene._display_mileage_m > initial_mileage, "Keyboard advances route mileage")
	var lead := scene.get_node("Train/LeadCar") as Node3D
	var expected: Transform3D = scene.route_profile.pose_at_mileage(scene._display_mileage_m, scene.TRAIN_TRACK_CENTER, scene.CAR_BASE_HEIGHT_M)
	check(lead.global_position.distance_to(expected.origin) < 0.001, "Keyboard moves actual train")
	check(lead._wheel_speed_mps > 0.0, "Keyboard drives wheel speed")
	check(not scene._speed_chart._samples.is_empty(), "Keyboard updates speed plot")

	if "--capture-control-test" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var capture_error := root.get_texture().get_image().save_png("res://.godot/keyboard-control-test.png")
		check(capture_error == OK, "Save control console screenshot")

	var keyboard_wheel_speed: float = lead._wheel_speed_mps
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", 49000)
	var packet := {"schema": "railway_ltd.v1", "type": "state", "seq": 5, "t": 1.0, "mileage_m": initial_mileage + 200.0, "speed_m_s": 15.0}
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await create_timer(0.05).timeout
	scene.simulation_stream._process(0.0)
	check(not scene._has_stream_state and scene.simulation_stream.last_state.is_empty(), "Keyboard discards UDP")
	check(is_equal_approx(lead._wheel_speed_mps, keyboard_wheel_speed), "UDP cannot override keyboard wheels")
	var retained: float = scene._display_mileage_m
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await create_timer(0.05).timeout
	scene._source_option.item_selected.emit(0)
	scene.simulation_stream._process(0.0)
	check(scene._input_source == "udp" and not scene._has_stream_state, "Runtime selector switches to waiting UDP")
	check(scene._display_mileage_m == retained and lead._wheel_speed_mps == 0.0, "Switch preserves mileage and clears wheel speed")
	packet.seq = 0
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await create_timer(0.05).timeout
	scene.simulation_stream._process(0.0)
	check(scene._has_stream_state and scene.simulation_stream.last_state.seq == 0, "Restarted UDP sequence accepted")
	scene._process(0.0)
	check(scene._display_mileage_m >= packet.mileage_m, "UDP resumes route control")
	retained = scene._display_mileage_m
	var body := lead.get_node("ModelMount") as Node3D
	var base_pose := body.transform
	body.position += Vector3(0.1, 0.2, 0.0)
	scene._source_option.item_selected.emit(1)
	check(body.transform.is_equal_approx(base_pose), "Switch clears previous UDP body displacement")
	check(scene._keyboard_driver.mileage_m == retained and scene._keyboard_driver.speed_mps == 15.0, "Keyboard takes over current UDP speed and mileage")
	for i in range(1200):
		scene._step_keyboard_control(1.0 / 60.0, false, true)
	check(scene._keyboard_driver.speed_mps == 0.0 and lead._wheel_speed_mps == 0.0, "S stops actual train")
	sender.close()
	scene.queue_free()
	await process_frame
	await process_frame
	print("BALLASTED_KEYBOARD_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
