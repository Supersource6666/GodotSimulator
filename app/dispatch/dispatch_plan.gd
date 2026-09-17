class_name DispatchPlan
extends RefCounted
## 列车调度方案模型（参考 Libre TrainSim 的"选线路 → 选车次/时刻表 → 载入场景"流程）。
##
## 调度台用它生成时刻表、运行图与走行时分；三维场景用同一份方案生成同一条运行曲线，
## 因此"计划时刻"与"实际运行"始终一致：场景按方案停车、停站、按限速运行。
##
## 走行曲线为区段内的标准牵引模型（匀加速 → 限速巡航 → 匀制动），
## 同一函数在调度台与场景中都会被调用，保证两端结果一致。

const SCHEMA_VERSION := 1
const ACCEL_MPS2 := 0.65      # 启动加速度（约 2.3 km/h/s，接近 N700 系常用值）
const BRAKE_MPS2 := 0.90      # 常用制动减速度
const SAMPLE_STEP_M := 2.0    # 运行曲线采样步长
const MIN_SPEED_KMH := 40.0
const MAX_SPEED_KMH := 320.0
const MAX_DWELL_S := 900.0
const TIME_EPSILON := 0.0001


# ── 时间格式 ──────────────────────────────────────────────────────────────────

static func format_clock(seconds: float) -> String:
	var total := int(round(seconds))
	var hours := posmod(total / 3600, 24)
	return "%02d:%02d:%02d" % [hours, posmod(total / 60, 60), posmod(total, 60)]


static func format_short_clock(seconds: float) -> String:
	var total := int(round(seconds))
	return "%02d:%02d" % [posmod(total / 3600, 24), posmod(total / 60, 60)]


static func format_duration(seconds: float) -> String:
	var total := maxi(int(round(seconds)), 0)
	if total < 60:
		return "%d 秒" % total
	if total < 3600:
		return "%d 分 %02d 秒" % [total / 60, total % 60]
	return "%d 时 %02d 分" % [total / 3600, (total % 3600) / 60]


static func parse_short_clock(text: String) -> float:
	var parts := text.strip_edges().split(":", false)
	if parts.size() < 2:
		return -1.0
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1.0
	var hours := int(parts[0])
	var minutes := int(parts[1])
	if hours < 0 or hours > 47 or minutes < 0 or minutes > 59:
		return -1.0
	return float(hours * 3600 + minutes * 60)


static func direction_label(direction: int, route_config: Dictionary) -> String:
	var directions: Array = route_config.get("directions", [])
	for entry in directions:
		if not entry is Dictionary:
			continue
		if int(entry.get("key_int", 0)) == direction:
			return str(entry.get("label", ""))
	for entry in directions:
		if entry is Dictionary and str(entry.get("key", "")) == ("down" if direction >= 0 else "up"):
			return str(entry.get("label", ""))
	return "正向" if direction >= 0 else "反向"


# ── 计划构造 ──────────────────────────────────────────────────────────────────

static func default_plan(module_id: String, dispatch_config: Dictionary) -> Dictionary:
	var route_config: Dictionary = dispatch_config.get("route", {})
	var services: Array = dispatch_config.get("services", [])
	var service: Dictionary = services[0] if not services.is_empty() and services[0] is Dictionary else {}
	var stations: Array = []
	for raw in dispatch_config.get("stations", []):
		if not raw is Dictionary:
			continue
		stations.append({
			"name": str(raw.get("name", "车站")),
			"code": str(raw.get("code", "")),
			"chainage_m": float(raw.get("chainage_m", 0.0)),
			"platform": str(raw.get("platform", "")),
			"platforms": raw.get("platforms", []),
			"dwell_s": float(raw.get("dwell_s", 90.0)),
			"stop": bool(raw.get("stop", true)),
			"origin": bool(raw.get("origin", false)),
			"terminal": bool(raw.get("terminal", false)),
		})
	if not stations.is_empty():
		stations[0]["stop"] = true
		stations[stations.size() - 1]["stop"] = true
	return {
		"schema": SCHEMA_VERSION,
		"module": module_id,
		"route_name": str(route_config.get("name", module_id)),
		"route_section": str(route_config.get("section", "")),
		"operator": str(route_config.get("operator", "")),
		"service_key": str(service.get("key", "custom")),
		"service_name": str(service.get("name", "列车")),
		"service_label": str(service.get("label", "")),
		"number": str(service.get("number", "1")),
		"car_count": int(service.get("cars", 4)),
		"direction": 1,
		"direction_label": direction_label(1, route_config),
		"max_speed_kmh": float(service.get("speed_kmh", route_config.get("max_speed_kmh", 120.0))),
		"line_limit_kmh": float(route_config.get("max_speed_kmh", 120.0)),
		"departure_s": 6.0 * 3600.0,
		"dispatcher": "调度台",
		"note": "",
		"created_ms": Time.get_unix_time_from_system(),
		"stations": stations,
	}


