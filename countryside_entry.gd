extends Node
## Keep the original scene, shaders, models and data in the external project.
const RESOURCE_BRIDGE := preload("res://external_preview_resources.gd")
const ADAPTER_SOURCE := """extends %s
func _parse_cli(args: PackedStringArray) -> void:
	var defaults := PackedStringArray(%s)
	defaults.append_array(args)
	if "--cab-view" in args:
		defaults.append("--camera-mode=driver")
	# The original smoke check only uses a timer; this entry validates assets too.
	defaults.append("--smoke=false")
	super._parse_cli(defaults)

func _update_status_text() -> void:
	if _status == null:
		return
	var views := {"third": "第三人称", "driver": "驾驶视角", "top": "俯视", "oblique": "斜俯视"}
	_status.text = "郊外 · 大糸线大町  " + str(roundi(_travelled)) + " / " + str(roundi(_dist_m)) + " m"
	_status.text += String.chr(10) + "速度 " + str(roundi(_speed * 3.6)) + " km/h  ·  " + views.get(_camera_mode, _camera_mode)
	_status.text += "  ·  " + ("已暂停" if _paused or _force_pause else "运行中")
	_status.text += String.chr(10) + "M 切换视角 · 按住 P 暂停 · +/- 调速 · W 线框"
"""
var bridge: ResourceFormatLoader
var preview: Node3D
var error_label: Label

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
	# Inherit the original script in memory; only supply the launch defaults.
	var script := GDScript.new()
	var base_path := external_root.path_join("train/scripts/environment/offline_jingguang_preview.gd")
	script.source_code = ADAPTER_SOURCE % [JSON.stringify(base_path), JSON.stringify([
		"--path=" + data_dir, "--corridor=on", "--camera-mode=third", "--speed=20",
		"--output-dir=user://countryside_captures"
	])]
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
		and preview._external_train.get_child_count() == 7))
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

func _exit_tree() -> void:
	if bridge != null:
		ResourceLoader.remove_resource_format_loader(bridge)
		bridge.clear_scene_uids()
