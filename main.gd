extends Node3D

# Matterhorn, Swiss/Italian Alps. The cartographic origin is placed near the
# summit so the initial camera can frame the surrounding high-relief terrain.
const ALPS_LATITUDE := 45.9763
const ALPS_LONGITUDE := 7.6586
const ALPS_ALTITUDE := 4478.0
const ALPS_LOCATION_NAME := "阿尔卑斯山 · 马特洪峰（采尔马特）"

var _tileset: Cesium3DTileset
var _status_label: Label
var _elapsed := 0.0
var _next_progress_report := 5.0
var _reported_loaded := false
var _http_server := TCPServer.new()
var _http_port := 8787
var _http_clients: Array[StreamPeerTCP] = []
var _use_cesium_ion := false


func _ready() -> void:
	# CesiumGDConfig creates its singleton node on first use. Waiting one frame
	# avoids adding that node while the scene root is still attaching children.
	await get_tree().process_frame
	_use_cesium_ion = _configure_cesium_ion()
	if not _use_cesium_ion:
		_start_local_tile_server()
	_create_environment()
	_create_cesium_scene()
	_create_help_overlay()
	print("3D Tiles demo initialized with Godot ", Engine.get_version_info().string)
	print("Tileset source: ", "Cesium ion 3D Tiles" if _use_cesium_ion else _sample_tileset_url())


func _process(delta: float) -> void:
	if not _use_cesium_ion:
		_serve_local_tile_requests()
	_elapsed += delta
	# v1.0.1 does not reliably flip is_initial_loading_finished(), so an instantiated
	# Cesium3DTile node is the authoritative signal that content reached Godot.
	var loaded_tile_count := _get_loaded_tile_count()
	if _tileset != null and not _reported_loaded and (_tileset.is_initial_loading_finished() or loaded_tile_count > 0):
		_reported_loaded = true
		_status_label.text = "状态：3D Tiles 已完成初始加载"
		_status_label.modulate = Color(0.55, 1.0, 0.65)
		print("3D Tiles content instantiated; tile nodes=", loaded_tile_count)
	if "--demo-smoke-test" in OS.get_cmdline_user_args() and _elapsed >= _next_progress_report:
		print("3D Tiles load progress: elapsed=", snapped(_elapsed, 0.1), "s tiles=", loaded_tile_count, " loaded=", _reported_loaded)
		_next_progress_report += 5.0
	if "--demo-smoke-test" in OS.get_cmdline_user_args() and _elapsed >= 30.0:
		print("DEMO_SMOKE_TEST_RESULT loaded=", _reported_loaded)
		get_tree().quit(0 if _reported_loaded else 2)


func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# A brighter daylight base keeps aerial imagery readable without flattening
	# the directional-light shading that gives the terrain its depth.
	environment.background_color = Color("87b8e8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dce8ff")
	environment.ambient_light_energy = 1.2
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.15
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)


func _create_cesium_scene() -> void:
	var georeference := CesiumGeoreference.new()
	georeference.name = "CesiumGeoreference"
	georeference.latitude = ALPS_LATITUDE
	georeference.longitude = ALPS_LONGITUDE
	georeference.altitude = ALPS_ALTITUDE
	georeference.origin_type = CesiumGeoreference.OriginType.CartographicOrigin
	georeference.rotation_degrees.x = -90.0
	add_child(georeference)

	_tileset = Cesium3DTileset.new()
	_tileset.name = "Cesium3DTileset"
	if _use_cesium_ion:
		_tileset.data_source = Cesium3DTileset.CesiumDataSource.FromCesiumIon
		_tileset.ion_asset_id = 1
		var bing_overlay := CesiumIonRasterOverlay.new()
		bing_overlay.name = "BingMapsAerialImagery"
		bing_overlay.key = "Overlay0"
		bing_overlay.asset_id = 2
		_tileset.add_child(bing_overlay)
	else:
		_tileset.data_source = Cesium3DTileset.CesiumDataSource.FromUrl
		_tileset.url = _sample_tileset_url()
	# Lower values request finer terrain/imagery LOD. 2.0 is a high-quality
	# desktop preset; the plugin default and the previous demo value were coarser.
	_tileset.maximum_screen_space_error = 2.0
	_tileset.maximum_simultaneous_tile_loads = 48
	_tileset.preload_ancestors = true
	_tileset.preload_siblings = true
	_tileset.create_physics_meshes = true
	_tileset.show_hierarchy = true
	_tileset.rotation_degrees.x = 90.0
	georeference.add_child(_tileset)

	var camera := Camera3D.new()
	camera.name = "DynamicCamera"
	camera.set_script(preload("res://addons/cesium_godot/scripts/georeference_camera_controller.gd"))
	camera.globe_node = georeference
	var camera_tilesets: Array[Cesium3DTileset] = [_tileset]
	camera.tilesets = camera_tilesets
	# Begin several kilometres from the summit for a recognisable alpine panorama.
	camera.position = Vector3(0.0, 1800.0, 6200.0)
	camera.near = 0.5
	camera.fov = 55.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	# The controller rebuilds the surface-aligned camera basis every frame, so its
	# own persistent pitch must be initialized as well as calling look_at().
	camera.curr_pitch = deg_to_rad(-18.0)
	camera.move_speed = 250.0


