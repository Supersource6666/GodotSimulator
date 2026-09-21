extends "res://scenes/ballastless_track/ballastless_track.gd"
## Metres. Deterministic angular aggregate in spatial batches.
const Mineral = preload("res://scenes/ballasted_track/mineral.gdshader")
const Components = preload("res://scenes/ballasted_track/track_components.gd")
const LENGTH := 600
const START := 18.0
const CENTERS := [-4.2,0.0]
var rng := RandomNumberGenerator.new()
var stone_count := 0
var sleeper_count := 0

func _ready() -> void:
	rng.seed = 18092026
	_build_environment()
	var env: Environment = get_node("ClearSkyEnvironment").environment
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://scenes/ballasted_track/overcast_sky.gdshader")
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b5bec1")
	env.ambient_light_energy = 0.50
	env.ssao_enabled = false
	env.fog_density = 0.00055
	env.fog_light_color = Color("c4cecc")
	env.fog_light_energy = 0.32
	env.fog_sky_affect = 0.05
	var sun: DirectionalLight3D = get_node("Sunlight")
	sun.light_color = Color("f5f4ee")
	sun.light_energy = 0.82
	sun.light_angular_distance = 2.5
	sun.directional_shadow_max_distance = 110.0
	_ground()
	_tracks()
	_ballast()
	_catenary()
	_verges()
	var ly := preload("res://scenes/ballasted_track/ly_building.gd").new()
	ly.name = "LYFacility"
	add_child(ly)
	_build_camera()
	_build_camera_reset()
	_build_interface()
	var label: Label = _info_panel.get_child(0)
	label.text = "有砟轨道 / BALLASTED TRACK\n右键拖动 · WASD 移动 · Q/E 升降 · Shift 加速\nR 参考视角 · 2 道砟近景 · 3 全景 · 4 扣件特写 · 5 LY建筑 · F1 说明 · Esc 返回"
	_info_panel.hide()
	if "--reference-capture" in OS.get_cmdline_user_args(): _capture_reference.call_deferred()
	if "--demo-smoke-test" in OS.get_cmdline_user_args(): _finish_smoke_test.call_deferred()

