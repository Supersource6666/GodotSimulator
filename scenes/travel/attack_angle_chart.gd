extends "res://scenes/travel/derail_chart.gd"
## 轮对冲角（摇头角/攻角）曲线图窗（读取 wx.dat 的一轮~三轮 + 六轮冲角位移，单位 °）。
## 数据列：14~17 为一轮/二轮/三轮/六轮冲角（表头原文，六轮实为第四轮）。


func _ready() -> void:
	title_text = "轮对冲角（摇头角）"
	channel_text = "4 通道 · °"
	y_axis_text = "冲角 (°)"
	series_count = 4
	y_axis_format = "%.6f"
	data_path = "res://offline_data/dynamic_data/wx.dat"
	space_separated = true
	skip_lines = 4
	time_col = 0
	min_cols = 18
	plot_stride = 20
	super._ready()
	# 靠近右下角（轮对视角下动力学图窗隐藏，此处空闲）。


func _make_labels() -> PackedStringArray:
	return PackedStringArray(["轮对I冲角", "轮对II冲角", "轮对III冲角", "轮对IV冲角"])


func _process_row(cols: PackedStringArray) -> void:
	for k in range(4):
		series[k].append(cols[14 + k].to_float())
