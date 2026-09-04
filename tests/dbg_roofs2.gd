extends SceneTree
## One close-up per roof kind from the "bad" diagonal + a low angle that
## catches soffits and eave bands.

const OUT := "/tmp/dbg_roofs"


func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute(OUT)
        await process_frame
        var env := WorldEnvironment.new()
        var e := Environment.new()
        e.background_mode = Environment.BG_COLOR
        e.background_color = Color(0.25, 0.28, 0.33)
        e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        e.ambient_light_color = Color.WHITE
        e.ambient_light_energy = 0.6
        env.environment = e
        root.add_child(env)
        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-50, -35, 0)
        sun.light_energy = 1.1
        root.add_child(sun)

        var cases := [
                ["hip_T", BFFootprint.create_T(13, 10), BFParams.Roof.HIP],
                ["mansard_U", BFFootprint.create_U(19, 14), BFParams.Roof.MANSARD],
                ["gambrel", BFFootprint.create_rect(10, 8), BFParams.Roof.GAMBREL],
                ["shed", BFFootprint.create_rect(10, 8), BFParams.Roof.SHED],
                ["hip_L", BFFootprint.create_L(9, 7), BFParams.Roof.HIP],
        ]
        var cam := Camera3D.new()
        root.add_child(cam)
        cam.current = true
        for i in cases.size():
                var b := ProceduralBuilding.new()
                b.params = BFParams.new()
                b.params.footprint = cases[i][1]
                b.params.floors = 1
                b.params.roof_kind = cases[i][2]
                b.params.generate_interior = false
                b.params.generate_collision = false
                b.params.facade_bands = false
                b.params.balconies = false
                b.position = Vector3(0, 0, 0)
                root.add_child(b)
                b.generate()
                await process_frame
                var fp: BFFootprint = cases[i][1]
                var r: float = maxf(fp.size_xz().x, fp.size_xz().y) * 1.4 + 6.0
                cam.position = Vector3(r * 0.75, r * 0.55, r * 0.75)
                cam.look_at(Vector3(0, 2.5, 0))
                for f in 3:
                        await process_frame
                root.get_texture().get_image().save_png("%s/%s.png" % [OUT, cases[i][0]])
                b.queue_free()
                await process_frame
        print("CLOSEUPS DONE")
        quit(0)
