extends SceneTree
func _initialize() -> void:
	var b := ProceduralBuilding.new()
	get_root().add_child(b)
	var p := BFParams.new()
	b.params = p
	p.footprint = BFFootprint.create_rect(8, 6)
	p.floors = 1
	p.roof_kind = BFParams.Roof.FLAT
	p.roof_railing = false
	p.rooftop_equipment = false
	p.balconies = false
	p.seed = 42
	b.generate()
	for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
		var nm: String = (mi as MeshInstance3D).name
		if nm.contains("plaster_ext"):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			var arrays := mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			print("verts=", verts.size(), " tris=", idx.size() / 3)
			# sample first 12 verts of the front face (z = -3 outer)
			var count := 0
			for i in verts.size():
				if absf(verts[i].z + 3.0) < 0.001 and count < 10:
					print("v=%s n=%s" % [str(verts[i].snapped(Vector3(0.1, 0.1, 0.1))), str(norms[i].snapped(Vector3(0.05, 0.05, 0.05)))])
					count += 1
			break
	quit()
