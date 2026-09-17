extends Control
## 列车调度台（加载三维场景前的中转界面）。
##
## 参照 Libre TrainSim 的"选线路 → 编车次/时刻表 → 载入场景"流程，提供：
##   - 左侧：列车运行配置（种别 / 车次 / 编组 / 方向 / 出发时刻 / 限速）
##   - 中间：车站时刻表（到点 / 发点 / 停车-通过 / 股道）
##   - 右侧：运行概要、前置检查与调度日志
##   - 底部：列车运行图（时间—里程图）与发车操作
##
## 确认发车后，方案写入 DispatchContext 单例，再载入对应模块的三维场景，
## 场景按同一份方案运行。

const REGISTRY := preload("res://app/scene_registry.gd")
const PLAN := preload("res://app/dispatch/dispatch_plan.gd")
const DIAGRAM := preload("res://app/dispatch/dispatch_diagram.gd")

var _registry := REGISTRY.new()
var _entry: Dictionary = {}
var _module_id := ""
var _dispatch_config: Dictionary = {}
var _plan: Dictionary = {}
var _schedule: Dictionary = {}

var _table_header: HBoxContainer
var _table_body: VBoxContainer
var _rows: Array[Dictionary] = []
var _empty_table_label: Label
var _summary: Label
var _checklist: Label
var _log_view: RichTextLabel
var _diagram: Control
var _launch_button: Button
var _route_title: Label
var _direction_warning: Label
var _direction_option: OptionButton

var _service_option: OptionButton
var _number_edit: LineEdit
var _car_option: OptionButton
var _hour_spin: SpinBox
var _minute_spin: SpinBox
var _speed_spin: SpinBox
var _dispatcher_edit: LineEdit
var _note_edit: LineEdit

var _updating := false


func _ready() -> void:
	_registry.discover()
	_module_id = _resolve_module_id()
	var entry := _registry.resolve(_module_id)
	if entry.is_empty():
		_show_fatal("未知模块：" + _module_id)
		return
	_entry = entry
	_dispatch_config = _registry.load_dispatch(entry)
	_plan = PLAN.default_plan(_module_id, _dispatch_config)
	_apply_cli_overrides()
	_build_ui()
	_recompute()
	_log_plan_ready()
	if "--dispatch-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_smoke_test")
	elif "--demo-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_on_launch")


func _resolve_module_id() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dispatch="):
			return arg.trim_prefix("--dispatch=").strip_edges().to_lower()
		if arg.begins_with("--local-scene="):
			return arg.trim_prefix("--local-scene=").strip_edges().to_lower()
	var context := get_node_or_null("/root/DispatchContext")
	if context != null and not str(context.pending_module).is_empty():
		return context.take_module()
	return str(ProjectSettings.get_setting("application/local_scenes/default_id", "urban"))


func _apply_cli_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--train-number="):
			_plan["number"] = arg.trim_prefix("--train-number=").strip_edges()
		elif arg.begins_with("--departure="):
			var parsed := PLAN.parse_short_clock(arg.trim_prefix("--departure="))
			if parsed >= 0.0:
				_plan["departure_s"] = parsed


# ── UI 构建 ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("0d1c27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_build_header())

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 10)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main_row)

	var left := _build_config_panel()
	left.custom_minimum_size.x = 300.0
	main_row.add_child(left)

	var middle := _build_table_panel()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.add_child(middle)

	var right := _build_dispatch_panel()
	right.custom_minimum_size.x = 316.0
	main_row.add_child(right)

	var diagram_panel := _make_panel("")
	diagram_panel.custom_minimum_size.y = 180.0
	root.add_child(diagram_panel)
	_diagram = DIAGRAM.new()
	_diagram.name = "TrainDiagram"
	_diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diagram_panel.get_node("Body").add_child(_diagram)

	root.add_child(_build_action_bar())


func _build_header() -> PanelContainer:
	var panel := _make_panel("")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.get_node("Body").add_child(row)
	var title := Label.new()
	title.text = "列车调度台  ·  Train Dispatching"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#f3f9ff"))
	row.add_child(title)
	_route_title = Label.new()
	_route_title.text = ""
	_route_title.add_theme_font_size_override("font_size", 16)
	_route_title.add_theme_color_override("font_color", Color("#9fc3dd"))
	_route_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_route_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_route_title)
	return panel


