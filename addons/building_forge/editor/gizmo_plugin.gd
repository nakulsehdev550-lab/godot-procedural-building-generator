@tool
extends EditorNode3DGizmoPlugin
## Gizmo for ProceduralBuilding - the full interactive editing handle set:
##   [0, n)      bottom vertex handles (ground wall corners)
##   [n, 2n)     TOP vertex handles (roof/wall corner columns) - drag moves
##               the same footprint vertex, shown at the roof line
##   [2n, 3n)    edge midpoint handles - dragging INSERTS a new bend point
##               in the wall and keeps dragging the new vertex
##   next        roof pitch handle (ridge/peak) on pitched roofs
##   last        building height handle (drag up/down to add/remove floors)
## Drag any handle: the whole building regenerates live (interiors, windows
## and stairs follow). While dragging, generation runs in fast mode (no
## props/collision) and a full rebuild happens when the drag commits.

const ProceduralBuildingS := preload("res://addons/building_forge/core/building_generator.gd")
const BFRoofBuilderS := preload("res://addons/building_forge/core/geometry/roof_builder.gd")

const SNAP := 0.25
const MID_SPAWNED := "bf_mid_spawned"      # handle_id -> spawned vertex index
const POINTS_START := "bf_points_start"    # PackedVector2Array before drag
const PITCH_START := "bf_pitch_start"      # roof_pitch before drag

var editor_plugin: EditorPlugin = null


func _get_gizmo_name() -> String:
        return "BuildingForge"


func _has_gizmo(node: Node3D) -> bool:
        return node is ProceduralBuildingS


func _get_priority() -> int:
        return -5  # below default node gizmos


func _redraw(gizmo: EditorNode3DGizmo) -> void:
        gizmo.clear()
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null or b.params == null or b.params.footprint == null:
                return
        var fp := b.params.footprint
        if fp.points.size() < 3:
                return
        var n := fp.points.size()
        var top := float(b.params.floors) * b.params.floor_height
        # footprint outline + corner posts
        var lines := PackedVector3Array()
        for i in n:
                var a := fp.points[i]
                var c := fp.points[(i + 1) % n]
                lines.append(Vector3(a.x, 0.02, a.y))
                lines.append(Vector3(c.x, 0.02, c.y))
        for i in n:
                var a := fp.points[i]
                lines.append(Vector3(a.x, 0.0, a.y))
                lines.append(Vector3(a.x, top, a.y))
        # ridge line hint (pitched roofs)
        var ridge = _ridge_hint(b)
        if ridge is Array:
                lines.append(ridge[0])
                lines.append(ridge[1])
        gizmo.add_lines(lines, get_material("outline", gizmo), false)
        # handle set
        var handles := PackedVector3Array()
        for p in fp.points:
                handles.append(Vector3(p.x, 0.05, p.y))            # bottom corners
        for p in fp.points:
                handles.append(Vector3(p.x, top, p.y))             # roof corners
        for i in n:
                var a := fp.points[i]
                var c := fp.points[(i + 1) % n]
                handles.append(Vector3((a.x + c.x) * 0.5, 0.05, (a.y + c.y) * 0.5))  # bend points
        var pitch := _pitch_handle_pos(b)
        if pitch != Vector3.INF:
                handles.append(pitch)                              # roof pitch
        handles.append(Vector3(fp.center_xz().x, top, fp.center_xz().y))  # height
        gizmo.add_handles(handles, get_material("handles", gizmo), PackedInt32Array(), false, false)


## [start, end] world-space ridge line for the gizmo, or Vector3.INF when none.
func _ridge_hint(b: ProceduralBuildingS) -> Variant:
        var fp := b.params.footprint
        var kind := b.params.roof_kind
        if fp.is_circular or not (kind in [BFParams.Roof.GABLE, BFParams.Roof.HIP]):
                return Vector3.INF
        var top := float(b.params.floors) * b.params.floor_height
        var obb := BFRoofBuilderS.oriented_bbox(fp.points)
        var center: Vector2 = obb[0]
        var ang: float = obb[2]
        var half: Vector2 = obb[1]
        var ca := cos(ang)
        var sa := sin(ang)
        var xfrm := Transform3D(Basis(Vector3(ca, 0, -sa), Vector3.UP, Vector3(sa, 0, ca)), Vector3(center.x, top + half.y * b.params.roof_pitch, center.y))
        var hl: float = half.x * (0.85 if kind == BFParams.Roof.GABLE else maxf(0.05, half.x - half.y))
        return [xfrm * Vector3(-hl, 0, 0), xfrm * Vector3(hl, 0, 0)]


