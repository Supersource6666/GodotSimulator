extends Node3D
## Visual single-arm pantograph, meters; no electrical/contact-force simulation.
const Batch = preload("res://assets/procedural/detail_batch.gd")
var raised := true
var raised_height := 1.8
var current_height := 1.8
var target_height := 1.8
var arm_nodes: Array[MeshInstance3D] = []
var head: Node3D
var carbon_top := 0.0
var steel: StandardMaterial3D

func _mat(color: String, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.metallic = metal
	m.roughness = 0.55 if metal>0 else 0.87
	return m

func _box(parent: Node3D, label: String, p: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = p
	parent.add_child(node)
	return node

func configure(height: float) -> void:
	raised_height = height
	current_height = height
	target_height = height
	steel = _mat("737b80",0.75)
	var base_mat := _mat("454b4c",0.5)
	var ceramic := _mat("654532")
	for x in [-0.42,0.42]:
		for z in [-0.48,0.48]:
			var body := CylinderMesh.new()
			body.top_radius = 0.065
			body.bottom_radius = 0.072
			body.height = 0.18
			body.radial_segments = 14
			body.material = ceramic
			var node := MeshInstance3D.new()
			node.mesh = body
			node.position = Vector3(x,0.09,z)
			add_child(node)
			for j in range(4):
				var disc := CylinderMesh.new()
				disc.top_radius = 0.093
				disc.bottom_radius = 0.088
				disc.height = 0.017
				disc.radial_segments = 14
				disc.material = ceramic
				var ring := MeshInstance3D.new()
				ring.mesh = disc
				ring.position = Vector3(x,0.035+j*0.039,z)
				add_child(ring)
		_box(self,"BaseSide",Vector3(x,0.205,0),Vector3(0.07,0.06,1.13),base_mat)
	for z in [-0.48,0.0,0.48]:
		_box(self,"BaseCrossMember",Vector3(0,0.205,z),Vector3(0.91,0.06,0.07),base_mat)
	for i in range(7):
		arm_nodes.append(_box(self,"ArticulatedArm_%d"%i,Vector3.ZERO,Vector3.ONE,steel if i<5 else base_mat))
	head = Node3D.new()
	head.name = "CollectorHead"
	add_child(head)
	_box(head,"HeadCarrier",Vector3(0,-0.085,0),Vector3(1.42,0.055,0.25),steel)
	for z in [-0.09,0.09]:
		_box(head,"CarbonContactStrip",Vector3(0,-0.0125,z),Vector3(1.45,0.025,0.058),_mat("24282a"))
		for side in [-1.0,1.0]:
			var horn := _box(head,"DownturnedHorn",Vector3.ZERO,Vector3.ONE,steel)
			horn.transform = Batch.beam(Vector3(side*0.72,-0.027,z),Vector3(side*0.97,-0.145,z),0.025)
	_update_geometry()

func set_raised(value: bool, instant: bool = false) -> void:
	raised = value
	target_height = raised_height if raised else 0.40
	if instant:
		current_height = target_height
		_update_geometry()

func _process(delta: float) -> void:
	if not is_equal_approx(current_height,target_height):
		current_height = move_toward(current_height,target_height,delta*0.9)
		_update_geometry()

func _update_geometry() -> void:
	var base := Vector3(0,0.25,0)
	var top := Vector3(0,current_height-0.085,0)
	var delta := top-base
	var distance := delta.length()
	var lower_length := 1.45
	var upper_length := 1.45
	# Analytic two-link linkage: pivots retain fixed arm lengths during raising.
	var direction := delta.normalized()
	var along := (lower_length*lower_length-upper_length*upper_length+distance*distance)/(2.0*distance)
	var sideways := sqrt(maxf(0.0,lower_length*lower_length-along*along))
	var knee := base+direction*along+Vector3(0,-direction.z,direction.y)*sideways
	arm_nodes[0].transform = Batch.beam(base+Vector3(-0.24,0,0),knee+Vector3(-0.12,0,0),0.065,0.09)
	arm_nodes[1].transform = Batch.beam(base+Vector3(0.24,0,0),knee+Vector3(0.12,0,0),0.065,0.09)
	arm_nodes[2].transform = Batch.beam(knee+Vector3(-0.12,0,0),top+Vector3(-0.32,0,0),0.044,0.065)
	arm_nodes[3].transform = Batch.beam(knee+Vector3(0.12,0,0),top+Vector3(0.32,0,0),0.044,0.065)
	arm_nodes[4].transform = Batch.beam(knee+Vector3(-0.19,0,0),knee+Vector3(0.19,0,0),0.085)
	arm_nodes[5].transform = Batch.beam(base+Vector3(0,0,-0.33),knee+Vector3(0,-0.075,0.10),0.022)
	arm_nodes[6].transform = Batch.beam(knee+Vector3(0,-0.075,0.10),top+Vector3(0,-0.055,0.13),0.018)
	head.position.y = current_height
	carbon_top = current_height
