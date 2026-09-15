extends Control

const CITY := "res://offline.tscn"
const COUNTRYSIDE := "res://countryside.tscn"
var status: Label

func _ready() -> void:
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
	for option in [["市区内", "东京—品川", CITY], ["郊外", "大糸线 · 大町", COUNTRYSIDE]]:
		var button := Button.new()
		button.text = option[0] + "  ·  " + option[1]
		button.custom_minimum_size.y = 76
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_open_scene.bind(option[2]))
		column.add_child(button)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status)
	var selected := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--local-scene="):
			selected = arg.trim_prefix("--local-scene=")
	if selected.is_empty() and "--demo-smoke-test" in OS.get_cmdline_user_args():
		selected = "city"
	if selected in ["city", "countryside"]:
		_open_scene.call_deferred(CITY if selected == "city" else COUNTRYSIDE)
	elif not selected.is_empty():
		status.text = "未知场景：" + selected
		if "--demo-smoke-test" in OS.get_cmdline_user_args():
			get_tree().quit(1)

func _open_scene(path: String) -> void:
	status.text = "正在加载…"
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		status.text = "场景加载失败：" + error_string(error)
