extends SceneTree
## End-to-end generation tests: builds multiple building types headlessly,
## validates every mesh, checks alignment invariants, interiors, stairs and
## measures generation performance.
##   godot --headless --path . --script res://tests/e2e_test.gd

var fails := 0
var checks := 0


func _initialize() -> void:
        test_house()
        test_apartment()
        test_tower()
        test_circular()
        test_user_move_preserved()
        test_finalize()
        test_floor_overrides()
        test_custom_openings()
        test_new_roofs()
        test_prop_replacement()
        test_tint()
        test_editor_api()
        if fails == 0:
                print("E2E: ALL %d CHECKS PASSED" % checks)
                quit(0)
        else:
                print("E2E: %d/%d FAILED" % [fails, checks])
                quit(1)


func check(cond: bool, msg: String) -> void:
        checks += 1
        if not cond:
                fails += 1
                printerr("  FAIL: " + msg)


func make_building(p: BFParams) -> ProceduralBuilding:
        var b := ProceduralBuilding.new()
        b.name = "TestBuilding"
        get_root().add_child(b)
        b.params = p
        b.generate()
        return b


func validate_building(b: ProceduralBuilding, label: String) -> void:
        var gen := b.get_node_or_null("Generated")
        check(gen != null, label + ": has Generated root")
        if gen == null:
                return
        var meshes: Array = gen.find_children("*", "MeshInstance3D", true, false)
        check(meshes.size() > 3, label + ": has meshes (%d)" % meshes.size())
        var total_tris := 0
        var err_count := 0
        for mi in meshes:
                var mesh: Mesh = (mi as MeshInstance3D).mesh
                if mesh == null:
                        err_count += 1
                        continue
                total_tris += _tri_count(mesh)
                var errs := BFMeshUtil.validate_mesh(mesh)
                if not errs.is_empty():
                        err_count += 1
                        if err_count <= 3:
                                printerr("    mesh %s: %s" % [(mi as MeshInstance3D).name, str(errs)])
        check(err_count == 0, label + ": all meshes valid (%d bad)" % err_count)
        check(total_tris > 500, label + ": triangle budget sane (%d)" % total_tris)
        print("  [%s] meshes=%d tris=%d  %s" % [label, meshes.size(), total_tris, b.stats])


func _tri_count(mesh: Mesh) -> int:
        var n := 0
        for s in mesh.get_surface_count():
                var arrays := mesh.surface_get_arrays(s)
                var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
                if idx.size() > 0:
                        n += idx.size() / 3
                else:
                        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                        n += verts.size() / 3
        return n


func test_house() -> void:
        print("* suburban house")
        var p := BFParams.new()
        p.footprint = BFFootprint.create_rect(10, 8)
        p.floors = 2
        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
        p.roof_kind = BFParams.Roof.GABLE
        p.seed = 42
        var b := make_building(p)
        validate_building(b, "house")
        # alignment: walls of floor 0 must start at y=0 and reach fh-0.12
        var shell_aabb = _aabb_of_named(b, "plaster_ext")
        if shell_aabb != null:
                check(absf((shell_aabb as AABB).position.y) < 0.01, "house walls base at y=0: %f" % (shell_aabb as AABB).position.y)
        # windows exist
        var found_window := false
        for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
                if (mi as MeshInstance3D).name.contains("trim_white"):
                        found_window = true
        check(found_window, "house has window/trim meshes")
        # stairs exist
        var has_stairs := false
        for mi2 in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
                if (mi2 as MeshInstance3D).name.contains("concrete"):
                        has_stairs = true
        check(has_stairs, "house has stair concrete")
        b.queue_free()


func test_apartment() -> void:
        print("* brick apartment")
        var p := BFParams.new()
        p.footprint = BFFootprint.create_L(16, 12)
        p.floors = 5
        p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
        p.apply_architecture_defaults()
        p.seed = 7
        var b := make_building(p)
        validate_building(b, "apartment")
        # 5 floor nodes
        var floors := 0
        for c in b.get_node("Generated").get_children():
                if (c as Node).name.begins_with("Floor_"):
                        floors += 1
        check(floors == 5, "apartment has 5 floor nodes (%d)" % floors)
        # balconies on floors > 0
        var has_balcony := false
        for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
                if (mi as MeshInstance3D).name.contains("concrete") and (mi as MeshInstance3D).name.contains("f01"):
                        has_balcony = true
        check(has_balcony, "apartment has balcony concrete")
        b.queue_free()


