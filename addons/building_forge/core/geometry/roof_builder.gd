@tool
class_name BFRoofBuilder
extends RefCounted
## Roof variants. Pitched roofs (gable/hip) are built over the footprint's
## oriented bounding box so they always fully cover the polygon; a flat deck
## seals the interior below. All quads are passed to BFMeshUtil in
## CCW-from-outside order; BFMeshUtil applies Godot's CW front-face rule.

const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")
const BFSlabBuilderS := preload("res://addons/building_forge/core/geometry/slab_builder.gd")
const BFWallBuilderS := preload("res://addons/building_forge/core/geometry/wall_builder.gd")

enum RoofKind { FLAT, GABLE, HIP, CONE, DOME }


static func to3(p: Vector2, y: float) -> Vector3:
        return Vector3(p.x, y, p.y)


## Oriented bounding box: [center: Vector2, half: Vector2, angle: float].
## half.x is the longer side; angle rotates local X to world.
static func oriented_bbox(poly: PackedVector2Array) -> Array:
        if poly.is_empty():
                return [Vector2.ZERO, Vector2.ONE, 0.0]
        var n := poly.size()
        var best_area := INF
        var best := [Vector2.ZERO, Vector2.ONE, 0.0]
        var angles := []
        for i in n:
                var d := (poly[(i + 1) % n] - poly[i]).normalized()
                angles.append(atan2(d.y, d.x))
        var tried := {}
        var step := maxi(1, n / 12)
        for i in range(0, n, step):
                var ang: float = angles[i]
                var key := snappedf(ang, 0.01)
                if tried.has(key):
                        continue
                tried[key] = true
                var c := cos(-ang)
                var s := sin(-ang)
                var lo := Vector2(INF, INF)
                var hi := Vector2(-INF, -INF)
                for p in poly:
                        var q := Vector2(p.x * c - p.y * s, p.x * s + p.y * c)
                        lo = lo.min(q)
                        hi = hi.max(q)
                var area := (hi.x - lo.x) * (hi.y - lo.y)
                if area < best_area:
                        best_area = area
                        var cl := (lo + hi) * 0.5
                        var c2 := cos(ang)
                        var s2 := sin(ang)
                        var center := Vector2(cl.x * c2 - cl.y * s2, cl.x * s2 + cl.y * c2)
                        var half := (hi - lo) * 0.5
                        if half.y > half.x:
                                best = [center, Vector2(half.y, half.x), ang + PI * 0.5]
                        else:
                                best = [center, half, ang]
        return best


static func build_roof(kind: int, st: SurfaceTool, st_trim: SurfaceTool, fp: BFFootprint,
                base_y: float, params: Dictionary) -> void:
        var overhang: float = params.get("overhang", 0.45)
        var pitch: float = params.get("pitch", 0.55)
        var tile: Vector2 = params.get("tile", Vector2(0.5, 0.5))
        match kind:
                RoofKind.FLAT:
                        _build_flat(st, st_trim, fp, base_y, overhang, params.get("parapet_h", 0.55), tile)
                RoofKind.GABLE:
                        _build_gable(st, st_trim, fp, base_y, overhang, pitch, tile)
                RoofKind.HIP:
                        _build_hip(st, st_trim, fp, base_y, overhang, pitch, tile)
                RoofKind.CONE:
                        _build_cone(st, st_trim, fp, base_y, overhang, params.get("cone_pitch", 0.8), tile)
                RoofKind.DOME:
                        _build_dome(st, fp, base_y - 0.28, tile)  # seat dome on wall tops


## Eave soffit: horizontal band from the wall face out to the ACTUAL roof
## extent (each mitered wall vertex is ray-cast to the roof boundary),
## facing DOWN. Without it the wedge under pitched/cone roofs is see-through
## from outside, especially on non-rectangular footprints where the roof
## overhangs the polygon outset.
## cast: Callable(from: Vector2, dir: Vector2) -> Vector2 (outer point).
static func _soffit(st: SurfaceTool, fp: BFFootprint, y: float, overhang: float, tile: Vector2, cast: Callable) -> void:
        if overhang < 0.02:
                return
        var n := fp.points.size()
        var outer := PackedVector2Array()
        outer.resize(n)
        for i in n:
                var prev := (fp.points[(i - 1 + n) % n] - fp.points[i]).normalized()
                var next := (fp.points[(i + 1) % n] - fp.points[i]).normalized()
                var n0 := Vector2(prev.y, -prev.x)
                var n1 := Vector2(next.y, -next.x)
                var m := n0 + n1
                m = m.normalized() if m.length() > 0.01 else n1
                outer[i] = cast.call(fp.points[i], m)
        for i in n:
                var a: Vector2 = fp.points[i]
                var b: Vector2 = fp.points[(i + 1) % n]
                var a2: Vector2 = outer[i]
                var b2: Vector2 = outer[(i + 1) % n]
                BFMeshUtilS.add_quad(st,
                        [to3(a2, y), to3(b2, y), to3(b, y), to3(a, y)], Vector3.DOWN,
                        [Vector2(a2.x * tile.x, a2.y * tile.y), Vector2(b2.x * tile.x, b2.y * tile.y),
                        Vector2(b.x * tile.x, b.y * tile.y), Vector2(a.x * tile.x, a.y * tile.y)])


