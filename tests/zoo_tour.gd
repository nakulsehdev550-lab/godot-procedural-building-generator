extends SceneTree
## House zoo + interior tour renderer: generates a zoo of buildings covering
## the settings matrix, captures exterior orbits AND interior eye-level
## walkthrough shots of every room (per floor), plus a manifest for review.
## Run under xvfb with GL compatibility:
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/zoo_tour.gd

const OUT := "/home/z/my-project/building-generator/renders/zoo"
const MAX_ROOM_SHOTS_PER_FLOOR := 7
const BFPartitionerS := preload("res://addons/building_forge/core/interior/room_partitioner.gd")


func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute(OUT)
        await process_frame
        _setup_world()
        var manifest: Array = []
        var zoo := _zoo_configs()
        for i in zoo.size():
                var entry: Dictionary = zoo[i]
                var data := await _tour_building(entry, i)
                manifest.append(data)
                # rewrite manifest after every building so partial runs survive
                var fw := FileAccess.open(OUT + "/manifest.json", FileAccess.WRITE)
                if fw != null:
                        fw.store_string(JSON.stringify(manifest, "  "))
                        fw.close()
        print("ZOO DONE: %d buildings" % zoo.size())
        quit(0)


func _zoo_configs() -> Array:
        return BFZooConfigs.all()


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
        e.ambient_light_energy = 0.75
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
        gm.size = Vector2(400, 400)
        ground.mesh = gm
        var gmat := StandardMaterial3D.new()
        gmat.albedo_color = Color(0.3, 0.33, 0.28)
        gmat.roughness = 0.95
        ground.mesh.surface_set_material(0, gmat)
        root.add_child(ground)


func _tour_building(entry: Dictionary, idx: int) -> Dictionary:
        var tag: String = entry.name
        var bdir := OUT + "/" + tag
        DirAccess.make_dir_recursive_absolute(bdir)
        var b := ProceduralBuilding.new()
        root.add_child(b)
        (entry.cfg as Callable).call(b.params)
        b.generate()
        await process_frame
        var data := {"name": tag, "floors": b.params.floors, "stats": b.stats, "rooms": []}

        # exterior orbit
        var fp: BFFootprint = b.params.footprint
        var sz := fp.size_xz()
        var ext_h: float = clampf(b.params.floors * b.params.floor_height * 0.85 + 4.0, 5.0, 46.0)
        var radius: float = maxf(sz.x, sz.y) * 1.15 + 8.0
        var cam := Camera3D.new()
        root.add_child(cam)
        cam.current = true
        var fill := OmniLight3D.new()
        fill.omni_range = 14.0
        fill.light_energy = 0.0  # off for exteriors
        cam.add_child(fill)
        for i in 6:
                var a := TAU * float(i) / 6.0 + 0.523  # 30 deg offset: face-on views of both axes
                cam.position = Vector3(cos(a) * radius, ext_h, sin(a) * radius)
                cam.look_at(Vector3(0, ext_h * 0.35, 0))
                for f in 3:
                        await process_frame
                root.get_texture().get_image().save_png("%s/ext_%02d.png" % [bdir, i])
        print("  %s: exterior done" % tag)

        # interior walkthrough: every room, eye level, looking at its door
        var fh := b.params.floor_height
        var floors_toured: Array = []
        for fi in b.params.floors:
                if b.params.floors > 6 and fi != 0 and fi != 1 and fi != b.params.floors - 1:
                        continue
                floors_toured.append(fi)
        for fi in floors_toured:
                var layout: Dictionary = b.last_room_layout.get(fi, {})
                if layout.is_empty():
                        continue
                var rooms: Array = layout.rooms
                var walls: Array = layout.walls
                var base := float(fi) * fh
                var shots := 0
                var kinds := {}
                for r in rooms:
                        var room: BFPartitionerS.Room = r as BFPartitionerS.Room
                        var k: String = room.kind
                        kinds[k] = kinds.get(k, 0) + 1
                        if shots >= MAX_ROOM_SHOTS_PER_FLOOR:
                                continue
                        var rect: Rect2 = room.rect
                        var eye := Vector3(rect.get_center().x, base + 1.55, rect.get_center().y)
                        # look toward the room's first door (shows connectivity), else diagonal
                        var doors := BFPartitionerS.room_doors(room, walls)
                        var target: Vector3
                        if doors.size() > 0:
                                var dp: Vector2 = doors[0].pos
                                target = Vector3(dp.x, base + 1.3, dp.y)
                        else:
                                target = Vector3(rect.position.x, base + 1.2, rect.end.y)
                        if eye.distance_to(target) < 0.5:
                                target = Vector3(rect.end.x, base + 1.3, rect.position.y)
                        cam.position = eye
                        cam.look_at(target)
                        fill.light_energy = 0.9  # interior fill light
                        for f in 3:
                                await process_frame
                        root.get_texture().get_image().save_png("%s/f%02d_%s_%02d.png" % [bdir, fi, k, shots])
                        shots += 1
                data.rooms.append({"floor": fi, "kinds": kinds, "shots": shots})
                print("  %s: floor %d toured (%d shots)" % [tag, fi, shots])
        cam.queue_free()
        b.queue_free()
        await process_frame
        await process_frame
        return data
