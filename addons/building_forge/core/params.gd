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
enum Roof { FLAT, GABLE, HIP, CONE, DOME }
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
@export_range(0.0, 1.2, 0.05) var roof_overhang: float = 0.45
@export var window_style: WindowStyle = WindowStyle.PUNCHED
## Path to a texture folder set (swap stylized/lowpoly/realistic here).
@export_dir var texture_style_dir: String = "res://addons/building_forge/textures/baked"

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
