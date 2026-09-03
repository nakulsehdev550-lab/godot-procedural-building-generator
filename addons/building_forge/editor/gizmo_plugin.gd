@tool
extends EditorNode3DGizmoPlugin
## Gizmo for ProceduralBuilding: footprint vertex handles + height handle.

const ProceduralBuildingS := preload("res://addons/building_forge/core/building_generator.gd")

const HANDLE_HEIGHT := 999  # special handle id (billboard, top center)

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
        # footprint outline lines
        var lines := PackedVector3Array()
        var n := fp.points.size()
        for i in n:
                var a := fp.points[i]
                var c := fp.points[(i + 1) % n]
                lines.append(Vector3(a.x, 0.02, a.y))
                lines.append(Vector3(c.x, 0.02, c.y))
        # vertical corner posts to full height
        var top := float(b.params.floors) * b.params.floor_height
        for i in n:
                var a := fp.points[i]
                lines.append(Vector3(a.x, 0.0, a.y))
                lines.append(Vector3(a.x, top, a.y))
        gizmo.add_lines(lines, get_material("outline", gizmo), false)
        # vertex handles
        var handles := PackedVector3Array()
        for p in fp.points:
                handles.append(Vector3(p.x, 0.05, p.y))
        # height handle
        handles.append(Vector3(fp.center_xz().x, top, fp.center_xz().y))
        gizmo.add_handles(handles, get_material("handles", gizmo), PackedInt32Array(), false, false)


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
        if handle_id == gizmo.get_handle_count() - 1:
                return "Building Height"
        return "Footprint Vertex %d" % handle_id


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null:
                return null
        var fp := b.params.footprint
        if handle_id == _height_handle_id(gizmo):
                return b.params.floors
        if handle_id < fp.points.size():
                return fp.points[handle_id]
        return null


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool,
                camera: Camera3D, screen_pos: Vector2) -> void:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null or b.params == null or b.params.footprint == null:
                return
        var fp := b.params.footprint
        if handle_id == _height_handle_id(gizmo):
                var new_floors := _floors_from_screen(b, camera, screen_pos)
                if new_floors >= 1 and new_floors <= 50:
                        b.params.floors = new_floors
                return
        if handle_id >= fp.points.size():
                return
        var hit := _plane_hit(b, camera, screen_pos)
        var pts := fp.points.duplicate()
        pts[handle_id] = hit
        fp.points = pts  # setter normalizes winding + emits changed


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool,
                restore: Variant, cancel: bool) -> void:
        var b := gizmo.get_node_3d() as ProceduralBuildingS
        if b == null:
                return
        if cancel:
                if handle_id == _height_handle_id(gizmo):
                        b.params.floors = int(restore)
                elif restore is Vector2:
                        var fp2 := b.params.footprint
                        var pts := fp2.points.duplicate()
                        pts[handle_id] = restore
                        fp2.points = pts
                return
        if editor_plugin == null:
                return
        var undo: EditorUndoRedoManager = editor_plugin.get_undo_redo()
        undo.create_action("BuildingForge: Edit Handle")
        if handle_id == _height_handle_id(gizmo):
                undo.add_do_property(b.params, "floors", b.params.floors)
                undo.add_undo_property(b.params, "floors", int(restore))
        elif restore is Vector2:
                undo.add_do_property(b.params.footprint, "points", b.params.footprint.points)
                undo.add_undo_property(b.params.footprint, "points", restore)
        undo.add_do_method(b.params, "emit_changed")
        undo.add_undo_method(b.params, "emit_changed")
        undo.commit_action()


func _height_handle_id(gizmo: EditorNode3DGizmo) -> int:
        return gizmo.get_handle_count() - 1


func _floors_from_screen(b: ProceduralBuildingS, camera: Camera3D, screen_pos: Vector2) -> int:
        # project drag ray onto the world Y axis through the handle
        var fp := b.params.footprint
        var top := float(b.params.floors) * b.params.floor_height
        var center := b.to_global(Vector3(fp.center_xz().x, top, fp.center_xz().y))
        var origin := camera.project_ray_origin(screen_pos)
        var dir := camera.project_ray_normal(screen_pos)
        # closest point on ray to the vertical line through center
        var to_center := center - origin
        var along := to_center.dot(dir)
        var closest := origin + dir * along
        var dy := closest.y - center.y
        var add_floors := int(round(dy / b.params.floor_height))
        return b.params.floors + add_floors


func _plane_hit(b: ProceduralBuildingS, camera: Camera3D, screen_pos: Vector2) -> Vector2:
        var origin := camera.project_ray_origin(screen_pos)
        var dir := camera.project_ray_normal(screen_pos)
        var plane_y := b.global_position.y
        if absf(dir.y) < 0.0001:
                return Vector2.ZERO
        var t := (plane_y - origin.y) / dir.y
        var hit := origin + dir * t
        var local := b.to_local(hit)
        return Vector2(local.x, local.z).snapped(Vector2(0.25, 0.25))


func _init() -> void:
        create_material("outline", Color(1.0, 0.72, 0.2))
        create_handle_material("handles")
        create_handle_material("sec_handles")
