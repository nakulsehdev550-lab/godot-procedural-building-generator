@tool
class_name BFRoomPartitioner
extends RefCounted
## Partitions the floor interior into rectangular rooms via BSP splits,
## treating the stairwell as a first-class room so the spanning tree doors
## always reach it. Produces rooms + wall segments + door connections.
##
## Connectivity contract (v1.1):
##  - every room, including the stair hall, is reachable through doors
##  - rooms extend to the inner face of the exterior walls; no wall skin
##    is built along the facade (windows / balcony doors open into rooms)
##  - door edges respect soft prohibition rules (bedroom-bedroom and
##    bedroom-bathroom doors are a last resort, matching real plans)

const MIN_ROOM := 2.2          # m, min room dimension
const INT_WALL_T := 0.10       # interior wall thickness


class Room:
        extends RefCounted
        var rect: Rect2
        var id: int
        var kind: String = "living"   # living / bedroom / kitchen / dining / bath / office / lounge / storage / stair
        var doors: Array = []          # of {pos: Vector2, dir: Vector2}


class WallSeg:
        extends RefCounted
        var a: Vector2
        var b: Vector2
        var door: Dictionary = {}      # empty = no door
        var room_a: int = -1           # room id on side A (-1 = void/shaft/exterior)
        var room_b: int = -1           # room id on side B


## Returns { rooms: Array[Room], walls: Array[WallSeg], interior: Rect2 }
## interior_pts: the actual interior polygon - candidate rooms must fit
## inside it (bbox alone would place rooms in L/T/U notches!).
static func partition(bounds: Rect2, interior_pts: PackedVector2Array, stair_cell: Rect2,
                max_room_area: float, rng: RandomNumberGenerator) -> Dictionary:
        var rooms: Array = []
        var next_id := 0
        # the stairwell is claimed FIRST as one whole room - no BSP split lines
        # cut through the shaft, and adjacent rooms share walls with it so
        # doors always reach the stairs
        if stair_cell.get_area() > 0.5:
                var sr := Room.new()
                sr.rect = stair_cell
                sr.id = next_id
                next_id += 1
                sr.kind = "stair"
                rooms.append(sr)
        var queue: Array = [bounds.grow(-0.02)]
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
                var inter := r.intersection(stair_cell)
                if inter.get_area() > 0.3:
                        # carve strips around the stair cell; the cell itself
                        # belongs to the pre-created stair room
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
        # walls between room pairs + boundary walls facing interior voids
        var walls: Array = []
        var adj := {}  # "idA|idB" -> WallSeg
        for i in rooms.size():
                for j in range(i + 1, rooms.size()):
                        var ra: Room = rooms[i]
                        var rb: Room = rooms[j]
                        var seg := _shared_wall(ra.rect, rb.rect)
                        if seg != null:
                                seg.room_a = ra.id
                                seg.room_b = rb.id
                                adj["%d|%d" % [ra.id, rb.id]] = seg
                                walls.append(seg)
        # boundary walls: only where the edge faces an INTERIOR void (stair shaft
        # remainder / unpartitioned sliver). Edges along the facade are sealed by
        # the exterior band itself and must stay open to it.
        for ra in rooms:
                for side in 4:
                        var seg2 := _boundary_wall(ra, rooms, side, interior_pts)
                        if seg2 != null:
                                seg2.room_a = ra.id
                                walls.append(seg2)
        # doors: spanning tree from the stair hall -> every room reachable
        if rooms.size() > 0:
                _place_doors(rooms, adj, stair_cell, rng)
                _verify_connectivity(rooms, adj, rng)
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


## Room edge that faces an interior void (not another room, and the probe
## stays INSIDE the interior polygon). Facade-facing edges return null: the
## exterior wall band is the wall there, and rooms must open onto it.
static func _boundary_wall(ra: Room, rooms: Array, side: int, interior_pts: PackedVector2Array) -> WallSeg:
        var r := ra.rect
        var seg: WallSeg = null
        match side:
                0:
                        if _edge_facing_void(Vector2(r.get_center().x, r.position.y), Vector2(0, -1), rooms, ra, interior_pts):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.position.x, r.position.y)
                                seg.b = Vector2(r.end.x, r.position.y)
                1:
                        if _edge_facing_void(Vector2(r.end.x, r.get_center().y), Vector2(1, 0), rooms, ra, interior_pts):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.end.x, r.position.y)
                                seg.b = Vector2(r.end.x, r.end.y)
                2:
                        if _edge_facing_void(Vector2(r.get_center().x, r.end.y), Vector2(0, 1), rooms, ra, interior_pts):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.end.x, r.end.y)
                                seg.b = Vector2(r.position.x, r.end.y)
                3:
                        if _edge_facing_void(Vector2(r.position.x, r.get_center().y), Vector2(-1, 0), rooms, ra, interior_pts):
                                seg = WallSeg.new()
                                seg.a = Vector2(r.position.x, r.end.y)
                                seg.b = Vector2(r.position.x, r.position.y)
        return seg


