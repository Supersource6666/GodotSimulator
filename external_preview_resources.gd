extends ResourceFormatLoader
## Read the external preview's narrow dependency set without importing/copying assets.
var project_root := "E:/game_project"
var failures: Array[String] = []
var loaded_models := 0
var scene_uids: Array[int] = []

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["glb", "gd", "gdshader", "tscn"])

func _handles_type(type: StringName) -> bool:
	return type in [&"PackedScene", &"Script", &"GDScript", &"Shader"]

func _external_path(path: String) -> String:
	if path.begins_with("res://train/"):
		return project_root.path_join(path.trim_prefix("res://"))
	return path

func _get_resource_type(path: String) -> String:
	var actual := _external_path(path)
	if not actual.begins_with(project_root + "/train/"):
		return ""
	match actual.get_extension():
		"tscn": return "PackedScene" if path.begins_with("res://train/") else ""
		"glb": return "PackedScene"
		"gd": return "GDScript"
		"gdshader": return "Shader"
	return ""

func _exists(path: String) -> bool:
	return not _get_resource_type(path).is_empty() and FileAccess.file_exists(_external_path(path))

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int):
	# Let the built-in loader handle actual .tscn files and unrelated assets.
	if _get_resource_type(path).is_empty():
		return ERR_FILE_UNRECOGNIZED
	var actual := _external_path(path)
	if not _exists(path):
		failures.append(actual)
		return ERR_FILE_NOT_FOUND
	match actual.get_extension():
		"tscn":
			_register_scene_uids(actual)
			return ResourceLoader.load(actual, "PackedScene")
		"glb":
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var error := document.append_from_file(actual, state)
			if error != OK:
				failures.append(actual)
				return error
			var model := document.generate_scene(state)
			if model == null:
				failures.append(actual)
				return ERR_CANT_CREATE
			var packed := PackedScene.new()
			error = packed.pack(model)
			model.free()
			if error != OK:
				failures.append(actual)
				return error
			loaded_models += 1
			return packed
		"gdshader":
			var shader := Shader.new()
			shader.code = FileAccess.get_file_as_string(actual)
			return shader
		"gd":
			var script := GDScript.new()
			# The source preview removes this physics controller immediately after
			# instantiation. A neutral script avoids unrelated project singletons.
			if actual.ends_with("/train/scripts/train_car.gd"):
				script.source_code = "extends Node3D\n"
			else:
				script.source_code = FileAccess.get_file_as_string(actual)
			var error := script.reload()
			if error != OK:
				failures.append(actual)
				return error
			return script
	return ERR_FILE_UNRECOGNIZED

func _register_scene_uids(path: String) -> void:
	# The external editor UID cache is not part of this project. Register only
	# missing scene dependencies in memory; keep existing project mappings intact.
	var pattern := RegEx.new()
	pattern.compile('uid="([^"]+)" path="([^"]+)"')
	for item in pattern.search_all(FileAccess.get_file_as_string(path)):
		var id := ResourceUID.text_to_id(item.get_string(1))
		if id != ResourceUID.INVALID_ID and not ResourceUID.has_id(id):
			ResourceUID.add_id(id, item.get_string(2))
			scene_uids.append(id)

func clear_scene_uids() -> void:
	for id in scene_uids:
		ResourceUID.remove_id(id)
	scene_uids.clear()
