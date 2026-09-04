@tool
class_name BFFloorOverride
extends Resource
## Per-floor overrides for the building generator (index 0 = ground floor).
## Unset / "inherit" fields fall back to the global BFParams value.
## Inspired by Houdini Labs' Building Generator floor overrides and CityEngine
## facade splits: "shop base + apartments above + penthouse" in one building.

@export_group("Floor Override")
@export var enabled := true
## Facade material id for this floor; "inherit" uses params.facade_material.
@export var facade_material := "inherit"
## Window style for this floor; -1 inherits params.window_style.
@export_range(-1, 2, 1) var window_style := -1
## Footprint outset in meters for this floor. Positive = overhang (jettied
## medieval floors, cornices), negative = setback (tower terraces).
@export_range(-2.0, 2.0, 0.05) var outset := 0.0
## Balconies on this floor; -1 inherits, 0 forces off, 1 forces on.
@export_range(-1, 1, 1) var balconies := -1


func applies() -> bool:
        return enabled


func effective_facade(global_id: String) -> String:
        return facade_material if facade_material != "" and facade_material != "inherit" else global_id


func effective_window_style(global_style: int) -> int:
        return window_style if window_style >= 0 else global_style


func effective_balconies(global_on: bool) -> bool:
        return balconies == 1 if balconies >= 0 else global_on
