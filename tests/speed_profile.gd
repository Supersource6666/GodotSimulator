extends SceneTree

const SPEED_PROFILE_SCRIPT := preload("res://speed_profile.gd")


func _initialize() -> void:
	var profile = SPEED_PROFILE_SCRIPT.new()
	assert(profile.load_csv("res://GPS_Data/speed_1.csv"))
	assert(profile.speeds.size() == 1551)
	assert(is_equal_approx(profile.sample_progress(0.0), 2.334))
	assert(is_equal_approx(profile.sample_progress(1.0), 8.541))
	var midpoint := profile.sample_progress(0.5)
	assert(midpoint >= 0.0 and midpoint <= 200.0)
	print("SPEED_PROFILE_PASS samples=", profile.speeds.size(), " midpoint_kmh=", midpoint)
	quit(0)