func _build_config_panel() -> PanelContainer:
	var panel := _make_panel("运行配置")
	var panel_body: VBoxContainer = panel.get_node("Body")
	# 配置项较多，非全屏窗口高度有限时用纵向滚动避免字段被裁切。
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_body.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_service_option = OptionButton.new()
	for service in _dispatch_config.get("services", []):
		if service is Dictionary:
			_service_option.add_item(str(service.get("name", "")), _service_option.item_count)
	body.add_child(_label_row("列车种别", _service_option))
	_service_option.item_selected.connect(_on_service_changed)

	_number_edit = LineEdit.new()
	_number_edit.text = str(_plan.get("number", "1"))
	_number_edit.placeholder_text = "例如 301"
	body.add_child(_label_row("车次", _number_edit))
	_number_edit.text_changed.connect(func(_text): _on_plan_edited())

	_car_option = OptionButton.new()
	for cars in [2, 4, 8, 12, 16]:
		_car_option.add_item("%d 辆编组" % cars, cars)
	body.add_child(_label_row("编组", _car_option))
	_car_option.item_selected.connect(func(_index): _on_plan_edited())

	_direction_option = OptionButton.new()
	var directions: Array = _dispatch_config.get("route", {}).get("directions", [])
	if directions.is_empty():
		_direction_option.add_item("正向", 0)
	else:
		for entry in directions:
			if not entry is Dictionary:
				continue
			var label := str(entry.get("label", "正向"))
			if not bool(entry.get("simulated", true)):
				label += "（不仿真）"
			_direction_option.add_item(label, _direction_option.item_count)
	_direction_option.item_selected.connect(func(_index): _on_plan_edited())
	body.add_child(_label_row("运行方向", _direction_option))
	_direction_warning = Label.new()
	_direction_warning.add_theme_font_size_override("font_size", 12)
	_direction_warning.add_theme_color_override("font_color", Color("#f6c177"))
	_direction_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_direction_warning)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	_hour_spin = SpinBox.new()
	_hour_spin.min_value = 0
	_hour_spin.max_value = 47
	_hour_spin.step = 1
	_hour_spin.custom_minimum_size.x = 70.0
	_minute_spin = SpinBox.new()
	_minute_spin.min_value = 0
	_minute_spin.max_value = 59
	_minute_spin.step = 1
	_minute_spin.custom_minimum_size.x = 70.0
	var now_button := Button.new()
	now_button.text = "现在"
	now_button.pressed.connect(_set_departure_now)
	time_row.add_child(_hour_spin)
	time_row.add_child(_minute_spin)
	time_row.add_child(now_button)
	body.add_child(_label_row("出发时刻（时:分）", time_row))
	_hour_spin.value_changed.connect(func(_v): _on_plan_edited())
	_minute_spin.value_changed.connect(func(_v): _on_plan_edited())

	_speed_spin = SpinBox.new()
	_speed_spin.min_value = 40.0
	_speed_spin.max_value = 320.0
	_speed_spin.step = 5.0
	_speed_spin.suffix = " km/h"
	body.add_child(_label_row("最高速度", _speed_spin))
	_speed_spin.value_changed.connect(func(_v): _on_plan_edited())

	_dispatcher_edit = LineEdit.new()
	_dispatcher_edit.text = str(_plan.get("dispatcher", "调度台"))
	body.add_child(_label_row("调度员", _dispatcher_edit))
	_dispatcher_edit.text_changed.connect(func(_text): _on_plan_edited())

	_note_edit = LineEdit.new()
	_note_edit.placeholder_text = "备注（可选）"
	body.add_child(_label_row("备注", _note_edit))
	_note_edit.text_changed.connect(func(_text): _on_plan_edited())

	return panel