## Ray-cast helper factory: to an oriented box (gable/hip roof extent).
static func _obb_cast(xfrm: Transform3D, hx: float, hz: float, max_t: float) -> Callable:
        var inv := xfrm.affine_inverse()
        return func(from: Vector2, dir: Vector2) -> Vector2:
                var l0 := inv * Vector3(from.x, 0, from.y)
                var ld := inv.basis * Vector3(dir.x, 0, dir.y)
                var t := max_t
                if absf(ld.x) > 0.0001:
                        var tx := ((hx if ld.x > 0 else -hx) - l0.x) / ld.x
                        if tx > 0.001:
                                t = minf(t, tx)
                if absf(ld.z) > 0.0001:
                        var tz := ((hz if ld.z > 0 else -hz) - l0.z) / ld.z
                        if tz > 0.001:
                                t = minf(t, tz)
                var hit := l0 + ld * t
                var w := xfrm * Vector3(hit.x, 0, hit.z)
                return Vector2(w.x, w.z)


## Ray-cast helper factory: to a circle (cone roof extent).
static func _circle_cast(c: Vector2, r: float, max_t: float) -> Callable:
        return func(from: Vector2, dir: Vector2) -> Vector2:
                var d := from - c
                var b := d.dot(dir)
                var disc := b * b - (d.length_squared() - r * r)
                var t := max_t
                if disc >= 0.0:
                        var sq := sqrt(disc)
                        var t1 := -b - sq
                        var t2 := -b + sq
                        if t1 > 0.001:
                                t = minf(t, t1)
                        elif t2 > 0.001:
                                t = minf(t, t2)
                return from + dir * t


## Flat horizontal surface at height y (top face of a deck), Godot-CW order.
static func _deck(st: SurfaceTool, fp: BFFootprint, y: float, tile: Vector2) -> void:
        var tris := Geometry2D.triangulate_polygon(fp.points)
        if tris.is_empty():
                return
        tris = BFSlabBuilderS.filter_degenerate(fp.points, tris)
        for t in range(0, tris.size(), 3):
                for k in [0, 1, 2]:
                        var p: Vector2 = fp.points[tris[t + k]]
                        st.set_normal(Vector3.UP)
                        st.set_uv(Vector2(p.x * tile.x, p.y * tile.y))
                        st.add_vertex(to3(p, y))


static func _build_flat(st: SurfaceTool, st_trim: SurfaceTool, fp: BFFootprint, base_y: float,
                overhang: float, parapet_h: float, tile: Vector2) -> void:
        var outer := fp.outset(overhang)
        BFSlabBuilderS.build_slab(st, outer, base_y - 0.12, base_y + 0.05, Rect2(), tile, false)
        # inner ring must share vertex order with outer (offset_polygon output
        # order is arbitrary -> use our order-preserving miter inset instead)
        var inner := BFWallBuilderS.inner_polygon(outer, 0.12)
        _parapet_band(st, outer, inner, base_y + 0.05, base_y + 0.05 + parapet_h, 0.25, tile)
        _fascia(st_trim, outer, base_y - 0.14, base_y - 0.02, tile)


