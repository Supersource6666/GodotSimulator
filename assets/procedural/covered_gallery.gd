extends Node3D
## Concrete covered galleries spanning the three levelled ground crossings.
## The floor datum sits below rail top; the 8.5 m clear interior also contains
## the existing catenary without changing train or camera motion.

const DetailBatch := preload("res://assets/procedural/detail_batch.gd")
const SEGMENT_LENGTH_M := 5.0
const INNER_HALF_WIDTH_M := 4.8
const WALL_THICKNESS_M := 0.45
const FLOOR_THICKNESS_M := 0.50
const FLOOR_TOP_BELOW_RAIL_M := 0.42
const CLEAR_HEIGHT_M := 8.5
const ROOF_THICKNESS_M := 0.50
const CONCRETE_COLOR := Color(0.39, 0.40, 0.41)

var segment_count := 0
var _geometry: Node3D


func build(centers: Array, half_length: float, pose_provider: Callable) -> void:
	if is_instance_valid(_geometry):
		_geometry.queue_free()
	_geometry = Node3D.new()
	_geometry.name = "GalleryGeometry"
	add_child(_geometry)
	segment_count = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = CONCRETE_COLOR
	material.roughness = 0.92
	material.metallic = 0.0
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	unit_box.material = material
	var poses: Array[Transform3D] = []
	for center_value in centers:
		var center := float(center_value)
		var start := center - half_length
		var finish := center + half_length
		var distance := start
		while distance < finish - 0.001:
			var next_distance := minf(distance + SEGMENT_LENGTH_M, finish)
			var from_pose: Dictionary = pose_provider.call(distance, 0.0)
			var to_pose: Dictionary = pose_provider.call(next_distance, 0.0)
			_append_segment(poses, from_pose, to_pose)
			segment_count += 1
			distance = next_distance
	DetailBatch.batch(_geometry, "CoveredGalleryBoxes", unit_box, poses, 1800.0)
	print("COVERED_GALLERIES_READY count=", centers.size(), " segments=", segment_count)


func _append_segment(poses: Array[Transform3D], from_pose: Dictionary, to_pose: Dictionary) -> void:
	var from_point: Vector3 = from_pose["point"]
	var to_point: Vector3 = to_pose["point"]
	var delta := to_point - from_point
	var length := delta.length()
	if length <= 0.001:
		return
	var forward := delta / length
	var up := Vector3.UP
	var right := forward.cross(up).normalized()
	if right.length_squared() <= 0.000001:
		right = from_pose["right"]
	var midpoint := (from_point + to_point) * 0.5
	var outer_width := INNER_HALF_WIDTH_M * 2.0 + WALL_THICKNESS_M * 2.0
	var floor_center_y := -FLOOR_TOP_BELOW_RAIL_M - FLOOR_THICKNESS_M * 0.5
	var roof_center_y := CLEAR_HEIGHT_M + ROOF_THICKNESS_M * 0.5
	var wall_bottom := -FLOOR_TOP_BELOW_RAIL_M - FLOOR_THICKNESS_M
	var wall_top := CLEAR_HEIGHT_M + ROOF_THICKNESS_M
	var wall_height := wall_top - wall_bottom
	var wall_center_y := (wall_top + wall_bottom) * 0.5
	poses.append(_box_pose(right, up, forward, midpoint + up * floor_center_y,
		Vector3(outer_width, FLOOR_THICKNESS_M, length)))
	poses.append(_box_pose(right, up, forward, midpoint + up * roof_center_y,
		Vector3(outer_width, ROOF_THICKNESS_M, length)))
	for side in [-1.0, 1.0]:
		var lateral: float = float(side) * (INNER_HALF_WIDTH_M + WALL_THICKNESS_M * 0.5)
		poses.append(_box_pose(right, up, forward, midpoint + right * lateral + up * wall_center_y,
			Vector3(WALL_THICKNESS_M, wall_height, length)))


func _box_pose(right: Vector3, up: Vector3, forward: Vector3, origin: Vector3,
		size: Vector3) -> Transform3D:
	return Transform3D(Basis(right * size.x, up * size.y, -forward * size.z), origin)