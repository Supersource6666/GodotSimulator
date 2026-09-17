extends "res://scenes/travel/derail_chart.gd"
## 轮重减载率曲线图窗（参考 WheelRateData.cs）。
## 每个轮对的左右轮各一条曲线（4 轴 × 2 轮 = 8 条）：
## 减载率 = (静轮重 - 动轮重) / 静轮重，静轮重取各轴首帧左右轮垂向力均值。

var _static_axle_load: Array[float] = []


func _ready() -> void:
	title_text = "轮重减载率"
	channel_text = "8 通道 · 单位 1"
	y_axis_text = "轮重减载率 (1)"
	series_count = 8
	y_axis_format = "%.4f"
	super._ready()
	# 位置紧挨脱轨系数图窗上方（无间隔）。
	position.y -= size.y


func _make_labels() -> PackedStringArray:
	var result := PackedStringArray()
	for k in range(1, 5):
		result.append("轴%d 左轮" % k)
	for k in range(1, 5):
		result.append("轴%d 右轮" % k)
	return result


func _process_row(cols: PackedStringArray) -> void:
	# 每轮对 6 值：[左Fx, 左Fy, 左Fz, 右Fx, 右Fy, 右Fz]
	# 首帧左右轮垂向力均值作为静轮重参考，逐轮计算减载率。
	if _static_axle_load.is_empty():
		for k in range(4):
			var fz_l0 := cols[2 + 6 * k + 2].to_float()
			var fz_r0 := cols[2 + 6 * k + 5].to_float()
			_static_axle_load.append((fz_l0 + fz_r0) * 0.5)
	for k in range(4):
		var fz_l := cols[2 + 6 * k + 2].to_float()
		var fz_r := cols[2 + 6 * k + 5].to_float()
		var static_load := _static_axle_load[k]
		series[k].append(_safe_div(static_load - fz_l, static_load))
		series[k + 4].append(_safe_div(static_load - fz_r, static_load))
