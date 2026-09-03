extends SceneTree
func _initialize() -> void:
	var b := ProceduralBuilding.new()
	get_root().add_child(b)
	var p := BFParams.new()
	b.params = p
	p.footprint = BFFootprint.create_L(16, 12)
	p.floors = 5
	p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
	p.apply_architecture_defaults()
	p.seed = 7
	b.generate()
	var seen := {}
	for mi in b.get_node("Generated").find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mat := mesh.surface_get_material(0)
		var mat_name: String = mat.resource_name if mat != null else "none"
		var key := mat_name
		seen[key] = seen.get(key, 0) + 1
	for k in seen:
		print(k, " x", seen[k])
	quit()
