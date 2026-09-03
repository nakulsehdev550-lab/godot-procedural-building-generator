@tool
extends EditorPlugin
## BuildingForge editor plugin: dock, footprint draw tool, gizmo handles,
## inspector buttons.

const ProceduralBuildingS := preload("res://addons/building_forge/core/building_generator.gd")
const BFGizmoPluginS := preload("res://addons/building_forge/editor/gizmo_plugin.gd")
const BFDockS := preload("res://addons/building_forge/editor/dock.gd")

var _dock: Control = null
var _gizmo_plugin: EditorNode3DGizmoPlugin = null
var _draw_mode := false  # footprint drawing active
var _draw_shape := 0     # 0 rect, 1 circle, 2 polygon
var _snap := 0.5
var _poly_points := PackedVector2Array()
var _drag_start := Vector2.ZERO
var _drag_active := false
var _drag_cur := Vector2.ZERO
var _undo: EditorUndoRedoManager = null


func _enter_tree() -> void:
        _gizmo_plugin = BFGizmoPluginS.new()
        _gizmo_plugin.editor_plugin = self
        add_node_3d_gizmo_plugin(_gizmo_plugin)
        _dock = BFDockS.new()
        _dock.plugin = self
        add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
        _undo = get_undo_redo()
        print("[BuildingForge] loaded")


func _exit_tree() -> void:
        if _dock != null:
                remove_control_from_docks(_dock)
                _dock.queue_free()
        if _gizmo_plugin != null:
                remove_node_3d_gizmo_plugin(_gizmo_plugin)
        print("[BuildingForge] unloaded")


func _handles(object: Object) -> bool:
        return object is ProceduralBuilding


func _edit(object: Object) -> void:
        pass


## Forward viewport input while draw mode is on and a building is selected.
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
        if not _draw_mode:
                return EditorPlugin.AFTER_GUI_INPUT_PASS
        var b := _selected_building()
        if b == null:
                return EditorPlugin.AFTER_GUI_INPUT_PASS
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT:
                        var wp := _plane_hit(viewport_camera, mb.position, b)
                        if mb.pressed:
                                if _draw_shape == 2:  # polygon: click adds point
                                        _poly_points.append(wp)
                                        update_overlays()
                                        return EditorPlugin.AFTER_GUI_INPUT_STOP
                                _drag_active = true
                                _drag_start = wp
                                _drag_cur = wp
                        else:
                                if _draw_shape == 0:
                                        _commit_rect(b, _drag_start, wp)
                                elif _draw_shape == 1:
                                        _commit_circle(b, _drag_start, _drag_start.distance_to(wp))
                                _drag_active = false
                                update_overlays()
                        return EditorPlugin.AFTER_GUI_INPUT_STOP
                if mb.button_index == MOUSE_BUTTON_RIGHT and _draw_shape == 2 and _poly_points.size() >= 3:
                        _commit_polygon(b)
                        return EditorPlugin.AFTER_GUI_INPUT_STOP
        elif event is InputEventMouseMotion and _drag_active:
                _drag_cur = _plane_hit(viewport_camera, (event as InputEventMouseMotion).position, b)
                update_overlays()
                return EditorPlugin.AFTER_GUI_INPUT_STOP
        elif event is InputEventKey:
                var k := event as InputEventKey
                if k.pressed and k.keycode == KEY_ENTER and _draw_shape == 2 and _poly_points.size() >= 3:
                        _commit_polygon(b)
                        return EditorPlugin.AFTER_GUI_INPUT_STOP
                if k.pressed and k.keycode == KEY_ESCAPE:
                        _poly_points.clear()
                        update_overlays()
                        return EditorPlugin.AFTER_GUI_INPUT_STOP
        return EditorPlugin.AFTER_GUI_INPUT_PASS


