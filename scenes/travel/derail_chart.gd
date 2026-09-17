extends Control
## 脱轨系数曲线图窗（参考 DerailLineData.cs）。
## 读取 wheel_force.csv，按核心公式 drail = hf / vf = 横向力 / 垂向力
## 计算并绘制 4 个轮对 × 左右轮共 8 条脱轨系数曲线。
## 白色主题；图例显示在曲线图内，点击图例项可勾选/取消对应曲线。

# 数据源与解析参数：子类可在 _ready 里（super._ready() 之前）覆盖，
# 以读取不同格式的动力学数据文件（逗号分隔 wheel_force.csv 或空格分隔 wx.dat）。
var data_path := "res://offline_data/dynamic_data/wheel_force.csv"
var plot_stride := 8  # 每 plot_stride 个数据行取 1 行用于绘制
var min_cols := 26
var time_col := 1
var space_separated := false
var skip_lines := 0
const TITLE_BAR_HEIGHT := 38.0  # 顶部可拖动标题栏高度
const CLOSE_BUTTON_SIZE := 24.0  # 标题栏右上角关闭按钮边长
const CLOSE_BUTTON_MARGIN := 8.0  # 关闭按钮距标题栏右侧边距
const COLORS := [
	Color("d32f2f"), Color("f57c00"), Color("f9a825"), Color("2e7d32"),
	Color("1976d2"), Color("7b1fa2"), Color("c2185b"), Color("00796b"),
]

var title_text := "脱轨系数曲线"
var channel_text := "8 通道 · 单位 1"
var y_axis_text := "脱轨系数 (1)"
var series_count := 8
var y_axis_format := "%.3f"
var error_text := ""
var sample_count := 0
var times := PackedFloat64Array()
var series: Array[PackedFloat64Array] = []
var labels := PackedStringArray()
var visible_flags: Array[bool] = []
var current_index := 0
var playing := true
var playback_rate := 160.0  # 实时回放速度（数据点/秒）
var _dragging := false
var _close_hover := false
var _legend_rects: Array[Rect2] = []
var _min_t := 0.0
var _max_t := 1.0
var _min_v := 0.0
var _max_v := 0.001


