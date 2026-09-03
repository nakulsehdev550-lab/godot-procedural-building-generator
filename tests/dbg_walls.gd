extends SceneTree
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
const BFWallS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")
const BFFootprintS := preload("res://addons/building_forge/core/footprint.gd")
const BFStairS := preload("res://addons/building_forge/core/geometry/stair_builder.gd")
func _initialize() -> void:
	var fp := BFFootprintS.create_rect(14, 11)
	var inner := BFWallS.inner_polygon(fp.points, 0.25)
	var lo := inner[0]; var hi := inner[0]
	for pt in inner: lo = lo.min(pt); hi = hi.max(pt)
	var bounds := Rect2(lo, hi - lo)
	var plan_d := BFStairS.plan(BFStairS.StairKind.DOGLEG, 3.0, null)
	var sz: Vector2 = plan_d.cell.size
	var cell := Rect2(Vector2(bounds.position.x + 0.3, bounds.position.y + 0.3), sz)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var res := BFPartitionerS.partition(bounds.grow(-0.02), inner, cell, 18.0, rng)
	BFPartitionerS.assign_kinds(res.rooms, 0, 3, rng, false)
	print("door segs:")
	for s in res.walls:
		var seg := s as BFPartitionerS.WallSeg
		if not seg.door.is_empty():
			print("  seg A=", seg.a, " B=", seg.b, " doorA=", seg.door.a, " doorB=", seg.door.b, " rooms=", seg.room_a, "/", seg.room_b)
	print("all segs near (3.9, 1.4):")
	for s2 in res.walls:
		var seg2 := s2 as BFPartitionerS.WallSeg
		var mid := (seg2.a + seg2.b) * 0.5
		if absf(mid.x - 3.9) < 1.2 and absf(mid.y - 1.4) < 1.2:
			print("  A=", seg2.a, " B=", seg2.b, " door=", not seg2.door.is_empty(), " rooms=", seg2.room_a, "/", seg2.room_b)
	quit(0)
