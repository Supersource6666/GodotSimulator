extends Node3D
## Lightweight camera-local cab shell. The source train GLB is exterior-only, so
## this supplies an unobstructed windscreen, dashboard and frame for driver view.

func _ready() -> void:
	_add_box("Dashboard", Vector3(2.7, 0.36, 1.15), Vector3(0.0, -0.72, -1.05), Color("17222b"))
	_add_box("Console", Vector3(1.15, 0.22, 0.62), Vector3(0.0, -0.48, -1.32), Color("293944"))
	_add_box("LeftPillar", Vector3(0.13, 1.65, 0.16), Vector3(-1.16, 0.02, -1.12), Color("111a20"))
	_add_box("RightPillar", Vector3(0.13, 1.65, 0.16), Vector3(1.16, 0.02, -1.12), Color("111a20"))
	_add_box("TopFrame", Vector3(2.45, 0.16, 0.18), Vector3(0.0, 0.79, -1.12), Color("111a20"))
	_add_box("LeftDeskWing", Vector3(0.58, 0.2, 0.55), Vector3(-0.95, -0.54, -1.25), Color("202d36"))
	_add_box("RightDeskWing", Vector3(0.58, 0.2, 0.55), Vector3(0.95, -0.54, -1.25), Color("202d36"))

func _add_box(node_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.metallic_specular = 0.18
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)