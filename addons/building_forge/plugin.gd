@tool
extends EditorPlugin
# BuildingForge editor plugin entry point.
# Full editor integration (dock, draw tool, gizmos, inspector buttons)
# is registered here. Runtime generation code lives in core/.


func _enter_tree() -> void:
	print("[BuildingForge] plugin loaded")


func _exit_tree() -> void:
	print("[BuildingForge] plugin unloaded")
