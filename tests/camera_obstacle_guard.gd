extends SceneTree
const Guard = preload("res://camera_obstacle_guard.gd")
var world: Node3D
var obstacles: Array[Node3D] = []
var failures := 0

func _initialize() -> void:
	call_deferred("_test")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _route(distance: float) -> Vector3:
	return Vector3(0, 0, -distance)

func _box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Guard.BUILDING_LAYER
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	body.position = position
	obstacles.append(body)

func _sync() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _clear() -> void:
	for obstacle in obstacles:
		obstacle.free()
	obstacles.clear()
	await _sync()

func _test() -> void:
	world = Node3D.new()
	root.add_child(world)
	await _sync()
	var space := world.get_world_3d().direct_space_state
	var side_guard = Guard.new()
	var side_targets := PackedVector3Array([Vector3(0, 3, 0)])
	var side_position: Vector3 = side_guard.resolve(space, _route, 0, side_targets, Vector3.ZERO, 0, 100, 24, 22)
	_check(side_position.is_equal_approx(Vector3(22, 24, -100)), "Front-side camera should follow route with lateral offset")
	_box(Vector3(22, 24, -100), Vector3(8, 20, 8))
	await _sync()
	side_position = side_guard.resolve(space, _route, 0, side_targets, Vector3.ZERO, 0, 100, 24, 22)
	_check(side_position.x < 22 and side_guard.clear_view(space, side_position, side_targets), "Blocked side camera must retract to clear corridor")
	await _clear()
	var guard = Guard.new()
	var targets := PackedVector3Array([Vector3(0, 3, 0)])
	var expected := Vector3(0, 40, -100)
	var result: Vector3 = guard.resolve(space, _route, 0, targets, Vector3.ZERO, 0)
	_check(result.is_equal_approx(expected), "Clear route must use 100 m / 40 m")
	_box(Vector3(0, 35, -90), Vector3(20, 70, 8))
	await _sync()
	result = guard.resolve(space, _route, 0, targets, expected, 0)
	_check(is_equal_approx(result.y, 40.0) and result.z > -90, "Must shorten before raising")
	_check(guard.clear_view(space, result, targets), "Shortened view must be clear")
	await _clear()
	for distance in [100.0, 75.0, 50.0, 30.0, 0.0]:
		_box(Vector3(0, 40, -distance), Vector3(4, 4, 4))
	await _sync()
	result = guard.resolve(space, _route, 0, targets, expected, 0)
	_check(result.y > 40 and not guard.blocked, "Blocked 40 m candidates must raise camera")
	_check(guard.clear_view(space, result, targets), "Raised camera must have clear sightline")
	await _clear()
	_box(Vector3(0, 40, 0), Vector3(2, 10, 20))
	await _sync()
	_check(not guard.clear_motion(space, Vector3(-10, 40, 0), Vector3(10, 40, 0)),
		"Camera sweep must detect a wall between clear endpoints")
	await _clear()
	# A real rendered mesh must also register, not only primitive test bodies.
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(20, 70, 8)
	mesh.mesh = cube
	holder.add_child(mesh)
	world.add_child(holder)
	holder.position = Vector3(0, 35, -90)
	guard.add_buildings(holder)
	obstacles.append(holder)
	await _sync()
	_check(guard.collision_meshes == 1, "Building collision mesh not registered")
	_check(not guard.clear_view(space, expected, targets), "Trimesh must obstruct view")
	result = guard.resolve(space, _route, 0, targets, expected, 0)
	_check(result.z > -90 and is_equal_approx(result.y, 40), "Trimesh avoidance failed")
	await _clear()
	# A solid enclosure around target admits no valid view: preserve camera.
	_box(Vector3(0, 3, 0), Vector3(20, 20, 20))
	await _sync()
	result = guard.resolve(space, _route, 0, targets, expected, 0)
	_check(guard.blocked and result.is_equal_approx(expected), "No safe candidate must fail closed")
	await _clear()
	var enclosure := Node3D.new()
	var enclosure_mesh := MeshInstance3D.new()
	var enclosure_box := BoxMesh.new()
	enclosure_box.size = Vector3(300, 200, 300)
	enclosure_mesh.mesh = enclosure_box
	enclosure.add_child(enclosure_mesh)
	world.add_child(enclosure)
	enclosure.position = Vector3(0, 60, -50)
	guard.add_buildings(enclosure)
	obstacles.append(enclosure)
	await _sync()
	_check(not guard.clear_view(space, expected, targets), "Camera wholly inside a hollow building must be rejected")
	await _clear()
	var curve := func(distance: float) -> Vector3:
		return Vector3(distance * 0.5, 0, -distance * 0.5)
	result = guard.resolve(space, curve, 0, targets, expected, 0)
	_check(result.is_equal_approx(Vector3(50, 40, -50)), "Camera must sample curved route, not tangent")
	world.free()
	print("CAMERA_GUARD_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
