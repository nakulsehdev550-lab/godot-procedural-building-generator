extends SceneTree
## Dump every MeshInstance3D whose world AABB intersects a probe box
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
func _initialize() -> void:
	var b := ProceduralBuilding.new()
	root.add_child(b)
	b.params = BFParams.new()
	b.params.footprint = BFFootprint.create_rect(11, 8.5)
	b.params.floors = 2
	b.params.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
	b.params.roof_kind = BFParams.Roof.GABLE
	b.params.stair_kind = BFParams.Stair.STRAIGHT
	b.params.seed = 42
	b.generate()
	await process_frame
	var layout: Dictionary = b.last_room_layout.get(0, {})
	var walls: Array = layout.walls
	# find the living room + its door
	var probe := Vector3.INF
	for r in layout.rooms:
		var room: BFPartitionerS.Room = r as BFPartitionerS.Room
		if room.kind == "living":
			var doors := BFPartitionerS.room_doors(room, walls)
			if doors.size() > 0:
				var dp: Vector2 = doors[0].pos
				probe = Vector3(dp.x, 1.2, dp.y)
				print("living door at ", dp, " rooms ", seg_ids(room, walls))
	print("probe=", probe)
	if probe == Vector3.INF:
		quit(0); return
	var gen := b.get_node("Generated")
	for mi in gen.find_children("*", "MeshInstance3D", true, false):
		var mi3 := mi as MeshInstance3D
		if mi3.mesh == null: continue
		var aabb := mi3.global_transform * mi3.mesh.get_aabb()
		if aabb.has_point(probe) or aabb.grow(0.05).has_point(probe):
			print("HIT: ", mi3.name, " aabb=", aabb, " tris=", mi3.mesh.get_aabb())
	quit(0)
func seg_ids(room: BFPartitionerS.Room, walls: Array) -> String:
	var out := ""
	for s in walls:
		var seg := s as BFPartitionerS.WallSeg
		if seg.room_a == room.id or seg.room_b == room.id:
			out += str(seg.room_a) + "/" + str(seg.room_b) + " "
	return out
