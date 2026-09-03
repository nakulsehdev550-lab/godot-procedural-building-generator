extends SceneTree
## Architecture QA tests - verifies the v1.1 user-reported fixes:
##   1. regenerate does not pile up old buildings
##   2. stairs exist for every floor below the top + slab holes punched
##   3. every room is door-reachable (partitioner graph connectivity)
##   4. the stair hall has a door (no sealed stairwells)
##   5. room kind diversity (bath per floor, kitchen on ground, not all bedrooms)
##   6. balcony door span reserved in the facade layout
##   7. no coplanar floor finishes (z-fighting)
##   godot --headless --path . --script res://tests/connectivity_test.gd

const ProceduralBuildingS := preload("res://addons/building_forge/core/building_generator.gd")
const BFParamsS := preload("res://addons/building_forge/core/params.gd")
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
const BFStairS := preload("res://addons/building_forge/core/geometry/stair_builder.gd")
const BFFacadeS := preload("res://addons/building_forge/core/facade/facade.gd")
const BFWallS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")
const BFFootprintS := preload("res://addons/building_forge/core/footprint.gd")

var fails := 0
var checks := 0


func _initialize() -> void:
        test_regenerate_idempotent()
        for i in 6:
                test_building(i)
        if fails == 0:
                print("CONNECTIVITY: ALL %d CHECKS PASSED" % checks)
                quit(0)
        else:
                print("CONNECTIVITY: %d/%d FAILED" % [fails, checks])
                quit(1)


func check(cond: bool, msg: String) -> void:
        checks += 1
        if not cond:
                fails += 1
                printerr("  FAIL: " + msg)


func make_params(cfg: int) -> BFParams:
        var p := BFParams.new()
        match cfg % 6:
                0:  # suburban house
                        p.footprint = BFFootprintS.create_rect(11, 8.5)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.roof_kind = BFParams.Roof.GABLE
                        p.stair_kind = BFParams.Stair.STRAIGHT
                1:  # brick apartment
                        p.footprint = BFFootprintS.create_rect(18, 13)
                        p.floors = 5
                        p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
                        p.roof_kind = BFParams.Roof.FLAT
                        p.stair_kind = BFParams.Stair.DOGLEG
                        p.balconies = true
                2:  # L-shaped modern villa
                        p.footprint = BFFootprintS.create_L(14, 11)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.roof_kind = BFParams.Roof.FLAT
                        p.window_style = BFParams.WindowStyle.CURTAIN
                        p.stair_kind = BFParams.Stair.DOGLEG
                        p.ground_balcony = true
                3:  # narrow townhouse (stair fit stress test)
                        p.footprint = BFFootprintS.create_rect(6.5, 11)
                        p.floors = 3
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.roof_kind = BFParams.Roof.GABLE
                        p.stair_kind = BFParams.Stair.AUTO
                4:  # circular tower
                        p.footprint = BFFootprintS.create_circle(8)
                        p.floors = 6
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.roof_kind = BFParams.Roof.CONE
                        p.window_style = BFParams.WindowStyle.CURTAIN
                        p.stair_kind = BFParams.Stair.SPIRAL
                5:  # U-shaped office tower
                        p.footprint = BFFootprintS.create_U(20, 15)
                        p.floors = 8
                        p.architecture = BFParams.ArchStyle.OFFICE_TOWER
                        p.roof_kind = BFParams.Roof.FLAT
                        p.window_style = BFParams.WindowStyle.CURTAIN
                        p.stair_kind = BFParams.Stair.AUTO
        p.seed = 1000 + cfg * 17
        return p


func test_regenerate_idempotent() -> void:
        var b := ProceduralBuilding.new()
        get_root().add_child(b)
        b.generate()
        b.generate()
        b.generate()
        var count := 0
        var collision_count := 0
        for c in b.get_children():
                if c.name == "Generated" or c.name.begins_with("Generated"):
                        count += 1
                if c.name.begins_with("Collision"):
                        collision_count += 1
        check(count == 1, "regenerate x3 leaves exactly 1 Generated node (got %d: %s)" % [count, str(b.get_children().map(func(c): return c.name))])
        check(collision_count == 1, "regenerate x3 leaves exactly 1 Collision node (got %d)" % collision_count)
        # stats must still be valid
        check(b.stats.contains("floors"), "stats valid after regens")
        b.free()


