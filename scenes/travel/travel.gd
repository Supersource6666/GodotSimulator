extends Node3D
## Photo-inspired cutting with the same external rolling stock as outdoors.
const Batch := preload("res://assets/procedural/detail_batch.gd")
const Track := preload("res://scenes/travel/outdoors_track.gd")
const Bridge := preload("res://scenes/outdoors/external_resources.gd")
const Landscape := preload("res://scenes/travel/landscape.gd")
const DerailChart := preload("res://scenes/travel/derail_chart.gd")
const WheelRateChart := preload("res://scenes/travel/wheel_rate_chart.gd")
const ChartToggle := preload("res://scenes/travel/chart_toggle.gd")
const LateralForceChart := preload("res://scenes/travel/lateral_force_chart.gd")
const WheelsetDisplacementChart := preload("res://scenes/travel/wheelset_displacement_chart.gd")
const AttackAngleChart := preload("res://scenes/travel/attack_angle_chart.gd")
const LENGTH := 1000.0
const START := 45.0
const RAIL_TOP := 0.54
const TRAIN_HEAD_START_Z := -42.0
const TRAIN_HEAD_END_Z := -850.0
# 轮对（wheelset0720.glb）统一材质色：模型自带 5 种彩色材质，此处统一为单一颜色。
const WHEELSET_COLOR := "55586B"
const WHEELSET_PATHS := [
	"RunningGear/FrontBogieVisual/FrontWheelset",
	"RunningGear/FrontBogieVisual/RearWheelset",
	"RunningGear/RearBogieVisual/FrontWheelset",
	"RunningGear/RearBogieVisual/RearWheelset",
]
# 轮对补光：日光下车体把转向架压在阴影里，轮对（StandardMaterial3D）没有直接光，
# 材质自发光又太弱，因此每个轮对两侧外置一盏无阴影点光源，从外侧照亮车轮外侧面与轮辐。
const WHEELSET_LIGHT_COLOR := "ffe9cf"
const WHEELSET_LIGHT_ENERGY := 2.5
const WHEELSET_LIGHT_RANGE := 3.5
const WHEELSET_LIGHT_SIDES := [-1.0, 1.0]
const WHEELSET_LIGHT_OUTBOARD := 1.45
const WHEELSET_LIGHT_DROP := 0.15
# 车身专用 shader：保留原始贴图颜色，但隔离绿色天空环境光，
# 用中性环境光 + 直接光重建车身光照，避免被路堑两侧植被/天空染绿。
const BODY_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 albedo : source_color = vec4(0.85, 0.85, 0.86, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float ambient_energy : hint_range(0.0, 0.5) = 0.16;

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_tex, UV).rgb;
	METALLIC = 0.0;
	ROUGHNESS = 0.6;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * ndotl;
	DIFFUSE_LIGHT += ALBEDO * vec3(ambient_energy);
}
"""
# 轮对 shader：GLB 车轮外侧面法线通常朝内，StandardMaterial3D 从外侧看会全黑。
# 用 cull_disabled + FRONT_FACING 翻转法线，让外侧受光；同时保留基础自发光填充。
const WHEELSET_SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 albedo : source_color = vec4(0.333, 0.345, 0.42, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float emission_energy : hint_range(0.0, 2.0) = 0.35;

varying vec3 v_normal;

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = albedo.rgb * emission_energy;
	// 双面渲染：让朝向相机的一侧法线始终朝外，避免车轮外侧面（法线朝内）受光为负而发黑。
	vec3 to_cam = CAMERA_POSITION_WORLD - NODE_POSITION_WORLD;
	v_normal = dot(NORMAL, to_cam) < 0.0 ? -NORMAL : NORMAL;
}

void light() {
	vec3 N = normalize(v_normal);
	float ndotl = max(dot(N, LIGHT), 0.0);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * ALBEDO * ndotl;
}
"""
var bridge: ResourceFormatLoader
var train: Node3D
var camera: Camera3D
var arch_count := 0
var tracks: Array[MeshInstance3D] = []
var train_ok := false
var help: Label
var pos_spins: Array[SpinBox] = []
var rot_spins: Array[SpinBox] = []
var _updating_camera_controls := false
var train_progress := 0.0
var progress_slider: HSlider
var progress_label: Label
var progress_track: Control
var camera_controls_panel: Control
var cam_offset := Vector3.ZERO
var cam_rot := Vector3.ZERO
var _body_shader: Shader
var _wheelset_shader: Shader
var _wheelset_material: ShaderMaterial
var wheelset_lights: Array[OmniLight3D] = []
var derail_chart: Control
var wheel_rate_chart: Control
var lateral_force_chart: Control
var wheelset_displacement_chart: Control
var attack_angle_chart: Control
var chart_selectors: Control
var dynamics_toggles: Array[Button] = []
var wheel_geometry_toggles: Array[Button] = []
var _updating_chart_visibility := false
# 轮轨相机锚点：头车前转向架前轮对（一车一转向架一轴）。
var wheel_watch: Node3D
var wheel_view := false

