extends Control
## Fixed design canvas scaled uniformly with the window; simulation remains full-screen.
const TEXT := Color("dce7ed")
const MUTED := Color("8ea4b4")
const CYAN := Color("65c6cd")
const AMBER := Color("e9b45c")
var scene: Node
var speed: Label
var prediction_text: Label
var receiver: CanvasLayer
var receiver_was_visible := true
var pause_button: Button

func style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.09, 0.125, 0.94)
	box.border_color = Color("354b5c")
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func label(parent: Node, text: String, font_size: int = 14, color: Color = TEXT) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	parent.add_child(item)
	return item

func panel_at(at: Vector2, extent: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.size = extent
	panel.add_theme_stylebox_override("panel", style())
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box

func place(item: Control, at: Vector2, extent: Vector2) -> void:
	item.reparent(self)
	item.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	item.custom_minimum_size = Vector2.ZERO
	item.position = at
	item.size = extent
	if item is PanelContainer:
		item.add_theme_stylebox_override("panel", style())
	item.add_theme_font_size_override("font_size", 13)
	item.add_theme_color_override("font_color", TEXT)

func action(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", style())
	var hover := style()
	hover.border_color = CYAN
	hover.bg_color = Color("263d4e")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func configure(owner_scene: Node, layer: CanvasLayer) -> void:
	scene = owner_scene
	name = "BallastedHMI"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(self)
	size = Vector2(1280, 720)
	var header := panel_at(Vector2(16, 14), Vector2(1248, 58))
	var row := HBoxContainer.new()
	header.add_child(row)
	var title := label(row, "有砟轨道 / 碎石道床", 23)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(row, "BALLASTED TRACK   /   运行监视", 14, CYAN)
	var back := action(row, "返回主界面", func() -> void: get_tree().change_scene_to_file("res://app/local.tscn"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	var map: Control = scene._mini_map
	place(map, Vector2(16, 84), Vector2(312, 242))
	var map_view := map.get("_map_view") as Control
	map_view.custom_minimum_size.y = 160
	var forward_one := panel_at(Vector2(16, 338), Vector2(312, 156))
	label(forward_one, "01 / DDPM 独立预测", 14, CYAN)
	prediction_text = label(forward_one, "等待预测数据", 12, MUTED)
	prediction_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	receiver = get_node_or_null("/root/DDPMPrediction") as CanvasLayer
	if receiver != null:
		receiver_was_visible = receiver.visible
		receiver.visible = false
	place(scene._prediction_hud, Vector2(16, 506), Vector2(312, 162))
	place(scene._speed_chart, Vector2(944, 442), Vector2(320, 226))
	place(scene._info_panel, Vector2(344, 94), Vector2(584, 170))
	var info_label := scene._info_panel.get_child(0) as Label
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 14)
	var old_console := layer.get_node_or_null("TrainControlConsole")
	if old_console != null:
		# Reuse the connected source selector and status label; keep simulation callbacks intact.
		var box := panel_at(Vector2(944, 84), Vector2(320, 346))
		label(box, "02 / 列车控制", 14, CYAN)
		speed = label(box, "0.0  km/h", 34, TEXT)
		scene._source_option.reparent(box)
		scene._source_option.add_theme_font_size_override("font_size", 13)
		scene._source_option.custom_minimum_size.y = 34
		scene._source_option.set_item_text(0, "外部仿真 / UDP")
		scene._source_option.set_item_text(1, "本地驾驶 / 键盘")
		scene._control_status_label.reparent(box)
		scene._control_status_label.add_theme_font_size_override("font_size", 13)
		scene._control_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var buttons := HBoxContainer.new()
		box.add_child(buttons)
		pause_button = action(buttons, "暂停 / 继续", scene._toggle_train_pause)
		action(buttons, "重启", scene._restart_train_from_route_start)
		label(box, "W 牵引  /  S 制动  /  松开惰行\nSpace 暂停  ·  R 重启\nC / 6 司机室  ·  V 速度曲线", 13, MUTED)
		old_console.queue_free()
	var footer := panel_at(Vector2(16, 680), Vector2(1248, 28))
	# Slim footer has smaller margins than the instrumentation panels.
	var footer_style := style()
	footer_style.content_margin_top = 3
	footer_style.content_margin_bottom = 3
	footer.get_parent().add_theme_stylebox_override("panel", footer_style)
	var footer_row := HBoxContainer.new()
	footer.add_child(footer_row)
	var hint := label(footer_row, "双线电气化  /  19 节编组     ·     F1 场景说明     ·     Esc 返回主界面", 12, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(footer_row, "SIMULATION / LOCAL", 12, CYAN)
	get_viewport().size_changed.connect(_resize)
	_resize()
	_settle_layout.call_deferred()
	tree_exiting.connect(_restore_receiver)

func _settle_layout() -> void:
	# Containers recalculate their minimum sizes after reparenting and font changes.
	for i in range(2):
		await get_tree().process_frame
	scene._mini_map.size = Vector2(312, 242)
	scene._prediction_hud.size = Vector2(312, 162)

func _resize() -> void:
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	scale = Vector2.ONE * factor
	position = (viewport_size - Vector2(1280, 720) * factor) * 0.5

func _restore_receiver() -> void:
	if is_instance_valid(receiver):
		receiver.visible = receiver_was_visible

func _process(_delta: float) -> void:
	if not is_instance_valid(scene):
		return
	if speed != null:
		var speed_mps: float = scene._keyboard_driver.speed_mps if scene._input_source == "keyboard" else float(scene._target_stream_state.get("speed_m_s", 0.0))
		var live: bool = scene._input_source == "keyboard" or (scene._has_stream_state and Time.get_ticks_usec() - scene._last_stream_receive_usec <= 1000000)
		speed.text = "%.1f  km/h" % (speed_mps * 3.6) if live else "—  km/h"
		speed.add_theme_color_override("font_color", TEXT if live else AMBER)
		scene._update_control_status(speed_mps)
		pause_button.text = "继续运行" if scene._train_paused else "暂停运行"
	if receiver != null and receiver.get_child_count() > 0:
		var original: Label = receiver.get_child(0).get_child(0)
		prediction_text.text = original.text.trim_prefix("DDPM forward_01 预测\n")
		prediction_text.add_theme_color_override("font_color", CYAN if receiver.valid else AMBER)
