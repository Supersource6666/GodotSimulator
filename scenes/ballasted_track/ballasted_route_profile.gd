extends RefCounted
## Signed-curvature route reconstructed from ping_duan_mian.csv.
## Godot coordinates: X is track right, Y is up, and increasing mileage initially follows -Z.

var first_mileage_m := 0.0
var last_mileage_m := 0.0
var sample_spacing_m := 0.0
var _mileages := PackedFloat64Array()
var _curvatures := PackedFloat64Array()
var _headings := PackedFloat64Array()
var _points := PackedVector2Array()


func load_profile(path: String, maximum_distance_m: float, start_z: float) -> String:
	_mileages.clear()
	_curvatures.clear()
	_headings.clear()
	_points.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "cannot open route profile: %s" % path
	var header := file.get_line().strip_edges().to_lower()
	if header != "mileage,curvature_simulation":
		return "route CSV header must be mileage,curvature_simulation"
	var heading := 0.0
	var point := Vector2(0.0, start_z)
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var columns := line.split(",", false)
		if columns.size() != 2 or not columns[0].is_valid_float() or not columns[1].is_valid_float():
			return "invalid route CSV row: %s" % line
		var mileage := float(columns[0])
		var curvature := float(columns[1])
		if _mileages.is_empty():
			first_mileage_m = mileage
			_mileages.append(mileage)
			_curvatures.append(curvature)
			_headings.append(heading)
			_points.append(point)
			continue
		var distance := mileage - first_mileage_m
		if distance > maximum_distance_m + 1.0:
			break
		var previous_mileage := _mileages[-1]
		var ds := mileage - previous_mileage
		if ds <= 0.0:
			return "route mileages must be strictly increasing"
		var average_curvature := 0.5 * (_curvatures[-1] + curvature)
		var middle_heading := heading + 0.5 * average_curvature * ds
		point += Vector2(sin(middle_heading), -cos(middle_heading)) * ds
		heading += average_curvature * ds
		_mileages.append(mileage)
		_curvatures.append(curvature)
		_headings.append(heading)
		_points.append(point)
	if _mileages.size() < 2:
		return "route profile has fewer than two usable rows"
	last_mileage_m = _mileages[-1]
	sample_spacing_m = _mileages[1] - _mileages[0]
	return ""


func sample_count() -> int:
	return _mileages.size()


func distance_range_m() -> float:
	return last_mileage_m - first_mileage_m


func curvature_at_distance(distance_m: float) -> float:
	var sample := _sample(distance_m)
	return float(sample.curvature)


func pose_at_distance(distance_m: float, lateral_m: float = 0.0, height_m: float = 0.0) -> Transform3D:
	var sample := _sample(distance_m)
	var heading := float(sample.heading)
	var center := sample.point as Vector2
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	var right := Vector3(cos(heading), 0.0, sin(heading))
	var origin := Vector3(center.x, height_m, center.y) + right * lateral_m
	return Transform3D(Basis(right, Vector3.UP, -forward), origin)


func pose_at_mileage(mileage_m: float, lateral_m: float = 0.0, height_m: float = 0.0) -> Transform3D:
	return pose_at_distance(mileage_m - first_mileage_m, lateral_m, height_m)


func _sample(distance_m: float) -> Dictionary:
	var mileage := first_mileage_m + distance_m
	if mileage <= first_mileage_m:
		var forward_distance := mileage - first_mileage_m
		return {
			"point": _points[0] + Vector2(0.0, -forward_distance),
			"heading": 0.0,
			"curvature": _curvatures[0],
		}
	if mileage >= last_mileage_m:
		var heading := _headings[-1]
		var extra := mileage - last_mileage_m
		return {
			"point": _points[-1] + Vector2(sin(heading), -cos(heading)) * extra,
			"heading": heading,
			"curvature": _curvatures[-1],
		}
	var low := 0
	var high := _mileages.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if _mileages[middle] <= mileage:
			low = middle
		else:
			high = middle
	var fraction := (mileage - _mileages[low]) / (_mileages[high] - _mileages[low])
	return {
		"point": _points[low].lerp(_points[high], fraction),
		"heading": lerpf(_headings[low], _headings[high], fraction),
		"curvature": lerpf(_curvatures[low], _curvatures[high], fraction),
	}
