extends SceneTree
static func signed_volume(mesh: Mesh) -> float:
	var total := 0.0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in idx.size() / 3:
			total += verts[idx[t * 3]].dot(verts[idx[t * 3 + 1]].cross(verts[idx[t * 3 + 2]]))
	return total / 6.0
func _initialize() -> void:
	var fp := BFFootprint.create_L(16, 12)
	var st := BFMeshUtil.new_st()
	BFWallBuilder.build_walls(st, fp, 0.0, 3.0, 0.25, {}, Vector2(0.5, 0.5))
	var mesh := BFMeshUtil.commit(st)
	var inner := BFWallBuilder.inner_polygon(fp.points, 0.25)
	var ia := 0.0
	for i in inner.size():
		var p0 := inner[i]
		var p1 := inner[(i + 1) % inner.size()]
		ia += p0.x * p1.y - p1.x * p0.y
	var expected := (fp.area() - absf(ia) * 0.5) * 3.0
	print("L volume=", signed_volume(mesh), " expected=", expected, " verts_ok=", BFMeshUtil.validate_mesh(mesh).is_empty())
	quit()