func _ready() -> void:
	_environment()
	_corridor()
	_slopes()
	_vegetation()
	_train()
	camera = Camera3D.new()
	camera.name = "ReferenceCamera"
	camera.fov = 53
	camera.far = 1800
	add_child(camera)
	camera.current = true
	_reference_view()
	var layer := CanvasLayer.new()
	add_child(layer)
	help = Label.new()
	help.position = Vector2(24, 22)
	help.text = "TRAVEL  路堑铁路\n1 参考视角   2 列车近景   Ctrl+Shift+W 轮轨相机   D 脱轨系数   W 轮重减载率   F1 说明   Esc 返回"
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 5)
	layer.add_child(help)
	help.hide()
	_build_camera_controls(layer)
	_sync_camera_controls()
	_build_progress_bar(layer)
	derail_chart = DerailChart.new()
	derail_chart.name = "DerailChart"
	layer.add_child(derail_chart)
	wheel_rate_chart = WheelRateChart.new()
	wheel_rate_chart.name = "WheelRateChart"
	layer.add_child(wheel_rate_chart)
	derail_chart.show()
	wheel_rate_chart.show()
	lateral_force_chart = LateralForceChart.new()
	lateral_force_chart.name = "LateralForceChart"
	layer.add_child(lateral_force_chart)
	lateral_force_chart.hide()
	wheelset_displacement_chart = WheelsetDisplacementChart.new()
	wheelset_displacement_chart.name = "WheelsetDisplacementChart"
	layer.add_child(wheelset_displacement_chart)
	wheelset_displacement_chart.hide()
	attack_angle_chart = AttackAngleChart.new()
	attack_angle_chart.name = "AttackAngleChart"
	layer.add_child(attack_angle_chart)
	attack_angle_chart.hide()
	_build_chart_selectors(layer)
	if not train_ok:
		help.text = "列车资源加载失败，请检查 E:/game_project 或 --external-project 参数。"
		help.show()
	if "--demo-smoke-test" in OS.get_cmdline_user_args():
		var ok := train_ok and tracks.size() == 2 and arch_count > 500
		ok = ok and derail_chart.error_text.is_empty() and derail_chart.sample_count == 16384
		ok = ok and wheel_rate_chart.error_text.is_empty() and wheel_rate_chart.sample_count == 16384
		ok = ok and wheelset_displacement_chart.error_text.is_empty() and wheelset_displacement_chart.sample_count == 41875
		ok = ok and attack_angle_chart.error_text.is_empty() and attack_angle_chart.sample_count == 41875
		ok = ok and wheelset_lights.size() == 4 * WHEELSET_PATHS.size() * WHEELSET_LIGHT_SIDES.size()
		for track in tracks:
			ok = ok and track.mesh != null and track.sleeper_instance_count > 2000
			ok = ok and track.fastener_instance_count == track.sleeper_instance_count
			ok = ok and is_equal_approx(track.ballast_height_m + track.sleeper_height_m + track.rail_height_m, RAIL_TOP)
		print("TRAVEL_SMOKE ", "PASS" if ok else "FAIL", " arches=", arch_count, " train=", train_ok)
		get_tree().quit(0 if ok else 1)
	if "--travel-capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _build_camera_controls(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	camera_controls_panel = panel
	panel.position = Vector2(24, 76)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.06, 0.78)
	style.border_color = Color(0.4, 0.55, 0.66, 0.6)
	style.set_border_width_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var title := Label.new()
	title.text = "相机相对列车偏移（跟随）"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#eaf4fb"))
	column.add_child(title)
	column.add_child(_spin_row("pos", pos_spins, 3, -600.0, 600.0, 0.5))
	column.add_child(_spin_row("rot", rot_spins, 3, -180.0, 180.0, 0.5))
	var reset := Button.new()
	reset.text = "复位到参考视角"
	reset.pressed.connect(_reference_view)
	column.add_child(reset)


