@tool
class_name ProceduralBuilding
extends Node3D
## BuildingForge main generator node. Add it to a scene, draw or pick a
## footprint, tweak parameters - the whole building regenerates live.
##
## Every generated node carries metadata (bf_part_id / bf_origin_transform).
## If you move a part manually, regeneration keeps your change (matched by
## part id). Use Finalize() to convert to a plain editable scene.

const BFWallBuilderS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")
const BFSlabBuilderS := preload("res://addons/building_forge/core/geometry/slab_builder.gd")
const BFRoofBuilderS := preload("res://addons/building_forge/core/geometry/roof_builder.gd")
const BFStairBuilderS := preload("res://addons/building_forge/core/geometry/stair_builder.gd")
const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")
const BFFacadeS := preload("res://addons/building_forge/core/facade/facade.gd")
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
const BFPropsS := preload("res://addons/building_forge/core/props/prop_factory.gd")
const BFMatLib := preload("res://addons/building_forge/core/materials/material_library.gd")

@export_group("Building")
@export var params: BFParams:
        set(v):
                if v == null:
                        v = BFParams.new()
                params = v
                if not v.changed.is_connected(_on_params_changed):
                        v.changed.connect(_on_params_changed)
                _regen()
## Rebuild everything (also available in the inspector via the dock).
@export var regenerate := false:
        set(v):
                regenerate = false
                _regen()
@export_group("Info")
@export var stats: String = ""

var _dirty := false
var _user_moves: Dictionary = {}    # part_id -> Transform3D (preserved across regen)
var _generating := false
## Debug/tooling: floor_index -> {rooms: Array[Room], walls: Array[WallSeg]}
## from the last generation (used by the interior tour renderer + tests).
var last_room_layout: Dictionary = {}


func _ready() -> void:
        if params == null:
                params = BFParams.new()
        # Always build on ready: in the editor (scene open) and at game runtime
        # (instanced scenes have owner set, so owner must not gate generation).
        _regen()


func _notification(what: int) -> void:
        if what == NOTIFICATION_EDITOR_PRE_SAVE:
                pass


func _on_params_changed() -> void:
        _regen()


func _regen() -> void:
        if _generating:
                _dirty = true
                return
        if not is_inside_tree():
                return
        _generating = true
        generate()
        _generating = false
        if _dirty:
                _dirty = false
                call_deferred("_regen")


## ------------------------------------------------------------------ build

