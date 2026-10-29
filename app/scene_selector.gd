extends Control

const REGISTRY := preload("res://app/scene_registry.gd")
var registry := REGISTRY.new()
var status: Label
var selected_entry: Dictionary = {}
var module_buttons: Array[Button] = []
var detail_title: Label
var detail_description: Label
var detail_code: Label
var dispatch_detail: Label
var clock_label: Label
var launch_button: Button
var preview_button: Button
const INK := Color("dce7ed")
const MUTED := Color("8ea4b4")
const ACCENT := Color("e9b45c")

func _ready() -> void:
	registry.discover()
	_build_hmi()
	# Keep the prediction receiver active; its scene overlay belongs in the simulation.
	var prediction := get_node_or_null("/root/DDPMPrediction") as CanvasLayer
	if prediction != null:
		prediction.visible = false
		tree_exiting.connect(func() -> void: prediction.visible = true)
	if not registry.errors.is_empty():
		_show_error("\n".join(registry.errors))
		return
	if registry.entries.is_empty():
		_show_error("没有可用场景，请检查 scenes 下的 scene.cfg。")
		return
	var selected := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--local-scene="):
			selected = arg.trim_prefix("--local-scene=")
	if selected.is_empty() and "--demo-smoke-test" in OS.get_cmdline_user_args():
		selected = registry.default_id()
	if not selected.is_empty():
		var entry := registry.resolve(selected)
		if entry.is_empty():
			_show_error("未知场景：" + selected)
		else:
			_open_entry.call_deferred(entry)
	if "--hmi-capture" in OS.get_cmdline_user_args():
		_capture_hmi.call_deferred()
	if "--hmi-smoke-test" in OS.get_cmdline_user_args():
		var ok := module_buttons.size() == registry.entries.size() and not selected_entry.is_empty()
		for item in registry.entries:
			_select_module(item)
			ok = ok and detail_title.text == str(item.title)
		print("HMI_SELECTOR_SMOKE ", "PASS" if ok else "FAIL")
		get_tree().quit(0 if ok else 1)

func _style(fill: Color, border: Color, padding: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func _label(parent: Node, text: String, size: int = 16, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("15212b") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("15212b") if primary else Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(ACCENT if primary else Color("1a2a37"), ACCENT if primary else Color("354b5c"), 12))
	button.add_theme_stylebox_override("hover", _style(Color("f4c77f") if primary else Color("283e4f"), ACCENT, 12))
	button.add_theme_stylebox_override("pressed", _style(Color("cc9946") if primary else Color("334c5c"), ACCENT, 12))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color("65c6cd"), 12))
	parent.add_child(button)
	return button

