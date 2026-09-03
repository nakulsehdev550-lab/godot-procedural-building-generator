extends SceneTree
func _initialize() -> void:
	var b := ProceduralBuilding.new()
	get_root().add_child(b)
	var p := BFParams.new()
	b.params = p
	p.footprint = BFFootprint.create_L(16, 12)
	p.floors = 5
	p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
	p.apply_architecture_defaults()
	p.seed = 7
	b.generate()
	for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		var wt := (mi as MeshInstance3D).transform
		var wmin := aabb.position * 1.0 + wt.origin
		var wmax := wmin + aabb.size
		# notch region: x in [0.8, 8], z in [-6, 0.6]
		if wmax.x > 1.0 and wmin.x < 8.0 and wmax.z > -6.0 and wmin.z < 0.4:
			var mat := mesh.surface_get_material(0)
			var mn: String = mat.resource_name if mat != null else "?"
			print("%s [%s] x:%.1f..%.1f y:%.1f..%.1f z:%.1f..%.1f" % [(mi as MeshInstance3D).name, mn, wmin.x, wmax.x, wmin.y, wmax.y, wmin.z, wmax.z])
	quit()
