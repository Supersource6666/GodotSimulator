extends RefCounted
## Native physics BVH queries only. Building trimeshes are created once on load,
## never rebuilt or scanned in GDScript while the train is moving.
const BUILDING_LAYER := 1 << 20
const CLEARANCE_M := 1.5
var blocked := false
var adjusted := false
var query_count := 0
var collision_meshes := 0
var max_collider_build_ms := 0.0
var max_query_ms := 0.0
var initialized := false
var partial_view := false
var aim_target := Vector3.ZERO
var sphere := SphereShape3D.new()

func _init() -> void:
	sphere.radius = CLEARANCE_M

func add_buildings(instance: Node) -> void:
	var start := Time.get_ticks_usec()
	for mesh in instance.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var shape: ConcavePolygonShape3D = mesh.mesh.create_trimesh_shape()
		if shape == null:
			continue
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.name = "CameraBuildingObstacle"
		body.collision_layer = BUILDING_LAYER
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		mesh.add_child(body)
		collision_meshes += 1
	max_collider_build_ms = maxf(max_collider_build_ms, (Time.get_ticks_usec() - start) / 1000.0)

func _shape_query(position: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = BUILDING_LAYER
	query.margin = 0.1
	return query

func clear_view(space: PhysicsDirectSpaceState3D, position: Vector3, targets: PackedVector3Array) -> bool:
	return visible_targets(space, position, targets).size() == targets.size()

func point_clear(space: PhysicsDirectSpaceState3D, position: Vector3) -> bool:
	query_count += 1
	if not space.intersect_shape(_shape_query(position), 1).is_empty():
		return false
	# Concave trimeshes are hollow: a sphere wholly inside a building does not
	# intersect its walls. A first upward back-face without a matching front-face
	# indicates an interior/underside; conservatively reject that viewpoint.
	var ray := PhysicsRayQueryParameters3D.create(position, position + Vector3.UP * 10000, BUILDING_LAYER)
	ray.hit_back_faces = true
	query_count += 1
	var two_sided := space.intersect_ray(ray)
	if two_sided.is_empty():
		return true
	ray.hit_back_faces = false
	query_count += 1
	var front := space.intersect_ray(ray)
	return not front.is_empty() and (front.position as Vector3).distance_squared_to(two_sided.position) < 0.0001

func visible_targets(space: PhysicsDirectSpaceState3D, position: Vector3, targets: PackedVector3Array) -> PackedVector3Array:
	var visible := PackedVector3Array()
	if not point_clear(space, position):
		return visible
	for target in targets:
		var ray := PhysicsRayQueryParameters3D.create(position, target, BUILDING_LAYER)
		ray.hit_back_faces = true
		ray.hit_from_inside = true
		query_count += 1
		if space.intersect_ray(ray).is_empty():
			visible.append(target)
	return visible

func clear_motion(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	if from.is_equal_approx(to):
		return true
	var query := _shape_query(from)
	query.motion = to - from
	query_count += 1
	var fractions := space.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.99999

func resolve(space: PhysicsDirectSpaceState3D, route_sampler: Callable, mileage: float,
		targets: PackedVector3Array, previous: Vector3, delta: float,
		forward_m: float = 100.0, height_m: float = 40.0, side_m: float = 0.0) -> Vector3:
	var start := Time.get_ticks_usec()
	blocked = false
	adjusted = false
	partial_view = false
	query_count = 0
	var candidate := Vector3.ZERO
	var found := false
	var visible := PackedVector3Array()
	var required_count := targets.size()
	# Prefer closing the gap at the requested 40 m height before raising it.
	# Sample actual chainage: never project the tangent into buildings on bends.
	# Prefer seeing the full consist. A station canopy/overpass may physically
	# cover a car; in that case keep at least half the actual car centers visible
	# and aim at a visible car. Do not hide buildings or move through them.
	for required in [targets.size(), maxi(1, ceili(targets.size() * 0.5))]:
		required_count = required
		for height in [height_m, height_m + 15.0, height_m + 35.0, height_m + 60.0, height_m + 100.0, height_m + 160.0, height_m + 240.0]:
			for distance in [forward_m, forward_m * 0.75, forward_m * 0.5, forward_m * 0.3, 0.0]:
				var ground: Vector3 = route_sampler.call(mileage + distance)
				var tangent: Vector3 = route_sampler.call(mileage + distance + 1.0) - route_sampler.call(mileage + distance - 1.0)
				var right := tangent.cross(Vector3.UP).normalized()
				var offsets := [side_m, side_m * 0.5, 0.0] if side_m != 0.0 else [0.0]
				for offset in offsets:
					var position: Vector3 = ground + Vector3.UP * float(height) + right * float(offset)
					visible = visible_targets(space, position, targets)
					if visible.size() >= required_count:
						candidate = position
						found = true
						adjusted = distance != forward_m or height != height_m or offset != side_m
						break
				if found:
					break
			if found:
				break
		if found:
			break
	if not found:
		blocked = true
		max_query_ms = maxf(max_query_ms, (Time.get_ticks_usec() - start) / 1000.0)
		return previous
	if initialized and delta > 0.0:
		var smooth := previous.lerp(candidate, 1.0 - exp(-8.0 * delta))
		var smooth_visible := visible_targets(space, smooth, targets)
		if smooth_visible.size() >= required_count and clear_motion(space, previous, smooth):
			candidate = smooth
			visible = smooth_visible
		# If smoothing would cross a wall, cut directly to a verified clear
		# viewpoint. Do not animate through the obstacle to hide a collision.
	initialized = true
	partial_view = visible.size() < targets.size()
	var center := Vector3.ZERO
	for target in targets:
		center += target
	center /= max(1, targets.size())
	aim_target = visible[0]
	for target in visible:
		if target.distance_squared_to(center) < aim_target.distance_squared_to(center):
			aim_target = target
	max_query_ms = maxf(max_query_ms, (Time.get_ticks_usec() - start) / 1000.0)
	return candidate
