extends RefCounted
## 两级局部平滑：先沿里程压低纵断面噪声，再对平面转角做二次倒圆。
## 均为局部算子，无全局样条过冲，端点保持不变。
const TRIM_M := 20.0          # 转角倒圆在两侧边上的切点距离上限
const TRIM_RATIO := 0.40      # 切点距离不超过相邻较短边的比例上限
const STEP_M := 1.0
## 纵断面预平滑：DEM 高程在个别短线段上会出现 ~0.6 m 尖峰（如 2.42 km 处一段
## 6.3 m 短边），使坡度在几米内突跳 ~5.9°。二次倒圆只作用于顶点附近，无法消除
## 这种低点数下的“坡度顶动”。这里先按水平里程对 Y 做高斯低通，把该尖峰压到
## <1°，列车与相机不再上下抖动；XZ 位置与端点完全保留。
const PROFILE_WINDOW_M := 120.0
## 圆滑完成后把线路按水平弧长统一重采样到 ~STEP_M 间距。
## 二次角部按参数 t 取样会在顶点附近造成点距不均（0.4~2 m），这里统一成
## 均匀 1 m 点距——消除“1 m 尺度”的点位抖动/不匀，避免视觉层按点索引取样本时出现跳动。
const RESAMPLE_STEP_M := 1.0
## Filter by distance, not source vertex density. Broad transitions remove the
## short alternating bends that remain after local corner rounding.
const PLAN_SIGMA_M := 30.0
const PLAN_RADIUS_M := 90.0

static func smooth(source: PackedVector3Array) -> PackedVector3Array:
	if source.size() < 3:
		return source.duplicate()
	var profiled := _smooth_profile(source, PROFILE_WINDOW_M)
	var result := PackedVector3Array([profiled[0]])
	for index in range(1, profiled.size() - 1):
		var point := profiled[index]
		var incoming := point - profiled[index - 1]
		var outgoing := profiled[index + 1] - point
		var before := incoming.length()
		var after := outgoing.length()
		if minf(before, after) < 0.001:
			continue
		var trim := minf(TRIM_M, minf(before, after) * TRIM_RATIO)
		var a := point - incoming / before * trim
		var b := point + outgoing / after * trim
		if result[-1].distance_to(a) > 0.001:
			result.append(a)
		var steps := maxi(4, ceili(trim * 2.0 / STEP_M))
		for step in range(1, steps + 1):
			var t := float(step) / steps
			result.append(a.lerp(point, t).lerp(point.lerp(b, t), t))
	result.append(profiled[-1])
	return _resample_uniform(_smooth_plan(_resample_uniform(result, RESAMPLE_STEP_M)), RESAMPLE_STEP_M)


static func _smooth_plan(points: PackedVector3Array) -> PackedVector3Array:
	var result := points.duplicate()
	var radius := ceili(PLAN_RADIUS_M / RESAMPLE_STEP_M)
	var weights := PackedFloat64Array()
	var weight_sum := 0.0
	for offset in range(-radius, radius + 1):
		var weight := exp(-0.5 * pow(offset * RESAMPLE_STEP_M / PLAN_SIGMA_M, 2.0))
		weights.append(weight)
		weight_sum += weight
	var last := points.size() - 1
	for i in range(1, last):
		# Accumulate local offsets in double precision, avoiding float32
		# cancellation at city-scale coordinates. Reflect around endpoints
		# so station positions stay fixed without a clamped-end kink.
		var dx := 0.0
		var dz := 0.0
		for offset in range(-radius, radius + 1):
			var j := i + offset
			var point: Vector3
			if j < 0:
				point = points[0] * 2.0 - points[mini(-j, last)]
			elif j > last:
				point = points[last] * 2.0 - points[maxi(2 * last - j, 0)]
			else:
				point = points[j]
			var weight := weights[offset + radius]
			dx += float(point.x - points[i].x) * weight
			dz += float(point.z - points[i].z) * weight
		result[i] = Vector3(points[i].x + dx / weight_sum, points[i].y, points[i].z + dz / weight_sum)
	return result


## 沿水平里程对高程做高斯加权低通；首末点与 XZ 坐标保持不变。
static func _smooth_profile(source: PackedVector3Array, window: float) -> PackedVector3Array:
	var count := source.size()
	var result := source.duplicate()
	if count < 3 or window <= 0.0:
		return result
	var chain := PackedFloat64Array()
	chain.resize(count)
	chain[0] = 0.0
	for i in range(1, count):
		var d := source[i] - source[i - 1]
		chain[i] = chain[i - 1] + Vector2(d.x, d.z).length()
	var sigma := maxf(window * 0.5, 1.0)
	var inv_two_sigma_sq := 1.0 / (2.0 * sigma * sigma)
	for i in range(1, count - 1):
		var weighted := 0.0
		var weight_sum := 0.0
		for j in range(count):
			var offset := chain[j] - chain[i]
			if absf(offset) > window:
				continue
			var weight := exp(-offset * offset * inv_two_sigma_sq)
			weighted += source[j].y * weight
			weight_sum += weight
		if weight_sum > 0.0:
			result[i] = Vector3(source[i].x, weighted / weight_sum, source[i].z)
	return result


static func _resample_uniform(points: PackedVector3Array, step: float) -> PackedVector3Array:
	var count := points.size()
	if count < 3:
		return points
	var chain := PackedFloat64Array()
	chain.resize(count)
	chain[0] = 0.0
	for i in range(1, count):
		var d := points[i] - points[i - 1]
		chain[i] = chain[i - 1] + Vector2(d.x, d.z).length()
	var total := chain[count - 1]
	var out := PackedVector3Array([points[0]])
	var target := step
	var index := 0
	while target < total - 0.5 * step:
		while index < count - 1 and chain[index + 1] < target:
			index += 1
		var seg_len := chain[index + 1] - chain[index]
		var fraction := (target - chain[index]) / seg_len if seg_len > 1e-6 else 0.0
		out.append(Vector3(lerpf(points[index].x, points[index + 1].x, fraction),
			lerpf(points[index].y, points[index + 1].y, fraction),
			lerpf(points[index].z, points[index + 1].z, fraction)))
		target += step
	if out[-1].distance_to(points[-1]) > 0.001:
		out.append(points[-1])
	return out