func generate() -> void:
        var t0 := Time.get_ticks_usec()
        _collect_user_moves()
        # wipe old generation. Must be an IMMEDIATE free: queue_free() defers to
        # end of frame, so the new "Generated" child would collide with the
        # dying one and get renamed (@Generated@2) - the next regeneration
        # would then never find "Generated" again and buildings pile up.
        var old := get_node_or_null("Generated")
        if old != null:
                remove_child(old)
                old.free()
        var old_col := get_node_or_null("Collision")
        if old_col != null:
                remove_child(old_col)
                old_col.free()
        var root := Node3D.new()
        root.name = "Generated"
        add_child(root)
        if params == null:
                params = BFParams.new()
        var fp: BFFootprint = params.footprint
        if fp == null or fp.validate() != "":
                stats = "Invalid footprint: %s" % (fp.validate() if fp != null else "none")
                return
        var rng := RandomNumberGenerator.new()
        rng.seed = params.seed
        var style_dir: String = params.texture_style_dir
        var fh := params.floor_height
        var n_floors := params.floors
        var t := params.wall_thickness

        var inner := BFWallBuilderS.inner_polygon(fp.points, t)
        var inner_fp := BFFootprint.create(inner)
        var interior_bounds := _rect_of(inner_fp)

        # stair planning: polygon-aware, tries kind preferences, orientations
        # and refits - same shaft on every floor; may legitimately fail on
        # tiny footprints (then no stairs and NO slab hole are built)
        var stair := _plan_stairs(fp, inner, interior_bounds, fh, rng)
        var plan_d: Dictionary = stair.get("plan", {})
        var stair_cell: Rect2 = stair.get("cell", Rect2())
        var stair_flip: bool = stair.get("flip", false)
        var stair_hole: Rect2 = stair.get("hole", Rect2())

        var tri_count := 0
        for i in n_floors:
                var base := float(i) * fh
                var wall_h := fh - 0.3 if i > 0 else fh - 0.12
                var wall_base := base - 0.01
                var wall_h2 := wall_h + 0.02
                var floor_node := Node3D.new()
                floor_node.name = "Floor_%02d" % i
                root.add_child(floor_node)
                var m3d: MeshInstance3D = null
                var surfaces: Dictionary = {}   # mat_id -> SurfaceTool (merge mode)
                if params.merge_geometry:
                        m3d = MeshInstance3D.new()
                        m3d.name = "Shell"
                        floor_node.add_child(m3d)
                # balcony plan for this floor: edge + reserved door span so the
                # facade layout never punches a window over the balcony door
                var balcony_edge := -1
                var balcony_u := Vector2.ZERO
                var has_balcony := false
                if params.balconies and (i > 0 or params.ground_balcony) and i % params.balcony_every_n_floors == 0:
                        has_balcony = true
                if has_balcony:
                        balcony_edge = fp.longest_edge()
                        var elen := fp.edge_length(balcony_edge)
                        var bw := minf(3.2, elen * 0.5)
                        var door_w := minf(1.0, bw)
                        balcony_u = Vector2(elen * 0.5 - door_w * 0.5, elen * 0.5 + door_w * 0.5)
                var open := BFFacadeS.layout_floor(fp, base, wall_h, params, rng, balcony_edge, balcony_u)
                tri_count += _build_exterior(floor_node, surfaces, fp, wall_base, wall_h2, wall_h, t, open, rng,
                        balcony_edge, balcony_u, has_balcony)
                if params.generate_interior:
                        tri_count += _build_interior(floor_node, surfaces, fp, inner_fp, base, fh, wall_h, t,
                                stair_cell, stair_hole, plan_d, stair_flip, i, n_floors, rng)
                # slab above this floor (ceiling / next floor base)
                var slab_st := surfaces_for(surfaces, "concrete", style_dir)
                var slab_holes: Array = []
                if plan_d.size() > 0 and i < n_floors - 1:
                        slab_holes.append(stair_hole)
                BFSlabBuilderS.build_slab(slab_st, fp.points, base + fh - 0.301, base + fh, Rect2(), Vector2(0.5, 0.5), false, slab_holes)
                # thin sub-finish under interior walls; room finishes sit above
                # it (different Y) so nothing is coplanar (z-fighting fix)
                if i == 0 and params.generate_interior:
                        BFSlabBuilderS.build_slab(surfaces_for(surfaces, "wood_floor", style_dir), inner, base + 0.001, base + 0.011, Rect2(), Vector2(0.5, 0.5), true)
                _commit_surfaces(surfaces, floor_node, m3d, style_dir, "f%02d" % i)
                tri_count += 0
        # roof
        var roof_node := Node3D.new()
        roof_node.name = "Roof"
        root.add_child(roof_node)
        tri_count += _build_roof(roof_node, fp, float(n_floors) * fh, rng)
        _apply_user_moves(root)
        stats = "floors=%d  tris=%s  parts=%d  %.1f ms" % [
                n_floors, _fmt_int(_count_tris(root)), _count_parts(root), float(Time.get_ticks_usec() - t0) / 1000.0]
        if params.generate_collision:
                _build_collision(root)
        queue_redraw_gizmos()


func surfaces_for(surfaces: Dictionary, mat_id: String, _style: String) -> SurfaceTool:
        if not surfaces.has(mat_id):
                surfaces[mat_id] = BFMeshUtilS.new_st()
        return surfaces[mat_id]


func _build_exterior(floor_node: Node3D, surfaces: Dictionary, fp: BFFootprint, base: float,
        build_h: float, logic_h: float, t: float, openings: Dictionary, rng: RandomNumberGenerator,
        balcony_edge := -1, balcony_u := Vector2.ZERO, has_balcony := false) -> int:
        var p := params
        var style := p.texture_style_dir
        var st_wall := surfaces_for(surfaces, p.facade_material, style)
        var st_trim := surfaces_for(surfaces, "trim_white", style)
        var st_glass := surfaces_for(surfaces, "__glass", style)
        var st_door := surfaces_for(surfaces, "wood_dark", style)
        var st_concrete := surfaces_for(surfaces, "concrete", style)
        BFWallBuilderS.build_walls(st_wall, fp, base, build_h, t, _to_wall_openings(openings), Vector2(0.5, 0.5))
        # facade elements
        var n := fp.edge_count()
        var curtain := p.window_style == BFParams.WindowStyle.CURTAIN
        for e in n:
                if not openings.has(e):
                        continue
                var edge := fp.edge(e)
                var a: Vector2 = edge[0]
                var d: Vector2 = fp.edge_dir(e)
                for o in openings[e]:
                        var od: Dictionary = o
                        if od.kind == "door":
                                BFFacadeS.build_door(st_trim, st_door, a, d, od.u1, od.u2, od.v2, base, t, Vector2(0.5, 0.5))
                        elif od.kind == "balcony_door":
                                pass  # punched by the wall builder; dressed by _build_balcony
                        else:
                                BFFacadeS.build_window(st_trim, st_glass, a, d, od.u1, od.u2, od.v1, od.v2, base, t, p, Vector2(0.5, 0.5))
                                if curtain:
                                        BFFacadeS.build_mullions(st_trim, a, d, od.u1, od.u2, od.v1, od.v2, base, 1.35)
        # balcony (door span already reserved in the facade layout)
        if has_balcony:
                _build_balcony(floor_node, st_concrete, st_trim, st_glass, fp, base, t, rng, balcony_edge, balcony_u)
        return 0


