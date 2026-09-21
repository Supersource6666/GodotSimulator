extends Node3D
## Minimal animation adapter for the ballasted-track rolling-stock scene.

const WHEELSET_PATHS := [
	"RunningGear/FrontBogieVisual/FrontWheelset/WheelsetModel",
	"RunningGear/FrontBogieVisual/RearWheelset/WheelsetModel",
	"RunningGear/RearBogieVisual/FrontWheelset/WheelsetModel",
	"RunningGear/RearBogieVisual/RearWheelset/WheelsetModel",
]

@export var wheel_radius_m := 0.4575
@export var maximum_visual_spin_deg_per_frame := 16.0
var _wheel_models: Array[Node3D] = []
var _wheel_base_bases: Array[Basis] = []
var _wheel_rotation_rad := 0.0
var _wheel_speed_mps := 0.0


func _ready() -> void:
	for path in WHEELSET_PATHS:
		var model := get_node_or_null(path) as Node3D
		if model != null:
			_wheel_models.append(model)
			_wheel_base_bases.append(model.transform.basis)


func set_wheel_speed(speed_mps: float) -> void:
	_wheel_speed_mps = speed_mps


func _process(delta: float) -> void:
	_advance_wheel_rotation(_wheel_speed_mps, delta)


func _advance_wheel_rotation(speed_mps: float, simulation_delta: float) -> void:
	if simulation_delta <= 0.0 or _wheel_models.is_empty():
		return
	var step := speed_mps * simulation_delta / maxf(wheel_radius_m, 0.001)
	var limit := deg_to_rad(maximum_visual_spin_deg_per_frame)
	step = clampf(step, -limit, limit)
	_wheel_rotation_rad = wrapf(_wheel_rotation_rad - step, -TAU, TAU)
	var spin := Basis(Vector3(0.0, 0.0, 1.0), _wheel_rotation_rad)
	for index in range(_wheel_models.size()):
		var transform := _wheel_models[index].transform
		transform.basis = _wheel_base_bases[index] * spin
		_wheel_models[index].transform = transform
