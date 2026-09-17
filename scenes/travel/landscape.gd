extends RefCounted
## Deterministic local vegetation with geometric leaves, no texture downloads.
const Batch := preload("res://assets/procedural/detail_batch.gd")

static func ground_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying vec3 wp;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898,78.233,37.719))) * 43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
 mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float patch=noise(wp*0.43)*0.65+noise(wp*1.6)*0.35;
 float grain=noise(wp*95.0);
 float streak=noise(vec3(wp.x*7.0,wp.y*0.7,wp.z*2.0));
 vec3 earth=mix(vec3(0.16,0.125,0.082),vec3(0.30,0.265,0.17),grain);
 vec3 grass=mix(vec3(0.075,0.12,0.045),vec3(0.22,0.28,0.105),noise(wp*16.0));
 ALBEDO=mix(earth,grass,smoothstep(0.38,0.58,patch))*mix(0.75,1.12,streak);
 ROUGHNESS=0.96;
 NORMAL_MAP=vec3(0.5+(grain-0.5)*0.15,0.5+(noise(wp*70.0)-0.5)*0.15,1.0);
 NORMAL_MAP_DEPTH=0.5;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

static func slope(parent: Node3D, side: float, start: float, length_m: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = 428
	noise.frequency = 1.2
	for z in range(int(length_m)):
		for u in range(24):
			var points: Array[Vector3] = []
			for offset in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
				var uphill: float = (u + offset.x) * 0.5
				var along: float = start - z - offset.y
				var height := noise.get_noise_2d(uphill, along) * 0.055
				points.append(Vector3(side * (7.1 + uphill * 0.8), uphill * 0.6 + height, along))
			for index in ([0,2,1,1,2,3] if side > 0 else [0,1,2,1,3,2]):
				st.add_vertex(points[index])
	st.generate_normals()
	st.set_material(material)
	var instance := MeshInstance3D.new()
	instance.name = "UnevenSoilSlope"
	instance.mesh = st.commit()
	parent.add_child(instance)

static func _leaf(st: SurfaceTool, center: Vector3, size: float, rng: RandomNumberGenerator, color: Color) -> void:
	var basis := Basis.from_euler(Vector3(rng.randf_range(-1.2,1.2), rng.randf_range(0,TAU), rng.randf_range(-0.8,0.8)))
	var a := center + basis * Vector3(0,0,-size)
	var b := center + basis * Vector3(size*0.43,0,0)
	var c := center + basis * Vector3(0,0,size)
	var d := center + basis * Vector3(-size*0.43,0,0)
	var ridge := center + basis * Vector3(0,size*0.12,0)
	st.set_color(color)
	for p in [a,b,ridge,b,c,ridge,c,d,ridge,d,a,ridge]:
		st.add_vertex(p)

static func _branch(st: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.35
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 7
	mesh.rings = 1
	var pose := Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
	st.append_from(mesh,0,pose)

static func _tree(seed_value: int) -> Array[Mesh]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(rng.randf_range(-0.4,0.4),6.5,rng.randf_range(-0.4,0.4))
	_branch(wood,Vector3.ZERO,top,0.17)
	for branch in range(19):
		var phase := branch * 2.399
		var height := 2.2 + branch * 0.21
		var extent := rng.randf_range(1.4,2.7) * (1.0 - branch * 0.022)
		var a := top * (height/6.5)
		var b := a + Vector3(cos(phase)*extent,rng.randf_range(0.5,1.5),sin(phase)*extent)
		_branch(wood,a,b,0.047)
		for twig in range(4):
			var tip := b + Vector3(rng.randf_range(-0.8,0.8),rng.randf_range(0.0,0.9),rng.randf_range(-0.8,0.8))
			_branch(wood,a.lerp(b,0.7),tip,0.014)
			for leaf in range(48):
				var p := tip + Vector3(rng.randfn(0,0.42),rng.randfn(0,0.32),rng.randfn(0,0.42))
				var color := Color("243d17").lerp(Color("64753a"),rng.randf())
				_leaf(leaves,p,rng.randf_range(0.13,0.26),rng,color)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("51473a")
	bark.roughness = 1
	wood.set_material(bark)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.roughness = 0.88
	leaf_mat.backlight_enabled = true
	leaf_mat.backlight = Color(0.16,0.2,0.07)
	leaves.generate_normals()
	leaves.set_material(leaf_mat)
	return [wood.commit(),leaves.commit()]

static func build(parent: Node3D, start: float, length_m: float) -> void:
	var root := Node3D.new()
	root.name = "Woodland"
	parent.add_child(root)
	var variants: Array[Array] = []
	for i in range(4):
		variants.append(_tree(840 + i))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8108
	for chunk in range(0,int(length_m),100):
		for variant in range(4):
			var trees: Array[Transform3D] = []
			var bushes: Array[Transform3D] = []
			for side: float in [-1,1]:
				for i in range(10):
					var z := start - chunk - rng.randf_range(0,100)
					var scale_value := rng.randf_range(0.7,1.5)
					var basis := Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3(scale_value,scale_value*rng.randf_range(0.85,1.15),scale_value))
					trees.append(Transform3D(basis,Vector3(side*rng.randf_range(18,40),7.15,z)))
				for i in range(22):
					var z := start-chunk-rng.randf_range(0,100)
					var uphill := rng.randf_range(0.5,12)
					# Keep maintenance stairs and rib borders clear.
					var station := start-z
					if absf(station-20)<0.65 or absf(station-140)<0.65 or absf(station-320)<0.65 or absf(station-600)<0.65:
						continue
					var s := rng.randf_range(0.12,0.24)
					bushes.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3(s*1.4,s*0.75,s*1.4)),Vector3(side*(7.1+uphill*0.8),uphill*0.6,z)))
			Batch.batch(root,"BranchingTrunks_%d_%d"%[chunk,variant],variants[variant][0],trees,750)
			Batch.batch(root,"LeafCrowns_%d_%d"%[chunk,variant],variants[variant][1],trees,750)
			Batch.batch(root,"Understory_%d_%d"%[chunk,variant],variants[variant][1],bushes,350)
	_grass(root,start,length_m,rng)

