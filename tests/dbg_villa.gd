extends SceneTree
func _initialize() -> void:
	var b := ProceduralBuilding.new()
	get_root().add_child(b)
	var p := BFParams.new()
	b.params = p
	p.footprint = BFFootprint.create_L(14, 11)
	p.floors = 2
	p.architecture = BFParams.ArchStyle.MODERN
	p.apply_architecture_defaults()
	p.seed = 11
	print("roof_kind=", p.roof_kind, " facade=", p.facade_material, " wstyle=", p.window_style)
	b.generate()
	for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
		print("  ", (mi as MeshInstance3D).name, " aabb=", (mi as MeshInstance3D).mesh.get_aabb().size)
	quit()