func _build_balcony(floor_node: Node3D, st_conc: SurfaceTool, st_trim: SurfaceTool,
                st_glass: SurfaceTool, fp: BFFootprint, base: float, t: float, rng: RandomNumberGenerator,
                balcony_edge := -1, balcony_u := Vector2.ZERO) -> void:
        var e := balcony_edge if balcony_edge >= 0 else fp.longest_edge()
        var edge := fp.edge(e)
        var a: Vector2 = edge[0]
        var b: Vector2 = edge[1]
        var d := fp.edge_dir(e)
        var n_out := Vector2(d.y, -d.x)  # outward
        var elen := fp.edge_length(e)
        var bw := minf(3.2, elen * 0.5)
        var bd := 1.4
        var u1 := elen * 0.5 - bw * 0.5
        var c := a + d * (u1 + bw * 0.5)
        var dir_out3 := Vector3(n_out.x, 0, n_out.y)
        var basis := Basis(Vector3(d.x, 0, d.y), Vector3.UP, dir_out3)
        # slab
        var slab_xf := Transform3D(basis, Vector3(c.x + n_out.x * bd * 0.5, base + 0.06, c.y + n_out.y * bd * 0.5))
        BFMeshUtilS.add_box(st_conc, slab_xf, Vector3(bw, 0.12, bd), Vector2(0.5, 0.5))
        # railing on 3 open sides
        var y := base + 0.12
        var front_a := Vector3(c.x, y, c.y) + dir_out3 * bd + Vector3(d.x, 0, d.y) * (-bw * 0.5)
        var front_b := front_a + Vector3(d.x, 0, d.y) * bw
        BFMeshUtilS.add_railing(st_trim, front_a, front_b, y, 1.02, 0.05)
        BFMeshUtilS.add_railing(st_trim, Vector3(c.x, y, c.y) + d3(d) * (-bw * 0.5), front_a, y, 1.02, 0.05)
        BFMeshUtilS.add_railing(st_trim, Vector3(c.x, y, c.y) + d3(d) * bw * 0.5, front_b, y, 1.02, 0.05)
        # balcony door (glass) - uses the span reserved in the facade layout
        var door_w := (balcony_u.y - balcony_u.x) if balcony_u.y > balcony_u.x else minf(1.0, bw)
        var du1 := balcony_u.x if balcony_u.y > balcony_u.x else u1 + bw * 0.5 - door_w * 0.5
        BFFacadeS.build_door(st_trim, st_glass, a, d, du1, du1 + door_w, params.door_height, base, t, Vector2(0.5, 0.5), true)


func d3(v: Vector2) -> Vector3:
        return Vector3(v.x, 0, v.y)


