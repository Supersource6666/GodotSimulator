extends SceneTree

const CENTERS := [2407.0, 3008.0, 3924.0]
const HALF_LENGTH := 65.0
const TRANSITION := 60.0
const GALLERY_CONFIGS := [
	{
		"center_m": 2407.0,
		"half_span_m": 42.0,
		"inner_width_m": 30.0,
		"roof_top_below_rail_m": 0.42,
		"clear_height_m": 4.5,
		"wall_thickness_m": 0.30,
		"floor_thickness_m": 0.35,
		"roof_thickness_m": 0.30,
	},
	{
		"center_m": 3008.0,
		"half_span_m": 65.0,
		"roof_top_below_rail_m": 0.42,
		"clear_height_m": 4.5,
		"floor_thickness_m": 0.35,
		"roof_thickness_m": 0.30,
	},
	{
		"center_m": 3924.0,
		"half_span_m": 42.0,
		"inner_width_m": 30.0,
		"roof_top_below_rail_m": 0.42,
		"clear_height_m": 4.5,
		"wall_thickness_m": 0.30,
		"floor_thickness_m": 0.35,
		"roof_thickness_m": 0.30,
	},
]

func pose(distance: float, vertical_offset: float = 0.0) -> Dictionary:
	return {
		"point": Vector3(0.0, 20.0 + vertical_offset, -distance),
		"forward": Vector3.FORWARD,
		"right": Vector3.RIGHT,
		"up": Vector3.UP,
		"distance": distance,
	}

func _initialize() -> void:
	var points := PackedVector3Array()
	var chain := PackedFloat64Array()
	for index in range(4501):
		var distance := float(index)
		chain.append(distance)
		points.append(Vector3(0.0, 20.0 + sin(distance * 0.017) * 2.0, -distance))
	var source := points.duplicate()
	var ground = load("res://ground_track.gd").new()
	for index in CENTERS.size():
		assert(is_equal_approx(CENTERS[index], float(GALLERY_CONFIGS[index].center_m)))
	var levelled: PackedVector3Array = ground.level_crossings(points, chain, CENTERS, HALF_LENGTH, TRANSITION)
	assert(levelled.size() == points.size())
	for center_value in CENTERS:
		var center := int(center_value)
		var expected := -INF
		for index in range(center - int(HALF_LENGTH), center + int(HALF_LENGTH) + 1):
			expected = maxf(expected, source[index].y)
		for index in range(center - int(HALF_LENGTH), center + int(HALF_LENGTH) + 1):
			assert(is_equal_approx(levelled[index].y, expected))
	assert(levelled[2000].is_equal_approx(source[2000]))
	var gallery = load("res://assets/procedural/covered_gallery.gd").new()
	root.add_child(gallery)
	gallery.build(GALLERY_CONFIGS, pose)
	assert(gallery.segment_count == 3)
	var boxes := gallery.get_node("GalleryGeometry/CoveredGalleryBoxes") as MultiMeshInstance3D
	assert(boxes != null and boxes.multimesh.instance_count == 12)
	var first_gallery: Dictionary = GALLERY_CONFIGS[0]
	var first_poses: Array[Transform3D] = []
	gallery._append_crossing(first_poses, pose(first_gallery.center_m, 0.0),
		first_gallery.half_span_m, first_gallery)
	var first_roof := first_poses[1]
	var first_roof_top := first_roof.origin.y - 20.0 + first_roof.basis.y.length() * 0.5
	assert(is_equal_approx(first_roof_top, -0.42))
	assert(is_equal_approx(first_poses[0].basis.z.length(), 84.0))
	assert(is_equal_approx(first_poses[0].basis.x.length(), 30.6))
	assert(is_equal_approx(first_poses[2].basis.y.length(), 5.15))
	var second_gallery: Dictionary = GALLERY_CONFIGS[1]
	var second_poses: Array[Transform3D] = []
	gallery._append_crossing(second_poses, pose(second_gallery.center_m, 0.0),
		second_gallery.half_span_m, second_gallery)
	var second_roof := second_poses[1]
	var second_roof_top := second_roof.origin.y - 20.0 + second_roof.basis.y.length() * 0.5
	assert(is_equal_approx(second_roof_top, -0.42))
	assert(is_equal_approx(second_poses[2].basis.y.length(), 5.15))
	var crossing_poses: Array[Transform3D] = []
	var moved_gallery: Dictionary = GALLERY_CONFIGS[2]
	gallery._append_crossing(crossing_poses, pose(moved_gallery.center_m, 0.0),
		moved_gallery.half_span_m, moved_gallery)
	assert(crossing_poses.size() == 4)
	var first_floor := crossing_poses[0]
	var long_axis := first_floor.basis.z
	assert(is_equal_approx(long_axis.length(), 84.0))
	assert(absf(long_axis.normalized().dot(Vector3.FORWARD)) < 0.0001)
	assert(absf(long_axis.normalized().dot(Vector3.RIGHT)) > 0.9999)
	assert(is_equal_approx(first_floor.basis.x.length(), 30.6))
	assert(is_equal_approx(first_floor.basis.y.length(), 0.35))
	assert(is_equal_approx(first_floor.origin.y, 14.605))
	var roof := crossing_poses[1]
	var roof_top_relative_to_rail := roof.origin.y - 20.0 + roof.basis.y.length() * 0.5
	assert(is_equal_approx(roof_top_relative_to_rail, -0.42))
	var total_height := 0.35 + 4.5 + 0.30
	assert(is_equal_approx(total_height, 5.15))
	print("GROUND_GALLERIES_PASS center_m=3924 outer_width_m=30.6 total_height_m=5.15")
	quit(0)
