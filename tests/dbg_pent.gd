extends SceneTree
## Debug: penthouse_tower floor 9 partition (hang reproduction)

const BFWallS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
const BFStairS := preload("res://addons/building_forge/core/geometry/stair_builder.gd")
const BFFootprintS := preload("res://addons/building_forge/core/footprint.gd")


func _initialize() -> void:
	var fp := BFFootprintS.create_rect(16, 12)
	var inner := BFWallS.inner_polygon(fp.points, 0.25)
	var lo := inner[0]
	var hi := inner[0]
	for pt in inner:
		lo = lo.min(pt)
		hi = hi.max(pt)
	var bounds := Rect2(lo, hi - lo)
	print("bounds=", bounds)
	var plan_d := BFStairS.plan(BFStairS.StairKind.DOGLEG, 3.0, null)
	# replicate _stair_search_cell order: corners with pad 0.3
	var sz: Vector2 = plan_d.cell.size
	var pad := 0.3
	var cell := Rect2(Vector2(bounds.position.x + pad, bounds.position.y + pad), sz)
	print("cell=", cell, " fits=", BFPartitionerS.rect_in_polygon(cell, inner, 0.18))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	print("partitioning...")
	var res := BFPartitionerS.partition(bounds.grow(-0.02), inner, cell, 24.0, rng)
	print("rooms=", (res.rooms as Array).size())
	for r in res.rooms:
		print("  ", (r as BFPartitionerS.Room).kind, " ", (r as BFPartitionerS.Room).rect)
	quit(0)
