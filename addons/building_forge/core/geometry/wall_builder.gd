@tool
class_name BFWallBuilder
extends RefCounted
## Exterior wall generator: builds a continuous band around the footprint
## with mathematically mitered corners (no gaps possible by construction)
## and punched openings for windows / doors.
##
## The band for edge i is the prism between the outer segment [A,B] and the
## mitered inner segment [A',B']. Openings subdivide the band into solid
## pieces (below / above / between), whose end caps double as the jamb
## reveals of the openings. UVs run continuously along each edge so brick /
## plaster textures flow around corners without visible seams.

const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")

const MITER_CLAMP := 3.0  # max miter length, in multiples of thickness


static func to3(p: Vector2, y: float) -> Vector3:
        return Vector3(p.x, y, p.y)


## Computes the inward-mitered inner polygon (same vertex count as outer).
static func inner_polygon(outer: PackedVector2Array, thickness: float) -> PackedVector2Array:
        var n := outer.size()
        var inner := PackedVector2Array()
        inner.resize(n)
        if n < 3:
                return inner
        for i in n:
                var v := outer[i]
                var prev := outer[(i - 1 + n) % n]
                var next := outer[(i + 1) % n]
                var d0 := (v - prev).normalized()
                var d1 := (next - v).normalized()
                var n0 := Vector2(d0.y, -d0.x)  # outward normals (CCW polygon)
                var n1 := Vector2(d1.y, -d1.x)
                var cr := d0.cross(d1)
                if absf(cr) < 0.08:
                        # near-parallel edges (common on tessellated circles): simple offset
                        inner[i] = v - n0 * thickness
                        continue
                # Offset lines: L0: X = v - n0*t + s*d0 ; L1: X = v - n1*t + r*d1
                # s*d0 - r*d1 = (n0 - n1)*t  -> cross with d1 solves s
                var rhs := (n0 - n1) * thickness
                var s := rhs.cross(d1) / cr
                var q := v - n0 * thickness + d0 * s
                # clamp runaway miters at sharp corners
                var ml := (q - v).length()
                var max_ml := thickness * MITER_CLAMP
                if ml > max_ml:
                        q = v + (q - v).normalized() * max_ml
                inner[i] = q
        return inner


## Computes the outward-mitered outer polygon (same vertex count/order as
## input). Used for eave soffits: the result edges pair 1:1 with the input.
static func outer_polygon(outer: PackedVector2Array, thickness: float) -> PackedVector2Array:
        var n := outer.size()
        var out := PackedVector2Array()
        out.resize(n)
        if n < 3:
                return out
        for i in n:
                var v := outer[i]
                var prev := outer[(i - 1 + n) % n]
                var next := outer[(i + 1) % n]
                var d0 := (v - prev).normalized()
                var d1 := (next - v).normalized()
                var n0 := Vector2(d0.y, -d0.x)  # outward normals (CCW polygon)
                var n1 := Vector2(d1.y, -d1.x)
                var cr := d0.cross(d1)
                if absf(cr) < 0.08:
                        # near-parallel edges (tessellated circles): simple offset
                        out[i] = v + n0 * thickness
                        continue
                var rhs := (n1 - n0) * thickness
                var s := rhs.cross(d1) / cr
                var q := v + n0 * thickness + d0 * s
                var ml := (q - v).length()
                var max_ml := thickness * MITER_CLAMP
                if ml > max_ml:
                        q = v + (q - v).normalized() * max_ml
                out[i] = q
        return out


## Builds all wall pieces for one floor onto the SurfaceTool.
## openings: Dictionary  edge_index -> Array of Dictionaries {u1,u2,v1,v2}
##           (u along edge from A in meters, v from wall base in meters).
static func build_walls(st: SurfaceTool, fp: BFFootprint, base_y: float, height: float,
                thickness: float, openings: Dictionary, tile := Vector2(0.5, 0.5)) -> void:
        var outer := fp.points
        var inner := inner_polygon(outer, thickness)
        var n := outer.size()
        var top_y := base_y + height
        for i in n:
                var a: Vector2 = outer[i]
                var b: Vector2 = outer[(i + 1) % n]
                var a2: Vector2 = inner[i]
                var b2: Vector2 = inner[(i + 1) % n]
                var d := (b - a)
                var edge_len := d.length()
                if edge_len < 0.01:
                        continue
                d = d / edge_len
                var d3 := Vector3(d.x, 0, d.y)
                var n_out3 := Vector3(d.y, 0, -d.x)
                # sort openings by u1
                var ops: Array = []
                if openings.has(i):
                        ops = (openings[i] as Array).duplicate()
                        ops.sort_custom(func(x, y): return x.u1 < y.u1)
                # build solid pieces
                var cursor := 0.0
                for op in ops:
                        var o: Dictionary = op
                        var u1: float = clampf(o.u1, 0.0, edge_len)
                        var u2: float = clampf(o.u2, 0.0, edge_len)
                        var v1: float = clampf(o.v1, 0.0, height)
                        var v2: float = clampf(o.v2, 0.0, height)
                        if u1 > cursor + 0.005:
                                _piece(st, a, b, a2, b2, d3, n_out3, edge_len, cursor, u1, 0.0, height, base_y, top_y, tile)
                        if v1 > 0.01:
                                _piece(st, a, b, a2, b2, d3, n_out3, edge_len, u1, u2, 0.0, v1, base_y, top_y, tile)
                        if height - v2 > 0.01:
                                _piece(st, a, b, a2, b2, d3, n_out3, edge_len, u1, u2, v2, height, base_y, top_y, tile)
                        cursor = maxf(cursor, u2)
                if edge_len - cursor > 0.005:
                        _piece(st, a, b, a2, b2, d3, n_out3, edge_len, cursor, edge_len, 0.0, height, base_y, top_y, tile)