func _build_interior(floor_node: Node3D, surfaces: Dictionary, fp: BFFootprint, inner_fp: BFFootprint,
                base: float, fh: float, wall_h: float, t: float, stair_cell: Rect2, stair_hole: Rect2,
                plan_d: Dictionary, stair_flip: bool, floor_i: int, n_floors: int, rng: RandomNumberGenerator) -> int:
        var p := params
        var style := p.texture_style_dir
        var st_int := surfaces_for(surfaces, p.interior_material, style)
        var st_trim := surfaces_for(surfaces, "trim_white", style)
        var st_wood := surfaces_for(surfaces, "wood_dark", style)
        var st_conc := surfaces_for(surfaces, "concrete", style)
        # partition rooms. NO pre-shrink: rooms extend to the inner face of the
        # exterior walls so windows / balcony doors open into rooms, and the
        # stairwell is a first-class room that doors always reach.
        var bounds := _rect_of(inner_fp).grow(-0.02)
        var rooms: Array = []
        var walls: Array = []
        if bounds.get_area() >= 4.0:
                var res := BFPartitionerS.partition(bounds, inner_fp.points, stair_cell, p.max_room_area, rng)
                rooms = res.rooms
                walls = res.walls
                BFPartitionerS.assign_kinds(rooms, floor_i, n_floors, rng,
                        p.architecture == BFParams.ArchStyle.OFFICE_TOWER)
        last_room_layout[floor_i] = {"rooms": rooms, "walls": walls}
        var finish_top := 0.024  # room finish top; walls start here (z-fight fix)
        # interior walls + doors
        for seg in walls:
                var s := seg as BFPartitionerS.WallSeg
                var d := s.b - s.a
                var l := d.length()
                if l < 0.3:
                        continue
                d /= l
                var mid := (s.a + s.b) * 0.5
                var basis := Basis(Vector3(d.x, 0, d.y), Vector3.UP, Vector3(-d.y, 0, d.x))
                if s.door.is_empty():
                        var xf := Transform3D(basis, Vector3(mid.x, base + finish_top + wall_h * 0.5, mid.y))
                        BFMeshUtilS.add_box(st_int, xf, Vector3(l, wall_h, BFPartitionerS.INT_WALL_T), Vector2(0.5, 0.5))
                else:
                        var da: Vector2 = s.door.a
                        var db: Vector2 = s.door.b
                        var dl := da.distance_to(s.a)
                        var dr := s.b.distance_to(db)
                        var dh: float = minf(2.08, wall_h - 0.15)
                        if dl > 0.05:
                                var m1 := (s.a + da) * 0.5
                                BFMeshUtilS.add_box(st_int, Transform3D(basis, Vector3(m1.x, base + finish_top + wall_h * 0.5, m1.y)), Vector3(dl, wall_h, BFPartitionerS.INT_WALL_T), Vector2(0.5, 0.5))
                        if dr > 0.05:
                                var m2 := (db + s.b) * 0.5
                                BFMeshUtilS.add_box(st_int, Transform3D(basis, Vector3(m2.x, base + finish_top + wall_h * 0.5, m2.y)), Vector3(dr, wall_h, BFPartitionerS.INT_WALL_T), Vector2(0.5, 0.5))
                        # above-door lintel piece
                        var mc := (da + db) * 0.5
                        var lintel_h := wall_h - dh
                        if lintel_h > 0.05:
                                BFMeshUtilS.add_box(st_int, Transform3D(basis, Vector3(mc.x, base + finish_top + dh + lintel_h * 0.5, mc.y)), Vector3(da.distance_to(db), lintel_h, BFPartitionerS.INT_WALL_T), Vector2(0.5, 0.5))
                        # door frame + panel (closed, centered)
                        var dw := da.distance_to(db)
                        var bdoor := Basis(Vector3(-d.y, 0, d.x), Vector3.UP, Vector3(d.x, 0, d.y))
                        var dxf := Transform3D(bdoor, Vector3(mc.x, base + dh * 0.5, mc.y))
                        BFMeshUtilS.add_box(st_trim, dxf, Vector3(dw + 0.08, 0.06, 0.16), Vector2(0.5, 0.5))
                        BFMeshUtilS.add_box(st_trim, dxf * Transform3D(Basis.IDENTITY, Vector3(-(dw * 0.5 + 0.04), 0, 0)), Vector3(0.06, dh, 0.16), Vector2(0.5, 0.5))
                        BFMeshUtilS.add_box(st_trim, dxf * Transform3D(Basis.IDENTITY, Vector3(dw * 0.5 + 0.04, 0, 0)), Vector3(0.06, dh, 0.16), Vector2(0.5, 0.5))
                        BFMeshUtilS.add_box(st_wood, dxf, Vector3(0.04, dh - 0.06, dw - 0.02), Vector2(0.5, 0.5))
        # room floor finishes + props
        var st_fin_wood := surfaces_for(surfaces, "wood_floor", style)
        var st_fin_tile := surfaces_for(surfaces, "tile_floor", style)
        var st_fin_carpet := surfaces_for(surfaces, "carpet", style)
        var prop_sts := _prop_sts(surfaces, style)
        for r in rooms:
                var room := r as BFPartitionerS.Room
                var rect := room.rect.grow(-0.04)
                if rect.get_area() < 1.0:
                        continue
                match room.kind:
                        "bath", "kitchen", "storage":
                                BFSlabBuilderS.build_floor_finish(st_fin_tile, rect, base + finish_top)
                        "bedroom":
                                BFSlabBuilderS.build_floor_finish(st_fin_carpet, rect, base + finish_top)
                        _:
                                BFSlabBuilderS.build_floor_finish(st_fin_wood, rect, base + finish_top)
                if p.generate_props:
                        var doors := BFPartitionerS.room_doors(room, walls)
                        var placements := BFPropsS.layout_room(room.kind, rect, doors, base + finish_top, rng)
                        var pi := 0
                        for pl in placements:
                                _build_prop(floor_node, prop_sts, pl, floor_i, room.id, base, style, pi)
                                pi += 1
        # stairs to next floor: only when a fit was planned and this is not the
        # top floor (stairs into a solid ceiling are a classic generator bug)
        if plan_d.size() > 0 and floor_i < n_floors - 1:
                var stair_node := Node3D.new()
                stair_node.name = "Stairs"
                floor_node.add_child(stair_node)
                var st_stair := surfaces_for(surfaces, "concrete", style)
                var st_wood2 := surfaces_for(surfaces, "wood_dark", style)
                BFStairBuilderS.build(st_stair, st_wood2, plan_d, stair_cell, fh, base, rng, Vector2(0.5, 0.5), stair_flip)
        return 0


