extends PanelContainer
## HUD for the forward_02 / DDPM online prediction carried inside
## railway_ltd.v1 UDP packets as state["prediction"].
##
## The eight targets are, in training order: N_r, N_l, c_x_r, c_y_r, c_z_r,
## c_x_l, c_y_l, c_z_l. Only N_r / N_l are forces (N); the six c targets keep
## the training-table units and are NOT wear depths, so they are printed raw.
##
## valid=0 means the 150 x 0.25 m window has not filled yet. Those zeros are
## NOT wheel unloading and must not be read as a derailment indicator.

var _label: Label
var _announced := false


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.text = "03 / DDPM 在线预测 · forward_02"
	title.add_theme_color_override("font_color", Color("65c6cd"))
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	_label = Label.new()
	_label.text = "等待 UDP 预测数据…"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_label)


func update_prediction(prediction: Dictionary) -> void:
	if _label == null or prediction.is_empty():
		return
	if int(prediction.get("valid", 0)) != 1:
		_label.text = "窗口未满（valid=0）\n当前零值不代表轮轨失载"
		return
	var n_r := float(prediction.get("N_r", 0.0))
	var n_l := float(prediction.get("N_l", 0.0))
	if not _announced:
		_announced = true
		# One-shot trace so a broken UDP link is visible without opening the scene.
		print("DDPM_HUD_FIRST_VALID: N_l=%.1f N N_r=%.1f N mileage=%.2f m" % [
			n_l, n_r, float(prediction.get("absolute_mileage_m", 0.0))])
	var lines := PackedStringArray()
	lines.append("法向力  左 %.2f kN    右 %.2f kN" % [n_l / 1000.0, n_r / 1000.0])
	lines.append("c_x     左 %.5f    右 %.5f" % [
		float(prediction.get("c_x_l", 0.0)), float(prediction.get("c_x_r", 0.0))])
	lines.append("c_y     左 %.5f    右 %.5f" % [
		float(prediction.get("c_y_l", 0.0)), float(prediction.get("c_y_r", 0.0))])
	lines.append("c_z     左 %.5f    右 %.5f" % [
		float(prediction.get("c_z_l", 0.0)), float(prediction.get("c_z_r", 0.0))])
	lines.append("源时间 %.3f s    推理 %.2f ms" % [
		float(prediction.get("source_time_s", 0.0)),
		float(prediction.get("inference_ms", 0.0))])
	lines.append("绝对里程 %.2f m" % float(prediction.get("absolute_mileage_m", 0.0)))
	if int(prediction.get("warning", 0)) == 1:
		lines.append("[!] 输入分布/物理值超出提示")
	_label.text = "\n".join(lines)
