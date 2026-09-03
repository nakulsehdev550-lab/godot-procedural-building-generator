extends SceneTree
## Compound movie scene: three buildings + orbiting camera.
func _initialize() -> void:
	var main := Node3D.new()
	root.add_child(main)
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
	main.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	main.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(400, 400)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.42, 0.33)
	gmat.roughness = 0.95
	ground.mesh.surface_set_material(0, gmat)
	main.add_child(ground)
	_spawn(main, "res://demo/demo_house.tscn", Vector3(-26, 0, 6))
	_spawn(main, "res://demo/demo_apartment.tscn", Vector3(8, 0, -8))
	_spawn(main, "res://demo/demo_villa.tscn", Vector3(-12, 0, -26))
	_spawn(main, "res://demo/demo_tower.tscn", Vector3(30, 0, 22))
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var orb := Orbiter.new()
	orb.cam = cam
	main.add_child(orb)
func _spawn(main: Node3D, path: String, pos: Vector3) -> void:
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	inst.position = pos
	main.add_child(inst)
class Orbiter extends Node:
	var cam: Camera3D
	var t := 0.0
	func _process(delta: float) -> void:
		t += delta
		var a := 0.4 + t * 0.22
		var r := 52.0 - minf(t * 0.8, 14.0)
		cam.position = Vector3(cos(a) * r, 14.0 + sin(t * 0.3) * 6.0, sin(a) * r)
		cam.look_at(Vector3(0, 7, 0))
