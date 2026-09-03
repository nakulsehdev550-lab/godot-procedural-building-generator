extends SceneTree
func _initialize() -> void:
	await process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 140, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	root.add_child(sun)
	var b := ProceduralBuilding.new()
	root.add_child(b)
	var p := BFParams.new()
	b.params = p
	p.footprint = BFFootprint.create_L(16, 12)
	p.floors = 5
	p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
	p.apply_architecture_defaults()
	p.seed = 7
	b.generate()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.position = Vector3(14, 9, -4)
	cam.look_at(Vector3(0.8, 8, -3))
	for f in 8:
		await process_frame
	root.get_texture().get_image().save_png("renders/notch.png")
	print("saved notch")
	quit()