func _build_table_panel() -> PanelContainer:
	var panel := _make_panel("车站时刻表")
	var body: VBoxContainer = panel.get_node("Body")
	_table_header = HBoxContainer.new()
	_table_header.add_theme_constant_override("separation", 6)
	_add_table_header_cell(_table_header, "车站", 132.0, true)
	_add_table_header_cell(_table_header, "里程", 62.0)
	_add_table_header_cell(_table_header, "到点", 62.0)
	_add_table_header_cell(_table_header, "发点", 62.0)
	_add_table_header_cell(_table_header, "停车", 46.0)
	_add_table_header_cell(_table_header, "停靠时分", 74.0)
	_add_table_header_cell(_table_header, "股道", 92.0)
	body.add_child(_table_header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_table_body = VBoxContainer.new()
	_table_body.add_theme_constant_override("separation", 5)
	_table_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_table_body)

	for index in range((_plan.get("stations", []) as Array).size()):
		_table_body.add_child(_build_station_row(index))
	return panel


func _add_table_header_cell(parent: HBoxContainer, text: String, width: float, expand: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = width
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color("#8fb4cc"))
	parent.add_child(label)


func _build_station_row(index: int) -> Control:
	var stations: Array = _plan.get("stations", [])
	var station: Dictionary = stations[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name := Label.new()
	name.text = str(station.get("name", "?"))
	name.custom_minimum_size.x = 132.0
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var chainage := Label.new()
	chainage.custom_minimum_size.x = 62.0
	row.add_child(chainage)
	var arrival := Label.new()
	arrival.custom_minimum_size.x = 62.0
	row.add_child(arrival)
	var departure := Label.new()
	departure.custom_minimum_size.x = 62.0
	row.add_child(departure)
	var stop := CheckBox.new()
	stop.custom_minimum_size.x = 46.0
	stop.tooltip_text = "勾选为停车，取消为通过"
	row.add_child(stop)
	var dwell := SpinBox.new()
	dwell.min_value = 0.0
	dwell.max_value = 900.0
	dwell.step = 5.0
	dwell.suffix = " s"
	dwell.custom_minimum_size.x = 74.0
	row.add_child(dwell)
	var platform := OptionButton.new()
	platform.custom_minimum_size.x = 92.0
	var platforms: Array = station.get("platforms", [])
	if platforms.is_empty():
		platform.add_item(str(station.get("platform", "-")))
	else:
		for p in platforms:
			platform.add_item(str(p), platform.item_count)
	row.add_child(platform)

	var record := {
		"index": index,
		"name": name,
		"chainage": chainage,
		"arrival": arrival,
		"departure": departure,
		"stop": stop,
		"dwell": dwell,
		"platform": platform,
	}
	stop.toggled.connect(func(_pressed): _on_plan_edited())
	dwell.value_changed.connect(func(_v): _on_plan_edited())
	platform.item_selected.connect(func(_i): _on_plan_edited())
	_rows.append(record)
	return row


func _build_dispatch_panel() -> PanelContainer:
	var panel := _make_panel("调度监视")
	var panel_body: VBoxContainer = panel.get_node("Body")
	# 监视区内容较多，非全屏窗口高度有限时纵向滚动，避免把底部操作栏挤出画面。
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_body.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var summary_panel := _make_panel("运行概要")
	body.add_child(summary_panel)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", Color("#dcebf4"))
	summary_panel.get_node("Body").add_child(_summary)

	var checklist_panel := _make_panel("前置检查")
	body.add_child(checklist_panel)
	_checklist = Label.new()
	_checklist.add_theme_font_size_override("font_size", 13)
	_checklist.add_theme_color_override("font_color", Color("#cfe2ee"))
	checklist_panel.get_node("Body").add_child(_checklist)

	var log_panel := _make_panel("调度日志")
	log_panel.custom_minimum_size.y = 160.0
	body.add_child(log_panel)
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.follow_focus = true
	log_panel.get_node("Body").add_child(log_scroll)
	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_view.add_theme_font_size_override("normal_font_size", 13)
	log_scroll.add_child(_log_view)
	return panel


func _build_action_bar() -> PanelContainer:
	var panel := _make_panel("")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.get_node("Body").add_child(row)
	var back := Button.new()
	back.text = "返回场景选择"
	back.custom_minimum_size = Vector2(150.0, 48.0)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://app/local.tscn"))
	row.add_child(back)
	var reset := Button.new()
	reset.text = "重置方案"
	reset.custom_minimum_size = Vector2(120.0, 48.0)
	reset.pressed.connect(_on_reset)
	row.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_launch_button = Button.new()
	_launch_button.text = "确认发车（加载三维场景）"
	_launch_button.custom_minimum_size = Vector2(260.0, 48.0)
	_launch_button.add_theme_font_size_override("font_size", 18)
	_launch_button.pressed.connect(_on_launch)
	row.add_child(_launch_button)
	return panel


func _label_row(caption: String, control: Control) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#9fbdd4"))
	column.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(control)
	return column


func _make_panel(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.08, 0.105, 0.94)
	style.border_color = Color(0.30, 0.45, 0.55, 0.55)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 7)
	panel.add_child(body)
	if not title.is_empty():
		var label := Label.new()
		label.text = title
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color("#eaf4fb"))
		body.add_child(label)
		var separator := HSeparator.new()
		body.add_child(separator)
	return panel


