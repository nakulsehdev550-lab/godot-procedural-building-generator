extends SceneTree
## Generates demo scenes: demo_house.tscn (main), demo_apartment.tscn,
## demo_villa.tscn, demo_tower.tscn
func _initialize() -> void:
	await process_frame
	_make("demo_house", func(p):
		p.footprint = BFFootprint.create_rect(11, 8.5)
		p.floors = 2
		p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
		p.roof_kind = BFParams.Roof.GABLE
		p.seed = 42)
	_make("demo_apartment", func(p):
		p.footprint = BFFootprint.create_L(16, 12)
		p.floors = 5
		p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
		p.apply_architecture_defaults()
		p.seed = 7)
	_make("demo_villa", func(p):
		p.footprint = BFFootprint.create_L(14, 11)
		p.floors = 2
		p.architecture = BFParams.ArchStyle.MODERN
		p.apply_architecture_defaults()
		p.seed = 11)
	_make("demo_tower", func(p):
		p.footprint = BFFootprint.create_circle(8)
		p.floors = 8
		p.roof_kind = BFParams.Roof.CONE
		p.window_style = BFParams.WindowStyle.CURTAIN
		p.stair_kind = BFParams.Stair.SPIRAL
		p.seed = 3)
	quit(0)


func _make(demo_name: String, cfg: Callable) -> void:
	var root_node := Node3D.new()
	root_node.name = demo_name.to_pascal_case()
	# environment
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.55, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.86)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root_node.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root_node.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(220, 220)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.42, 0.33)
	gmat.roughness = 0.95
	ground.mesh.surface_set_material(0, gmat)
	root_node.add_child(ground)
	# building
	var b := ProceduralBuilding.new()
	b.name = "Building"
	var bp := BFParams.new()
	b.params = bp
	cfg.call(bp)
	bp.emit_changed()
	var ps := PackedScene.new()
	ps.pack(root_node)
	var err := ResourceSaver.save(ps, "res://demo/%s.tscn" % demo_name)
	print("saved %s: err=%d" % [demo_name, err])
