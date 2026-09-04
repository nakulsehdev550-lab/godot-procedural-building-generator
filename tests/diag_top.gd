extends SceneTree
## Top-down X-ray diagnostic: renders floor-0 plan of the apartment_dogleg
## config from above, with upper floors hidden, to identify geometry bugs.

const OUT := "/tmp/diag"
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-85, 20, 0)
	sun.light_energy = 1.0
	root.add_child(sun)

	var b := ProceduralBuilding.new()
	root.add_child(b)
	b.params.footprint = BFFootprint.create_oval(13, 9)
	b.params.floors = 2
	b.params.architecture = BFParams.ArchStyle.MODERN
	b.params.roof_kind = BFParams.Roof.DOME
	b.params.window_style = BFParams.WindowStyle.CURTAIN
	b.params.stair_kind = BFParams.Stair.SPIRAL
	b.params.seed = 15
	b.generate()
	await process_frame

	# hide everything above floor 0 (ceiling slab + upper floors + roof)
	var gen := b.get_node("Generated")
	var fi := 0
	for i in range(1, b.params.floors):
		var fnode := gen.get_node_or_null("Floor_%02d" % i)
		if fnode != null:
			fnode.visible = false
	gen.get_node("Roof").visible = false
	# hide the ceiling slab of floor 0: it is the concrete surface named f00_XX_concrete
	# (single mesh holds slab+stairs concrete); instead raise camera above wall tops
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var fp: BFFootprint = b.params.footprint
	var sz := fp.size_xz()
	cam.position = Vector3(0, 2.05, 0.01)
	cam.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.35
	cam.far = 60.0
	cam.size = maxf(sz.x, sz.y) + 6.0
	for f in 6:
		await process_frame
	root.get_texture().get_image().save_png(OUT + "/apartment_top.png")
	print("saved top view")

	# closeup around the living room door from eye level for context
	var layout: Dictionary = b.last_room_layout.get(0, {})
	var walls: Array = layout.walls
	for r in layout.rooms:
		var room: BFPartitionerS.Room = r as BFPartitionerS.Room
		if room.kind == "living":
			var doors := BFPartitionerS.room_doors(room, walls)
			var c := room.rect.get_center()
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.position = Vector3(c.x, 1.6, c.y)
			if doors.size() > 0:
				var dp: Vector2 = doors[0].pos
				cam.look_at(Vector3(dp.x, 1.4, dp.y))
				print("living center=", c, " door=", dp)
			else:
				cam.look_at(Vector3(room.rect.end.x, 1.4, room.rect.position.y))
			for f in 6:
				await process_frame
			root.get_texture().get_image().save_png(OUT + "/apartment_living_eye.png")
			print("saved living eye view")
	quit(0)