func _spin_row(label_text: String, target: Array, count: int, min_value: float, max_value: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 34
	label.add_theme_color_override("font_color", Color("#9fbdd4"))
	row.add_child(label)
	for i in range(count):
		var spin := SpinBox.new()
		spin.min_value = min_value
		spin.max_value = max_value
		spin.step = step
		spin.custom_minimum_size.x = 88
		spin.value_changed.connect(_on_camera_control_changed)
		target.append(spin)
		row.add_child(spin)
	return row


func _on_camera_control_changed(_value: float) -> void:
	if _updating_camera_controls or camera == null:
		return
	cam_offset = Vector3(pos_spins[0].value, pos_spins[1].value, pos_spins[2].value)
	cam_rot = Vector3(rot_spins[0].value, rot_spins[1].value, rot_spins[2].value)
	_apply_camera()


func _sync_camera_controls() -> void:
	if camera == null or pos_spins.is_empty():
		return
	_updating_camera_controls = true
	pos_spins[0].set_value_no_signal(cam_offset.x)
	pos_spins[1].set_value_no_signal(cam_offset.y)
	pos_spins[2].set_value_no_signal(cam_offset.z)
	rot_spins[0].set_value_no_signal(cam_rot.x)
	rot_spins[1].set_value_no_signal(cam_rot.y)
	rot_spins[2].set_value_no_signal(cam_rot.z)
	_updating_camera_controls = false


func _build_chart_selectors(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	chart_selectors = panel
	panel.position = Vector2(0, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.91,0.93,0.92,0.94)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6
	style.content_margin_right = 6
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var captions := ["脱轨系数","轮重减载率","轮轴横向力","轮对横向位移","轮对冲角"]
	var charts: Array[Control] = [derail_chart,wheel_rate_chart,lateral_force_chart,wheelset_displacement_chart,attack_angle_chart]
	dynamics_toggles.clear()
	wheel_geometry_toggles.clear()
	for i in range(charts.size()):
		var chart: Control = charts[i]
		var selector := ChartToggle.new()
		selector.caption = captions[i]
		selector.toggle_mode = true
		if i < 3:
			# 动力学图窗：勾选状态跟随窗口初始显隐（脱轨/轮重减载率开，轮轴横向力关）。
			selector.button_pressed = chart.visible
			dynamics_toggles.append(selector)
		else:
			# 轮对几何图窗：进入轮对视角时默认打开。
			selector.button_pressed = true
			wheel_geometry_toggles.append(selector)
		row.add_child(selector)
		selector.toggled.connect(func(on: bool): chart.visible = on)
		chart.visibility_changed.connect(func():
			if _updating_chart_visibility:
				return
			selector.set_pressed_no_signal(chart.visible)
			selector.queue_redraw())
	# 默认视角：显示动力学图窗，隐藏轮对几何图窗。
	_set_view_charts(false)

func _set_view_charts(wheel_mode: bool) -> void:
	# 动力学图窗只在默认视角显示；轮对几何图窗只在轮对视角显示。
	_updating_chart_visibility = true
	for toggle in dynamics_toggles:
		if is_instance_valid(toggle):
			toggle.visible = not wheel_mode
	for toggle in wheel_geometry_toggles:
		if is_instance_valid(toggle):
			toggle.visible = wheel_mode
	_sync_chart_windows()
	_updating_chart_visibility = false


func _sync_chart_windows() -> void:
	# 图窗可见性 = 所属视角可见 且 勾选框处于开启状态。
	if dynamics_toggles.size() >= 3:
		derail_chart.visible = dynamics_toggles[0].visible and dynamics_toggles[0].button_pressed
		wheel_rate_chart.visible = dynamics_toggles[1].visible and dynamics_toggles[1].button_pressed
		lateral_force_chart.visible = dynamics_toggles[2].visible and dynamics_toggles[2].button_pressed
	if wheel_geometry_toggles.size() >= 2:
		wheelset_displacement_chart.visible = wheel_geometry_toggles[0].visible and wheel_geometry_toggles[0].button_pressed
		attack_angle_chart.visible = wheel_geometry_toggles[1].visible and wheel_geometry_toggles[1].button_pressed


func _build_progress_bar(layer: CanvasLayer) -> void:
	var track := VBoxContainer.new()
	progress_track = track
	track.name = "JourneyProgressTrack"
	track.anchor_left = 0.08
	track.anchor_top = 1.0
	track.anchor_right = 0.92
	track.anchor_bottom = 1.0
	track.offset_top = -72.0
	track.offset_bottom = -16.0
	layer.add_child(track)
	progress_label = Label.new()
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_font_size_override("font_size", 17)
	progress_label.add_theme_color_override("font_color", Color.WHITE)
	progress_label.add_theme_color_override("font_outline_color", Color.BLACK)
	progress_label.add_theme_constant_override("outline_size", 4)
	track.add_child(progress_label)
	progress_slider = HSlider.new()
	progress_slider.min_value = 0.0
	progress_slider.max_value = 100.0
	progress_slider.step = 0.1
	progress_slider.custom_minimum_size = Vector2(0.0, 28.0)
	progress_slider.tooltip_text = "拖动以控制列车在线路上的位置"
	progress_slider.value_changed.connect(_on_progress_changed)
	track.add_child(progress_slider)
	_set_train_progress(0.0)


func _on_progress_changed(value: float) -> void:
	_set_train_progress(value / 100.0)
	if derail_chart != null:
		derail_chart.set_progress(value / 100.0)


func _set_train_progress(value: float) -> void:
	if train == null:
		return
	train_progress = clampf(value, 0.0, 1.0)
	var head_z := lerpf(TRAIN_HEAD_START_Z, TRAIN_HEAD_END_Z, train_progress)
	train.position.z = head_z - TRAIN_HEAD_START_Z
	_apply_camera()
	if progress_label != null:
		var mileage := START - head_z
		var total := START - TRAIN_HEAD_END_Z
		progress_label.text = "列车 %d m / %d m" % [roundi(mileage), roundi(total)]
	if progress_slider != null:
		progress_slider.set_value_no_signal(train_progress * 100.0)


func _mat(color: String, roughness: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = roughness
	return m

func _surface(color_a: String, color_b: String, scale_m: float) -> StandardMaterial3D:
	var m := _mat("ffffff", 0.82)
	var noise := FastNoiseLite.new()
	noise.seed = 172
	noise.frequency = 0.035
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color_a))
	ramp.set_color(1, Color(color_b))
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	m.albedo_texture = texture
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / scale_m
	return m

func _box(parent: Node, title: String, p: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = m
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = box
	node.position = p
	parent.add_child(node)
	return node

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4f88b8")
	sky_mat.sky_horizon_color = Color("cddce6")
	sky_mat.ground_horizon_color = Color("a8b09a")
	sky_mat.ground_bottom_color = Color("55604a")
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.14
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	# ACES + mild grading: keeps sky from clipping and adds photographic contrast.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.12
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.08
	# Contact shadows sell the scale of the seats, rails and arch ribs.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Aerial perspective: the far end of the 1 km cutting should wash out.
	env.fog_enabled = true
	env.fog_light_color = Color("c9dbe8")
	env.fog_density = 0.00055
	env.fog_sky_affect = 0.02
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.35
	sun.light_color = Color("fff2d8")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.06
	sun.light_angular_distance = 0.8
	add_child(sun)

func _corridor() -> void:
	var root := Node3D.new()
	root.name = "DoubleTrackCutting"
	add_child(root)
	var concrete := _surface("777b74", "b7b8ac", 1.5)
	_box(root, "Formation", Vector3(0, -0.25, START - LENGTH / 2), Vector3(15, 0.5, LENGTH), _surface("444b49", "777d77", 0.4))
	for side in [-1.0, 1.0]:
		var x: float = side * 2.3
		var track: MeshInstance3D = Track.new()
		track.name = "LeftTrack" if side < 0 else "RightTrack"
		track.ballast_width_m = 3.4
		track.ballast_height_m = 0.16
		track.sleeper_height_m = 0.22
		track.rail_height_m = 0.16
		track.rail_head_width_m = 0.07
		# 1.435 m between inner rail-head faces, 1.505 m between centres.
		track.rail_gauge_m = 1.505
		track.sleeper_spacing_m = 0.65
		root.add_child(track)
		var samples: Array[Dictionary] = []
		for d in range(0, int(LENGTH) + 1, 5):
			samples.append({"point": Vector3(x, 0, START - d), "forward": Vector3.FORWARD, "right": Vector3.RIGHT, "up": Vector3.UP, "distance": float(d)})
		track.set_custom_samples(samples)
		track.generate_track_mesh()
		track.mesh.surface_set_material(0, concrete)
		tracks.append(track)
		_box(root, "ServicePath", Vector3(side * 5.5, 0.025, START - LENGTH / 2), Vector3(1.25, 0.12, LENGTH), concrete)
		_box(root, "DrainChannel", Vector3(side * 6.4, -0.03, START - LENGTH / 2), Vector3(0.45, 0.07, LENGTH), _mat("303b39"))
		for dx in [-0.29, 0.29]:
			_box(root, "DrainEdge", Vector3(side * 6.4 + dx, 0.08, START - LENGTH / 2), Vector3(0.12, 0.22, LENGTH), concrete)
		for dx in [-0.27, 0.27]:
			_box(root, "CableTrough", Vector3(side * 4.55 + dx, 0.08, START - LENGTH / 2), Vector3(0.10, 0.18, LENGTH), concrete)
		var covers: Array[Transform3D] = []
		for d in range(0, int(LENGTH), 2):
			covers.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, 0.06, 1.97)), Vector3(side * 4.55, 0.19, START - d)))
		var unit := BoxMesh.new()
		unit.material = concrete
		Batch.batch(root, "CableCovers", unit, covers, 0)

