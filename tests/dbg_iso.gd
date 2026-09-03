extends SceneTree
func _initialize() -> void:
	await process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.27, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.8)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	root.add_child(sun)
	# reference box with same material
	var ref := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 3, 2)
	ref.mesh = bm
	ref.mesh.surface_set_material(0, BFMaterialLibrary.get_material("plaster_ext"))
	ref.position = Vector3(-8, 1.5, 0)
	root.add_child(ref)
	# one-floor building, no roof
	var b := ProceduralBuilding.new()
	root.add_child(b)
	var p := b.params
	p.footprint = BFFootprint.create_rect(8, 6)
	p.floors = 1
	p.roof_kind = BFParams.Roof.FLAT
	p.roof_railing = false
	p.rooftop_equipment = false
	p.balconies = false
	p.seed = 42
	p.emit_changed()
	b.generate()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 2, 14)
	cam.look_at(Vector3(-2, 1.5, 0))
	for f in 8:
		await process_frame
	root.get_texture().get_image().save_png("renders/isolation.png")
	print("saved isolation")
	quit()
