extends SceneTree
const OUT := "/tmp/diag"
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")
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
        sun.rotation_degrees = Vector3(-60, 30, 0)
        sun.light_energy = 1.1
        root.add_child(sun)
        var b := ProceduralBuilding.new()
        root.add_child(b)
        b.params.footprint = BFFootprint.create_circle(8)
        b.params.floors = 3
        b.params.roof_kind = BFParams.Roof.CONE
        b.params.window_style = BFParams.WindowStyle.CURTAIN
        b.params.stair_kind = BFParams.Stair.SPIRAL
        b.params.seed = 3
        b.generate()
        await process_frame
        var gen := b.get_node("Generated")
        for i in range(1, 3):
                (gen.get_node("Floor_%02d" % i) as Node3D).visible = false
        (gen.get_node("Roof") as Node3D).visible = false
        var cam := Camera3D.new()
        root.add_child(cam)
        cam.current = true
        # eye level inside the actual stair room, from its corner toward center
        var layout: Dictionary = b.last_room_layout.get(0, {})
        var stair_rect: Rect2 = Rect2()
        for r in layout.rooms:
                if (r as BFPartitionerS.Room).kind == "stair":
                        stair_rect = (r as BFPartitionerS.Room).rect
        print("stair rect: ", stair_rect)
        var sc := stair_rect.get_center()
        cam.position = Vector3(sc.x, 2.05, sc.y + 0.01)
        cam.look_at(Vector3(sc.x, 0, sc.y), Vector3(0, 0, -1))
        cam.projection = Camera3D.PROJECTION_ORTHOGONAL
        cam.near = 0.35
        cam.size = 6.0
        for f in 8:
                await process_frame
        root.get_texture().get_image().save_png(OUT + "/spiral_fixed.png")
        print("saved spiral")
        # facade exterior check
        var cam2 := Camera3D.new()
        root.add_child(cam2)
        cam2.current = true
        cam2.position = Vector3(22, 7, 10)
        cam2.look_at(Vector3.ZERO)
        for f in 8:
                await process_frame
        root.get_texture().get_image().save_png(OUT + "/tower_ext.png")
        print("saved ext")
        quit(0)
