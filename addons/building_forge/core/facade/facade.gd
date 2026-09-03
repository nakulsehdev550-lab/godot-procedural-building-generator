@tool
class_name BFFacade
extends RefCounted
## Facade layout + window/door mesh construction.
##
## Layout: per polygon edge, compute opening rectangles (u along edge, v
## vertical) for windows and doors, respecting spacing, margins and corners.
## Meshes: window frames + glass + sills, door frames + panels, curtain-wall
## mullions. All built from BFMeshUtil boxes so they stay lightweight.

const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")
const BFWallBuilderS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")


## Computes all exterior openings for one floor.
## balcony_edge / balcony_u: when a balcony is built on this floor, the door
## span on that edge is reserved here (no window overlaps it; the wall gets a
## full-height "balcony_door" opening that _build_balcony dresses later).
## Returns Dictionary { edge_index: Array[Dictionary] }
## each: {u1,u2,v1,v2, kind:"window"/"door"/"balcony_door", edge:int}
static func layout_floor(fp: BFFootprint, base_y: float, wall_h: float, p: BFParams, rng: RandomNumberGenerator,
                balcony_edge := -1, balcony_u := Vector2.ZERO) -> Dictionary:
        var openings := {}
        var entrance_edge := _pick_entrance_edge(fp)
        var skip_entrance := not _has_entrance(fp, base_y)
        for e in fp.edge_count():
                var is_balcony_edge := e == balcony_edge and balcony_u.y > balcony_u.x
                var list: Array = []
                var elen := fp.edge_length(e)
                # circular footprints: tessellated edges are short -> one window per
                # edge, sized to the edge (curtain style falls back to punched)
                if fp.is_circular:
                        # tessellated edges vary in length -> use a FIXED window
                        # size at even arc spacing so the band reads consistent
                        var ww := minf(p.window_width, 1.6)
                        var v1c := p.window_sill
                        var v2c := minf(p.window_sill + p.window_height, wall_h - 0.18)
                        if v2c - v1c >= 0.4 and elen >= ww + 0.7:
                                var spacing := maxf(ww + 1.1, 2.2)
                                var n_c := maxi(1, int(round(elen / spacing)))
                                for k in n_c:
                                        var cu := elen * (float(k) + 0.5) / float(n_c)
                                        list.append({"u1": cu - ww * 0.5, "u2": cu + ww * 0.5, "v1": v1c, "v2": v2c, "kind": "window"})
                        if is_balcony_edge:
                                pass  # no balconies on circular footprints
                        elif e == entrance_edge and not skip_entrance:
                                list.clear()
                                var dw2 := p.door_width
                                list.append({"u1": elen * 0.5 - dw2 * 0.5, "u2": elen * 0.5 + dw2 * 0.5, "v1": 0.0, "v2": p.door_height, "kind": "door"})
                        if not list.is_empty():
                                openings[e] = list
                        continue
                match p.window_style:
                        BFParams.WindowStyle.CURTAIN:
                                list = _layout_curtain(elen, wall_h, p, e == entrance_edge and not skip_entrance)
                        BFParams.WindowStyle.TALL:
                                list = _layout_tall(elen, wall_h, p)
                        _:
                                list = _layout_punched(elen, wall_h, p, rng)
                if is_balcony_edge:
                        # drop windows overlapping the balcony door span, reserve the door
                        var kept: Array = []
                        for o in list:
                                if float(o.u2) < balcony_u.x - 0.12 or float(o.u1) > balcony_u.y + 0.12:
                                        kept.append(o)
                        list = kept
                        list.append({"u1": balcony_u.x, "u2": balcony_u.y, "v1": 0.0, "v2": p.door_height, "kind": "balcony_door", "edge": e})
                if e == entrance_edge and not skip_entrance:
                        var dw := p.door_width
                        var u0 := elen * 0.5 - dw * 0.5
                        # avoid overlap with existing openings: clear a window if needed
                        var cleaned: Array = []
                        for o in list:
                                if float(o.u2) < u0 - 0.1 or float(o.u1) > u0 + dw + 0.1:
                                        cleaned.append(o)
                        list = cleaned
                        list.append({
                                "u1": u0, "u2": u0 + dw, "v1": 0.0, "v2": p.door_height,
                                "kind": "door", "edge": e,
                        })
                if not list.is_empty():
                        openings[e] = list
        return openings