static func train_label(plan: Dictionary) -> String:
	var name := str(plan.get("service_name", "列车"))
	var number := str(plan.get("number", "")).strip_edges()
	return name if number.is_empty() else "%s %s号" % [name, number]


static func speed_cap_kmh(plan: Dictionary) -> float:
	return clampf(float(plan.get("max_speed_kmh", 120.0)), MIN_SPEED_KMH, MAX_SPEED_KMH)


# ── 时刻表 / 运行曲线 ─────────────────────────────────────────────────────────

static func build_schedule(plan: Dictionary, route_length_m: float) -> Dictionary:
	var total_distance := maxf(route_length_m, 0.0)
	var stations: Array[Dictionary] = []
	for raw in plan.get("stations", []):
		if not raw is Dictionary:
			continue
		stations.append({
			"name": str(raw.get("name", "车站")),
			"code": str(raw.get("code", "")),
			"platform": str(raw.get("platform", "")),
			"chainage_m": clampf(float(raw.get("chainage_m", 0.0)), 0.0, total_distance),
			"stop": bool(raw.get("stop", true)),
			"dwell_s": clampf(float(raw.get("dwell_s", 0.0)), 0.0, MAX_DWELL_S),
			"origin": bool(raw.get("origin", false)),
			"terminal": bool(raw.get("terminal", false)),
			"arrival_s": 0.0,
			"departure_s": 0.0,
			"time_s": 0.0,
			"speed_kmh": 0.0,
			"stopped": bool(raw.get("stop", true)),
		})
	if stations.is_empty():
		return {}
	stations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["chainage_m"]) < float(b["chainage_m"]))
	stations[0]["stop"] = true
	stations[0]["origin"] = true
	stations[stations.size() - 1]["terminal"] = true
	var last_index := stations.size() - 1
	var origin_distance := float(stations[0]["chainage_m"])
	var terminal_distance := float(stations[last_index]["chainage_m"])
	var run_to_route_end := not bool(stations[last_index]["stop"]) \
		and terminal_distance < total_distance - 0.5
	var v_cap := speed_cap_kmh(plan) / 3.6

	var samples_x := PackedFloat64Array()
	var samples_t := PackedFloat64Array()
	var samples_v := PackedFloat64Array()

	var stop_indices: Array[int] = [0]
	for index in range(1, stations.size()):
		if bool(stations[index]["stop"]):
			stop_indices.append(index)

	var clock := 0.0
	var cursor := origin_distance
	var station_cursor := 0
	samples_x.append(origin_distance)
	samples_t.append(0.0)
	samples_v.append(0.0)

	for order in range(1, stop_indices.size()):
		var target_index: int = stop_indices[order]
		var target_x := float(stations[target_index]["chainage_m"])
		var segment := _build_segment(cursor, target_x, v_cap, true)
		for index in range(station_cursor + 1, target_index):
			var passing := _sample_at(segment, float(stations[index]["chainage_m"]))
			stations[index]["time_s"] = clock + float(passing["t"])
			stations[index]["arrival_s"] = stations[index]["time_s"]
			stations[index]["departure_s"] = stations[index]["time_s"]
			stations[index]["speed_kmh"] = float(passing["v"]) * 3.6
		_append_segment(samples_x, samples_t, samples_v, segment, clock)
		clock += float(segment["duration"])
		stations[target_index]["arrival_s"] = clock
		stations[target_index]["time_s"] = clock
		stations[target_index]["speed_kmh"] = 0.0
		var dwell := float(stations[target_index]["dwell_s"])
		var is_final_point := order == stop_indices.size() - 1 and not run_to_route_end
		if is_final_point:
			dwell = 0.0
		stations[target_index]["departure_s"] = clock + dwell
		if dwell > 0.0:
			samples_x.append(target_x)
			samples_t.append(clock + dwell)
			samples_v.append(0.0)
		clock += dwell
		cursor = target_x
		station_cursor = target_index

	if run_to_route_end and cursor < total_distance - 0.5:
		var segment := _build_segment(cursor, total_distance, v_cap, false)
		for index in range(station_cursor + 1, stations.size()):
			var passing := _sample_at(segment, float(stations[index]["chainage_m"]))
			stations[index]["time_s"] = clock + float(passing["t"])
			stations[index]["arrival_s"] = stations[index]["time_s"]
			stations[index]["departure_s"] = stations[index]["time_s"]
			stations[index]["speed_kmh"] = float(passing["v"]) * 3.6
		_append_segment(samples_x, samples_t, samples_v, segment, clock)
		clock += float(segment["duration"])

	var distance := samples_x[samples_x.size() - 1]
	var max_speed := 0.0
	for value in samples_v:
		max_speed = maxf(max_speed, float(value))
	var stop_count := 0
	var pass_count := 0
	for station in stations:
		if bool(station["stop"]):
			stop_count += 1
		else:
			pass_count += 1
	return {
		"schema": SCHEMA_VERSION,
		"route_length_m": total_distance,
		"distance_m": distance,
		"total_time_s": clock,
		"run_time_s": clock,
		"max_speed_kmh": max_speed * 3.6,
		"avg_speed_kmh": (distance / clock * 3.6) if clock > 0.0 else 0.0,
		"speed_cap_kmh": v_cap * 3.6,
		"stop_count": stop_count,
		"pass_count": pass_count,
		"stops": stop_count,
		"stations": stations,
		"samples_x": samples_x,
		"samples_t": samples_t,
		"samples_v": samples_v,
	}


