class_name SpeedProfile
extends RefCounted

var times := PackedFloat64Array()
var speeds := PackedFloat64Array()


func load_csv(path: String) -> bool:
	times.clear()
	speeds.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var header := file.get_csv_line()
	var time_column := header.find("video_time_s")
	var speed_column := header.find("speed_kmh")
	var status_column := header.find("status")
	if time_column < 0 or speed_column < 0:
		return false
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= maxi(time_column, speed_column):
			continue
		if status_column >= 0 and row.size() > status_column and row[status_column] != "parsed":
			continue
		if not row[time_column].is_valid_float() or not row[speed_column].is_valid_float():
			continue
		var sample_time := float(row[time_column])
		var sample_speed := float(row[speed_column])
		if not times.is_empty() and sample_time <= times[-1]:
			continue
		times.append(sample_time)
		speeds.append(maxf(sample_speed, 0.0))
	return times.size() >= 2


func sample_progress(progress: float) -> float:
	if speeds.is_empty():
		return 0.0
	if speeds.size() == 1:
		return speeds[0]
	var target_time := lerpf(times[0], times[-1], clampf(progress, 0.0, 1.0))
	var low := 0
	var high := times.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if target_time >= times[middle]:
			low = middle
		else:
			high = middle
	var fraction := (target_time - times[low]) / maxf(times[high] - times[low], 0.000001)
	return lerpf(speeds[low], speeds[high], fraction)
