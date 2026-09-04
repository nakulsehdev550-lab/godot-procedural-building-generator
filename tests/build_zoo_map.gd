extends SceneTree
## Builds the walkable FPS zoo map: demo/zoo_map.tscn.
## 16 buildings on a plaza with paths + a first-person player who can walk
## inside every building and restyle them (E facade / R roof / G paint).
## Buildings are NOT baked into the tscn: they regenerate from seeded params
## on load (proves the runtime path); use Finalize for static baking.
## Run: godot --headless --path . --script res://tests/build_zoo_map.gd

const BFPlayerS := preload("res://demo/player.gd")
const BFZooS := preload("res://tests/zoo_configs.gd")


func _initialize() -> void:
        await process_frame
        var map := Node3D.new()
        map.name = "ZooMap"

        var env := WorldEnvironment.new()
        var e := Environment.new()
        var sky := Sky.new()
        var sky_mat := ProceduralSkyMaterial.new()
        sky_mat.sky_top_color = Color(0.35, 0.54, 0.8)
        sky_mat.sky_horizon_color = Color(0.74, 0.81, 0.86)
        sky_mat.ground_bottom_color = Color(0.22, 0.24, 0.25)
        sky_mat.ground_horizon_color = Color(0.68, 0.74, 0.78)
        sky.sky_material = sky_mat
        e.background_mode = Environment.BG_SKY
        e.sky = sky
        e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        e.ambient_light_energy = 0.85
        e.tonemap_mode = Environment.TONE_MAPPER_ACES
        env.environment = e
        map.add_child(env)

        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-46, -38, 0)
        sun.light_energy = 1.1
        sun.shadow_enabled = true
        map.add_child(sun)

        # ground
        var ground := MeshInstance3D.new()
        var gm := PlaneMesh.new()
        gm.size = Vector2(260, 200)
        ground.mesh = gm
        ground.mesh.surface_set_material(0, _mat(Color(0.36, 0.42, 0.3)))
        ground.name = "Ground"
        map.add_child(ground)

        # central + cross paths
        var path_mat := _mat(Color(0.42, 0.4, 0.37))
        for strip in [[Vector2(0, 0), Vector2(250, 6)], [Vector2(0, 0), Vector2(6, 190)]]:
                var pmi := MeshInstance3D.new()
                var bm := BoxMesh.new()
                bm.size = Vector3(strip[1].x, 0.06, strip[1].y)
                pmi.mesh = bm
                pmi.mesh.surface_set_material(0, path_mat)
                pmi.position = Vector3((strip[0] as Vector2).x, 0.03, (strip[0] as Vector2).y)
                pmi.name = "Path_%d" % map.get_child_count()
                map.add_child(pmi)

        # buildings: 4 columns x 4 rows
        var zoo := BFZooS.all()
        var cols := [-90, -30, 30, 90]
        var rows := [-70, -24, 24, 70]
        var i := 0
        for entry in zoo:
                var b := ProceduralBuilding.new()
                b.name = entry.name
                b.params = BFParams.new()  # map isn't in-tree yet: _ready hasn't run
                (entry.cfg as Callable).call(b.params)
                b.position = Vector3(cols[i % 4], 0, rows[int(i / 4.0)])
                map.add_child(b)
                b.generate()
                i += 1
                print("  built %s (%s)" % [entry.name, b.stats])

        # player at the path start
        var player := CharacterBody3D.new()
        player.name = "Player"
        player.set_script(BFPlayerS)
        player.position = Vector3(-115, 0.2, 0)
        map.add_child(player)

        var packed := PackedScene.new()
        _own(map, map)
        packed.pack(map)
        var err := ResourceSaver.save(packed, "res://demo/zoo_map.tscn")
        print("ZOO MAP SAVED: ", error_string(err))
        quit(0)


func _own(n: Node, root: Node) -> void:
        for c in n.get_children():
                # Generated/Collision subtrees stay unowned: they regenerate at
                # runtime. Player rig children too (script rebuilds on _ready)
                # but the Player NODE itself must be saved (with its script).
                if _inside_baked(c) or _inside_player_rig(c):
                        continue
                c.owner = root
                _own(c, root)


func _inside_player_rig(n: Node) -> bool:
        var p := n.get_parent()
        while p != null:
                if p is BFTestPlayer:
                        return true
                p = p.get_parent()
        return false


func _inside_baked(n: Node) -> bool:
        var p := n.get_parent()
        while p != null:
                if p.name == "Generated" or p.name == "Collision":
                        return true
                p = p.get_parent()
        return false


func _mat(c: Color) -> StandardMaterial3D:
        var m := StandardMaterial3D.new()
        m.albedo_color = c
        m.roughness = 0.95
        return m