static func _append_segment(xs: PackedFloat64Array, ts: PackedFloat64Array,
		vs: PackedFloat64Array, segment: Dictionary, offset: float) -> void:
	var seg_xs: PackedFloat64Array = segment["xs"]
	var seg_ts: PackedFloat64Array = segment["ts"]
	var seg_vs: PackedFloat64Array = segment["vs"]
	for index in range(1, seg_xs.size()):
		xs.append(seg_xs[index])
		ts.append(offset + seg_ts[index])
		vs.append(seg_vs[index])


static func _build_segment(x0: float, x1: float, v_cap: float, stop_at_end: bool) -> Dictionary:
	var xs := PackedFloat64Array()
	var ts := PackedFloat64Array()
	var vs := PackedFloat64Array()
	var span := x1 - x0
	if span <= 0.0:
		xs.append(x0)
		ts.append(0.0)
		vs.append(0.0)
		return {"xs": xs, "ts": ts, "vs": vs, "duration": 0.0}
	var acceleration := ACCEL_MPS2
	var braking := BRAKE_MPS2
	var v_peak := v_cap
	var accel_distance := v_peak * v_peak / (2.0 * acceleration)
	var brake_distance := 0.0 if not stop_at_end else v_peak * v_peak / (2.0 * braking)
	if stop_at_end and accel_distance + brake_distance > span:
		v_peak = sqrt(2.0 * span * acceleration * braking / (acceleration + braking))
		accel_distance = v_peak * v_peak / (2.0 * acceleration)
		brake_distance = v_peak * v_peak / (2.0 * braking)
	var t_accel := v_peak / acceleration
	var t_brake := v_peak / braking if stop_at_end else 0.0
	var duration := 0.0
	if stop_at_end:
		duration = t_accel + maxf(span - accel_distance - brake_distance, 0.0) / v_peak + t_brake
	elif accel_distance > span:
		# 区段太短，尚未加速到限速就结束（例如末站通过后直到区段终点）。
		duration = sqrt(maxf(2.0 * acceleration * span, 0.0)) / acceleration
	else:
		duration = t_accel + (span - accel_distance) / v_peak
	var count := int(floor(span / SAMPLE_STEP_M))
	for index in range(count + 1):
		var offset := minf(SAMPLE_STEP_M * float(index), span)
		var speed := 0.0
		var time := 0.0
		if offset <= accel_distance:
			speed = sqrt(maxf(2.0 * acceleration * offset, 0.0))
			time = speed / acceleration
		elif stop_at_end and offset >= span - brake_distance:
			speed = sqrt(maxf(2.0 * braking * (span - offset), 0.0))
			time = duration - speed / braking
		else:
			speed = v_peak
			time = t_accel + (offset - accel_distance) / v_peak
		xs.append(x0 + offset)
		ts.append(clampf(time, 0.0, duration))
		vs.append(speed)
	return {"xs": xs, "ts": ts, "vs": vs, "duration": duration}


