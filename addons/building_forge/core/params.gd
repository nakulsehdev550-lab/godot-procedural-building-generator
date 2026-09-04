@tool
class_name BFParams
extends Resource
## Every generator parameter, fully exposed to the inspector.
## Presets are simply BFParams .tres files (see presets/).

## Architecture styles drive facade layout + default materials.
enum ArchStyle { CLASSIC_HOUSE, BRICK_APARTMENT, MODERN, OFFICE_TOWER, CUSTOM }
## Facade window layout styles.
enum WindowStyle { PUNCHED, CURTAIN, TALL }
## Roof kinds (mirror of BFRoofBuilder.RoofKind for inspector comfort).
enum Roof { FLAT, GABLE, HIP, CONE, DOME, MANSARD, GAMBREL, SHED }
## Stair kinds.
enum Stair { AUTO, STRAIGHT, DOGLEG, SPIRAL }

@export_group("Shape")
## Footprint polygon (draw it in the viewport or pick a preset shape).
@export var footprint: BFFootprint = BFFootprint.create_rect(10, 8):
        set(v):
                footprint = v
                emit_changed()
@export_range(1, 50, 1) var floors: int = 2
@export_range(2.2, 6.0, 0.05) var floor_height: float = 3.0
@export_range(0.0, 360.0, 1.0, "degrees") var rotation_degrees_y: float = 0.0

@export_group("Style")
@export var architecture: ArchStyle = ArchStyle.CLASSIC_HOUSE
## Exterior wall material id (see BFMaterialLibrary).
@export var facade_material: String = "plaster_ext"
## Interior wall material id.
@export var interior_material: String = "plaster_int"
@export var roof_kind: Roof = Roof.GABLE
@export_range(0.0, 2.4, 0.05) var roof_pitch: float = 0.55
## Secondary roof pitch (mansard lower slope / gambrel lower slope).
@export_range(0.1, 3.0, 0.05) var roof_pitch2: float = 1.3
@export_range(0.0, 1.2, 0.05) var roof_overhang: float = 0.45
@export var window_style: WindowStyle = WindowStyle.PUNCHED
## Paint: multiplies the facade / roof albedo (works with textures).
@export var facade_tint: Color = Color.WHITE:
        set(v):
                facade_tint = v
                emit_changed()
@export var roof_tint: Color = Color.WHITE:
        set(v):
                roof_tint = v
                emit_changed()
## Path to a texture folder set (swap stylized/lowpoly/realistic here).
@export_dir var texture_style_dir: String = "res://addons/building_forge/textures/baked"

@export_group("Facade Detail")
## Stone plinth band at the base + cornice band under the roofline.
@export var facade_bands: bool = true
## Brick chimney on pitched roofs / rooftop on flat roofs.
@export var chimney: bool = false
## Picket fence around the plot with a gate at the entrance.
@export var site_fence: bool = false
## Concrete pad slab under the building (site preparation).
@export var terrain_pad: bool = false

@export_group("Walls & Openings")
@export_range(0.08, 0.6, 0.01) var wall_thickness: float = 0.25
@export_range(0.5, 3.0, 0.05) var window_width: float = 1.3
@export_range(0.5, 2.6, 0.05) var window_height: float = 1.4
@export_range(0.0, 2.0, 0.05) var window_sill: float = 0.9
@export_range(0.6, 1.6, 0.05) var door_width: float = 0.95
@export_range(1.9, 2.6, 0.05) var door_height: float = 2.1
@export_range(2.0, 6.0, 0.1) var window_spacing: float = 3.0
@export var window_frames: bool = true
@export var window_sills: bool = true

@export_group("Interior")
@export var generate_interior: bool = true
@export var generate_props: bool = true
@export_range(8.0, 60.0, 1.0) var max_room_area: float = 24.0
@export var stair_kind: Stair = Stair.AUTO
@export var balconies: bool = true
@export_range(1, 4, 1) var balcony_every_n_floors: int = 1
@export var ground_balcony: bool = false

@export_group("Roof Extras")
@export var roof_railing: bool = true
@export var rooftop_equipment: bool = true

@export_group("Interactive Editing")
## Custom openings cut into walls by the right-click tool. Each entry:
## {point: Vector2 (XZ on the wall line), width, height, sill, kind}
## Openings follow their wall when vertices move (stored by position, not
## edge index). Editable here or via the viewport right-click menu.
@export var custom_openings: Array[Dictionary] = []:
        set(v):
                custom_openings = v
                emit_changed()
