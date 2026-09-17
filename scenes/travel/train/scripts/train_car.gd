class_name TrainCar
extends Node3D

const DEFAULT_MODEL_SCENE_PATH := "res://train/models/train1.glb"
const FRONT_BOGIE_LOCAL_Z_SIGN := -1.0
const REAR_BOGIE_LOCAL_Z_SIGN := 1.0
const DEFAULT_BOGIE_TRACK_HEIGHT_M := 0.70
const DEFAULT_WHEELSET_CENTER_HEIGHT_M := 0.48
# wheelset0720.glb 车轮实际半径（沿模型 AABB 实测）：轮对中心挂在 wheelset_center_height_m 处，
# 车轮踏面在轮对中心下方 wheel_radius 处。用中心高度减半径即可把踏面精确放到轨面（front_pos）上。
const DEFAULT_WHEELSET_VISUAL_RADIUS_M := 0.389
const DEFAULT_RUNNING_GEAR_LATERAL_OFFSET_M := -0.15
const DEFAULT_RUNNING_GEAR_LONGITUDINAL_OFFSET_M := 2.2
# 车体（车体中心）与转向架（转向架中心）在 Z 方向的最大安全相对位置（米）。
# 默认 bogie_distance_m/2 - L_o = 9 - 2.2 = 6.8m，留 0.2m 余量；用户若把 L_o 调到 0 或负值
# （转向架间距被压缩到 ≤ bogie_distance_m），转向架会被拉回 7m 处，避免车体与转向架穿模。
const MAX_BODY_BOGIE_Z_RELATIVE_M := 7.0

@export var track_manager_path: NodePath
@export var model_scene_path := DEFAULT_MODEL_SCENE_PATH
@export_range(1.0, 40.0, 0.1) var bogie_distance_m := 18.0
@export_range(0.0, 500000.0, 0.1) var current_s_m := 0.0
@export_range(0.0, 500.0, 0.1) var speed_kmh := 80.0
@export_range(0.0001, 10.0, 0.0001) var model_scale := 1.0
@export var model_axis_scale := Vector3(0.86, 0.9, 1.0)
@export var model_height_offset_m := 1.40
@export var model_vertical_offset_m := -0.9  # 仅车体相对轮对/转向架的上下微调（负值=车体整体下移，轮对与转向架保持不动）
@export var model_lateral_offset_m := 0.0
@export var model_longitudinal_offset_m := 0.0
@export var model_yaw_degrees := 0.0
@export var running_gear_lateral_offset_m := DEFAULT_RUNNING_GEAR_LATERAL_OFFSET_M
@export var running_gear_longitudinal_offset_m := DEFAULT_RUNNING_GEAR_LONGITUDINAL_OFFSET_M
@export var running_gear_longitudinal_shift_m := 0.0  # 走行部（转向架+轮对）整体前后平移（正值=整体后移，负值=整体前移）
@export var running_gear_rear_longitudinal_shift_m := 0.0  # 仅后（第二）转向架单独前后平移（正值=后移），前转向架不动
@export var running_gear_front_longitudinal_shift_m := 0.0  # 仅前（第一）转向架单独前后平移（正值=后移），后转向架不动
# 走行部（转向架 + 轮对）整体竖向偏移：正值抬高、负值压低。
# 贴轨基准算出的踏面正好与轨面（front_pos/rear_pos）相切，看起来"悬"在轨面上，
# 这里给一个固定的下压量让车轮略微坐进轨面，视觉上更贴合；车体（车头模型）不受影响。
const DEFAULT_RUNNING_GEAR_HEIGHT_OFFSET_M := -0.03
@export var running_gear_height_offset_m := DEFAULT_RUNNING_GEAR_HEIGHT_OFFSET_M  # 转向架与轮对在贴轨基础上的额外抬高（米），正值抬高、负值压低
@export var bogie_track_height_m := DEFAULT_BOGIE_TRACK_HEIGHT_M
@export var bogie_model_local_offset := Vector3.ZERO
@export var bogie_model_height_offset_m := 0.08  # 仅转向架构架的竖向偏移（正值=构架整体上移，轮对/车轮不受影响）
@export var bogie_model_width_scale := 1.0  # 转向架整体横向缩放（变宽就调大）
@export var bogie_model_length_scale := 1.5  # 转向架整体纵向（前后）缩放：构架拉长、轮对按同一比例前后移动，相对位置不变；轮对模型本身不缩放
@export var wheelset_spacing_m := 1.8  # 轮对基准纵向间距（米）：实际位置 = 本值 × bogie_model_length_scale
@export var rear_wheelset_forward_shift_m := 0.10  # 仅后（第二）轮对沿车头方向的偏移（正值=前移、负值=后移；前轮对不动）
@export var wheelset_center_height_m := DEFAULT_WHEELSET_CENTER_HEIGHT_M
@export var wheelset_model_local_offset := Vector3.ZERO
@export_range(0.0, 5.0, 0.01) var roll_influence := 1.1
@export_range(0.0, 1.0, 0.01) var max_roll_rad := 0.10
@export var run_from_track_manager := false
@export var show_debug_body := false
@export var wheel_spin_local_axis := Vector3(0.0, 0.0, 1.0)  # 车轮自转所绕的模型局部轴（默认 glb 的 Z 轴）
# 每帧最大视觉转角（度）。高速时单帧转角若超过轮盘螺栓对称角的一半，
# 采样后会呈现"倒转/忽正忽反"的频闪错觉（wagon-wheel effect）。
# 以最常见的 8 螺栓车轮为例：螺栓间隔 = 360/8 = 45°，半角 = 22.5°。
# 限幅必须严格小于半角（否则会被视觉读成倒转）。这里取 16°，对 8 螺栓 (16/45=0.36<0.5) 与 10 螺栓 (16/36=0.44<0.5) 均稳定正转，
# 兼顾速度与防频闪；若车轮实为 12+ 螺栓（间隔 ≤30°，半角 ≤15°），请降到 14 避免重新出现频闪。
# 设为 360 即关闭限幅、严格按 ω = v/r 的真实转速滚动（高速下会重新出现频闪）。
@export var wheel_spin_max_visual_deg_per_frame := 16.0
# 视觉自转的目标角速度（度/秒）。用于"按时间"限幅，使画面转速不随帧率波动而忽快忽慢。
# 720 = 16°/帧 × 45fps：帧率 ≥45 时转速恒定为 720°/秒（= 2 圈/秒），不会因为运行到后期帧率下降而变慢；
# 仅当帧率低于 45fps 时才回落到单帧硬上限 16°/帧（进一步牺牲转速、保证不频闪倒转）。
# 若希望更快，可调高本值，但需同时保证「本值/期望最低帧率 ≤ 单帧硬上限」，否则又会随帧率下降而变慢。
@export var wheel_spin_visual_deg_per_sec := 720.0