## One solid band piece [ua,ub] x [va,vb] (v from wall base).
## Outer points parametrize a->b; inner points a2->b2 by the SAME relative
## fraction, so miter-shortened inner edges stay exactly paired (watertight).
static func _piece(st: SurfaceTool, a: Vector2, b: Vector2, a2: Vector2, b2: Vector2,
                d3: Vector3, n_out3: Vector3, edge_len: float, ua: float, ub: float,
                va: float, vb: float, base_y: float, top_y: float, tile: Vector2) -> void:
        var ya := base_y + va
        var yb := base_y + vb
        var t_a := ua / edge_len
        var t_b := ub / edge_len
        var o_a := to3(a.lerp(b, t_a), 0)
        var o_b := to3(a.lerp(b, t_b), 0)
        var i_a := to3(a2.lerp(b2, t_a), 0)
        var i_b := to3(a2.lerp(b2, t_b), 0)
        var o_ay := Vector3(o_a.x, ya, o_a.z)
        var o_by := Vector3(o_b.x, ya, o_b.z)
        var o_at := Vector3(o_a.x, yb, o_a.z)
        var o_bt := Vector3(o_b.x, yb, o_b.z)
        var i_ay := Vector3(i_a.x, ya, i_a.z)
        var i_by := Vector3(i_b.x, ya, i_b.z)
        var i_at := Vector3(i_a.x, yb, i_a.z)
        var i_bt := Vector3(i_b.x, yb, i_b.z)
        var u_ta := ua * tile.x
        var u_tb := ub * tile.x
        var v_ta := (top_y - ya) * tile.y
        var v_tb := (top_y - yb) * tile.y

        # outer face (normal n_out)
        BFMeshUtilS.add_quad(st, [o_ay, o_at, o_bt, o_by], n_out3,
                [Vector2(u_ta, v_ta), Vector2(u_ta, v_tb), Vector2(u_tb, v_tb), Vector2(u_tb, v_ta)])
        # inner face (normal -n_out)
        BFMeshUtilS.add_quad(st, [i_ay, i_by, i_bt, i_at], -n_out3,
                [Vector2(u_ta, v_ta), Vector2(u_tb, v_ta), Vector2(u_tb, v_tb), Vector2(u_ta, v_tb)])
        # top face (UP) - visible as window sill reveals
        var uv_oa := Vector2(o_a.x, o_a.z) * tile.x
        var uv_ob := Vector2(o_b.x, o_b.z) * tile.x
        var uv_ia := Vector2(i_a.x, i_a.z) * tile.x
        var uv_ib := Vector2(i_b.x, i_b.z) * tile.x
        BFMeshUtilS.add_quad(st, [o_at, i_at, i_bt, o_bt], Vector3.UP,
                [uv_oa, uv_ia, uv_ib, uv_ob])
        # bottom face (DOWN) - visible as lintel reveals; all points at ya level
        BFMeshUtilS.add_quad(st, [o_ay, o_by, i_by, i_ay], Vector3.DOWN,
                [uv_oa, uv_ob, uv_ib, uv_ia])
        # start cap (normal -d)
        BFMeshUtilS.add_quad(st, [o_ay, i_ay, i_at, o_at], -d3,
                [Vector2(u_ta, v_ta), Vector2(u_ta, v_tb), Vector2(u_ta, v_tb), Vector2(u_ta, v_ta)])
        # end cap (normal +d, wound so cross points back into the band)
        BFMeshUtilS.add_quad(st, [o_by, o_bt, i_bt, i_by], d3,
                [Vector2(u_tb, v_ta), Vector2(u_tb, v_tb), Vector2(u_tb, v_tb), Vector2(u_tb, v_ta)])


## convenience: opening factory
static func make_opening(u1: float, u2: float, v1: float, v2: float) -> Dictionary:
        return {"u1": u1, "u2": u2, "v1": v1, "v2": v2}
