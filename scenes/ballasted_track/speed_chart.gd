extends Control
## Lightweight rolling speed plot for the realtime railway scene.

@export_range(10.0, 300.0, 5.0) var history_seconds := 60.0
@export_range(0.02, 1.0, 0.01) var sample_interval_s := 0.10

var _samples: Array[Vector2] = []
var _current_speed_kmh := 0.0
var _cab_view := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(430.0, 220.0)
	queue_redraw()


func add_sample(simulation_time_s: float, speed_mps: float) -> void:
	_current_speed_kmh = maxf(speed_mps, 0.0) * 3.6
	if not _samples.is_empty() and simulation_time_s < _samples[-1].x:
		_samples.clear()
	if not _samples.is_empty() and simulation_time_s - _samples[-1].x < sample_interval_s:
		queue_redraw()
		return
	_samples.append(Vector2(simulation_time_s, _current_speed_kmh))
	var cutoff := simulation_time_s - history_seconds
	while _samples.size() > 1 and _samples[1].x < cutoff:
		_samples.pop_front()
	queue_redraw()


func set_cab_view(enabled: bool) -> void:
	_cab_view = enabled
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.018, 0.045, 0.052, 0.90), true)
	draw_rect(bounds.grow(-1.0), Color(0.34, 0.58, 0.60, 0.72), false, 1.0)
	var font := get_theme_default_font()
	var title := "SPEED CURVE  |  %6.1f km/h" % _current_speed_kmh
	if _cab_view:
		title += "  |  CAB"
	draw_string(font, Vector2(16.0, 24.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color("e8f4ed"))

	var plot := Rect2(Vector2(54.0, 38.0), Vector2(maxf(size.x - 70.0, 40.0),
		maxf(size.y - 70.0, 40.0)))
	var peak := 0.0
	for sample in _samples:
		peak = maxf(peak, sample.y)
	var speed_max := maxf(40.0, ceil(maxf(peak, _current_speed_kmh) / 20.0) * 20.0)
	for line in range(5):
		var fraction := float(line) / 4.0
		var y := plot.end.y - plot.size.y * fraction
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y),
			Color(0.42, 0.58, 0.58, 0.24), 1.0)
		draw_string(font, Vector2(7.0, y + 5.0), "%3.0f" % (speed_max * fraction),
			HORIZONTAL_ALIGNMENT_RIGHT, 39.0, 12, Color("a9bdba"))
	for line in range(7):
		var fraction := float(line) / 6.0
		var x := plot.position.x + plot.size.x * fraction
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y),
			Color(0.42, 0.58, 0.58, 0.16), 1.0)
		var seconds_ago := history_seconds * (1.0 - fraction)
		draw_string(font, Vector2(x - 17.0, plot.end.y + 18.0), "-%02d" % int(seconds_ago),
			HORIZONTAL_ALIGNMENT_CENTER, 34.0, 11, Color("8ea5a2"))
	if _samples.size() < 2:
		draw_string(font, plot.get_center() + Vector2(-62.0, 4.0), "Waiting for realtime speed...",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("91aaa6"))
		return
	var latest_time := _samples[-1].x
	var earliest_time := latest_time - history_seconds
	var points := PackedVector2Array()
	for sample in _samples:
		var x_fraction := clampf((sample.x - earliest_time) / history_seconds, 0.0, 1.0)
		var y_fraction := clampf(sample.y / speed_max, 0.0, 1.0)
		points.append(Vector2(plot.position.x + plot.size.x * x_fraction,
			plot.end.y - plot.size.y * y_fraction))
	draw_polyline(points, Color("55e39a"), 2.4, true)
	draw_circle(points[-1], 3.8, Color("e7d34e"))
