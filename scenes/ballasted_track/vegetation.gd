extends Node3D
## Deterministic branching trees with individual folded leaf geometry.
const Batch = preload("res://assets/procedural/detail_batch.gd")
var rng := RandomNumberGenerator.new()
var plant_count := 0

func _material(color: Color, leaves: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	if leaves:
		m.albedo_color = Color("6e7b5c")
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.backlight_enabled = true
		m.backlight = Color(0.012,0.018,0.006)
	return m

func _branch(st: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.top_radius = radius*0.50
	mesh.bottom_radius = radius
	mesh.radial_segments = 7
	st.append_from(mesh,0,Batch.beam(a,b,1.0))

func _leaf(st: SurfaceTool, p: Vector3, size: float, shade: Color) -> void:
	var basis := Basis.from_euler(Vector3(rng.randf_range(-1.1,1.1),rng.randf()*TAU,rng.randf_range(-0.7,0.7)))
	var verts: Array[Vector3] = [p+basis*Vector3(0,0,-size),p+basis*Vector3(-size*0.38,-size*0.10,0),p+basis*Vector3(0,size*0.06,0),p+basis*Vector3(size*0.38,-size*0.10,0),p+basis*Vector3(0,0,size)]
	for tri in [[0,1,2],[1,4,2],[4,3,2],[3,0,2]]:
		var normal := (verts[tri[2]]-verts[tri[0]]).cross(verts[tri[1]]-verts[tri[0]]).normalized()
		st.set_normal(normal)
		st.set_color(shade)
		for index in tri: st.add_vertex(verts[index])

func _plant_mesh(variant: int) -> ArrayMesh:
	var tall := variant<3
	var height := rng.randf_range(5.5,8.0) if tall else rng.randf_range(1.2,2.1)
	var crown := height*0.32 if tall else height*0.65
	var branches := SurfaceTool.new()
	branches.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Vector3(rng.randf_range(-0.3,0.3),0,rng.randf_range(-0.3,0.3))
	var fork := Vector3(0,height*0.37,0)+lean
	_branch(branches,Vector3.ZERO,fork,height*0.025)
	_branch(branches,fork,Vector3(lean.x,height*0.82,lean.z),height*0.015)
	var clusters: Array[Vector3] = []
	for i in range(17 if tall else 10):
		var angle := i*2.399+variant
		var spread := rng.randf_range(0.45,1.0)*crown
		var point := Vector3(cos(angle)*spread,height*rng.randf_range(0.50,0.91),sin(angle)*spread)+lean
		var elbow := fork.lerp(point,0.48)-Vector3(0,height*0.10,0)
		_branch(branches,fork,elbow,height*0.010)
		_branch(branches,elbow,point,height*0.005)
		clusters.append(point)
	var mesh := ArrayMesh.new()
	branches.set_material(_material(Color("494638")))
	branches.commit(mesh)
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	var greens := [Color("334523"),Color("3e512c"),Color("2a3c24"),Color("48562c"),Color("38482b")]
	for center in clusters:
		var cluster_size := crown*rng.randf_range(0.43,0.66)
		for i in range(480 if tall else 180):
			var dir := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
			if dir.length_squared()>1: dir = dir.normalized()*rng.randf_range(0.5,1.0)
			var p := center+dir*Vector3(cluster_size,cluster_size*0.65,cluster_size)
			var shade: Color = greens[(variant+i%2)%greens.size()]
			shade = shade.darkened(rng.randf_range(0.0,0.24))
			_leaf(foliage,p,rng.randf_range(0.10,0.18) if tall else rng.randf_range(0.055,0.105),shade)
	foliage.set_material(_material(Color.WHITE,true))
	foliage.commit(mesh)
	return mesh

func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(9):
		var angle := rng.randf()*TAU
		var h := rng.randf_range(0.12,0.39)
		var base := Vector3(rng.randf_range(-0.13,0.13),0,rng.randf_range(-0.13,0.13))
		var w := Vector3(cos(angle),0,sin(angle))*rng.randf_range(0.008,0.018)
		var tip := base+Vector3(sin(angle)*h*0.35,h,cos(angle)*h*0.35)
		st.set_color(Color("566137").darkened(rng.randf_range(0.05,0.40)))
		st.set_normal(Vector3.UP)
		for p in [base-w,base+w,tip]: st.add_vertex(p)
	st.set_material(_material(Color.WHITE,true))
	return st.commit()

func build(length: int) -> void:
	rng.seed = 2026091807
	var meshes: Array[ArrayMesh] = []
	for i in range(6): meshes.append(_plant_mesh(i))
	var grass := _grass_mesh()
	for chunk in range(0,length,24):
		var buckets: Array = []
		for i in range(6): buckets.append([])
		for i in range(40):
			# Photo: taller mixed hedge on right; open low vegetation on left.
			var right := i%3!=0
			var tall := right and i%4==0
			var variant := rng.randi_range(0,2) if tall else rng.randi_range(3,5)
			var x := rng.randf_range(7.2,17.0) if right else rng.randf_range(-27,-11)
			var z := 18.0-chunk-rng.randf_range(0,24)
			# Keep the LY building apron clear without changing plant counts.
			if x < -6.0 and z > -24.0 and z < -2.0: x -= 17.0
			var scale := rng.randf_range(0.75,1.2) if right else rng.randf_range(0.45,0.85)
			buckets[variant].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(scale,scale*rng.randf_range(0.85,1.12),scale)),Vector3(x,-0.10,z)))
			plant_count += 1
		# Dense shrub understorey near the right maintenance path.
		for i in range(12):
			var p := Vector3(rng.randf_range(6.0,8.8),-0.10,18.0-chunk-i*2.0+rng.randf_range(-0.6,0.6))
			var scale := rng.randf_range(0.9,1.25)
			buckets[rng.randi_range(3,5)].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),p))
			plant_count += 1
		for i in range(3):
			var p := Vector3(rng.randf_range(-65,-38),-0.10,18.0-chunk-rng.randf_range(0,24))
			var scale := rng.randf_range(0.45,0.7)
			buckets[rng.randi_range(0,2)].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),p))
			plant_count += 1
		for i in range(6):
			var poses: Array[Transform3D] = []
			poses.assign(buckets[i])
			Batch.batch(self,"BranchingVegetation_%d_%d"%[chunk,i],meshes[i],poses,460)
		var grasses: Array[Transform3D] = []
		for i in range(1100):
			var x := rng.randf_range(4.45,9.5) if i%2==0 else rng.randf_range(-10.8,-7.0)
			var z := 18.0-chunk-rng.randf_range(0,24)
			# Keep the LY building apron clear without changing plant counts.
			if x < -6.0 and z > -24.0 and z < -2.0: x -= 17.0
			var scale := rng.randf_range(0.5,1.5)
			grasses.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),Vector3(x,-0.10,z)))
		var instance := Batch.batch(self,"WildVergeGrass_%d"%chunk,grass,grasses,125)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