func _build_hmi() -> void:
	var background := ColorRect.new()
	background.color = Color("0d1720")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var branding := VBoxContainer.new()
	branding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(branding)
	_label(branding, "RAIL SIMULATOR   /   OPERATOR STATION", 13, Color("65c6cd"))
	_label(branding, "铁路仿真 · 综合控制台", 29)
	var indicators := VBoxContainer.new()
	header.add_child(indicators)
	_label(indicators, "●  本地工作站     /     场景选择", 14, Color("65c6cd"))
	clock_label = _label(indicators, "", 14, MUTED)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var divider := HSeparator.new()
	layout.add_child(divider)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var modules := VBoxContainer.new()
	modules.custom_minimum_size.x = 300
	modules.add_theme_constant_override("separation", 10)
	body.add_child(modules)
	_label(modules, "01  /  仿真模块", 19)
	_label(modules, "%02d 个本地模块 · 选择后查看任务" % registry.entries.size(), 13, MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modules.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for index in range(registry.entries.size()):
		var entry: Dictionary = registry.entries[index]
		var button := _button(list, "%02d    %s" % [index + 1, entry.title])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 49
		button.set_meta("module_id", entry.id)
		button.pressed.connect(_select_module.bind(entry))
		module_buttons.append(button)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("14222e"), Color("304352"), 24))
	body.add_child(panel)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 14)
	panel.add_child(detail)
	detail_code = _label(detail, "", 13, Color("65c6cd"))
	detail_title = _label(detail, "请选择模块", 32)
	detail_description = _label(detail, "", 17, MUTED)
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var diagram := Control.new()
	diagram.custom_minimum_size.y = 100
	diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diagram.draw.connect(func() -> void:
		var width := diagram.size.x
		var mid := diagram.size.y * 0.5
		for i in range(18):
			var x := width * float(i + 1) / 19.0
			diagram.draw_line(Vector2(x, mid - 23), Vector2(x, mid + 23), Color("2a4050"), 5.0)
		for offset in [-13.0, 13.0]:
			diagram.draw_line(Vector2(0, mid + offset), Vector2(width, mid + offset), Color("73919f"), 2.0)
		diagram.draw_line(Vector2(0, mid), Vector2(width * 0.68, mid), ACCENT, 3.0)
		diagram.draw_circle(Vector2(width * 0.68, mid), 6, ACCENT)
	)
	diagram.resized.connect(diagram.queue_redraw)
	detail.add_child(diagram)
	_label(detail, "02  /  作业准备", 18)
	dispatch_detail = _label(detail, "", 15, MUTED)
	dispatch_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(detail, "调度运行    选择车次与计划后进入场景\n直接预览    打开三维场景，检查线路与设备", 15, MUTED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	detail.add_child(actions)
	launch_button = _button(actions, "进入调度台  →", true)
	launch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_button.pressed.connect(func() -> void: _open_entry(selected_entry))
	preview_button = _button(actions, "直接预览")
	preview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_button.pressed.connect(func() -> void: _open_scene(str(selected_entry.path)))
	status = _label(layout, "就绪 · 请选择仿真模块", 14, Color("65c6cd"))
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	var help := _label(footer, "操作指引  /  点击选择模块   ·   Tab 切换焦点   ·   Enter 确认", 13, MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exit_button := _button(footer, "退出系统  /  Esc")
	exit_button.custom_minimum_size.y = 36
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	launch_button.disabled = registry.entries.is_empty()
	preview_button.disabled = registry.entries.is_empty()
	if not registry.entries.is_empty():
		var initial := registry.resolve(registry.default_id())
		_select_module(registry.entries[0] if initial.is_empty() else initial)
	_process(0)

func _select_module(entry: Dictionary) -> void:
	selected_entry = entry
	detail_title.text = str(entry.title)
	detail_description.text = str(entry.description)
	detail_code.text = "MODULE  /  " + str(entry.id).to_upper()
	dispatch_detail.text = "调度配置：线路配置可用" if not str(entry.dispatch_path).is_empty() else "调度配置：使用限速调度模式"
	status.text = "就绪 · 已选择「%s」" % entry.title
	for button in module_buttons:
		var active := str(button.get_meta("module_id")) == str(entry.id)
		button.add_theme_stylebox_override("normal", _style(Color("30352e") if active else Color("1a2a37"), ACCENT if active else Color("354b5c"), 12))
		button.add_theme_color_override("font_color", ACCENT if active else INK)

func _process(_delta: float) -> void:
	if clock_label != null:
		clock_label.text = Time.get_datetime_string_from_system().replace("T", "   ")

func _capture_hmi() -> void:
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("res://app/hmi_preview.png")
	print("HMI_CAPTURE ", error_string(error))
	get_tree().quit(0 if error == OK else 1)

func _show_error(message: String) -> void:
	status.text = message
	push_error(message)
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit(1)

func _open_entry(entry: Dictionary) -> void:
	# 冒烟测试与显式跳过时直接载入三维场景；否则先进入调度台。
	if _should_skip_dispatch():
		_open_scene(str(entry.path))
		return
	status.text = "正在打开调度台…"
	var context := get_node_or_null("/root/DispatchContext")
	if context != null:
		context.select_module(str(entry.id))
	var error := get_tree().change_scene_to_file("res://app/dispatch/dispatch_console.tscn")
	if error != OK:
		_show_error("调度台加载失败：" + error_string(error))


func _should_skip_dispatch() -> bool:
	return "--skip-dispatch" in OS.get_cmdline_user_args() \
		or "--demo-smoke-test" in OS.get_cmdline_user_args()


func _open_scene(path: String) -> void:
	status.text = "正在加载…"
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_show_error("场景加载失败：" + error_string(error))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			get_tree().quit()