static func _sample_at(segment: Dictionary, x: float) -> Dictionary:
	var xs: PackedFloat64Array = segment["xs"]
	var ts: PackedFloat64Array = segment["ts"]
	var vs: PackedFloat64Array = segment["vs"]
	var count := xs.size()
	if count == 0:
		return {"t": 0.0, "v": 0.0}
	if x <= xs[0]:
		return {"t": ts[0], "v": vs[0]}
	if x >= xs[count - 1]:
		return {"t": ts[count - 1], "v": vs[count - 1]}
	var low := 0
	var high := count - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if x >= xs[middle]:
			low = middle
		else:
			high = middle
	var span := maxf(xs[high] - xs[low], 0.0001)
	var ratio := clampf((x - xs[low]) / span, 0.0, 1.0)
	return {"t": lerpf(ts[low], ts[high], ratio), "v": lerpf(vs[low], vs[high], ratio)}


# ── 运行曲线查询 ─────────────────────────────────────────────────────────────

static func distance_at_time(schedule: Dictionary, time_s: float) -> float:
	var ts: PackedFloat64Array = schedule.get("samples_t", PackedFloat64Array())
	var xs: PackedFloat64Array = schedule.get("samples_x", PackedFloat64Array())
	if ts.is_empty():
		return 0.0
	if time_s <= ts[0]:
		return xs[0]
	if time_s >= ts[ts.size() - 1]:
		return xs[xs.size() - 1]
	var low := 0
	var high := ts.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if time_s >= ts[middle]:
			low = middle
		else:
			high = middle
	var span := ts[high] - ts[low]
	if span <= TIME_EPSILON:
		return xs[high]
	return lerpf(xs[low], xs[high], clampf((time_s - ts[low]) / span, 0.0, 1.0))


static func speed_at_time(schedule: Dictionary, time_s: float) -> float:
	var ts: PackedFloat64Array = schedule.get("samples_t", PackedFloat64Array())
	var vs: PackedFloat64Array = schedule.get("samples_v", PackedFloat64Array())
	if ts.is_empty():
		return 0.0
	if time_s <= ts[0]:
		return vs[0]
	if time_s >= ts[ts.size() - 1]:
		return vs[vs.size() - 1]
	var low := 0
	var high := ts.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if time_s >= ts[middle]:
			low = middle
		else:
			high = middle
	var span := ts[high] - ts[low]
	if span <= TIME_EPSILON:
		return vs[high]
	return lerpf(vs[low], vs[high], clampf((time_s - ts[low]) / span, 0.0, 1.0))


static func time_at_distance(schedule: Dictionary, distance_m: float) -> float:
	var xs: PackedFloat64Array = schedule.get("samples_x", PackedFloat64Array())
	var ts: PackedFloat64Array = schedule.get("samples_t", PackedFloat64Array())
	if xs.is_empty():
		return 0.0
	var index := 0
	var high := xs.size() - 1
	while high - index > 1:
		var middle := (index + high) / 2
		if distance_m >= xs[middle]:
			index = middle
		else:
			high = middle
	return ts[index] if distance_m < xs[xs.size() - 1] else ts[ts.size() - 1]


static func station_index_at(schedule: Dictionary, time_s: float) -> int:
	var stations: Array = schedule.get("stations", [])
	var result := -1
	for index in range(stations.size()):
		var station: Dictionary = stations[index]
		if time_s + TIME_EPSILON >= float(station.get("departure_s", 0.0)):
			result = index
	return result


static func next_station_index(schedule: Dictionary, time_s: float) -> int:
	var stations: Array = schedule.get("stations", [])
	for index in range(stations.size()):
		var station: Dictionary = stations[index]
		if time_s < float(station.get("departure_s", 0.0)) - TIME_EPSILON:
			return index
	return -1


static func validate(plan: Dictionary, schedule: Dictionary) -> PackedStringArray:
	var notes := PackedStringArray()
	var stations: Array = plan.get("stations", [])
	if stations.is_empty():
		notes.append("未提供车站数据：场景只按运行限速运行，不执行停站。")
		return notes
	if schedule.is_empty():
		notes.append("时刻表无法生成：请检查车站里程。")
		return notes
	var route_length := float(schedule.get("route_length_m", 0.0))
	var previous := -1.0
	for station in schedule.get("stations", []):
		var chainage := float(station.get("chainage_m", 0.0))
		if chainage <= previous:
			notes.append("车站里程重复或未递增：%s" % str(station.get("name", "")))
		previous = chainage
	if not (schedule.get("stations", []) as Array).is_empty():
		var last: Dictionary = (schedule["stations"] as Array)[(schedule["stations"] as Array).size() - 1]
		if float(last.get("chainage_m", 0.0)) > route_length + 0.5:
			notes.append("车站里程超出线路长度。")
	if float(schedule.get("total_time_s", 0.0)) <= 0.0:
		notes.append("走行时分为 0：请检查限速与站间里程。")
	return notes
