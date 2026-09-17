extends Node
## Keep the original scene, shaders, models and data in the external project.
const RESOURCE_BRIDGE := preload("res://scenes/outdoors/external_resources.gd")
const ADAPTER_SOURCE := """extends %s
var _progress_track: Control
var _progress_label: Label
var _progress_slider: HSlider
var _progress_visible := true
var _space_pause := false

func _parse_cli(args: PackedStringArray) -> void:
	var defaults := PackedStringArray(%s)
	defaults.append_array(args)
	if "--cab-view" in args:
		defaults.append("--camera-mode=driver")
	# 状态面板默认隐藏；用 Ctrl+Shift+G 显隐。
	if "--overlay" not in args:
		defaults.append("--overlay=false")
	# The original smoke check only uses a timer; this entry validates assets too.
	defaults.append("--smoke=false")
	super._parse_cli(defaults)

func _unhandled_input(event: InputEvent) -> void:
	# Ctrl+Shift+O 独立切换底部里程文字与进度滑块。
	if event is InputEventKey:
		var progress_key := event as InputEventKey
		if (progress_key.pressed and not progress_key.echo
				and progress_key.keycode == KEY_O
				and progress_key.ctrl_pressed and progress_key.shift_pressed
				and not progress_key.alt_pressed and not progress_key.meta_pressed):
			_progress_visible = not _progress_visible
			_update_status_text()
			get_viewport().set_input_as_handled()
			return
	# Ctrl+Shift+G 切换状态面板（里程/视角）显隐。
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (key_event.pressed and not key_event.echo
				and key_event.keycode == KEY_G
				and key_event.ctrl_pressed and key_event.shift_pressed
				and not key_event.alt_pressed and not key_event.meta_pressed):
			if _status != null:
				_status.visible = not _status.visible
			_update_status_text()
			get_viewport().set_input_as_handled()
			return
	# 空格切换暂停（替代原工程的长按 P）。
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			_space_pause = not _space_pause
			_update_status_text()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _process(delta: float) -> void:
	# 与原工程 _process 一致，仅暂停来源改为空格开关。
	_paused = _force_pause or _space_pause
	if not _route.is_empty() and not _paused:
		_travelled += _speed * delta
		if _travelled > _dist_m:
			_travelled = fmod(_travelled, _dist_m)
	_update_camera_transform()
	_update_shader_world_uniforms()
	_update_status_text()
	if _perf:
		_track_perf(delta)

func _ensure_progress_bar() -> void:
	# 与市区场景一致的底部进度条：上方里程文字 + 下方可拖动滑块（拖动即跳转里程）。
	if _progress_slider != null or _status == null or _dist_m <= 0.0:
		return
	_progress_track = VBoxContainer.new()
	_progress_track.name = "JourneyProgressTrack"
	_progress_track.visible = _progress_visible
	_progress_track.anchor_left = 0.08
	_progress_track.anchor_top = 1.0
	_progress_track.anchor_right = 0.92
	_progress_track.anchor_bottom = 1.0
	_progress_track.offset_top = -72.0
	_progress_track.offset_bottom = -16.0
	_status.get_parent().add_child(_progress_track)
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 17)
	_progress_label.add_theme_color_override("font_color", Color.WHITE)
	_progress_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_progress_label.add_theme_constant_override("outline_size", 4)
	_progress_track.add_child(_progress_label)
	_progress_slider = HSlider.new()
	_progress_slider.min_value = 0.0
	_progress_slider.max_value = 100.0
	_progress_slider.step = 0.1
	_progress_slider.custom_minimum_size = Vector2(0.0, 28.0)
	_progress_slider.tooltip_text = "拖动或点击以跳转运行进度"
	_progress_slider.value_changed.connect(_seek_to_progress)
	_progress_track.add_child(_progress_slider)

func _seek_to_progress(percent: float) -> void:
	if _dist_m <= 0.0:
		return
	_jump_to_distance(percent * _dist_m / 100.0)

func _update_status_text() -> void:
	if _status == null:
		return
	var views := {"third": "第三人称", "driver": "驾驶视角", "top": "俯视", "oblique": "斜俯视"}
	_status.text = "郊外 · 大糸线大町  " + str(roundi(_travelled)) + " / " + str(roundi(_dist_m)) + " m"
	_status.text += String.chr(10) + "速度 " + str(roundi(_speed * 3.6)) + " km/h  ·  " + views.get(_camera_mode, _camera_mode)
	_status.text += "  ·  " + ("已暂停" if _paused or _force_pause else "运行中")
	_status.text += String.chr(10) + "M 切换视角 · Space 暂停 · +/- 调速 · W 线框 · Ctrl+Shift+G 面板 · Ctrl+Shift+O 进度条 · 拖动跳转"
	_ensure_progress_bar()
	if _progress_slider == null:
		return
	# 每帧刷新保留用户选择，与 Ctrl+Shift+G 状态面板互不影响。
	_progress_track.visible = _progress_visible
	_progress_label.text = str(roundi(_travelled)) + " m / " + str(roundi(_dist_m)) + " m"
	_progress_slider.set_value_no_signal(100.0 * _travelled / _dist_m)
"""
var bridge: ResourceFormatLoader
var preview: Node3D
var error_label: Label

