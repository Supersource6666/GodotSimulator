extends Node3D
## Reference-inspired visual overhead line, not a surveyed electrical design.
const Batch = preload("res://assets/procedural/detail_batch.gd")
const MAST_SPACING_M := 50.0
const CHUNK_LENGTH_M := 300.0
const WIRE_HEIGHT_M := 6.1
const MESSENGER_HEIGHT_M := 7.0
const MAST_HEIGHT_M := 7.8
const MAST_OFFSET_M := 4.65
const WIRE_STEP_M := 10.0
var mast_count := 0
var wire_segment_count := 0
var _root: Node3D

func build(route_length: float, pose_source: Callable) -> void:
	if _root != null:
		_root.free()
	_root = Node3D.new()
	_root.name = "OverheadLineBatches"
	add_child(_root)
	mast_count = 0
	wire_segment_count = 0
	if route_length <= 0 or not pose_source.is_valid():
		return
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.40, 0.43, 0.45)
	steel.metallic = 0.35
	steel.roughness = 0.8
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.12, 0.13, 0.14)
	wire_mat.roughness = 0.9
	var ceramic := StandardMaterial3D.new()
	ceramic.albedo_color = Color(0.37, 0.28, 0.22)
	ceramic.roughness = 0.85
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = steel
	var wire := CylinderMesh.new()
	wire.top_radius = 1
	wire.bottom_radius = 1
	wire.height = 1
	wire.radial_segments = 6
	wire.rings = 0
	wire.material = wire_mat
	var insulator := CylinderMesh.new()
	insulator.top_radius = 1
	insulator.bottom_radius = 1
	insulator.height = 1
	insulator.radial_segments = 8
	insulator.rings = 0
	insulator.material = ceramic
	var groups: Dictionary = {}
	var distance := 0.0
	while distance <= route_length:
		var key := int(distance / CHUNK_LENGTH_M)
		if not groups.has(key):
			groups[key] = {"steel": [], "wire": [], "ceramic": []}
		var group: Dictionary = groups[key]
		var pose: Dictionary = pose_source.call(distance, 0.0)
		var point: Vector3 = pose.point
		var right: Vector3 = pose.right
		var up: Vector3 = pose.up
		var base := point + right * MAST_OFFSET_M - up * 0.4
		# Two mast uprights and diagonal lattice braces.
		for side in [-1.0, 1.0]:
			var foot: Vector3 = base + right * float(side) * 0.15
			group.steel.append(Batch.beam(foot, foot + up * MAST_HEIGHT_M, 0.08, 0.12))
		for section in range(8):
			var sign := -1.0 if section % 2 == 0 else 1.0
			group.steel.append(Batch.beam(base + up * section * 0.95 + right * sign * 0.15,
				base + up * (section + 1) * 0.95 - right * sign * 0.15, 0.035))
		var contact := _wire_point(distance, pose_source, false)
		var arm_tip := contact + up * 0.35
		group.steel.append(Batch.beam(base + up * 6.8, arm_tip, 0.07))
		group.steel.append(Batch.beam(base + up * 7.6, arm_tip + right * 0.6, 0.055))
		group.steel.append(Batch.beam(arm_tip, contact, 0.045))
		var insulator_mid := (base + up * 6.8).lerp(arm_tip, 0.28)
		group.ceramic.append(Batch.beam(insulator_mid - right * 0.24, insulator_mid + right * 0.24, 0.105))
		mast_count += 1
		var end := minf(distance + MAST_SPACING_M, route_length)
		var cursor := distance
		while cursor < end:
			var next := minf(cursor + WIRE_STEP_M, end)
			var contact_a := _wire_point(cursor, pose_source, false)
			var contact_b := _wire_point(next, pose_source, false)
			var messenger_a := _wire_point(cursor, pose_source, true)
			var messenger_b := _wire_point(next, pose_source, true)
			group.wire.append(Batch.beam(contact_a, contact_b, 0.018))
			group.wire.append(Batch.beam(messenger_a, messenger_b, 0.012))
			group.wire.append(Batch.beam(contact_a, messenger_a, 0.008))
			wire_segment_count += 3
			cursor = next
		distance += MAST_SPACING_M
	for key in groups:
		var group: Dictionary = groups[key]
		var steel_poses: Array[Transform3D] = []
		var wire_poses: Array[Transform3D] = []
		var ceramic_poses: Array[Transform3D] = []
		steel_poses.assign(group.steel)
		wire_poses.assign(group.wire)
		ceramic_poses.assign(group.ceramic)
		Batch.batch(_root, "Masts_%d" % key, box, steel_poses, 0)
		Batch.batch(_root, "Wires_%d" % key, wire, wire_poses, 0)
		Batch.batch(_root, "Insulators_%d" % key, insulator, ceramic_poses, 900)
	print("CATENARY_READY masts=", mast_count, " wire_segments=", wire_segment_count)

func _wire_point(distance: float, pose_source: Callable, messenger: bool) -> Vector3:
	var pose: Dictionary = pose_source.call(distance, 0.0)
	var span := int(floor(distance / MAST_SPACING_M))
	var t := fposmod(distance, MAST_SPACING_M) / MAST_SPACING_M
	var sign := -1.0 if span % 2 == 0 else 1.0
	var stagger := lerpf(sign * 0.18, -sign * 0.18, t)
	var height := MESSENGER_HEIGHT_M - 0.35 * 4.0 * t * (1.0 - t) if messenger else WIRE_HEIGHT_M
	return (pose.point as Vector3) + (pose.up as Vector3) * height + (pose.right as Vector3) * stagger