static func _edge_facing_void(edge_center: Vector2, outward: Vector2, rooms: Array, self_room: Room, interior_pts: PackedVector2Array) -> bool:
        # outside the interior polygon -> that's the exterior wall, not a void
        if not Geometry2D.is_point_in_polygon(edge_center + outward * 0.3, interior_pts):
                return false
        # is there another room on the other side of this edge center?
        for d: Vector2 in [outward * 0.3, Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0, 0.3), Vector2(0, -0.3)]:
                var p := edge_center + d
                for rb in rooms:
                        if rb == self_room:
                                continue
                        if (rb as Room).rect.has_point(p):
                                return false
        return true


## Door-edge soft prohibitions (from floor-plan research): these pairs get
## doors only when no better edge exists.
static func _door_penalty(a: Room, b: Room) -> int:
        var bad := ["bedroom", "bath", "storage"]
        var pa := bad.has(a.kind)
        var pb := bad.has(b.kind)
        if pa and pb:
                return 10
        # kitchen next to bedroom is uncommon
        if (a.kind == "kitchen" and b.kind == "bedroom") or (a.kind == "bedroom" and b.kind == "kitchen"):
                return 6
        # prefer doors into the stair hall and social rooms
        var social := ["stair", "living", "dining", "lounge", "kitchen", "office"]
        if social.has(a.kind) or social.has(b.kind):
                return 0
        return 2


static func _place_doors(rooms: Array, adj: Dictionary, stair_cell: Rect2, rng: RandomNumberGenerator) -> void:
        if rooms.is_empty():
                return
        # BFS spanning tree starting from a stair room (falls back to the room
        # nearest the stair). Among candidate edges prefer low door-penalty pairs.
        var start: Room = null
        for r in rooms:
                if (r as Room).kind == "stair":
                        start = r
                        break
        if start == null:
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
                # gather candidate edges from cur to unconnected rooms, sort by penalty
                var cands: Array = []
                for key in adj:
                        var parts := (key as String).split("|")
                        var ia := int(parts[0])
                        var ib := int(parts[1])
                        var other: Room = null
                        if ia == cur.id and not connected.has(ib):
                                other = _room_by_id(rooms, ib)
                        elif ib == cur.id and not connected.has(ia):
                                other = _room_by_id(rooms, ia)
                        if other != null:
                                cands.append({"key": key, "room": other, "pen": _door_penalty(cur, other)})
                cands.sort_custom(func(x, y):
                        if x.pen != y.pen:
                                return x.pen < y.pen
                        return (x.room as Room).rect.get_area() > (y.room as Room).rect.get_area())
                for c in cands:
                        if connected.has((c.room as Room).id):
                                continue
                        var seg: WallSeg = adj[c.key]
                        seg.door = _door_on_seg(seg, rng)
                        connected[(c.room as Room).id] = true
                        frontier.append(c.room)
        # a few extra doors for flow (only between social rooms)
        for key2 in adj:
                var seg2: WallSeg = adj[key2]
                if seg2.door.is_empty() and rng.randf() < 0.12:
                        var ra := _room_by_id(rooms, int((key2 as String).split("|")[0]))
                        var rb := _room_by_id(rooms, int((key2 as String).split("|")[1]))
                        if ra != null and rb != null and _door_penalty(ra, rb) <= 2:
                                seg2.door = _door_on_seg(seg2, rng)


## Safety net: if any room ended up unreachable, punch a door on a shared
## wall to a connected room until the graph is fully connected.
static func _verify_connectivity(rooms: Array, adj: Dictionary, rng: RandomNumberGenerator) -> void:
        if rooms.is_empty():
                return
        var start: Room = rooms[0]
        for r in rooms:
                if (r as Room).kind == "stair":
                        start = r
                        break
        for _iter in rooms.size() + 2:
                var connected := {start.id: true}
                var frontier: Array = [start]
                while frontier.size() > 0:
                        var cur: Room = frontier.pop_front()
                        for key in adj:
                                var seg: WallSeg = adj[key]
                                if seg.door.is_empty():
                                        continue
                                var ia := int((key as String).split("|")[0])
                                var ib := int((key as String).split("|")[1])
                                if ia == cur.id and not connected.has(ib):
                                        connected[ib] = true
                                        frontier.append(_room_by_id(rooms, ib))
                                elif ib == cur.id and not connected.has(ia):
                                        connected[ia] = true
                                        frontier.append(_room_by_id(rooms, ia))
                if connected.size() >= rooms.size():
                        return
                # connect one stranded room
                for r in rooms:
                        if not connected.has((r as Room).id):
                                var best_key := ""
                                for key in adj:
                                        var parts := (key as String).split("|")
                                        var ia2 := int(parts[0])
                                        var ib2 := int(parts[1])
                                        if (ia2 == (r as Room).id and connected.has(ib2)) or (ib2 == (r as Room).id and connected.has(ia2)):
                                                best_key = key
                                                break
                                if best_key != "":
                                        var seg3: WallSeg = adj[best_key]
                                        if seg3.door.is_empty():
                                                seg3.door = _door_on_seg(seg3, rng)
                                break


