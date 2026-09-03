extends SceneTree
const BFParamsS := preload("res://addons/building_forge/core/params.gd")
func _initialize() -> void:
	var b := ProceduralBuilding.new()
	root.add_child(b)
	b.params = BFParamsS.new()
	b.params.footprint = BFFootprint.create_rect(16, 12)
	b.params.floors = 10
	b.params.architecture = BFParams.ArchStyle.MODERN
	b.params.apply_architecture_defaults()
	b.params.roof_kind = BFParams.Roof.FLAT
	b.params.roof_railing = true
	b.params.balconies = true
	b.params.balcony_every_n_floors = 2
	b.params.stair_kind = BFParams.Stair.DOGLEG
	b.params.seed = 99
	print("generating...")
	b.generate()
	print("DONE: ", b.stats)
	for fi in b.last_room_layout:
		print("floor ", fi, " rooms=", (b.last_room_layout[fi].rooms as Array).size())
	quit(0)
