extends SceneTree
func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var receiver = load("res://shared/ddpm_prediction_receiver.gd").new()
	receiver.listen_port = 49121
	root.add_child(receiver)
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", 49121)
	var values := {"N_r": 61000.0, "N_l": 60000.0, "c_x_r": 0.001, "c_y_r": 0.002, "c_z_r": 0.003, "c_x_l": 0.004, "c_y_l": 0.005, "c_z_l": 0.006}
	var message := {"schema": "rail.ddpm.prediction.v1", "model_id": "forward_01", "service_id": "TEST_ONLY", "session": "fixture", "seq": 1, "status": "prediction", "valid": true, "predictions": values, "source_time_s": 20.0, "mileage_m": 641100.0, "inference_ms": 3.0}
	sender.put_packet(JSON.stringify(message).to_utf8_buffer())
	await create_timer(0.1).timeout
	assert(receiver.valid and receiver.last_prediction.predictions.N_r == 61000.0)
	assert(not receiver.accept_message(message), "Duplicate sequence accepted")
	message.seq = 2
	message.valid = false
	message.status = "model_unavailable"
	sender.put_packet(JSON.stringify(message).to_utf8_buffer())
	await create_timer(0.1).timeout
	assert(not receiver.valid and receiver.last_prediction.is_empty())
	sender.close()
	print("DDPM_GODOT_UDP_TEST_PASSED: fixture packets, not model predictions")
	quit(0)