func _pitch_handle_pos(b: ProceduralBuildingS) -> Vector3:
        var ridge = _ridge_hint(b)
        if not (ridge is Array):
                # cone roofs get an apex handle
                var fp := b.params.footprint
                if fp.is_circular and b.params.roof_kind == BFParams.Roof.CONE:
                        var r := maxf(fp.size_xz().x, fp.size_xz().y) * 0.5
                        return Vector3(fp.center_xz().x, float(b.params.floors) * b.params.floor_height + r * b.params.roof_pitch, fp.center_xz().y)
                return Vector3.INF
        return (ridge[0] as Vector3).lerp(ridge[1] as Vector3, 0.5)


## 0 bottom vertex, 1 top vertex, 2 edge midpoint, 3 roof pitch, 4 height.
func _handle_kind(gizmo: EditorNode3DGizmo, handle_id: int) -> int:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null or b.params == null or b.params.footprint == null:
                return -1
        var n := b.params.footprint.points.size()
        if handle_id < n:
                return 0
        if handle_id < 2 * n:
                return 1
        if handle_id < 3 * n:
                return 2
        if _pitch_handle_pos(b) != Vector3.INF and handle_id == 3 * n:
                return 3
        return 4


func _vertex_index(gizmo: EditorNode3DGizmo, handle_id: int) -> int:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        var n := b.params.footprint.points.size()
        return handle_id % n


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
        match _handle_kind(gizmo, handle_id):
                0:
                        return "Wall Corner %d" % _vertex_index(gizmo, handle_id)
                1:
                        return "Roof Corner %d" % _vertex_index(gizmo, handle_id)
                2:
                        return "Drag to Add Bend Point"
                3:
                        return "Roof Pitch"
                _:
                        return "Building Height"


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null or b.params == null or b.params.footprint == null:
                return null
        var kind := _handle_kind(gizmo, handle_id)
        if kind == 4:
                return b.params.floors
        if kind == 3:
                return b.params.roof_pitch
        var vi := _vertex_index(gizmo, handle_id)
        if kind == 0 or kind == 1:
                return b.params.footprint.points[vi]
        if kind == 2:
                return _mid_pos(b, vi)
        return null


func _mid_pos(b: ProceduralBuildingS, edge_i: int) -> Vector3:
        var fp := b.params.footprint
        var a := fp.points[edge_i]
        var c := fp.points[(edge_i + 1) % fp.points.size()]
        return Vector3((a.x + c.x) * 0.5, 0.05, (a.y + c.y) * 0.5)


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool,
                camera: Camera3D, screen_pos: Vector2) -> void:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null or b.params == null or b.params.footprint == null:
                return
        b.fast_regen = true
        if not gizmo.has_meta(POINTS_START):
                gizmo.set_meta(POINTS_START, b.params.footprint.points.duplicate())
        var fp := b.params.footprint
        var kind := _handle_kind(gizmo, handle_id)
        if kind == 4:
                var new_floors := _floors_from_screen(b, camera, screen_pos)
                if new_floors >= 1 and new_floors <= 50:
                        b.params.floors = new_floors
                return
        if kind == 3:
                if not b.has_meta(PITCH_START):
                        b.set_meta(PITCH_START, b.params.roof_pitch)
                var dy := _drag_dy(b, camera, screen_pos, _pitch_handle_pos(b))
                var start: float = b.get_meta(PITCH_START)
                var hz := maxf(BFRoofBuilderS.oriented_bbox(fp.points)[1].y, 1.0)
                b.params.roof_pitch = snappedf(clampf(start + dy / hz, 0.05, 3.0), 0.05)
                return
        var vi := _vertex_index(gizmo, handle_id)
        if kind == 2:
                # first motion inserts the bend point at the edge midpoint and
                # retargets this drag onto the NEW vertex index
                var spawned: Dictionary = gizmo.get_meta(MID_SPAWNED, {})
                if not spawned.has(handle_id):
                        var mid := (fp.points[vi] + fp.points[(vi + 1) % fp.points.size()]) * 0.5
                        var new_idx := fp.insert_point_on_nearest_edge(mid, 0.05)
                        if new_idx < 0:
                                return
                        spawned[handle_id] = new_idx
                        gizmo.set_meta(MID_SPAWNED, spawned)
                vi = int(spawned.get(handle_id, vi))
        var hit := _plane_hit(b, camera, screen_pos)
        var pts := fp.points.duplicate()
        pts[vi] = hit
        fp.points = pts  # setter normalizes winding + emits changed