## Polygon-aware stair planning: tries the preferred kind first, then
## fallbacks; each kind is tried un-rotated and 90deg-rotated over a grid of
## positions inside the interior polygon; refits (compresses treads / spiral
## radius) before giving up. Returns {plan, cell, flip, hole} or {}.
func _plan_stairs(fp: BFFootprint, inner: PackedVector2Array, interior_bounds: Rect2, fh: float, rng: RandomNumberGenerator) -> Dictionary:
        var order: Array = []
        match params.stair_kind:
                BFParams.Stair.STRAIGHT:
                        order = [BFStairBuilderS.StairKind.STRAIGHT]
                BFParams.Stair.DOGLEG:
                        order = [BFStairBuilderS.StairKind.DOGLEG]
                BFParams.Stair.SPIRAL:
                        order = [BFStairBuilderS.StairKind.SPIRAL]
                _:
                        var pref := _resolve_stair_kind(fp, params.floors)
                        if pref == BFStairBuilderS.StairKind.SPIRAL:
                                order = [BFStairBuilderS.StairKind.SPIRAL, BFStairBuilderS.StairKind.DOGLEG, BFStairBuilderS.StairKind.STRAIGHT]
                        elif pref == BFStairBuilderS.StairKind.STRAIGHT:
                                order = [BFStairBuilderS.StairKind.STRAIGHT, BFStairBuilderS.StairKind.DOGLEG, BFStairBuilderS.StairKind.SPIRAL]
                        else:
                                order = [BFStairBuilderS.StairKind.DOGLEG, BFStairBuilderS.StairKind.STRAIGHT, BFStairBuilderS.StairKind.SPIRAL]
        for kind in order:
                var plan_d := BFStairBuilderS.plan(kind, fh, rng)
                var fit := _fit_stair(plan_d, inner, interior_bounds)
                if not fit.is_empty():
                        return fit
        print("[BuildingForge] footprint too small for any staircase; building will have no stairs")
        return {}


func _fit_stair(plan_d: Dictionary, inner: PackedVector2Array, interior_bounds: Rect2) -> Dictionary:
        var cell0: Rect2 = plan_d.cell
        var scales := [1.0, 0.9, 0.8, 0.7]
        for sc in scales:
                var pd := plan_d
                if sc < 1.0:
                        pd = BFStairBuilderS.refit(plan_d, cell0.size * sc)
                        if pd.is_empty():
                                continue
                for flip in [false, true]:
                        var sz: Vector2 = Vector2(pd.cell.size.y, pd.cell.size.x) if flip else pd.cell.size
                        var world_cell := _stair_search_cell(sz, inner, interior_bounds)
                        if world_cell.get_area() > 0.0:
                                var hole := BFStairBuilderS.hole_world(pd, world_cell, flip)
                                return {"plan": pd, "cell": world_cell, "flip": flip, "hole": hole}
        return {}