func _module_id() -> String:
	return "outdoors"

func _adapter_extension() -> String:
	return ""

func _smoke_extra() -> bool:
	return true

func _ready() -> void:
	var external_root := "E:/game_project"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--external-project="):
			external_root = arg.trim_prefix("--external-project=").replace("\\", "/").trim_suffix("/")
	var source_scene := external_root.path_join("train/scenes/offline_jingguang_preview.tscn")
	var data_dir := external_root.path_join("train/data/offline_oito_omachi")
	for required in [source_scene, data_dir.path_join("manifest.json")]:
		if not FileAccess.file_exists(required):
			_fail("郊外场景资源不存在：" + required)
			return
	bridge = RESOURCE_BRIDGE.new()
	bridge.project_root = external_root
	ResourceLoader.add_resource_format_loader(bridge, true)
	var packed := load(source_scene) as PackedScene
	if packed == null:
		_fail("郊外场景加载失败：" + source_scene)
		return
	# 调度方案（若存在）提供运行限速；默认保持 20 m/s（72 km/h）。
	var speed_mps := 20.0
	var context := get_node_or_null("/root/DispatchContext")
	var plan: Dictionary = context.resolve() if context != null else {}
	if not plan.is_empty() and str(plan.get("module", "")) == _module_id():
		speed_mps = clampf(float(plan.get("max_speed_kmh", 72.0)) / 3.6, 1.0, 40.0)
	# Inherit the original script in memory; only supply the launch defaults.
	var script := GDScript.new()
	var base_path := external_root.path_join("train/scripts/environment/offline_jingguang_preview.gd")
	script.source_code = ADAPTER_SOURCE % [JSON.stringify(base_path), JSON.stringify([
		"--path=" + data_dir, "--corridor=on", "--camera-mode=third",
		"--speed=%.3f" % speed_mps,
		"--output-dir=user://countryside_captures"
	])]
	script.source_code += _adapter_extension()
	if script.reload() != OK:
		_fail("郊外场景接入脚本无法加载")
		return
	preview = packed.instantiate() as Node3D
	preview.set_script(script)
	add_child(preview)
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		get_tree().create_timer(4.0).timeout.connect(_smoke_result)


func _smoke_result() -> void:
	var ok: bool = bridge.failures.is_empty() and preview._dist_m > 0.0 and preview._travelled > 0.0 \
		and preview._total_glbs > 0 and preview._loaded_glbs == preview._total_glbs \
		and preview._corridor_enabled and is_equal_approx(preview._speed, 20.0) \
		and (preview._camera_mode != "third" or (preview._external_train != null \
		and preview._external_train.get_child_count() == 7)) and _smoke_extra()
	print("COUNTRYSIDE_SMOKE ", "PASS" if ok else "FAIL", " tiles=", preview._loaded_glbs,
		"/", preview._total_glbs, " models=", bridge.loaded_models, " failures=", bridge.failures)
	get_tree().quit(0 if ok else 1)

func _fail(message: String) -> void:
	push_error(message)
	error_label = Label.new()
	error_label.text = message + "\n请检查原资源目录，或使用 -ExternalProject 指定位置。"
	error_label.position = Vector2(40, 80)
	add_child(error_label)
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit(1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			# 返回上一级：列车调度台（并记住当前模块）。
			var context := get_node_or_null("/root/DispatchContext")
			if context != null:
				context.select_module(_module_id())
			get_tree().change_scene_to_file("res://app/dispatch/dispatch_console.tscn")


func _exit_tree() -> void:
	if bridge != null:
		ResourceLoader.remove_resource_format_loader(bridge)
		bridge.clear_scene_uids()