func _slope_point(side: float, uphill: float, z: float) -> Vector3:
	return Vector3(side * (7.1 + uphill * 0.8), uphill * 0.6, z)

func _slopes() -> void:
	var root := Node3D.new()
	root.name = "ArchedSlopeProtection"
	add_child(root)
	var soil := Landscape.ground_material()
	var concrete := _surface("72756a", "b0ae9e", 0.7)
	var mesh := BoxMesh.new()
	mesh.material = concrete
	var poses: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		Landscape.slope(root, float(side), START, LENGTH, soil)
		_box(root, "UpperGround", Vector3(side * 38, 7.02, START - LENGTH / 2), Vector3(43, 0.3, LENGTH), soil)
		for level in [0.0, 3.9, 7.8, 12.0]:
			poses.append(Batch.beam(_slope_point(side, level, START) + Vector3(0, 0.16, 0), _slope_point(side, level, START - LENGTH) + Vector3(0, 0.16, 0), 0.18, 0.2))
		for d in range(0, int(LENGTH), 3):
			var z := START - float(d) - 1.5
			for row in range(3):
				var base := row * 3.9
				var points: Array[Vector3] = []
				points.append(_slope_point(side, base, z - 1.4))
				points.append(_slope_point(side, base + 1.85, z - 1.4))
				for segment in range(13):
					var angle := PI * segment / 12.0
					points.append(_slope_point(side, base + 1.85 + 1.4 * sin(angle), z - 1.4 * cos(angle)))
				points.append(_slope_point(side, base, z + 1.4))
				for i in range(points.size() - 1):
					if points[i].distance_to(points[i + 1]) > 0.001:
						poses.append(Batch.beam(points[i] + Vector3(0, 0.18, 0), points[i + 1] + Vector3(0, 0.18, 0), 0.15, 0.18))
				arch_count += 1
		# Steps climbing the bank, breaking up the repeating arch bays.
		for station in [20.0, 140.0, 320.0, 600.0]:
			for step in range(32):
				var p := _slope_point(side, float(step) * 0.375, START - station)
				poses.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.36, 0.16, 0.85)), p + Vector3(0, 0.18, 0)))
	Batch.batch(root, "ConcreteArchRibsAndSteps", mesh, poses, 0)