static func _has_entrance(fp: BFFootprint, base_y: float) -> bool:
        return base_y < 0.01  # ground floor only


static func _pick_entrance_edge(fp: BFFootprint) -> int:
        # longest edge (stable, no rng: entrance stays put when tweaking)
        return fp.longest_edge()


static func _layout_punched(elen: float, wall_h: float, p: BFParams, rng: RandomNumberGenerator) -> Array:
        var out: Array = []
        var w := p.window_width
        var v1 := p.window_sill
        var v2 := minf(p.window_sill + p.window_height, wall_h - 0.18)
        if v2 - v1 < 0.4 or elen < w + 1.2:
                return out
        var step := p.window_spacing
        var usable := elen - 2.0 * 0.8
        var n := int(floor((usable + (step - w)) / step))
        if n <= 0:
                n = 1
        var span := n * w + (n - 1) * (step - w)
        var start := (elen - span) * 0.5
        for i in n:
                var u1 := start + float(i) * step
                if u1 + w <= elen - 0.6:
                        out.append({"u1": u1, "u2": u1 + w, "v1": v1, "v2": v2, "kind": "window"})
        return out


static func _layout_tall(elen: float, wall_h: float, p: BFParams) -> Array:
        var out: Array = []
        var w := p.window_width * 0.8
        var v1 := 0.35
        var v2 := wall_h - 0.35
        if v2 - v1 < 0.8 or elen < w + 1.2:
                return out
        var step := maxf(p.window_spacing * 0.85, w + 0.7)
        var usable := elen - 1.6
        var n := maxi(1, int(floor((usable + (step - w)) / step)))
        var span := n * w + (n - 1) * (step - w)
        var start := (elen - span) * 0.5
        for i in n:
                var u1 := start + float(i) * step
                if u1 + w <= elen - 0.6:
                        out.append({"u1": u1, "u2": u1 + w, "v1": v1, "v2": v2, "kind": "window"})
        return out


## Curtain wall: full-width glass band with mullion slots, door gap on
## the entrance edge.
static func _layout_curtain(elen: float, wall_h: float, p: BFParams, entrance: bool) -> Array:
        var out: Array = []
        var v1 := 0.35
        var v2 := wall_h - 0.4
        if v2 - v1 < 0.6 or elen < 2.0:
                return out
        var dw := p.door_width + 0.2
        if entrance and elen > dw + 2.0:
                var u0 := elen * 0.5 - dw * 0.5
                if u0 > 0.4:
                        out.append({"u1": 0.25, "u2": u0, "v1": v1, "v2": v2, "kind": "window"})
                if elen - (u0 + dw) > 0.4:
                        out.append({"u1": u0 + dw, "u2": elen - 0.25, "v1": v1, "v2": v2, "kind": "window"})
                out.append({"u1": u0 + 0.1, "u2": u0 + dw - 0.1, "v1": 0.0, "v2": p.door_height, "kind": "door"})
        else:
                out.append({"u1": 0.25, "u2": elen - 0.25, "v1": v1, "v2": v2, "kind": "window"})
        return out


## Adds a window assembly (frame + glass + optional sill) into an opening.
## Geometry in building-local coords.
static func build_window(st_frame: SurfaceTool, st_glass: SurfaceTool, edge_a: Vector2, edge_dir: Vector2,
                u1: float, u2: float, v1: float, v2: float, base_y: float, thickness: float,
                p: BFParams, tile: Vector2) -> void:
        var w := u2 - u1
        var h := v2 - v1
        var c := edge_a + edge_dir * (u1 + w * 0.5)
        var outward := Vector3(edge_dir.y, 0, -edge_dir.x)
        var basis := Basis(edge_dir_3(edge_dir), Vector3.UP, outward)
        var frame_t := 0.055
        var depth := thickness + 0.06
        # glass pane centered in wall depth
        var glass_t := Transform3D(basis, Vector3(c.x, base_y + v1 + h * 0.5, c.y))
        BFMeshUtilS.add_box(st_glass, glass_t, Vector3(w - frame_t * 1.4, h - frame_t * 1.4, 0.02), tile)
        if p.window_frames:
                var fxf := Transform3D(basis, Vector3(c.x, base_y + v1 + h * 0.5, c.y))
                # 4 frame members
                BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5 - frame_t * 0.5, 0)), Vector3(w, frame_t, depth * 0.55), tile)
                BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(0, -h * 0.5 + frame_t * 0.5, 0)), Vector3(w, frame_t, depth * 0.55), tile)
                BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + frame_t * 0.5, 0, 0)), Vector3(frame_t, h, depth * 0.55), tile)
                BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - frame_t * 0.5, 0, 0)), Vector3(frame_t, h, depth * 0.55), tile)
                # mullion cross bars for wide windows
                if w > 1.6:
                        BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(0.04, h - frame_t, depth * 0.4), tile)
                if h > 1.6:
                        BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(w - frame_t, 0.04, depth * 0.4), tile)
        if p.window_sills:
                var sxf := Transform3D(basis, Vector3(c.x, base_y + v1 - 0.03, c.y) + outward * (thickness * 0.5 + 0.04))
                BFMeshUtilS.add_box(st_frame, sxf, Vector3(w + 0.16, 0.06, 0.16), tile)


