extends CanvasLayer
## Independent prediction overlay. Does not pretend predictions are vehicle poses.
signal prediction_received(message: Dictionary)
signal prediction_invalidated(reason: String)

@export var listen_address: String = "127.0.0.1"
@export var listen_port: int = 49111
@export var stale_seconds: float = 2.0
var last_prediction: Dictionary = {}
var valid: bool = false
var accepted_packets: int = 0
var _udp := PacketPeerUDP.new()
var _key: String = ""
var _sequence: int = -1
var _retired: Dictionary = {}
var _last_receive_ms: int = 0
var _label: Label
var _status: String = "等待 Simulink / DDPM UDP 数据 :49111"
const OUTPUTS := ["N_r", "N_l", "c_x_r", "c_y_r", "c_z_r", "c_x_l", "c_y_l", "c_z_l"]

func _ready() -> void:
	layer = 80
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 86)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.custom_minimum_size = Vector2(350, 110)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_label)
	_label.text = "DDPM forward_01 预测\n" + _status
	var error := _udp.bind(listen_port, listen_address)
	if error != OK:
		_invalidate("UDP 端口绑定失败：%d" % error)
		set_process(false)
	else:
		print("DDPM_UDP_READY %s:%d" % [listen_address, listen_port])

func _process(_delta: float) -> void:
	var limit: int = mini(_udp.get_available_packet_count(), 512)
	for _i in range(limit):
		var bytes := _udp.get_packet()
		if bytes.size() > 8192:
			continue
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if parsed is Dictionary:
			accept_message(parsed as Dictionary)
	if valid and Time.get_ticks_msec() - _last_receive_ms > int(stale_seconds * 1000.0):
		_invalidate("数据已超时，预测无效")

func accept_message(message: Dictionary) -> bool:
	if message.get("schema", "") != "rail.ddpm.prediction.v1" or message.get("model_id", "") != "forward_01":
		return false
	var key := String(message.get("service_id", "")) + ":" + String(message.get("session", ""))
	var sequence := int(message.get("seq", -1))
	if key == ":" or sequence < 0 or _retired.has(key):
		return false
	if key != _key:
		if not _key.is_empty():
			_retired[_key] = true
		_key = key
		_sequence = -1
	if sequence <= _sequence:
		return false
	_sequence = sequence
	accepted_packets += 1
	_last_receive_ms = Time.get_ticks_msec()
	var status := String(message.get("status", ""))
	if status != "prediction" or message.get("valid", false) != true:
		var reasons := {"model_unavailable": "模型未就绪", "warming_up": "空间窗口积累中", "invalid_synthesis": "合成信号尚未有效", "stale": "Simulink 数据超时"}
		_invalidate(String(reasons.get(status, status)) + "\n" + String(message.get("message", "")))
		return true
	var values: Variant = message.get("predictions")
	if not values is Dictionary:
		_invalidate("缺少预测量")
		return false
	for name in OUTPUTS:
		if not values.has(name) or not _finite_number(values[name]):
			_invalidate("预测量格式错误")
			return false
	for name in ["source_time_s", "mileage_m", "inference_ms"]:
		if not _finite_number(message.get(name)):
			_invalidate("时间/里程格式错误")
			return false
	last_prediction = message.duplicate(true)
	valid = true
	_status = "分布/物理值提示" if message.get("warning", false) else "在线预测（非实测）"
	_label.text = "DDPM forward_01 · %s\n源时间 %.3f s | 里程 %.3f km\n右轮 %.2f kN   左轮 %.2f kN\n右 c: %.6f / %.6f / %.6f\n左 c: %.6f / %.6f / %.6f\n推理 %.2f ms | 合成延迟 6 s" % [
		_status, float(message.source_time_s), float(message.mileage_m) / 1000.0,
		float(values.N_r) / 1000.0, float(values.N_l) / 1000.0,
		float(values.c_x_r), float(values.c_y_r), float(values.c_z_r),
		float(values.c_x_l), float(values.c_y_l), float(values.c_z_l), float(message.inference_ms)]
	# Scene scripts may subscribe without replacing the existing dynamics UDP stream.
	var scene := get_tree().current_scene
	if scene != null:
		scene.set_meta("ddpm_prediction", last_prediction)
		scene.set_meta("ddpm_prediction_valid", true)
	prediction_received.emit(last_prediction)
	return true

func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _invalidate(reason: String) -> void:
	valid = false
	last_prediction.clear()
	_status = reason
	if _label != null:
		_label.text = "DDPM forward_01 预测\n" + reason + "\n当前无有效预测，不以零值代替"
	var scene := get_tree().current_scene
	if scene != null:
		scene.set_meta("ddpm_prediction_valid", false)
		scene.remove_meta("ddpm_prediction")
	prediction_invalidated.emit(reason)

func _exit_tree() -> void:
	_udp.close()
