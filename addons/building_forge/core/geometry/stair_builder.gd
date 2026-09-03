@tool
class_name BFStairBuilder
extends RefCounted
## Staircase generator: straight runs, doglegs (U-shaped) and spirals.
## Builders work in CELL-LOCAL coordinates (x = width axis, z = run axis)
## and are placed through a transform, so a stair can be rotated 90 degrees
## (flip) to fit narrow footprints. Returns the slab hole rectangle so the
## floor above gets a proper stairwell opening with correct headroom.

const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")

enum StairKind { STRAIGHT, DOGLEG, SPIRAL }

const MAX_RISER := 0.19
const TREAD := 0.27
const HEADROOM := 2.02


## Plans a stair: returns Dictionary with
##  steps:int, riser:float, tread:float, cell:Rect2 (LOCAL), hole:Rect2 (LOCAL),
##  floor_h:float, kind:int
static func plan(kind: int, floor_h: float, rng: RandomNumberGenerator, width := 1.15) -> Dictionary:
        var steps := ceili(floor_h / MAX_RISER)
        var riser := floor_h / float(steps)
        match kind:
                StairKind.STRAIGHT:
                        var run := steps * TREAD
                        var cell := Rect2(Vector2.ZERO, Vector2(width + 0.1, run + 1.15))
                        # hole starts where headroom below the slab drops under HEADROOM:
                        # last step fully under solid slab i must satisfy fh - riser*i >= HEADROOM
                        var hole_steps := int(floor((floor_h - HEADROOM) / riser)) + 1
                        hole_steps = clampi(hole_steps, 1, maxi(1, steps - 2))
                        var hole := Rect2(Vector2(0.05, hole_steps * TREAD), Vector2(width, run + 1.15 - hole_steps * TREAD))
                        return {"steps": steps, "riser": riser, "tread": TREAD, "cell": cell,
                                "hole": hole, "bottom_dir": Vector2(0, 1), "kind": kind, "floor_h": floor_h}
                StairKind.DOGLEG:
                        var run := steps * TREAD
                        var half_run := ceilf(run * 0.5)
                        var cell := Rect2(Vector2.ZERO, Vector2(width * 2.0 + 0.2, half_run + 1.15))
                        var hole_y0 := half_run * 0.55
                        var hole := Rect2(Vector2(0.1, hole_y0), Vector2(width * 2.0, half_run + 1.15 - hole_y0))
                        return {"steps": steps, "riser": riser, "tread": TREAD, "cell": cell,
                                "hole": hole, "bottom_dir": Vector2(0, 1), "kind": kind, "floor_h": floor_h}
                _:
                        return _plan_spiral(floor_h, 1.25)


static func _plan_spiral(floor_h: float, R: float) -> Dictionary:
        var ssteps := ceili(floor_h / MAX_RISER)
        var delta := clampf(0.26 / (0.62 * R), 0.25, 0.55)
        var cell := Rect2(Vector2.ZERO, Vector2(2 * R + 0.3, 2 * R + 0.3))
        var hole_r := R + 0.12
        var hole := Rect2(Vector2(cell.size.x * 0.5 - hole_r, cell.size.y * 0.5 - hole_r), Vector2(hole_r * 2, hole_r * 2))
        return {"steps": ssteps, "riser": floor_h / float(ssteps), "tread": delta * 0.62 * R,
                "cell": cell, "hole": hole, "bottom_dir": Vector2(1, 0), "kind": StairKind.SPIRAL,
                "radius": R, "delta": delta, "floor_h": floor_h}


## Re-plans a stair into a smaller target footprint (cell-local size) by
## compressing tread depth or spiral radius. Returns {} when impossible.
static func refit(plan_d: Dictionary, target: Vector2) -> Dictionary:
        var kind: int = plan_d.kind
        var floor_h: float = plan_d.floor_h
        var steps: int = plan_d.steps
        match kind:
                StairKind.STRAIGHT:
                        var w: float = plan_d.cell.size.x
                        var w2: float = minf(w, target.x)
                        var avail: float = target.y - 1.15
                        var tread2: float = avail / float(steps)
                        if tread2 < 0.235:
                                return {}
                        tread2 = minf(tread2, TREAD)
                        var run: float = steps * tread2
                        var riser: float = plan_d.riser
                        var hole_steps := clampi(int(floor((floor_h - HEADROOM) / riser)) + 1, 1, maxi(1, steps - 2))
                        var hole := Rect2(Vector2(0.05, hole_steps * tread2), Vector2(w2 - 0.1, run + 1.15 - hole_steps * tread2))
                        return {"steps": steps, "riser": riser, "tread": tread2, "cell": Rect2(Vector2.ZERO, Vector2(w2, run + 1.15)),
                                "hole": hole, "bottom_dir": Vector2(0, 1), "kind": kind, "floor_h": floor_h}
                StairKind.DOGLEG:
                        var w2: float = minf(plan_d.cell.size.x, target.x)
                        var half_steps := steps / 2
                        var avail: float = target.y - 1.15
                        var tread2: float = avail / float(maxi(1, half_steps))
                        if tread2 < 0.235:
                                return {}
                        tread2 = minf(tread2, TREAD)
                        var half_run: float = ceilf(steps * tread2 * 0.5)
                        var cell := Rect2(Vector2.ZERO, Vector2(w2, half_run + 1.15))
                        var hole_y0 := half_run * 0.55
                        var hole := Rect2(Vector2(0.1, hole_y0), Vector2(w2 - 0.2, half_run + 1.15 - hole_y0))
                        return {"steps": steps, "riser": plan_d.riser, "tread": tread2, "cell": cell,
                                "hole": hole, "bottom_dir": Vector2(0, 1), "kind": kind, "floor_h": floor_h}
                _:
                        var R: float = clampf((minf(target.x, target.y) - 0.3) * 0.5, 0.8, 1.25)
                        if R < 0.85:
                                return {}
                        return _plan_spiral(floor_h, R)