func _sample_tileset_url() -> String:
	return "http://127.0.0.1:%d/tileset.json" % _http_port


func _get_loaded_tile_count() -> int:
	if _tileset == null:
		return 0
	var count := 0
	for child in _tileset.get_children():
		if child is Cesium3DTile:
			count += 1
	return count


func _apply_high_quality_filtering() -> void:
	if _tileset == null:
		return
	for child in _tileset.get_children():
		if not child is Cesium3DTile:
			continue
		_enable_anisotropy_recursive(child)


func _enable_anisotropy_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.get_surface_override_material(surface_index)
				if source_material == null:
					source_material = mesh_instance.mesh.surface_get_material(surface_index)
				if source_material is BaseMaterial3D:
					if source_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
						continue
					# Update the material in place. A surface override created before the
					# asynchronous raster arrives would permanently hide the Bing texture.
					source_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for child in node.get_children():
		_enable_anisotropy_recursive(child)


func _configure_cesium_ion() -> bool:
	const token_path := "res://cesium_token.txt"
	if not FileAccess.file_exists(token_path):
		push_warning("cesium_token.txt not found; using the local sample tileset")
		return false
	var token := FileAccess.get_file_as_string(token_path).strip_edges()
	if token.is_empty():
		push_warning("cesium_token.txt is empty; using the local sample tileset")
		return false
	CesiumGDConfig.get_singleton(self).accessToken = token
	print("Cesium ion token configured (value hidden)")
	return true


func _start_local_tile_server() -> void:
	var listen_error := ERR_CANT_CREATE
	for candidate_port in range(8787, 8797):
		listen_error = _http_server.listen(candidate_port, "127.0.0.1")
		if listen_error == OK:
			_http_port = candidate_port
			print("Local 3D Tiles server listening on 127.0.0.1:", _http_port)
			return
	push_error("Unable to start local 3D Tiles server: " + error_string(listen_error))


func _serve_local_tile_requests() -> void:
	while _http_server.is_connection_available():
		var peer := _http_server.take_connection()
		if peer != null:
			_http_clients.append(peer)

	for peer in _http_clients.duplicate():
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR or peer.get_status() == StreamPeerTCP.STATUS_NONE:
			_http_clients.erase(peer)
			continue
		if peer.get_available_bytes() <= 0:
			continue
		var request: String = peer.get_utf8_string(peer.get_available_bytes())
		if not request.contains("\r\n\r\n"):
			continue
		var request_line: String = request.get_slice("\r\n", 0)
		var requested_path: String = request_line.get_slice(" ", 1).trim_prefix("/").get_slice("?", 0)
		_send_local_tile_response(peer, requested_path)
		_http_clients.erase(peer)


func _send_local_tile_response(peer: StreamPeerTCP, requested_path: String) -> void:
	var allowed_files := ["tileset.json", "dragon_low.b3dm", "dragon_medium.b3dm", "dragon_high.b3dm"]
	if requested_path not in allowed_files:
		peer.put_data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer())
		peer.disconnect_from_host()
		return

	var body := FileAccess.get_file_as_bytes("res://demo_data/" + requested_path)
	var content_type := "application/json" if requested_path.ends_with(".json") else "application/octet-stream"
	var headers := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [content_type, body.size()]
	peer.put_data(headers.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


func _exit_tree() -> void:
	if not _use_cesium_ion:
		_http_server.stop()


func _create_help_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DemoUI"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(500.0, 0.0)
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var text_box := VBoxContainer.new()
	margin.add_child(text_box)

	var title := Label.new()
	title.text = "3D Tiles for Godot · 阿尔卑斯山 Demo"
	title.add_theme_font_size_override("font_size", 20)
	text_box.add_child(title)

	var instructions := Label.new()
	instructions.text = "位置：" + (ALPS_LOCATION_NAME if _use_cesium_ion else "CesiumGS 本地回退样例") + "\nW/A/S/D：移动    Q/E：下降/上升\n鼠标右键拖动：环视    +/-：调整速度\n高清预设：SSE 2.0 / 16× 各向异性过滤\n数据：" + ("Cesium World Terrain + Bing Aerial" if _use_cesium_ion else "CesiumGS 本地样例")
	text_box.add_child(instructions)

	_status_label = Label.new()
	_status_label.text = "状态：正在加载 " + ("Cesium ion 3D Tiles…" if _use_cesium_ion else "本地 3D Tiles…")
	_status_label.modulate = Color(1.0, 0.85, 0.45)
	text_box.add_child(_status_label)