func _vegetation() -> void:
	Landscape.build(self, START, LENGTH)

func _train() -> void:
	var external := "E:/game_project"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--external-project="):
			external = arg.trim_prefix("--external-project=").replace("\\", "/").trim_suffix("/")
	bridge = Bridge.new()
	bridge.project_root = external
	ResourceLoader.add_resource_format_loader(bridge, true)
	if not FileAccess.file_exists(external.path_join("train/scenes/train_car.tscn")):
		push_error("Travel: outdoors train assets missing at " + external)
		return
	var packed := load("res://train/scenes/train_car.tscn") as PackedScene
	var middle := load("res://train/models/train2.glb") as PackedScene
	if packed == null or middle == null:
		return
	train = Node3D.new()
	train.name = "OutdoorsTrain"
	add_child(train)
	var spacing := 26.5
	for i in range(4):
		var car := Node3D.new()
		car.name = "Car_%d" % (i + 1)
		train.add_child(car)
		var model := packed.instantiate() as Node3D
		model.set_script(null)
		if i in [1, 2]:
			var mount := model.get_node("ModelMount")
			mount.get_node("Model").free()
			var body := middle.instantiate()
			body.name = "Model"
			mount.add_child(body)
		car.add_child(model)
		if i == 0:
			# 轮轨相机锚点：头车前转向架前轮对（一车一转向架一轴）的轴心。
			wheel_watch = model.get_node_or_null("RunningGear/FrontBogieVisual/FrontWheelset") as Node3D
		_restore_appearance(model)
		_tint_wheelsets(model)
		var bounds := AABB()
		var first := true
		for node in model.find_children("*", "MeshInstance3D", true, false):
			if node.mesh == null:
				continue
			var b: AABB = model.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
			bounds = b if first else bounds.merge(b)
			first = false
		if first:
			return
		var factor := 27.0 / bounds.size.z
		model.scale = Vector3.ONE * factor
		model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
		if i == 3:
			model.rotation.y = PI
			model.position.x *= -1
			model.position.z *= -1
		# Lead car faces the viewer; remaining cars extend into the cutting.
		car.rotation.y = PI
		car.position = Vector3(-2.3, RAIL_TOP, -42 - i * spacing)
		_add_wheelset_lights(car, model)
	for i in range(3):
		_box(train, "Gangway_%d" % i, Vector3(-2.3, RAIL_TOP + 2.05, -42 - i * spacing - spacing * 0.5), Vector3(2.65, 2.75, 0.7), _mat("14181b"))
	train_ok = bridge.failures.is_empty() and train.get_child_count() == 7

