extends RefCounted
## Geometric alignment only: no wheel/rail contact or suspension solver.

static func measure(point: Vector3, route: PackedVector3Array) -> Dictionary:
	var best_squared := INF
	var result: Dictionary = {}
	for index in range(route.size() - 1):
		var start := route[index]
		var segment := route[index + 1] - start
		var flat := Vector3(segment.x, 0.0, segment.z)
		if flat.length_squared() < 0.000001:
			continue
		var weight := clampf((point - start).dot(flat) / flat.length_squared(), 0.0, 1.0)
		var center := start + segment * weight
		var difference := point - center
		var squared := Vector2(difference.x, difference.z).length_squared()
		if squared < best_squared:
			best_squared = squared
			var forward := flat.normalized()
			var right := forward.cross(Vector3.UP).normalized()
			result = {"center": center, "forward": forward, "right": right,
				"lateral_mm": difference.dot(right) * 1000.0}
	return result
