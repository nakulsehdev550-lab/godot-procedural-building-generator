@tool
class_name BFPropFactory
extends RefCounted
## Procedural furniture factory. Every prop is a small multi-box assembly
## with pivot at floor level, centered on origin, facing -Z (forward).
## Registry pattern: id -> build fn collecting boxes per material id, so
## props merge cleanly in merge mode.

const BFMeshUtilS := preload("res://addons/building_forge/core/geometry/mesh_util.gd")

const T := Vector2(0.5, 0.5)  # default uv tile for mesh-mapped mats


static func _registry() -> Dictionary:
        return {
                "bed_single": _bed.bind(0.95, 2.0),
                "bed_double": _bed.bind(1.5, 2.05),
                "nightstand": _nightstand,
                "wardrobe": _wardrobe,
                "desk": _desk,
                "chair": _chair,
                "sofa": _sofa,
                "coffee_table": _coffee_table,
                "tv_console": _tv_console,
                "bookshelf": _bookshelf,
                "dining_table": _dining_table,
                "dining_chair": _dining_chair,
                "floor_lamp": _floor_lamp,
                "plant": _plant,
                "rug": _rug,
                "kitchen_counter": _kitchen_counter,
                "fridge": _fridge,
                "stove": _stove,
                "toilet": _toilet,
                "washbasin": _washbasin,
                "bathtub": _bathtub,
                "shower": _shower,
                "desk_pc": _desk_pc,
                "washing_machine": _washing_machine,
        }


static func has_prop(id: String) -> bool:
        return _registry().has(id)


## Builds prop `id` into per-material SurfaceTools (dict id->SurfaceTool).
## Returns local AABB for placement logic.
static func build(id: String, sts: Dictionary, rng: RandomNumberGenerator) -> AABB:
        if not _registry().has(id):
                return AABB(Vector3.ZERO, Vector3.ZERO)
        var fn: Callable = _registry()[id]
        var box := BoxCollector.new()
        fn.call(box, rng)
        for mat_id in box.parts:
                var st: SurfaceTool = sts.get(mat_id)
                if st == null:
                        continue
                for entry in box.parts[mat_id]:
                        if entry[2] != null:
                                for cyl in entry[2]:
                                        BFMeshUtilS.add_cylinder(st, cyl[0], cyl[1], cyl[2], cyl[3], T, true, true)
                        else:
                                BFMeshUtilS.add_box(st, entry[0], entry[1], T)
        return box.aabb


## Collects boxes/cylinders per material until flushed.
class BoxCollector:
        extends RefCounted
        var parts: Dictionary = {}
        var aabb := AABB(Vector3.ZERO, Vector3.ZERO)

        func box(mat_id: String, xf: Transform3D, size: Vector3) -> void:
                if not parts.has(mat_id):
                        parts[mat_id] = []
                parts[mat_id].append([xf, size, null])
                _grow(xf * AABB(-size * 0.5, size))

        func cyl(mat_id: String, xf: Transform3D, radius: float, height: float, segs := 10) -> void:
                if not parts.has(mat_id):
                        parts[mat_id] = []
                parts[mat_id].append([Transform3D(), Vector3.ZERO, [[xf, radius, height, segs]]])
                _grow(AABB(Vector3(xf.origin.x - radius, xf.origin.y - height * 0.5, xf.origin.z - radius), Vector3(radius * 2, height, radius * 2)))

        func _grow(a: AABB) -> void:
                if aabb.size == Vector3.ZERO:
                        aabb = a
                else:
                        aabb = aabb.merge(a)


# ---------- ternary-free helpers (4.3 compat) -------------------------------

static func _sgn(v: float) -> float:
        return -1.0 if v < 0.0 else 1.0


# ---------- furniture builders (forward = -Z) ------------------------------

