class_name BFTestPlayer
extends CharacterBody3D
## FPS test-drive controller for the BuildingForge zoo map.
##   WASD move, Shift sprint, Space jump, mouse look, click to capture,
##   ESC to release the mouse.
## While looking at a building:
##   E - cycle facade material   R - cycle roof kind
##   G - cycle facade paint      F - flashlight

const MOUSE_SENS := 0.0028
const WALK := 4.6
const SPRINT := 8.2
const JUMP := 4.6

const FACADE_CYCLE := ["plaster_ext", "brick_red", "brick_gray", "stone", "facade_panel", "concrete"]
const TINT_CYCLE := [Color.WHITE, Color(0.98, 0.93, 0.8), Color(0.87, 0.56, 0.42),
        Color(0.68, 0.79, 0.58), Color(0.62, 0.8, 0.86), Color(0.4, 0.42, 0.46)]
const ROOF_CYCLE := [0, 1, 2, 5, 6, 7, 3, 4]  # BFParams.Roof order minus duplicates

var cam: Camera3D
var _pitch := 0.0
var _captured := false
var _flash: SpotLight3D
var _hint: Label
var _target: ProceduralBuilding = null
var _facade_i := {}
var _tint_i := {}
var _roof_i := {}


func _ready() -> void:
        # guard: the rig already exists when reloaded from a saved scene
        if cam != null:
                _capture()
                return
        cam = Camera3D.new()
        cam.position = Vector3(0, 1.62, 0)
        cam.current = true
        add_child(cam)
        _flash = SpotLight3D.new()
        _flash.position = Vector3(0, 1.5, 0.1)
        _flash.rotation_degrees = Vector3(-8, 0, 0)
        _flash.spot_range = 18.0
        _flash.spot_angle = 38.0
        _flash.light_energy = 0.0
        cam.add_child(_flash)
        var col := CollisionShape3D.new()
        var cap := CapsuleShape3D.new()
        cap.radius = 0.35
        cap.height = 1.75
        col.shape = cap
        col.position = Vector3(0, 0.9, 0)
        add_child(col)
        var ui := CanvasLayer.new()
        add_child(ui)
        _hint = Label.new()
        _hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        _hint.position = Vector2(-360, -70)
        _hint.custom_minimum_size = Vector2(720, 40)
        _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _hint.add_theme_font_size_override("font_size", 17)
        _hint.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
        _hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
        _hint.add_theme_constant_override("outline_size", 6)
        ui.add_child(_hint)
        _capture()


func _capture() -> void:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        _captured = true


func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
                _captured = false
                return
        if event is InputEventMouseButton and event.pressed and not _captured:
                _capture()
                return
        if _captured and event is InputEventMouseMotion:
                rotate_y(-event.relative.x * MOUSE_SENS)
                _pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
                cam.rotation.x = _pitch
                return
        if _captured and event is InputEventKey and event.pressed and not event.echo:
                match event.keycode:
                        KEY_E:
                                _paint_facade()
                        KEY_R:
                                _cycle_roof()
                        KEY_G:
                                _cycle_tint()
                        KEY_F:
                                _flash.light_energy = 0.0 if _flash.light_energy > 0.5 else 2.2


func _physics_process(delta: float) -> void:
        if not is_on_floor():
                velocity.y -= 14.0 * delta
        var input_dir := Vector2.ZERO
        if _captured:
                input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
                if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
                        velocity.y = JUMP
        var wish := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
        var speed := SPRINT if Input.is_key_pressed(KEY_SHIFT) else WALK
        velocity.x = wish.x * speed
        velocity.z = wish.z * speed
        move_and_slide()
        _update_target()


func _update_target() -> void:
        var space := get_world_3d().direct_space_state
        var from := cam.global_position
        var to := from + -cam.global_transform.basis.z * 6.0
        var q := PhysicsRayQueryParameters3D.create(from, to)
        var hit := space.intersect_ray(q)
        _target = null
        if hit.has("collider"):
                var n: Node = hit.collider
                while n != null:
                        if n is ProceduralBuilding:
                                _target = n
                                break
                        n = n.get_parent()
        if _target != null:
                _hint.text = "[E] paint facade   [R] roof style   [G] paint color   [F] flashlight  |  %s" % _target.name
        else:
                _hint.text = "[E/R/G] aim at a building to restyle it   [F] flashlight   [ESC] mouse"


func _paint_facade() -> void:
        if _target == null:
                return
        var i := int(_facade_i.get(_target.name, -1)) + 1
        _facade_i[_target.name] = i
        _target.params.facade_material = FACADE_CYCLE[i % FACADE_CYCLE.size()]
        _target.params.emit_changed()


func _cycle_tint() -> void:
        if _target == null:
                return
        var i := int(_tint_i.get(_target.name, -1)) + 1
        _tint_i[_target.name] = i
        _target.params.facade_tint = TINT_CYCLE[i % TINT_CYCLE.size()]
        _target.params.emit_changed()


func _cycle_roof() -> void:
        if _target == null:
                return
        var i := int(_roof_i.get(_target.name, -1)) + 1
        _roof_i[_target.name] = i
        _target.params.roof_kind = ROOF_CYCLE[i % ROOF_CYCLE.size()]
        _target.params.emit_changed()
