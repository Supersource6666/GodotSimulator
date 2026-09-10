extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node)
	for child in node.get_children():
		_meshes(child, output)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var directory := "res://tile_diagnostic/coarse/" if "--coarse" in OS.get_cmdline_user_args() else "res://tile_diagnostic/"
	var glb := FileAccess.get_file_as_bytes(directory + "original.glb")
	var json_length := glb.decode_u32(12)
	var model: Dictionary = JSON.parse_string(glb.slice(20,20+json_length).get_string_from_utf8())
	var matrix: Array = model.nodes[0].matrix
	var origin_engine := Vector3(matrix[12],matrix[13],matrix[14])
	var origin_ecef := Vector3(origin_engine.x,-origin_engine.z,origin_engine.y)
	var geo := CesiumGeoreference.new()
	geo.origin_type = CesiumGeoreference.OriginType.CartographicOrigin
	geo.ecefX = origin_ecef.x
	geo.ecefY = origin_ecef.y
	geo.ecefZ = origin_ecef.z
	geo.rotation_degrees.x = -90
	world.add_child(geo)
	var tileset := Cesium3DTileset.new()
	tileset.data_source = Cesium3DTileset.CesiumDataSource.FromUrl
	tileset.url = "http://127.0.0.1:18789/coarse/tileset.json" if "--coarse" in OS.get_cmdline_user_args() else "http://127.0.0.1:18789/tileset.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tileset-url="):
			tileset.url = argument.trim_prefix("--tileset-url=")
	tileset.rotation_degrees.x = 90
	tileset.show_hierarchy = true
	geo.add_child(tileset)
	var camera := Camera3D.new()
	world.add_child(camera)
	var up := origin_engine.normalized()
	var right := up.cross(Vector3.UP).normalized()
	camera.position = up * 240 + right * 160
	camera.look_at(Vector3.ZERO,up)
	camera.near = 0.1
	camera.far = 3000
	camera.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2,0.25,0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	world.add_child(env)
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var err := document.append_from_buffer(glb,directory,state)
	assert(err == OK)
	var reference := document.generate_scene(state)
	world.add_child(reference)
	reference.position = -origin_engine
	reference.hide()
	var plugin_meshes: Array[MeshInstance3D] = []
	for frame in range(600):
		tileset.update_tileset(geo.get_tx_engine_to_ecef() * camera.global_transform)
		await process_frame
		plugin_meshes.clear()
		_meshes(tileset, plugin_meshes)
		if not plugin_meshes.is_empty():
			break
	assert(not plugin_meshes.is_empty(), "Local Cesium tile did not load")
	var reference_meshes: Array[MeshInstance3D] = []
	_meshes(reference,reference_meshes)
	var report := {"plugin_meshes":plugin_meshes.size(),"reference_meshes":reference_meshes.size(),"surfaces":[]}
	var actual := plugin_meshes[0]
	if ProjectSettings.get_setting("cesium/prepare_query_meshes", false):
		assert(actual.mesh.get_meta("preview_bvh_ready", false), "Tile BVH must be built before publication")
	var expected := reference_meshes[0]
	report.plugin_transform = str(actual.global_transform)
	report.reference_transform = str(expected.global_transform)
	for surface in actual.mesh.get_surface_count():
		var a := actual.mesh.surface_get_arrays(surface)
		var b := expected.mesh.surface_get_arrays(surface)
		var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bv: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
		var ai: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var bi: PackedInt32Array = b[Mesh.ARRAY_INDEX]
		var vertex_error := 0.0
		for i in mini(av.size(),bv.size()):
			vertex_error = maxf(vertex_error,av[i].distance_to(bv[i]))
		var winding_matches := ai.size() == bi.size()
		for i in range(0,mini(ai.size(),bi.size()),3):
			# Godot's importer reverses glTF winding; Cesium uses front culling.
			winding_matches = winding_matches and ai[i] == bi[i] and ai[i+1] == bi[i+2] and ai[i+2] == bi[i+1]
		var am = actual.get_active_material(surface)
		var bm = expected.get_active_material(surface)
		report.surfaces.append({"plugin_vertices":av.size(),"reference_vertices":bv.size(),"max_vertex_error":vertex_error,"plugin_indices":ai.size(),"reference_indices":bi.size(),"same_triangles_reversed_winding":winding_matches,"plugin_texture":str(am.get_texture(BaseMaterial3D.TEXTURE_ALBEDO).get_size()),"reference_texture":str(bm.get_texture(BaseMaterial3D.TEXTURE_ALBEDO).get_size())})
	if "--cache-probe" in OS.get_cmdline_user_args():
		for surface in report.surfaces:
			assert(surface.max_vertex_error == 0.0 and surface.same_triangles_reversed_winding)
		print("CACHE_PROBE_PASS")
		quit()
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + "plugin.png")
	geo.hide()
	reference.show()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + "reference.png")
	var output := FileAccess.open(directory + "comparison.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("COMPARISON ",JSON.stringify(report))
	quit()
