extends SceneTree
## Visual QA renderer: builds demo scenes, captures turntable PNGs.
## Run under xvfb with GL compatibility:
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/render_qa.gd

const OUT := "/home/z/my-project/building-generator/renders"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	_setup_world()
	await _capture_all()
	quit(0)


func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.55, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.86)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.24)
	sky_mat.ground_horizon_color = Color(0.68, 0.74, 0.78)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(300, 300)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.33, 0.28)
	gmat.roughness = 0.95
	ground.mesh.surface_set_material(0, gmat)
	root.add_child(ground)


func _make_building(cfg: Callable) -> ProceduralBuilding:
	var b := ProceduralBuilding.new()
	root.add_child(b)
	cfg.call(b.params)
	b.params.emit_changed()
	b.generate()
	return b


func _capture_orbit(tag: String, focus: Vector3, radius: float, height: float, shots := 8) -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	for i in shots:
		var a := TAU * float(i) / float(shots)
		cam.position = focus + Vector3(cos(a) * radius, height, sin(a) * radius)
		cam.look_at(focus + Vector3(0, height * 0.25, 0))
		for f in 6:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_%02d.png" % [OUT, tag, i])
		print("captured %s_%02d" % [tag, i])
	cam.queue_free()


func _capture_all() -> void:
	# 1. suburban house
	var house := _make_building(func(p):
		p.footprint = BFFootprint.create_rect(11, 8.5)
		p.floors = 2
		p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
		p.roof_kind = BFParams.Roof.GABLE
		p.seed = 42)
	await _capture_orbit("house", Vector3(0, 3, 0), 22.0, 9.0, 8)
	house.queue_free()

	# 2. brick apartment
	var apt := _make_building(func(p):
		p.footprint = BFFootprint.create_L(16, 12)
		p.floors = 5
		p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
		p.apply_architecture_defaults()
		p.seed = 7)
	await _capture_orbit("apartment", Vector3(0, 8, 0), 34.0, 16.0, 8)
	apt.queue_free()

	# 3. modern villa with curtain wall
	var villa := _make_building(func(p):
		p.footprint = BFFootprint.create_L(14, 11)
		p.floors = 2
		p.architecture = BFParams.ArchStyle.MODERN
		p.apply_architecture_defaults()
		p.seed = 11)
	await _capture_orbit("villa", Vector3(0, 3, 0), 24.0, 8.0, 8)
	villa.queue_free()

	# 4. circular tower
	var tower := _make_building(func(p):
		p.footprint = BFFootprint.create_circle(8)
		p.floors = 8
		p.roof_kind = BFParams.Roof.CONE
		p.window_style = BFParams.WindowStyle.CURTAIN
		p.stair_kind = BFParams.Stair.SPIRAL
		p.seed = 3)
	await _capture_orbit("round_tower", Vector3(0, 14, 0), 36.0, 24.0, 8)
	tower.queue_free()

	# 5. interior shot: cutaway house (top floors hidden by camera inside)
	var interior := _make_building(func(p):
		p.footprint = BFFootprint.create_rect(12, 9)
		p.floors = 2
		p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
		p.roof_kind = BFParams.Roof.FLAT
		p.seed = 42)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.position = Vector3(4.5, 1.7, 3.5)
	cam.look_at(Vector3(-2, 1.2, -2))
	for f in 8:
		await process_frame
	var img2 := root.get_texture().get_image()
	img2.save_png(OUT + "/interior_ground.png")
	print("captured interior_ground")
	cam.queue_free()
	interior.queue_free()
