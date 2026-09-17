extends SceneTree
const REPAIR := preload("res://scenes/on_ground/elevation_repair.gd")
var failed := false

func _initialize() -> void:
	var route: Array = []
	var ground: Array = []
	for i in range(31):
		route.append([float(i * i + i), 0.0, 0.0])
		ground.append(700.0 + float(i * i + i) * 0.02)
	var baseline := ground.duplicate()
	var clean := REPAIR.repair(route, ground)
	check(clean.indices.is_empty() and clean.heights == ground, "normal slopes unchanged")
	ground[14] -= 315.0
	ground[15] -= 100.0
	var repaired := REPAIR.repair(route, ground)
	check(repaired.indices == [14, 15], "only the two holes repaired")
	for i in range(ground.size()):
		check(absf(float(repaired.heights[i]) - float(baseline[i])) < 0.000001, "distance-weighted interpolation")
	check(ground[14] == baseline[14] - 315.0, "input resource unchanged")
	var spike := baseline.duplicate()
	spike[14] += 315.0
	var fixed_spike := REPAIR.repair(route, spike)
	check(fixed_spike.indices == [14], "isolated upward spike repaired")
	check(absf(fixed_spike.heights[14] - baseline[14]) < 0.000001, "spike interpolation")
	print("ELEVATION_REPAIR_TEST ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