func test_tower() -> void:
        print("* office tower")
        var p := BFParams.new()
        p.footprint = BFFootprint.create_rect(24, 18)
        p.floors = 12
        p.architecture = BFParams.ArchStyle.OFFICE_TOWER
        p.apply_architecture_defaults()
        p.max_room_area = 40.0
        p.seed = 1234
        var t0 := Time.get_ticks_usec()
        var b := make_building(p)
        var ms := (Time.get_ticks_usec() - t0) / 1000.0
        validate_building(b, "tower")
        check(ms < 30000.0, "tower generation < 30s (%.1f ms)" % ms)
        print("  tower gen time: %.1f ms" % ms)
        b.queue_free()


func test_circular() -> void:
        print("* circular villa")
        var p := BFParams.new()
        p.footprint = BFFootprint.create_circle(7)
        p.floors = 3
        p.roof_kind = BFParams.Roof.CONE
        p.seed = 55
        var b := make_building(p)
        validate_building(b, "circular")
        b.queue_free()


## Regeneration must preserve user-moved parts (matched by part id).
func test_user_move_preserved() -> void:
        print("* user move preservation")
        var p := BFParams.new()
        p.footprint = BFFootprint.create_rect(10, 8)
        p.floors = 2
        p.generate_interior = true
        p.seed = 42
        var b := make_building(p)
        var meshes: Array = b.get_node("Generated").find_children("*", "MeshInstance3D", true, false)
        check(meshes.size() > 0, "preservation: meshes exist")
        if meshes.is_empty():
                return
        var target := meshes[0] as MeshInstance3D
        var pid: String = target.get_meta("bf_part_id")
        var moved := target.transform.translated(Vector3(1.5, 2.5, -0.5))
        target.transform = moved
        b.generate()  # manual regeneration
        var meshes2: Array = b.get_node("Generated").find_children("*", "MeshInstance3D", true, false)
        var restored: MeshInstance3D = null
        for mi in meshes2:
                if (mi as MeshInstance3D).has_meta("bf_part_id") and (mi as MeshInstance3D).get_meta("bf_part_id") == pid:
                        restored = mi
                        break
        check(restored != null, "preservation: part id found after regen")
        if restored != null:
                check(restored.transform.origin.distance_to(moved.origin) < 0.001,
                        "preservation: transform kept (%s vs %s)" % [restored.transform.origin, moved.origin])
        b.queue_free()


func test_finalize() -> void:
        print("* finalize")
        var p := BFParams.new()
        p.footprint = BFFootprint.create_rect(9, 7)
        p.floors = 1
        p.seed = 3
        var b := make_building(p)
        var standalone := b.finalize()
        check(standalone != null, "finalize returns node")
        if standalone != null:
                check(standalone.get_child_count() > 0, "finalize has children")
                var meshes: Array = standalone.find_children("*", "MeshInstance3D", true, false)
                check(meshes.size() > 0, "finalize kept meshes (%d)" % meshes.size())
        standalone.queue_free()
        b.queue_free()


func _aabb_of_named(b: ProceduralBuilding, substr: String):
        for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
                if (mi as MeshInstance3D).name.contains(substr):
                        var mesh: Mesh = (mi as MeshInstance3D).mesh
                        if mesh != null:
                                var aabb := mesh.get_aabb()
                                var x := (mi as MeshInstance3D).transform
                                return AABB(aabb.position + x.origin, aabb.size)
        return null


## --- v1.2 feature regression -----------------------------------------------

func test_floor_overrides() -> void:
                var p := BFParams.new()
                p.footprint = BFFootprint.create_rect(12, 9)
                p.floors = 3
                p.roof_kind = BFParams.Roof.FLAT
                var ov := BFFloorOverride.new()
                ov.facade_material = "brick_red"
                ov.outset = 0.6
                p.floor_overrides = [null, ov, null]
                var b := make_building(p)
                validate_building(b, "floor_overrides")
                var brick := b.get_node("Generated").find_child("f01_00_brick_red", true, false)
                if brick == null:
                        brick = b.get_node("Generated").find_child("*brick_red*", true, false)
                check(brick != null, "floor_overrides: floor 1 uses brick_red")
                # floor 1 outset: its wall AABB must exceed the ground floor's
                var f1_wall := _wall_aabb(b, "Floor_01")
                var f0_wall := _wall_aabb(b, "Floor_00")
                check(f1_wall.size.x > f0_wall.size.x + 0.5, "floor_overrides: floor 1 overhangs ground (%.2f vs %.2f)" % [f1_wall.size.x, f0_wall.size.x])
                b.queue_free()