static func _grass(root: Node3D, start: float, length_m: float, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(12):
		var angle := rng.randf_range(0,TAU)
		var base := Vector3(rng.randf_range(-0.11,0.11),0,rng.randf_range(-0.11,0.11))
		var tip := base+Vector3(cos(angle)*0.13,rng.randf_range(0.12,0.34),sin(angle)*0.13)
		st.set_color(Color("646941").lerp(Color("343f1d"),rng.randf()))
		for p in [base+Vector3(0.015,0,0),base-Vector3(0.015,0,0),tip]:
			st.add_vertex(p)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1
	st.set_material(m)
	var grass := st.commit()
	var rock := SphereMesh.new()
	rock.radial_segments = 5
	rock.rings = 3
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("6b6756")
	stone.roughness = 1
	rock.material = stone
	for chunk in range(0,int(length_m),50):
		var tufts: Array[Transform3D] = []
		var stones: Array[Transform3D] = []
		for i in range(900):
			var side := -1.0 if i%2 == 0 else 1.0
			var u := rng.randf_range(0.2,11.8)
			var z := start-chunk-rng.randf_range(0,50)
			var p := Vector3(side*(7.1+u*0.8),u*0.6+0.04,z)
			var s := rng.randf_range(0.5,1.4)
			if fposmod(u,3.9)<0.22:
				continue
			tufts.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3.ONE*s),p))
			if i%12 == 0:
				stones.append(Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf()*TAU,rng.randf())).scaled(Vector3(0.12,0.07,0.16)*s),p))
		Batch.batch(root,"GrassTufts_%d"%chunk,grass,tufts,180)
		Batch.batch(root,"SlopeStones_%d"%chunk,rock,stones,160)
