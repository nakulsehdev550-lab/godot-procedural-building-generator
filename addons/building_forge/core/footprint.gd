@tool
class_name BFFootprint
extends Resource
## Building footprint: a closed 2D polygon in the XZ plane (local meters).
## Stored CCW (counter-clockwise, Godot convention for positive-area polygons
## on the XZ plane viewed from above with +Z down in UV space -> we store in
## standard Vector2 where +Y maps to +Z world).
##
## Provides shape generators (rect / L / T / U / circle / free polygon),
## validation, area/perimeter, insets and edge queries used by every builder.

@export var points: PackedVector2Array = PackedVector2Array([
        Vector2(-5, -4), Vector2(5, -4), Vector2(5, 4), Vector2(-5, 4)]):
        set(p):
                points = p
                _normalize_winding()
                emit_changed()

## If true the polygon is a full circle approximation (enables cone/dome roofs
## and spiral-window layout).
@export var is_circular := false


static func create(pts: PackedVector2Array) -> BFFootprint:
        var f := BFFootprint.new()
        f.points = pts
        return f


static func create_rect(w: float, d: float, center := Vector2.ZERO) -> BFFootprint:
        var h := Vector2(w, d) * 0.5
        return create(PackedVector2Array([
                center + Vector2(-h.x, -h.y), center + Vector2(h.x, -h.y),
                center + Vector2(h.x, h.y), center + Vector2(-h.x, h.y)]))


static func create_L(w: float, d: float, cut := 0.45) -> BFFootprint:
        # L-shape: bottom-right quadrant removed. cut = fraction of each dimension removed.
        var hw := w * 0.5
        var hd := d * 0.5
        var cx := w * (0.5 - cut)
        var cy := d * (0.5 - cut)
        return create(PackedVector2Array([
                Vector2(-hw, -hd), Vector2(cx, -hd), Vector2(cx, cy), Vector2(hw, cy),
                Vector2(hw, hd), Vector2(-hw, hd)]))


static func create_T(w: float, d: float, cut := 0.4) -> BFFootprint:
        var hw := w * 0.5
        var hd := d * 0.5
        var cx := w * (0.5 - cut)
        return create(PackedVector2Array([
                Vector2(-cx, -hd), Vector2(cx, -hd), Vector2(cx, cy_up(hd, cut)), Vector2(hw, cy_up(hd, cut)),
                Vector2(hw, hd), Vector2(-hw, hd)]))


static func cy_up(hd: float, cut: float) -> float:
        return -hd + d2(hd, cut)


static func d2(hd: float, cut: float) -> float:
        return (hd * 2.0) * (0.5 - cut)


static func create_U(w: float, d: float, cut := 0.35) -> BFFootprint:
        var hw := w * 0.5
        var hd := d * 0.5
        var cx := w * (0.5 - cut)
        var cy := d * (0.5 - cut)
        return create(PackedVector2Array([
                Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(cx, hd),
                Vector2(cx, cy), Vector2(-cx, cy), Vector2(-cx, hd), Vector2(-hw, hd)]))


static func create_circle(radius: float, center := Vector2.ZERO, segments := 0) -> BFFootprint:
        var n := segments if segments > 0 else maxi(24, int(radius * 4.0))
        var pts := PackedVector2Array()
        pts.resize(n)
        for i in n:
                var a := TAU * float(i) / float(n)
                pts[i] = center + Vector2(cos(a), sin(a)) * radius
        var f := create(pts)
        f.is_circular = true
        return f


static func create_oval(w: float, d: float, segments := 0) -> BFFootprint:
        var n := segments if segments > 0 else maxi(24, int(maxf(w, d) * 4.0))
        var pts := PackedVector2Array()
        pts.resize(n)
        for i in n:
                var a := TAU * float(i) / float(n)
                pts[i] = Vector2(cos(a) * w * 0.5, sin(a) * d * 0.5)
        var f := create(pts)
        f.is_circular = true
        return f


func _init() -> void:
        if points.size() >= 3:
                _normalize_winding()


func _normalize_winding() -> void:
        if points.size() >= 3 and Geometry2D.is_polygon_clockwise(points):
                points.reverse()


## --- Queries -------------------------------------------------------------

func size_xz() -> Vector2:
        if points.is_empty():
                return Vector2.ZERO
        var lo := points[0]
        var hi := points[0]
        for p in points:
                lo = lo.min(p)
                hi = hi.max(p)
        return hi - lo


func center_xz() -> Vector2:
        if points.is_empty():
                return Vector2.ZERO
        var lo := points[0]
        var hi := points[0]
        for p in points:
                lo = lo.min(p)
                hi = hi.max(p)
        return (lo + hi) * 0.5


func area() -> float:
        if points.size() < 3:
                return 0.0
        var a := 0.0
        var n := points.size()
        for i in n:
                var p0 := points[i]
                var p1 := points[(i + 1) % n]
                a += p0.x * p1.y - p1.x * p0.y
        return absf(a) * 0.5