func _ready() -> void:
	var vp := get_viewport_rect().size
	size = Vector2(380, vp.y / 3.0)
	position = Vector2(maxf(vp.x - size.x - 1.0, 0.0), maxf(vp.y - size.y - 1.0, 0.0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	_load_data()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _close_button_rect().has_point(mb.position):
					# 关闭按钮：隐藏图窗，左上角勾选框经 visibility_changed 自动同步为 OFF。
					_dragging = false
					_close_hover = false
					mouse_default_cursor_shape = Control.CURSOR_ARROW
					hide()
				elif mb.position.y <= TITLE_BAR_HEIGHT:
					_dragging = true
				else:
					_toggle_legend_at(mb.position)
			else:
				_dragging = false
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			position += motion.relative
			return
		var hover := _close_button_rect().has_point(motion.position)
		if hover != _close_hover:
			_close_hover = hover
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover else Control.CURSOR_ARROW
			queue_redraw()


func _on_mouse_exited() -> void:
	if not _close_hover:
		return
	_close_hover = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


# 标题栏（拖拽区）右上角的关闭按钮矩形。
func _close_button_rect() -> Rect2:
	var origin := Vector2(
		size.x - CLOSE_BUTTON_SIZE - CLOSE_BUTTON_MARGIN,
		(TITLE_BAR_HEIGHT - CLOSE_BUTTON_SIZE) * 0.5)
	return Rect2(origin, Vector2(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE))


func _toggle_legend_at(pos: Vector2) -> void:
	for index in range(_legend_rects.size()):
		if _legend_rects[index].has_point(pos):
			visible_flags[index] = not visible_flags[index]
			queue_redraw()
			break


func _load_data() -> void:
	error_text = ""
	sample_count = 0
	times.clear()
	series.clear()
	visible_flags.clear()
	labels = _make_labels()
	for i in range(series_count):
		series.append(PackedFloat64Array())
		visible_flags.append(true)
	if not FileAccess.file_exists(data_path):
		error_text = "缺少数据文件：" + data_path
		queue_redraw()
		return
	var file := FileAccess.open(data_path, FileAccess.READ)
	if file == null:
		error_text = "无法打开数据文件：" + data_path
		queue_redraw()
		return
	# 跳过表头行（按原始字节读到换行，避免 GBK 中文表头触发 UTF-8 解码告警）。
	for _i in range(skip_lines):
		while not file.eof_reached():
			if file.get_8() == 0x0A:
				break
	var data_index := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		var cols: PackedStringArray
		if space_separated:
			cols = line.split(" ", false)
		else:
			cols = line.split(",")
		if cols.size() < min_cols:
			continue
		if data_index % plot_stride == 0:
			times.append(cols[time_col].to_float())
			_process_row(cols)
		data_index += 1
	file.close()
	sample_count = data_index
	if sample_count == 0:
		error_text = "数据为空"
	_recompute_bounds()
	queue_redraw()


func set_progress(frac: float) -> void:
	if times.size() < 2:
		return
	playing = false
	current_index = clampi(int(frac * float(times.size() - 1)), 0, times.size() - 1)
	queue_redraw()


func set_playing(value: bool) -> void:
	playing = value


func _process_row(cols: PackedStringArray) -> void:
	# 默认：脱轨系数 drail = Fy / Fz（4 轮对 × 左右轮，共 8 条）
	for k in range(4):
		# 每轮对 6 值：[左轮Fx, 左轮Fy, 左轮Fz, 右轮Fx, 右轮Fy, 右轮Fz]
		var fy_l := cols[2 + 6 * k + 1].to_float()
		var fz_l := cols[2 + 6 * k + 2].to_float()
		var fy_r := cols[2 + 6 * k + 4].to_float()
		var fz_r := cols[2 + 6 * k + 5].to_float()
		series[k].append(_safe_div(fy_l, fz_l))
		series[k + 4].append(_safe_div(fy_r, fz_r))


func _make_labels() -> PackedStringArray:
	var result := PackedStringArray()
	for k in range(1, 5):
		result.append("轴%d 左轮" % k)
	for k in range(1, 5):
		result.append("轴%d 右轮" % k)
	return result


func _safe_div(numerator: float, denominator: float) -> float:
	if absf(denominator) < 0.001:
		return numerator / (0.001 if denominator >= 0.0 else -0.001)
	return numerator / denominator


func _recompute_bounds() -> void:
	if times.is_empty():
		return
	_min_t = times[0]
	_max_t = times[times.size() - 1]
	if _max_t <= _min_t:
		_max_t = _min_t + 1.0
	_min_v = INF
	_max_v = -INF
	for curve in series:
		for value in curve:
			_min_v = minf(_min_v, float(value))
			_max_v = maxf(_max_v, float(value))
	if _max_v <= _min_v:
		_max_v = _min_v + 0.001
	var pad := (_max_v - _min_v) * 0.08
	_min_v -= pad
	_max_v += pad


func _plot_rect() -> Rect2:
	return Rect2(Vector2(54.0, 96.0), Vector2(maxf(size.x - 68.0, 10.0), maxf(size.y - 137.0, 10.0)))


func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.985, 0.99, 1.0, 0.98)
	style.border_color = Color(0.78, 0.82, 0.86, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style


func _draw_close_button() -> void:
	var rect := _close_button_rect()
	if _close_hover:
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.87, 0.90, 0.93, 1.0)
		hover.set_corner_radius_all(6)
		draw_style_box(hover, rect)
	var color := Color("#c62828") if _close_hover else Color("#4a5a66")
	var center := rect.get_center()
	var arm := 5.0
	draw_line(center + Vector2(-arm, -arm), center + Vector2(arm, arm), color, 1.8, true)
	draw_line(center + Vector2(-arm, arm), center + Vector2(arm, -arm), color, 1.8, true)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_style_box(_window_style(), Rect2(Vector2.ZERO, size))
	# 标题栏（可拖动）
	var header := StyleBoxFlat.new()
	header.bg_color = Color(0.93, 0.95, 0.97, 0.98)
	header.corner_radius_top_left = 10
	header.corner_radius_top_right = 10
	draw_style_box(header, Rect2(1, 1, size.x - 2, TITLE_BAR_HEIGHT - 1))
	draw_line(Vector2(16, 14), Vector2(16, 25), COLORS[4], 2)
	draw_polyline(PackedVector2Array([Vector2(16,22),Vector2(21,18),Vector2(26,24),Vector2(31,13)]),COLORS[4],1.5,true)
	draw_line(Vector2(0.0, TITLE_BAR_HEIGHT), Vector2(size.x, TITLE_BAR_HEIGHT), Color(0.85, 0.88, 0.90), 1.0)
	draw_string(font, Vector2(40.0, 25.0), title_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("#1f2a33"))
	# 通道说明右对齐，为右上角关闭按钮留出位置。
	draw_string(font, Vector2(size.x - CLOSE_BUTTON_SIZE - CLOSE_BUTTON_MARGIN - 142.0, 25), channel_text,
		HORIZONTAL_ALIGNMENT_RIGHT, 130.0, 11, Color("#5a6b78"))
	_draw_close_button()
	if not error_text.is_empty():
		draw_string(font, Vector2(120.0, 120.0), error_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#c62828"))
		return
	if times.size() < 2:
		draw_string(font, Vector2(120.0, 120.0), "无数据",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#5a6b78"))
		return

	var plot := _plot_rect()
	draw_rect(plot, Color(1.0, 1.0, 1.0, 0.96), true)
	draw_rect(plot, Color(0.78, 0.82, 0.86), false, 1.0)

	# 网格 + X 轴（时间）刻度
	var cols := 6
	for i in range(cols + 1):
		var frac := float(i) / float(cols)
		var x := plot.position.x + plot.size.x * frac
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(0.86, 0.88, 0.90, 0.8), 1.0)
		var t_label := lerpf(_min_t, _max_t, frac)
		draw_string(font, Vector2(x - 22.0, plot.end.y + 18.0), "%.2f" % t_label,
			HORIZONTAL_ALIGNMENT_CENTER, 44.0, 10, Color(0.42, 0.48, 0.54))
	# X 轴名称
	draw_string(font, Vector2(plot.position.x, size.y - 13.0), "时间 (s)",
		HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, 11, Color(0.40, 0.46, 0.52))

	# 网格 + Y 轴（脱轨系数）刻度
	var rows := 5
	for i in range(rows + 1):
		var frac := float(i) / float(rows)
		var y := plot.position.y + plot.size.y * (1.0 - frac)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(0.86, 0.88, 0.90, 0.8), 1.0)
		var v_label := lerpf(_min_v, _max_v, frac)
		draw_string(font, Vector2(4.0, y + 4.0), y_axis_format % v_label,
			HORIZONTAL_ALIGNMENT_RIGHT, plot.position.x - 12.0, 11, Color(0.42, 0.48, 0.54))
	# 零线
	var zero_y := plot.position.y + plot.size.y * (1.0 - clampf((0.0 - _min_v) / (_max_v - _min_v), 0.0, 1.0))
	if _min_v <= 0.0 and _max_v >= 0.0:
		draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), Color(0.55, 0.60, 0.65, 0.7), 1.0)

	# 曲线（直接渲染全部，跳过隐藏的）
	for index in range(series.size()):
		if not visible_flags[index]:
			continue
		var curve: PackedFloat64Array = series[index]
		if curve.size() < 2:
			continue
		var points := PackedVector2Array()
		for i in range(curve.size()):
			var t := float(times[i]) if i < times.size() else 0.0
			var x := plot.position.x + plot.size.x * clampf((t - _min_t) / (_max_t - _min_t), 0.0, 1.0)
			var y := plot.position.y + plot.size.y * (1.0 - clampf((float(curve[i]) - _min_v) / (_max_v - _min_v), 0.0, 1.0))
			points.append(Vector2(x, y))
		draw_polyline(points, COLORS[index % COLORS.size()], 1.5, true)

	# 图例（曲线图内顶部，可点击勾选）
	_legend_rects.clear()
	var legend_cols := 4
	var item_w := (size.x - 28.0) / float(legend_cols)
	for index in range(labels.size()):
		var row := index / legend_cols
		var col := index % legend_cols
		var rect := Rect2(14.0 + col * item_w, 43.0 + row * 19.0, item_w - 5.0, 17.0)
		_legend_rects.append(rect)
		var color: Color = COLORS[index % COLORS.size()]
		var on: bool = visible_flags[index]
		var chip := StyleBoxFlat.new()
		chip.bg_color = Color(0.93, 0.95, 0.97, 0.9) if on else Color(0.96, 0.97, 0.98, 0.9)
		chip.set_corner_radius_all(4)
		draw_style_box(chip, rect)
		draw_line(rect.position + Vector2(5, 8), rect.position + Vector2(16, 8), color if on else Color("#c0c6cc"), 2)
		var text_color: Color = color if on else Color(0.70, 0.74, 0.78)
		draw_string(font, rect.position + Vector2(20, 12), labels[index],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, text_color)
	draw_string(font, Vector2(16, 88), y_axis_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#5a6b78"))
	draw_string(font, Vector2(size.x - 155, 88), "点击图例显示 / 隐藏曲线",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8a96a1"))
