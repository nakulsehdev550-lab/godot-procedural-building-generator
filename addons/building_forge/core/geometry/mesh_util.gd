@tool
class_name BFMeshUtil
extends RefCounted
## Low-level mesh construction helpers for BuildingForge.
##
## All builders emit CCW-wound triangles (Godot front faces) with outward
## normals, world-consistent UVs and optional per-face emission so walls can
## skip hidden faces. Everything is deterministic so regeneration produces
## byte-identical geometry.

const FACE_PX := 1
const FACE_NX := 2
const FACE_PY := 4
const FACE_NY := 8
const FACE_PZ := 16
const FACE_NZ := 32
const FACE_ALL := 63
## Faces visible from outside (skip fully hidden interior faces of niche boxes)
const FACE_NO_BOTTOM := FACE_ALL & ~FACE_NY

const DEGENERATE_EPS := 0.0000001


static func new_st() -> SurfaceTool:
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        return st


## Adds an axis-aligned-in-local-space box, transformed by xf.
## uv_tile: UV units per meter. UVs derive from LOCAL coordinates so tiling is
## continuous across all boxes sharing a material (world projection happens by
## keeping the building axis-aligned at generation time).
static func add_box(st: SurfaceTool, xf: Transform3D, size: Vector3, uv_tile := Vector2(0.5, 0.5), faces := FACE_ALL, uv_offset := Vector2.ZERO) -> void:
        var h := size * 0.5
        var nx := -size.x * uv_tile.x * 0.5 + uv_offset.x
        var px := size.x * uv_tile.x * 0.5 + uv_offset.x
        var ny := -size.y * uv_tile.y * 0.5 + uv_offset.y
        var py := size.y * uv_tile.y * 0.5 + uv_offset.y
        # Per face: 4 corners (CCW from outside) then uv per corner.
        if faces & FACE_PX:
                _emit_quad(st, [
                        _v3(h.x, -h.y, h.z), _v3(h.x, -h.y, -h.z), _v3(h.x, h.y, -h.z), _v3(h.x, h.y, h.z)],
                        Vector3.RIGHT, [Vector2(px, py), Vector2(nx, py), Vector2(nx, ny), Vector2(px, ny)], xf)
        if faces & FACE_NX:
                _emit_quad(st, [
                        _v3(-h.x, -h.y, -h.z), _v3(-h.x, -h.y, h.z), _v3(-h.x, h.y, h.z), _v3(-h.x, h.y, -h.z)],
                        Vector3.LEFT, [Vector2(nx, py), Vector2(px, py), Vector2(px, ny), Vector2(nx, ny)], xf)
        if faces & FACE_PY:
                _emit_quad(st, [
                        _v3(h.x, h.y, h.z), _v3(h.x, h.y, -h.z), _v3(-h.x, h.y, -h.z), _v3(-h.x, h.y, h.z)],
                        Vector3.UP, [Vector2(px, py), Vector2(px, ny), Vector2(nx, ny), Vector2(nx, py)], xf)
        if faces & FACE_NY:
                _emit_quad(st, [
                        _v3(-h.x, -h.y, -h.z), _v3(h.x, -h.y, -h.z), _v3(h.x, -h.y, h.z), _v3(-h.x, -h.y, h.z)],
                        Vector3.DOWN, [Vector2(nx, ny), Vector2(px, ny), Vector2(px, py), Vector2(nx, py)], xf)
        if faces & FACE_PZ:
                _emit_quad(st, [
                        _v3(h.x, -h.y, h.z), _v3(h.x, h.y, h.z), _v3(-h.x, h.y, h.z), _v3(-h.x, -h.y, h.z)],
                        Vector3.BACK, [Vector2(px, py), Vector2(px, ny), Vector2(nx, ny), Vector2(nx, py)], xf)
        if faces & FACE_NZ:
                _emit_quad(st, [
                        _v3(-h.x, -h.y, -h.z), _v3(-h.x, h.y, -h.z), _v3(h.x, h.y, -h.z), _v3(h.x, -h.y, -h.z)],
                        Vector3.FORWARD, [Vector2(nx, py), Vector2(nx, ny), Vector2(px, ny), Vector2(px, py)], xf)


static func _v3(x: float, y: float, z: float) -> Vector3:
        return Vector3(x, y, z)