## Deterministic position search: corners -> center -> edge midpoints ->
## grid. Returns the first rect that fits the polygon (with clearance),
## else Rect2().
func _stair_search_cell(sz: Vector2, inner: PackedVector2Array, bounds: Rect2) -> Rect2:
        var pad := 0.3
        var c := bounds.get_center()
        var candidates: Array = [
                Vector2(bounds.position.x + pad, bounds.position.y + pad),
                Vector2(bounds.end.x - sz.x - pad, bounds.position.y + pad),
                Vector2(bounds.position.x + pad, bounds.end.y - sz.y - pad),
                Vector2(bounds.end.x - sz.x - pad, bounds.end.y - sz.y - pad),
                c - sz * 0.5,
                Vector2(c.x - sz.x * 0.5, bounds.position.y + pad),
                Vector2(c.x - sz.x * 0.5, bounds.end.y - sz.y - pad),
                Vector2(bounds.position.x + pad, c.y - sz.y * 0.5),
                Vector2(bounds.end.x - sz.x - pad, c.y - sz.y * 0.5),
        ]
        var gx := maxi(1, int((bounds.size.x - sz.x - 2.0 * pad) / 0.7))
        var gy := maxi(1, int((bounds.size.y - sz.y - 2.0 * pad) / 0.7))
        for iy in gy + 1:
                for ix in gx + 1:
                        candidates.append(Vector2(
                                bounds.position.x + pad + minf(ix * 0.7, bounds.size.x - sz.x - 2.0 * pad),
                                bounds.position.y + pad + minf(iy * 0.7, bounds.size.y - sz.y - 2.0 * pad)))
        for pos in candidates:
                var r := Rect2(pos, sz)
                if r.position.x < bounds.position.x - 0.01 or r.position.y < bounds.position.y - 0.01:
                        continue
                if r.end.x > bounds.end.x + 0.01 or r.end.y > bounds.end.y + 0.01:
                        continue
                if BFPartitionerS.rect_in_polygon(r, inner, 0.18):
                        return r
        return Rect2()


func _prop_sts(surfaces: Dictionary, style: String) -> Dictionary:
        var ids := ["wood_dark", "wood_light", "fabric_bed", "fabric_sofa", "appliance", "metal", "metal_dark", "porcelain", "glass", "glass_dark", "carpet", "stone", "brick_red", "tile_floor"]
        var out := {}
        for id in ids:
                out[id] = surfaces_for(surfaces, id, style)
        return out


func _build_prop(floor_node: Node3D, prop_sts: Dictionary, pl: Dictionary, floor_i: int, room_id: int, base: float, style: String, prop_i: int) -> void:
    var id: String = pl.id
    if not BFPropsS.has_prop(id):
        return
    var node := Node3D.new()
    node.name = "Prop_%s_f%02d_r%d_%d" % [id, floor_i, room_id, prop_i]
    node.transform = Transform3D(Basis(Vector3.UP, pl.rot_y), pl.pos)
    floor_node.add_child(node)
    var sts := {}
    for k in prop_sts:
        sts[k] = BFMeshUtilS.new_st()
    var prng := RandomNumberGenerator.new()
    prng.seed = hash("%s|%d|%d|%d" % [id, floor_i, room_id, prop_i])
    var aabb := BFPropsS.build(id, sts, prng)
    if aabb.size == Vector3.ZERO:
        node.queue_free()
        return
    var mesh := ArrayMesh.new()
    for k in sts:
        var m: Mesh = BFMeshUtilS.commit(sts[k])
        if m == null:
            continue
        var start := mesh.get_surface_count()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
        mesh.surface_set_material(start, BFMatLib.get_material(k, style))
    if mesh.get_surface_count() == 0:
        node.queue_free()
        return
    var mi := MeshInstance3D.new()
    mi.name = "Mesh"
    mi.mesh = mesh
    _set_part_meta(mi, "prop|%s|%d|%d|%s" % [id, floor_i, room_id, node.name])
    node.add_child(mi)