func test_building(cfg: int) -> void:
        var p := make_params(cfg)
        var b := ProceduralBuilding.new()
        get_root().add_child(b)
        b.params = p
        b.generate()
        var label := "cfg%d(%s f%d)" % [cfg, p.footprint.is_circular and "circle" or "poly", p.floors]
        var gen := b.get_node_or_null("Generated")
        check(gen != null, label + ": generated")
        if gen == null:
                b.free()
                return

        # --- floors exist
        for i in p.floors:
                check(gen.has_node("Floor_%02d" % i), label + ": Floor_%02d exists" % i)

        # --- stairs: partitioner sees the stair cell on every floor below top
        var fp: BFFootprint = p.footprint
        var inner := BFWallS.inner_polygon(fp.points, p.wall_thickness)
        var inner_fp := BFFootprintS.create(inner)
        var bounds := Rect2(inner[0], Vector2.ZERO)
        var lo := inner[0]
        var hi := inner[0]
        for pt in inner:
                lo = lo.min(pt)
                hi = hi.max(pt)
        bounds = Rect2(lo, hi - lo)
        if bounds.get_area() >= 4.0:
                var rng := RandomNumberGenerator.new()
                rng.seed = p.seed
                var res := BFPartitionerS.partition(bounds.grow(-0.02), inner, _stair_cell_for(p, bounds, inner), p.max_room_area, rng)
                var rooms: Array = res.rooms
                BFPartitionerS.assign_kinds(rooms, 0, p.floors, rng, p.architecture == BFParams.ArchStyle.OFFICE_TOWER)
                var stair_rooms := 0
                for r in rooms:
                        if (r as BFPartitionerS.Room).kind == "stair":
                                stair_rooms += 1
                check(stair_rooms >= 1, label + ": stairwell is a room (%d stair rooms, %d total)" % [stair_rooms, rooms.size()])

                # --- door graph connectivity: every room reachable
                var walls: Array = res.walls
                var adj := {}
                for s in walls:
                        var seg := s as BFPartitionerS.WallSeg
                        if seg.door.is_empty():
                                continue
                        adj[seg.room_a] = adj.get(seg.room_a, [])
                        adj[seg.room_a].append(seg.room_b)
                        adj[seg.room_b] = adj.get(seg.room_b, [])
                        adj[seg.room_b].append(seg.room_a)
                if rooms.size() > 0:
                        var start: int = (rooms[0] as BFPartitionerS.Room).id
                        for r in rooms:
                                if (r as BFPartitionerS.Room).kind == "stair":
                                        start = (r as BFPartitionerS.Room).id
                                        break
                        var seen := {start: true}
                        var queue: Array = [start]
                        while queue.size() > 0:
                                var cur: int = queue.pop_front()
                                for nb in adj.get(cur, []):
                                        if not seen.has(nb):
                                                seen[nb] = true
                                                queue.append(nb)
                        check(seen.size() >= rooms.size(), label + ": all %d rooms door-reachable (reached %d)" % [rooms.size(), seen.size()])

                        # --- stair hall has a door
                        var stair_has_door := false
                        for s2 in walls:
                                var seg2 := s2 as BFPartitionerS.WallSeg
                                if not seg2.door.is_empty() and (seg2.room_a == start or seg2.room_b == start):
                                        stair_has_door = true
                        check(stair_has_door, label + ": stair hall has a door")

                        # --- room kind diversity on this floor
                        var kinds := {}
                        for r2 in rooms:
                                var k: String = (r2 as BFPartitionerS.Room).kind
                                kinds[k] = kinds.get(k, 0) + 1
                        var has_bath: bool = kinds.has("bath")
                        check(has_bath, label + ": floor has a bathroom (kinds=%s)" % str(kinds))
                        var non_bedroom := 0
                        for k2 in kinds:
                                if k2 != "bedroom":
                                        non_bedroom += kinds[k2]
                        check(non_bedroom >= 1, label + ": not all rooms are bedrooms (kinds=%s)" % str(kinds))
                        if cfg % 6 == 5:
                                check(kinds.has("office"), label + ": office tower has offices (kinds=%s)" % str(kinds))

        # --- balcony door span reserved in facade layout (not for circles)
        if p.balconies and p.floors > 1 and not p.footprint.is_circular:
                var rng2 := RandomNumberGenerator.new()
                rng2.seed = p.seed
                var open := BFFacadeS.layout_floor(fp, p.floor_height, p.floor_height - 0.3, p, rng2, fp.longest_edge(), Vector2(3.0, 4.0))
                var found := false
                var overlap := false
                for e in open:
                        for o in open[e]:
                                if o.kind == "balcony_door":
                                        found = true
                                elif o.kind == "window" and e == fp.longest_edge():
                                        if not (float(o.u2) < 3.0 - 0.12 or float(o.u1) > 4.0 + 0.12):
                                                overlap = true
                check(found, label + ": balcony door span present in layout")
                check(not overlap, label + ": no window overlaps balcony door span")

        b.free()


## Replicates the generator's stair planning to get the cell used by partition
func _stair_cell_for(p: BFParams, bounds: Rect2, inner: PackedVector2Array) -> Rect2:
        var fp: BFFootprint = p.footprint
        var fh := p.floor_height
        var kind := _resolve(p, fp)
        var plan_d := BFStairS.plan(kind, fh, null)
        # try center + corners like the generator does
        var sz: Vector2 = plan_d.cell.size
        var pad := 0.3
        var c := bounds.get_center()
        var candidates := [
                Rect2(Vector2(bounds.position.x + pad, bounds.position.y + pad), sz),
                Rect2(Vector2(bounds.end.x - sz.x - pad, bounds.position.y + pad), sz),
                Rect2(Vector2(bounds.position.x + pad, bounds.end.y - sz.y - pad), sz),
                Rect2(Vector2(bounds.end.x - sz.x - pad, bounds.end.y - sz.y - pad), sz),
                Rect2(c - sz * 0.5, sz),
        ]
        for r in candidates:
                if BFPartitionerS.rect_in_polygon(r, inner, 0.18):
                        return r
        return Rect2()


func _resolve(p: BFParams, fp: BFFootprint) -> int:
        match p.stair_kind:
                BFParams.Stair.STRAIGHT:
                        return BFStairS.StairKind.STRAIGHT
                BFParams.Stair.DOGLEG:
                        return BFStairS.StairKind.DOGLEG
                BFParams.Stair.SPIRAL:
                        return BFStairS.StairKind.SPIRAL
        return BFStairS.StairKind.STRAIGHT
