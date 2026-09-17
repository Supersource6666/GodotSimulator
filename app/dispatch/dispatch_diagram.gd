extends Control
## 列车运行图（时间—里程图）。
## 横轴为时刻，纵轴为里程；车站画水平参考线，列车运行线由调度方案的五彩采样点直接绘制，
## 与三维场景实际走的曲线是同一组数据，因此运行图就是"计划"本身。

const PLAN := preload("res://app/dispatch/dispatch_plan.gd")
const PADDING_LEFT := 108.0
const PADDING_RIGHT := 64.0
const PADDING_TOP := 20.0
const PADDING_BOTTOM := 30.0
const BACKGROUND := Color("0b1a24")
const GRID := Color(0.28, 0.42, 0.52, 0.35)
const STATION_LINE := Color(0.55, 0.72, 0.85, 0.55)
const RUN_LINE := Color("ffc86b")

var schedule: Dictionary = {}
var departure_s := 0.0
var highlight_time := -1.0
var title := "列车运行图（横轴 时刻 / 纵轴 里程）"


func set_schedule(new_schedule: Dictionary, departure_seconds: float) -> void:
	schedule = new_schedule
	departure_s = departure_seconds
	queue_redraw()


func set_highlight_time(time_s: float) -> void:
	if is_equal_approx(highlight_time, time_s):
		return
	highlight_time = time_s
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := 11
	var plot := Rect2(Vector2(PADDING_LEFT, PADDING_TOP),
		Vector2(maxf(size.x - PADDING_LEFT - PADDING_RIGHT, 10.0),
			maxf(size.y - PADDING_TOP - PADDING_BOTTOM, 10.0)))
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
	if schedule.is_empty():
		draw_string(font, Vector2(PADDING_LEFT, plot.position.y + 26.0), "暂无运行图数据",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.78, 0.84))
		return

	var route_length := maxf(float(schedule.get("route_length_m", 0.0)), 1.0)
	var total_time := maxf(float(schedule.get("total_time_s", 0.0)), 1.0)
	var time_min := 0.0
	var time_max := total_time
	draw_rect(plot, Color(0.02, 0.05, 0.07, 0.6), true)

	# 时间网格：按总时长自动选择刻度（30 秒 / 1 分 / 5 分）。
	var tick := 30.0
	if total_time > 900.0:
		tick = 300.0
	elif total_time > 300.0:
		tick = 60.0
	var tick_time := 0.0
	while tick_time <= time_max + 0.001:
		var x := plot.position.x + plot.size.x * (tick_time - time_min) / (time_max - time_min)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.position.y + plot.size.y), GRID, 1.0)
		draw_string(font, Vector2(x - 18.0, plot.position.y + plot.size.y + 16.0),
			PLAN.format_short_clock(departure_s + tick_time),
			HORIZONTAL_ALIGNMENT_CENTER, 36.0, font_size, Color(0.68, 0.78, 0.85))
		tick_time += tick

	# 里程网格：每 1 km。
	var kilometer := 1000.0
	while kilometer < route_length:
		var y := plot.position.y + plot.size.y * (1.0 - kilometer / route_length)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.position.x + plot.size.x, y), GRID, 1.0)
		draw_string(font, Vector2(plot.position.x + 4.0, y - 4.0), "%.0f km" % (kilometer / 1000.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 1, Color(0.55, 0.65, 0.72))
		kilometer += 1000.0

	# 车站参考线与站名（含停车/通过标记）。
	for station in schedule.get("stations", []):
		var chainage := float(station.get("chainage_m", 0.0))
		var y := plot.position.y + plot.size.y * (1.0 - chainage / route_length)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.position.x + plot.size.x, y), STATION_LINE, 1.0)
		var marker := "●" if bool(station.get("stop", true)) else "○"
		draw_string(font, Vector2(PADDING_LEFT - 100.0, y - 4.0),
			"%s %s" % [marker, str(station.get("name", ""))],
			HORIZONTAL_ALIGNMENT_LEFT, 98.0, font_size + 1, Color(0.85, 0.92, 0.97))

	# 运行线。
	var xs: PackedFloat64Array = schedule.get("samples_x", PackedFloat64Array())
	var ts: PackedFloat64Array = schedule.get("samples_t", PackedFloat64Array())
	if ts.size() >= 2:
		var points := PackedVector2Array()
		for index in range(ts.size()):
			var time := clampf(float(ts[index]), time_min, time_max)
			var x := plot.position.x + plot.size.x * (time - time_min) / (time_max - time_min)
			var y := plot.position.y + plot.size.y * (1.0 - clampf(float(xs[index]), 0.0, route_length) / route_length)
			points.append(Vector2(x, y))
		draw_polyline(points, RUN_LINE, 2.0, true)
		# 车站到点（或通过时刻）。
		for station in schedule.get("stations", []):
			var moment := float(station.get("departure_s", 0.0)) \
				if bool(station.get("stop", true)) else float(station.get("time_s", 0.0))
			var dot_x := plot.position.x + plot.size.x \
				* (clampf(moment, time_min, time_max) - time_min) / (time_max - time_min)
			var dot_y := plot.position.y + plot.size.y \
				* (1.0 - clampf(float(station.get("chainage_m", 0.0)), 0.0, route_length) / route_length)
			draw_circle(Vector2(dot_x, dot_y), 3.0, RUN_LINE)

	if highlight_time >= 0.0 and highlight_time <= total_time:
		var x := plot.position.x + plot.size.x * (highlight_time - time_min) / (time_max - time_min)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.position.y + plot.size.y),
			Color(0.35, 0.9, 1.0, 0.85), 1.5)

	draw_string(font, Vector2(plot.position.x, 14.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 1, Color(0.62, 0.75, 0.83))
	draw_string(font, Vector2(plot.position.x + plot.size.x - 150.0, 14.0),
		"● 停车  ○ 通过", HORIZONTAL_ALIGNMENT_LEFT, 150.0, font_size, Color(0.62, 0.75, 0.83))
