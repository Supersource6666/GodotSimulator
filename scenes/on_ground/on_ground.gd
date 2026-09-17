extends "res://scenes/outdoors/outdoors.gd"
## Reuse outdoors terrain, trains, track components and controls.
const GROUND_ADAPTER := """
# Track reference to slab bottom: 0.48 m; corridor: 0.06 m; clearance: 0.02 m.
const GROUND_TRACK_OFFSET := 0.56
const ELEVATION_REPAIR := preload("res://scenes/on_ground/elevation_repair.gd")
var _ground_track_ready := false
var _repaired_indices: Array[int] = []
var _inspection_start := 8630.0
var _inspection_end := 8730.0
var _inspection_location := 8632.0

func _remap_station(distance: float, old_chain: PackedFloat32Array) -> float:
	for i in range(1, old_chain.size()):
		if old_chain[i] >= distance:
			var weight := (distance - old_chain[i - 1]) / maxf(old_chain[i] - old_chain[i - 1], 0.000001)
			return lerpf(_cum[i - 1], _cum[i], weight)
	return _dist_m

func _repair_elevation_holes() -> void:
	var result := ELEVATION_REPAIR.repair(_route, _ground_y)
	_repaired_indices.assign(result.indices)
	if _repaired_indices.is_empty():
		return
	var old_chain := _cum.duplicate()
	_ground_y = result.heights
	for index in _repaired_indices:
		_route[index][1] = float(_ground_y[index]) + GROUND_TRACK_OFFSET
	_cum[0] = 0.0
	for i in range(1, _route.size()):
		_cum[i] = _cum[i - 1] + _point(i).distance_to(_point(i - 1))
	_dist_m = _cum[_cum.size() - 1]
	_flat_start = _remap_station(_flat_start, old_chain)
	_flat_end = _remap_station(_flat_end, old_chain)
	_inspection_start = _remap_station(_inspection_start, old_chain)
	_inspection_end = _remap_station(_inspection_end, old_chain)
	_inspection_location = _remap_station(_inspection_location, old_chain)
	print("ON_GROUND_ELEVATION_REPAIR indices=", _repaired_indices, " inspection=", _inspection_location)
# Include the 109 m consist and tangent samples around the requested interval.
const FLAT_START_M := 8500.0
const FLAT_END_M := 8770.0
const TRANSITION_M := 100.0
var _flat_direction := Vector3.FORWARD
var _flat_start := 0.0
var _flat_end := 0.0

func _ready() -> void:
	super._ready()
	call_deferred("_inspect_horizontal_section")

func _inspect_horizontal_section() -> void:
	if not _ground_track_ready or _hold_site or _capture_enabled or _motion_test:
		return
	_space_pause = true
	_paused = true
	_jump_to_distance(_inspection_location)

func _route_sample(distance: float) -> Dictionary:
	var sample := super._route_sample(distance)
	if not sample.is_empty() and distance >= _flat_start and distance <= _flat_end:
		# Avoid tiny per-car yaw differences from float-rounded route vertices.
		sample["fwd"] = _flat_direction
	return sample

func _flatten_inspection_section() -> void:
	var original_stations := _cum.duplicate()
	var start_sample := super._route_sample(FLAT_START_M)
	var end_sample := super._route_sample(FLAT_END_M)
	if start_sample.is_empty() or end_sample.is_empty():
		return
	var first: Vector3 = start_sample.pos
	var last: Vector3 = end_sample.pos
	var level := maxf(first.y, last.y)
	for i in range(_route.size()):
		if original_stations[i] >= FLAT_START_M and original_stations[i] <= FLAT_END_M:
			level = maxf(level, _point(i).y)
	first.y = level
	last.y = level
	_flat_direction = (last - first).normalized()
	_ground_y = _ground_y.duplicate()
	for i in range(_route.size()):
		var station := float(original_stations[i])
		if station < FLAT_START_M - TRANSITION_M or station > FLAT_END_M + TRANSITION_M:
			continue
		var weight := 1.0
		if station < FLAT_START_M:
			weight = smoothstep(FLAT_START_M - TRANSITION_M, FLAT_START_M, station)
		elif station > FLAT_END_M:
			weight = 1.0 - smoothstep(FLAT_END_M, FLAT_END_M + TRANSITION_M, station)
		var straight := first + (last - first) * ((station - FLAT_START_M) / (FLAT_END_M - FLAT_START_M))
		var point := _point(i).lerp(straight, weight)
		_route[i] = [point.x, point.y, point.z]
		_ground_y[i] = float(point.y) - GROUND_TRACK_OFFSET
	_cum[0] = 0.0
	for i in range(1, _route.size()):
		_cum[i] = _cum[i - 1] + _point(i).distance_to(_point(i - 1))
	# Stay one sample inside the straight section so interpolated positions also align.
	for i in range(_route.size()):
		if original_stations[i] >= FLAT_START_M and original_stations[i] <= FLAT_END_M:
			if _flat_start == 0.0:
				_flat_start = _cum[i]
			_flat_end = _cum[i]
	_dist_m = _cum[_cum.size() - 1]
	print("ON_GROUND_FLAT section=", _flat_start, "..", _flat_end, " elevation=", level)

func _load_manifest() -> void:
	super._load_manifest()
	if _route.size() < 2 or _ground_y.size() != _route.size():
		push_error("OnGround: missing route ground heights")
		_route.clear()
		_dist_m = 0.0
		return
	# Preserve the horizontal alignment, replacing the viaduct elevation.
	_route = _route.duplicate(true)
	_cum = PackedFloat32Array()
	_cum.resize(_route.size())
	for i in range(_route.size()):
		_route[i][1] = float(_ground_y[i]) + GROUND_TRACK_OFFSET
		if i > 0:
			_cum[i] = _cum[i - 1] + _point(i).distance_to(_point(i - 1))
	_dist_m = _cum[_cum.size() - 1]
	_flatten_inspection_section()
	_repair_elevation_holes()
	_ground_track_ready = true
	print("ON_GROUND_READY samples=", _route.size(), " offset=", GROUND_TRACK_OFFSET)

func _point(i: int) -> Vector3:
	if _route.is_empty():
		return Vector3.ZERO
	i = clampi(i, 0, _route.size() - 1)
	var point: Array = _route[i]
	return Vector3(float(point[0]), float(_ground_y[i]) + GROUND_TRACK_OFFSET, float(point[2]))

func _add_track_batch(parent: Node3D, label: String, transforms: Array[Transform3D], material: Material) -> void:
	if label in ["BoxGirder", "Piers"]:
		return
	super._add_track_batch(parent, label, transforms, material)
"""

