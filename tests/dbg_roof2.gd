extends SceneTree
func _initialize() -> void:
	var fp := BFFootprint.create_L(16, 12)
	print("footprint pts: ", fp.points)
	var outer := fp.outset(0.45)
	print("outset pts (", outer.size(), "): ", outer)
	var inner := BFWallBuilder.inner_polygon(outer, 0.12)
	print("parapet inner pts (", inner.size(), "): ", inner)
	# build only the roof
	var st := BFMeshUtil.new_st()
	var stt := BFMeshUtil.new_st()
	BFRoofBuilder.build_roof(BFRoofBuilder.RoofKind.FLAT, st, stt, fp, 15.0, {"overhang": 0.45, "pitch": 0.55, "tile": Vector2(0.5, 0.5), "parapet_h": 0.55})
	var mesh := BFMeshUtil.commit(st)
	print("roof surface mesh: verts=", mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), " errs=", BFMeshUtil.validate_mesh(mesh))
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mn := Vector3(999, 999, 999)
	var mx := Vector3(-999, -999, -999)
	for v in verts:
		mn = mn.min(v); mx = mx.max(v)
	print("roof bbox: ", mn, " -> ", mx)
	quit()
