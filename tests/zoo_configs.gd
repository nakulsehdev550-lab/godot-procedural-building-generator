class_name BFZooConfigs
extends RefCounted
## Shared zoo building configs: used by the tour renderer AND the walkable
## zoo map. Covers the settings matrix: shapes x styles x roofs x stairs,
## plus v1.2 feature showcases (per-floor overrides, custom openings, tint).

static func all() -> Array:
        return [
                {"name": "suburban_house", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(11, 8.5)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.roof_kind = BFParams.Roof.GABLE
                        p.stair_kind = BFParams.Stair.STRAIGHT
                        p.chimney = true
                        p.terrain_pad = true
                        p.seed = 42},
                {"name": "stone_cottage", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_L(9, 7)
                        p.floors = 1
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.facade_material = "stone"
                        p.roof_kind = BFParams.Roof.HIP
                        p.chimney = true
                        p.seed = 7},
                {"name": "village_house", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(8.5, 6.5)
                        p.floors = 1
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.roof_kind = BFParams.Roof.GAMBREL
                        p.roof_pitch = 0.5
                        p.roof_pitch2 = 1.6
                        p.chimney = true
                        p.site_fence = true
                        p.terrain_pad = true
                        p.max_room_area = 16.0
                        p.seed = 64},
                {"name": "modern_villa", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_L(14, 11)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.apply_architecture_defaults()
                        p.roof_kind = BFParams.Roof.FLAT
                        p.stair_kind = BFParams.Stair.DOGLEG
                        p.balconies = true
                        p.ground_balcony = true
                        p.seed = 11},
                {"name": "mansion", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_U(19, 14)
                        p.floors = 3
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.roof_kind = BFParams.Roof.MANSARD
                        p.roof_pitch = 0.35
                        p.roof_pitch2 = 1.7
                        p.chimney = true
                        p.balconies = true
                        p.seed = 21},
                {"name": "brick_apartment", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(18, 13)
                        p.floors = 5
                        p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
                        p.apply_architecture_defaults()
                        p.balconies = true
                        p.stair_kind = BFParams.Stair.DOGLEG
                        p.seed = 7},
                {"name": "townhouse_tall", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(6.5, 11)
                        p.floors = 3
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.facade_material = "brick_gray"
                        p.roof_kind = BFParams.Roof.SHED
                        p.window_style = BFParams.WindowStyle.TALL
                        p.stair_kind = BFParams.Stair.AUTO
                        p.seed = 23},
                {"name": "shop_apartments", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(14, 11)
                        p.floors = 5
                        p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
                        p.apply_architecture_defaults()
                        p.balconies = true
                        p.stair_kind = BFParams.Stair.DOGLEG
                        var shops := BFFloorOverride.new()
                        shops.facade_material = "facade_panel"
                        shops.window_style = BFParams.WindowStyle.CURTAIN
                        p.floor_overrides = [shops]
                        p.seed = 13},
                {"name": "round_tower", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_circle(8)
                        p.floors = 6
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.roof_kind = BFParams.Roof.CONE
                        p.window_style = BFParams.WindowStyle.CURTAIN
                        p.stair_kind = BFParams.Stair.SPIRAL
                        p.seed = 3},
                {"name": "office_tower_u", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_U(20, 15)
                        p.floors = 8
                        p.architecture = BFParams.ArchStyle.OFFICE_TOWER
                        p.apply_architecture_defaults()
                        p.roof_kind = BFParams.Roof.FLAT
                        p.window_style = BFParams.WindowStyle.CURTAIN
                        p.stair_kind = BFParams.Stair.AUTO
                        p.seed = 5},
                {"name": "setback_tower", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(18, 14)
                        p.floors = 10
                        p.architecture = BFParams.ArchStyle.OFFICE_TOWER
                        p.apply_architecture_defaults()
                        p.stair_kind = BFParams.Stair.SPIRAL
                        var mid := BFFloorOverride.new()
                        mid.outset = -1.2
                        var top := BFFloorOverride.new()
                        top.outset = -2.2
                        p.floor_overrides = [null, null, null, null, mid, mid, mid, mid, top, top]
                        p.seed = 17},
                {"name": "tshape_family", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_T(13, 10)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.roof_kind = BFParams.Roof.HIP
                        p.balconies = true
                        p.site_fence = true
                        p.seed = 77},
                {"name": "oval_villa", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_oval(13, 9)
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.roof_kind = BFParams.Roof.DOME
                        p.window_style = BFParams.WindowStyle.CURTAIN
                        p.stair_kind = BFParams.Stair.SPIRAL
                        p.seed = 15},
                {"name": "apartment_dogleg", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(14, 11)
                        p.floors = 3
                        p.architecture = BFParams.ArchStyle.BRICK_APARTMENT
                        p.apply_architecture_defaults()
                        p.balconies = true
                        p.stair_kind = BFParams.Stair.DOGLEG
                        p.max_room_area = 18.0
                        p.seed = 31},
                {"name": "penthouse_tower", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create_rect(16, 12)
                        p.floors = 10
                        p.architecture = BFParams.ArchStyle.MODERN
                        p.apply_architecture_defaults()
                        p.roof_kind = BFParams.Roof.FLAT
                        p.roof_railing = true
                        p.balconies = true
                        p.balcony_every_n_floors = 2
                        p.stair_kind = BFParams.Stair.DOGLEG
                        p.seed = 99},
                {"name": "freeform_house", "cfg": func(p: BFParams):
                        p.footprint = BFFootprint.create(PackedVector2Array([
                                Vector2(-6, -4), Vector2(3, -4), Vector2(6, -1.5), Vector2(6, 4),
                                Vector2(-2, 4), Vector2(-6, 1.5)]))
                        p.floors = 2
                        p.architecture = BFParams.ArchStyle.CLASSIC_HOUSE
                        p.roof_kind = BFParams.Roof.FLAT
                        p.stair_kind = BFParams.Stair.AUTO
                        p.custom_openings = [
                                {"point": Vector2(3, -4), "width": 2.2, "height": 1.6, "sill": 0.7, "kind": "window", "floor": 0},
                                {"point": Vector2(-6, -1.5), "width": 1.6, "height": 2.1, "sill": 0.0, "kind": "door", "floor": 0},
                        ]
                        p.seed = 55},
        ]