func _restore_appearance(node: Node) -> void:
	# Same surface roles and opaque livery as outdoors' preview.
	if node is MeshInstance3D and node.mesh != null and node.name in ["TL0004", "TL0006"]:
		for i in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(i)
			var source_name := source.resource_name.to_lower() if source != null else ""
			var glass: bool = (node.name == "TL0004" and i in [1, 3, 5]) or (node.name == "TL0006" and i == 3)
			for token in ["glass", "wind", "shield", "window", "m_08", "material.001"]:
				glass = glass or source_name.contains(token)
			var band := (node.name == "TL0004" and i in [0, 1, 6, 8]) or (node.name == "TL0006" and i == 6)
			if not glass and not band:
				# 车身主体：保留原始贴图与基色，用 shader 隔离绿色环境光。
				node.set_surface_override_material(i, _body_material(source))
				continue
			var m := StandardMaterial3D.new()
			if source is StandardMaterial3D:
				m.albedo_color = source.albedo_color
				m.albedo_texture = source.albedo_texture
			if band:
				m.albedo_color = Color(0.06, 0.10, 0.22)
			if glass:
				m.albedo_color = Color(0.055, 0.075, 0.10)
			m.roughness = 0.38 if glass else 0.65
			m.metallic_specular = 0.35 if glass else 0.22
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_color.a = 1
			node.set_surface_override_material(i, m)
	for child in node.get_children():
		_restore_appearance(child)


