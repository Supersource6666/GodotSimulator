extends PanelContainer
## 车内调度时刻表 HUD。
## 显示车次、当前区间、下一站、计划到发点、剩余里程与时间，
## 以及"实绩相对计划"的偏差。按 T 切换显示。

const PLAN := preload("res://app/dispatch/dispatch_plan.gd")

var _plan: Dictionary = {}
var _schedule: Dictionary = {}
var _train_label: Label
var _segment_label: Label
var _next_label: Label
var _time_label: Label
var _offset_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	name = "DispatchBoard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -392.0
	offset_right = -20.0
	offset_top = -238.0
	offset_bottom = -88.0
	custom_minimum_size = Vector2(372.0, 150.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.06, 0.085, 0.86)
	style.border_color = Color(0.42, 0.60, 0.72, 0.7)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	_train_label = _add_label(column, 17, Color("#eaf4fb"))
	_segment_label = _add_label(column, 14, Color("#cfe2ee"))
	_next_label = _add_label(column, 14, Color("#ffd08a"))
	_time_label = _add_label(column, 14, Color("#cfe2ee"))
	_offset_label = _add_label(column, 13, Color("#9fbdd4"))


func _add_label(parent: VBoxContainer, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func configure(plan: Dictionary, schedule: Dictionary) -> void:
	_plan = plan.duplicate(true)
	_schedule = schedule.duplicate(true)
	var direction := str(_plan.get("direction_label", ""))
	if direction.is_empty():
		direction = "下り" if int(_plan.get("direction", 1)) >= 0 else "上り"
	_train_label.text = "%s · %s · %d 辆" % [
		PLAN.train_label(_plan),
		direction,
		int(_plan.get("car_count", 4))]
	refresh(0.0, 0.0, false, false)


func refresh(clock: float, mileage: float, paused: bool, finished: bool) -> void:
	if _schedule.is_empty():
		_segment_label.text = "暂无调度计划"
		_next_label.text = ""
		_time_label.text = ""
		_offset_label.text = ""
		return
	var stations: Array = _schedule.get("stations", [])
	var current := PLAN.station_index_at(_schedule, clock)
	var next := PLAN.next_station_index(_schedule, clock)
	var departure_s := float(_plan.get("departure_s", 0.0))
	var now_abs := departure_s + clock

	var segment_text := "区间："
	if current >= 0:
		segment_text += str(stations[current].get("name", "?"))
	else:
		segment_text += "始发"
	segment_text += " → "
	if next >= 0:
		segment_text += str(stations[next].get("name", "终点"))
	else:
		segment_text += "终点"
	_segment_label.text = segment_text

	if finished:
		_next_label.text = "终到 · %s" % PLAN.format_clock(now_abs)
		_time_label.text = "已到达终点站"
		_offset_label.text = "正点到达"
	else:
		if next >= 0:
			var next_station: Dictionary = stations[next]
			var arrival_rel := float(next_station.get("arrival_s", 0.0))
			var arrival_abs := departure_s + arrival_rel
			var stop := bool(next_station.get("stop", true))
			var remaining := maxf(arrival_rel - clock, 0.0)
			var remaining_distance := maxf(float(next_station.get("chainage_m", 0.0)) - mileage, 0.0)
			_next_label.text = "下一站：%s · %s%s · 剩 %.2f km" % [
				str(next_station.get("name", "")),
				"停车" if stop else "通过",
				(" · " + str(next_station.get("platform", ""))) if stop else "",
				remaining_distance / 1000.0]
			_time_label.text = "计划%s %s · 剩余 %s" % [
				"到" if stop else "通过",
				PLAN.format_clock(arrival_abs),
				PLAN.format_duration(remaining)]
		else:
			_next_label.text = "终点站"
			_time_label.text = "计划到点 %s" % PLAN.format_clock(departure_s + float(_schedule.get("total_time_s", 0.0)))
		var state := "走行中"
		if paused:
			state = "调度暂停"
		_offset_label.text = "当前时刻 %s · %s · 里程 %.2f / %.2f km" % [
			PLAN.format_clock(now_abs),
			state,
			mileage / 1000.0,
			float(_schedule.get("route_length_m", 0.0)) / 1000.0]