## Parapet ring: prism between outer polygon and inner (inset) polygon.
static func _parapet_band(st: SurfaceTool, outer: PackedVector2Array, inner: PackedVector2Array,
                y0: float, y1: float, thick: float, tile: Vector2) -> void:
        var n := outer.size()
        var m := inner.size()
        if n != m:
                for i in n:
                        var a: Vector2 = outer[i]
                        var b: Vector2 = outer[(i + 1) % n]
                        var mid := (a + b) * 0.5
                        var d := (b - a).normalized()
                        var xform := Transform3D(Basis(Vector3(d.x, 0, d.y), Vector3.UP, Vector3(d.y, 0, -d.x)), Vector3(mid.x, (y0 + y1) * 0.5, mid.y))
                        BFMeshUtilS.add_box(st, xform, Vector3(a.distance_to(b), y1 - y0, thick), tile)
                return
        for i in n:
                var a: Vector2 = outer[i]
                var b: Vector2 = outer[(i + 1) % n]
                var a2: Vector2 = inner[i]
                var b2: Vector2 = inner[(i + 1) % n]
                var d := (b - a)
                var l := d.length()
                if l < 0.01:
                        continue
                d /= l
                var d3 := Vector3(d.x, 0, d.y)
                var n_out3 := Vector3(d.y, 0, -d.x)
                var o_ay := to3(a, y0)
                var o_by := to3(b, y0)
                var i_ay := to3(a2, y0)
                var i_by := to3(b2, y0)
                var o_at := Vector3(o_ay.x, y1, o_ay.z)
                var o_bt := Vector3(o_by.x, y1, o_by.z)
                var i_at := Vector3(i_ay.x, y1, i_ay.z)
                var i_bt := Vector3(i_by.x, y1, i_by.z)
                BFMeshUtilS.add_quad(st, [o_ay, o_at, o_bt, o_by], n_out3,
                        [Vector2(a.x * tile.x, y0 * tile.y), Vector2(a.x * tile.x, y1 * tile.y),
                        Vector2(b.x * tile.x, y1 * tile.y), Vector2(b.x * tile.x, y0 * tile.y)])
                BFMeshUtilS.add_quad(st, [i_ay, i_by, i_bt, i_at], -n_out3,
                        [Vector2(a2.x * tile.x, y0 * tile.y), Vector2(b2.x * tile.x, y0 * tile.y),
                        Vector2(b2.x * tile.x, y1 * tile.y), Vector2(a2.x * tile.x, y1 * tile.y)])
                BFMeshUtilS.add_quad(st, [o_at, i_at, i_bt, o_bt], Vector3.UP,
                        [Vector2(a.x * tile.x, a.y * tile.x), Vector2(a2.x * tile.x, a2.y * tile.x),
                        Vector2(b2.x * tile.x, b2.y * tile.x), Vector2(b.x * tile.x, b.y * tile.x)])
                BFMeshUtilS.add_quad(st, [o_ay, o_by, i_by, i_ay], Vector3.DOWN,
                        [Vector2(a.x * tile.x, a.y * tile.x), Vector2(b.x * tile.x, b.y * tile.x),
                        Vector2(b2.x * tile.x, b2.y * tile.x), Vector2(a2.x * tile.x, a2.y * tile.x)])
                BFMeshUtilS.add_quad(st, [o_ay, i_ay, i_at, o_at], -d3,
                        [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
                BFMeshUtilS.add_quad(st, [o_by, o_bt, i_bt, i_by], d3,
                        [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


## Fascia: downward-facing trim band around the eave edge.
static func _fascia(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float, tile: Vector2) -> void:
        var n := poly.size()
        for i in n:
                var a := poly[i]
                var b := poly[(i + 1) % n]
                var d := (b - a).normalized()
                BFMeshUtilS.add_quad(st, [to3(a, y0), to3(a, y1), to3(b, y1), to3(b, y0)],
                        Vector3(d.y, 0, -d.x),
                        [Vector2(a.x * tile.x, -y0 * tile.y), Vector2(a.x * tile.x, -y1 * tile.y),
                        Vector2(b.x * tile.x, -y1 * tile.y), Vector2(b.x * tile.x, -y0 * tile.y)])


static func _pitched_xfrm(fp: BFFootprint, base_y: float, overhang: float) -> Array:
        var obb := oriented_bbox(fp.points)
        var center: Vector2 = obb[0]
        var half: Vector2 = obb[1]
        var ang: float = obb[2]
        var ca := cos(ang)
        var sa := sin(ang)
        var hx: float = half.x + overhang
        var hz: float = half.y + overhang
        var xfrm := Transform3D(Basis(Vector3(ca, 0, -sa), Vector3.UP, Vector3(sa, 0, ca)), Vector3(center.x, base_y, center.y))
        return [xfrm, hx, hz, ca, sa]


static func _build_gable(st: SurfaceTool, st_trim: SurfaceTool, fp: BFFootprint, base_y: float,
                overhang: float, pitch: float, tile: Vector2) -> void:
        var p := _pitched_xfrm(fp, base_y, overhang)
        var xfrm: Transform3D = p[0]
        var hx: float = p[1]
        var hz: float = p[2]
        var ridge_h: float = hz * pitch
        var eave_y := -0.02
        var uv_e0 := Vector2(-hx * tile.x, -hz * tile.y)
        var uv_e1 := Vector2(hx * tile.x, -hz * tile.y)
        var uv_r1 := Vector2(hx * tile.x, 0)
        var uv_r0 := Vector2(-hx * tile.x, 0)
        # south slope (visible normal up & -z)
        BFMeshUtilS.add_quad(st,
                [xfrm * Vector3(-hx, eave_y, -hz), xfrm * Vector3(-hx, ridge_h, 0),
                xfrm * Vector3(hx, ridge_h, 0), xfrm * Vector3(hx, eave_y, -hz)],
                Vector3(0, cos(atan(pitch)), -sin(atan(pitch))).normalized(),
                [uv_e0, uv_r0, uv_r1, uv_e1])
        # north slope (visible normal up & +z)
        BFMeshUtilS.add_quad(st,
                [xfrm * Vector3(hx, eave_y, hz), xfrm * Vector3(hx, ridge_h, 0),
                xfrm * Vector3(-hx, ridge_h, 0), xfrm * Vector3(-hx, eave_y, hz)],
                Vector3(0, cos(atan(pitch)), sin(atan(pitch))).normalized(),
                [uv_e1, uv_r1, uv_r0, uv_e0])
        # gable end walls (verge triangles, extended to the overhang edge)
        for sx in [-1.0, 1.0]:
                BFMeshUtilS.add_quad(st,
                        [xfrm * Vector3(sx * hx, eave_y, -sx * hz), xfrm * Vector3(sx * hx, ridge_h, 0),
                        xfrm * Vector3(sx * hx, eave_y, sx * hz)],
                        xfrm.basis * Vector3(sx, 0, 0),
                        [Vector2(0, 0), Vector2(hz * tile.x, ridge_h * tile.y), Vector2(2 * hz * tile.x, 0)])
        # seal interior
        _deck(st, fp, base_y - 0.02, tile)
        _soffit(st_trim, fp, base_y - 0.02, overhang, tile, _obb_cast(xfrm, hx, hz, overhang * 3.0 + 1.0))


static func _build_hip(st: SurfaceTool, st_trim: SurfaceTool, fp: BFFootprint, base_y: float,
                overhang: float, pitch: float, tile: Vector2) -> void:
        var p := _pitched_xfrm(fp, base_y, overhang)
        var xfrm: Transform3D = p[0]
        var hx: float = p[1]
        var hz: float = p[2]
        var ridge_h: float = hz * pitch
        var ridge_half_len: float = maxf(0.05, hx - hz)
        var r0 := Vector3(-ridge_half_len, ridge_h, 0)
        var r1 := Vector3(ridge_half_len, ridge_h, 0)
        var eave_y := -0.02
        BFMeshUtilS.add_quad(st,
                [xfrm * Vector3(-hx, eave_y, -hz), xfrm * r0, xfrm * r1, xfrm * Vector3(hx, eave_y, -hz)],
                Vector3(0, cos(atan(pitch)), -sin(atan(pitch))).normalized(),
                [Vector2(-hx * tile.x, -hz * tile.y), Vector2(-ridge_half_len * tile.x, 0),
                Vector2(ridge_half_len * tile.x, 0), Vector2(hx * tile.x, -hz * tile.y)])
        BFMeshUtilS.add_quad(st,
                [xfrm * Vector3(hx, eave_y, hz), xfrm * r1, xfrm * r0, xfrm * Vector3(-hx, eave_y, hz)],
                Vector3(0, cos(atan(pitch)), sin(atan(pitch))).normalized(),
                [Vector2(hx * tile.x, -hz * tile.y), Vector2(ridge_half_len * tile.x, 0),
                Vector2(-ridge_half_len * tile.x, 0), Vector2(-hx * tile.x, -hz * tile.y)])
        for s in [[1.0, r1], [-1.0, r0]]:
                var sx: float = s[0]
                var r: Vector3 = s[1]
                BFMeshUtilS.add_quad(st,
                        [xfrm * Vector3(sx * hx, eave_y, sx * hz), xfrm * r, xfrm * Vector3(sx * hx, eave_y, -sx * hz)],
                        xfrm.basis * Vector3(sx, 0, 0).normalized(),
                        [Vector2(0, 0), Vector2(hz * tile.x, ridge_h * tile.y), Vector2(2 * hz * tile.x, 0)])
        _deck(st, fp, base_y - 0.02, tile)
        _soffit(st_trim, fp, base_y - 0.02, overhang, tile, _obb_cast(xfrm, hx, hz, overhang * 3.0 + 1.0))


static func _build_cone(st: SurfaceTool, st_trim: SurfaceTool, fp: BFFootprint, base_y: float,
                overhang: float, pitch: float, tile: Vector2) -> void:
        var c := fp.center_xz()
        var sz := fp.size_xz()
        var r := maxf(sz.x, sz.y) * 0.5 + overhang
        var h := r * pitch
        var segs := maxi(20, fp.points.size())
        var apex := to3(c, base_y + h)
        # triangle fan; already in final Godot order (cross points inward)
        for i in segs:
                var a0 := TAU * float(i) / float(segs)
                var a1 := TAU * float(i + 1) / float(segs)
                var p0 := Vector3(c.x + cos(a0) * r, base_y, c.y + sin(a0) * r)
                var p1 := Vector3(c.x + cos(a1) * r, base_y, c.y + sin(a1) * r)
                var mid_a := (a0 + a1) * 0.5
                var nrm := Vector3(cos(mid_a) * h, r, sin(mid_a) * h).normalized()
                st.set_normal(nrm)
                st.set_uv(Vector2(a0 * r * tile.x, 0))
                st.add_vertex(p0)
                st.set_normal(nrm)
                st.set_uv(Vector2(a1 * r * tile.x, 0))
                st.add_vertex(p1)
                st.set_normal(nrm)
                st.set_uv(Vector2(mid_a * r * tile.x, h * tile.y))
                st.add_vertex(apex)
        _deck(st, fp, base_y - 0.02, tile)
        var cc := fp.center_xz()
        var rr := maxf(fp.size_xz().x, fp.size_xz().y) * 0.5 + overhang
        _soffit(st_trim, fp, base_y, overhang, tile, _circle_cast(cc, rr, overhang * 3.0 + 1.0))


static func _build_dome(st: SurfaceTool, fp: BFFootprint, base_y: float, tile: Vector2) -> void:
        var c := fp.center_xz()
        var sz := fp.size_xz()
        var r := maxf(sz.x, sz.y) * 0.5
        # squash along the short axis so an oval drum gets an ELLIPSOID dome
        # (a circular dome on an oval drum floats over the narrow ends)
        var fz := clampf(sz.y / maxf(sz.x, 0.01), 0.5, 1.0)
        var fx := 1.0
        var rings := 8
        var segs := maxi(20, fp.points.size())
        for ri in rings:
                var phi0 := PI * 0.5 * float(ri) / float(rings)
                var phi1 := PI * 0.5 * float(ri + 1) / float(rings)
                for si in segs:
                        var a0 := TAU * float(si) / float(segs)
                        var a1 := TAU * float(si + 1) / float(segs)
                        var p00 := _sph_x(c, r, phi0, a0, base_y, fx, fz)
                        var p01 := _sph_x(c, r, phi0, a1, base_y, fx, fz)
                        var p10 := _sph_x(c, r, phi1, a0, base_y, fx, fz)
                        var p11 := _sph_x(c, r, phi1, a1, base_y, fx, fz)
                        var nrm := (p00 + p01 + p10 + p11 - Vector3(c.x, base_y, c.y) * 4.0).normalized()
                        BFMeshUtilS.add_quad(st, [p00, p01, p11, p10], nrm,
                                [Vector2(a0 * r * tile.x, phi0 * r * tile.y), Vector2(a1 * r * tile.x, phi0 * r * tile.y),
                                Vector2(a1 * r * tile.x, phi1 * r * tile.y), Vector2(a0 * r * tile.x, phi1 * r * tile.y)])
        _deck(st, fp, base_y - 0.02, tile)


static func _sph(c: Vector2, r: float, phi: float, a: float, base_y: float) -> Vector3:
        return Vector3(c.x + cos(a) * sin(phi) * r, base_y + cos(phi) * r, c.y + sin(a) * sin(phi) * r)


static func _sph_x(c: Vector2, r: float, phi: float, a: float, base_y: float, fx: float, fz: float) -> Vector3:
        return Vector3(c.x + cos(a) * sin(phi) * r * fx, base_y + cos(phi) * r, c.y + sin(a) * sin(phi) * r * fz)
