@tool
class_name BFStairBuilder
extends RefCounted
## Staircase generator: straight runs, doglegs (U-shaped) and spirals.
## Builds treads/risers, stringer, landings, railings and returns the slab
## hole rectangles so the floor above gets a proper stairwell opening.

const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")

enum StairKind { STRAIGHT, DOGLEG, SPIRAL }

const MAX_RISER := 0.19
const TREAD := 0.27


## Plans a stair: returns Dictionary with
##  steps:int, riser:float, tread:float, cell:Rect2 (XZ, local), hole:Rect2,
##  bottom_dir:Vector2 (unit, direction of ascent), kind:int
static func plan(kind: int, floor_h: float, rng: RandomNumberGenerator, width := 1.15) -> Dictionary:
        var steps := ceili(floor_h / MAX_RISER)
        var riser := floor_h / float(steps)
        match kind:
                StairKind.STRAIGHT:
                        var run := steps * TREAD
                        var cell := Rect2(Vector2.ZERO, Vector2(width + 0.1, run + 1.15))
                        var hole_steps := ceili(2.05 / riser)  # where headroom drops below 2.05 m
                        var hole_len := run - hole_steps * TREAD + 1.15
                        var hole := Rect2(Vector2(0.05, hole_steps * TREAD), Vector2(width, hole_len))
                        return {"steps": steps, "riser": riser, "tread": TREAD, "cell": cell,
                                "hole": hole, "bottom_dir": Vector2(0, 1), "kind": kind}
                StairKind.DOGLEG:
                        var run := steps * TREAD
                        var half_run := ceilf(run * 0.5)
                        var cell := Rect2(Vector2.ZERO, Vector2(width * 2.0 + 0.2, half_run + 1.15))
                        var hole := Rect2(Vector2(0.1, half_run * 0.55), Vector2(width * 2.0, half_run * 0.45 + 1.15))
                        return {"steps": steps, "riser": riser, "tread": TREAD, "cell": cell,
                                "hole": hole, "bottom_dir": Vector2(0, 1), "kind": kind}
                _:
                        var R := 1.25
                        var delta := clampf(0.26 / (0.62 * R), 0.25, 0.55)
                        var ssteps := ceili(floor_h / MAX_RISER)
                        var cell := Rect2(Vector2(-R - 0.15, -R - 0.15), Vector2(2 * R + 0.3, 2 * R + 0.3))
                        var hole_r := R + 0.12
                        var hole := Rect2(Vector2(-hole_r, -hole_r), Vector2(hole_r * 2, hole_r * 2))
                        return {"steps": ssteps, "riser": floor_h / float(ssteps), "tread": delta * 0.62 * R,
                                "cell": cell, "hole": hole, "bottom_dir": Vector2(1, 0), "kind": StairKind.SPIRAL,
                                "radius": R, "delta": delta}


## Places `cell` inside the interior bounds: tries the 4 corners, picks the
## first whose cell fits fully inside `bounds` (expanded check), else centers it.
static func place_cell(cell: Rect2, bounds: Rect2, rng: RandomNumberGenerator) -> Rect2:
        var c := cell.size
        var pad := 0.35
        var positions := [
                Vector2(bounds.position.x + pad, bounds.position.y + pad),
                Vector2(bounds.end.x - c.x - pad, bounds.position.y + pad),
                Vector2(bounds.position.x + pad, bounds.end.y - c.y - pad),
                Vector2(bounds.end.x - c.x - pad, bounds.end.y - c.y - pad),
                Vector2(bounds.get_center().x - c.x * 0.5, bounds.position.y + pad),
                bounds.get_center() - c * 0.5,
        ]
        for pos in positions:
                var r := Rect2(pos, c)
                if bounds.grow(-pad * 0.5).encloses(r):
                        return r
        return Rect2(bounds.get_center() - c * 0.5, c)


