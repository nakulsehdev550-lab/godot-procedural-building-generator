extends SceneTree
## v1.2.0 release QA: load the REAL zoo map scene (demo/zoo_map.tscn) and
## capture overview + eye-level shots for visual inspection.
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/qa_v12_shots.gd

const OUT := "/home/z/my-project/building-generator/renders/qa_v12"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await process_frame
	var packed: PackedScene = load("res://demo/zoo_map.tscn")
	if packed == null:
		push_error("zoo_map.tscn missing")
		quit(1)
		return
	var map := packed.instantiate()
	root.add_child(map)
	for f in 12:
		await process_frame
	# let physics settle buildings' runtime regeneration
	for f in 30:
		await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true

	# overview orbit of the whole zoo
	var focus := Vector3(0, 2, 0)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.35
		cam.position = focus + Vector3(cos(a) * 135.0, 62.0, sin(a) * 135.0)
		cam.look_at(focus)
		for f in 5:
			await process_frame
		root.get_texture().get_image().save_png("%s/overview_%02d.png" % [OUT, i])
		print("captured overview_%02d" % i)

	# eye-level street shots: approach 4 buildings from the plaza center
	var spots := [
		{"pos": Vector3(-58, 1.7, 0), "look": Vector3(-90, 5, 0)},    # west column
		{"pos": Vector3(58, 1.7, 0), "look": Vector3(90, 5, 0)},      # east column
		{"pos": Vector3(0, 1.7, -50), "look": Vector3(0, 5, -70)},    # north row
		{"pos": Vector3(0, 1.7, 50), "look": Vector3(0, 5, 70)},      # south row
	]
	for s_i in spots.size():
		cam.position = spots[s_i].pos
		cam.look_at(spots[s_i].look)
		for f in 5:
			await process_frame
		root.get_texture().get_image().save_png("%s/street_%02d.png" % [OUT, s_i])
		print("captured street_%02d" % s_i)

	# close-up of one building facade (window detail / z-fight check)
	cam.position = Vector3(-90 + 16.0, 4.5, 10.0)
	cam.look_at(Vector3(-90, 4.0, 0))
	for f in 5:
		await process_frame
	root.get_texture().get_image().save_png(OUT + "/facade_close.png")
	print("captured facade_close")
	print("QA V12 DONE")
	quit(0)
