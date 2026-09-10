extends SceneTree

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var train = load("res://train_visual.gd").new()
	root.add_child(train)
	var modified := 0
	var preserved := 0
	for path in [train.HEAD_MODEL_PATH, train.MIDDLE_MODEL_PATH]:
		var template: Node3D = train._model_templates[path]
		for node in template.find_children("*", "MeshInstance3D", true, false):
			for surface in node.mesh.get_surface_count():
				var original: BaseMaterial3D = node.mesh.surface_get_material(surface)
				var override: BaseMaterial3D = node.get_surface_override_material(surface)
				if override != null:
					assert(override != original)
					assert(override.roughness >= 0.179 and override.roughness <= 0.851)
					assert(override.metallic == 0.0)
					if override.clearcoat_enabled:
						assert(override.albedo_color.is_equal_approx(Color(0.78, 0.78, 0.78)))
						assert(is_equal_approx(override.roughness, 0.42))
					assert(override.albedo_color.a == 1.0)
					assert(override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
					assert(not override.refraction_enabled)
					modified += 1
				else:
					preserved += 1
	assert(modified > 0)
	for path in [train.BOGIE_MODEL_PATH, train.WHEEL_MODEL_PATH]:
		for node in train._model_templates[path].find_children("*", "MeshInstance3D", true, false):
			for surface in node.mesh.get_surface_count():
				assert(node.get_surface_override_material(surface) == null)
	assert(train.cars.size() == 4 and train.wheels.size() == 16)
	var head: Node3D = train.cars[0].get_child(0)
	var tail: Node3D = train.cars[3].get_child(0)
	assert(head.get_meta("model_path") == train.HEAD_MODEL_PATH)
	assert(tail.get_meta("model_path") == train.HEAD_MODEL_PATH)
	assert(head.basis.z.normalized().dot(tail.basis.z.normalized()) < -0.999)
	for index in [1, 2]:
		assert(train.cars[index].get_child(0).get_meta("model_path") == train.MIDDLE_MODEL_PATH)
	for car in train.cars:
		var body: Node3D = car.get_child(0)
		assert(absf(train.visual_bounds(body, car).position.y - 0.55) < 0.001)
		assert(absf(train.visual_bounds(body, car).get_center().z) < 0.001)
	print("TRAIN_MATERIALS_PASS softened=", modified, " preserved=", preserved, " cars=4 wheels=16")
	# Detached template nodes are owned by the current model cache.
	var templates: Array = train._model_templates.values()
	train.free()
	for template in templates:
		assert(not is_instance_valid(template))
	quit(0)