static func build_door(st_frame: SurfaceTool, st_panel: SurfaceTool, edge_a: Vector2, edge_dir: Vector2,
                u1: float, u2: float, v2: float, base_y: float, thickness: float, tile: Vector2, glass_door := false) -> void:
        var w := u2 - u1
        var h := v2
        var c := edge_a + edge_dir * (u1 + w * 0.5)
        var outward := Vector3(edge_dir.y, 0, -edge_dir.x)
        var basis := Basis(edge_dir_3(edge_dir), Vector3.UP, outward)
        var frame_t := 0.06
        var fxf := Transform3D(basis, Vector3(c.x, base_y + h * 0.5, c.y))
        BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5 - frame_t * 0.5, 0)), Vector3(w + frame_t * 2, frame_t, thickness + 0.05), tile)
        BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 - frame_t * 0.5, 0, 0)), Vector3(frame_t, h, thickness + 0.05), tile)
        BFMeshUtilS.add_box(st_frame, fxf * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 + frame_t * 0.5, 0, 0)), Vector3(frame_t, h, thickness + 0.05), tile)
        # door panel (slightly ajar look: rotate 8 degrees? keep closed & simple)
        var panel := Transform3D(basis, Vector3(c.x, base_y + h * 0.5 - 0.02, c.y))
        BFMeshUtilS.add_box(st_panel, panel, Vector3(w - 0.02, h - 0.04, 0.05), tile)
        # handle
        var hx := Transform3D(basis, fxf.origin + basis * Vector3(w * 0.5 - 0.1, -0.06, thickness * 0.5 + 0.04))
        BFMeshUtilS.add_box(st_frame, hx, Vector3(0.03, 0.14, 0.03), tile)
        if glass_door:
                var gt := Transform3D(basis, Vector3(c.x, base_y + h * 0.55, c.y))
                BFMeshUtilS.add_box(st_panel, gt, Vector3(w - 0.06, h * 0.7, 0.015), tile)


static func edge_dir_3(d2: Vector2) -> Vector3:
        return Vector3(d2.x, 0, d2.y)


## Builds curtain-wall mullions over a window band (modern look).
static func build_mullions(st_frame: SurfaceTool, edge_a: Vector2, edge_dir: Vector2,
                u1: float, u2: float, v1: float, v2: float, base_y: float, spacing := 1.4) -> void:
        var w := u2 - u1
        var h := v2 - v1
        var n := maxi(0, int(w / spacing))
        var outward := Vector3(edge_dir.y, 0, -edge_dir.x)
        var basis := Basis(edge_dir_3(edge_dir), Vector3.UP, outward)
        for i in range(1, n + 1):
                var uu := u1 + w * float(i) / float(n + 1)
                var c := edge_a + edge_dir * uu
                var xf := Transform3D(basis, Vector3(c.x, base_y + v1 + h * 0.5, c.y))
                BFMeshUtilS.add_box(st_frame, xf, Vector3(0.05, h, 0.09), Vector2(0.5, 0.5))
        # horizontal rails
        var rn := maxi(0, int(h / spacing))
        for j in range(1, rn + 1):
                var vv := v1 + h * float(j) / float(rn + 1)
                var c2 := edge_a + edge_dir * (u1 + w * 0.5)
                var xf2 := Transform3D(basis, Vector3(c2.x, base_y + vv, c2.y))
                BFMeshUtilS.add_box(st_frame, xf2, Vector3(w, 0.045, 0.09), Vector2(0.5, 0.5))