static func _bed(b: BoxCollector, rng: RandomNumberGenerator, w: float, d: float) -> void:
        var frame_h := 0.32
        var mat_h := 0.22
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, frame_h * 0.5 + 0.04, 0)), Vector3(w, 0.08, d))
        for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.04), 0.05, sz * (d * 0.5 - 0.04))), Vector3(0.07, 0.1, 0.07))
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.55, -d * 0.5 + 0.03)), Vector3(w, 0.55, 0.06))
        b.box("fabric_bed", Transform3D(Basis.IDENTITY, Vector3(0, frame_h + mat_h * 0.5 + 0.06, d * 0.03)), Vector3(w - 0.08, mat_h, d - 0.16))
        var pillows := 1 if w < 1.2 else 2
        for i in pillows:
                var px := 0.0 if pillows == 1 else (-w * 0.22 if i == 0 else w * 0.22)
                b.box("fabric_bed", Transform3D(Basis.IDENTITY, Vector3(px, frame_h + mat_h + 0.10, -d * 0.5 + 0.30)), Vector3(w * 0.42, 0.11, 0.4))
        b.box("fabric_sofa", Transform3D(Basis.IDENTITY, Vector3(0, frame_h + mat_h + 0.10, d * 0.16)), Vector3(w - 0.04, 0.06, d * 0.62))


static func _nightstand(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Vector3(0.45, 0.5, 0.4))
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(0, 0.32, 0.205)), Vector3(0.37, 0.14, 0.02))
        b.cyl("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.32, 0.23)), 0.012, 0.1, 8)


static func _wardrobe(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 1.05, 0)), Vector3(1.2, 2.1, 0.6))
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(-0.29, 1.0, 0.31)), Vector3(0.56, 1.9, 0.03))
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(0.29, 1.0, 0.31)), Vector3(0.56, 1.9, 0.03))
        b.cyl("metal_dark", Transform3D(Basis.IDENTITY, Vector3(-0.03, 1.05, 0.34)), 0.012, 0.14, 8)
        b.cyl("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0.03, 1.05, 0.34)), 0.012, 0.14, 8)


static func _desk(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(0, 0.74, 0)), Vector3(1.4, 0.05, 0.7))
        for sx in [-1.0, 1.0]:
                b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(sx * 0.65, 0.37, 0)), Vector3(0.06, 0.74, 0.65))
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.45, -0.28)), Vector3(1.2, 0.3, 0.04))


static func _desk_pc(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        _desk(b, rng)
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.9, -0.12)), Vector3(0.55, 0.33, 0.03))
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.795, -0.1)), Vector3(0.16, 0.12, 0.14))
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.775, 0.02)), Vector3(0.42, 0.02, 0.15))


static func _chair(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("fabric_sofa", Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Vector3(0.45, 0.07, 0.45))
        b.box("fabric_sofa", Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0.2)), Vector3(0.45, 0.55, 0.06))
        for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                        b.cyl("metal_dark", Transform3D(Basis.IDENTITY, Vector3(sx * 0.19, 0.22, sz * 0.19)), 0.02, 0.44, 8)


static func _dining_chair(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        _chair(b, rng)


static func _sofa(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        var w := 2.0
        b.box("fabric_sofa", Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0.15)), Vector3(w, 0.32, 0.85))
        b.box("fabric_sofa", Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0.5)), Vector3(w, 0.62, 0.22))
        for sx in [-1.0, 1.0]:
                b.box("fabric_sofa", Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.11), 0.55, 0.1)), Vector3(0.22, 0.3, 0.8))
        for i in 2:
                var px := -0.5 if i == 0 else 0.5
                b.box("fabric_sofa", Transform3D(Basis.IDENTITY, Vector3(px, 0.5, 0.28)), Vector3(0.9, 0.16, 0.55))
        for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                        b.cyl("wood_dark", Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.12), 0.06, 0.15 + sz * 0.3)), 0.025, 0.12, 8)


static func _coffee_table(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(0, 0.42, 0)), Vector3(1.0, 0.05, 0.55))
        for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                        b.cyl("wood_dark", Transform3D(Basis.IDENTITY, Vector3(sx * 0.42, 0.21, sz * 0.2)), 0.025, 0.42, 8)


static func _tv_console(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.26, 0)), Vector3(1.6, 0.5, 0.42))
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), Vector3(1.15, 0.65, 0.05))
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.56, 0)), Vector3(0.12, 0.12, 0.12))


static func _bookshelf(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)), Vector3(0.9, 1.8, 0.3))
        for i in 4:
                b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(0, 0.35 + i * 0.42, 0.02)), Vector3(0.82, 0.03, 0.26))
                var nbooks := rng.randi_range(3, 6)
                for k in nbooks:
                        var col: String = ["fabric_sofa", "metal_dark", "brick_red"][k % 3]
                        var bw := rng.randf_range(0.03, 0.06)
                        b.box(col, Transform3D(Basis.IDENTITY, Vector3(-0.35 + k * 0.12, 0.38 + i * 0.42 + 0.11, 0.02)), Vector3(bw, 0.22, 0.2))