func _module_id() -> String:
	return "on_ground"

func _adapter_extension() -> String:
	return GROUND_ADAPTER

func _smoke_extra() -> bool:
	var track := preview.get_node_or_null("TrackSuperstructure")
	var ok: bool = preview._ground_track_ready and track != null
	if track != null:
		ok = ok and track.find_children("BoxGirder*", "", false, false).is_empty()
		ok = ok and track.find_children("Piers*", "", false, false).is_empty()
		ok = ok and not track.find_children("Rails*", "", false, false).is_empty()
	for i in range(preview._route.size()):
		ok = ok and is_equal_approx(preview._point(i).y, float(preview._ground_y[i]) + 0.56)
	# Check actual car transforms throughout the requested 100 m interval.
	var repaired_max_step := 0.0
	for index in preview._repaired_indices:
		for segment in [index - 1, index]:
			var delta: Vector3 = preview._point(segment + 1) - preview._point(segment)
			repaired_max_step = maxf(repaired_max_step, absf(delta.y))
			ok = ok and absf(delta.y) / maxf(Vector2(delta.x, delta.z).length(), 0.001) < 0.15
	print("ON_GROUND_REPAIR_CHECK count=", preview._repaired_indices.size(), " max_step_m=", repaired_max_step)
	var saved_distance: float = preview._travelled
	var max_angle := 0.0
	var max_height_difference := 0.0
	for step in range(101):
		var station: float = lerpf(preview._inspection_start, preview._inspection_end, step / 100.0)
		preview._travelled = station
		preview._update_camera_transform()
		if preview._external_train == null:
			var sample: Dictionary = preview._route_sample(float(station))
			ok = ok and absf((sample.fwd as Vector3).y) < 0.00001
			continue
		var lead := preview._external_train.get_child(0) as Node3D
		for index in range(1, 4):
			var car := preview._external_train.get_child(index) as Node3D
			max_angle = maxf(max_angle, lead.global_basis.z.angle_to(car.global_basis.z))
			max_height_difference = maxf(max_height_difference, absf(lead.global_position.y - car.global_position.y))
	preview._jump_to_distance(saved_distance)
	ok = ok and max_angle < 0.00001 and max_height_difference < 0.001
	print("ON_GROUND_CAR_ALIGNMENT angle_deg=", rad_to_deg(max_angle), " height_difference_m=", max_height_difference)
	print("ON_GROUND_SMOKE ", "PASS" if ok else "FAIL")
	return ok
