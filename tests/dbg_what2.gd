extends SceneTree
const OUT := "/tmp/diag"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 40, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var b := ProceduralBuilding.new()
	root.add_child(b)
	b.params = BFParams.new()
	b.params.footprint = BFFootprint.create_rect(11, 8.5)
	b.params.floors = 2
	b.params.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
	b.params.roof_kind = BFParams.Roof.GABLE
	b.params.stair_kind = BFParams.Stair.STRAIGHT
	b.params.seed = 42
	b.generate()
	await process_frame
	var layout: Dictionary = b.last_room_layout.get(0, {})
	var door := Vector2(-3.7, -1.406567)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var gen := b.get_node("Generated")
	var variants := {
		"all": [],
		"no_int": ["f00_05_plaster_int"],
		"no_conc": ["f00_04_concrete"],
		"no_wood": ["f00_03_wood_dark"],
	}
	for vname in variants:
		var hide: Array = variants[vname]
		for mi in gen.find_children("*", "MeshInstance3D", true, false):
			var mi3 := mi as MeshInstance3D
			mi3.visible = not hide.any(func(h): return mi3.name.begins_with(h))
		cam.position = Vector3(door.x, 1.6, door.y - 1.6)
		cam.look_at(Vector3(door.x, 1.3, door.y))
		for f in 8:
			await process_frame
		root.get_texture().get_image().save_png("%s/door_%s.png" % [OUT, vname])
		print("saved ", vname)
	quit(0)