## Builds the stair into st (structure) and st_trim (wood/handrail).
## cell_pos: XZ origin of the planned cell. dir rotates the whole stair
## (bottom_dir rotated by dir.angle()). Returns dict:
## {top_center: Vector3, exit_dir: Vector2 (pointing away from top landing)}
static func build(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary, cell: Rect2,
                floor_h: float, base_y: float, rng: RandomNumberGenerator, tile := Vector2(0.5, 0.5)) -> Dictionary:
        var kind: int = plan_d.kind
        match kind:
                StairKind.STRAIGHT:
                        return _build_straight(st, st_trim, plan_d, cell, floor_h, base_y, tile)
                StairKind.DOGLEG:
                        return _build_dogleg(st, st_trim, plan_d, cell, floor_h, base_y, tile)
                _:
                        return _build_spiral(st, st_trim, plan_d, cell, floor_h, base_y, tile)


static func _railing(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
        BFMeshUtilS.add_railing(st, a, b, a.y, 0.95, 0.045)


static func _build_straight(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary,
                cell: Rect2, floor_h: float, base_y: float, tile: Vector2) -> Dictionary:
        var steps: int = plan_d.steps
        var riser: float = plan_d.riser
        var tread: float = plan_d.tread
        var x0 := cell.position.x + 0.05
        var w := cell.size.x - 0.1
        var z := cell.position.y
        for i in steps:
                var y0 := base_y + riser * i
                var y1 := base_y + riser * (i + 1)
                var zz := z + tread * i
                BFMeshUtilS.add_box(st, Transform3D(Basis.IDENTITY, Vector3(x0 + w * 0.5, (y0 + y1) * 0.5 + 0.02, zz + tread * 0.5)),
                        Vector3(w, y1 - y0 + 0.04, tread), tile)
        # top landing
        var lz := z + tread * steps
        BFMeshUtilS.add_box(st, Transform3D(Basis.IDENTITY, Vector3(x0 + w * 0.5, base_y + floor_h + 0.01, lz + 0.55)),
                Vector3(w, 0.06, 1.1), tile)
        # side railing (open long side: x = x0 + w)
        var rail_a := Vector3(x0 + w, base_y + 0.95, z + 0.05)
        var rail_b := Vector3(x0 + w, base_y + floor_h + 0.95, lz + 0.05)
        _railing(st_trim, rail_a, rail_b)
        # stringer board (visual, along the side)
        BFMeshUtilS.add_box(st_trim, Transform3D(Basis.IDENTITY, Vector3(x0 - 0.03, base_y + floor_h * 0.5, z + tread * steps * 0.5)),
                Vector3(0.06, 0.32, tread * steps + 0.1), tile)
        return {
                "top_center": Vector3(x0 + w * 0.5, base_y + floor_h, lz + 0.55),
                "exit_dir": Vector2(0, 1),
                "bottom_center": Vector3(x0 + w * 0.5, base_y, z + 0.4),
        }


static func _build_dogleg(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary,
                cell: Rect2, floor_h: float, base_y: float, tile: Vector2) -> Dictionary:
        var steps: int = plan_d.steps
        var riser: float = plan_d.riser
        var tread: float = plan_d.tread
        var half_steps := steps / 2
        var w := cell.size.x * 0.5 - 0.1
        var x0 := cell.position.x + 0.05
        var x1 := cell.position.x + cell.size.x * 0.5 + 0.05
        var z := cell.position.y
        # run 1: up along +z on left column
        for i in half_steps:
                var y0 := base_y + riser * i
                var y1 := base_y + riser * (i + 1)
                BFMeshUtilS.add_box(st, Transform3D(Basis.IDENTITY, Vector3(x0 + w * 0.5, (y0 + y1) * 0.5 + 0.02, z + tread * i + tread * 0.5)),
                        Vector3(w, y1 - y0 + 0.04, tread), tile)
        # mid landing
        var mid_y := base_y + riser * half_steps
        var lz := z + tread * half_steps
        BFMeshUtilS.add_box(st, Transform3D(Basis.IDENTITY, Vector3(cell.get_center().x, mid_y + 0.01, lz + 0.55)),
                Vector3(cell.size.x - 0.1, 0.06, 1.1), tile)
        # run 2: back along -z on right column
        for i in range(half_steps, steps):
                var y0 := base_y + riser * i
                var y1 := base_y + riser * (i + 1)
                var zz := lz + 1.1 - tread * (i - half_steps) - tread * 0.5
                BFMeshUtilS.add_box(st, Transform3D(Basis.IDENTITY, Vector3(x1 + w * 0.5, (y0 + y1) * 0.5 + 0.02, zz)),
                        Vector3(w, y1 - y0 + 0.04, tread), tile)
        # top landing (right column, at z start)
        var top := Vector3(x1 + w * 0.5, base_y + floor_h + 0.01, z + 0.55)
        BFMeshUtilS.add_box(st, Transform3D(Basis.IDENTITY, top), Vector3(w, 0.06, 1.1), tile)
        # railings: outer left of run1 + outer right of run2
        _railing(st_trim, Vector3(x0, base_y + 0.95, z + 0.05), Vector3(x0, base_y + mid_y + 0.95, lz + 0.05))
        _railing(st_trim, Vector3(x1 + w, base_y + mid_y + 0.95, lz + 1.05), Vector3(x1 + w, base_y + floor_h + 0.95, z + 1.05))
        return {
                "top_center": top,
                "exit_dir": Vector2(0, -1),
                "bottom_center": Vector3(x0 + w * 0.5, base_y, z + 0.4),
        }


static func _build_spiral(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary,
                cell: Rect2, floor_h: float, base_y: float, tile: Vector2) -> Dictionary:
        var steps: int = plan_d.steps
        var riser: float = plan_d.riser
        var R: float = plan_d.radius
        var delta: float = plan_d.delta
        var c := cell.get_center()
        # center pole
        BFMeshUtilS.add_cylinder(st, Transform3D(Basis.IDENTITY, Vector3(c.x, base_y + floor_h * 0.5, c.y)),
                0.09, floor_h + 0.1, 10, tile, true, true)
        var ang := 0.0
        for i in steps:
                var y0 := base_y + riser * i
                var a0 := ang
                var a1 := ang + delta
                ang = a1
                var r_in := 0.12
                var r_out := R
                # wedge approximated by a rotated box spanning mid-angle
                var mid := (a0 + a1) * 0.5
                var span := (a1 - a0) * (r_out + r_in) * 0.5
                var xfm := Transform3D(Basis(Vector3.UP, mid), Vector3(c.x, y0 + riser * 0.5 + 0.02, c.y))
                xfm = xfrm_rotated_step(xfm, mid, c, (r_in + r_out) * 0.5)
                BFMeshUtilS.add_box(st, xfm, Vector3(span, riser + 0.03, r_out - r_in), tile)
        # handrail: helix approximated with short segments
        var ang2 := 0.0
        var prev_top := Vector3(c.x + cos(0) * R, base_y + 0.95, c.y)
        for i in steps:
                ang2 += delta
                var y := base_y + riser * (i + 1) + 0.95
                var nxt := Vector3(c.x + cos(ang2) * R, y, c.y + sin(ang2) * R)
                BFMeshUtilS.add_box(st_trim, _seg_xform(prev_top, nxt), _seg_size(prev_top, nxt), tile)
                prev_top = nxt
        return {
                "top_center": Vector3(c.x + cos(ang) * (R - 0.3), base_y + floor_h, c.y + sin(ang) * (R - 0.3)),
                "exit_dir": Vector2(cos(ang), sin(ang)),
                "bottom_center": Vector3(c.x + R * 0.8, base_y, c.y),
        }


static func xfrm_rotated_step(xfm: Transform3D, mid: float, c: Vector2, rmid: float) -> Transform3D:
        var pos := Vector3(c.x + cos(mid) * rmid, xfm.origin.y, c.y + sin(mid) * rmid)
        return Transform3D(Basis(Vector3.UP, mid + PI * 0.5), pos)


static func _seg_xform(a: Vector3, b: Vector3) -> Transform3D:
        var dir := (b - a).normalized()
        var basis := Basis(-dir, Vector3.UP, dir.cross(Vector3.UP).normalized())
        return Transform3D(basis, (a + b) * 0.5)


static func _seg_size(a: Vector3, b: Vector3) -> Vector3:
        return Vector3(0.05, 0.05, a.distance_to(b) + 0.02)
