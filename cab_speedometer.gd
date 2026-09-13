extends Control
## Screen-space cab instrument driven by the sampled speed CSV profile.

const BASE_SIZE := Vector2(220.0, 272.0)
const DIAL_CENTER := Vector2(110.0, 106.0)
const DIAL_RADIUS := 91.0
const MAX_SPEED_KMH := 200.0

var speed_kmh := 0.0
var distance_km := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
	queue_redraw()


func set_reading(new_speed_kmh: float, new_distance_m: float) -> void:
	var next_speed := clampf(new_speed_kmh, 0.0, MAX_SPEED_KMH)
	var next_distance := maxf(new_distance_m, 0.0) / 1000.0
	if is_equal_approx(speed_kmh, next_speed) and is_equal_approx(distance_km, next_distance):
		return
	speed_kmh = next_speed
	distance_km = next_distance
	queue_redraw()


func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var factor := clampf(minf(viewport_size.x / 1280.0, viewport_size.y / 720.0), 0.70, 1.35)
	size = BASE_SIZE * factor
	position = Vector2(22.0 * factor, viewport_size.y - size.y - 74.0 * factor)
	queue_redraw()


func _draw() -> void:
	var factor := size.x / BASE_SIZE.x
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(factor, factor))
	# Compact translucent backing keeps the dial legible over the cab photograph.
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, BASE_SIZE))
	draw_circle(DIAL_CENTER, DIAL_RADIUS + 7.0, Color("#12171d"))
	draw_circle(DIAL_CENTER, DIAL_RADIUS + 2.0, Color("#a9adb0"))
	draw_circle(DIAL_CENTER, DIAL_RADIUS - 2.0, Color("#f2f0e7"))
	draw_arc(DIAL_CENTER, DIAL_RADIUS - 7.0, deg_to_rad(-225.0), deg_to_rad(45.0), 72, Color("#c3a55d"), 2.0, true)
	for value in range(0, 201, 10):
		var angle := _value_angle(float(value))
		var major := value % 20 == 0
		var outer := DIAL_CENTER + Vector2(cos(angle), sin(angle)) * (DIAL_RADIUS - 8.0)
		var inner_radius := DIAL_RADIUS - (19.0 if major else 14.0)
		var inner := DIAL_CENTER + Vector2(cos(angle), sin(angle)) * inner_radius
		draw_line(inner, outer, Color("#161616"), 2.2 if major else 1.2, true)
		if major:
			_draw_centered_text(str(value), DIAL_CENTER + Vector2(cos(angle), sin(angle)) * (DIAL_RADIUS - 31.0), 15, Color("#111111"))
	_draw_centered_text("km/h", Vector2(DIAL_CENTER.x, 151.0), 15, Color("#111111"))
	var needle_angle := _value_angle(speed_kmh)
	var needle_direction := Vector2(cos(needle_angle), sin(needle_angle))
	draw_line(DIAL_CENTER - needle_direction * 12.0, DIAL_CENTER + needle_direction * 61.0, Color("#301b0e"), 4.0, true)
	draw_circle(DIAL_CENTER, 9.0, Color("#2a2119"))
	draw_circle(DIAL_CENTER, 4.5, Color("#a88d55"))
	_draw_centered_text("%.1f km/h" % speed_kmh, Vector2(DIAL_CENTER.x, 211.0), 22, Color.WHITE)
	draw_string(_font, Vector2(20.0, 240.0), "DISTANCE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("#cbd1d7"))
	draw_rect(Rect2(20.0, 247.0, 5.0, 19.0), Color("#d45ac0"))
	draw_string(_font, Vector2(35.0, 265.0), "%.2f km" % distance_km, HORIZONTAL_ALIGNMENT_LEFT, 165.0, 22, Color.WHITE)


func _value_angle(value: float) -> float:
	return deg_to_rad(135.0 + clampf(value / MAX_SPEED_KMH, 0.0, 1.0) * 270.0)


func _draw_centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var ascent := _font.get_ascent(font_size)
	draw_string(_font, center + Vector2(-width * 0.5, ascent * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.045, 0.78)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	return style