func _build_roof(roof_node: Node3D, fp: BFFootprint, base: float, rng: RandomNumberGenerator) -> int:
        var p := params
        var style := p.texture_style_dir
        var st_roof := BFMeshUtilS.new_st()
        var st_trim := BFMeshUtilS.new_st()
        var st_conc := BFMeshUtilS.new_st()
        var st_metal := BFMeshUtilS.new_st()
        var kind := p.roof_kind
        if fp.is_circular and (kind == BFParams.Roof.GABLE or kind == BFParams.Roof.HIP):
                kind = BFParams.Roof.CONE
        var roof_params := {"overhang": p.roof_overhang, "pitch": p.roof_pitch, "tile": Vector2(0.5, 0.5), "parapet_h": 0.55}
        BFRoofBuilderS.build_roof(kind, st_roof, st_trim, fp, base, roof_params)
        # rooftop extras for flat roofs
        if kind == BFParams.Roof.FLAT and p.rooftop_equipment and fp.area() > 30.0:
                var inner := fp.inset(0.8)
                if inner.size() >= 3:
                        var c := fp.center_xz()
                        var bx := Transform3D(Basis.IDENTITY, Vector3(c.x + 1.5, base + 0.35, c.y - 1.0))
                        BFMeshUtilS.add_box(st_metal, bx, Vector3(1.4, 0.7, 1.0), Vector2(0.5, 0.5))
                        var bx2 := Transform3D(Basis.IDENTITY, Vector3(c.x - 1.2, base + 0.3, c.y + 1.4))
                        BFMeshUtilS.add_box(st_metal, bx2, Vector3(1.0, 0.6, 0.8), Vector2(0.5, 0.5))
        if kind == BFParams.Roof.FLAT and p.roof_railing:
                var outer := fp.outset(0.05)
                var n := outer.size()
                var rail_base := base + 0.05  # deck top (was floating 0.55 m above it)
                for i in n:
                        var a: Vector2 = outer[i]
                        var b: Vector2 = outer[(i + 1) % n]
                        BFMeshUtilS.add_railing(st_metal, Vector3(a.x, rail_base, a.y), Vector3(b.x, rail_base, b.y), rail_base, 0.5, 0.04)
        _commit_mesh(roof_node, st_roof, BFMatLib.get_material(_roof_mat(), style), "Roof_Surface")
        _commit_mesh(roof_node, st_trim, BFMatLib.get_material("trim_white", style), "Roof_Trim")
        _commit_mesh(roof_node, st_conc, BFMatLib.get_material("concrete", style), "Roof_Concrete")
        _commit_mesh(roof_node, st_metal, BFMatLib.get_material("metal_dark", style), "Roof_Metal")
        return 0


func _roof_mat() -> String:
        match params.roof_kind:
                BFParams.Roof.GABLE, BFParams.Roof.HIP:
                        return "roof_shingle" if params.architecture == BFParams.ArchStyle.CLASSIC_HOUSE else "roof_tile"
                BFParams.Roof.CONE:
                        return "roof_tile"
                _:
                        return "asphalt"


func _resolve_stair_kind(fp: BFFootprint, n_floors: int) -> int:
        match params.stair_kind:
                BFParams.Stair.STRAIGHT:
                        return BFStairBuilderS.StairKind.STRAIGHT
                BFParams.Stair.DOGLEG:
                        return BFStairBuilderS.StairKind.DOGLEG
                BFParams.Stair.SPIRAL:
                        return BFStairBuilderS.StairKind.SPIRAL
                _:
                        if fp.is_circular or n_floors >= 8:
                                return BFStairBuilderS.StairKind.SPIRAL
                        var inner := BFWallBuilderS.inner_polygon(fp.points, params.wall_thickness)
                        var sz := _rect_of(BFFootprint.create(inner))
                        if sz.size.x > 6.0 and sz.size.y > 6.0:
                                return BFStairBuilderS.StairKind.STRAIGHT
                        return BFStairBuilderS.StairKind.DOGLEG


func _to_wall_openings(openings: Dictionary) -> Dictionary:
        var out := {}
        for e in openings:
                var list: Array = []
                for o in openings[e]:
                        list.append(BFWallBuilderS.make_opening(o.u1, o.u2, o.v1, o.v2))
                out[e] = list
        return out


func _commit_surfaces(surfaces: Dictionary, floor_node: Node3D, m3d: MeshInstance3D, style: String, id_prefix: String) -> void:
        if m3d != null:
                var mesh := ArrayMesh.new()
                var idx := 0
                for mat_id in surfaces:
                        var m: Mesh = BFMeshUtilS.commit(surfaces[mat_id])
                        if m == null:
                                continue
                        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
                        mesh.surface_set_material(idx, BFMatLib.get_material(mat_id, style))
                        idx += 1
                if idx > 0:
                        m3d.mesh = mesh
                        _set_part_meta(m3d, id_prefix + "|merged")
                return
        var i := 0
        for mat_id in surfaces:
                var m: Mesh = BFMeshUtilS.commit(surfaces[mat_id])
                if m == null:
                        continue
                var mi := MeshInstance3D.new()
                mi.name = "%s_%02d_%s" % [id_prefix, i, mat_id]
                mi.mesh = m
                mi.mesh.surface_set_material(0, BFMatLib.get_material(mat_id, style))
                floor_node.add_child(mi)
                _set_part_meta(mi, "%s|%s|%d" % [id_prefix, mat_id, i])
                i += 1


