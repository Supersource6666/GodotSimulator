extends Node
## Godot 4 receiver for railway31dof.v1 UDP packets.
## The solver transmits every integration step. Rendering consumes only the newest queued packet.

signal state_received(state: Dictionary)
signal stream_error(message: String)

@export var listen_address := "127.0.0.1"
@export_range(1, 65535, 1) var listen_port := 49000
@export var drive_all_cars := true
@export_range(0.0, 100.0, 0.1) var displacement_scale := 1.0
@export_range(0.0, 100.0, 0.1) var rotation_scale := 1.0
@export var lateral_sign := 1.0
@export var pitch_sign := 1.0
@export var yaw_sign := -1.0
@export var roll_sign := -1.0
@export_range(1.0, 1000000.0, 1.0) var force_reference_N := 77033.025

var _udp := PacketPeerUDP.new()
var _bindings: Array[Dictionary] = []
var _last_sequence := -1
var _last_simulation_time := 0.0
var packet_count := 0
var dropped_or_skipped_steps := 0
var last_state: Dictionary = {}


func _ready() -> void:
	var error := _udp.bind(listen_port, listen_address)
	if error != OK:
		var message := "31DOF UDP bind failed at %s:%d (error %d)" % [listen_address, listen_port, error]
		push_error(message)
		stream_error.emit(message)
		set_process(false)
	else:
		print("31DOF UDP receiver listening at %s:%d" % [listen_address, listen_port])


func attach_train(train_root: Node3D) -> void:
	_bindings.clear()
	if train_root == null:
		return
	for car_wrapper in train_root.get_children():
		if not (car_wrapper is Node3D):
			continue
		var vehicle := car_wrapper as Node3D
		if vehicle.get_node_or_null("ModelMount") == null:
			if car_wrapper.get_child_count() == 0:
				continue
			vehicle = car_wrapper.get_child(0) as Node3D
		if vehicle == null:
			continue
		var body := vehicle.get_node_or_null("ModelMount") as Node3D
		var front_bogie := vehicle.get_node_or_null("RunningGear/FrontBogieVisual") as Node3D
		var rear_bogie := vehicle.get_node_or_null("RunningGear/RearBogieVisual") as Node3D
		var wheelsets: Array[Node3D] = []
		for path in [
			"RunningGear/FrontBogieVisual/FrontWheelset",
			"RunningGear/FrontBogieVisual/RearWheelset",
			"RunningGear/RearBogieVisual/FrontWheelset",
			"RunningGear/RearBogieVisual/RearWheelset",
		]:
			var wheelset := vehicle.get_node_or_null(path) as Node3D
			if wheelset != null:
				wheelsets.append(wheelset)
		if body == null or front_bogie == null or rear_bogie == null or wheelsets.size() != 4:
			push_warning("31DOF receiver skipped incomplete vehicle node: " + String(vehicle.get_path()))
			continue
		_bindings.append({
			"vehicle": vehicle,
			"body": body,
			"body_base": body.transform,
			"bogies": [front_bogie, rear_bogie],
			"bogie_bases": [front_bogie.transform, rear_bogie.transform],
			"wheelsets": wheelsets,
			"wheelset_bases": [wheelsets[0].transform, wheelsets[1].transform,
				wheelsets[2].transform, wheelsets[3].transform],
		})
		if not drive_all_cars:
			break
	print("31DOF receiver attached to %d visual car(s)" % _bindings.size())


func _process(_delta: float) -> void:
	var newest := PackedByteArray()
	var queued := _udp.get_available_packet_count()
	while _udp.get_available_packet_count() > 0:
		newest = _udp.get_packet()
	if newest.is_empty():
		return
	var parsed = JSON.parse_string(newest.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var state := parsed as Dictionary
	if state.get("schema", "") != "railway31dof.v1" or state.get("type", "") != "state":
		return
	var sequence := int(state.get("seq", -1))
	if sequence <= _last_sequence:
		return
	if _last_sequence >= 0:
		dropped_or_skipped_steps += maxi(0, sequence - _last_sequence - 1)
	_last_sequence = sequence
	packet_count += queued
	last_state = state
	_apply_state(state)
	state_received.emit(state)


func _apply_state(state: Dictionary) -> void:
	var car_state := state.get("car", []) as Array
	var bogie_states := state.get("bogies", []) as Array
	var wheelset_states := state.get("wheelsets", []) as Array
	var normal_forces := state.get("normal_N", []) as Array
	if car_state.size() != 5 or bogie_states.size() != 2 or wheelset_states.size() != 4:
		return
	var simulation_time := float(state.get("t", 0.0))
	var simulation_delta := maxf(0.0, simulation_time - _last_simulation_time)
	_last_simulation_time = simulation_time
	for binding in _bindings:
		_apply_pose(binding.body as Node3D, binding.body_base as Transform3D, car_state, [])
		var bogies := binding.bogies as Array
		var bogie_bases := binding.bogie_bases as Array
		for bogie_index in range(2):
			_apply_pose(bogies[bogie_index] as Node3D, bogie_bases[bogie_index] as Transform3D,
				bogie_states[bogie_index] as Array, [])
		var wheelsets := binding.wheelsets as Array
		var wheelset_bases := binding.wheelset_bases as Array
		for wheelset_index in range(4):
			var bogie_index := 0 if wheelset_index < 2 else 1
			_apply_pose(wheelsets[wheelset_index] as Node3D,
				wheelset_bases[wheelset_index] as Transform3D,
				wheelset_states[wheelset_index] as Array, bogie_states[bogie_index] as Array)
		var vehicle := binding.vehicle as Node3D
		if vehicle.has_method("_advance_wheel_rotation") and simulation_delta > 0.0:
			vehicle.call("_advance_wheel_rotation", float(state.get("speed_m_s", 0.0)), simulation_delta)
		if vehicle.has_method("update_force_arrow_scales") and normal_forces.size() == 4:
			for axle_index in range(4):
				var forces := normal_forces[axle_index] as Array
				if forces.size() == 2:
					vehicle.call("update_force_arrow_scales", axle_index + 1, [
						float(forces[0]) / force_reference_N, 0.0, 0.0,
						float(forces[1]) / force_reference_N, 0.0, 0.0,
					])


func _apply_pose(node: Node3D, base: Transform3D, state: Array, reference: Array) -> void:
	if node == null or state.size() != 5:
		return
	var ref_z := float(reference[0]) if reference.size() == 5 else 0.0
	var ref_pitch := float(reference[1]) if reference.size() == 5 else 0.0
	var ref_y := float(reference[2]) if reference.size() == 5 else 0.0
	var ref_roll := float(reference[3]) if reference.size() == 5 else 0.0
	var ref_yaw := float(reference[4]) if reference.size() == 5 else 0.0
	var vertical := (float(state[0]) - ref_z) * displacement_scale
	var lateral := (float(state[2]) - ref_y) * displacement_scale * lateral_sign
	var pitch := (float(state[1]) - ref_pitch) * rotation_scale * pitch_sign
	var yaw := (float(state[4]) - ref_yaw) * rotation_scale * yaw_sign
	var roll := (float(state[3]) - ref_roll) * rotation_scale * roll_sign
	var delta_basis := Basis.from_euler(Vector3(pitch, yaw, roll))
	node.transform = Transform3D(base.basis * delta_basis,
		base.origin + Vector3(lateral, vertical, 0.0))
