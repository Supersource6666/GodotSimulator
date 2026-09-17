extends RefCounted
## Discover module metadata without loading scene assets.
const MODULE_ROOT := "res://scenes"
var entries: Array[Dictionary] = []
var errors: PackedStringArray = []
var _lookup: Dictionary = {}

func discover() -> void:
	entries.clear()
	errors.clear()
	_lookup.clear()
	var folders := DirAccess.get_directories_at(MODULE_ROOT)
	folders.sort()
	for folder in folders:
		var directory := MODULE_ROOT.path_join(folder)
		var config_path := directory.path_join("scene.cfg")
		if not FileAccess.file_exists(config_path):
			continue
		var config := ConfigFile.new()
		if config.load(config_path) != OK:
			errors.append("无法读取场景配置：" + config_path)
			continue
		var id := str(config.get_value("scene", "id", "")).strip_edges()
		var title := str(config.get_value("scene", "title", "")).strip_edges()
		var relative := str(config.get_value("scene", "entry", "scene.tscn"))
		if id != folder or id != id.to_lower() or title.is_empty() \
				or relative.is_absolute_path() or relative.contains("..") or relative.contains(":"):
			errors.append("无效场景配置：" + config_path)
			continue
		var path := directory.path_join(relative)
		if not relative.ends_with(".tscn") or not FileAccess.file_exists(path):
			errors.append("场景入口不存在：" + path)
			continue
		var aliases: Variant = config.get_value("scene", "aliases", [])
		if not aliases is Array and not aliases is PackedStringArray:
			errors.append("场景 aliases 必须为数组：" + config_path)
			continue
		var keys: Array[String] = [id]
		for alias in aliases:
			var key := str(alias).strip_edges().to_lower()
			if not key.is_empty() and not key in keys:
				keys.append(key)
		var collision := false
		for key in keys:
			if _lookup.has(key):
				errors.append("场景名称或别名重复：" + key)
				collision = true
		if collision:
			continue
		var dispatch_path := ""
		var dispatch := str(config.get_value("scene", "dispatch", "")).strip_edges()
		if not dispatch.is_empty():
			if dispatch.is_absolute_path() or dispatch.contains("..") or dispatch.contains(":"):
				errors.append("无效调度配置路径：" + config_path)
				continue
			var dispatch_candidate := directory.path_join(dispatch)
			if FileAccess.file_exists(dispatch_candidate):
				dispatch_path = dispatch_candidate
			# 调度配置为可选：文件缺失时降级为"仅限速调度"，不阻断菜单。
		var entry := {"id": id, "title": title, "path": path,
			"description": str(config.get_value("scene", "description", "")),
			"order": int(config.get_value("scene", "order", 100)),
			"dispatch_path": dispatch_path}
		entries.append(entry)
		for key in keys:
			_lookup[key] = entry
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.id < b.id if a.order == b.order else a.order < b.order)

func resolve(id_or_alias: String) -> Dictionary:
	return _lookup.get(id_or_alias.strip_edges().to_lower(), {})

func default_id() -> String:
	return str(ProjectSettings.get_setting("application/local_scenes/default_id", "urban"))


func load_dispatch(entry: Dictionary) -> Dictionary:
	var config_path := str(entry.get("dispatch_path", ""))
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not parsed is Dictionary:
		push_warning("调度配置格式无效：" + config_path)
		return {}
	return parsed
