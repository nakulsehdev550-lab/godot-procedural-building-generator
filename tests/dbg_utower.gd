extends SceneTree
## Debug: U-tower partition

const BFWallS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
const BFStairS := preload("res://addons/building_forge/core/geometry/stair_builder.gd")
const BFFootprintS := preload("res://addons/building_forge/core/footprint.gd")


func _initialize() -> void:
	var fp := BFFootprintS.create_U(20, 15)
	var inner := BFWallS.inner_polygon(fp.points, 0.25)
	var lo := inner[0]
	var hi := inner[0]
	for pt in inner:
		lo = lo.min(pt)
		hi = hi.max(pt)
	var bounds := Rect2(lo, hi - lo)
	print("bounds=", bounds)
	var plan_d := BFStairS.plan(BFStairS.StairKind.DOGLEG, 3.0, null)
	var sz: Vector2 = plan_d.cell.size
	var pad := 0.3
	var cell := Rect2(Vector2(bounds.position.x + pad, bounds.position.y + pad), sz)
	if not BFPartitionerS.rect_in_polygon(cell, inner, 0.18):
		cell = Rect2(bounds.get_center() - sz * 0.5, sz)
	print("cell=", cell, " fits=", BFPartitionerS.rect_in_polygon(cell, inner, 0.18))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1005
	var res := BFPartitionerS.partition(bounds.grow(-0.02), inner, cell, 24.0, rng)
	var rooms: Array = res.rooms
	print("rooms=", rooms.size())
	for r in rooms:
		print("  kind=", (r as BFPartitionerS.Room).kind, " rect=", (r as BFPartitionerS.Room).rect, " area=", (r as BFPartitionerS.Room).rect.get_area())
	quit(0)
