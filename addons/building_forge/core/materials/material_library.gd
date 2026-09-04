@tool
class_name BFMaterialLibrary
extends RefCounted
## Central material registry. Builds StandardMaterial3D objects from the
## baked PBR texture sets and caches them.
##
## MODULARITY: every material resolves through a BFMaterialStyle resource
## that points at a texture folder. Ship additional folders (e.g. "stylized",
## "lowpoly") with the same PNG layout and swap styles at runtime or in the
## inspector - no code changes needed. If a texture is missing, a flat-color
## fallback material is generated so the plugin never breaks.

const DEFAULT_STYLE_DIR := "res://addons/building_forge/textures/baked"

## Materials rendered with world-space triplanar (architecture surfaces).
const TRIPLANAR := [
        "brick_red", "brick_gray", "plaster_ext", "plaster_int", "concrete",
        "wood_floor", "roof_tile", "roof_shingle", "tile_floor", "tile_wall",
        "asphalt", "stone", "facade_panel",
]

const TILE_SIZE := {  # meters per texture repeat (drives triplanar scale)
        "brick_red": 2.0, "brick_gray": 2.0, "plaster_ext": 3.0, "plaster_int": 3.0,
        "concrete": 3.0, "wood_floor": 2.0, "roof_tile": 1.5, "roof_shingle": 1.5,
        "tile_floor": 1.0, "tile_wall": 1.0, "asphalt": 2.0, "stone": 2.0,
        "facade_panel": 1.2, "wood_dark": 1.0, "wood_light": 1.0,
        "fabric_sofa": 0.8, "fabric_bed": 0.8, "carpet": 1.5, "metal": 0.5,
        "metal_dark": 0.5, "porcelain": 0.3, "appliance": 0.5, "trim_white": 0.3,
}

const METALLIC := {"metal": 0.9, "metal_dark": 0.85, "appliance": 0.5, "facade_panel": 0.25}

const FLAT_COLORS := {  # fallback when a texture set is missing
        "brick_red": Color(0.55, 0.28, 0.2), "brick_gray": Color(0.45, 0.44, 0.43),
        "plaster_ext": Color(0.88, 0.85, 0.79), "plaster_int": Color(0.92, 0.91, 0.89),
        "concrete": Color(0.63, 0.63, 0.62), "wood_floor": Color(0.56, 0.4, 0.24),
        "wood_dark": Color(0.3, 0.2, 0.12), "wood_light": Color(0.7, 0.54, 0.35),
        "roof_tile": Color(0.56, 0.28, 0.2), "roof_shingle": Color(0.18, 0.18, 0.19),
        "tile_floor": Color(0.8, 0.79, 0.77), "tile_wall": Color(0.9, 0.9, 0.89),
        "asphalt": Color(0.18, 0.18, 0.19), "stone": Color(0.6, 0.57, 0.52),
        "facade_panel": Color(0.24, 0.25, 0.27), "fabric_sofa": Color(0.55, 0.5, 0.45),
        "fabric_bed": Color(0.85, 0.85, 0.83), "carpet": Color(0.38, 0.4, 0.45),
        "metal": Color(0.7, 0.71, 0.72), "metal_dark": Color(0.28, 0.29, 0.31),
        "porcelain": Color(0.94, 0.94, 0.93), "appliance": Color(0.87, 0.88, 0.89),
        "trim_white": Color(0.92, 0.91, 0.89),
        "glass": Color(0.5, 0.65, 0.72, 0.45), "glass_dark": Color(0.09, 0.12, 0.15, 0.68),
}

static var _cache: Dictionary = {}


## Returns the cached StandardMaterial3D for a material id.
static func get_material(id: String, style_dir := DEFAULT_STYLE_DIR) -> StandardMaterial3D:
        if id == "glass" or id == "glass_dark" or id == "__glass":
                return get_glass(id == "glass_dark")
        var key := style_dir + "/" + id
        if _cache.has(key):
                return _cache.get(key)
        var mat := _build(id, style_dir)
        _cache[key] = mat
        return mat


static func _build(id: String, style_dir: String) -> StandardMaterial3D:
        var mat := StandardMaterial3D.new()
        mat.resource_name = id
        var dir := style_dir.path_join(id)
        var albedo_path := dir.path_join(id + "_albedo.png")
        var normal_path := dir.path_join(id + "_normal.png")
        var rough_path := dir.path_join(id + "_rough.png")
        var has_tex := ResourceLoader.exists(albedo_path)
        if has_tex:
                mat.albedo_texture = load(albedo_path)
                if ResourceLoader.exists(normal_path):
                        mat.normal_enabled = true
                        mat.normal_texture = load(normal_path)
                        # strong-grain props (wood) streak badly at glancing
                        # angles - keep architecture surfaces strong, props soft
                        mat.normal_scale = 0.45 if id in ["wood_dark", "wood_light", "fabric_sofa", "fabric_bed"] else 0.9
                if ResourceLoader.exists(rough_path):
                        mat.roughness_texture = load(rough_path)
                        mat.roughness = 1.0
                if id in TRIPLANAR:
                        mat.uv1_triplanar = true
                        mat.uv1_world_triplanar = true
                        var ts := float(TILE_SIZE.get(id, 1.0))
                        mat.uv1_scale = Vector3.ONE / maxf(ts, 0.05)
        else:
                # flat-color fallback (also used by custom low-poly styles)
                mat.albedo_color = FLAT_COLORS.get(id, Color(0.7, 0.7, 0.7))
        mat.roughness = 0.85 if not has_tex else mat.roughness
        mat.metallic = float(METALLIC.get(id, 0.0))
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        return mat


## Glass is parameter-only (no textures).
## DEPTH_PRE_PASS is the fix for thin panes: without it the two faces of the
## same glass box blend in triangle order (the back face can draw OVER the
## front one -> "transparent from one side" look) and shimmer/z-fight at
## glancing angles. With a depth pre-pass only the nearest face renders, so
## glass looks correct from BOTH sides and never self-fights.
static func get_glass(dark := false) -> StandardMaterial3D:
        var id := "glass_dark" if dark else "glass"
        if _cache.has(id):
                return _cache.get(id)
        var mat := StandardMaterial3D.new()
        mat.resource_name = id
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
        mat.albedo_color = FLAT_COLORS.get(id, Color(0.7, 0.85, 0.9, 0.3))
        mat.roughness = 0.07
        mat.metallic = 0.15
        mat.metallic_specular = 0.6
        mat.cull_mode = BaseMaterial3D.CULL_BACK
        _cache[id] = mat
        return mat


## Returns a tinted variant of a library material (per-building facade / roof
## paint). Tint multiplies the albedo (works over textures AND flat colors).
## Cached per (id, style, hex tint) so buildings sharing a color share one
## material instance.
static func get_tinted(id: String, style_dir: String, tint: Color) -> StandardMaterial3D:
        if tint == Color.WHITE or id == "glass" or id == "glass_dark" or id == "__glass":
                return get_material(id, style_dir)
        var key := "%s/%s#%s" % [style_dir, id, tint.to_html()]
        if _cache.has(key):
                return _cache.get(key)
        var base := get_material(id, style_dir)
        var mat := base.duplicate() as StandardMaterial3D
        mat.resource_name = id + "_tinted"
        var a := base.albedo_color
        mat.albedo_color = Color(a.r * tint.r, a.g * tint.g, a.b * tint.b, a.a)
        _cache[key] = mat
        return mat


static func clear_cache() -> void:
        _cache.clear()
