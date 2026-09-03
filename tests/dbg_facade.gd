extends SceneTree
const BFFacadeS := preload("res://addons/building_forge/core/facade/facade.gd")
func _initialize() -> void:
	var p := BFParams.new()
	p.footprint = BFFootprint.create_rect(14, 11)
	p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
	p.apply_architecture_defaults()
	p.balconies = true
	p.stair_kind = BFParams.Stair.DOGLEG
	p.seed = 31
	var fp := p.footprint
	print("longest_edge=", fp.longest_edge(), " elen=", fp.edge_length(fp.longest_edge()))
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	# floor 0
	var open0 := BFFacadeS.layout_floor(fp, 0.0, 2.88, p, rng, -1, Vector2.ZERO)
	print("f0 keys=", open0.keys())
	for e in open0:
		for o in open0[e]:
			print("f0 edge=", e, " kind=", o.kind, " u=", o.u1, "..", o.u2)
	# raw punched layout for edge 0
	var raw := BFFacadeS._layout_punched(14.0, 2.88, p, rng)
	print("raw punched edge0 count=", raw.size())
	for o in raw:
		print("  raw kind=", o.kind, " u=", o.u1, "..", o.u2)
	# floor 1 with balcony reservation
	var be := fp.longest_edge()
	var open1 := BFFacadeS.layout_floor(fp, 3.0, 2.7, p, rng, be, Vector2(6.5, 7.5))
	for e in open1:
		for o in open1[e]:
			print("f1 edge=", e, " kind=", o.kind, " u=", o.u1, "..", o.u2)
	quit(0)
