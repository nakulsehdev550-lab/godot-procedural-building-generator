@tool
class_name BFRoomPartitioner
extends RefCounted
## Partitions the floor interior into rectangular rooms via BSP splits,
## reserving a stairwell cell. Produces rooms + wall segments + door
## connections (spanning tree over adjacency, so every room is reachable).

const MIN_ROOM := 2.2          # m, min room dimension
const INT_WALL_T := 0.10       # interior wall thickness


class Room:
        extends RefCounted
        var rect: Rect2
        var id: int
        var kind: String = "living"   # living / bedroom / kitchen / bath / office / stair
        var doors: Array = []          # of {pos: Vector2, dir: Vector2}


class WallSeg:
        extends RefCounted
        var a: Vector2
        var b: Vector2
        var door: Dictionary = {}      # empty = no door


## Returns { rooms: Array[Room], walls: Array[WallSeg], interior: Rect2 }
## interior_pts: the actual interior polygon - candidate rooms must fit
## inside it (bbox alone would place rooms in L/T/U notches!).
static func partition(bounds: Rect2, interior_pts: PackedVector2Array, stair_cell: Rect2,
                max_room_area: float, rng: RandomNumberGenerator) -> Dictionary:
        var rooms: Array = []
        var queue: Array = [bounds.grow(-0.05)]
        var next_id := 0
        var guard := 0
        while queue.is_empty() == false and guard < 8192:
                guard += 1
                var r: Rect2 = queue.pop_back()
                if r.get_area() < 1.2 or r.size.x < MIN_ROOM - 0.4 or r.size.y < MIN_ROOM - 0.4:
                        continue
                # rooms must fit the real interior polygon
                if not rect_in_polygon(r, interior_pts):
                        # keep carving: split into quadrants and test each
                        var hx := r.size.x * 0.5
                        var hy := r.size.y * 0.5
                        queue.append(Rect2(r.position, Vector2(hx, hy)))
                        queue.append(Rect2(r.position + Vector2(hx, 0), Vector2(hx, hy)))
                        queue.append(Rect2(r.position + Vector2(0, hy), Vector2(hx, hy)))
                        queue.append(Rect2(r.position + Vector2(hx, hy), Vector2(hx, hy)))
                        continue
                var clipped := r.intersection(stair_cell)
                if clipped.get_area() > 0.3:
                        var cuts := _cuts_around(r, stair_cell)
                        for c in cuts:
                                queue.append(c)
                        continue
                if r.get_area() <= max_room_area or r.size.x < MIN_ROOM * 2.0 or r.size.y < MIN_ROOM * 2.0:
                        if r.size.x >= MIN_ROOM - 0.2 and r.size.y >= MIN_ROOM - 0.2:
                                var room := Room.new()
                                room.rect = r
                                room.id = next_id
                                next_id += 1
                                rooms.append(room)
                else:
                        var horizontal := r.size.x > r.size.y
                        var axis_len := r.size.x if horizontal else r.size.y
                        var t := rng.randf_range(0.35, 0.65)
                        var cut := axis_len * t
                        cut = clampf(cut, MIN_ROOM, axis_len - MIN_ROOM)
                        if horizontal:
                                queue.append(Rect2(r.position, Vector2(cut, r.size.y)))
                                queue.append(Rect2(r.position + Vector2(cut, 0), Vector2(r.size.x - cut, r.size.y)))
                        else:
                                queue.append(Rect2(r.position, Vector2(r.size.x, cut)))
                                queue.append(Rect2(r.position + Vector2(0, cut), Vector2(r.size.x, r.size.y - cut)))
        # walls between room pairs + boundary walls facing voids/stair
        var walls: Array = []
        var adj := {}  # "idA|idB" -> WallSeg
        for i in rooms.size():
                for j in range(i + 1, rooms.size()):
                        var ra: Room = rooms[i]
                        var rb: Room = rooms[j]
                        var seg := _shared_wall(ra.rect, rb.rect)
                        if seg != null:
                                adj["%d|%d" % [ra.id, rb.id]] = seg
                                walls.append(seg)
        # boundary walls: room edge not touching another room and not near polygon edge
        for ra in rooms:
                for side in 4:
                        var seg2 := _boundary_wall(ra, rooms, side)
                        if seg2 != null:
                                walls.append(seg2)
        # doors: spanning tree over room adjacency from the room nearest stair bottom
        if rooms.size() > 0:
                _place_doors(rooms, adj, stair_cell, rng)
        return {"rooms": rooms, "walls": walls, "interior": bounds}