# ── 数据同步与刷新 ────────────────────────────────────────────────────────────

func _on_plan_edited() -> void:
	if _updating:
		return
	_read_plan_from_ui()
	_recompute()


func _on_service_changed(index: int) -> void:
	# 切换种别时同步最高速度与默认编组，再统一读取其余控件。
	var services: Array = _dispatch_config.get("services", [])
	if index >= 0 and index < services.size() and services[index] is Dictionary:
		var service: Dictionary = services[index]
		if _speed_spin != null:
			_speed_spin.set_value_no_signal(float(service.get("speed_kmh", _speed_spin.value)))
		if _car_option != null:
			for car_index in range(_car_option.item_count):
				if _car_option.get_item_id(car_index) == int(service.get("cars", 0)):
					_car_option.select(car_index)
					break
	_on_plan_edited()


func _read_plan_from_ui() -> void:
	if _service_option != null:
		var selected := _service_option.selected
		var services: Array = _dispatch_config.get("services", [])
		if selected >= 0 and selected < services.size() and services[selected] is Dictionary:
			var service: Dictionary = services[selected]
			_plan["service_key"] = str(service.get("key", ""))
			_plan["service_name"] = str(service.get("name", ""))
			_plan["service_label"] = str(service.get("label", ""))
			_plan["max_speed_kmh"] = float(service.get("speed_kmh", _plan.get("max_speed_kmh", 120.0)))
			_plan["car_count"] = int(service.get("cars", _plan.get("car_count", 4)))
	if _number_edit != null:
		_plan["number"] = _number_edit.text.strip_edges()
	if _car_option != null:
		_plan["car_count"] = _car_option.get_selected_id()
	if _direction_option != null:
		_plan["direction"] = 1 if _direction_option.selected <= 0 else -1
		var directions: Array = _dispatch_config.get("route", {}).get("directions", [])
		if _direction_option.selected >= 0 and _direction_option.selected < directions.size() \
				and directions[_direction_option.selected] is Dictionary:
			_plan["direction_label"] = str(directions[_direction_option.selected].get("label", ""))
	if _hour_spin != null and _minute_spin != null:
		_plan["departure_s"] = float(int(_hour_spin.value) * 3600 + int(_minute_spin.value) * 60)
	if _speed_spin != null:
		_plan["max_speed_kmh"] = float(_speed_spin.value)
	if _dispatcher_edit != null:
		_plan["dispatcher"] = _dispatcher_edit.text.strip_edges()
	if _note_edit != null:
		_plan["note"] = _note_edit.text.strip_edges()
	var stations: Array = _plan.get("stations", [])
	for record in _rows:
		var index: int = record["index"]
		if index < 0 or index >= stations.size():
			continue
		var station: Dictionary = stations[index]
		station["stop"] = bool((record["stop"] as CheckBox).button_pressed)
		station["dwell_s"] = float((record["dwell"] as SpinBox).value)
		var platform_option := record["platform"] as OptionButton
		if platform_option.item_count > 0:
			station["platform"] = platform_option.get_item_text(platform_option.selected)