var _track_manager: TrackManager
var _model_root: Node3D
var _debug_body: MeshInstance3D
var _running_gear_root: Node3D
var _front_bogie_visual: Node3D
var _rear_bogie_visual: Node3D
var _bogie_models: Array[Node3D] = []
var _wheelset_mounts: Array[Node3D] = []
var _wheelset_models: Array[Node3D] = []
var _last_forward := Vector3.FORWARD
var _roll_rad := 0.0
# 轮对视角下转向架/轮对半透明
var _bogie_material: StandardMaterial3D
var _wheelset_material: StandardMaterial3D
var _running_gear_transparent := false
var _wheel_rotation_rad := 0.0
var _wheelset_base_basis: Array[Basis] = []
var _load_logged := false
var _pose_logged := false
var _model_origin_normalized := false

# 轮对受力箭头
var _force_arrows_root: Node3D
# 每个轮对：[{shaft, head} × 6] = 左垂,左纵,左横, 右垂,右纵,右横
var _force_arrows_by_wheelset: Array[Array] = []
# 三支箭头按受力方向着色，与 _force_arrow_dirs 一一对应：
#   垂向（Y，向上）= 红，纵向（Z，沿线路）= 蓝，横向（X，跨轨）= 绿
var _force_arrow_colors := [Color(0.72, 0.03, 0.03, 1.0), Color(0.03, 0.13, 0.68, 1.0), Color(0.03, 0.50, 0.10, 1.0)]
var _force_arrow_dirs: Array[Vector3] = [Vector3.UP, Vector3.FORWARD, Vector3.LEFT]
const ARROW_BASE_SHAFT_HEIGHT := 0.28
const ARROW_BASE_HEAD_HEIGHT := 0.13
const ARROW_BASE_HEAD_RADIUS := 0.035
const ARROW_SHAFT_RADIUS := 0.016
const ARROW_SHAFT_TOP_RATIO := 0.7
const ARROW_BASE_RISE_M := 0.15  # 箭头组相对轮轨接触点上移（米）
const ARROW_RIGHT_WHEEL_SHIFT_M := -0.2  # 仅右轮箭头组的横向微调（米），正值=往车体右侧挪、负值=往轨道中心挪；左轮保持不动
const ARROW_LEFT_WHEEL_SHIFT_M := 0.04   # 仅左轮箭头组的横向微调（米），正值=往车体右侧（轨道中心）挪、负值=往车体左侧（轨道外侧）挪；右轮保持不动
const ARROW_RIGHT_WHEEL_DROP_M := 0.04  # 仅右轮箭头组的竖直微调（米），正值=整体下移；左轮保持不动
const ARROW_RIGHT_WHEEL_FORWARD_M := 0.025  # 仅右轮箭头组沿列车前进方向的偏移（米），正值=向前；与 ARROW_LEFT_WHEEL_FORWARD_M 同值即两组箭头前后对齐
const ARROW_LEFT_WHEEL_FORWARD_M := 0.05  # 仅左轮箭头组沿列车前进方向的偏移（米），正值=向前；与 ARROW_RIGHT_WHEEL_FORWARD_M 同值即两组前后对齐
const ARROW_LENGTH_SCALE := 0.75  # 沿箭头局部高度方向缩短，覆盖初始和实时受力长度
const ARROW_MIN_SCALE := 0.15
const ARROW_MIN_HEAD_SIZE := 0.030
const ARROW_MIN_SHAFT_RADIUS := 0.008

# 参考力值，用于归一化箭头长度
const REF_VERTICAL := 1.0
const REF_LONGITUDINAL := 1.0
const REF_LATERAL := 50000.0

# 轮对视角下转向架/轮对的半透明程度（0=全透明，1=不透明）
# X 键切换：默认不透明；按下后转向架/轮对变成半透明（半透），方便看到背后的接触应力云图。
const RUNNING_GEAR_TRANSPARENT_ALPHA := 0.5

@onready var model_mount: Marker3D = $ModelMount
@onready var front_bogie_marker: Marker3D = $FrontBogie
@onready var rear_bogie_marker: Marker3D = $RearBogie


func _ready() -> void:
	_track_manager = get_node_or_null(track_manager_path) as TrackManager
	_ensure_model_loaded()
	_ensure_running_gear_loaded()
	_ensure_wheelset_click_colliders()
	_ensure_force_arrows()
	_ensure_debug_body()


func _process(delta: float) -> void:
	if not run_from_track_manager or _track_manager == null:
		return

	var curve := _track_manager.get_curve()
	if curve == null:
		return

	var total_length := curve.get_baked_length()
	if total_length <= 0.0:
		return

	current_s_m = fposmod(current_s_m + speed_kmh / 3.6 * delta, total_length)
	var front_s := _track_manager.normalize_mileage(current_s_m + bogie_distance_m * 0.5)
	var rear_s := _track_manager.normalize_mileage(current_s_m - bogie_distance_m * 0.5)
	var front_transform := _track_manager.sample_transform(front_s)
	var rear_transform := _track_manager.sample_transform(rear_s)
	var curvature := _estimate_curvature(front_transform.origin, rear_transform.origin, bogie_distance_m)
	apply_bogie_constraint(front_transform.origin, rear_transform.origin, Vector3.UP, speed_kmh / 3.6, curvature, delta)


