extends RefCounted
## Simple longitudinal preview control; does not replace the external dynamics solver.
var mileage_m := 0.0
const INITIAL_SPEED_MPS := 154.0 / 3.6
var speed_mps := INITIAL_SPEED_MPS
var time_s := 0.0
var end_mileage_m := INF
var maximum_speed_mps := 160.0 / 3.6
var traction_mps2 := 15.0
var brake_mps2 := 0.8
var coast_mps2 := 0.015
var control_status := "COASTING"

func advance(delta: float, traction: bool, brake: bool) -> Dictionary:
	delta = maxf(delta, 0.0)
	var acceleration := -brake_mps2 if brake else (traction_mps2 if traction else -coast_mps2)
	var old_speed := speed_mps
	var new_speed := clampf(old_speed + acceleration * delta, 0.0, maximum_speed_mps)
	var active_time := delta
	if acceleration != 0.0:
		active_time = clampf((new_speed - old_speed) / acceleration, 0.0, delta)
	mileage_m += (old_speed + new_speed) * 0.5 * active_time + new_speed * (delta - active_time)
	speed_mps = new_speed
	control_status = "BRAKING" if brake else ("TRACTION" if traction else "COASTING")
	if mileage_m >= end_mileage_m:
		mileage_m = end_mileage_m
		speed_mps = 0.0
		control_status = "ROUTE END"
	elif speed_mps <= 0.0:
		control_status = "STOPPED"
	time_s += delta
	return {"schema": "keyboard", "mileage_m": mileage_m, "speed_m_s": speed_mps, "t": time_s}