## World-space rect of the stairwell hole for the slab above.
## flip: stair rotated 90 deg (run along world -X from cell corner).
static func hole_world(plan_d: Dictionary, cell: Rect2, flip: bool) -> Rect2:
        var h: Rect2 = plan_d.hole
        if plan_d.kind == StairKind.SPIRAL:
                return Rect2(cell.get_center() - h.size * 0.5, h.size)
        if not flip:
                return Rect2(cell.position + h.position, h.size)
        # rotated: local (x,z) -> world (-z, x) relative to cell corner
        return Rect2(Vector2(cell.position.x - (h.position.y + h.size.y), cell.position.y + h.position.x),
                Vector2(h.size.y, h.size.x))


## Builds the stair into st (structure) and st_trim (wood/handrail).
## cell: XZ rect the stair occupies; flip rotates it 90 deg.
## Returns {top_center: Vector3, bottom_center: Vector3}
static func build(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary, cell: Rect2,
                floor_h: float, base_y: float, rng: RandomNumberGenerator, tile := Vector2(0.5, 0.5), flip := false) -> Dictionary:
        var kind: int = plan_d.kind
        var place := Transform3D(Basis.IDENTITY, Vector3(cell.position.x, 0, cell.position.y))
        if flip and kind != StairKind.SPIRAL:
                # proper rotation: local (x,y,z) -> world (-z, y, x)
                place = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cell.position.x, 0, cell.position.y))
        match kind:
                StairKind.STRAIGHT:
                        return _build_straight(st, st_trim, plan_d, cell, floor_h, base_y, tile, place)
                StairKind.DOGLEG:
                        return _build_dogleg(st, st_trim, plan_d, cell, floor_h, base_y, tile, place)
                _:
                        return _build_spiral(st, st_trim, plan_d, cell, floor_h, base_y, tile, place)