func _mineral(color: String, scale: float = 180.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Mineral
	m.set_shader_parameter("stone_color",Color(color))
	m.set_shader_parameter("grain_scale",scale)
	return m

func _height(x: float) -> float:
	return 0.34-maxf(minf(absf(x),absf(x+4.2))-1.48,0)*0.60

func _ground_material(is_path: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://scenes/ballasted_track/verge_ground.gdshader")
	m.set_shader_parameter("path",is_path)
	return m

func _ground() -> void:
	_add_box(self,"Earth",Vector3(-2,-0.23,-270),Vector3(1000,0.25,1100),_ground_material())
	_add_box(self,"MaintenancePath",Vector3(3.6,-0.08,-282),Vector3(1.5,0.06,LENGTH),_ground_material(true))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(96):
		var a := -6.9+i*0.1
		var b := a+0.1
		for p in [Vector3(a,_height(a)-0.04,START),Vector3(a,_height(a)-0.04,START-LENGTH),Vector3(b,_height(b)-0.04,START),Vector3(b,_height(b)-0.04,START),Vector3(a,_height(a)-0.04,START-LENGTH),Vector3(b,_height(b)-0.04,START-LENGTH)]: st.add_vertex(p)
	st.generate_normals()
	st.set_material(_mineral("414442",110))
	var bed := MeshInstance3D.new()
	bed.name = "SlopedBallastFormation"
	bed.mesh = st.commit()
	add_child(bed)

func _sleeper() -> ArrayMesh:
	return Components.sleeper()

func _tracks() -> void:
	var rust := _mineral("583829",65)
	var polished := _material(Color("a0a8aa"),0.26,0.8)
	var sleeper := _sleeper()
	var clip := Components.fastening()
	for center in CENTERS:
		for side in [-1.0,1.0]:
			var x: float = center+side*0.7535
			_add_box(self,"RailFoot",Vector3(x,0.515,START-LENGTH*0.5),Vector3(0.15,0.026,LENGTH),rust)
			_add_box(self,"RailWeb",Vector3(x,0.58,START-LENGTH*0.5),Vector3(0.018,0.12,LENGTH),rust)
			_add_box(self,"RailHead",Vector3(x,0.665,START-LENGTH*0.5),Vector3(0.073,0.046,LENGTH),rust)
			_add_box(self,"PolishedRunningSurface",Vector3(x,0.69,START-LENGTH*0.5),Vector3(0.069,0.005,LENGTH),polished)
		for chunk in range(0,LENGTH,24):
			var sleepers: Array[Transform3D] = []
			var clips: Array[Transform3D] = []
			for i in range(40):
				var z := START-chunk-i*0.6
				sleepers.append(Transform3D(Basis.IDENTITY,Vector3(center,0,z)))
				sleeper_count += 1
				for side in [-1.0,1.0]:
					var p := Vector3(center+side*0.7535,0,z)
					clips.append(Transform3D(Basis.IDENTITY,p))
			DetailBatch.batch(self,"ConcreteSleepers",sleeper,sleepers,0)
			var assembly := DetailBatch.batch(self,"BoltedSpringFastenings",clip,clips,0)
			assembly.set_meta("fastening_assembly",true)

func _stone(index: int) -> ArrayMesh:
	var points := PackedVector3Array()
	for ring in range(3):
		for i in range(7):
			var angle := TAU*i/7.0+ring*0.24
			var radius := rng.randf_range(0.65,1.0)*(0.57 if ring!=1 else 1.0)
			points.append(Vector3(cos(angle)*radius,(ring-1)*0.65+rng.randf_range(-0.19,0.19),sin(angle)*radius))
	var vertices := points
	var indices := PackedInt32Array()
	for ring in range(2):
		for j in range(7):
			var a := ring*7+j
			var b := ring*7+(j+1)%7
			indices.append_array([a,b,a+7,b,b+7,a+7])
	for j in range(1,6):
		indices.append_array([0,j+1,j,14,14+j,15+j])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,indices.size(),3):
		var shade := rng.randf_range(0.83,1.13)
		st.set_color(Color(shade,shade,shade))
		st.set_smooth_group(-1)
		for j in range(3): st.add_vertex(vertices[indices[i+j]])
	st.generate_normals()
	st.set_material(_mineral(["555b59","676b66","424b4e","77786c","4b5051","616563","8a897c","3c4446"][index]))
	return st.commit()

func _ballast() -> void:
	var meshes: Array[ArrayMesh] = []
	for i in range(8): meshes.append(_stone(i))
	for chunk in range(0,LENGTH,12):
		var buckets: Array = []
		for i in range(8): buckets.append([])
		var step := 0.058 if chunk<84 else 0.105
		for zi in range(int(12.0/step)):
			var z := START-chunk-zi*step
			for xi in range(int(9.55/step)):
				var x := -6.87+xi*step+rng.randf_range(-step*0.43,step*0.43)
				var zz := z+rng.randf_range(-step*0.43,step*0.43)
				var d := minf(absf(x),absf(x+4.2))
				var tie_dist := absf(fposmod(START-zz+0.3,0.6)-0.3)
				if d<1.31 and tie_dist<0.146: continue
				var radius := rng.randf_range(0.028,0.048) if chunk<84 else rng.randf_range(0.047,0.078)
				var p := Vector3(x,_height(x)+rng.randf_range(-0.018,0.016),zz)
				var basis := Basis.from_euler(Vector3(rng.randf_range(-0.7,0.7),rng.randf()*TAU,rng.randf_range(-0.7,0.7)))
				basis = basis.scaled(Vector3(radius*rng.randf_range(0.8,1.35),radius,radius*rng.randf_range(0.8,1.4)))
				buckets[rng.randi_range(0,7)].append(Transform3D(basis,p))
				stone_count += 1
		for i in range(8):
			var poses: Array[Transform3D] = []
			poses.assign(buckets[i])
			DetailBatch.batch(self,"AngularBallast_%d_%d"%[chunk,i],meshes[i],poses,190)

func _catenary() -> void:
	var steel := BoxMesh.new()
	steel.size = Vector3.ONE
	steel.material = _material(Color("4d6064"),0.65,0.45)
	var poses: Array[Transform3D] = []
	for d in range(12,LENGTH,48):
		var z := START-d
		for x in [-6.6,2.8]:
			_add_box(self,"MastFoundation",Vector3(x,0.12,z),Vector3(0.65,0.5,0.65),_mineral("9c9d90"))
			for side in [-1,1]: poses.append(DetailBatch.beam(Vector3(x+side*0.17,0.2,z),Vector3(x+side*0.17,8.4,z),0.065))
			for j in range(11):
				poses.append(DetailBatch.beam(Vector3(x-0.17,0.3+j*0.72,z),Vector3(x+0.17,1.02+j*0.72,z),0.035))
				poses.append(DetailBatch.beam(Vector3(x+0.17,0.3+j*0.72,z),Vector3(x-0.17,1.02+j*0.72,z),0.035))
			var tx := 0.0 if x>0 else -4.2
			poses.append(DetailBatch.beam(Vector3(x,7.6,z),Vector3(tx,6.35,z),0.055))
			poses.append(DetailBatch.beam(Vector3(x,6.45,z),Vector3(tx,6.35,z),0.045))
	for tx in CENTERS:
		for d in range(0,LENGTH,6):
			var z := START-d
			var y := 6.7+0.65*pow((fposmod(d-12,48)-24)/24,2)
			var yy := 6.7+0.65*pow((fposmod(d+6-12,48)-24)/24,2)
			poses.append(DetailBatch.beam(Vector3(tx,5.95,z),Vector3(tx,5.95,z-6),0.012))
			poses.append(DetailBatch.beam(Vector3(tx,y,z),Vector3(tx,yy,z-6),0.01))
			poses.append(DetailBatch.beam(Vector3(tx,5.95,z),Vector3(tx,y,z),0.008))
	DetailBatch.batch(self,"LatticeMastsAndCatenary",steel,poses,0)

func _verges() -> void:
	var vegetation := preload("res://scenes/ballasted_track/vegetation.gd").new()
	vegetation.name = "NaturalRailwayVerges"
	add_child(vegetation)
	vegetation.build(LENGTH)

func _build_camera_reset() -> void:
	# Match travel/track_detail: centered, 0.84 m above rail, 53 degree FOV.
	_camera.position = Vector3(0.0,1.53,13.7)
	_camera.look_at(Vector3(0.0,0.63,-326.3),Vector3.UP)
	_camera.near = 0.035
	_camera.fov = 53

func _process(delta: float) -> void:
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	_camera.position += _camera.basis*direction*delta*(14.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 2.5)
	_camera.position.y = maxf(_camera.position.y,0.75)

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_camera.rotation.y -= event.relative.x*0.003
		_camera.rotation.x = clampf(_camera.rotation.x-event.relative.y*0.003,-1.4,1.4)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_2:
				_camera.fov = 69
				_camera.position = Vector3(1.8,0.87,12)
				_camera.rotation_degrees = Vector3(-30,35,0)
			KEY_5:
				_ly_camera()
			KEY_4:
				_hardware_camera()
			KEY_3:
				_camera.fov = 69
				_camera.position = Vector3(9,6,20)
				_camera.look_at(Vector3(-2,0,-24))

func _ly_camera() -> void:
	_camera.position = Vector3(2.0,3.8,1.0)
	_camera.fov = 62
	_camera.look_at(Vector3(-6,3,-18))

func _hardware_camera() -> void:
	_camera.position = Vector3(1.2,0.97,12.43)
	_camera.fov = 48
	_camera.look_at(Vector3(0.7535,0.54,12))

func _finish_smoke_test() -> void:
	await get_tree().process_frame
	var ok := stone_count>300000 and sleeper_count==2000 and get_node_or_null("SlopedBallastFormation")!=null
	ok = ok and get_node_or_null("LYFacility/ServiceBuilding/LYSign") != null
	var fastening_count := 0
	for child in get_children():
		if child is MultiMeshInstance3D: ok = ok and child.multimesh.mesh != null
		if child is MultiMeshInstance3D and child.has_meta("fastening_assembly"):
			fastening_count += child.multimesh.instance_count
			ok = ok and child.multimesh.mesh.get_surface_count()==4
			ok = ok and child.visibility_range_end==0.0 and child.multimesh.instance_count==80
	ok = ok and fastening_count==4000
	ok = ok and get_node("NaturalRailwayVerges").plant_count==1375
	print("BALLASTED_TRACK_SMOKE ","PASS" if ok else "FAIL"," stones=",stone_count," sleepers=",sleeper_count," fastening_assemblies=",fastening_count)
	get_tree().quit(0 if ok else 1)

func _capture_reference() -> void:
	if "--detail-capture" in OS.get_cmdline_user_args():
		_camera.position = Vector3(1.8,0.87,12)
		_camera.rotation_degrees = Vector3(-30,35,0)
	if "--hardware-capture" in OS.get_cmdline_user_args(): _hardware_camera()
	if "--ly-capture" in OS.get_cmdline_user_args(): _ly_camera()
	for i in range(12): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := "detail.png" if "--detail-capture" in OS.get_cmdline_user_args() else "preview.png"
	if "--hardware-capture" in OS.get_cmdline_user_args(): file = "fastening_detail.png"
	if "--ly-capture" in OS.get_cmdline_user_args(): file = "ly_preview.png"
	var error := get_viewport().get_texture().get_image().save_png("res://scenes/ballasted_track/"+file)
	print("BALLASTED_CAPTURE ",error_string(error))
	get_tree().quit(0 if error==OK else 1)