func _write_plan_to_ui() -> void:
	_updating = true
	if _service_option != null:
		var key := str(_plan.get("service_key", ""))
		for index in range(_service_option.item_count):
			if _service_option.get_item_text(index) == str(_plan.get("service_name", "")):
				_service_option.select(index)
				break
	if _number_edit != null:
		_number_edit.text = str(_plan.get("number", "1"))
	if _car_option != null:
		for index in range(_car_option.item_count):
			if _car_option.get_item_id(index) == int(_plan.get("car_count", 4)):
				_car_option.select(index)
				break
	if _direction_option != null and _direction_option.item_count > 0:
		_direction_option.select(0 if int(_plan.get("direction", 1)) >= 0 else mini(1, _direction_option.item_count - 1))
	if _hour_spin != null:
		_hour_spin.set_value_no_signal(posmod(int(_plan.get("departure_s", 0.0)) / 3600, 24))
	if _minute_spin != null:
		_minute_spin.set_value_no_signal(posmod(int(_plan.get("departure_s", 0.0)) / 60, 60))
	if _speed_spin != null:
		_speed_spin.set_value_no_signal(float(_plan.get("max_speed_kmh", 120.0)))
	if _dispatcher_edit != null:
		_dispatcher_edit.text = str(_plan.get("dispatcher", "调度台"))
	if _note_edit != null:
		_note_edit.text = str(_plan.get("note", ""))
	var stations: Array = _plan.get("stations", [])
	for record in _rows:
		var index: int = record["index"]
		if index < 0 or index >= stations.size():
			continue
		var station: Dictionary = stations[index]
		(record["stop"] as CheckBox).set_pressed_no_signal(bool(station.get("stop", true)))
		(record["dwell"] as SpinBox).set_value_no_signal(float(station.get("dwell_s", 0.0)))
		var platform_option := record["platform"] as OptionButton
		if platform_option.item_count > 0:
			var target := str(station.get("platform", ""))
			for pindex in range(platform_option.item_count):
				if platform_option.get_item_text(pindex) == target:
					platform_option.select(pindex)
					break
	_updating = false


func _recompute() -> void:
	_write_plan_to_ui()
	var route_length := float((_dispatch_config.get("route", {}) as Dictionary).get("distance_m", 0.0))
	if route_length <= 0.0 and not (_plan.get("stations", []) as Array).is_empty():
		var max_chainage := 0.0
		for station in _plan.get("stations", []):
			max_chainage = maxf(max_chainage, float((station as Dictionary).get("chainage_m", 0.0)))
		route_length = max_chainage + 500.0
	_schedule = PLAN.build_schedule(_plan, route_length)
	_refresh_table()
	_refresh_summary()
	if _diagram != null:
		_diagram.set_schedule(_schedule, float(_plan.get("departure_s", 0.0)))
	if _route_title != null:
		var route: Dictionary = _dispatch_config.get("route", {})
		_route_title.text = "%s · %s · %s" % [
			str(route.get("name", _module_id)),
			str(route.get("section", "")),
			str(route.get("operator", ""))]
	if _direction_warning != null:
		var simulated := true
		var directions: Array = (_dispatch_config.get("route", {}) as Dictionary).get("directions", [])
		if _direction_option != null and _direction_option.selected >= 0 \
				and _direction_option.selected < directions.size() \
				and directions[_direction_option.selected] is Dictionary:
			simulated = bool(directions[_direction_option.selected].get("simulated", true))
		_direction_warning.text = "" if simulated \
			else "该方向不在预览区段内，场景将按正方向运行（仅记录调度方向）。"


