extends Node3D
## LY railway service building and open inspection shelter, estimated from LY.jpg.
const Batch = preload("res://assets/procedural/detail_batch.gd")
var groups: Dictionary = {}
var materials: Dictionary = {}

func _mat(key: String, color: String, metallic: float = 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.8 if metallic == 0.0 else 0.48
	material.metallic = metallic
	materials[key] = material
	groups[key] = []

func _box(key: String, center: Vector3, size: Vector3) -> void:
	groups[key].append(Transform3D(Basis.IDENTITY.scaled(size), center))

func _beam(key: String, a: Vector3, b: Vector3, width: float) -> void:
	groups[key].append(Batch.beam(a, b, width))

func _ready() -> void:
	_mat("Plaster", "deded3")
	_mat("BlueTrim", "244e8a")
	_mat("Concrete", "929488")
	_mat("Steel", "858c88", 0.55)
	_mat("WindowGlass", "263d40", 0.25)
	_mat("Shutter", "b0b2a8", 0.25)
	_mat("Roof", "9b9e93", 0.2)
	# Local facade faces +Z; the wing is turned toward the railway after batching.
	_box("Concrete", Vector3(0,0.04,0), Vector3(13.2,0.30,7.1))
	_box("Plaster", Vector3(0,2.32,0), Vector3(12,4.3,6))
	_box("BlueTrim", Vector3(0,0.63,0), Vector3(12.06,0.92,6.06))
	_box("Plaster", Vector3(0,0.89,0), Vector3(12.09,0.10,6.09))
	_box("BlueTrim", Vector3(0,4.52,0), Vector3(12.24,0.48,6.24))
	_box("Roof", Vector3(0,4.72,0), Vector3(11.9,0.10,5.9))
	# Shutter recess, jambs, corrugations and concrete threshold.
	_box("WindowGlass", Vector3(-3.85,1.76,3.035), Vector3(2.45,3.2,0.035))
	_box("Shutter", Vector3(-3.85,1.77,3.065), Vector3(2.22,3.12,0.035))
	for i in range(39):
		_box("Steel", Vector3(-3.85,0.25+i*0.08,3.095), Vector3(2.22,0.016,0.023))
	for x in [-5.06,-2.64]:
		_box("Plaster", Vector3(x,1.79,3.10), Vector3(0.16,3.3,0.20))
	_box("Plaster", Vector3(-3.85,3.44,3.10), Vector3(2.58,0.18,0.20))
	_box("Concrete", Vector3(-3.85,0.17,3.53), Vector3(2.7,0.18,0.95))
	for x in [-1.1,1.25,3.6]:
		_box("WindowGlass", Vector3(x,2.14,3.055), Vector3(1.25,2.22,0.045))
		for dx in [-0.69,0.69]:
			_box("Plaster", Vector3(x+dx,2.14,3.10), Vector3(0.12,2.45,0.16))
		for y in [0.95,3.33]:
			_box("Plaster", Vector3(x,y,3.12), Vector3(1.48,0.12,0.22))
		for dx in range(7):
			_box("Steel", Vector3(x-0.57+dx*0.19,2.14,3.21), Vector3(0.025,2.22,0.025))
		for y in [1.35,2.1,2.95]:
			_box("Steel", Vector3(x,y,3.21), Vector3(1.25,0.028,0.035))
	# Small high level louvred vent.
	_box("WindowGlass", Vector3(-1.1,3.87,3.05), Vector3(0.48,0.43,0.06))
	for i in range(6):
		_box("Steel", Vector3(-1.1,3.68+i*0.07,3.10), Vector3(0.48,0.025,0.07))
	# Front corner drain, fixed roof access ladder and guard hoops.
	_box("Plaster", Vector3(-5.60,2.35,3.22), Vector3(0.11,4.35,0.11))
	_box("Plaster", Vector3(-5.60,4.26,3.22), Vector3(0.25,0.22,0.22))
	for x in [-6.25,-6.95]:
		_beam("Steel", Vector3(x,0.25,2.35), Vector3(x,5.65,2.35),0.045)
	for i in range(18):
		_beam("Steel",Vector3(-6.25,0.40+i*0.29,2.35),Vector3(-6.95,0.40+i*0.29,2.35),0.035)
	for y in [3.3,4.0,4.7,5.4]:
		for i in range(12):
			var a := PI*i/12.0
			var b := PI*(i+1)/12.0
			_beam("Steel",Vector3(-6.60+0.46*cos(a),y,2.35+0.65*sin(a)),Vector3(-6.60+0.46*cos(b),y,2.35+0.65*sin(b)),0.025)
	# Low roof safety rail.
	for x in [-5.8,5.8]:
		_beam("Steel",Vector3(x,4.95,-2.8),Vector3(x,4.95,2.8),0.025)
		for z in [-2.8,0.0,2.8]:
			_beam("Steel",Vector3(x,4.72,z),Vector3(x,4.95,z),0.025)
	_beam("Steel",Vector3(-5.8,4.95,-2.8),Vector3(5.8,4.95,-2.8),0.025)
	var wing := Node3D.new()
	wing.name = "ServiceBuilding"
	add_child(wing)
	wing.position = Vector3(-12.2,0,-13)
	wing.rotation.y = PI/2
	_flush(wing)
	var sign := Label3D.new()
	sign.name = "LYSign"
	sign.text = "LY"
	sign.font_size = 128
	sign.pixel_size = 0.007
	sign.modulate = Color("b42c37")
	sign.outline_size = 0
	sign.no_depth_test = false
	sign.position = Vector3(2.43,2.35,3.13)
	wing.add_child(sign)
	# Open-through shelter over the right-hand track. Roof above catenary.
	for z in [-27.0,-31.0,-35.0]:
		for x in [-2.05,2.05]:
			_box("Concrete",Vector3(x,0.46,z),Vector3(0.68,1.0,0.78))
			_box("BlueTrim",Vector3(x,4.45,z),Vector3(0.27,8.0,0.32))
			_box("Plaster",Vector3(x-signf(x)*0.19,4.45,z),Vector3(0.16,7.5,0.25))
			_beam("Steel",Vector3(x,6.1,z),Vector3(x*0.57,8.18,z),0.13)
			_beam("Plaster",Vector3(x,8.25,z),Vector3(0,8.78,z),0.18)
	for x in [-2.05,2.05]:
		_beam("BlueTrim",Vector3(x,8.40,-26.7),Vector3(x,8.40,-35.3),0.22)
		for y in [1.4,4.4,7.5]:
			_beam("Steel",Vector3(x,y,-27),Vector3(x,y,-35),0.09)
		for z in [-27.0,-31.0]:
			_beam("Steel",Vector3(x,1.4,z),Vector3(x,7.5,z-4),0.085)
			_beam("Steel",Vector3(x,7.5,z),Vector3(x,1.4,z-4),0.085)
		# Upper side cladding; open lower sides reveal the bracing.
		_box("Roof",Vector3(x,6.6,-31),Vector3(0.055,2.9,7.9))
		var roof_pose := Transform3D(Basis(Vector3.FORWARD,signf(x)*atan2(0.53,2.05)),Vector3(x*0.5,8.52,-31))
		roof_pose.basis = roof_pose.basis.scaled(Vector3(2.22,0.10,8.65))
		groups["Roof"].append(roof_pose)
		for z in [-27.0,-29.0,-31.0,-33.0,-35.0]:
			_beam("Steel",Vector3(x,8.23,z),Vector3(0,8.76,z),0.075)
	_beam("BlueTrim",Vector3(0,8.8,-26.65),Vector3(0,8.8,-35.35),0.13)
	_box("Concrete",Vector3(-11.9,-0.015,-13),Vector3(9.4,0.18,17))
	# Narrow trackside service walk, outside the rail envelope.
	_box("Concrete",Vector3(3.55,0.01,-30),Vector3(1.3,0.20,13))
	_flush(self)

func _flush(parent: Node3D) -> void:
	for key: String in groups:
		var poses: Array[Transform3D] = []
		poses.assign(groups[key])
		if not poses.is_empty():
			var mesh := BoxMesh.new()
			mesh.size = Vector3.ONE
			mesh.material = materials[key]
			Batch.batch(parent, key, mesh, poses, 0)
		groups[key] = []