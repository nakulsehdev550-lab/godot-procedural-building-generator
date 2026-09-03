extends SceneTree
## Headless texture baking runner:
##   godot --headless --path . --script res://addons/building_forge/textures/bake_all.gd
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var count: int = BFTextureBaker.bake_all()
	print("[BF] baked %d material sets in %.1fs" % [count, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