## True when the rect fits fully inside the polygon (corners + edge midpoints
## + center inside, with a small margin so walls don't poke through facades).
static func rect_in_polygon(r: Rect2, pts: PackedVector2Array, margin := 0.14) -> bool:
        if pts.size() < 3:
                return false
        var rr := r.grow(-margin)
        if rr.get_area() <= 0.0:
                return false
        var probes := PackedVector2Array([
                rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y),
                rr.get_center(),
                Vector2(rr.get_center().x, rr.position.y), Vector2(rr.get_center().x, rr.end.y),
                Vector2(rr.position.x, rr.get_center().y), Vector2(rr.end.x, rr.get_center().y)])
        for p in probes:
                if not Geometry2D.is_point_in_polygon(p, pts):
                        return false
        return true


static func _cuts_around(r: Rect2, cell: Rect2) -> Array:
        var out: Array = []
        # guillotine the room into up-to-4 strips around the cell intersection
        var ix0 := maxf(r.position.x, cell.position.x)
        var ix1 := minf(r.end.x, cell.end.x)
        var iy0 := maxf(r.position.y, cell.position.y)
        var iy1 := minf(r.end.y, cell.end.y)
        if ix0 - r.position.x > MIN_ROOM:
                out.append(Rect2(r.position, Vector2(ix0 - r.position.x, r.size.y)))
        if r.end.x - ix1 > MIN_ROOM:
                out.append(Rect2(Vector2(ix1, r.position.y), Vector2(r.end.x - ix1, r.size.y)))
        # middle band (y range) minus cell x-range
        var mid := Rect2(Vector2(ix0, r.position.y), Vector2(ix1 - ix0, r.size.y))
        if iy0 - mid.position.y > MIN_ROOM:
                out.append(Rect2(mid.position, Vector2(mid.size.x, iy0 - mid.position.y)))
        if mid.end.y - iy1 > MIN_ROOM:
                out.append(Rect2(Vector2(mid.position.x, iy1), Vector2(mid.size.x, mid.end.y - iy1)))
        return out


## If rects share an edge overlap >= 1.2 m, returns a WallSeg on the seam.
static func _shared_wall(ra: Rect2, rb: Rect2) -> WallSeg:
        # vertical seam?
        if absf(ra.end.x - rb.position.x) < 0.02 or absf(rb.end.x - ra.position.x) < 0.02:
                var x := ra.end.x if absf(ra.end.x - rb.position.x) < 0.02 else rb.end.x
                var y0 := maxf(ra.position.y, rb.position.y)
                var y1 := minf(ra.end.y, rb.end.y)
                if y1 - y0 >= 1.2:
                        var s := WallSeg.new()
                        s.a = Vector2(x, y0)
                        s.b = Vector2(x, y1)
                        return s
        if absf(ra.end.y - rb.position.y) < 0.02 or absf(rb.end.y - ra.position.y) < 0.02:
                var y := ra.end.y if absf(ra.end.y - rb.position.y) < 0.02 else rb.end.y
                var x0 := maxf(ra.position.x, rb.position.x)
                var x1 := minf(ra.end.x, rb.end.x)
                if x1 - x0 >= 1.2:
                        var s := WallSeg.new()
                        s.a = Vector2(x0, y)
                        s.b = Vector2(x1, y)
                        return s
        return null


## Room edge that faces neither another room nor (approximately) the polygon
## edge -> needs a closing wall (faces void / stair shaft).
static func _boundary_wall(ra: Room, rooms: Array, side: int) -> WallSeg:
        var r := ra.rect
        var seg: WallSeg = null
        match side:
                0:
                        if _edge_facing_void(Vector2(r.get_center().x, r.position.y), rooms, ra):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.position.x, r.position.y)
                                seg.b = Vector2(r.end.x, r.position.y)
                1:
                        if _edge_facing_void(Vector2(r.end.x, r.get_center().y), rooms, ra):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.end.x, r.position.y)
                                seg.b = Vector2(r.end.x, r.end.y)
                2:
                        if _edge_facing_void(Vector2(r.get_center().x, r.end.y), rooms, ra):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.end.x, r.end.y)
                                seg.b = Vector2(r.position.x, r.end.y)
                3:
                        if _edge_facing_void(Vector2(r.position.x, r.get_center().y), rooms, ra):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.position.x, r.end.y)
                                seg.b = Vector2(r.position.x, r.position.y)
        return seg


