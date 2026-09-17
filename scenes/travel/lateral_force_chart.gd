extends "res://scenes/travel/derail_chart.gd"
## Signed axle lateral resultant: left Fy + right Fy in source force units.
func _ready() -> void:
	title_text = "轮轴横向力"
	channel_text = "4 通道"
	y_axis_text = "轮轴横向力（原始单位）"
	series_count = 4
	y_axis_format = "%.1f"
	super._ready()
	position.x = maxf(position.x-size.x-20,0)

func _make_labels() -> PackedStringArray:
	return PackedStringArray(["轴1","轴2","轴3","轴4"])

func _process_row(cols: PackedStringArray) -> void:
	for k in range(4):
		series[k].append(cols[3+6*k].to_float()+cols[6+6*k].to_float())
