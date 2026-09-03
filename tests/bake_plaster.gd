extends SceneTree
func _initialize() -> void:
	BFTextureBaker.bake_material("plaster_ext")
	BFTextureBaker.bake_material("plaster_int")
	print("plaster rebaked")
	quit()