func test_custom_openings() -> void:
                var p := BFParams.new()
                p.footprint = BFFootprint.create_rect(12, 9)
                p.floors = 2
                p.roof_kind = BFParams.Roof.FLAT
                var b := make_building(p)
                var ok := b.add_custom_opening_at(Vector2(6.0, 0.0), "window", 1.3)
                check(ok, "custom_openings: window added near an edge")
                check(b.params.custom_openings.size() == 1, "custom_openings: stored in params")
                b.generate()
                var has_custom := false
                for fi in b.last_openings:
                                for e in b.last_openings[fi]:
                                                for o in b.last_openings[fi][e]:
                                                                if o.get("edge", 0) == -1:
                                                                                has_custom = true
                check(has_custom, "custom_openings: punched in facade layout")
                check(b.remove_custom_openings_near(Vector2(6.0, 0.0)) == 1, "custom_openings: removed by position")
                b.queue_free()


func test_new_roofs() -> void:
                for kind in [BFParams.Roof.MANSARD, BFParams.Roof.GAMBREL, BFParams.Roof.SHED]:
                                var p := BFParams.new()
                                p.footprint = BFFootprint.create_rect(11, 8)
                                p.floors = 1
                                p.roof_kind = kind
                                var b := make_building(p)
                                validate_building(b, "roof_%d" % kind)
                                var roof := b.get_node("Generated").find_child("Roof_Surface", true, false)
                                check(roof != null, "roof_%d: Roof_Surface exists" % kind)
                                b.queue_free()


func test_prop_replacement() -> void:
                var p := BFParams.new()
                p.footprint = BFFootprint.create_rect(12, 9)
                p.floors = 2
                p.roof_kind = BFParams.Roof.FLAT
                var scene := PackedScene.new()
                var mi := MeshInstance3D.new()
                mi.name = "CustomSofa"
                var bm := BoxMesh.new()
                bm.size = Vector3(1, 0.5, 1)
                mi.mesh = bm
                scene.pack(mi)
                p.prop_scenes = {"sofa": scene}
                var b := make_building(p)
                var found := false
                for wrap in b.get_node("Generated").find_children("Prop_sofa_*", "Node3D", true, false):
                                if (wrap as Node3D).get_child_count() > 0:
                                                found = true
                check(found, "prop_replacement: custom sofa scene instanced")
                b.queue_free()


func test_tint() -> void:
                var p := BFParams.new()
                p.footprint = BFFootprint.create_rect(12, 9)
                p.floors = 1
                p.roof_kind = BFParams.Roof.FLAT
                p.facade_tint = Color(0.5, 0.4, 0.3)
                var b := make_building(p)
                var wall := b.get_node("Generated").find_child("f00_00_plaster_ext", true, false)
                check(wall != null, "tint: wall mesh exists")
                if wall != null:
                                var mat: Material = (wall as MeshInstance3D).mesh.surface_get_material(0)
                                check(mat != null and mat.resource_name == "plaster_ext_tinted", "tint: tinted material applied")
                                var s := mat as StandardMaterial3D
                                check(s != null and s.albedo_color.is_equal_approx(Color(0.5, 0.4, 0.3)), "tint: albedo multiplied")
                b.queue_free()


func test_editor_api() -> void:
                var p := BFParams.new()
                p.footprint = BFFootprint.create_rect(12, 9)
                p.floors = 2
                p.roof_kind = BFParams.Roof.FLAT
                var b := make_building(p)
                var n0: int = b.params.footprint.points.size()
                var idx := b.insert_wall_point(Vector2(6.0, 0.0))
                check(idx > 0 and b.params.footprint.points.size() == n0 + 1, "editor_api: bend point inserted")
                check(b.remove_wall_point(Vector2(6.05, 0.0)), "editor_api: point removed")
                check(b.params.footprint.points.size() == n0, "editor_api: vertex count restored")
                b.set_entrance_at(Vector2(0.0, -4.5))
                check(b.params.entrance_point != Vector2(INF, INF), "editor_api: entrance override set")
                check(b.add_custom_opening_at(Vector2(6.0, 0.0), "door", 1.0), "editor_api: door opening added")
                b.clear_custom_openings()
                check(b.params.custom_openings.is_empty(), "editor_api: openings cleared")
                b.queue_free()


func _wall_aabb(b: ProceduralBuilding, floor_name: String) -> AABB:
        var n := b.get_node("Generated").get_node_or_null(floor_name)
        if n == null:
                return AABB()
        for mi in (n as Node3D).find_children("*", "MeshInstance3D", true, false):
                var nm := (mi as MeshInstance3D).name
                if "_00_" in nm and ("plaster_ext" in nm or "brick_red" in nm or "stone" in nm or "facade_panel" in nm):
                        return (mi as MeshInstance3D).mesh.get_aabb()
        return AABB()
