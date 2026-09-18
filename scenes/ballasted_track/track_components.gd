extends RefCounted
## Reference-led visual assembly, not a manufacturing drawing.
## Coordinates: X across sleeper, Y up, Z along rail. Rail-foot underside: 0.502 m.
const SEAT_TOP := 0.49
const PAD_TOP := 0.502
const BOLT_OFFSET := 0.155

static func material(color: String, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = rough
	m.metallic = metal
	return m

static func concrete() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://scenes/ballasted_track/sleeper_concrete.gdshader")
	return m

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	# Godot clockwise front faces; explicit planar normals prevent pillowy concrete.
	if (c-a).cross(b-a).dot(outward) < 0:
		var swap := b
		b = c
		c = swap
	st.set_normal((c-a).cross(b-a).normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_triangle(st,a,b,c,outward)
	_triangle(st,a,c,d,outward)

static func sleeper() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# x, top, top half-width. Lower body remains a continuous prestressed beam.
	# Raised end blocks, recessed flat rail seats, long tapered transition to waist.
	var profiles := [
		Vector3(-1.25,0.49,0.108),Vector3(-1.215,0.525,0.119),
		Vector3(-1.055,0.525,0.119),Vector3(-1.02,0.49,0.116),
		Vector3(-0.49,0.49,0.116),Vector3(-0.445,0.515,0.112),
		Vector3(-0.32,0.475,0.103),Vector3(-0.13,0.449,0.096),
		Vector3(0.13,0.449,0.096),Vector3(0.32,0.475,0.103),
		Vector3(0.445,0.515,0.112),Vector3(0.49,0.49,0.116),
		Vector3(1.02,0.49,0.116),Vector3(1.055,0.525,0.119),
		Vector3(1.215,0.525,0.119),Vector3(1.25,0.49,0.108)]
	var rings: Array = []
	for p in profiles:
		var bottom := 0.285
		var width := 0.14 if absf(p.x)<1.24 else 0.128
		var bevel := 0.009
		rings.append([Vector3(p.x,bottom,-width+bevel),
			Vector3(p.x,bottom+bevel,-width),Vector3(p.x,p.y-bevel,-p.z),
			Vector3(p.x,p.y,-p.z+bevel),Vector3(p.x,p.y,p.z-bevel),
			Vector3(p.x,p.y-bevel,p.z),Vector3(p.x,bottom+bevel,width),
			Vector3(p.x,bottom,width-bevel)])
	for i in range(rings.size()-1):
		for j in range(8):
			var k := (j+1)%8
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][k]
			var mid := (a+b)*0.5
			_quad(st,a,b,rings[i+1][k],rings[i+1][j],Vector3(0,mid.y-0.395,mid.z))
	for end in [0,rings.size()-1]:
		var center := Vector3(profiles[end].x,0.39,0)
		for j in range(8):
			_triangle(st,center,rings[end][j],rings[end][(j+1)%8],Vector3.LEFT if end==0 else Vector3.RIGHT)
	st.set_material(concrete())
	return st.commit()

static func _box(st: SurfaceTool, p: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	st.append_from(mesh,0,Transform3D(Basis.IDENTITY,p))

static func _cylinder(st: SurfaceTool, p: Vector3, radius: float, height: float, sides: int = 16) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	st.append_from(mesh,0,Transform3D(Basis.IDENTITY,p))

static func _ring(st: SurfaceTool, p: Vector3, outer: float, inner: float, height: float, sides: int = 24) -> void:
	for i in range(sides):
		var a := TAU*i/sides
		var b := TAU*(i+1)/sides
		var u := Vector3(cos(a),0,sin(a))
		var v := Vector3(cos(b),0,sin(b))
		var up := Vector3.UP*height*0.5
		_quad(st,p+u*inner+up,p+u*outer+up,p+v*outer+up,p+v*inner+up,Vector3.UP)
		_quad(st,p+u*outer-up,p+u*outer+up,p+v*outer+up,p+v*outer-up,u+v)
		_quad(st,p+u*inner-up,p+v*inner-up,p+v*inner+up,p+u*inner+up,-u-v)

static func _tube(st: SurfaceTool, points: Array[Vector3], radius: float) -> void:
	for i in range(points.size()-1):
		var axis := (points[i+1]-points[i]).normalized()
		var u := axis.cross(Vector3.UP).normalized()
		if u.length_squared()<0.01: u = Vector3.RIGHT
		var v := axis.cross(u).normalized()
		for j in range(10):
			var n := u*cos(TAU*j/10)+v*sin(TAU*j/10)
			var m := u*cos(TAU*(j+1)/10)+v*sin(TAU*(j+1)/10)
			for pair in [[points[i]+n*radius,n],[points[i+1]+n*radius,n],[points[i]+m*radius,m],[points[i]+m*radius,m],[points[i+1]+n*radius,n],[points[i+1]+m*radius,m]]:
				st.set_normal(pair[1])
				st.add_vertex(pair[0])

	for end in [0,points.size()-1]:
		var axis := (points[1]-points[0]).normalized() if end==0 else (points[-1]-points[-2]).normalized()
		var u := axis.cross(Vector3.UP).normalized()
		var v := axis.cross(u).normalized()
		for j in range(10):
			var a := points[end]+radius*(u*cos(TAU*j/10)+v*sin(TAU*j/10))
			var b := points[end]+radius*(u*cos(TAU*(j+1)/10)+v*sin(TAU*(j+1)/10))
			_triangle(st,points[end],a,b,-axis if end==0 else axis)

static func fastening() -> ArrayMesh:
	var result := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Resilient pad carries the rail foot; cast-in anchors pass through side plates.
	_box(st,Vector3(0,0.496,0),Vector3(0.162,0.012,0.196))
	for side in [-1.0,1.0]:
		_box(st,Vector3(side*0.144,0.494,0),Vector3(0.122,0.008,0.19))
		_ring(st,Vector3(side*BOLT_OFFSET,0.499,0),0.018,0.011,0.003)
	st.set_material(material("292d2d",0.91))
	st.commit(result)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		# Gauge block bears against the flange edge. Thin toe insulator rests on flange.
		_box(st,Vector3(side*0.089,0.514,0),Vector3(0.024,0.028,0.142))
		_box(st,Vector3(side*0.066,0.531,0),Vector3(0.036,0.006,0.148))
		_box(st,Vector3(side*0.192,0.509,0),Vector3(0.050,0.022,0.166))
		_box(st,Vector3(side*0.212,0.524,0),Vector3(0.026,0.022,0.148))
	st.set_material(material("51463a",0.88,0.08))
	st.commit(result)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		# Twin toes, rear heels and a central loop loaded by the nut/washer.
		var control: Array[Vector3] = [
			Vector3(0.069,0.541,0.059),Vector3(0.105,0.560,0.067),
			Vector3(0.151,0.576,0.061),Vector3(0.195,0.558,0.052),
			Vector3(0.210,0.542,0.037),Vector3(0.188,0.567,0.022),
			Vector3(0.157,0.579,0.017),Vector3(0.133,0.579,0),
			Vector3(0.157,0.579,-0.017),Vector3(0.188,0.567,-0.022),
			Vector3(0.210,0.542,-0.037),Vector3(0.195,0.558,-0.052),
			Vector3(0.151,0.576,-0.061),Vector3(0.105,0.560,-0.067),
			Vector3(0.069,0.541,-0.059)]
		var curve := Curve3D.new()
		for i in range(control.size()):
			var p := control[i]
			p.x *= side
			var tangent := (control[mini(i+1,control.size()-1)]-control[maxi(i-1,0)])*0.16
			tangent.x *= side
			curve.add_point(p,-tangent,tangent)
		curve.bake_interval = 0.004
		var points: Array[Vector3] = []
		points.assign(curve.get_baked_points())
		_tube(st,points,0.007)
	st.set_material(material("743c2e",0.78,0.24))
	st.commit(result)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0,1.0]:
		var x: float = side*BOLT_OFFSET
		_cylinder(st,Vector3(x,0.553,0),0.010,0.15,16)
		_ring(st,Vector3(x,0.588,0),0.027,0.0105,0.004)
		_cylinder(st,Vector3(x,0.601,0),0.021,0.023,6)
		# Beveled nut crown and exposed thread ridges, readable in close view.
		_cylinder(st,Vector3(x,0.614,0),0.0185,0.003,6)
		for j in range(5):
			_ring(st,Vector3(x,0.616+j*0.0026,0),0.011,0.009,0.0012,16)
	st.set_material(material("5e493d",0.69,0.35))
	st.commit(result)
	return result
