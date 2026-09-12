extends Node3D
## Camera-local Shinkansen cab overlay. Transparent windscreen pixels reveal the
## live 3D route while the photographic console and frame remain screen-aligned.

const CAB_OVERLAY_TEXTURE := preload("res://assets/Shinkansen/cab_overlay.png")
const OVERLAY_DISTANCE_M := 0.60
const OVERLAY_COVER_MARGIN := 1.002

var _overlay: Sprite3D
var _last_viewport_size := Vector2.ZERO
var _last_camera_fov := -1.0


func _ready() -> void:
	_overlay = Sprite3D.new()
	_overlay.name = "CabOverlay"
	_overlay.texture = CAB_OVERLAY_TEXTURE
	_overlay.position = Vector3(0.0, 0.0, -OVERLAY_DISTANCE_M)
	_overlay.centered = true
	_overlay.shaded = false
	_overlay.no_depth_test = true
	_overlay.double_sided = true
	_overlay.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_overlay.render_priority = 127
	add_child(_overlay)
	get_viewport().size_changed.connect(_fit_overlay_to_viewport)
	_fit_overlay_to_viewport()


func _process(_delta: float) -> void:
	# Camera FOV changes when cab view is toggled and does not emit a resize signal.
	# Cache both values so ordinary frames do not rebuild the overlay transform.
	var camera := get_parent() as Camera3D
	if camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size != _last_viewport_size or not is_equal_approx(camera.fov, _last_camera_fov):
		_fit_overlay_to_viewport()


func _fit_overlay_to_viewport() -> void:
	var camera := get_parent() as Camera3D
	if camera == null or _overlay == null or _overlay.texture == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var texture_size := _overlay.texture.get_size()
	# KEEP_HEIGHT makes Camera3D.fov vertical. Scale uniformly until both the
	# viewport width and height are covered, preserving the source aspect ratio.
	var visible_height := 2.0 * OVERLAY_DISTANCE_M * tan(deg_to_rad(camera.fov) * 0.5)
	var visible_width := visible_height * viewport_size.aspect()
	_overlay.pixel_size = maxf(visible_width / texture_size.x, visible_height / texture_size.y) \
		* OVERLAY_COVER_MARGIN
	_last_viewport_size = viewport_size
	_last_camera_fov = camera.fov
