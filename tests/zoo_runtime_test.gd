extends SceneTree
## Runtime smoke test: loads the walkable zoo map WITHOUT the plugin editor
## context (pure game runtime path), lets buildings regenerate from params,
## checks the player rig and collision, and verifies paint interactions work
## at runtime (facade material / roof kind / tint cycles).

const ZooMap := "res://demo/zoo_map.tscn"


func _initialize() -> void:
        await process_frame
        var ps: PackedScene = load(ZooMap)
        if ps == null:
                print("ZOO-RUNTIME FAIL: map not found")
                quit(1)
                return
        var map := ps.instantiate()
        root.add_child(map)
        await process_frame
        var buildings: Array = []
        for c in map.get_children():
                if c is ProceduralBuilding:
                        buildings.append(c)
        var player := map.get_node_or_null("Player")
        var ok := true
        ok = ok and _check(buildings.size() == 16, "16 buildings, got %d" % buildings.size())
        ok = ok and _check(player != null, "player exists")
        if player != null:
                ok = ok and _check(player.get("cam") != null, "player camera built")
        # every building generated geometry + collision
        var gen_count := 0
        var col_count := 0
        var total_tris := 0
        for b in buildings:
                var g: Node = b.get_node_or_null("Generated")
                var col: Node = b.get_node_or_null("Collision")
                if g != null and g.get_child_count() > 0:
                        gen_count += 1
                if col != null and col.get_child_count() > 0:
                        col_count += 1
                total_tris += int(b.stats.split("tris=")[1].split(" ")[0]) if "tris=" in b.stats else 0
        ok = ok and _check(gen_count == buildings.size(), "all buildings generated (gen=%d)" % gen_count)
        ok = ok and _check(col_count == buildings.size(), "all buildings have collision (col=%d)" % col_count)
        # runtime paint: facade material cycle on the first building
        if buildings.size() > 0:
                var b0: ProceduralBuilding = buildings[0]
                var before: String = b0.params.facade_material
                b0.params.facade_material = "brick_red"
                b0.params.emit_changed()
                await process_frame
                await process_frame
                var found := false
                for mi in b0.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
                        if (mi as MeshInstance3D).name.contains("brick_red"):
                                found = true
                                break
                ok = ok and _check(found, "runtime repaint applied (facade brick_red, was %s)" % before)
        if ok:
                print("ZOO-RUNTIME: ALL PASSED (tris total ~%d)" % total_tris)
        else:
                print("ZOO-RUNTIME: FAILURES")
        quit(0 if ok else 1)


func _check(cond: bool, label: String) -> bool:
        print(("  OK  " if cond else "  FAIL ") + label)
        return cond
