extends SceneTree

func max_turn(points: PackedVector3Array) -> float:
	var result := 0.0
	for index in range(1, points.size() - 1):
		var a := points[index] - points[index - 1]
		var b := points[index + 1] - points[index]
		if minf(a.length(), b.length()) > 0.001:
			result = maxf(result, rad_to_deg(a.angle_to(b)))
	return result

func max_slope(points: PackedVector3Array) -> float:
	# 纵断面最大坡度；DEM 尖峰会在这里暴露为陡坡。
	var result := 0.0
	for index in range(1, points.size()):
		var d := points[index] - points[index - 1]
		var horizontal := Vector2(d.x, d.z).length()
		if horizontal > 0.001:
			result = maxf(result, absf(rad_to_deg(atan2(d.y, horizontal))))
	return result

func max_slope_change(points: PackedVector3Array) -> float:
	# 相邻两点坡度的最大变化量；DEM 尖峰会在这里暴露为急顶动。
	var result := 0.0
	var previous := 0.0
	for index in range(1, points.size()):
		var d := points[index] - points[index - 1]
		var horizontal := Vector2(d.x, d.z).length()
		var slope := rad_to_deg(atan2(d.y, horizontal)) if horizontal > 0.001 else 0.0
		if index > 1:
			result = maxf(result, absf(slope - previous))
		previous = slope
	return result

func _initialize() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://offline_data/manifest.json"))
	var source := PackedVector3Array()
	for point in manifest.route:
		source.append(Vector3(point[0], point[1], point[2]))
	var smooth := preload("res://route_smoothing.gd").smooth(source)
	var deviation := 0.0
	for point in smooth:
		var nearest := INF
		for index in range(source.size() - 1):
			var closest := Geometry3D.get_closest_point_to_segment(point, source[index], source[index + 1])
			nearest = minf(nearest, point.distance_to(closest))
		deviation = maxf(deviation, nearest)
	var before := max_turn(source)
	var after := max_turn(smooth)
	var slope_before := max_slope(source)
	var slope_after := max_slope(smooth)
	var kink_before := max_slope_change(source)
	var kink_after := max_slope_change(smooth)
	var ok := smooth[0] == source[0] and smooth[-1] == source[-1] and after < before \
		and slope_after < slope_before and kink_after < kink_before and deviation < 6.01
	print("ROUTE_SMOOTHING ", "PASS" if ok else "FAIL", " source_points=", source.size(), " smooth_points=", smooth.size(),
		" max_turn_before_deg=", before, " max_turn_after_deg=", after,
		" max_slope_before_deg=", slope_before, " max_slope_after_deg=", slope_after,
		" slope_kink_before_deg=", kink_before, " slope_kink_after_deg=", kink_after,
		" max_deviation_m=", deviation)
	quit(0 if ok else 1)