func perimeter() -> float:
        var l := 0.0
        var n := points.size()
        for i in n:
                l += points[i].distance_to(points[(i + 1) % n])
        return l


func edge_count() -> int:
        return points.size()


## Returns edge i as [start, end] in world-local 2D.
func edge(i: int) -> Array:
        return [points[i], points[(i + 1) % points.size()]]


func edge_length(i: int) -> float:
        var e := edge(i)
        return (e[0] as Vector2).distance_to(e[1] as Vector2)


func edge_dir(i: int) -> Vector2:
        var e := edge(i)
        var d: Vector2 = (e[1] as Vector2) - (e[0] as Vector2)
        return d.normalized()


## Outward normal of edge i (polygon is CCW -> outward normal is direction rotated -90deg).
func edge_outward(i: int) -> Vector2:
        var d := edge_dir(i)
        return Vector2(d.y, -d.x)


## Longest edge index (used for entrance placement / gable orientation).
func longest_edge() -> int:
        var best := 0
        var best_len := -1.0
        for i in points.size():
                var l := edge_length(i)
                if l > best_len:
                        best_len = l
                        best = i
        return best


## --- Validation ----------------------------------------------------------

## Returns "" if valid, else a human-readable problem.
func validate() -> String:
        if points.size() < 3:
                return "Footprint needs at least 3 points"
        if area() < 1.0:
                return "Footprint too small (min 1 m2)"
        # self-intersection test: offsetting inward a little must not invert area
        var inner := inset(0.15)
        if inner.size() < 3 or _poly_area_signed(inner) <= 0.0:
                return "Footprint self-intersects or is too thin"
        var s := size_xz()
        if s.x > 200.0 or s.y > 200.0:
                return "Footprint larger than 200 m in a side"
        return ""


static func _poly_area_signed(poly: PackedVector2Array) -> float:
        if poly.size() < 3:
                return 0.0
        var a := 0.0
        for i in poly.size():
                var p0 := poly[i]
                var p1 := poly[(i + 1) % poly.size()]
                a += p0.x * p1.y - p1.x * p0.y
        return a * 0.5


## --- Geometry ops --------------------------------------------------------

## Shrinks the polygon inward by `delta` meters with miter joins.
## Falls back to progressively smaller deltas for thin footprints.
func inset(delta: float) -> PackedVector2Array:
        if delta <= 0.001:
                return points.duplicate()
        var try_deltas := [delta, delta * 0.7, delta * 0.45, delta * 0.25]
        for d in try_deltas:
                var res := Geometry2D.offset_polygon(points, d, Geometry2D.JOIN_MITER)
                if res.size() >= 3 and _poly_area_signed(res) > 0.0:
                        return res
        return points.duplicate()


## Grows outward (for roofs / balconies alignment).
func outset(delta: float) -> PackedVector2Array:
        if delta <= 0.001:
                return points.duplicate()
        var res := Geometry2D.offset_polygon(points, -delta, Geometry2D.JOIN_MITER)
        if res.size() >= 3:
                return res
        return points.duplicate()


## Snap all points to a grid (used by the draw tool).
func snap(grid: float) -> void:
        for i in points.size():
                points[i] = points[i].snapped(Vector2(grid, grid))
        _normalize_winding()
        emit_changed()


## Adds a point on the edge nearest to `at` (draw tool: click an edge).
## Returns the inserted index or -1.
func insert_point_on_nearest_edge(at: Vector2, max_dist := 1.5) -> int:
        var best_i := -1
        var best_t := 0.0
        var best_d := max_dist
        var n := points.size()
        for i in n:
                var a := points[i]
                var b := points[(i + 1) % n]
                var ab := b - a
                var l2 := ab.length_squared()
                if l2 < 0.0001:
                        continue
                var t := clampf((at - a).dot(ab) / l2, 0.02, 0.98)
                var proj := a + ab * t
                var d := proj.distance_to(at)
                if d < best_d:
                        best_d = d
                        best_i = i
                        best_t = t
        if best_i < 0:
                return -1
        points.insert(best_i + 1, points[best_i].lerp(points[(best_i + 1) % n], best_t))
        return best_i + 1


## Removes the vertex nearest to `at` if closer than max_dist.
func remove_point_near(at: Vector2, max_dist := 0.8) -> bool:
        if points.size() <= 3:
                return false
        var best_i := -1
        var best_d := max_dist
        for i in points.size():
                var d := points[i].distance_to(at)
                if d < best_d:
                        best_d = d
                        best_i = i
        if best_i < 0:
                return false
        points.remove_at(best_i)
        emit_changed()
        return true


## Distance from point to polygon edge (for interior tests with tolerance).
func distance_to_edge(at: Vector2) -> float:
        var best := INF
        var n := points.size()
        for i in n:
                var a := points[i]
                var b := points[(i + 1) % n]
                var ab := b - a
                var l2 := ab.length_squared()
                var t := clampf((at - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0
                best = minf(best, (a + ab * t).distance_to(at))
        return best
