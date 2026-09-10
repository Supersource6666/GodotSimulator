extends Node3D
## 程序化高架桥/桥梁生成器
## 参考图：单箱梁 + 两侧走道 + 黑色金属栏杆 + 桥墩
## 位置约定：track 在 y=0，桥在 y=0 之下（track 坐在箱梁顶上）

# ─── 桥墩配置 ───
const PIER_SPACING := 80.0             # 桥墩间距（米）
const GIRDER_SEGMENT_MAX_LENGTH := 20.0 # 曲线段最大长度，避免整跨直梁切过弯道
const COLUMN_COUNT := 3                # 每墩立柱数量
const COLUMN_RADIUS := 0.85            # 圆柱半径
const COLUMN_SPREAD := 2.8             # 立柱横向间距
const PIER_MIN_HEIGHT := 5.4           # 最小桥墩高度 = 结构总高(箱梁3+墩帽1.4+横梁1)，低于此值不建桥墩
const PIER_MAX_HEIGHT := 80.0          # 最大桥墩高度
const BASE_HEIGHT := 0.6               # 承台底座高度
const CROSS_BEAM_HEIGHT := 1.0         # 墩顶横梁高度

# ─── 箱梁配置（顶面在 track 位置 y=0） ───
const GIRDER_TOTAL_HEIGHT := 3.0       # 箱梁总高
const GIRDER_TOP_WIDTH := 12.0         # 顶板宽度
const GIRDER_BOTTOM_WIDTH := 6.4       # 底板宽度
const GIRDER_TOP_THICK := 0.4          # 顶板厚
const GIRDER_BOTTOM_THICK := 0.35      # 底板厚
const PIER_CAP_HEIGHT := 1.4           # 墩帽高度
const PIER_CAP_OVERHANG := 0.7         # 墩帽外挑
const WALKWAY_WIDTH := 1.2             # 边缘走道宽度
const WALKWAY_THICK := 0.25            # 走道板厚

# ─── 栏杆配置 ───
const RAILING_HEIGHT := 1.15           # 栏杆总高
const POST_SPACING := 3.5              # 立柱间距
const POST_SIZE := 0.08                # 立柱截面
const RAIL_THICK := 0.06               # 横杆粗细
const RAILING_INSET := 0.15            # 栏杆相对走道边缘内缩

# ─── 色彩（除护栏外，全部统一深灰色） ───
const CONCRETE_COLOR := Color(0.32, 0.32, 0.32)
const DECK_COLOR := Color(0.30, 0.30, 0.30)
const WALKWAY_COLOR := Color(0.34, 0.34, 0.34)
const RAILING_COLOR := Color(0.04, 0.04, 0.04)
const JOINT_COLOR := Color(0.26, 0.26, 0.26)
const BASE_COLOR := Color(0.30, 0.30, 0.30)
const TERRAIN_COLLISION_MASK := 128
## 离线模式：无真实地形射线/无 Terrain3D 时，桥面(样本点)到虚构地面的距离。
## 地面 = 桥面样本点往下 virtual_ground_offset_m，用于生成可落地的桥墩视觉估计。
@export var virtual_ground_offset_m := 8.0

var _pier_parent: Node3D
var _girder_parent: Node3D
var _material_cache: Dictionary = {}
var _railing_material: StandardMaterial3D
var _built := false


func build_bridge(samples: Array, route_length: float, track_parent: Node3D, space_state) -> void:
	if _built:
		return
	if samples.size() < 2:
		return

	_pier_parent = Node3D.new()
	_pier_parent.name = "BridgePiers"
	track_parent.add_child(_pier_parent)

	_girder_parent = Node3D.new()
	_girder_parent.name = "BridgeGirders"
	track_parent.add_child(_girder_parent)

	var pier_data := _collect_pier_data(samples, route_length, space_state)

	for i in range(pier_data.size()):
		var pd: Dictionary = pier_data[i]
		if pd["pier_height"] >= PIER_MIN_HEIGHT:
			_build_pier(pd)

		if i < pier_data.size() - 1:
			var nd: Dictionary = pier_data[i + 1]
			_build_curved_girder_span(samples, route_length, pd, nd)

	_built = true


