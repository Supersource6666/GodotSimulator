extends Control

const REGISTRY := preload("res://app/scene_registry.gd")
var registry := REGISTRY.new()
var status: Label

func _ready() -> void:
	registry.discover()
	var background := ColorRect.new()
	background.color = Color("152532")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	column.custom_minimum_size.x = 460
	center.add_child(column)
	var title := Label.new()
	title.text = "选择本地场景"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	for entry in registry.entries:
		var button := Button.new()
		button.text = entry.title
		if not str(entry.description).is_empty():
			button.text += "  ·  " + str(entry.description)
		button.custom_minimum_size.y = 76
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_open_entry.bind(entry))
		column.add_child(button)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status)
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
