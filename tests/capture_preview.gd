extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var preview = load("res://journey.gd").new()
	root.add_child(preview)
	await process_frame
	await process_frame
	preview._paused = not ("--moving" in OS.get_cmdline_user_args())
	if "--at-1200" in OS.get_cmdline_user_args():
		preview._journey_distance = 1200.0
		preview._update_route_position(1200.0)
	for step in range(24 if "--long" in OS.get_cmdline_user_args() else 4):
		await create_timer(15.0).timeout
		print("DETAIL_PROGRESS seconds=",(step+1)*15," samples=",preview._view_coverage," distance=",preview._journey_distance," tiles=",preview._get_loaded_tile_count())
		print("PERF probe_max_ms=",preview._probe_max_ms," build_max_ms=",preview._triangle_build_max_ms," native_max_ms=",preview._native_update_max_ms," process_max_ms=",preview._process_max_ms," pending_bvh=",preview._triangle_queue.size()," cached_bvh=",preview._triangle_cache.size())
		if "--long" in OS.get_cmdline_user_args() and preview._view_ready_elapsed >= 5.0:
			break
	var camera: Camera3D = preview._route_camera
	print("CAMERA ", camera.global_transform)
	print("TRAIN_CAPTURE position=", preview._train.global_position, " ready=", preview._train.ready_for_preview, " rail_height=", preview._rail_height, " screen=", camera.unproject_position(preview._train.global_position))
	var count := 0
	for tile in preview._tileset.get_children():
		if tile is MeshInstance3D and tile.visible:
			if count < 6:
				print("TILE position=", tile.global_position, " bounds=", tile.get_aabb(), " basis=", tile.global_basis)
			count += 1
	print("VISIBLE_NODES ", count)
	print("COVERAGE ", preview._view_coverage)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-diagnostic.png")
	print("CAPTURE_DONE")
	quit()