func apply_bogie_constraint(front_pos: Vector3, rear_pos: Vector3, up_axis: Vector3, speed_mps: float, curvature: float, delta: float) -> void:
	var up := up_axis.normalized()
	# 前进方向取前后转向架连线的真实方向（含坡度），车体随桥面一起俯仰。
	# 转向架/轮对不再挂在车体局部坐标里（否则坡度会让轮对相对轨面上下漂移），
	# 而是直接按前后转向架里程点的轨面法向定位，保证轮轨间距恒定。
	var forward := front_pos - rear_pos
	if forward.length_squared() <= 0.000001:
		forward = _last_forward
	forward = forward.normalized()
	_last_forward = forward

	# 横向轴保持水平（前×上），"上"轴与坡面垂直，保证车体三轴正交
	var right := forward.cross(up).normalized()
	if right.length_squared() <= 0.000001:
		right = Vector3.RIGHT
	var pitched_up := right.cross(forward).normalized()
	if pitched_up.length_squared() <= 0.000001:
		pitched_up = up

	var target_roll := clampf(-curvature * speed_mps * speed_mps * 0.01 * roll_influence, -max_roll_rad, max_roll_rad)
	var roll_weight := 1.0 if delta <= 0.0 else 1.0 - exp(-10.0 * delta)
	_roll_rad = lerpf(_roll_rad, target_roll, roll_weight)

	var body_pos := (front_pos + rear_pos) * 0.5 + pitched_up * model_height_offset_m
	var basis := Basis(right, pitched_up, -forward)
	basis = basis.rotated(forward, _roll_rad)
	basis = basis.rotated(pitched_up, deg_to_rad(model_yaw_degrees))
	global_transform = Transform3D(basis, body_pos)
	_update_model_mount_offset()

	_advance_wheel_rotation(speed_mps, delta)

	# 转向架基准则沿轨面法向/切向，不受车体侧滚影响（真实轮对也不侧滚）。
	var bogie_basis := Basis(right, pitched_up, -forward)
	# 先把轮对中心高度与车轮半径之差扣掉，让车轮踏面正好落在 front_pos/rear_pos（轨面）上；
	# running_gear_height_offset_m 则作为在贴轨基础上的"额外抬高"微调（正值抬高、负值压低）。
	var wheel_contact_offset := wheelset_center_height_m - DEFAULT_WHEELSET_VISUAL_RADIUS_M
	var gear_height := running_gear_height_offset_m - wheel_contact_offset
	# 走行部整体前后平移：正向为"后移"（沿车头方向的反方向），前后转向架一起同向平移。
	var gear_shift := -forward * running_gear_longitudinal_shift_m
	# 后（第二）转向架再单独后移一点。
	var rear_gear_shift := -forward * running_gear_rear_longitudinal_shift_m
	# 前（第一）转向架也可单独后移一点：轮对侧视等视角用来微调它相对车体的纵向位置。
	var front_gear_shift := -forward * running_gear_front_longitudinal_shift_m
	var front_target := front_pos + right * running_gear_lateral_offset_m - forward * running_gear_longitudinal_offset_m + pitched_up * gear_height + gear_shift + front_gear_shift
	var rear_target := rear_pos + right * running_gear_lateral_offset_m + forward * running_gear_longitudinal_offset_m + pitched_up * gear_height + gear_shift + rear_gear_shift
	# 防穿模：转向架中心相对车体中心的 Z 偏移绝对值不得超过 MAX_BODY_BOGIE_Z_RELATIVE_M。
	# 这是运行时 clamp，不修改 export 变量——用户调小 bogie_distance_m / 把 L_o 调 0 或负值时，
	# 转向架会被拉回安全位置，避免车体与转向架在车长方向相互穿插。
	var body_z := body_pos.dot(forward)
	var max_z := MAX_BODY_BOGIE_Z_RELATIVE_M
	var front_dz := front_target.dot(forward) - body_z
	var rear_dz := rear_target.dot(forward) - body_z
	if absf(front_dz) > max_z:
		front_target += forward * (max_z * signf(front_dz) - front_dz)
	if absf(rear_dz) > max_z:
		rear_target += forward * (max_z * signf(rear_dz) - rear_dz)
	if _front_bogie_visual != null:
		_front_bogie_visual.global_position = front_target
		_front_bogie_visual.global_basis = bogie_basis
	if _rear_bogie_visual != null:
		_rear_bogie_visual.global_position = rear_target
		_rear_bogie_visual.global_basis = bogie_basis
	front_bogie_marker.global_position = front_target
	rear_bogie_marker.global_position = rear_target
	_update_running_gear_positions()
	_log_pose_once(front_pos, rear_pos)


func set_model_scene_path(path: String) -> void:
	model_scene_path = path
	_clear_model()
	_ensure_model_loaded()


func apply_model_settings() -> void:
	_ensure_model_loaded()
	_ensure_running_gear_loaded()
	_ensure_debug_body()
	_update_model_mount_offset()
	if _model_root:
		_model_root.visible = true
		_apply_model_scale()
		_normalize_model_origin()
	_update_running_gear_positions()


func set_body_visible(is_visible: bool) -> void:
	_ensure_model_loaded()
	model_mount.visible = is_visible
	if _model_root:
		_model_root.visible = is_visible


func _update_model_mount_offset() -> void:
	# Y 方向只作用于车体（ModelMount），轮对/转向架按轨面独立定位，不受影响。
	model_mount.position = Vector3(model_lateral_offset_m, model_vertical_offset_m, model_longitudinal_offset_m)


func get_axle_wheelset_position(axle_index: int) -> Vector3:
	_ensure_running_gear_loaded()
	var axle_paths := [
		"RunningGear/FrontBogieVisual/FrontWheelset",
		"RunningGear/FrontBogieVisual/RearWheelset",
		"RunningGear/RearBogieVisual/FrontWheelset",
		"RunningGear/RearBogieVisual/RearWheelset",
	]
	var clamped_index := clampi(axle_index, 1, axle_paths.size()) - 1
	var axle := get_node_or_null(axle_paths[clamped_index]) as Node3D
	if axle != null:
		return axle.global_position
	if front_bogie_marker != null:
		return front_bogie_marker.global_position
	return global_position


# 转向架基准点的世界坐标（bogie_index: 1 = 前转向架，2 = 后转向架）。
# 与 apply_bogie_constraint 中赋给 FrontBogieVisual/RearBogieVisual 的落点一致（轨面上的转向架中心），
# 供"轮对侧视"这类贴近轨面的机位当基准：双线横移、坡度、转向架相对车体的偏摆都已包含在内。
func get_bogie_center_position(bogie_index: int) -> Vector3:
	_ensure_running_gear_loaded()
	var bogie := _front_bogie_visual if bogie_index <= 1 else _rear_bogie_visual
	if bogie != null:
		return bogie.global_position
	if front_bogie_marker != null:
		return front_bogie_marker.global_position
	return global_position


# 单独控制前（第一）/后（第二）转向架及其轮对的可见性。
# 轮对侧视（键 7）只留第一转向架，其它视角两个都要在，进入对应视角时恢复。
func set_bogie_visible(bogie_index: int, is_visible: bool) -> void:
	_ensure_running_gear_loaded()
	var bogie := _front_bogie_visual if bogie_index <= 1 else _rear_bogie_visual
	if bogie != null:
		bogie.visible = is_visible


# ---------------------------------------------------------------------------
# 轮轨接触点几何（点击拾取 → 接触应力云图）
# ---------------------------------------------------------------------------
# 左右轮横向半距，接触点拾取与受力箭头共用。
# 标准轨距 1435 mm 的一半：钢轨中心线的横向位置。
# 轮轨接触点、点击拾取、受力箭头组三者共用，保证箭头正好落在轨顶接触点（蓝点）上。
const CONTACT_HALF_GAUGE_M := 1.435 * 0.5