func _refresh_table() -> void:
	var stations: Array = _plan.get("stations", [])
	if stations.is_empty():
		if _table_body != null and _empty_table_label == null:
			_empty_table_label = Label.new()
			_empty_table_label.text = "该模块未提供车站数据，仅按运行限速调度。"
			_empty_table_label.add_theme_font_size_override("font_size", 14)
			_empty_table_label.add_theme_color_override("font_color", Color("#8fb4cc"))
			_table_body.add_child(_empty_table_label)
		return
	for record in _rows:
		var index: int = record["index"]
		if index < 0 or index >= stations.size():
			continue
		var station: Dictionary = stations[index]
		var schedule_stations: Array = _schedule.get("stations", [])
		var scheduled: Dictionary = schedule_stations[index] if index < schedule_stations.size() else {}
		(record["name"] as Label).text = _station_display(station)
		(record["chainage"] as Label).text = _format_chainage(float(station.get("chainage_m", 0.0)))
		var stop := bool(station.get("stop", true))
		if scheduled.is_empty():
			(record["arrival"] as Label).text = "--"
			(record["departure"] as Label).text = "--"
		elif stop:
			(record["arrival"] as Label).text = PLAN.format_short_clock(
				float(_plan.get("departure_s", 0.0)) + float(scheduled.get("arrival_s", 0.0)))
			(record["departure"] as Label).text = PLAN.format_short_clock(
				float(_plan.get("departure_s", 0.0)) + float(scheduled.get("departure_s", 0.0)))
		else:
			(record["arrival"] as Label).text = "通过"
			(record["departure"] as Label).text = PLAN.format_short_clock(
				float(_plan.get("departure_s", 0.0)) + float(scheduled.get("time_s", 0.0)))
		var dwell := record["dwell"] as SpinBox
		dwell.editable = stop
		dwell.modulate.a = 1.0 if stop else 0.45


func _station_display(station: Dictionary) -> String:
	var code := str(station.get("code", "")).strip_edges()
	if code.is_empty():
		return str(station.get("name", "?"))
	return "%s %s" % [code, str(station.get("name", "?"))]


func _format_chainage(chainage: float) -> String:
	if chainage >= 1000.0:
		return "%.2f km" % (chainage / 1000.0)
	return "%.0f m" % chainage


func _refresh_summary() -> void:
	var route: Dictionary = _dispatch_config.get("route", {})
	var route_length := float(route.get("distance_m", 0.0))
	if _summary != null:
		if _schedule.is_empty():
			_summary.text = "暂无时刻表（无车站数据）\n线路：%s\n运营：%s" % [
				str(route.get("name", _module_id)), str(route.get("operator", ""))]
		else:
			_summary.text = "车次：%s\n全程：%.2f km\n走行时分：%s\n平均速度：%.0f km/h\n最高速度：%.0f km/h\n停车：%d 站 · 通过：%d 站" % [
				PLAN.train_label(_plan),
				float(_schedule.get("distance_m", 0.0)) / 1000.0,
				PLAN.format_duration(float(_schedule.get("total_time_s", 0.0))),
				float(_schedule.get("avg_speed_kmh", 0.0)),
				float(_schedule.get("max_speed_kmh", 0.0)),
				int(_schedule.get("stop_count", 0)),
				int(_schedule.get("pass_count", 0))]
	if _checklist != null:
		_checklist.text = "\n".join(_build_checklist())


func _build_checklist() -> PackedStringArray:
	var lines := PackedStringArray()
	var checks := {
		"场景入口可用": FileAccess.file_exists(str(_entry.get("path", ""))),
		"车次已填写": not str(_plan.get("number", "")).strip_edges().is_empty(),
		"限速有效": PLAN.speed_cap_kmh(_plan) >= 40.0,
		"车站数据已提供": not (_plan.get("stations", []) as Array).is_empty(),
		"时刻表已生成": not _schedule.is_empty(),
		"走行时分大于 0": float(_schedule.get("total_time_s", 0.0)) > 0.0,
	}
	var order := ["场景入口可用", "车次已填写", "限速有效", "车站数据已提供", "时刻表已生成", "走行时分大于 0"]
	for name in order:
		var ok: bool = checks[name]
		lines.append(("✓ " if ok else "✗ ") + name)
	for warning in PLAN.validate(_plan, _schedule):
		lines.append("! " + warning)
	return lines


# ── 日志与操作 ────────────────────────────────────────────────────────────────

func _log(text: String) -> void:
	if _log_view == null:
		return
	var stamp := Time.get_datetime_string_from_system(false, true)
	_log_view.append_text("[color=#7fa8c9][%s][/color] %s\n" % [stamp, text])


