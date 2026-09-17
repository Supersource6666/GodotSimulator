extends Node
## 调度方案传递通道（单例）。
## 选择界面 → 调度台 → 三维场景；调度台写入方案，场景读取后按计划运行。
## 也支持命令行注入：--dispatch-plan-file=<user:// 或 res:// 路径>。

const CACHE_PATH := "user://last_dispatch_plan.json"

var _plan: Dictionary = {}
var _source := ""
var pending_module := ""


func select_module(module_id: String) -> void:
	pending_module = module_id.strip_edges().to_lower()


func take_module() -> String:
	var value := pending_module
	pending_module = ""
	return value


func set_plan(plan: Dictionary, source := "dispatch-console") -> void:
	_plan = plan.duplicate(true)
	_source = source
	_write_cache(_plan)


func clear_plan() -> void:
	_plan = {}
	_source = ""


func has_plan() -> bool:
	return not _plan.is_empty()


func current_plan() -> Dictionary:
	return _plan.duplicate(true)


func plan_source() -> String:
	return _source


## 解析当前应当使用的调度方案：内存方案优先，其次命令行文件，最后是上一次的缓存。
func resolve() -> Dictionary:
	if not _plan.is_empty():
		return _plan.duplicate(true)
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dispatch-plan-file="):
			path = arg.trim_prefix("--dispatch-plan-file=").strip_edges().replace("\\", "/")
	if path.is_empty():
		return {}
	var plan := _read_plan(path)
	if not plan.is_empty():
		_source = path
	return plan


static func _read_plan(path: String) -> Dictionary:
	var resolved := path
	if not resolved.begins_with("res://") and not resolved.begins_with("user://") \
			and not resolved.contains(":/") and not resolved.begins_with("/"):
		resolved = "user://" + resolved
	if not FileAccess.file_exists(resolved):
		push_warning("调度方案文件不存在：" + resolved)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(resolved))
	if not parsed is Dictionary:
		push_warning("调度方案文件格式无效：" + resolved)
		return {}
	return parsed


func _write_cache(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(plan, "  "))
	file.close()


## 供自动化测试与调试使用：读取缓存中最后一次的调度方案。
func cached_plan() -> Dictionary:
	return _read_plan(CACHE_PATH)
