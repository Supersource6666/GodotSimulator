extends SceneTree

class UIOnly:
	extends "res://offline_journey.gd"

	func _ready() -> void:
		_setup_scene()
		set_process(false)

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var preview := UIOnly.new()
	root.add_child(preview)
	var environment: Environment = preview.get_child(0).environment
	assert(not environment.fog_enabled and not environment.volumetric_fog_enabled)
	assert(environment.ambient_light_color == Color.WHITE)
	assert(is_equal_approx(environment.ambient_light_energy, 0.32))
	assert(environment.tonemap_mode == Environment.TONE_MAPPER_ACES)
	assert(environment.adjustment_enabled and environment.adjustment_contrast > 1.0)
	assert(is_equal_approx(preview.CONFLICT_MILEAGE_C_M, 1718.0))
	assert(preview.panel.visible and not preview.ready_for_trip)
	var key := InputEventKey.new()
	key.keycode = KEY_G
	key.pressed = true
	key.ctrl_pressed = true
	key.shift_pressed = true
	preview._unhandled_key_input(key)
	assert(not preview.panel.visible)
	assert(preview.mini_map.visible)
	key.echo = true
	preview._unhandled_key_input(key)
	assert(not preview.panel.visible)
	key.echo = false
	key.pressed = false
	preview._unhandled_key_input(key)
	assert(not preview.panel.visible)
	key.pressed = true
	preview._unhandled_key_input(key)
	assert(preview.panel.visible)
	assert(preview.mini_map.visible)
	key.shift_pressed = false
	preview._unhandled_key_input(key)
	assert(preview.panel.visible)
	# Bottom journey controls are a sibling, not a child of the hidden panels.
	key.shift_pressed = true
	preview._unhandled_key_input(key)
	var progress_track := preview.panel.get_parent().get_node("JourneyProgressTrack") as VBoxContainer
	assert(progress_track.is_visible_in_tree())
	assert(not preview.panel.visible)
	assert(preview.mini_map.visible)
	key.keycode = KEY_F
	preview._unhandled_key_input(key)
	assert(not preview.mini_map.visible)
	assert(not preview.panel.visible)
	preview._unhandled_key_input(key)
	assert(preview.mini_map.visible)
	assert(not preview.panel.visible)
	key.ctrl_pressed = false
	key.shift_pressed = false
	preview._unhandled_key_input(key)
	assert(preview.wireframe_enabled)
	assert(root.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME)
	preview._unhandled_key_input(key)
	assert(not preview.wireframe_enabled)
	assert(root.debug_draw == Viewport.DEBUG_DRAW_DISABLED)
	preview.free()
	print("OFFLINE_HUD_TEST PASS: independent status/minimap/wireframe toggles, repeat, release, modifiers")
	quit(0)
