extends SceneTree


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var panel = load("res://mini_map_panel.gd").new()
	panel.allow_google_map = false
	root.add_child(panel)
	panel.configure(6686.0)
	panel.set_mileage(3270.0)
	assert(panel.route_geo.size() == 170)
	assert(panel.request_node == null)
	assert(panel.desired_cell == 7)
	assert(absf(panel.current_geo.y - 35.65406) < 0.00015)
	assert(absf(panel.current_geo.x - 139.75708) < 0.00015)
	assert("纬度" in panel.coordinate_label.text and "经度" in panel.coordinate_label.text)
	assert(panel.current_heading >= 0.0 and panel.current_heading < 360.0)
	panel.free()
	print("MINI_MAP_TEST PASS: route, coordinate, heading and offline fallback")
	quit(0)
