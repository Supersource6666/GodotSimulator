extends SceneTree
## Rendering benchmark: use a graphical renderer, never --headless.
var scene

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/ballasted_track/scene.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene._set_input_source("keyboard")
	var sun := scene.get_node("Sunlight") as DirectionalLight3D
	var sun_shadows := sun.shadow_enabled
	var ballast: Array[Node] = []
	for child in scene.get_children():
		if String(child.name).begins_with("RouteBallast_"):
			ballast.append(child)
	for mode in ["baseline", "no_shadows", "no_ballast", "no_train", "no_ui"]:
		print("RENDER_PROFILE_START ", mode)
		sun.shadow_enabled = sun_shadows and mode != "no_shadows"
		for node in ballast:
			node.visible = mode != "no_ballast"
		scene.get_node("Train").visible = mode != "no_train"
		scene.get_node("SceneInterface").visible = mode != "no_ui"
		scene._keyboard_driver.mileage_m = scene.route_profile.first_mileage_m + 50.0
		scene._keyboard_driver.speed_mps = 154.0 / 3.6
		var samples: Array[float] = []
		var update_ms := 0.0
		var calls := 0.0
		var primitives := 0.0
		var previous := Time.get_ticks_usec()
		for i in range(30):
			var start := Time.get_ticks_usec()
			scene._step_keyboard_control(1.0 / 60.0, false, false)
			var duration := Time.get_ticks_usec() - start
			await process_frame
			var now := Time.get_ticks_usec()
			if i >= 5:
				samples.append(float(now - previous) / 1000.0)
				update_ms += float(duration) / 1000.0
				calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			previous = now
		var total := 0.0
		for sample in samples:
			total += sample
		samples.sort()
		print("RENDER_PROFILE ", mode, " avg_ms=", total / samples.size(),
			" p95_ms=", samples[int(samples.size() * 0.95)], " update_ms=", update_ms / samples.size(),
			" draw_calls=", calls / samples.size(), " primitives=", primitives / samples.size())
	scene.queue_free()
	await process_frame
	await process_frame
	quit()