func clear_bridge() -> void:
	if _pier_parent:
		_pier_parent.queue_free()
		_pier_parent = null
	if _girder_parent:
		_girder_parent.queue_free()
		_girder_parent = null
	_built = false


# ══════════════════════════════════════════
# 数据采样与地形探测
# ══════════════════════════════════════════

func _collect_pier_data(samples: Array, route_length: float, space_state) -> Array:
	var list: Array = []
	var distance := 0.0
	while distance < route_length + 1.0:
		_append_pier(list, samples, route_length, clampf(distance, 0.0, route_length), space_state)
		distance += PIER_SPACING
	# 终点处补一跨，避免最后一跨悬空到不了线路终点。
	if not list.is_empty() and route_length - float(list[list.size() - 1]["distance"]) > 5.0:
		_append_pier(list, samples, route_length, route_length, space_state)
	return list


func _append_pier(list: Array, samples: Array, route_length: float, dist: float, space_state) -> void:
	var sample := _lerp_sample(samples, route_length, dist)
	var point: Vector3 = sample["point"]
	var up: Vector3 = sample["up"]
	var right: Vector3 = sample["right"]
	var tangent: Vector3 = sample["forward"]
	var ground_y := _find_ground(point, up, space_state)
	var pier_height := point.dot(up) - ground_y
	pier_height = clampf(pier_height, 0.0, PIER_MAX_HEIGHT)
	list.append({
		"point": point,
		"up": up,
		"right": right,
		"tangent": tangent,
		"ground_y": ground_y,
		"pier_height": pier_height,
		"distance": dist,
	})


func _lerp_sample(samples: Array, route_length: float, distance: float) -> Dictionary:
	if samples.is_empty():
		return {}

	var clamped_distance := clampf(distance, 0.0, route_length)
	var first_sample: Dictionary = samples[0]
	var last_sample: Dictionary = samples[samples.size() - 1]
	if clamped_distance <= float(first_sample.get("distance", 0.0)):
		return first_sample
	if clamped_distance >= float(last_sample.get("distance", route_length)):
		return last_sample

	var a := first_sample
	var b := last_sample
	for index in range(samples.size() - 1):
		var candidate_a: Dictionary = samples[index]
		var candidate_b: Dictionary = samples[index + 1]
		var a_distance := float(candidate_a.get("distance", 0.0))
		var b_distance := float(candidate_b.get("distance", route_length))
		if clamped_distance >= a_distance and clamped_distance <= b_distance:
			a = candidate_a
			b = candidate_b
			break

	var a_dist := float(a.get("distance", 0.0))
	var b_dist := float(b.get("distance", route_length))
	var t := clampf((clamped_distance - a_dist) / maxf(0.001, b_dist - a_dist), 0.0, 1.0)

	return {
		"point": (a["point"] as Vector3).lerp(b["point"] as Vector3, t),
		"forward": (a["forward"] as Vector3).lerp(b["forward"] as Vector3, t).normalized(),
		"up": (a["up"] as Vector3).lerp(b["up"] as Vector3, t).normalized(),
		"right": (a["right"] as Vector3).lerp(b["right"] as Vector3, t).normalized(),
		"distance": clamped_distance,
	}


