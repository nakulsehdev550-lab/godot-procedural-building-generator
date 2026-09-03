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
	# pyramid region guess: x 2..8, y 5..14, z -6..0
	for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var xform := (mi as MeshInstance3D).transform
		var hits := 0
		for v in verts:
			var w := xform * v
			if w.x > 2.0 and w.x < 8.0 and w.y > 5.0 and w.y < 14.0 and w.z > -6.0 and w.z < 0.0:
				hits += 1
		if hits > 0:
			var mat := mesh.surface_get_material(0)
			print("%s [%s] hits=%d/%d" % [(mi as MeshInstance3D).name, mat.resource_name if mat != null else "?", hits, verts.size()])
	quit()