static func _room_by_id(rooms: Array, id: int) -> Room:
        for r in rooms:
                if (r as Room).id == id:
                        return r
        return null


static func _door_on_seg(seg: WallSeg, rng: RandomNumberGenerator) -> Dictionary:
        var d := seg.b - seg.a
        var len_m := d.length()
        var dw := 0.92
        var t := rng.randf_range(0.3, 0.7)
        var c := seg.a + d * t
        var dir := Vector2(d.y, -d.x).normalized()  # perpendicular = passage direction
        return {"a": c - d.normalized() * dw * 0.5, "b": c + d.normalized() * dw * 0.5, "dir": dir, "w": dw}


## Assigns room kinds for one floor using a realistic program:
## ground: living + kitchen + dining + bedrooms + guaranteed bath
## upper:  bedrooms + guaranteed bath + occasional lounge / office / storage
## office towers: offices + meeting room + bath on every floor
## stair rooms must already be marked (kind == "stair").
static func assign_kinds(rooms: Array, floor_i: int, floor_count: int, rng: RandomNumberGenerator, office_building := false) -> void:
        if rooms.is_empty():
                return
        var work: Array = []
        for r in rooms:
                if (r as Room).kind != "stair":
                        work.append(r)
        if work.is_empty():
                return
        work.sort_custom(func(a, b): return (a as Room).rect.get_area() > (b as Room).rect.get_area())
        var small: Array = []
        var large: Array = []
        for r in work:
                if (r as Room).rect.get_area() < 6.5:
                        small.append(r)
                else:
                        large.append(r)
        # guarantee a bathroom on EVERY floor: if no small room exists, the
        # smallest large room becomes the bath (a large bathroom is realistic;
        # a floor without one is not)
        if small.is_empty() and large.size() > 1:
                var cand: Room = large[large.size() - 1]
                large.erase(cand)
                small.append(cand)
        if small.size() > 0:
                (small[0] as Room).kind = "bath"
        if small.size() > 1:
                (small[1] as Room).kind = "bath" if rng.randf() < 0.6 else "storage"
        for k in range(2, small.size()):
                var kinds: Array = ["storage", "bath", "storage"]
                (small[k] as Room).kind = kinds[k % kinds.size()]
        # large rooms per program
        if office_building:
                for i in large.size():
                        var r: Room = large[i]
                        if i == 0 and large.size() > 2:
                                r.kind = "dining"      # break / meeting room with table
                        elif i == 1 and large.size() > 3:
                                r.kind = "lounge"
                        else:
                                r.kind = "office"
                return
        if floor_i == 0:
                if large.size() > 0:
                        (large[0] as Room).kind = "living"
                if large.size() > 1:
                        (large[1] as Room).kind = "kitchen"
                if large.size() > 2:
                        (large[2] as Room).kind = "dining"
                for i in range(3, large.size()):
                        (large[i] as Room).kind = "bedroom"
        else:
                if large.size() > 0:
                        (large[0] as Room).kind = "bedroom"
                if large.size() > 1:
                        (large[1] as Room).kind = "bedroom"
                if large.size() > 2:
                        # variety on upper floors: office / lounge
                        (large[2] as Room).kind = "office" if rng.randf() < 0.5 else "lounge"
                for i in range(3, large.size()):
                        (large[i] as Room).kind = "bedroom"
                # penthouse gets a lounge-kitchen feel
                if floor_i == floor_count - 1 and floor_i > 0 and large.size() > 1:
                        (large[large.size() - 1] as Room).kind = "lounge"
        # safety: no leftover "living" on upper floors
        for r2 in work:
                if (r2 as Room).kind == "living" and floor_i > 0:
                        (r2 as Room).kind = "bedroom"


## Collects door touch points for a room (for prop placement avoidance).
## Returns Array of {pos: Vector2, dir: Vector2} where dir points across the
## wall (passage direction).
static func room_doors(room: Room, walls: Array) -> Array:
        var out: Array = []
        for s in walls:
                var seg := s as WallSeg
                if seg.door.is_empty():
                        continue
                if seg.room_a != room.id and seg.room_b != room.id:
                        continue
                var c: Vector2 = (seg.door.a + seg.door.b) * 0.5
                out.append({"pos": c, "dir": seg.door.dir})
        return out