func _forward_3d_draw_over_viewport(viewport_control: Control) -> void:
        if not _draw_mode:
                return
        var font := ThemeDB.fallback_font
        var col := Color(1.0, 0.72, 0.2)
        var msg := "BuildingForge draw: "
        match _draw_shape:
                0: msg += "drag = rectangle"
                1: msg += "drag = circle (center -> radius)"
                2: msg += "click points, Enter/RMB = finish, Esc = cancel"
        viewport_control.draw_string(font, Vector2(16, 28), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
        if _drag_active:
                _draw_poly(viewport_control, _rect_points(_drag_start, _drag_cur) if _draw_shape == 0
                        else _circle_points(_drag_start, _drag_start.distance_to(_drag_cur)), col)
        for i in _poly_points.size():
                var sp := _poly_points[i]
                viewport_control.draw_circle(sp, 3.0, col)
                if i > 0:
                        viewport_control.draw_line(_poly_points[i - 1], sp, col, 2.0)
        if _poly_points.size() > 2:
                viewport_control.draw_line(_poly_points[_poly_points.size() - 1], _poly_points[0], col * Color(1, 1, 1, 0.5), 1.5)


func _draw_poly(ctrl: Control, pts: PackedVector2Array, col: Color) -> void:
        if pts.size() < 2:
                return
        var draw_pts := pts.duplicate()
        draw_pts.append(pts[0])
        ctrl.draw_polyline(draw_pts, col, 2.0)


func _selected_building() -> ProceduralBuilding:
        var sel := EditorInterface.get_selection().get_selected_nodes()
        for n in sel:
                if n is ProceduralBuilding:
                        return n
        return null


func _plane_hit(cam: Camera3D, screen_pos: Vector2, b: ProceduralBuilding) -> Vector2:
        var origin := cam.project_ray_origin(screen_pos)
        var dir := cam.project_ray_normal(screen_pos)
        var plane_y := b.global_position.y
        if absf(dir.y) < 0.0001:
                var fallback := b.to_local(Vector3(origin.x + dir.x * 10.0, plane_y, origin.z + dir.z * 10.0))
                return Vector2(fallback.x, fallback.z)
        var t := (plane_y - origin.y) / dir.y
        var hit := origin + dir * t
        var local := b.to_local(hit)
        var p := Vector2(local.x, local.z)
        p = p.snapped(Vector2(_snap, _snap))
        return p


func _rect_points(a: Vector2, b: Vector2) -> PackedVector2Array:
        return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


func _circle_points(c: Vector2, r: float, segments := 32) -> PackedVector2Array:
        var pts := PackedVector2Array()
        for i in segments:
                var a := TAU * float(i) / float(segments)
                pts.append(c + Vector2(cos(a), sin(a)) * r)
        return pts


func _commit_rect(b: ProceduralBuilding, a: Vector2, bpt: Vector2) -> void:
        if (bpt - a).length() < 1.0:
                return
        var pts := _rect_points(a, bpt)
        _push_footprint(b, pts)


func _commit_circle(b: ProceduralBuilding, c: Vector2, r: float) -> void:
        if r < 1.0:
                return
        _push_footprint(b, _circle_points(c, r, maxi(24, int(r * 4.0))))


func _commit_polygon(b: ProceduralBuilding) -> void:
        if _poly_points.size() < 3:
                return
        _push_footprint(b, _poly_points.duplicate())
        _poly_points.clear()


func _push_footprint(b: ProceduralBuilding, pts: PackedVector2Array) -> void:
        var fp := BFFootprint.create(pts)
        if fp.validate() != "":
                print("[BuildingForge] invalid footprint: ", fp.validate())
                return
        var old_fp: BFFootprint = b.params.footprint
        var new_fp := fp
        _undo.create_action("BuildingForge: Draw Footprint")
        _undo.add_do_property(b.params, "footprint", new_fp)
        _undo.add_undo_property(b.params, "footprint", old_fp)
        _undo.add_do_method(b.params, "emit_changed")
        _undo.add_undo_method(b.params, "emit_changed")
        _undo.commit_action()


## --- API for the dock ------------------------------------------------------

func set_draw_mode(on: bool, shape: int) -> void:
        _draw_mode = on
        _draw_shape = shape
        _poly_points.clear()
        update_overlays()


func is_draw_mode() -> bool:
        return _draw_mode


func create_building() -> void:
        var scene_root := EditorInterface.get_edited_scene_root()
        if scene_root == null:
                print("[BuildingForge] open a scene first")
                return
        var b := ProceduralBuilding.new()
        b.name = "ProceduralBuilding"
        _undo.create_action("BuildingForge: Add Building")
        _undo.add_do_method(scene_root, "add_child", b)
        _undo.add_do_method(b, "set_owner", scene_root)
        _undo.add_do_reference(b)
        _undo.add_undo_method(scene_root, "remove_child", b)
        _undo.commit_action()
        b.position = Vector3.ZERO
        EditorInterface.get_selection().clear()
        EditorInterface.get_selection().add_node(b)
        print("[BuildingForge] building created")


func apply_preset(preset_name: String) -> void:
        var b := _selected_building()
        if b == null:
                print("[BuildingForge] select a ProceduralBuilding first")
                return
        var p: BFParams = b.params
        var presets := {
                "suburban_house": func():
                        p.footprint = BFFootprint.create_rect(11, 8.5)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.facade_material = "plaster_ext"
                        p.roof_kind = BFParams.Roof.GABLE
                        p.roof_pitch = 0.6
                        p.window_style = BFParams.WindowStyle.PUNCHED
                        p.stair_kind = BFParams.Stair.STRAIGHT
                        p.max_room_area = 20.0,
                "cottage": func():
                        p.footprint = BFFootprint.create_L(9, 7)
                        p.floors = 1
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.facade_material = "stone"
                        p.roof_kind = BFParams.Roof.HIP
                        p.window_style = BFParams.WindowStyle.PUNCHED,
                "modern_villa": func():
                        p.footprint = BFFootprint.create_L(14, 11)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.apply_architecture_defaults()
                        p.roof_kind = BFParams.Roof.FLAT
                        p.stair_kind = BFParams.Stair.DOGLEG,
                "apartment_block": func():
                        p.footprint = BFFootprint.create_rect(18, 13)
                        p.floors = 5
                        p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
                        p.apply_architecture_defaults()
                        p.balconies = true
                        p.stair_kind = BFParams.Stair.DOGLEG,
                "office_tower": func():
                        p.footprint = BFFootprint.create_rect(22, 17)
                        p.floors = 15
                        p.architecture = BFParams.ArchStyle.OFFICE_TOWER
                        p.apply_architecture_defaults()
                        p.stair_kind = BFParams.Stair.SPIRAL,
                "circular_tower": func():
                        p.footprint = BFFootprint.create_circle(8)
                        p.floors = 6
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.roof_kind = BFParams.Roof.CONE
                        p.window_style = BFParams.WindowStyle.CURTAIN
                        p.stair_kind = BFParams.Stair.SPIRAL,
        }
        if presets.has(preset_name):
                var fn: Callable = presets[preset_name]
                fn.call()
                _undo.create_action("BuildingForge: Preset " + preset_name)
                _undo.add_do_property(b, "params", p.clone_params())
                _undo.commit_action()
                b.params.emit_changed()


func randomize_seed() -> void:
        var b := _selected_building()
        if b != null:
                b.params.seed = randi() % 100000


func rebake_textures(res_div := 1.0) -> void:
        var n: int = BFTextureBaker.bake_all(BFTextureBaker.DEFAULT_DIR, res_div)
        BFMaterialLibrary.clear_cache()
        print("[BuildingForge] rebaked %d material sets" % n)
        EditorInterface.reload_scene_from_path(EditorInterface.get_edited_scene_root().scene_file_path) if EditorInterface.get_edited_scene_root() and EditorInterface.get_edited_scene_root().scene_file_path != "" else null
