extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var train = load("res://train_visual.gd").new()
	world.add_child(train)
	assert(train.ready_for_preview)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(24, 12, -30)
	camera.look_at(Vector3(0, 1.8, 0))
	camera.near = 0.5
	camera.far = 20000.0
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.5
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.22, 0.28)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://train-diagnostic.png")
	print("TRAIN_VISUAL_CAPTURE_PASS")
	quit()