# 轮对的轮轨接触点在自身局部坐标下的位置：横向 ±half_gauge，纵向为零，
# 竖直方向为轮对中心向下一个滚动圆半径处（与踏面相切的轨面位置）。
func get_wheel_contact_local_points() -> Dictionary:
	var contact_height := -maxf(wheelset_center_height_m, 0.01)
	return {
		"left": Vector3(-CONTACT_HALF_GAUGE_M, contact_height, 0.0),
		"right": Vector3(CONTACT_HALF_GAUGE_M, contact_height, 0.0),
	}


# 指定轮对左右轮的轮轨接触点（世界坐标）。{"left": Vector3, "right": Vector3}
func get_wheel_contact_points(axle_index: int) -> Dictionary:
	_ensure_running_gear_loaded()
	var idx := clampi(axle_index, 1, maxi(_wheelset_mounts.size(), 1)) - 1
	if idx < 0 or idx >= _wheelset_mounts.size():
		return {}
	var mount := _wheelset_mounts[idx]
	var local_points := get_wheel_contact_local_points()
	return {
		"left": mount.to_global(local_points["left"]),
		"right": mount.to_global(local_points["right"]),
	}


# 判断一次射线命中落在车轴中线的哪一侧，返回 "left" / "right"。
# 直接比较命中点到左右两个轮轨接触点的世界距离，谁近就是哪只轮。
# 这样不依赖轮轴 X 轴的实际朝向（模型可能带 90°/180° 旋转），也不会因为
# 某个父节点镜像缩放而把两侧判成同一结果。
func get_contact_side_from_hit(axle_index: int, hit_position: Vector3) -> String:
	var points := get_wheel_contact_points(axle_index)
	if points.is_empty():
		return "left"
	var distance_left := hit_position.distance_squared_to(points["left"] as Vector3)
	var distance_right := hit_position.distance_squared_to(points["right"] as Vector3)
	return "left" if distance_left < distance_right else "right"


func _ensure_model_loaded() -> void:
	if _model_root != null:
		return

	var existing_model := model_mount.get_node_or_null("Model") as Node3D
	if existing_model != null:
		_model_root = existing_model
		_model_root.visible = true
		_apply_model_scale()
		_normalize_model_origin()
		_apply_livery_paint()
		if _remove_bottom_black_surfaces(_model_root):
			_model_origin_normalized = false
			_normalize_model_origin()
		_log_model_loaded()
		return

	if model_scene_path.is_empty():
		return

	var packed_scene := load(model_scene_path) as PackedScene
	if packed_scene == null:
		push_warning("TrainCar: model scene not found: %s" % model_scene_path)
		return

	_model_root = packed_scene.instantiate() as Node3D
	_model_root.name = "Model"
	model_mount.add_child(_model_root)
	_remove_embedded_bogies(_model_root)
	_apply_model_scale()
	_normalize_model_origin()
	_apply_livery_paint()
	if _remove_bottom_black_surfaces(_model_root):
		_model_origin_normalized = false
		_normalize_model_origin()
	_log_model_loaded()


# 递归删除模型自带的转向架节点（保留运行时动态添加的转向架）
func _remove_embedded_bogies(node: Node) -> void:
	# 先递归子节点（自下而上删除，避免迭代时修改）
	for child in node.get_children():
		_remove_embedded_bogies(child)
	# 匹配转向架/底盘常见命名（大小写不敏感）
	var keywords := [
		"bogie", "boggie", "转向架", "runninggear", "running_gear", "wheelset",
		"底盘", "底架", "chassis", "underframe", "under_body", "underbody",
		"undercarriage", "bottom", "frame"
	]
	var node_name_lc := node.name.to_lower()
	for kw in keywords:
		if node_name_lc.contains(kw):
			node.queue_free()
			return


# 车底黑色面剔除：
# train1.glb 整车只有一个 mesh（TL0004），车底一整块纯黑 surface
# （fallback Material.004，位于模型 Y 最底部、横跨全车长），无独立节点名，
# 因此按 surface 的空间位置 + 材质颜色判断并重建 mesh。
const BOTTOM_BLACK_SURFACE_RATIO := 0.3          # 模型高度底部比例
const BOTTOM_BLACK_SURFACE_LUM_THRESHOLD := 0.2  # 材质 RGB 亮度之和上限（判断"黑色"）

func _remove_bottom_black_surfaces(root: Node) -> bool:
	var removed_any := false
	if root is MeshInstance3D:
		removed_any = _remove_bottom_black_surfaces_from_mesh(root as MeshInstance3D) or removed_any
	for child in root.get_children():
		removed_any = _remove_bottom_black_surfaces(child) or removed_any
	return removed_any


func _remove_bottom_black_surfaces_from_mesh(mi: MeshInstance3D) -> bool:
	var mesh: Mesh = mi.mesh
	if mesh == null:
		return false
	var aabb := mesh.get_aabb()
	if aabb.size.y <= 0.0001:
		return false
	var bottom_threshold_y := aabb.position.y + aabb.size.y * BOTTOM_BLACK_SURFACE_RATIO
	var to_remove: Array[int] = []
	for i in mesh.get_surface_count():
		# 用 mesh 自带材质判断颜色（不受 material_override 影响）
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var albedo := (mat as StandardMaterial3D).albedo_color
			if albedo.r + albedo.g + albedo.b <= BOTTOM_BLACK_SURFACE_LUM_THRESHOLD:
				var arrays := mesh.surface_get_arrays(i)
				if arrays.is_empty():
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var surf_max_y := -INF
				for v in verts:
					if v.y > surf_max_y:
						surf_max_y = v.y
				if surf_max_y <= bottom_threshold_y:
					to_remove.append(i)
	if to_remove.is_empty():
		return false
	# 重建 mesh，仅保留非底部黑色 surface，并迁移材质
	var new_mesh := ArrayMesh.new()
	for i in mesh.get_surface_count():
		if i in to_remove:
			continue
		var arrays := mesh.surface_get_arrays(i)
		var blend_shapes := mesh.surface_get_blend_shape_arrays(i)
		var new_idx := new_mesh.get_surface_count()
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blend_shapes)
		var mat: Material = mi.get_surface_override_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		if mat != null:
			new_mesh.surface_set_material(new_idx, mat)
	# 先清空 override material（材质已迁移到新 mesh surface material），再替换 mesh
	for i in mesh.get_surface_count():
		mi.set_surface_override_material(i, null)
	mi.mesh = new_mesh
	print_rich("[color=orange]TrainCar: removed %d bottom black surface(s) from %s[/color]" % [to_remove.size(), mi.name])
	return true


