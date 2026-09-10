extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("_test")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _test() -> void:
	var scene = load("res://offline.tscn").instantiate()
	root.add_child(scene)
	while not scene.ready_for_trip and not scene.failed:
		await process_frame
	scene.set_process(false)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var blocked: Array[float] = []
	var adjusted := 0
	var partial := 0
	var checked := 0
	for step in range(0, int(scene.distances[-1]) + 11, 10):
		var distance: float = minf(step, scene.distances[-1])
		scene.mileage = distance
		var previous: Vector3 = scene.camera.position
		scene._update_position(1.0 / 60.0)
		checked += 1
		if scene.camera_guard.blocked:
			blocked.append(distance)
			_check(scene.camera.position.is_equal_approx(previous), "Blocked camera moved into unverified location")
		else:
			var spacing: float = scene.train.CAR_CENTER_SPACING_M
			var front := float(scene.train.CONSIST_CAR_COUNT - 1) * 0.5 * spacing
			var targets := PackedVector3Array()
			for index in range(scene.train.CONSIST_CAR_COUNT):
				targets.append(scene.sample(distance + front - spacing * float(index)) + Vector3.UP * 3)
			var visible: PackedVector3Array = scene.camera_guard.visible_targets(space, scene.camera.position, targets)
			_check(visible.size() >= 2, "Camera lacks a clear consist view at " + str(distance))
			_check(scene.camera_guard.point_clear(space, scene.camera.position),
				"Camera overlaps a building")
			if scene.camera_guard.adjusted:
				adjusted += 1
			if scene.camera_guard.partial_view:
				partial += 1
	# Drive into each transition to a fully obstructed station/canopy and verify
	# that production _process restores the train mileage and pauses.
	var stop_checks := 0
	for distance in blocked:
		if distance < 10 or blocked.has(distance - 10) or is_equal_approx(distance, scene.distances[-1]):
			continue
		scene.mileage = distance - 10
		scene.paused = true
		scene._update_position()
		var old_distance: float = scene.mileage
		scene.paused = false
		scene._process(10.0 / scene.SPEED)
		_check(scene.paused and is_equal_approx(scene.mileage, old_distance), "Unsafe advance was not rolled back")
		stop_checks += 1
	var result := {
		"pass": failures == 0, "positions_every_m": 10, "checked_positions": checked,
		"adjusted_positions": adjusted, "partial_consist_positions": partial,
		"fully_obstructed_positions_m": blocked, "stop_checks": stop_checks,
		"collision_meshes": scene.camera_guard.collision_meshes,
		"max_query_ms": scene.camera_guard.max_query_ms,
		"max_collider_build_ms": scene.camera_guard.max_collider_build_ms,
		"note": "Safety pass, not uninterrupted-route pass. Fully occluded train causes a pause."
	}
	var file := FileAccess.open("res://tests/camera-safety-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("CAMERA_ROUTE_SAFETY ", "PASS" if failures == 0 else "FAIL", " checked=", checked,
		" adjusted=", adjusted, " partial=", partial, " blocked=", blocked.size(),
		" stop_checks=", stop_checks, " query_max_ms=", scene.camera_guard.max_query_ms)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