static func _railing(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
        BFMeshUtilS.add_railing(st, a, b, a.y, 0.95, 0.045)


static func _build_straight(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary,
                cell: Rect2, floor_h: float, base_y: float, tile: Vector2, xf: Transform3D) -> Dictionary:
        var steps: int = plan_d.steps
        var riser: float = plan_d.riser
        var tread: float = plan_d.tread
        var x0 := 0.05
        var w := cell.size.x - 0.1
        for i in steps:
                var y0 := base_y + riser * i
                var y1 := base_y + riser * (i + 1)
                var zz := tread * i
                BFMeshUtilS.add_box(st, xf * Transform3D(Basis.IDENTITY, Vector3(x0 + w * 0.5, (y0 + y1) * 0.5 + 0.02, zz + tread * 0.5)),
                        Vector3(w, y1 - y0 + 0.04, tread), tile)
        # top landing
        var lz := tread * steps
        BFMeshUtilS.add_box(st, xf * Transform3D(Basis.IDENTITY, Vector3(x0 + w * 0.5, base_y + floor_h + 0.01, lz + 0.55)),
                Vector3(w, 0.06, 1.1), tile)
        # side railing (open long side: x = x0 + w)
        _railing(st_trim, xf * Vector3(x0 + w, base_y + 0.95, 0.05), xf * Vector3(x0 + w, base_y + floor_h + 0.95, lz + 0.05))
        # stringer board (visual, along the side)
        BFMeshUtilS.add_box(st_trim, xf * Transform3D(Basis.IDENTITY, Vector3(x0 - 0.03, base_y + floor_h * 0.5, tread * steps * 0.5)),
                Vector3(0.06, 0.32, tread * steps + 0.1), tile)
        return {
                "top_center": xf * Vector3(x0 + w * 0.5, base_y + floor_h, lz + 0.55),
                "bottom_center": xf * Vector3(x0 + w * 0.5, base_y, 0.4),
        }


static func _build_dogleg(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary,
                cell: Rect2, floor_h: float, base_y: float, tile: Vector2, xf: Transform3D) -> Dictionary:
        var steps: int = plan_d.steps
        var riser: float = plan_d.riser
        var tread: float = plan_d.tread
        var half_steps := steps / 2
        var w := cell.size.x * 0.5 - 0.1
        var x0 := 0.05
        var x1 := cell.size.x * 0.5 + 0.05
        # run 1: up along +z on left column
        for i in half_steps:
                var y0 := base_y + riser * i
                var y1 := base_y + riser * (i + 1)
                BFMeshUtilS.add_box(st, xf * Transform3D(Basis.IDENTITY, Vector3(x0 + w * 0.5, (y0 + y1) * 0.5 + 0.02, tread * i + tread * 0.5)),
                        Vector3(w, y1 - y0 + 0.04, tread), tile)
        # mid landing
        var mid_y := base_y + riser * half_steps
        var lz := tread * half_steps
        BFMeshUtilS.add_box(st, xf * Transform3D(Basis.IDENTITY, Vector3(cell.size.x * 0.5, mid_y + 0.01, lz + 0.55)),
                Vector3(cell.size.x - 0.1, 0.06, 1.1), tile)
        # run 2: back along -z on right column
        for i in range(half_steps, steps):
                var y0 := base_y + riser * i
                var y1 := base_y + riser * (i + 1)
                var zz := lz + 1.1 - tread * (i - half_steps) - tread * 0.5
                BFMeshUtilS.add_box(st, xf * Transform3D(Basis.IDENTITY, Vector3(x1 + w * 0.5, (y0 + y1) * 0.5 + 0.02, zz)),
                        Vector3(w, y1 - y0 + 0.04, tread), tile)
        # top landing (right column, at z start)
        var top_local := Vector3(x1 + w * 0.5, base_y + floor_h + 0.01, 0.55)
        BFMeshUtilS.add_box(st, xf * Transform3D(Basis.IDENTITY, top_local), Vector3(w, 0.06, 1.1), tile)
        # railings: outer left of run1 + outer right of run2
        _railing(st_trim, xf * Vector3(x0, base_y + 0.95, 0.05), xf * Vector3(x0, base_y + mid_y + 0.95, lz + 0.05))
        _railing(st_trim, xf * Vector3(x1 + w, base_y + mid_y + 0.95, lz + 1.05), xf * Vector3(x1 + w, base_y + floor_h + 0.95, 1.05))
        return {
                "top_center": xf * top_local,
                "bottom_center": xf * Vector3(x0 + w * 0.5, base_y, 0.4),
        }


static func _build_spiral(st: SurfaceTool, st_trim: SurfaceTool, plan_d: Dictionary,
                cell: Rect2, floor_h: float, base_y: float, tile: Vector2, xf: Transform3D) -> Dictionary:
        var steps: int = plan_d.steps
        var riser: float = plan_d.riser
        var R: float = plan_d.radius
        var delta: float = plan_d.delta
        var c_local := Vector3(cell.size.x * 0.5, 0, cell.size.y * 0.5)
        # center pole
        BFMeshUtilS.add_cylinder(st, xf * Transform3D(Basis.IDENTITY, Vector3(c_local.x, base_y + floor_h * 0.5, c_local.z)),
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
                var step_xf := Transform3D(Basis(Vector3.UP, mid), Vector3(0, y0 + riser * 0.5 + 0.02, 0))
                step_xf = _rotated_step(step_xf, mid, (r_in + r_out) * 0.5)
                # box local +Z (radial depth) must map to the radial direction
                # at angle `mid`: rotation = PI/2 - mid  (was mid + PI/2: the
                # box's radial axis pointed at -mid, scrambling the helix)
                BFMeshUtilS.add_box(st, xf * step_xf, Vector3(span, riser + 0.03, r_out - r_in), tile)
        # handrail: helix approximated with short segments
        var ang2 := 0.0
        var prev_top := xf * (Vector3(c_local.x + cos(0) * R, base_y + 0.95, c_local.z + sin(0) * R))
        for i in steps:
                ang2 += delta
                var y := base_y + riser * (i + 1) + 0.95
                var nxt := xf * (Vector3(c_local.x + cos(ang2) * R, y, c_local.z + sin(ang2) * R))
                BFMeshUtilS.add_box(st_trim, _seg_xform(prev_top, nxt), _seg_size(prev_top, nxt), tile)
                prev_top = nxt
        return {
                "top_center": xf * (Vector3(c_local.x + cos(ang) * (R - 0.3), base_y + floor_h, c_local.z + sin(ang) * (R - 0.3))),
                "bottom_center": xf * (Vector3(c_local.x + R * 0.8, base_y, c_local.z)),
        }


static func _rotated_step(xfm: Transform3D, mid: float, rmid: float) -> Transform3D:
        var pos := Vector3(cos(mid) * rmid, xfm.origin.y, sin(mid) * rmid)
        return Transform3D(Basis(Vector3.UP, PI * 0.5 - mid), pos)


static func _seg_xform(a: Vector3, b: Vector3) -> Transform3D:
        var dir := (b - a).normalized()
        var basis := Basis(-dir, Vector3.UP, dir.cross(Vector3.UP).normalized())
        return Transform3D(basis, (a + b) * 0.5)


static func _seg_size(a: Vector3, b: Vector3) -> Vector3:
        return Vector3(0.05, 0.05, a.distance_to(b) + 0.02)