func _tint_wheelsets(model: Node) -> void:
	# 轮对统一材质色 #55586B：wheelset0720.glb 自带橙/蓝/白等 5 种材质，这里整体覆盖。
	# 覆盖只写在各 MeshInstance3D 的 material_override 上，不修改共享网格资源。
	for path in WHEELSET_PATHS:
		var wheelset := model.get_node_or_null(path)
		if wheelset != null:
			_tint_wheelset_recursive(wheelset)


func _add_wheelset_lights(car: Node3D, model: Node3D) -> void:
	# 灯挂在车厢节点下（不缩放），按轮对轴心的世界位置换算局部位置，
	# 两侧各一盏，保证从外侧看车轮外侧面时受光。
	for path in WHEELSET_PATHS:
		var wheelset := model.get_node_or_null(path) as Node3D
		if wheelset == null:
			continue
		var axle := wheelset.global_position
		for side in WHEELSET_LIGHT_SIDES:
			var light := OmniLight3D.new()
			light.name = "WheelsetLight"
			light.light_color = Color(WHEELSET_LIGHT_COLOR)
			light.light_energy = WHEELSET_LIGHT_ENERGY
			light.omni_range = WHEELSET_LIGHT_RANGE
			light.shadow_enabled = false
			light.visible = false
			car.add_child(light)
			light.global_position = axle + Vector3(side * WHEELSET_LIGHT_OUTBOARD, -WHEELSET_LIGHT_DROP, 0.0)
			wheelset_lights.append(light)


func _set_wheelset_lights_enabled(enabled: bool) -> void:
	for light in wheelset_lights:
		if is_instance_valid(light):
			light.visible = enabled


func _tint_wheelset_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _get_wheelset_material()
	for child in node.get_children():
		_tint_wheelset_recursive(child)


func _get_wheelset_material() -> ShaderMaterial:
	if _wheelset_material == null:
		if _wheelset_shader == null:
			_wheelset_shader = Shader.new()
			_wheelset_shader.code = WHEELSET_SHADER
		_wheelset_material = ShaderMaterial.new()
		_wheelset_material.shader = _wheelset_shader
		_wheelset_material.set_shader_parameter("albedo", Color(WHEELSET_COLOR))
		_wheelset_material.set_shader_parameter("roughness", 0.4)
		_wheelset_material.set_shader_parameter("metallic", 0.0)
		_wheelset_material.set_shader_parameter("emission_energy", 0.6)
	return _wheelset_material


func _body_material(source: Material) -> ShaderMaterial:
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = BODY_SHADER
	var material := ShaderMaterial.new()
	material.shader = _body_shader
	if source is StandardMaterial3D:
		material.set_shader_parameter("albedo_tex", source.albedo_texture)
		material.set_shader_parameter("albedo", source.albedo_color)
	return material

