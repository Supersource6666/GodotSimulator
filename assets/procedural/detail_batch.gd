extends RefCounted
## Shared lightweight geometry, spatially bounded batches (no network/assets).

static func batch(parent: Node3D, title: String, mesh: Mesh, poses: Array[Transform3D], distance: float) -> MultiMeshInstance3D:
	if poses.is_empty():
		return null
	var origin := poses[0].origin
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.mesh = mesh
	data.instance_count = poses.size()
	for index in poses.size():
		var pose := poses[index]
		pose.origin -= origin
		data.set_instance_transform(index, pose)
	var instance := MultiMeshInstance3D.new()
	instance.name = title
	instance.multimesh = data
	instance.position = origin
	instance.visibility_range_end = distance
	instance.visibility_range_end_margin = 80.0
	parent.add_child(instance)
	return instance

static func beam(from: Vector3, to: Vector3, width: float, depth: float = -1.0) -> Transform3D:
	var delta := to - from
	var up := delta.normalized()
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var right := reference.cross(up).normalized()
	var basis := Basis(right * width, up * delta.length(), right.cross(up) * (width if depth < 0 else depth))
	return Transform3D(basis, (from + to) * 0.5)
