@tool
class_name BFSlabBuilder
extends RefCounted
## Floor & ceiling slabs: extruded footprint polygons with rectangular
## stairwell holes. Hole cutting uses Geometry2D.clip_polygons (Clipper2),
## which is robust for any hole placement; result pieces are triangulated
## individually so slabs are always watertight.

const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")


static func to3(p: Vector2, y: float) -> Vector3:
        return Vector3(p.x, y, p.y)


static func _rect_poly(r: Rect2) -> PackedVector2Array:
        return PackedVector2Array([
                r.position, r.position + Vector2(r.size.x, 0),
                r.position + r.size, r.position + Vector2(0, r.size.y)])


static func _signed_area(poly: PackedVector2Array) -> float:
        if poly.size() < 3:
                return 0.0
        var a := 0.0
        for i in poly.size():
                var p0 := poly[i]
                var p1 := poly[(i + 1) % poly.size()]
                a += p0.x * p1.y - p1.x * p0.y
        return a * 0.5


## Subtracts rect holes from polygon. Returns array of hole-free CCW polygons.
static func minus_holes(poly: PackedVector2Array, holes: Array) -> Array:
        var pieces: Array = [poly]
        for h in holes:
                var hr: Rect2 = h
                if hr.size.x <= 0.0 or hr.size.y <= 0.0:
                        continue
                var next_pieces: Array = []
                for p in pieces:
                        var res := Geometry2D.clip_polygons(p, _rect_poly(hr))
                        for rp in res:
                                if rp.size() >= 3 and absf(_signed_area(rp)) > 0.01:
                                        next_pieces.append(rp)
                pieces = next_pieces
        # normalize winding to CCW
        var out: Array = []
        for p in pieces:
                if p.size() >= 3:
                        if Geometry2D.is_polygon_clockwise(p):
                                p.reverse()
                        out.append(p)
        return out


## Emits a closed slab: top face, bottom face, side band + hole bands.
## holes: Array of Rect2 (XZ, local). skip_bottom: for ground slabs.
static func build_slab(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float,
                hole := Rect2(), tile := Vector2(0.5, 0.5), skip_bottom := false, holes := []) -> void:
        if poly.size() < 3 or y1 - y0 < 0.01:
                return
        var all_holes: Array = holes.duplicate()
        if hole.size.x > 0.0 and hole.size.y > 0.0:
                all_holes.append(hole)
        var pieces := minus_holes(poly, all_holes)
        if pieces.is_empty():
                push_warning("[BF] slab triangulation produced nothing")
                return
        for piece in pieces:
                var tris := Geometry2D.triangulate_polygon(piece)
                if tris.is_empty():
                        continue
                # top (final cross -Y per Godot CW rule: natural 2D-CCW order gives -Y)
                for t in range(0, tris.size(), 3):
                        for k in [0, 1, 2]:
                                var p: Vector2 = piece[tris[t + k]]
                                st.set_normal(Vector3.UP)
                                st.set_uv(Vector2(p.x * tile.x, p.y * tile.y))
                                st.add_vertex(to3(p, y1))
                # bottom (skip under ground floor slab; reversed order -> cross +Y)
                if not skip_bottom:
                        for t in range(0, tris.size(), 3):
                                for k in [2, 1, 0]:
                                        var p: Vector2 = piece[tris[t + k]]
                                        st.set_normal(Vector3.DOWN)
                                        st.set_uv(Vector2(p.x * tile.x, p.y * tile.y))
                                        st.add_vertex(to3(p, y0))
        # side band around outer polygon
        var n := poly.size()
        for i in n:
                var a := poly[i]
                var b := poly[(i + 1) % n]
                var d := (b - a).normalized()
                var n_out := Vector3(d.y, 0, -d.x)
                BFMeshUtilS.add_quad(st,
                        [to3(a, y0), to3(a, y1), to3(b, y1), to3(b, y0)], n_out,
                        [Vector2(a.x * tile.x, -y0 * tile.y), Vector2(a.x * tile.x, -y1 * tile.y),
                        Vector2(b.x * tile.x, -y1 * tile.y), Vector2(b.x * tile.x, -y0 * tile.y)])
        # hole side bands (faces look into the hole volume)
        for h in all_holes:
                var hr: Rect2 = h
                var hp := _rect_poly(hr)
                for i in 4:
                        var a: Vector2 = hp[i]
                        var b: Vector2 = hp[(i + 1) % 4]
                        var d := (b - a).normalized()
                        var n_in := Vector3(-d.y, 0, d.x)
                        BFMeshUtilS.add_quad(st,
                                [to3(a, y0), to3(b, y0), to3(b, y1), to3(a, y1)], n_in,
                                [Vector2(a.x * tile.x, -y0 * tile.y), Vector2(b.x * tile.x, -y0 * tile.y),
                                Vector2(b.x * tile.x, -y1 * tile.y), Vector2(a.x * tile.x, -y1 * tile.y)])


## Emits a thin floor finish surface for a rectangular room.
static func build_floor_finish(st: SurfaceTool, rect: Rect2, y: float, thick := 0.02, tile := Vector2(0.5, 0.5)) -> void:
        BFMeshUtilS.add_box(st, Transform3D(Basis.IDENTITY, Vector3(
                rect.position.x + rect.size.x * 0.5, y - thick * 0.5, rect.position.y + rect.size.y * 0.5)),
                Vector3(rect.size.x, thick, rect.size.y), tile, BFMeshUtilS.FACE_PY)