func _reference_view() -> void:
	# 参考视角：相对列车车头的偏移与旋转（pos 单位米，rot 单位度）。
	wheel_view = false
	_set_wheelset_lights_enabled(false)
	_set_view_charts(false)
	cam_offset = Vector3(10.5, 12.0, 41.0)
	cam_rot = Vector3(-22.5, 0.0, 0.0)
	_apply_camera()
	_sync_camera_controls()


func _train_head_world() -> Vector3:
	if train == null:
		return Vector3(-2.3, RAIL_TOP, TRAIN_HEAD_START_Z)
	return Vector3(-2.3, RAIL_TOP, TRAIN_HEAD_START_Z) + train.position


func _set_view_world(pos: Vector3, target: Vector3) -> void:
	if camera == null:
		return
	wheel_view = false
	_set_wheelset_lights_enabled(false)
	_set_view_charts(false)
	camera.position = pos
	camera.look_at(target, Vector3.UP)
	cam_offset = camera.position - _train_head_world()
	cam_rot = camera.rotation_degrees
	_sync_camera_controls()


func _wheelset_view() -> void:
	# 轮轨相机：贴近观察头车第一转向架第一轴的轮轨接触区；再次触发退回参考视角。
	if wheel_view:
		_reference_view()
		return
	if wheel_watch == null or not is_instance_valid(wheel_watch):
		_reference_view()
		return
	var axle := wheel_watch.global_position
	# 将车体挡在右侧 (x > -0.52) 之外，从轨道间隙侧低角度观察轮对。
	_set_view_world(axle + Vector3(2.30, -0.40, 1.10), axle + Vector3(0.0, -0.39, 0.0))
	wheel_view = true
	_set_wheelset_lights_enabled(true)
	_set_view_charts(true)


func _apply_camera() -> void:
	if camera == null:
		return
	camera.position = _train_head_world() + cam_offset
	camera.rotation_degrees = cam_rot

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_G and event.ctrl_pressed and event.shift_pressed \
			and not event.alt_pressed and not event.meta_pressed:
		# Ctrl+Shift+G 切换进度条与相机控制面板显隐。
		if camera_controls_panel != null:
			camera_controls_panel.visible = not camera_controls_panel.visible
		if progress_track != null:
			progress_track.visible = not progress_track.visible
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_W and event.ctrl_pressed and event.shift_pressed \
			and not event.alt_pressed and not event.meta_pressed:
		# Ctrl+Shift+W 切换轮轨相机（对准头车第一转向架第一轴）。
		_wheelset_view()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_1: _reference_view()
		KEY_2: _set_view_world(Vector3(6, 4.8, -19), Vector3(-2.3, 1.8, -48))
		KEY_D:
			if derail_chart != null:
				derail_chart.visible = not derail_chart.visible
		KEY_W:
			if wheel_rate_chart != null:
				wheel_rate_chart.visible = not wheel_rate_chart.visible
		KEY_F1: help.visible = not help.visible
		KEY_ESCAPE: get_tree().change_scene_to_file("res://app/local.tscn")

func _capture() -> void:
	for i in range(50):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("res://scenes/travel/preview.png")
	print("TRAVEL_CAPTURE ", error_string(error))
	# 细节图：先关闭进度条与相机控制面板（同 Ctrl+Shift+G），再隐藏列车与图窗，相机前移看向路堑深处。
	if camera_controls_panel != null:
		camera_controls_panel.visible = false
	if progress_track != null:
		progress_track.visible = false
	derail_chart.hide()
	wheel_rate_chart.hide()
	lateral_force_chart.hide()
	chart_selectors.hide()
	if train != null:
		train.visible = false
	camera.position = Vector3(2.3, 1.3, -160)
	camera.look_at(Vector3(2.3, 0.4, -500))
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var detail_error := get_viewport().get_texture().get_image().save_png("res://scenes/travel/track_detail.png")
	print("TRAVEL_DETAIL_CAPTURE ", error_string(detail_error))
	get_tree().quit(0 if error == OK and detail_error == OK and train_ok else 1)

func _exit_tree() -> void:
	if bridge != null:
		ResourceLoader.remove_resource_format_loader(bridge)
		bridge.clear_scene_uids()