func _find_ground(point: Vector3, up: Vector3, space_state) -> float:
	# 离线视觉模式（无物理地形）：桥面往下 virtual_ground_offset_m 作为虚构地面，
	# 使桥墩能生成出可读的结构，不依赖 TERRAIN_COLLISION_MASK 射线或 Terrain3D。
	if space_state == null:
		return point.dot(up) - virtual_ground_offset_m

	var query := PhysicsRayQueryParameters3D.create(
		point + up * 500.0,
		point - up * 500.0,
		TERRAIN_COLLISION_MASK,
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.has("position"):
		return (hit["position"] as Vector3).dot(up)
	# Fallback: Terrain3D（tianditu 模式）没有物理碰撞体，用 snap_point_to_terrain 采样
	var terrain_h: Variant = _sample_terrain3d_height(point)
	if terrain_h is Vector3:
		return (terrain_h as Vector3).dot(up)
	return point.dot(up) - virtual_ground_offset_m


func _sample_terrain3d_height(point: Vector3) -> Variant:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	var bridge := root.find_child("CesiumBridge", true, false) as Node
	if bridge == null or not bridge.has_method("snap_point_to_terrain"):
		return null
	var sampled: Variant = bridge.call("snap_point_to_terrain", point)
	if sampled is Vector3:
		return sampled as Vector3
	return null


# ══════════════════════════════════════════
# 桥墩：承台 + 圆柱 + 柱顶环 + 横梁 + 墩帽
# 位置：track 在 y=0，桥墩在 y=0 之下
# ══════════════════════════════════════════

func _build_pier(data: Dictionary) -> void:
	var point: Vector3 = data["point"]
	var up: Vector3 = data["up"]
	var right: Vector3 = data["right"]
	var tangent: Vector3 = data["tangent"]
	var pier_height: float = data["pier_height"]

	var pier_mat := _make_material(CONCRETE_COLOR)
	var cap_mat := _make_material(CONCRETE_COLOR, 0.7)
	var base_mat := _make_material(BASE_COLOR)
	var col_basis := Basis(tangent, up, right)

	# 桥墩结构总高度（track 之下，到横梁顶面）
	var structure_h := GIRDER_TOTAL_HEIGHT + PIER_CAP_HEIGHT + CROSS_BEAM_HEIGHT
	# 圆柱净高（横梁底到地面）：必须严格 = pier_height - structure_h，
	# 使柱子底部正好落在真实地面 ground_point 上（不悬空、不插入过深）。
	var column_h := pier_height - structure_h
	if column_h < 0.0:
		column_h = 0.0

	# 地面位置：桥面往下 pier_height 就是真实地形表面
	var ground_point := point - up * pier_height

	# ── 承台底座 ──
	var base_w := COLUMN_SPREAD * float(COLUMN_COUNT - 1) + COLUMN_RADIUS * 2.0 + 1.5
	var base_d := COLUMN_RADIUS * 2.0 + 1.5
	var base_box := BoxMesh.new()
	base_box.size = Vector3(base_d, BASE_HEIGHT, base_w)
	var base_mi := MeshInstance3D.new()
	base_mi.name = "Base_%d" % int(data["distance"])
	base_mi.mesh = base_box
	base_mi.material_override = base_mat
	base_mi.basis = col_basis
	base_mi.position = ground_point + up * (BASE_HEIGHT * 0.5)
	_pier_parent.add_child(base_mi)

	# ── 圆柱立柱（3 根） ──
	for col in range(COLUMN_COUNT):
		var lateral := (float(col) - float(COLUMN_COUNT - 1) * 0.5) * COLUMN_SPREAD
		# 圆柱底面 = 承台顶面
		var col_bottom := ground_point + up * BASE_HEIGHT + right * lateral
		var col_center := col_bottom + up * (column_h * 0.5)

		var col_cyl := CylinderMesh.new()
		col_cyl.top_radius = COLUMN_RADIUS * 0.92
		col_cyl.bottom_radius = COLUMN_RADIUS
		col_cyl.height = column_h
		col_cyl.radial_segments = 12

		var mi := MeshInstance3D.new()
		mi.name = "Column_%d_%d" % [int(data["distance"]), col]
		mi.mesh = col_cyl
		mi.material_override = pier_mat
		mi.basis = col_basis
		mi.position = col_center
		_pier_parent.add_child(mi)

		# ── 柱顶环带 ──
		var ring_h := 0.3
		var ring_cyl := CylinderMesh.new()
		ring_cyl.top_radius = COLUMN_RADIUS * 1.18
		ring_cyl.bottom_radius = COLUMN_RADIUS * 0.92
		ring_cyl.height = ring_h
		ring_cyl.radial_segments = 12
		var ring_mi := MeshInstance3D.new()
		ring_mi.name = "Ring_%d_%d" % [int(data["distance"]), col]
		ring_mi.mesh = ring_cyl
		ring_mi.material_override = cap_mat
		ring_mi.basis = col_basis
		ring_mi.position = col_bottom + up * column_h + up * (ring_h * 0.5)
		_pier_parent.add_child(ring_mi)

	# ── 墩帽（紧贴箱梁底面之下） ──
	# 箱梁底面在 y = -GIRDER_TOTAL_HEIGHT
	var cap_center := point - up * (GIRDER_TOTAL_HEIGHT + PIER_CAP_HEIGHT * 0.5)
	var cap_box := BoxMesh.new()
	cap_box.size = Vector3(PIER_CAP_OVERHANG * 2.5, PIER_CAP_HEIGHT,
		GIRDER_BOTTOM_WIDTH + 0.4)
	var cap_mi := MeshInstance3D.new()
	cap_mi.name = "PierCap_%d" % int(data["distance"])
	cap_mi.mesh = cap_box
	cap_mi.material_override = cap_mat
	cap_mi.basis = col_basis
	cap_mi.position = cap_center
	_pier_parent.add_child(cap_mi)

	# ── 墩顶横梁（墩帽之下） ──
	var cross_center := point - up * (GIRDER_TOTAL_HEIGHT + PIER_CAP_HEIGHT + CROSS_BEAM_HEIGHT * 0.5)
	var cross_box := BoxMesh.new()
	cross_box.size = Vector3(COLUMN_RADIUS * 2.0 + PIER_CAP_OVERHANG * 2,
		CROSS_BEAM_HEIGHT, base_w)
	var cross_mi := MeshInstance3D.new()
	cross_mi.name = "CrossBeam_%d" % int(data["distance"])
	cross_mi.mesh = cross_box
	cross_mi.material_override = cap_mat
	cross_mi.basis = col_basis
	cross_mi.position = cross_center
	_pier_parent.add_child(cross_mi)


# ══════════════════════════════════════════
# 箱梁段：顶板 + 腹板 + 底板 + 桥面 + 走道 + 栏杆 + 伸缩缝
# 位置约定：track 在 y=0，箱梁顶面也在 y=0
# ══════════════════════════════════════════

func _build_curved_girder_span(samples: Array, route_length: float, from_pier: Dictionary, to_pier: Dictionary) -> void:
	var from_distance := float(from_pier["distance"])
	var to_distance := float(to_pier["distance"])
	var span_distance := maxf(to_distance - from_distance, 0.0)
	if span_distance <= 0.001:
		return

	var segment_count := maxi(1, int(ceil(span_distance / GIRDER_SEGMENT_MAX_LENGTH)))
	var previous := from_pier
	for segment_index in range(segment_count):
		var t := float(segment_index + 1) / float(segment_count)
		var segment_distance := lerpf(from_distance, to_distance, t)
		var next_sample := _lerp_sample(samples, route_length, segment_distance)
		var is_last_segment := segment_index == segment_count - 1
		_build_girder_segment(previous, next_sample, is_last_segment, int(from_distance))
		previous = next_sample


func _build_girder_segment(from: Dictionary, to: Dictionary, build_joint := true, joint_marker_distance := -1) -> void:
	var f_p: Vector3 = from["point"]
	var t_p: Vector3 = to["point"]
	var f_up: Vector3 = from["up"]
	var t_up: Vector3 = to["up"]

	var mid := (f_p + t_p) * 0.5
	var mid_up := (f_up + t_up).normalized()
	var span := f_p.distance_to(t_p)
	if span <= 0.001:
		return
	var mid_tan := (t_p - f_p) - mid_up * (t_p - f_p).dot(mid_up)
	if mid_tan.length_squared() <= 0.000001:
		mid_tan = from.get("tangent", from.get("forward", Vector3.FORWARD)) as Vector3
	mid_tan = mid_tan.normalized()
	var mid_right := mid_tan.cross(mid_up).normalized()
	if mid_right.length_squared() <= 0.000001:
		mid_right = from.get("right", Vector3.RIGHT) as Vector3

	var girder_mat := _make_material(CONCRETE_COLOR)
	var walkway_mat := _make_material(WALKWAY_COLOR)
	var joint_mat := _make_material(JOINT_COLOR)
	var girder_basis := Basis(mid_tan, mid_up, mid_right)

	var web_h := GIRDER_TOTAL_HEIGHT - GIRDER_TOP_THICK - GIRDER_BOTTOM_THICK
	# track 在 y=0，箱梁顶面在 y=0
	# top slab: 0 ~ -0.4
	# web:     -0.4 ~ -0.4-web_h
	# bot slab: -0.4-web_h ~ -0.4-web_h-0.35

	# ── 顶板（最宽，y: 0 ~ -0.4） ──
	var top_box := BoxMesh.new()
	top_box.size = Vector3(span, GIRDER_TOP_THICK, GIRDER_TOP_WIDTH)
	var top_mi := MeshInstance3D.new()
	top_mi.name = "TopSlab_%d_%d" % [int(from["distance"]), int(to["distance"])]
	top_mi.mesh = top_box
	top_mi.material_override = girder_mat
	top_mi.basis = girder_basis
	top_mi.position = mid - mid_up * (GIRDER_TOP_THICK * 0.5)
	_girder_parent.add_child(top_mi)

	# ── 左右腹板（y: -0.4 ~ -0.4-web_h） ──
	for side in [-1.0, 1.0]:
		var web_lat: Vector3 = mid_right * side * (GIRDER_BOTTOM_WIDTH * 0.5)
		var web_box := BoxMesh.new()
		web_box.size = Vector3(span, web_h, 0.4)
		var web_mi := MeshInstance3D.new()
		web_mi.name = "Web_%s_%d_%d" % ["L" if side < 0 else "R",
			int(from["distance"]), int(to["distance"])]
		web_mi.mesh = web_box
		web_mi.material_override = girder_mat
		web_mi.basis = girder_basis
		web_mi.position = mid - mid_up * (GIRDER_TOP_THICK + web_h * 0.5) + web_lat
		_girder_parent.add_child(web_mi)

	# ── 底板（最窄，y: -0.4-web_h ~ -0.4-web_h-0.35） ──
	var bot_offset := GIRDER_TOP_THICK + web_h + GIRDER_BOTTOM_THICK * 0.5
	var bottom_box := BoxMesh.new()
	bottom_box.size = Vector3(span, GIRDER_BOTTOM_THICK, GIRDER_BOTTOM_WIDTH)
	var bottom_mi := MeshInstance3D.new()
	bottom_mi.name = "BottomSlab_%d_%d" % [int(from["distance"]), int(to["distance"])]
	bottom_mi.mesh = bottom_box
	bottom_mi.material_override = girder_mat
	bottom_mi.basis = girder_basis
	bottom_mi.position = mid - mid_up * bot_offset
	_girder_parent.add_child(bottom_mi)

	# ── 两侧走道板（浅色，靠箱梁外缘） ──
	const walkway_margin := 0.5
	for side in [-1.0, 1.0]:
		var walk_lat: Vector3 = mid_right * side * (GIRDER_TOP_WIDTH * 0.5 - WALKWAY_WIDTH * 0.5 - walkway_margin)
		var walk_box := BoxMesh.new()
		walk_box.size = Vector3(span, WALKWAY_THICK, WALKWAY_WIDTH)
		var walk_mi := MeshInstance3D.new()
		walk_mi.name = "Walkway_%s_%d_%d" % ["L" if side < 0 else "R",
			int(from["distance"]), int(to["distance"])]
		walk_mi.mesh = walk_box
		walk_mi.material_override = walkway_mat
		walk_mi.basis = girder_basis
		walk_mi.position = mid + mid_up * (WALKWAY_THICK * 0.5) + walk_lat
		_girder_parent.add_child(walk_mi)

	# ── 黑色金属栏杆 ──
	_build_railing(mid, mid_up, mid_right, mid_tan, span,
		5.0, int(from["distance"]), int(to["distance"]))

	# ── 伸缩缝标记（已隐藏） ──


# ══════════════════════════════════════════
# 栏杆：黑色金属立柱 + 2 道横杆
# 立于走道外侧边缘，顶面 y=+WALKWAY_THICK
# ══════════════════════════════════════════

func _build_railing(
	mid: Vector3, mid_up: Vector3, mid_right: Vector3, mid_tan: Vector3,
	span: float, track_strip_width: float, from_dist: int, to_dist: int
) -> void:
	var rail_mat := _make_railing_material()
	var rail_basis := Basis(mid_tan, mid_up, mid_right)
	# 走道顶面在 y=+WALKWAY_THICK
	var base_y := WALKWAY_THICK

	for side in [-1.0, 1.0]:
		var lat_dir: Vector3 = mid_right * side
		# 栏杆立于箱梁顶板最外侧（GIRDER_TOP_WIDTH/2 - RAILING_INSET）
		var edge_offset: Vector3 = lat_dir * (GIRDER_TOP_WIDTH * 0.5 - RAILING_INSET)
		var rail_base := mid + mid_up * base_y + edge_offset

		# ── 立柱（每隔 3.5m 一根） ──
		var post_count := ceili(span / POST_SPACING) + 1
		for i in range(post_count):
			var t := float(i) / float(maxi(1, post_count - 1))
			var post_base := rail_base + mid_tan * (span * (t - 0.5))
			var post_box := BoxMesh.new()
			post_box.size = Vector3(POST_SIZE, RAILING_HEIGHT, POST_SIZE)
			var post := MeshInstance3D.new()
			post.name = "Post_%s_%d_%d_%d" % ["L" if side < 0 else "R", from_dist, to_dist, i]
			post.mesh = post_box
			post.material_override = rail_mat
			post.basis = rail_basis
			post.position = post_base + mid_up * (RAILING_HEIGHT * 0.5)
			_girder_parent.add_child(post)

		# ── 2 道水平横杆 ──
		var rail_heights := [RAILING_HEIGHT * 0.45, RAILING_HEIGHT * 0.95]
		for r in range(2):
			var rail_box := BoxMesh.new()
			rail_box.size = Vector3(span, RAIL_THICK, RAIL_THICK)
			var rail := MeshInstance3D.new()
			rail.name = "Rail%d_%s_%d_%d" % [r, "L" if side < 0 else "R", from_dist, to_dist]
			rail.mesh = rail_box
			rail.material_override = rail_mat
			rail.basis = rail_basis
			rail.position = rail_base + mid_up * rail_heights[r]
			_girder_parent.add_child(rail)


# ══════════════════════════════════════════
# 材质工厂
# ══════════════════════════════════════════

func _make_material(color: Color, brightness: float = 1.0) -> StandardMaterial3D:
	var key := "%s_%.3f" % [color.to_html(), brightness]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color * brightness
	mat.roughness = 0.88
	mat.metallic = 0.01
	_material_cache[key] = mat
	return mat


func _make_railing_material() -> StandardMaterial3D:
	if _railing_material != null:
		return _railing_material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RAILING_COLOR
	mat.roughness = 0.42
	mat.metallic = 0.78
	_railing_material = mat
	return mat