func _ensure_debug_body() -> void:
	if _debug_body != null:
		_debug_body.visible = show_debug_body
		return

	_debug_body = MeshInstance3D.new()
	_debug_body.name = "DebugBody"
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 4.2, 28.0)
	_debug_body.mesh = box
	_debug_body.position = Vector3(0.0, 2.1, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.08, 0.04, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_body.material_override = material
	_debug_body.visible = show_debug_body
	add_child(_debug_body)


func _ensure_running_gear_loaded() -> void:
	if _running_gear_root != null:
		return

	var existing_root := get_node_or_null("RunningGear") as Node3D
	if existing_root == null:
		push_warning("TrainCar: RunningGear scene node is missing.")
		return

	_running_gear_root = existing_root
	_front_bogie_visual = _running_gear_root.get_node_or_null("FrontBogieVisual") as Node3D
	_rear_bogie_visual = _running_gear_root.get_node_or_null("RearBogieVisual") as Node3D
	_cache_running_gear_parts()
	_update_running_gear_positions()


func _cache_running_gear_parts() -> void:
	_bogie_models.clear()
	_wheelset_mounts.clear()
	_wheelset_models.clear()
	_wheelset_base_basis.clear()

	for bogie_visual in [_front_bogie_visual, _rear_bogie_visual]:
		if bogie_visual == null:
			continue
		var bogie_model := bogie_visual.get_node_or_null("BogieModel") as Node3D
		if bogie_model != null:
			_bogie_models.append(bogie_model)
		for wheelset_name in ["FrontWheelset", "RearWheelset"]:
			var wheelset_mount := bogie_visual.get_node_or_null(wheelset_name) as Node3D
			if wheelset_mount == null:
				continue
			_wheelset_mounts.append(wheelset_mount)
			var wheelset_model := wheelset_mount.get_node_or_null("WheelsetModel") as Node3D
			if wheelset_model != null:
				_wheelset_models.append(wheelset_model)
				# 记录模型自带的基准朝向（glb 实例化时带 90° 旋转），自转时叠加在它之上
				_wheelset_base_basis.append(wheelset_model.transform.basis)


func _ensure_wheelset_click_colliders() -> void:
	_ensure_running_gear_loaded()
	for i in range(_wheelset_mounts.size()):
		var mount := _wheelset_mounts[i]
		var axle_index := i + 1
		if mount.get_node_or_null("WheelsetClickArea") != null:
			continue
		var body := StaticBody3D.new()
		body.name = "WheelsetClickArea"
		body.collision_layer = 1 << 31
		body.collision_mask = 0
		body.set_meta("axle_index", axle_index)
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.height = 1.5
		cylinder.radius = wheelset_center_height_m * 1.15
		shape.shape = cylinder
		shape.rotation_degrees = Vector3(0.0, 0.0, -90.0)
		body.add_child(shape)
		mount.add_child(body)
	print_rich("[color=green]Wheelset click colliders created: %d[/color]" % _wheelset_mounts.size())


func _update_running_gear_positions() -> void:
	if _front_bogie_visual == null or _rear_bogie_visual == null:
		return
	# 转向架/轮对的世界坐标已在 apply_bogie_constraint 里按轨面法向定位；
	# 这里只调整转向架内部各子节点的相对位置（轮对轴距、模型偏移、材质等）。

	var bogie_mat := _get_bogie_material()
	# 构架可单独上移/下压，轮对与车轮位置不受影响（依旧贴着轨面）。
	for bogie_model in _bogie_models:
		bogie_model.position = bogie_model_local_offset + Vector3.UP * bogie_model_height_offset_m
		# 注意 bogie.glb 自带 90° 旋转：BogieModel 的局部 X 轴才是纵向（前后）、局部 Z 轴是横向（左右）。
		# 所以纵向缩放写在 X 分量、横向缩放写在 Z 分量，写反就会拉错方向。
		bogie_model.scale = Vector3(bogie_model_length_scale, 1.0, bogie_model_width_scale)
		_apply_wheelset_material_recursive(bogie_model, bogie_mat)

	for wheelset_mount in _wheelset_mounts:
		# 轮对局部 -Z 为车头方向：前轮对在 -Z 侧、后轮对在 +Z 侧
		var wheel_z := wheelset_spacing_m * 0.5
		if wheelset_mount.name == "FrontWheelset":
			wheel_z = -wheel_z
		else:
			# 后轮对向车头方向前移（正值=前移），前轮对不动
			wheel_z -= rear_wheelset_forward_shift_m
		# 轮对随构架一起纵向拉开：位置乘同一缩放比例，轮对与构架的相对位置保持不变。
		# 只移动轮对节点（wheelset_mount）的位置，轮对模型（WheelsetModel）不缩放，车轮保持正圆。
		wheel_z *= bogie_model_length_scale
		wheelset_mount.position = Vector3(0.0, wheelset_center_height_m, wheel_z)

	var wheelset_mat := _get_wheelset_material()
	for wheelset_model in _wheelset_models:
		wheelset_model.position = wheelset_model_local_offset
		_apply_wheelset_material_recursive(wheelset_model, wheelset_mat)


# 车轮滚动：按 v = ω·r 绕轮轴自转。
# WheelsetModel 自带 glb 的基准朝向，必须在其基础上叠加自转，否则模型的 90° 校正旋转会被覆盖。
# 自转在模型的局部空间做（后乘），轮轴方向由 wheel_spin_local_axis 指定。
func _advance_wheel_rotation(speed_mps: float, delta: float) -> void:
	if delta <= 0.0 or _wheelset_models.is_empty():
		return
	var wheel_radius := maxf(wheelset_center_height_m, 0.001)
	# 真实角速度 ω = v / r，方向恒为前进（角度递减）
	var step := speed_mps * delta / wheel_radius
	# 限幅：单帧视觉转角不超过阈值，避免轮盘周向对称特征被采样成倒转（wagon-wheel）。
	# 双限幅：以固定角速度(度/秒)为基准做"按时间"限幅，使画面转速不随帧率波动；
	# 帧率足够高时用单帧硬上限 16° 防频闪，帧率骤降时回落到硬上限（牺牲转速、保正转）。
	var hard_cap := deg_to_rad(maxf(wheel_spin_max_visual_deg_per_frame, 1.0))
	var time_cap := deg_to_rad(wheel_spin_visual_deg_per_sec) * delta
	var max_step := minf(hard_cap, time_cap)
	if absf(step) > max_step:
		step = signf(step) * max_step
	_wheel_rotation_rad = wrapf(_wheel_rotation_rad - step, -TAU, TAU)

	var spin_axis := wheel_spin_local_axis
	if spin_axis.length_squared() <= 0.000001:
		spin_axis = Vector3(0.0, 0.0, 1.0)
	spin_axis = spin_axis.normalized()
	var spin_basis := Basis(spin_axis, _wheel_rotation_rad)

	for i in range(_wheelset_models.size()):
		var wheelset_model := _wheelset_models[i]
		if wheelset_model == null:
			continue
		var base := _wheelset_base_basis[i] if i < _wheelset_base_basis.size() else wheelset_model.transform.basis
		var t := wheelset_model.transform
		t.basis = base * spin_basis
		wheelset_model.transform = t



func set_running_gear_transparent(is_transparent: bool) -> void:
	_ensure_running_gear_loaded()
	_running_gear_transparent = is_transparent
	_update_running_gear_positions()


func _get_bogie_material() -> StandardMaterial3D:
	if _bogie_material == null:
		_bogie_material = StandardMaterial3D.new()
		_bogie_material.albedo_color = Color(0.14, 0.14, 0.16)
		_bogie_material.metallic = 0.5
		_bogie_material.roughness = 0.4
	_apply_running_gear_alpha(_bogie_material)
	return _bogie_material


func _get_wheelset_material() -> StandardMaterial3D:
	if _wheelset_material == null:
		_wheelset_material = StandardMaterial3D.new()
		_wheelset_material.albedo_color = Color(0.58, 0.55, 0.52)
		_wheelset_material.metallic = 0.8
		_wheelset_material.roughness = 0.45
	# 轮对始终保持不透明，只有转向架随轮对视角半透明
	_wheelset_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var wheelset_color := _wheelset_material.albedo_color
	wheelset_color.a = 1.0
	_wheelset_material.albedo_color = wheelset_color
	return _wheelset_material


func _apply_running_gear_alpha(mat: StandardMaterial3D) -> void:
	var color := mat.albedo_color
	if _running_gear_transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		color.a = RUNNING_GEAR_TRANSPARENT_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		color.a = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color


func _apply_wheelset_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_wheelset_material_recursive(child, material)


func _clear_model() -> void:
	if _model_root == null:
		return
	_model_root.queue_free()
	_model_root = null
	_model_origin_normalized = false


func _apply_model_scale() -> void:
	if _model_root == null:
		return
	_model_root.scale = model_axis_scale * model_scale


func _normalize_model_origin() -> void:
	if _model_origin_normalized or _model_root == null:
		return

	var bounds := _get_visual_bounds_in_space(_model_root, model_mount)
	if bounds.size.length_squared() <= 0.000001:
		return

	var center := bounds.get_center()
	var offset := Vector3(-center.x, -bounds.position.y, -center.z)
	_model_root.position += offset
	_model_origin_normalized = true


func _log_model_loaded() -> void:
	if _load_logged or _model_root == null:
		return
	var bounds := _get_visual_bounds_in_space(_model_root, model_mount)
	print_rich("[color=cyan]TrainCar model loaded: %s visible=%s bounds_pos=%s bounds_size=%s scale=%s model_pos=%s[/color]" % [
		_model_root.get_path(),
		_model_root.visible,
		bounds.position,
		bounds.size,
		_model_root.scale,
		_model_root.position,
	])
	_load_logged = true


# 车体涂装：复兴号风格（深蓝上半 / 白下半 / 红色装饰条）。
# 车窗/侧窗/车顶天窗同样涂成不透明深色（全列车不透明）。
# 与 train_demo_scene.gd 中 _apply_livery_paint() 保持一致。
const TRAIN_LIVERY_NAVY := Color(0.06, 0.10, 0.22)
const TRAIN_LIVERY_DARK_GLASS := Color(0.05, 0.07, 0.10)  # 不透明深色玻璃
const TRAIN_LIVERY_WINDSHIELD_GLASS := Color(0.15, 0.16, 0.18, 0.1)  # 车头挡风玻璃（全透明）
const TRAIN_LIVERY_WINDOW_GLASS := Color(0.15, 0.16, 0.18, 0.55)  # 窗户（车厢侧窗）
const TRAIN_LIVERY_CLEAR_GLASS := Color(0.15, 0.16, 0.18, 0.1)  # 全透明玻璃（M_08 窗户）

func _apply_livery_paint() -> void:
	if _model_root == null:
		return
	const HEAD_NAVY_INDICES := [0, 1, 6, 8]
	const HEAD_GLASS_INDICES := [3, 5]  # 车头侧窗 + 车顶天窗 → 不透明深色
	const HEAD_WINDSHIELD_INDEX := 1  # 车头挡风玻璃 → 半透明灰玻璃
	const CARRIAGE_NAVY_INDICES := [6]
	const CARRIAGE_GLASS_INDICES := [3]  # 车厢侧窗带 → 不透明深色
	_livery_paint_mesh_by_indices(_model_root, "TL0004", HEAD_NAVY_INDICES, TRAIN_LIVERY_NAVY)
	_livery_paint_mesh_by_indices(_model_root, "TL0004", HEAD_GLASS_INDICES, TRAIN_LIVERY_DARK_GLASS)
	_livery_paint_glass_by_indices(_model_root, "TL0004", [HEAD_WINDSHIELD_INDEX], TRAIN_LIVERY_WINDSHIELD_GLASS)
	_livery_paint_mesh_by_indices(_model_root, "TL0006", CARRIAGE_NAVY_INDICES, TRAIN_LIVERY_NAVY)
	_livery_paint_glass_by_indices(_model_root, "TL0006", CARRIAGE_GLASS_INDICES, TRAIN_LIVERY_WINDOW_GLASS)
	# 窗户（M_08 材质）→ 半透明灰玻璃 + 反射
	_livery_paint_glass_by_material_name(_model_root, "M_08", TRAIN_LIVERY_CLEAR_GLASS)
	# fallback Material.001 → 半透明灰玻璃 + 反射
	_livery_paint_glass_by_material_name(_model_root, "fallback Material.001", TRAIN_LIVERY_CLEAR_GLASS)
	# 兜底：任何名字像玻璃的材质也设为半透明
	_livery_paint_glass_by_material_name_substrings(_model_root, ["glass", "wind", "shield", "window", "M_08", "Material.001"], TRAIN_LIVERY_CLEAR_GLASS)
	# 兜底：车头/车厢所有 surface 强制不透明（含车顶天窗等任何残留透明面）
	_force_all_surfaces_opaque(_model_root, "TL0004")
	_force_all_surfaces_opaque(_model_root, "TL0006")


func _livery_paint_mesh_by_indices(node: Node, mesh_name: String, indices: Array, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.name == mesh_name and mi.mesh != null:
			for i in indices:
				if i < mi.mesh.get_surface_count():
					var new_mat := StandardMaterial3D.new()
					new_mat.albedo_color = color
					new_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					new_mat.metallic = 0.0
					new_mat.metallic_specular = 0.0
					new_mat.roughness = 1.0
					new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					mi.set_surface_override_material(i, new_mat)
	for c in node.get_children():
		_livery_paint_mesh_by_indices(c, mesh_name, indices, color)


func _livery_paint_glass_by_indices(node: Node, mesh_name: String, indices: Array, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.name == mesh_name and mi.mesh != null:
			for i in indices:
				if i < mi.mesh.get_surface_count():
					var new_mat := StandardMaterial3D.new()
					new_mat.albedo_color = color
					new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					new_mat.metallic = 0.6
					new_mat.metallic_specular = 0.8
					new_mat.roughness = 0.15
					new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					mi.set_surface_override_material(i, new_mat)
	for c in node.get_children():
		_livery_paint_glass_by_indices(c, mesh_name, indices, color)


func _livery_paint_glass_by_material_name(node: Node, material_name: String, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var orig := mi.get_active_material(i)
				if orig != null and orig.resource_name == material_name:
					var new_mat := _create_train_glass_material(color, material_name)
					mi.set_surface_override_material(i, new_mat)
	for c in node.get_children():
		_livery_paint_glass_by_material_name(c, material_name, color)


func _livery_paint_glass_by_material_name_substrings(node: Node, substrings: Array, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var orig := mi.get_active_material(i)
				if orig == null:
					continue
				var lower_name := orig.resource_name.to_lower()
				for sub in substrings:
					if lower_name.find(sub.to_lower()) >= 0:
						var new_mat := _create_train_glass_material(color, orig.resource_name)
						mi.set_surface_override_material(i, new_mat)
						break
	for c in node.get_children():
		_livery_paint_glass_by_material_name_substrings(c, substrings, color)


func _create_train_glass_material(color: Color, resource_name: String) -> StandardMaterial3D:
	var new_mat := StandardMaterial3D.new()
	new_mat.resource_name = resource_name
	new_mat.albedo_color = color
	new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	new_mat.metallic = 0.6
	new_mat.metallic_specular = 0.8
	new_mat.roughness = 0.15
	new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return new_mat


# 兜底：把指定 mesh 的所有 surface 强制设为不透明（含原来未列出的透明面，如车顶天窗），并关闭反射/镜面、双面渲染。
func _force_all_surfaces_opaque(node: Node, mesh_name: String) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.name == mesh_name and mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var orig := mi.get_active_material(i)
				if orig == null:
					continue
				if mesh_name == "TL0004" and i == 1:
					continue
				if mesh_name == "TL0006" and i == 3:
					continue
				if _train_material_name_looks_like_glass(orig.resource_name):
					continue
				var new_mat := orig.duplicate() as BaseMaterial3D
				new_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				new_mat.metallic = 0.0
				new_mat.metallic_specular = 0.0
				new_mat.roughness = 1.0
				mi.set_surface_override_material(i, new_mat)
	for c in node.get_children():
		_force_all_surfaces_opaque(c, mesh_name)


func _train_material_name_looks_like_glass(material_name: String) -> bool:
	var lower_name := material_name.to_lower()
	var glass_keywords := ["glass", "wind", "shield", "window", "M_08", "Material.001"]
	for kw in glass_keywords:
		if lower_name.find(kw.to_lower()) >= 0:
			return true
	return false


func _log_pose_once(front_pos: Vector3, rear_pos: Vector3) -> void:
	if _pose_logged:
		return
	_pose_logged = true
	print_rich("[color=cyan]TrainCar pose: body=%s front=%s rear=%s[/color]" % [
		global_position,
		front_pos,
		rear_pos,
	])


func _get_visual_bounds(node: Node) -> AABB:
	var has_bounds := false
	var bounds := AABB()
	if node is VisualInstance3D:
		bounds = (node as VisualInstance3D).get_aabb()
		has_bounds = bounds.size.length_squared() > 0.000001
	for child in node.get_children():
		var child_bounds := _get_visual_bounds(child)
		if child_bounds.size.length_squared() <= 0.000001:
			continue
		bounds = bounds.merge(child_bounds) if has_bounds else child_bounds
		has_bounds = true
	return bounds


func _get_visual_bounds_in_space(node: Node, space: Node3D) -> AABB:
	var has_bounds := false
	var bounds := AABB()
	var to_space := space.global_transform.affine_inverse()
	if node is VisualInstance3D:
		var visual := node as VisualInstance3D
		var local_bounds := visual.get_aabb()
		if local_bounds.size.length_squared() > 0.000001:
			for corner in _get_aabb_corners(local_bounds):
				var point := to_space * visual.global_transform * corner
				if has_bounds:
					bounds = bounds.expand(point)
				else:
					bounds = AABB(point, Vector3.ZERO)
					has_bounds = true
	for child in node.get_children():
		if child is Node:
			var child_bounds := _get_visual_bounds_in_space(child, space)
			if child_bounds.size.length_squared() <= 0.000001:
				continue
			bounds = bounds.merge(child_bounds) if has_bounds else child_bounds
			has_bounds = true
	return bounds


func _get_aabb_corners(bounds: AABB) -> Array[Vector3]:
	var start := bounds.position
	var end := bounds.position + bounds.size
	return [
		Vector3(start.x, start.y, start.z),
		Vector3(end.x, start.y, start.z),
		Vector3(start.x, end.y, start.z),
		Vector3(end.x, end.y, start.z),
		Vector3(start.x, start.y, end.z),
		Vector3(end.x, start.y, end.z),
		Vector3(start.x, end.y, end.z),
		Vector3(end.x, end.y, end.z),
	]


func _estimate_curvature(front_pos: Vector3, rear_pos: Vector3, fallback_distance: float) -> float:
	var chord_length := front_pos.distance_to(rear_pos)
	if chord_length <= 0.001:
		return 0.0
	return clampf((fallback_distance - chord_length) / maxf(0.001, fallback_distance), -0.02, 0.02)


# ---------------------------------------------------------------------------
# 轮对受力箭头（仅在轮对视角下显示）
# ---------------------------------------------------------------------------
func _ensure_force_arrows() -> void:
	if _force_arrows_root != null:
		return
	_force_arrows_root = Node3D.new()
	_force_arrows_root.name = "ForceArrowsRoot"
	add_child(_force_arrows_root)
	_force_arrows_by_wheelset.clear()

	var contact_points := get_wheel_contact_local_points()

	for wheelset_mount in _wheelset_mounts:
		var wheel_arrows: Array[Dictionary] = []
		var mount := Node3D.new()
		mount.name = "WheelsetForceArrows"
		mount.position.y = ARROW_BASE_RISE_M
		wheelset_mount.add_child(mount)
		# 左右轮各一组箭头，以接触斑为基准整体略微抬高。
		for side in [-1.0, 1.0]:
			var wheel_node := Node3D.new()
			wheel_node.name = "WheelArrows_%d" % int(side)
			wheel_node.position = contact_points["right" if side > 0.0 else "left"]
			# 右轮单独横向/竖直微调，左轮单独纵向微调；两组其余方向仍对准接触点
			if side > 0.0:
				wheel_node.position.x += ARROW_RIGHT_WHEEL_SHIFT_M
				wheel_node.position.y -= ARROW_RIGHT_WHEEL_DROP_M
				# 轮对局部 -Z 为列车前进方向，正值的前移量需取负
				wheel_node.position.z -= ARROW_RIGHT_WHEEL_FORWARD_M
			else:
				wheel_node.position.x += ARROW_LEFT_WHEEL_SHIFT_M
				# 轮对局部 -Z 为列车前进方向，正值的前移量需取负
				wheel_node.position.z -= ARROW_LEFT_WHEEL_FORWARD_M
			mount.add_child(wheel_node)

			for i in range(3):
				var res := _create_force_arrow(_force_arrow_colors[i], _force_arrow_dirs[i])
				res.arrow.name = "ForceArrow%d" % i
				wheel_node.add_child(res.arrow)
				wheel_arrows.append(res)

		_force_arrows_by_wheelset.append(wheel_arrows)
		mount.visible = false


func _create_force_arrow(color: Color, direction: Vector3) -> Dictionary:
	var arrow := Node3D.new()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.45
	mat.roughness = 0.3
	mat.metallic = 0.15

	# 三个箭头底部共起点
	arrow.position = Vector3.ZERO

	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.bottom_radius = ARROW_SHAFT_RADIUS
	shaft_mesh.top_radius = ARROW_SHAFT_RADIUS * ARROW_SHAFT_TOP_RATIO
	shaft_mesh.height = ARROW_BASE_SHAFT_HEIGHT
	shaft.mesh = shaft_mesh
	shaft.material_override = mat
	shaft.position.y = ARROW_BASE_SHAFT_HEIGHT * 0.5
	arrow.add_child(shaft)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = ARROW_BASE_HEAD_RADIUS
	head_mesh.height = ARROW_BASE_HEAD_HEIGHT
	head.mesh = head_mesh
	head.material_override = mat
	head.position.y = ARROW_BASE_SHAFT_HEIGHT + ARROW_BASE_HEAD_HEIGHT * 0.5
	arrow.add_child(head)

	# 让 local +Y（圆柱高度方向）对齐 force 方向
	var y_axis := direction.normalized()
	var x_axis := Vector3.UP.cross(y_axis).normalized()
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT
	var z_axis := x_axis.cross(y_axis).normalized()
	arrow.basis = Basis(x_axis, y_axis * ARROW_LENGTH_SCALE, z_axis)

	return {"arrow": arrow, "shaft": shaft, "head": head}


func show_axle_force_arrows(axle_index: int) -> void:
	# axle_index 为 1~4
	for mount in _wheelset_mounts:
		for child in mount.get_children():
			if child.name == "WheelsetForceArrows":
				child.visible = false

	var mount_idx := axle_index - 1
	if mount_idx < 0 or mount_idx >= _wheelset_mounts.size():
		return
	for child in _wheelset_mounts[mount_idx].get_children():
		if child.name == "WheelsetForceArrows":
			child.visible = true


func hide_all_force_arrows() -> void:
	for mount in _wheelset_mounts:
		for child in mount.get_children():
			if child.name == "WheelsetForceArrows":
				child.visible = false


# 同时显示指定若干轴的力箭头（其余全部隐藏）。
# 轮对侧视（键 7）看的是第一转向架，需要轴 1、2 的箭头一起出现。
func show_force_arrows_for_axles(axle_indices: Array) -> void:
	hide_all_force_arrows()
	for axle_index in axle_indices:
		var mount_idx := int(axle_index) - 1
		if mount_idx < 0 or mount_idx >= _wheelset_mounts.size():
			continue
		for child in _wheelset_mounts[mount_idx].get_children():
			if child.name == "WheelsetForceArrows":
				child.visible = true


# magnitudes: [left_vert, left_long, left_lat, right_vert, right_long, right_lat]
func update_force_arrow_scales(axle_index: int, magnitudes: Array) -> void:
	var mount_idx := axle_index - 1
	if mount_idx < 0 or mount_idx >= _force_arrows_by_wheelset.size():
		return
	var arrows := _force_arrows_by_wheelset[mount_idx]
	for i in range(mini(arrows.size(), magnitudes.size())):
		var mag := absf(float(magnitudes[i]))
		var scale := clampf(mag, ARROW_MIN_SCALE, 1.5)
		var k := sqrt(scale)
		var info: Dictionary = arrows[i]
		var shaft := info.shaft as MeshInstance3D
		var head := info.head as MeshInstance3D
		if not shaft or not head:
			continue
		var shaft_h := ARROW_BASE_SHAFT_HEIGHT * k
		var shaft_r := maxf(ARROW_SHAFT_RADIUS * k, ARROW_MIN_SHAFT_RADIUS)
		var shaft_mesh := shaft.mesh as CylinderMesh
		if shaft_mesh:
			shaft_mesh.height = shaft_h
			shaft_mesh.bottom_radius = shaft_r
			shaft_mesh.top_radius = shaft_r * ARROW_SHAFT_TOP_RATIO
			shaft.position.y = shaft_h * 0.5
		var head_h := maxf(ARROW_BASE_HEAD_HEIGHT * k, ARROW_MIN_HEAD_SIZE)
		var head_r := maxf(ARROW_BASE_HEAD_RADIUS * k, ARROW_MIN_HEAD_SIZE * 0.7)
		var head_mesh := head.mesh as CylinderMesh
		if head_mesh:
			head_mesh.height = head_h
			head_mesh.bottom_radius = head_r
			head_mesh.top_radius = 0.0
		head.position.y = shaft_h + head_h * 0.5