func _drag_dy(b: ProceduralBuildingS, camera: Camera3D, screen_pos: Vector2, handle: Vector3) -> float:
        var center := b.to_global(handle)
        var origin := camera.project_ray_origin(screen_pos)
        var dir := camera.project_ray_normal(screen_pos)
        var to_center := center - origin
        var along := to_center.dot(dir)
        var closest := origin + dir * along
        return closest.y - center.y


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool,
                restore: Variant, cancel: bool) -> void:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null:
                return
        b.fast_regen = false
        var kind := _handle_kind(gizmo, handle_id)
        var points_before: PackedVector2Array = gizmo.get_meta(POINTS_START, b.params.footprint.points)
        if cancel:
                match kind:
                        4:
                                b.params.floors = int(restore)
                        3:
                                b.params.roof_pitch = float(restore)
                        0, 1:
                                b.params.footprint.points = points_before.duplicate()
                        2:
                                var spawned: Dictionary = gizmo.get_meta(MID_SPAWNED, {})
                                if spawned.has(handle_id) and b.params.footprint.points.size() > 3:
                                        b.params.footprint.points = points_before.duplicate()
                        _:
                                pass
                b.params.emit_changed()
        elif editor_plugin != null:
                var undo: EditorUndoRedoManager = editor_plugin.get_undo_redo()
                undo.create_action("BuildingForge: Edit Handle")
                match kind:
                        4:
                                undo.add_do_property(b.params, "floors", b.params.floors)
                                undo.add_undo_property(b.params, "floors", int(restore))
                        3:
                                undo.add_do_property(b.params, "roof_pitch", b.params.roof_pitch)
                                undo.add_undo_property(b.params, "roof_pitch", float(restore))
                        0, 1, 2:
                                undo.add_do_property(b.params.footprint, "points", b.params.footprint.points)
                                undo.add_undo_property(b.params.footprint, "points", points_before.duplicate())
                        _:
                                pass
                undo.add_do_method(b.params, "emit_changed")
                undo.add_undo_method(b.params, "emit_changed")
                undo.commit_action()
        gizmo.remove_meta(MID_SPAWNED)
        gizmo.remove_meta(POINTS_START)
        b.remove_meta(PITCH_START)


func _floors_from_screen(b: ProceduralBuildingS, camera: Camera3D, screen_pos: Vector2) -> int:
        # project drag ray onto the world Y axis through the handle
        var fp := b.params.footprint
        var top := float(b.params.floors) * b.params.floor_height
        var center := b.to_global(Vector3(fp.center_xz().x, top, fp.center_xz().y))
        var origin := camera.project_ray_origin(screen_pos)
        var dir := camera.project_ray_normal(screen_pos)
        var to_center := center - origin
        var along := to_center.dot(dir)
        var closest := origin + dir * along
        var dy := closest.y - center.y
        return b.params.floors + int(round(dy / b.params.floor_height))


func _plane_hit(b: ProceduralBuildingS, camera: Camera3D, screen_pos: Vector2) -> Vector2:
        var origin := camera.project_ray_origin(screen_pos)
        var dir := camera.project_ray_normal(screen_pos)
        var plane_y := b.global_position.y
        if absf(dir.y) < 0.0001:
                return Vector2.ZERO
        var t := (plane_y - origin.y) / dir.y
        var hit := origin + dir * t
        var local := b.to_local(hit)
        return Vector2(local.x, local.z).snapped(Vector2(SNAP, SNAP))


func _init() -> void:
        create_material("outline", Color(1.0, 0.72, 0.2))
        create_handle_material("handles")
        create_handle_material("sec_handles")