## GODOT WINDING RULE (verified against BoxMesh): front faces are CLOCKWISE,
## i.e. (p1-p0) x (p2-p0) points OPPOSITE the outward normal.
## Callers pass quad points in natural CCW-from-outside order; we flip the
## emission order here so every caller uses the same math convention.
static func _emit_quad(st: SurfaceTool, pts: Array, n: Vector3, uvs: Array, xf: Transform3D) -> void:
        var nb := (xf.basis * n).normalized()
        var idx := [0, 2, 1, 0, 3, 2]
        for i in idx:
                var p: Vector3 = xf * (pts[i] as Vector3)
                st.set_normal(nb)
                st.set_uv(uvs[i])
                st.add_vertex(p)


## Quad/triangle from explicit points + explicit uv per point (wall bands use
## this). pts in CCW-from-outside order (3 or 4 points); emission is flipped
## internally to Godot's clockwise front-face rule.
static func add_quad(st: SurfaceTool, pts: Array, n: Vector3, uvs: Array) -> void:
        var nn := n.normalized()
        if pts.size() == 3:
                for i in [0, 2, 1]:
                        st.set_normal(nn)
                        st.set_uv(uvs[i])
                        st.add_vertex(pts[i])
                return
        for i in [0, 2, 1, 0, 3, 2]:
                st.set_normal(nn)
                st.set_uv(uvs[i])
                st.add_vertex(pts[i])


## DOUBLE-SIDED quad: emits the quad plus a reversed copy with the negated
## normal. Use for roof surfaces that are legitimately visible from BOTH
## sides (shed slopes seen from behind, gable end walls read through openings)
## - kills the whole single-sided culling guessing game for those pieces.
static func add_quad_double(st: SurfaceTool, pts: Array, n: Vector3, uvs: Array) -> void:
        add_quad(st, pts, n, uvs)
        var rev := pts.duplicate()
        rev.reverse()
        var ruv := uvs.duplicate()
        ruv.reverse()
        add_quad(st, rev, -n, ruv)


## Cylinder along local Y, centered at origin of xf (base at -h, top at +h).
static func add_cylinder(st: SurfaceTool, xf: Transform3D, radius: float, height: float, segments := 12, uv_tile := Vector2(0.5, 0.5), caps := true, smooth_side := true) -> void:
        var h := height * 0.5
        if smooth_side:
                st.set_smooth_group(1)
        for i in segments:
                var a0 := TAU * float(i) / float(segments)
                var a1 := TAU * float(i + 1) / float(segments)
                var p0 := Vector3(cos(a0) * radius, -h, sin(a0) * radius)
                var p1 := Vector3(cos(a1) * radius, -h, sin(a1) * radius)
                var p2 := Vector3(cos(a1) * radius, h, sin(a1) * radius)
                var p3 := Vector3(cos(a0) * radius, h, sin(a0) * radius)
                var n0 := Vector3(cos(a0), 0, sin(a0))
                var n1 := Vector3(cos(a1), 0, sin(a1))
                var u0 := a0 * radius * uv_tile.x
                var u1 := a1 * radius * uv_tile.x
                var quad_pts := [p0, p1, p2, p3]
                var quad_uvs := [Vector2(u0, h * uv_tile.y), Vector2(u1, h * uv_tile.y), Vector2(u1, -h * uv_tile.y), Vector2(u0, -h * uv_tile.y)]
                var quad_ns := [n0, n1, n1, n0]
                for k in [0, 1, 2, 0, 2, 3]:
                        st.set_normal((xf.basis * quad_ns[k]).normalized())
                        st.set_uv(quad_uvs[k])
                        st.add_vertex(xf * (quad_pts[k] as Vector3))
        st.set_smooth_group(0)
        if caps:
                # Top cap (fan, Godot-CW seen from +Y)
                var uvc := Vector2(0.5 * radius * uv_tile.x, 0.5 * radius * uv_tile.y)
                for i in segments:
                        var a0 := TAU * float(i) / float(segments)
                        var a1 := TAU * float(i + 1) / float(segments)
                        var t0 := Vector3(cos(a0) * radius, h, sin(a0) * radius)
                        var t1 := Vector3(cos(a1) * radius, h, sin(a1) * radius)
                        st.set_normal(xf.basis * Vector3.UP)
                        st.set_uv(uvc)
                        st.add_vertex(xf * Vector3(0, h, 0))
                        st.set_uv(uvc)
                        st.add_vertex(xf * t0)
                        st.set_uv(uvc)
                        st.add_vertex(xf * t1)
                # Bottom cap (Godot-CW seen from -Y)
                for i in segments:
                        var a0 := TAU * float(i) / float(segments)
                        var a1 := TAU * float(i + 1) / float(segments)
                        var b0 := Vector3(cos(a0) * radius, -h, sin(a0) * radius)
                        var b1 := Vector3(cos(a1) * radius, -h, sin(a1) * radius)
                        st.set_normal(xf.basis * Vector3.DOWN)
                        st.set_uv(uvc)
                        st.add_vertex(xf * Vector3(0, -h, 0))
                        st.set_uv(uvc)
                        st.add_vertex(xf * b1)
                        st.set_uv(uvc)
                        st.add_vertex(xf * b0)


