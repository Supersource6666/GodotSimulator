extends SceneTree

const CENTERS := [2326.0, 2915.0, 3837.0]
const HALF_LENGTH := 65.0
const TRANSITION := 60.0

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
	gallery.build(CENTERS, HALF_LENGTH, pose)
	assert(gallery.segment_count == 78)
	assert(gallery.get_node("GalleryGeometry/CoveredGalleryBoxes") is MultiMeshInstance3D)
	print("GROUND_GALLERIES_PASS centers=3 level_length_m=130 segments=78")
	quit(0)