func _commit_mesh(parent: Node3D, st: SurfaceTool, mat: Material, name: String) -> void:
        var m: Mesh = BFMeshUtilS.commit(st)
        if m == null:
                return
        var mi := MeshInstance3D.new()
        mi.name = name
        mi.mesh = m
        mi.mesh.surface_set_material(0, mat)
        parent.add_child(mi)
        _set_part_meta(mi, "roof|" + name)


func _set_part_meta(mi: MeshInstance3D, id: String) -> void:
        mi.set_meta("bf_part_id", id)
        mi.set_meta("bf_origin_transform", mi.transform)


func _collect_user_moves() -> void:
        # keep transforms of parts the user moved (origin changed vs stored)
        var old := get_node_or_null("Generated")
        if old == null:
                return
        for mi in old.find_children("*", "MeshInstance3D", true, false):
                if not (mi as MeshInstance3D).has_meta("bf_part_id"):
                        continue
                var stored: Transform3D = (mi as MeshInstance3D).get_meta("bf_origin_transform")
                var now: Transform3D = (mi as MeshInstance3D).transform
                if not now.origin.is_equal_approx(stored.origin) or not now.basis.is_equal_approx(stored.basis):
                        _user_moves[(mi as MeshInstance3D).get_meta("bf_part_id")] = now


func _apply_user_moves(root: Node3D) -> void:
        if _user_moves.is_empty():
                return
        for mi in root.find_children("*", "MeshInstance3D", true, false):
                var pid = (mi as MeshInstance3D).get_meta("bf_part_id", null)
                if pid != null and _user_moves.has(pid):
                        (mi as MeshInstance3D).transform = _user_moves[pid]
                        (mi as MeshInstance3D).set_meta("bf_origin_transform", _user_moves[pid])


func _build_collision(root: Node3D) -> void:
        var old_col := get_node_or_null("Collision")
        if old_col != null:
                old_col.queue_free()
        var body := StaticBody3D.new()
        body.name = "Collision"
        add_child(body)
        for floor_node in root.get_children():
                for mi in (floor_node as Node3D).find_children("*", "MeshInstance3D", true, false):
                        var mesh: Mesh = (mi as MeshInstance3D).mesh
                        if mesh == null:
                                continue
                        # skip tiny decorative + glass surfaces
                        if (mi as MeshInstance3D).name.begins_with("Roof_Trim") or (mi as MeshInstance3D).name.contains("glass"):
                                continue
                        var shape := mesh.create_trimesh_shape()
                        if shape == null:
                                continue
                        var cs := CollisionShape3D.new()
                        cs.shape = shape
                        cs.transform = (mi as MeshInstance3D).transform
                        body.add_child(cs)


func _rect_of(fp: BFFootprint) -> Rect2:
        if fp.points.is_empty():
                return Rect2()
        var lo := fp.points[0]
        var hi := fp.points[0]
        for p in fp.points:
                lo = lo.min(p)
                hi = hi.max(p)
        return Rect2(lo, hi - lo)


func _fmt_int(v: int) -> String:
        var s := str(v)
        var out := ""
        while s.length() > 3:
                out = "_" + s.substr(s.length() - 3) + out
                s = s.substr(0, s.length() - 3)
        return s + out


func _count_parts(root: Node3D) -> int:
        return root.find_children("*", "MeshInstance3D", true, false).size()




func _count_tris(root: Node3D) -> int:
    var n := 0
    for mi in root.find_children("*", "MeshInstance3D", true, false):
        var mesh: Mesh = (mi as MeshInstance3D).mesh
        if mesh == null:
            continue
        for s2 in mesh.get_surface_count():
            var arrays := mesh.surface_get_arrays(s2)
            var idx2: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            n += idx2.size() / 3 if idx2.size() > 0 else 0
    return n
func queue_redraw_gizmos() -> void:
        update_gizmos()


## Converts the generated building into plain, fully editable nodes
## (removes the generator behaviour). Non-destructive to geometry.
func finalize() -> Node3D:
        var gen := get_node_or_null("Generated")
        if gen == null:
                generate()
                gen = get_node_or_null("Generated")
        var parent := get_parent()
        if parent == null:
                return null
        var idx := get_index()
        var standalone := Node3D.new()
        standalone.name = name + "_Finalized"
        standalone.transform = transform
        parent.add_child(standalone)
        parent.move_child(standalone, idx)
        for child in gen.get_children():
                (child as Node).reparent(standalone, is_inside_tree())
        # bake generator transform into children
        for c in standalone.find_children("*", "MeshInstance3D", true, false):
                (c as MeshInstance3D).transform = standalone.transform.affine_inverse() * (c as MeshInstance3D).transform
        standalone.transform = Transform3D()
        return standalone
