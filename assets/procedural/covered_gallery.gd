extends Node3D
## Concrete covered galleries crossing the railway at the three levelled sites.
## Each gallery can use an independent span and vertical datum; underground
## galleries place their roof at the track-base level to fill terrain voids.

const DetailBatch := preload("res://assets/procedural/detail_batch.gd")
const INNER_HALF_WIDTH_M := 4.8
const WALL_THICKNESS_M := 0.45
const FLOOR_THICKNESS_M := 0.50
const FLOOR_TOP_BELOW_RAIL_M := 0.42
const CLEAR_HEIGHT_M := 8.5
const ROOF_THICKNESS_M := 0.50
const CONCRETE_COLOR := Color(0.39, 0.40, 0.41)

var segment_count := 0
var _geometry: Node3D


func build(galleries: Array, pose_provider: Callable) -> void:
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
	for gallery_value in galleries:
		var config: Dictionary = gallery_value
		var center := float(config.get("center_m", 0.0))
		var half_span := float(config.get("half_span_m", 0.0))
		var center_pose: Dictionary = pose_provider.call(center, 0.0)
		_append_crossing(poses, center_pose, half_span, config)
		segment_count += 1
	DetailBatch.batch(_geometry, "CoveredGalleryBoxes", unit_box, poses, 1800.0)
	print("COVERED_GALLERIES_READY count=", galleries.size(), " segments=", segment_count)


func _append_crossing(poses: Array[Transform3D], center_pose: Dictionary, half_span: float,
		config: Dictionary = {}) -> void:
	if half_span <= 0.001:
		return
	var midpoint: Vector3 = center_pose["point"]
	var up: Vector3 = center_pose.get("up", Vector3.UP)
	up = up.normalized()
	# The gallery's long axis follows the route normal (right), so it crosses
	# the rails at 90 degrees instead of extending along the track tangent.
	var crossing_direction: Vector3 = center_pose["right"]
	crossing_direction = (crossing_direction - up * crossing_direction.dot(up)).normalized()
	if crossing_direction.length_squared() <= 0.000001:
		var route_forward: Vector3 = center_pose.get("forward", Vector3.FORWARD)
		crossing_direction = route_forward.cross(up).normalized()
	var width_axis := crossing_direction.cross(up).normalized()
	var span := half_span * 2.0
	var inner_width := float(config.get("inner_width_m", INNER_HALF_WIDTH_M * 2.0))
	var wall_thickness := float(config.get("wall_thickness_m", WALL_THICKNESS_M))
	var floor_thickness := float(config.get("floor_thickness_m", FLOOR_THICKNESS_M))
	var roof_thickness := float(config.get("roof_thickness_m", ROOF_THICKNESS_M))
	var default_clear_height := CLEAR_HEIGHT_M + FLOOR_TOP_BELOW_RAIL_M
	var clear_height := float(config.get("clear_height_m", default_clear_height))
	var default_floor_bottom := -FLOOR_TOP_BELOW_RAIL_M - FLOOR_THICKNESS_M
	var floor_bottom := float(config.get("floor_bottom_above_rail_m", default_floor_bottom))
	if config.has("roof_top_below_rail_m"):
		# Derive the floor datum from the requested finished roof level so the
		# roof fills the depression while the usable passage remains underground.
		floor_bottom = -float(config.roof_top_below_rail_m) \
			- floor_thickness - clear_height - roof_thickness
	var floor_top := floor_bottom + floor_thickness
	var roof_bottom := floor_top + clear_height
	var outer_width := inner_width + wall_thickness * 2.0
	var floor_center_y := floor_bottom + floor_thickness * 0.5
	var roof_center_y := roof_bottom + roof_thickness * 0.5
	var wall_bottom := floor_bottom
	var wall_top := roof_bottom + roof_thickness
	var wall_height := wall_top - wall_bottom
	var wall_center_y := (wall_top + wall_bottom) * 0.5
	poses.append(_box_pose(width_axis, up, crossing_direction, midpoint + up * floor_center_y,
		Vector3(outer_width, floor_thickness, span)))
	poses.append(_box_pose(width_axis, up, crossing_direction, midpoint + up * roof_center_y,
		Vector3(outer_width, roof_thickness, span)))
	for side in [-1.0, 1.0]:
		var lateral: float = float(side) * (inner_width * 0.5 + wall_thickness * 0.5)
		poses.append(_box_pose(width_axis, up, crossing_direction, midpoint + width_axis * lateral + up * wall_center_y,
			Vector3(wall_thickness, wall_height, span)))


func _box_pose(right: Vector3, up: Vector3, forward: Vector3, origin: Vector3,
		size: Vector3) -> Transform3D:
	return Transform3D(Basis(right * size.x, up * size.y, -forward * size.z), origin)
