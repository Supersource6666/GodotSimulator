extends SceneTree
## Bakes the procedural passenger-car livery into portable glTF PBR surfaces.

const SOURCE_PATH := "res://scenes/ballasted_track/train/models/HXD3D_waggon.glb"
const OUTPUT_PATH := "res://scenes/ballasted_track/train/models/HXD3D_waggon_colored.glb"
const SCENE_SCALE := Vector3(2.715, 2.784, 3.209)

const BODY := 0
const RUNNING_GEAR := 1
const ROOF := 2
const WINDOW := 3
const DOOR_WINDOW := 4
const STRIPE := 5
const GANGWAY := 6
const SURFACE_NAMES := [
	"Green body", "Running gear", "Grey roof", "Side windows",
	"Door windows", "Yellow waist stripes", "Gangway",
]


func _initialize() -> void:
	var error := _export_colored_waggon()
	print("COLORED_WAGGON_EXPORT ", "PASS" if error == OK else "FAIL",
		" path=", OUTPUT_PATH, " error=", error_string(error))
	quit(0 if error == OK else 1)


func _export_colored_waggon() -> Error:
	var packed := load(SOURCE_PATH) as PackedScene
	if packed == null:
		push_error("Unable to load passenger-car source GLB")
		return ERR_FILE_CANT_OPEN
	var source_root := packed.instantiate() as Node3D
	var source_meshes := source_root.find_children("*", "MeshInstance3D", true, false)
	if source_meshes.is_empty():
		push_error("Passenger-car GLB contains no MeshInstance3D")
		source_root.free()
		return ERR_INVALID_DATA
	var source := source_meshes[0] as MeshInstance3D
	if source.mesh == null or source.mesh.get_surface_count() == 0:
		source_root.free()
		return ERR_INVALID_DATA

	var builders: Array[SurfaceTool] = []
	for category in range(SURFACE_NAMES.size()):
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builders.append(builder)

	var triangle_counts := PackedInt32Array()
	triangle_counts.resize(SURFACE_NAMES.size())
	for surface in range(source.mesh.get_surface_count()):
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if vertices.is_empty() or normals.size() != vertices.size():
			source_root.free()
			return ERR_INVALID_DATA
		if indices.is_empty():
			indices.resize(vertices.size())
			for index in range(vertices.size()):
				indices[index] = index
		for triangle in range(0, indices.size(), 3):
			var a := indices[triangle]
			var b := indices[triangle + 1]
			var c := indices[triangle + 2]
			var center := (vertices[a] + vertices[b] + vertices[c]) / 3.0
			var normal := (normals[a] + normals[b] + normals[c]).normalized()
			var category := _livery_category(center, normal)
			for vertex_index in [a, b, c]:
				builders[category].set_normal(normals[vertex_index])
				builders[category].add_vertex(vertices[vertex_index])
			triangle_counts[category] += 1

	var output_mesh: ArrayMesh
	var materials := _build_materials()
	for category in range(builders.size()):
		if triangle_counts[category] == 0:
			continue
		builders[category].set_material(materials[category])
		output_mesh = builders[category].commit(output_mesh)
		output_mesh.surface_set_name(output_mesh.get_surface_count() - 1,
			SURFACE_NAMES[category])
	source_root.free()
	if output_mesh == null:
		return ERR_INVALID_DATA

	var export_root := Node3D.new()
	export_root.name = "HXD3DColoredPassengerCar"
	var exported_mesh := MeshInstance3D.new()
	exported_mesh.name = "ColoredPassengerCar"
	exported_mesh.mesh = output_mesh
	exported_mesh.scale = SCENE_SCALE
	export_root.add_child(exported_mesh)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(export_root, state)
	if append_error != OK:
		export_root.free()
		return append_error
	var write_error := document.write_to_filesystem(state, OUTPUT_PATH)
	export_root.free()
	print("COLORED_WAGGON_SURFACES triangles=", triangle_counts)
	return write_error


func _livery_category(point: Vector3, _normal: Vector3) -> int:
	var side := smoothstep(0.42, 0.51, absf(point.x))
	var window_zone := _step(0.82, point.y) * (1.0 - _step(1.36, point.y))
	var passenger_zone := 1.0 - _step(3.34, absf(point.z))
	var bay_phase := fposmod((point.z + 3.18) / 0.49, 1.0)
	var window_bay := _step(0.14, bay_phase) * (1.0 - _step(0.82, bay_phase))
	var window_mask := side * window_zone * passenger_zone * window_bay
	var door_zone := _step(3.36, absf(point.z)) * (1.0 - _step(3.82, absf(point.z)))
	var door_window := side * door_zone * _step(0.88, point.y) * (1.0 - _step(1.31, point.y))
	var lower_stripe := _step(0.675, point.y) * (1.0 - _step(0.735, point.y))
	var upper_stripe := _step(1.405, point.y) * (1.0 - _step(1.445, point.y))
	var stripe_mask := side * maxf(lower_stripe, upper_stripe)
	var gangway := _step(3.91, absf(point.z)) * (1.0 - side) * _step(0.58, point.y)
	if gangway > 0.1:
		return GANGWAY
	if stripe_mask > 0.1:
		return STRIPE
	if door_window > 0.1:
		return DOOR_WINDOW
	if window_mask > 0.1:
		return WINDOW
	if point.y > 1.50:
		return ROOF
	if point.y < 0.55:
		return RUNNING_GEAR
	return BODY


func _step(edge: float, value: float) -> float:
	return 0.0 if value < edge else 1.0


func _build_materials() -> Array[StandardMaterial3D]:
	return [
		_material("Green body", Color(0.032, 0.25, 0.108), 0.68, 0.08),
		_material("Running gear", Color(0.035, 0.045, 0.043), 0.82, 0.34),
		_material("Grey roof", Color(0.50, 0.53, 0.51), 0.78, 0.18),
		_material("Blue smoked windows", Color(0.075, 0.25, 0.26), 0.24, 0.12),
		_material("Door windows", Color(0.062, 0.205, 0.213), 0.28, 0.10),
		_material("Yellow waist stripes", Color(0.91, 0.72, 0.08), 0.68, 0.08),
		_material("Dark gangway", Color(0.025, 0.032, 0.031), 0.84, 0.18),
	]


func _material(title: String, color: Color, roughness: float,
		metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = title
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = 0.38
	return material