## Horizontal ring railing between two 3D points at height h over segment a->b.
## Posts every ~1.1 m, top rail + mid rail boxes, thin profile.
static func add_railing(st: SurfaceTool, a: Vector3, b: Vector3, base_y: float, height := 1.05, thickness := 0.05, tile := Vector2(0.5, 0.5)) -> void:
        var dir := (b - a)
        var len_m := dir.length()
        if len_m < 0.05:
                return
        dir = dir / len_m
        var rail_xf_basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized() * -1.0)
        # posts
        var post_count := maxi(2, int(ceil(len_m / 1.1)) + 1)
        for i in post_count:
                var t := float(i) / float(post_count - 1)
                var p := a.lerp(b, t)
                add_box(st, Transform3D(rail_xf_basis, Vector3(p.x, base_y + height * 0.5, p.z)) * Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(thickness, height, thickness), tile)
        # top rail + mid rail (along full span, slightly longer to reach post centers)
        var mid := Transform3D(rail_xf_basis, Vector3((a.x + b.x) * 0.5, base_y + height - thickness * 0.5, (a.z + b.z) * 0.5))
        add_box(st, mid, Vector3(len_m, thickness, thickness), tile)
        var mid2 := Transform3D(rail_xf_basis, Vector3((a.x + b.x) * 0.5, base_y + height * 0.5, (a.z + b.z) * 0.5))
        add_box(st, mid2, Vector3(len_m, thickness * 0.7, thickness * 0.7), tile)


## Finalizes a SurfaceTool into an ArrayMesh.
## NOTE: normals are set explicitly by all builders (Godot convention:
## normal = outward, winding = CW front) - do NOT call generate_normals()
## here, it averages normals across faces and ruins flat-shaded walls.
## Returns null when the tool has no geometry.
static func commit(st: SurfaceTool, mat: Material = null) -> ArrayMesh:
        st.index()
        var mesh := st.commit()
        if mesh == null or mesh.get_surface_count() == 0:
                return null
        if mat != null:
                mesh.surface_set_material(0, mat)
        return mesh


static func aabb_of(mesh: Mesh) -> AABB:
        return mesh.get_aabb()


## Validates: no NaN/inf vertices, no degenerate triangles, sane uv bounds.
## Returns Array of error strings (empty = valid).
static func validate_mesh(mesh: Mesh, max_uv := 64.0) -> Array:
        var errs: Array = []
        if mesh == null:
                return ["null mesh"]
        for s in mesh.get_surface_count():
                var arrays := mesh.surface_get_arrays(s)
                var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                if verts.is_empty():
                        errs.append("surface %d has no vertices" % s)
                        continue
                var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
                var tri_count := (indices.size() if indices.size() > 0 else verts.size()) / 3
                if tri_count == 0:
                        errs.append("surface %d has no triangles" % s)
                for v in verts:
                        if is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or is_inf(v.x) or is_inf(v.y) or is_inf(v.z):
                                errs.append("surface %d has NaN/inf vertex" % s)
                                break
                var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
                if uvs != null:
                        for uv in uvs:
                                if absf(uv.x) > max_uv or absf(uv.y) > max_uv:
                                        errs.append("surface %d has out-of-range UV %s" % [s, uv])
                                        break
                # degenerate triangle check (sample first 512 tris for speed)
                var step := maxi(1, tri_count / 512)
                for t in range(0, tri_count, step):
                        var i0 := t * 3
                        var a: Vector3 = verts[indices[i0]] if indices.size() > 0 else verts[i0]
                        var b: Vector3 = verts[indices[i0 + 1]] if indices.size() > 0 else verts[i0 + 1]
                        var c: Vector3 = verts[indices[i0 + 2]] if indices.size() > 0 else verts[i0 + 2]
                        var cr := (b - a).cross(c - a)
                        if cr.length() < DEGENERATE_EPS:
                                errs.append("surface %d has degenerate triangle at %d" % [s, t])
                                break
        return errs
