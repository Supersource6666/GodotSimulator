extends Button
## Reference-style circular ON/OFF selector with keyboard accessibility.
var caption := ""

func _ready() -> void:
	toggle_mode = true
	custom_minimum_size = Vector2(220, 42)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	toggled.connect(func(_value: bool): queue_redraw())
	tooltip_text = "显示 / 隐藏" + caption + "图窗"

func _draw() -> void:
	var color := Color("#15212a")
	if is_hovered():
		draw_rect(Rect2(Vector2.ZERO,size),Color(1,1,1,0.18))
	var center := Vector2(19,size.y*0.5)
	draw_arc(center,11,0,TAU,40,color,1.7,true)
	if button_pressed:
		draw_polyline(PackedVector2Array([center+Vector2(-6,0),center+Vector2(-1,5),center+Vector2(7,-6)]),color,2,true)
	draw_string(get_theme_default_font(),Vector2(36, size.y*0.5+6),("ON  " if button_pressed else "OFF  ")+caption,HORIZONTAL_ALIGNMENT_LEFT,-1,18,color)