static func _dining_table(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), Vector3(1.5, 0.06, 0.9))
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.375, 0)), Vector3(0.12, 0.75, 0.7))
        for sz in [-1.0, 1.0]:
                b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, sz * 0.3)), Vector3(1.3, 0.06, 0.06))


static func _floor_lamp(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.cyl("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), 0.02, 1.5, 8)
        b.cyl("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), 0.14, 0.04, 10)
        b.cyl("fabric_bed", Transform3D(Basis.IDENTITY, Vector3(0, 1.58, 0)), 0.14, 0.22, 10)


static func _plant(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.cyl("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.14, 0)), 0.13, 0.28, 10)
        for i in 5:
                var a := TAU * float(i) / 5.0 + 0.4
                var leaf := Basis(Vector3(0, 0, 1), 0.7) * Basis(Vector3.UP, a)
                b.box("carpet", Transform3D(leaf, Vector3(cos(a) * 0.05, 0.45, sin(a) * 0.05)), Vector3(0.05, 0.4, 0.02))


static func _rug(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("carpet", Transform3D(Basis.IDENTITY, Vector3(0, 0.012, 0)), Vector3(2.0, 0.024, 1.4))


static func _kitchen_counter(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(0, 0.44, 0)), Vector3(2.0, 0.88, 0.6))
        b.box("stone", Transform3D(Basis.IDENTITY, Vector3(0, 0.905, 0.0)), Vector3(2.06, 0.05, 0.64))
        b.box("wood_dark", Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.6, 0.31)), Vector3(0.9, 0.7, 0.02))
        b.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.55, 0.87, 0)), Vector3(0.5, 0.12, 0.42))
        b.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(0.55, 1.05, -0.18)), 0.018, 0.3, 8)
        b.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.55, 1.16, -0.12)), Vector3(0.03, 0.03, 0.16))
        b.box("wood_light", Transform3D(Basis.IDENTITY, Vector3(-0.4, 1.7, -0.12)), Vector3(1.6, 0.6, 0.34))


static func _fridge(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)), Vector3(0.7, 1.8, 0.68))
        b.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.33, 1.0, 0.35)), Vector3(0.03, 0.5, 0.04))
        b.box("metal", Transform3D(Basis.IDENTITY, Vector3(0.33, 0.45, 0.35)), Vector3(0.03, 0.5, 0.04))


static func _stove(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.44, 0)), Vector3(0.6, 0.88, 0.6))
        b.box("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.895, 0)), Vector3(0.58, 0.02, 0.58))
        for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                        b.cyl("metal_dark", Transform3D(Basis.IDENTITY, Vector3(sx * 0.14, 0.91, sz * 0.14)), 0.09, 0.015, 12)
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0.31)), Vector3(0.5, 0.2, 0.03))


static func _toilet(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0.05)), Vector3(0.38, 0.4, 0.5))
        b.cyl("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.42, 0.08)), 0.19, 0.06, 12)
        b.box("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.5, -0.18)), Vector3(0.4, 0.6, 0.16))
        b.box("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.82, -0.18)), Vector3(0.42, 0.06, 0.18))


static func _washbasin(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.78, 0)), Vector3(0.55, 0.14, 0.45))
        b.box("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)), Vector3(0.1, 0.7, 0.1))
        b.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(0, 0.95, -0.16)), 0.015, 0.22, 8)
        b.box("metal", Transform3D(Basis.IDENTITY, Vector3(0, 1.02, -0.1)), Vector3(0.03, 0.03, 0.14))
        b.box("glass", Transform3D(Basis.IDENTITY, Vector3(0, 1.35, -0.2)), Vector3(0.5, 0.7, 0.02))


static func _bathtub(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.28, 0)), Vector3(1.6, 0.55, 0.75))
        b.box("porcelain", Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(1.42, 0.12, 0.57))
        b.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(-0.7, 0.75, 0)), 0.018, 0.32, 8)


static func _shower(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("tile_floor", Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), Vector3(0.9, 0.06, 0.9))
        b.box("glass", Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0.44)), Vector3(0.9, 1.9, 0.02))
        b.box("metal", Transform3D(Basis.IDENTITY, Vector3(-0.43, 1.0, 0.0)), Vector3(0.04, 1.9, 0.9))
        b.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(0, 2.0, -0.2)), 0.02, 0.3, 8)