func _log_plan_ready() -> void:
	_log("调度台启动：%s" % str(_route_title.text if _route_title != null else _module_id))
	if not (_plan.get("stations", []) as Array).is_empty():
		_log("车站数据已载入：%d 站" % (_plan.get("stations", []) as Array).size())
	if not _schedule.is_empty():
		var first: Dictionary = (_schedule.get("stations", []) as Array)[0]
		var last: Dictionary = (_schedule.get("stations", []) as Array)[(_schedule.get("stations", []) as Array).size() - 1]
		_log("计划：%s %s号 · %d 辆 · 最高 %.0f km/h" % [
			str(_plan.get("service_name", "")), str(_plan.get("number", "")),
			int(_plan.get("car_count", 4)), float(_plan.get("max_speed_kmh", 0.0))])
		_log("进路：%s %s → %s %s" % [
			str(first.get("name", "")), str(first.get("platform", "")),
			str(last.get("name", "")), str(last.get("platform", ""))])
		_log("运行时分 %s · 预计 %s 到达" % [
			PLAN.format_duration(float(_schedule.get("total_time_s", 0.0))),
			PLAN.format_clock(float(_plan.get("departure_s", 0.0)) + float(_schedule.get("total_time_s", 0.0)))])
	_log("调度方案就绪，等待发车指示。")


func _set_departure_now() -> void:
	var now := Time.get_datetime_dict_from_system()
	_hour_spin.set_value_no_signal(int(now.get("hour", 0)))
	_minute_spin.set_value_no_signal(int(now.get("minute", 0)))
	_on_plan_edited()


func _on_reset() -> void:
	_plan = PLAN.default_plan(_module_id, _dispatch_config)
	_write_plan_to_ui()
	_recompute()
	_log("调度方案已重置。")


func _on_launch() -> void:
	_read_plan_from_ui()
	_recompute()
	var context := get_node_or_null("/root/DispatchContext")
	if context == null:
		_show_fatal("缺少 DispatchContext 单例，请检查 project.godot。")
		return
	if str(_plan.get("number", "")).strip_edges().is_empty():
		_log("发车失败：车次未填写。")
		return
	context.set_plan(_plan, "dispatch-console")
	_log("出发指示确认：%s %s号 · %s → %s" % [
		str(_plan.get("service_name", "")), str(_plan.get("number", "")),
		_origin_station_name(), _destination_station_name()])
	_log("正在载入三维场景：%s" % str(_entry.get("title", "")))
	var error := get_tree().change_scene_to_file(str(_entry.get("path", "")))
	if error != OK:
		_show_fatal("场景加载失败：" + error_string(error))


func _origin_station_name() -> String:
	var stations: Array = _plan.get("stations", [])
	return str(stations[0].get("name", "起点")) if not stations.is_empty() else "起点"


func _destination_station_name() -> String:
	var stations: Array = _plan.get("stations", [])
	if stations.is_empty():
		return "终点"
	var index := stations.size() - 1
	while index >= 0 and not bool(stations[index].get("stop", true)):
		index -= 1
	return str(stations[maxi(index, 0)].get("name", "终点"))


func _run_smoke_test() -> void:
	_read_plan_from_ui()
	_recompute()
	var ok := true
	var stations: Array = _plan.get("stations", [])
	# 仅当提供车站数据却无法生成时刻表，或车次为空时判定失败；
	# "仅限速调度"（无车站数据）是合法的降级模式，不视为失败。
	if not stations.is_empty() and _schedule.is_empty():
		ok = false
	if str(_plan.get("number", "")).strip_edges().is_empty():
		ok = false
	var notes := PLAN.validate(_plan, _schedule)
	print("DISPATCH_SMOKE ", "PASS" if ok else "FAIL",
		" module=", _module_id, " train=", PLAN.train_label(_plan),
		" run_time_s=", _schedule.get("total_time_s", 0.0),
		" stops=", _schedule.get("stop_count", 0),
		" notes=", " | ".join(notes))
	get_tree().quit(0 if ok else 1)


func _show_fatal(message: String) -> void:
	push_error(message)
	var label := Label.new()
	label.text = message + "\n请检查 scenes 下的 scene.cfg 与 dispatch.json。"
	label.position = Vector2(40.0, 120.0)
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)
	if "--dispatch-smoke-test" in OS.get_cmdline_user_args() \
			or "--demo-smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			# 返回上一级：场景选择页。
			get_tree().change_scene_to_file("res://app/local.tscn")
