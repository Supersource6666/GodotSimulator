extends RefCounted
## Sample only local terrain, never building roofs. Called once before departure.
const TERRAIN_LAYER := 1 << 21
const RAIL_TOP_M := 0.42 # 0.02 clearance + slab 0.12 + seats 0.10 + rail 0.18
var bodies: Array[StaticBody3D] = []

func add_terrain(instance: Node) -> void:
	for mesh in instance.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var shape: ConcavePolygonShape3D = mesh.mesh.create_trimesh_shape()
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.collision_layer = TERRAIN_LAYER
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		mesh.add_child(body)
		bodies.append(body)

func conform(route: PackedVector3Array, space: PhysicsDirectSpaceState3D) -> PackedVector3Array:
	var result := route.duplicate()
	for i in range(route.size()):
		var forward := route[mini(i + 4, route.size() - 1)] - route[maxi(i - 4, 0)]
		forward.y = 0.0
		var right := forward.normalized().cross(Vector3.UP)
		var ground_y := -INF
		# Cover the single 3.6 m slab edges and the train centreline.
		for offset in [-1.8, 0.0, 1.8]:
			var point := route[i] + right * float(offset)
			var ray := PhysicsRayQueryParameters3D.create(
				Vector3(point.x, 1000.0, point.z), Vector3(point.x, -1000.0, point.z), TERRAIN_LAYER)
			var hit := space.intersect_ray(ray)
			if hit.is_empty():
				push_error("Ground track: missing terrain at route sample %d" % i)
				return PackedVector3Array()
			ground_y = maxf(ground_y, (hit.position as Vector3).y)
		result[i].y = ground_y + RAIL_TOP_M
	print("GROUND_TRACK_READY samples=", result.size(), " terrain_meshes=", bodies.size(), " bridges=0")
	# Terrain queries are no longer needed during travel.
	for body in bodies:
		body.queue_free()
	bodies.clear()
	return result
