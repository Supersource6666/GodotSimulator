extends "res://scenes/travel/derail_chart.gd"
## 轮对横向位移曲线图窗（读取 wx.dat 的一轮~四轮横向位移，单位 mm）。
## 数据列：0 时间，1 车速，2~5 一轮~四轮横向位移。


func _ready() -> void:
	title_text = "轮对横向位移"
	channel_text = "4 通道 · mm"
	y_axis_text = "横向位移 (mm)"
	series_count = 4
	y_axis_format = "%.4f"
	data_path = "res://offline_data/dynamic_data/wx.dat"
	space_separated = true
	skip_lines = 4
	time_col = 0
	min_cols = 18
	plot_stride = 20
	super._ready()
	# 紧挨轮对冲角图窗上方。
	position.y -= size.y


func _make_labels() -> PackedStringArray:
	return PackedStringArray(["轮对I", "轮对II", "轮对III", "轮对IV"])


func _process_row(cols: PackedStringArray) -> void:
	for k in range(4):
		series[k].append(cols[2 + k].to_float())
