extends SceneTree
## Debug: partition of an oval footprint

const BFWallS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
const BFStairS := preload("res://addons/building_forge/core/geometry/stair_builder.gd")
const BFFootprintS := preload("res://addons/building_forge/core/footprint.gd")


func _initialize() -> void:
	var fp := BFFootprintS.create_oval(13, 9)
	var inner := BFWallS.inner_polygon(fp.points, 0.25)
	var lo := inner[0]
	var hi := inner[0]
	for pt in inner:
		lo = lo.min(pt)
		hi = hi.max(pt)
	var bounds := Rect2(lo, hi - lo)
	print("bounds=", bounds, " area=", bounds.get_area())
	var plan_d := BFStairS.plan(BFStairS.StairKind.SPIRAL, 3.0, null)
	var cell := Rect2(bounds.get_center() - plan_d.cell.size * 0.5, plan_d.cell.size)
	print("spiral cell=", cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var res := BFPartitionerS.partition(bounds.grow(-0.02), inner, cell, 24.0, rng)
	var rooms: Array = res.rooms
	print("rooms=", rooms.size())
	for r in rooms:
		print("  kind=", (r as BFPartitionerS.Room).kind, " rect=", (r as BFPartitionerS.Room).rect, " area=", (r as BFPartitionerS.Room).rect.get_area())
	quit(0)