static func _edge_facing_void(edge_center: Vector2, rooms: Array, self_room: Room) -> bool:
        # is there another room on the other side of this edge center?
        var probe_dirs := [Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0, 0.3), Vector2(0, -0.3)]
        for d: Vector2 in probe_dirs:
                var p := edge_center + d
                for rb in rooms:
                        if rb == self_room:
                                continue
                        if (rb as Room).rect.has_point(p):
                                return false
        # if a room contains the center itself, edge is interior-adjacent: not void
        for rb2 in rooms:
                if rb2 != self_room and (rb2 as Room).rect.has_point(edge_center):
                        return false
        return true


static func _place_doors(rooms: Array, adj: Dictionary, stair_cell: Rect2, rng: RandomNumberGenerator) -> void:
        if rooms.is_empty():
                return
        # BFS spanning tree from room nearest to stair bottom
        var start: Room = rooms[0]
        var best_d := INF
        for r in rooms:
                var d: float = (r as Room).rect.get_center().distance_to(stair_cell.get_center())
                if d < best_d:
                        best_d = d
                        start = r
        var connected := {start.id: true}
        var frontier: Array = [start]
        while frontier.size() > 0:
                var cur: Room = frontier.pop_front()
                for key in adj:
                        var parts := (key as String).split("|")
                        var ia := int(parts[0])
                        var ib := int(parts[1])
                        var other: Room = null
                        if ia == cur.id and not connected.has(ib):
                                for r in rooms:
                                        if (r as Room).id == ib:
                                                other = r
                        elif ib == cur.id and not connected.has(ia):
                                for r2 in rooms:
                                        if (r2 as Room).id == ia:
                                                other = r2
                        if other != null:
                                var seg: WallSeg = adj[key]
                                seg.door = _door_on_seg(seg, rng)
                                connected[other.id] = true
                                frontier.append(other)
        # a few extra doors for flow (10% chance per remaining adjacency)
        for key2 in adj:
                var seg2: WallSeg = adj[key2]
                if seg2.door.is_empty() and rng.randf() < 0.12:
                        seg2.door = _door_on_seg(seg2, rng)


static func _door_on_seg(seg: WallSeg, rng: RandomNumberGenerator) -> Dictionary:
        var d := seg.b - seg.a
        var len_m := d.length()
        var dw := 0.92
        var t := rng.randf_range(0.3, 0.7)
        var c := seg.a + d * t
        var dir := Vector2(d.y, -d.x).normalized()  # perpendicular = passage direction
        return {"a": c - d.normalized() * dw * 0.5, "b": c + d.normalized() * dw * 0.5, "dir": dir, "w": dw}


## Assigns room kinds for a floor.
static func assign_kinds(rooms: Array, floor_i: int, rng: RandomNumberGenerator, has_stair_room: bool) -> void:
        if rooms.is_empty():
                return
        var sorted := rooms.duplicate()
        sorted.sort_custom(func(a, b): return (a as Room).rect.get_area() > (b as Room).rect.get_area())
        # stair room = the one containing stair cell gets kind stair (set by caller)
        var small: Array = []
        var large: Array = []
        for r in sorted:
                if (r as Room).kind == "stair":
                        continue
                if (r as Room).rect.get_area() < 6.5:
                        small.append(r)
                else:
                        large.append(r)
        if floor_i == 0:
                if large.size() > 0:
                        (large[0] as Room).kind = "living"
                if large.size() > 1:
                        (large[1] as Room).kind = "kitchen"
                if large.size() > 2:
                        (large[2] as Room).kind = "dining"
        else:
                if large.size() > 0:
                        (large[0] as Room).kind = "bedroom"
                if large.size() > 1:
                        (large[1] as Room).kind = "bedroom"
                if large.size() > 2 and floor_i % 2 == 0:
                        (large[2] as Room).kind = "office"
        # one bathroom per floor from small rooms
        if small.size() > 0:
                (small[0] as Room).kind = "bath"
        for r in sorted:
                if (r as Room).kind == "living":
                        (r as Room).kind = "bedroom"