static func _washing_machine(b: BoxCollector, rng: RandomNumberGenerator) -> void:
        b.box("appliance", Transform3D(Basis.IDENTITY, Vector3(0, 0.42, 0)), Vector3(0.6, 0.84, 0.6))
        b.cyl("glass_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0.3)), 0.2, 0.03, 14)


## Places props for a room of given kind. doors: Array of
## {pos: Vector2, dir: Vector2} door touch points (XZ) - furniture is kept
## out of door swing zones so rooms stay walkable. Returns Array of
## {id, pos: Vector3, rot_y: float} in building-local coords.
static func layout_room(kind: String, rect: Rect2, door_dirs: Array, base_y: float, rng: RandomNumberGenerator) -> Array:
        var out: Array = []
        var c := rect.get_center()
        match kind:
                "bedroom":
                        var bed := "bed_double" if rect.get_area() > 12.0 else "bed_single"
                        var horizontal := rect.size.x >= rect.size.y
                        if horizontal:
                                out.append({"id": bed, "pos": _v3(rect.position.x + 1.1, base_y, c.y), "rot_y": PI * 0.5})
                                out.append({"id": "nightstand", "pos": _v3(rect.position.x + 1.1, base_y, c.y - 1.35), "rot_y": PI * 0.5})
                                out.append({"id": "wardrobe", "pos": _v3(rect.end.x - 0.45, base_y, c.y), "rot_y": -PI * 0.5})
                        else:
                                out.append({"id": bed, "pos": _v3(c.x, base_y, rect.position.y + 1.15), "rot_y": 0.0})
                                out.append({"id": "nightstand", "pos": _v3(c.x - 0.85, base_y, rect.position.y + 0.45), "rot_y": 0.0})
                                out.append({"id": "wardrobe", "pos": _v3(rect.end.x - 0.45, base_y, rect.end.y - 0.6), "rot_y": -PI * 0.5})
                        out.append({"id": "rug", "pos": _v3(c.x, base_y, c.y + 0.8), "rot_y": 0.0})
                        out.append({"id": "floor_lamp", "pos": _v3(rect.end.x - 0.45, base_y, rect.position.y + 0.45), "rot_y": 0.0})
                "living":
                        out.append({"id": "sofa", "pos": _v3(c.x, base_y, c.y), "rot_y": 0.0})
                        out.append({"id": "coffee_table", "pos": _v3(c.x, base_y, c.y - 0.95), "rot_y": 0.0})
                        out.append({"id": "tv_console", "pos": _v3(c.x, base_y, c.y - 1.75), "rot_y": 0.0})
                        out.append({"id": "bookshelf", "pos": _v3(rect.end.x - 0.35, base_y, c.y + 0.8), "rot_y": -PI * 0.5})
                        out.append({"id": "floor_lamp", "pos": _v3(rect.position.x + 0.4, base_y, rect.end.y - 0.5), "rot_y": 0.0})
                        out.append({"id": "plant", "pos": _v3(rect.position.x + 0.4, base_y, rect.position.y + 0.4), "rot_y": 0.0})
                        out.append({"id": "rug", "pos": _v3(c.x, base_y, c.y - 0.3), "rot_y": 0.0})
                "lounge":
                        out.append({"id": "sofa", "pos": _v3(c.x, base_y, c.y - 0.4), "rot_y": 0.0})
                        out.append({"id": "coffee_table", "pos": _v3(c.x, base_y, c.y + 0.75), "rot_y": 0.0})
                        out.append({"id": "bookshelf", "pos": _v3(rect.end.x - 0.35, base_y, rect.position.y + 0.7), "rot_y": -PI * 0.5})
                        out.append({"id": "plant", "pos": _v3(rect.position.x + 0.4, base_y, rect.end.y - 0.45), "rot_y": 0.0})
                        out.append({"id": "rug", "pos": _v3(c.x, base_y, c.y + 0.4), "rot_y": 0.0})
                "kitchen":
                        var wall_z := rect.position.y + 0.32
                        out.append({"id": "kitchen_counter", "pos": _v3(c.x - 0.2, base_y, wall_z), "rot_y": 0.0})
                        out.append({"id": "stove", "pos": _v3(rect.end.x - 1.2, base_y, wall_z), "rot_y": 0.0})
                        out.append({"id": "fridge", "pos": _v3(rect.position.x + 0.45, base_y, rect.end.y - 0.5), "rot_y": PI})
                        out.append({"id": "dining_table", "pos": _v3(c.x + 0.3, base_y, rect.end.y - 1.2), "rot_y": 0.0})
                        out.append({"id": "dining_chair", "pos": _v3(c.x + 0.3, base_y, rect.end.y - 0.55), "rot_y": PI})
                        out.append({"id": "dining_chair", "pos": _v3(c.x - 0.45, base_y, rect.end.y - 1.2), "rot_y": PI * 0.5})
                "dining":
                        out.append({"id": "dining_table", "pos": _v3(c.x, base_y, c.y), "rot_y": 0.0})
                        for i in 4:
                                var a := TAU * float(i) / 4.0
                                out.append({"id": "dining_chair", "pos": _v3(c.x + cos(a) * 0.75, base_y, c.y + sin(a) * 0.75), "rot_y": a + PI})
                        out.append({"id": "plant", "pos": _v3(rect.end.x - 0.4, base_y, rect.position.y + 0.4), "rot_y": 0.0})
                "bath":
                        out.append({"id": "toilet", "pos": _v3(rect.position.x + 0.35, base_y, rect.position.y + 0.5), "rot_y": 0.0})
                        out.append({"id": "washbasin", "pos": _v3(rect.end.x - 0.4, base_y, rect.position.y + 0.4), "rot_y": 0.0})
                        if rect.get_area() > 5.5:
                                out.append({"id": "bathtub", "pos": _v3(c.x, base_y, rect.end.y - 0.5), "rot_y": 0.0})
                        else:
                                out.append({"id": "shower", "pos": _v3(c.x, base_y, rect.end.y - 0.55), "rot_y": 0.0})
                        out.append({"id": "washing_machine", "pos": _v3(rect.position.x + 0.4, base_y, rect.end.y - 0.45), "rot_y": 0.0})
                "office":
                        out.append({"id": "desk_pc", "pos": _v3(c.x, base_y, rect.position.y + 0.45), "rot_y": 0.0})
                        out.append({"id": "chair", "pos": _v3(c.x, base_y, rect.position.y + 1.05), "rot_y": PI})
                        out.append({"id": "bookshelf", "pos": _v3(rect.end.x - 0.35, base_y, c.y), "rot_y": -PI * 0.5})
                        out.append({"id": "plant", "pos": _v3(rect.position.x + 0.35, base_y, rect.end.y - 0.35), "rot_y": 0.0})
                "stair":
                        out.append({"id": "floor_lamp", "pos": _v3(rect.position.x + 0.3, base_y, rect.position.y + 0.3), "rot_y": 0.0})
                "storage":
                        out.append({"id": "washing_machine", "pos": _v3(rect.position.x + 0.4, base_y, rect.position.y + 0.4), "rot_y": 0.0})
                        out.append({"id": "bookshelf", "pos": _v3(rect.end.x - 0.35, base_y, rect.end.y - 0.5), "rot_y": -PI * 0.5})
                _:
                        out.append({"id": "plant", "pos": _v3(c.x, base_y, c.y), "rot_y": rng.randf() * TAU})
        _fit_placements(out, rect, door_dirs)
        return out


## Keeps props inside the room and out of door swing zones (0.85 m radius),
## so generated rooms stay accessible and furniture never blocks a doorway.
static func _fit_placements(placements: Array, rect: Rect2, doors: Array) -> void:
        var m := 0.32
        for pl in placements:
                var pos := Vector2(pl.pos.x, pl.pos.z)
                for d in doors:
                        var dp: Vector2 = d.pos
                        var dist := pos.distance_to(dp)
                        if dist < 0.85:
                                var away := (pos - dp).normalized() if dist > 0.01 else Vector2(0, 1)
                                pos = dp + away * 0.85
                pos.x = clampf(pos.x, rect.position.x + m, rect.end.x - m)
                pos.y = clampf(pos.y, rect.position.y + m, rect.end.y - m)
                pl.pos = _v3(pos.x, pl.pos.y, pos.y)


static func _v3(x: float, y: float, z: float) -> Vector3:
        return Vector3(x, y, z)
