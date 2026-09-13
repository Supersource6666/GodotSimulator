extends Control

var fraction := 0.0
var angle := 0.0
var stopped := false
var heading: Label
var percentage: Label
var detail: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	heading = _make_label(-142.0, 36.0, 24)
	heading.text = "正在加载离线场景"
	percentage = _make_label(-40.0, 80.0, 30)
	detail = _make_label(102.0, 100.0, 18)
	set_progress(0, 0)

func _make_label(top: float, height: float, font_size: int) -> Label:
	var item := Label.new()
	add_child(item)
	item.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	item.offset_left = -300.0
	item.offset_right = 300.0
	item.offset_top = top
	item.offset_bottom = top + height
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", Color("e8f4ff"))
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func set_progress(completed: int, total: int) -> void:
	fraction = clampf(float(completed) / float(total), 0.0, 1.0) if total > 0 else 0.0
	percentage.text = "%d%%" % floori(fraction * 100.0)
	if total <= 0:
		detail.text = "正在检查本地资源…"
	elif completed < total:
		detail.text = "资源加载：%d / %d" % [completed, total]
	else:
		detail.text = "资源加载：%d / %d\n正在准备轨道与场景…" % [completed, total]
	queue_redraw()

func show_error(message: String) -> void:
	stopped = true
	heading.text = "离线场景加载失败"
	percentage.text = "!"
	detail.text = message
	queue_redraw()

func finish() -> void:
	hide()
	set_process(false)

func _process(delta: float) -> void:
	if not stopped:
		angle = fposmod(angle + delta * TAU * 0.8, TAU)
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.028, 0.045, 0.93))
	draw_arc(center, 72.0, 0.0, TAU, 128, Color("263d51"), 7.0, true)
	var accent := Color("ff8b83") if stopped else Color("50c9ff")
	if fraction > 0.0:
		draw_arc(center, 72.0, -PI * 0.5, -PI * 0.5 + fraction * TAU, 128, accent, 7.0, true)
	if not stopped:
		draw_arc(center, 86.0, angle, angle + TAU * 0.24, 48, Color("a4e5ff"), 3.0, true)