## Entrance position override (XZ point near the wanted entrance edge).
## Vector2(INF, INF) = automatic (longest edge).
@export var entrance_point: Vector2 = Vector2(INF, INF):
        set(v):
                entrance_point = v
                emit_changed()
## Per-floor overrides (index 0 = ground floor): own facade material,
## window style, outset/setback and balcony switch.
@export var floor_overrides: Array[BFFloorOverride] = []

@export_group("Custom Models")
## Replace generated props with your own scenes: key = prop id ("sofa",
## "bed_double", "fridge", ...), value = PackedScene. The scene is
## instanced at the prop position, facing -Z (into the room). Generated
## geometry for that prop is skipped. Assigned scenes are baked into the
## scene at generation time (editor), never generated at game runtime.
@export var prop_scenes: Dictionary = {}
## Optional PackedScene replacing the whole generated window assembly
## (frame + glass). Instance origin = opening center, +Z faces OUTDOORS.
@export var window_scene: PackedScene
## Optional PackedScene replacing the generated door assembly.
@export var door_scene: PackedScene

@export_group("Output")
## One MeshInstance3D per floor (fast) instead of one per part (max editability).
@export var merge_geometry: bool = false
@export var generate_collision: bool = true
@export var props_collision: bool = false
@export var seed: int = 12345


func _init() -> void:
        if footprint == null:
                footprint = BFFootprint.create_rect(10, 8)


func clone_params() -> BFParams:
        var p := duplicate(true) as BFParams
        if p.footprint != null:
                p.footprint = footprint.duplicate(true) if footprint.can_duplicate() else footprint
        return p


## Convenience: adds a custom opening snapped onto the nearest wall edge.
## floor_i stores which floor was clicked (openings are per-floor).
## sill: vertical position of the window base (doors ignore it).
## Returns true when the opening landed on an edge.
func add_custom_opening(point: Vector2, kind: String, fp: BFFootprint, floor_h: float,
                floor_i := 0, sill := -1.0) -> bool:
        var n := fp.points.size()
        var best_d := 0.45
        var best := -1
        var t := 0.0
        for i in n:
                var a := fp.points[i]
                var b := fp.points[(i + 1) % n]
                var ab := b - a
                var l2 := ab.length_squared()
                if l2 < 0.0001:
                        continue
                var tt := clampf((point - a).dot(ab) / l2, 0.02, 0.98)
                var d := (a + ab * tt).distance_to(point)
                if d < best_d:
                        best_d = d
                        best = i
                        t = tt
        if best < 0:
                return false
        var on_edge := fp.points[best].lerp(fp.points[(best + 1) % n], t)
        var is_door := kind == "door"
        var w := door_width if is_door else window_width
        var h := door_height if is_door else window_height
        var s := 0.0 if is_door else (window_sill if sill < 0.0 else clampf(sill, 0.05, floor_h))
        if not is_door:
                # keep the window inside the floor: sill + height <= floor height
                h = minf(h, floor_h - s - 0.25)
                s = clampf(s, 0.05, maxf(0.05, floor_h - h - 0.2))
        custom_openings.append({"point": on_edge, "width": w, "height": h, "sill": s, "kind": kind, "floor": floor_i})
        emit_changed()
        return true


## Applies architecture-appropriate defaults (used by presets).
func apply_architecture_defaults() -> void:
        match architecture:
                ArchStyle.CLASSIC_HOUSE:
                        facade_material = "plaster_ext"
                        roof_kind = Roof.GABLE
                        roof_pitch = 0.6
                        window_style = WindowStyle.PUNCHED
                        window_frames = true
                ArchStyle.BRICK_APARTMENT:
                        facade_material = "brick_red"
                        roof_kind = Roof.FLAT
                        window_style = WindowStyle.PUNCHED
                        window_sills = true
                ArchStyle.MODERN:
                        facade_material = "facade_panel"
                        roof_kind = Roof.FLAT
                        window_style = WindowStyle.CURTAIN
                ArchStyle.OFFICE_TOWER:
                        facade_material = "concrete"
                        roof_kind = Roof.FLAT
                        window_style = WindowStyle.CURTAIN
                        window_spacing = 3.4
                _:
                        pass
        emit_changed()
