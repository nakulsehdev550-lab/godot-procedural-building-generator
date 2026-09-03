extends SceneTree
## Geometry smoke test: validates wall bands, slabs, insets and windings
## using exact analytic volumes. Run:
##   godot --headless --path . --script res://tests/geo_smoke.gd

var fails := 0


func _initialize() -> void:
        test_footprint()
        test_wall_solid()
        test_wall_openings()
        test_slab()
        if fails == 0:
                print("GEO_SMOKE: ALL PASSED")
                quit(0)
        else:
                print("GEO_SMOKE: %d FAILURES" % fails)
                quit(1)


func check(cond: bool, msg: String) -> void:
        if not cond:
                fails += 1
                printerr("FAIL: " + msg)


## Signed volume; Godot CW-front meshes with outward normals -> negative.
static func signed_volume(mesh: Mesh) -> float:
        var total := 0.0
        for s in mesh.get_surface_count():
                var arrays := mesh.surface_get_arrays(s)
                var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
                if idx.is_empty():
                        continue
                for t in idx.size() / 3:
                        var a := verts[idx[t * 3]]
                        var b := verts[idx[t * 3 + 1]]
                        var c := verts[idx[t * 3 + 2]]
                        total += a.dot(b.cross(c))
        return total / 6.0


func mesh_errors(mesh: Mesh) -> Array:
        return BFMeshUtil.validate_mesh(mesh)


func test_footprint() -> void:
        var fp := BFFootprint.create_rect(10, 8)
        check(is_equal_approx(fp.area(), 80.0), "rect area")
        check(fp.validate() == "", "rect validate: " + fp.validate())
        var inner := BFWallBuilder.inner_polygon(fp.points, 0.25)
        check(inner.size() == 4, "inner keeps vertex count")
        # inner must be exactly inset by 0.25
        check(is_equal_approx(inner[0].x, -4.75) and is_equal_approx(inner[0].y, -3.75), "miter inset corner 0: %s" % str(inner[0]))
        check(is_equal_approx(inner[1].x, 4.75) and is_equal_approx(inner[1].y, -3.75), "miter inset corner 1: %s" % str(inner[1]))
        var fp_l := BFFootprint.create_L(12, 9)
        check(fp_l.validate() == "", "L validate: " + fp_l.validate())
        check(BFFootprint.create_L(12, 9).area() > 40.0, "L area sane")
        var fp_u := BFFootprint.create_U(12, 10)
        check(fp_u.validate() == "", "U validate: " + fp_u.validate())
        var fp_c := BFFootprint.create_circle(6)
        check(fp_c.validate() == "", "circle validate")
        check(absf(fp_c.area() - PI * 36.0) < 1.5, "circle area ~ PI r2")


func test_wall_solid() -> void:
        var fp := BFFootprint.create_rect(10, 8)
        var st := BFMeshUtil.new_st()
        BFWallBuilder.build_walls(st, fp, 0.0, 3.0, 0.25, {}, Vector2(0.5, 0.5))
        var mesh := BFMeshUtil.commit(st)
        check(mesh != null, "wall mesh built")
        if mesh == null:
                return
        var errs := mesh_errors(mesh)
        check(errs.is_empty(), "wall mesh valid: %s" % str(errs))
        # exact volume: (outer - inner area) * height
        var inner := BFWallBuilder.inner_polygon(fp.points, 0.25)
        var inner_area := absf(BFFootprint._poly_area_signed(inner))
        var expected := (80.0 - inner_area) * 3.0
        var vol := signed_volume(mesh)
        check(absf(vol) > 0.0, "wall closed (nonzero volume)")
        check(absf(absf(vol) - expected) < 0.01, "wall volume exact: got %f want %f" % [vol, expected])
        check(vol < 0, "wall normals outward (Godot convention)")


func test_wall_openings() -> void:
        var fp := BFFootprint.create_rect(10, 8)
        # one window 1.2 x 1.4 on edge 0 (bottom, length 10), mid-edge
        var ops := {0: [BFWallBuilder.make_opening(4.0, 5.2, 0.9, 2.3)]}
        var st := BFMeshUtil.new_st()
        BFWallBuilder.build_walls(st, fp, 0.0, 3.0, 0.25, ops, Vector2(0.5, 0.5))
        var mesh := BFMeshUtil.commit(st)
        check(mesh != null, "wall w/ opening built")
        if mesh == null:
                return
        var errs := mesh_errors(mesh)
        check(errs.is_empty(), "opening mesh valid: %s" % str(errs))
        var inner := BFWallBuilder.inner_polygon(fp.points, 0.25)
        var inner_area := absf(BFFootprint._poly_area_signed(inner))
        var expected := (80.0 - inner_area) * 3.0 - 1.2 * 1.4 * 0.25
        var vol := signed_volume(mesh)
        check(absf(absf(vol) - expected) < 0.02, "opening volume exact: got %f want %f" % [vol, expected])
        check(vol < 0, "opening normals outward")


func test_slab() -> void:
        var fp := BFFootprint.create_rect(10, 8)
        var st := BFMeshUtil.new_st()
        BFSlabBuilder.build_slab(st, fp.points, 0.0, 0.3, Rect2(), Vector2(0.5, 0.5), false)
        var mesh := BFMeshUtil.commit(st)
        check(mesh != null, "slab built")
        if mesh == null:
                return
        var errs := mesh_errors(mesh)
        check(errs.is_empty(), "slab valid: %s" % str(errs))
        var vol := signed_volume(mesh)
        check(absf(absf(vol) - 24.0) < 0.01, "slab volume: got %f want 24" % vol)
        check(vol < 0, "slab normals outward")
        # slab with stair hole 2x3
        var st2 := BFMeshUtil.new_st()
        BFSlabBuilder.build_slab(st2, fp.points, 0.0, 0.3, Rect2(Vector2(1, 1), Vector2(2, 3)), Vector2(0.5, 0.5), false)
        var mesh2 := BFMeshUtil.commit(st2)
        var vol2 := signed_volume(mesh2)
        check(absf(absf(vol2) - (24.0 - 6.0 * 0.3)) < 0.05, "slab hole volume: got %f want %f" % [vol2, 24.0 - 1.8])
