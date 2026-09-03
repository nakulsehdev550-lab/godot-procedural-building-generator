@tool
class_name BFTextureBaker
extends RefCounted
## Procedural PBR texture baker. Generates tileable albedo + normal +
## roughness maps for every material in the library and saves them as PNG.
##
## All patterns are math-generated (FastNoiseLite + analytic patterns) and
## made seamlessly tileable: pattern geometry uses integer repeats per tile
## and noise is blended across tile borders (4-corner wrap).
##
## NOTE: pattern kernels return [height, Color, roughness] arrays (GDScript
## value types cannot be mutated in place).
##
## Usage (headless):
##   godot --headless --path . --script res://addons/building_forge/textures/bake_all.gd

const DEFAULT_DIR := "res://addons/building_forge/textures/baked"

# Material registry: id -> {size, tile (meters per repeat), fn, params}
const RECIPES := {
	"brick_red": {"size": 1024, "tile": 2.0, "fn": "brick", "base": Color(0.48, 0.23, 0.16), "var": 0.16, "mortar": Color(0.62, 0.60, 0.56), "rows": 22, "rough": 0.85},
	"brick_gray": {"size": 512, "tile": 2.0, "fn": "brick", "base": Color(0.42, 0.41, 0.40), "var": 0.13, "mortar": Color(0.60, 0.59, 0.57), "rows": 22, "rough": 0.85},
	"plaster_ext": {"size": 1024, "tile": 3.0, "fn": "stucco", "base": Color(0.80, 0.75, 0.66), "rough": 0.9},
	"plaster_int": {"size": 512, "tile": 3.0, "fn": "stucco", "base": Color(0.87, 0.85, 0.81), "rough": 0.9, "fine": true, "speckle": false},
	"concrete": {"size": 1024, "tile": 3.0, "fn": "concrete", "base": Color(0.62, 0.62, 0.61), "rough": 0.72},
	"wood_floor": {"size": 1024, "tile": 2.0, "fn": "planks", "base": Color(0.55, 0.38, 0.22), "planks": 13, "rough": 0.55},
	"wood_dark": {"size": 512, "tile": 1.0, "fn": "grain", "base": Color(0.28, 0.18, 0.11), "rough": 0.45},
	"wood_light": {"size": 512, "tile": 1.0, "fn": "grain", "base": Color(0.68, 0.52, 0.33), "rough": 0.5},
	"roof_tile": {"size": 1024, "tile": 1.5, "fn": "rooftiles", "base": Color(0.55, 0.26, 0.18), "var": 0.14, "rough": 0.7},
	"roof_shingle": {"size": 1024, "tile": 1.5, "fn": "shingles", "base": Color(0.16, 0.16, 0.17), "rough": 0.85},
	"tile_floor": {"size": 512, "tile": 1.0, "fn": "grid", "base": Color(0.78, 0.77, 0.75), "cells": 5, "rough": 0.28},
	"tile_wall": {"size": 512, "tile": 1.0, "fn": "subway", "base": Color(0.90, 0.90, 0.89), "rough": 0.2},
	"asphalt": {"size": 512, "tile": 2.0, "fn": "concrete", "base": Color(0.17, 0.17, 0.18), "rough": 0.9},
	"stone": {"size": 1024, "tile": 2.0, "fn": "ashlar", "base": Color(0.58, 0.55, 0.50), "var": 0.12, "rough": 0.8},
	"facade_panel": {"size": 512, "tile": 1.2, "fn": "panels", "base": Color(0.22, 0.23, 0.25), "rough": 0.45},
	"fabric_sofa": {"size": 512, "tile": 0.8, "fn": "weave", "base": Color(0.52, 0.47, 0.42), "rough": 0.9},
	"fabric_bed": {"size": 512, "tile": 0.8, "fn": "weave", "base": Color(0.82, 0.82, 0.80), "rough": 0.85, "fine": true, "speckle": false},
	"carpet": {"size": 512, "tile": 1.5, "fn": "fuzz", "base": Color(0.35, 0.38, 0.42), "rough": 0.95},
	"metal": {"size": 512, "tile": 0.5, "fn": "brushed", "base": Color(0.66, 0.67, 0.68), "rough": 0.32},
	"metal_dark": {"size": 512, "tile": 0.5, "fn": "brushed", "base": Color(0.25, 0.26, 0.28), "rough": 0.5},
	"porcelain": {"size": 256, "tile": 0.3, "fn": "flat", "base": Color(0.93, 0.93, 0.92), "rough": 0.15, "speckle": false},
	"appliance": {"size": 256, "tile": 0.5, "fn": "flat", "base": Color(0.85, 0.86, 0.87), "rough": 0.4, "speckle": false},
	"trim_white": {"size": 256, "tile": 0.3, "fn": "grain", "base": Color(0.90, 0.89, 0.87), "rough": 0.4, "subtle": true, "speckle": false},
}


static func _seed(id: String) -> int:
	return hash(id) & 0x7fffffff


static func _noise(id: String, freq: float, octaves := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = _seed(id)
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	return n


## Bakes every recipe. res_div scales resolution (1.0 = full). Returns count.
static func bake_all(base_dir := DEFAULT_DIR, res_div := 1.0) -> int:
	var count := 0
	for id in RECIPES:
		bake_material(id, base_dir, res_div)
		count += 1
	return count


static func material_dir(id: String, base_dir := DEFAULT_DIR) -> String:
	return base_dir.path_join(id)


static func bake_material(id: String, base_dir := DEFAULT_DIR, res_div := 1.0) -> void:
	if not RECIPES.has(id):
		push_error("[BF] unknown material recipe: " + id)
		return
	var r: Dictionary = RECIPES[id]
	var size := int(r.size / maxf(res_div, 0.05))
	size = maxi(32, size)
	var tile_m: float = r.tile
	var dir := material_dir(id, base_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var h_img := Image.create_empty(size, size, false, Image.FORMAT_L8)
	var c_img := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var r_img := Image.create_empty(size, size, false, Image.FORMAT_L8)
	_bake_pixels(id, r, h_img, c_img, r_img, size, tile_m)
	_apply_crevice_ao(c_img, h_img, 0.35)
	var n_img := _height_to_normal(h_img, r.get("normal_strength", 1.0))
	h_img = null
	var failed := false
	failed = failed or c_img.save_png(dir.path_join(id + "_albedo.png")) != OK
	failed = failed or n_img.save_png(dir.path_join(id + "_normal.png")) != OK
	failed = failed or r_img.save_png(dir.path_join(id + "_rough.png")) != OK
	if failed:
		push_error("[BF] bake failed for " + id)


static func _bake_pixels(id: String, r: Dictionary, h_img: Image, c_img: Image, r_img: Image, size: int, tile_m: float) -> void:
	var fn_name: String = r.fn
	var n1 := _noise(id + "_n1", 1.0 / tile_m * 6.0, 4)      # ~6 features per tile
	var n2 := _noise(id + "_n2", 1.0 / tile_m * 24.0, 3)     # detail
	var n3: FastNoiseLite = null
	if r.get("speckle", true):
		n3 = _noise(id + "_n3", 1.0 / tile_m * 90.0, 2)     # speckle
	var base: Color = r.get("base", Color(0.7, 0.7, 0.7))
	var rough_base: float = r.get("rough", 0.8)
	var rows := int(r.get("rows", 20))
	var planks := int(r.get("planks", 12))
	var cells := int(r.get("cells", 5))
	var col_var := float(r.get("var", 0.12))
	var fine := bool(r.get("fine", false))
	var subtle := bool(r.get("subtle", false))
	var w := float(size)
	var h_bytes := PackedByteArray()
	var c_bytes := PackedByteArray()
	var r_bytes := PackedByteArray()
	h_bytes.resize(size * size)
	c_bytes.resize(size * size * 3)
	r_bytes.resize(size * size)
	var mortar_c: Color = r.get("mortar", Color(0.6, 0.6, 0.6))
	for py in size:
		var v := float(py) / w
		var y := v * tile_m
		for px in size:
			var u := float(px) / w
			var x := u * tile_m
			# tileable noise via 4-corner blend (n3 unwrapped: high-freq)
			var nv1 := _tile_noise(n1, u, v, w)
			var nv2 := _tile_noise(n2, u, v, w)
			var nv3 := 0.0
			if n3 != null:
				nv3 = n3.get_noise_2d(u * w, v * w)
			var res: Array
			match fn_name:
				"brick":
					res = _brick_px(x, y, rows, base, col_var, mortar_c, nv1, nv2, nv3, rough_base)
				"stucco":
					res = _stucco_px(nv1, nv2, nv3, base, rough_base, fine)
				"concrete":
					res = _concrete_px(nv1, nv2, nv3, base, rough_base)
				"planks":
					res = _planks_px(x, y, planks, base, col_var, nv1, nv2, nv3, rough_base)
				"grain":
					res = _grain_px(nv1, nv2, nv3, base, rough_base, subtle)
				"rooftiles":
					res = _rooftiles_px(x, y, base, col_var, nv1, nv2, nv3, rough_base)
				"shingles":
					res = _shingles_px(x, y, base, nv1, nv2, nv3, rough_base)
				"grid":
					res = _grid_px(x, y, cells, base, nv1, nv2, nv3, rough_base)
				"subway":
					res = _subway_px(x, y, base, nv1, nv2, nv3, rough_base)
				"ashlar":
					res = _ashlar_px(x, y, base, col_var, nv1, nv2, nv3, rough_base)
				"panels":
					res = _panels_px(x, y, base, nv1, nv2, nv3, rough_base)
				"weave":
					res = _weave_px(x, y, base, nv1, nv2, nv3, rough_base, fine)
				"fuzz":
					res = _fuzz_px(nv1, nv2, nv3, base, rough_base)
				"brushed":
					res = _brushed_px(u, v, base, nv1, nv3, rough_base)
				_:
					res = _flat_px(nv1, nv2, base, rough_base)
			var h: float = res[0]
			var col: Color = res[1]
			var rough: float = res[2]
			var di := py * size + px
			h_bytes[di] = int(clampf(h, 0.0, 1.0) * 255.0)
			r_bytes[di] = int(clampf(rough, 0.0, 1.0) * 255.0)
			var c3 := di * 3
			c_bytes[c3] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			c_bytes[c3 + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			c_bytes[c3 + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
	h_img.set_data(size, size, false, Image.FORMAT_L8, h_bytes)
	c_img.set_data(size, size, false, Image.FORMAT_RGB8, c_bytes)
	r_img.set_data(size, size, false, Image.FORMAT_L8, r_bytes)


## 4-corner blend makes any noise field seamlessly tileable.
static func _tile_noise(n: FastNoiseLite, u: float, v: float, w: float) -> float:
	var x := u * w
	var y := v * w
	var n00 := n.get_noise_2d(x, y)
	var n10 := n.get_noise_2d(x - w, y)
	var n01 := n.get_noise_2d(x, y - w)
	var n11 := n.get_noise_2d(x - w, y - w)
	var a := lerpf(n00, n10, u)
	var b := lerpf(n01, n11, u)
	return lerpf(a, b, v)


# --- pattern kernels: each returns [h, Color, roughness] -------------------

static func _brick_px(x: float, y: float, rows: int, base: Color, col_var: float,
		mortar: Color, nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var row_pitch := 1.0 / float(rows)
	var row := int(floor(y / row_pitch))
	var in_row := (y - row * row_pitch) / row_pitch
	var offset := 0.5 * row_pitch * 3.7 * float(row % 2)
	var brick_len := 1.0 / 4.25
	var bx := fposmod(x + offset, brick_len) / brick_len
	var gap_v := 0.10
	var gap_h := 0.055
	var grain := nv2 * 0.5 + nv3 * 0.5
	if in_row < gap_v or in_row > 1.0 - gap_v or bx < gap_h or bx > 1.0 - gap_h:
		return [0.18 + grain * 0.1, mortar * (0.92 + grain * 0.16), 0.95]
	var bid := hash(row * 7349 + int(floor((x + offset) / brick_len)))
	var jitter := float(bid % 1000) / 1000.0
	var t := clampf(0.5 + (jitter - 0.5) * col_var * 6.0 + nv1 * 0.18, 0.0, 1.0)
	var col := base.lerp(base.darkened(0.35), t * 0.55).lerp(Color(0.52, 0.30, 0.20), nv1 * 0.15)
	col = col * (0.9 + grain * 0.2)
	var h := 0.62 + grain * 0.22 + (1.0 - absf(bx - 0.5) * 2.0) * 0.06
	return [h, col, rough0 + grain * 0.12]


static func _stucco_px(nv1: float, nv2: float, nv3: float, base: Color, rough0: float, fine: bool) -> Array:
	var bump := nv1 * 0.6 + nv2 * 0.3 + nv3 * 0.1
	var h := 0.45 + bump * 0.35
	var mottle := nv1 * 0.5 + nv2 * 0.5
	var col := base * ((0.97 if fine else 0.94) + mottle * (0.05 if fine else 0.10))
	return [h, col, rough0 + nv2 * 0.12]


static func _concrete_px(nv1: float, nv2: float, nv3: float, base: Color, rough0: float) -> Array:
	var h := 0.5 + nv1 * 0.25 + nv2 * 0.15
	var col := base * (0.88 + nv1 * 0.20)
	if nv3 > 0.42:
		col = col.darkened(0.22 * (nv3 - 0.42) * 4.0)
		h -= 0.06 * (nv3 - 0.42) * 4.0
	return [h, col, rough0 + nv2 * 0.12]


static func _planks_px(x: float, y: float, planks: int, base: Color, col_var: float,
		nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var plank_pitch := 1.0 / float(planks)
	var row := int(floor(y / plank_pitch))
	var in_row := (y - row * plank_pitch) / plank_pitch
	var plank_len := 0.62
	var seg := float(hash(row * 9277) % 1000) / 1000.0
	var offset := plank_len * seg
	var px_local := fposmod(x + offset, plank_len) / plank_len
	var pid := hash(row * 9277 + int(floor((x + offset) / plank_len)))
	var pj := float(pid % 1000) / 1000.0
	var grain_v := sin(px_local * 26.0 + nv2 * 5.0 + pj * 40.0) * 0.5 + 0.5
	var tone := clampf(0.5 + (pj - 0.5) * col_var * 5.0 + nv1 * 0.2, 0.0, 1.0)
	var groove_v := 0.055
	var groove_h := 0.02
	if in_row < groove_v or in_row > 1.0 - groove_v or px_local < groove_h or px_local > 1.0 - groove_h:
		return [0.22 + nv3 * 0.08, base.darkened(0.55), 0.75]
	var col := base.lerp(base.darkened(0.3), tone * 0.6)
	col = col * (0.88 + grain_v * 0.22 + nv3 * 0.06)
	var h := 0.6 + grain_v * 0.2 + (1.0 - absf(in_row - 0.5) * 2.0) * 0.05
	return [h, col, 0.45 + grain_v * 0.2 + nv2 * 0.1]


static func _grain_px(nv1: float, nv2: float, nv3: float, base: Color, rough0: float, subtle: bool) -> Array:
	var g := sin(nv1 * 18.0) * 0.5 + 0.5
	var amount := 0.08 if subtle else 0.25
	var col := base * (1.0 - amount * 0.5 + g * amount)
	var h := 0.5 + g * 0.25 + nv2 * 0.1
	return [h, col, rough0 + (g - 0.5) * 0.15]


static func _rooftiles_px(x: float, y: float, base: Color, col_var: float,
		nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var row_pitch := 1.0 / 9.0
	var row := int(floor(y / row_pitch))
	var in_row := (y - row * row_pitch) / row_pitch
	var tile_w := 1.0 / 5.5
	var offset := 0.5 * tile_w * float(row % 2)
	var cx := fposmod(x + offset, tile_w) / tile_w
	var tid := hash(row * 6151 + int(floor((x + offset) / tile_w)))
	var tj := float(tid % 1000) / 1000.0
	var bump := sin(cx * PI)
	var h := 0.35 + bump * 0.45 + (1.0 - in_row) * 0.15
	var tone := clampf(0.5 + (tj - 0.5) * col_var * 6.0 + nv1 * 0.15, 0.0, 1.0)
	var col := base.lerp(base.darkened(0.3), tone * 0.5) * (0.85 + bump * 0.25 + nv3 * 0.06)
	if in_row > 0.86:
		return [0.16, col.darkened(0.5), rough0]
	return [h, col, rough0 + nv2 * 0.12]


static func _shingles_px(x: float, y: float, base: Color, nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var row_pitch := 1.0 / 7.0
	var row := int(floor(y / row_pitch))
	var in_row := (y - row * row_pitch) / row_pitch
	var tab_w := 1.0 / 7.0
	var offset := tab_w * 0.5 * float(row % 2)
	var tx := fposmod(x + offset, tab_w) / tab_w
	var granule := nv2 * 0.5 + nv3 * 0.5
	var h := 0.5 + granule * 0.3 + (1.0 - in_row) * 0.12
	var col := base * (0.8 + granule * 0.35 + nv1 * 0.1)
	if in_row > 0.88:
		return [0.2, col.darkened(0.45), rough0]
	return [h, col, rough0 + granule * 0.12 - 0.03]


static func _grid_px(x: float, y: float, cells: int, base: Color, nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var pitch := 1.0 / float(cells)
	var cx := fposmod(x, pitch) / pitch
	var cy := fposmod(y, pitch) / pitch
	var cid := hash(int(floor(x / pitch)) * 31 + int(floor(y / pitch)) * 517)
	var tj := float(cid % 1000) / 1000.0
	var grout := 0.035
	if cx < grout or cx > 1.0 - grout or cy < grout or cy > 1.0 - grout:
		return [0.25 + nv3 * 0.06, Color(0.55, 0.54, 0.52) * (0.92 + nv3 * 0.12), 0.8]
	var col := base * (0.94 + (tj - 0.5) * 0.1 + nv2 * 0.05)
	return [0.62 + nv2 * 0.1, col, 0.22 + nv1 * 0.08]


static func _subway_px(x: float, y: float, base: Color, nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var row_pitch := 1.0 / 13.0
	var row := int(floor(y / row_pitch))
	var in_row := (y - row * row_pitch) / row_pitch
	var tw := 1.0 / 6.5
	var offset := tw * 0.5 * float(row % 2)
	var cx := fposmod(x + offset, tw) / tw
	if in_row < 0.045 or in_row > 0.955 or cx < 0.035 or cx > 0.965:
		return [0.24 + nv3 * 0.05, Color(0.72, 0.71, 0.69), 0.75]
	var domed := sin(clampf(cx, 0.0, 1.0) * PI)
	var col := base * (0.96 + nv2 * 0.06)
	return [0.55 + domed * 0.2, col, 0.16 + nv1 * 0.06]


static func _ashlar_px(x: float, y: float, base: Color, col_var: float, nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var row_pitch := 1.0 / 6.0
	var row := int(floor(y / row_pitch))
	var in_row := (y - row * row_pitch) / row_pitch
	var seg := float(hash(row * 4231) % 1000) / 1000.0
	var wlen := 0.35 + seg * 0.4
	var offset := wlen * float(hash(row * 911) % 1000) / 1000.0
	var sx := fposmod(x + offset, wlen) / wlen
	var sid := hash(row * 4231 + int(floor((x + offset) / wlen)))
	var sj := float(sid % 1000) / 1000.0
	var gap := 0.045
	if in_row < gap or in_row > 1.0 - gap or sx < gap or sx > 1.0 - gap:
		return [0.2 + nv3 * 0.08, Color(0.45, 0.44, 0.42) * (0.9 + nv3 * 0.15), 0.9]
	var tone := clampf(0.5 + (sj - 0.5) * col_var * 6.0 + nv1 * 0.2, 0.0, 1.0)
	var col := base.lerp(base.darkened(0.28), tone * 0.55) * (0.92 + nv2 * 0.14)
	var h := 0.55 + nv2 * 0.2 + (1.0 - maxf(absf(sx - 0.5), absf(in_row - 0.5)) * 2.0) * 0.1
	return [h, col, rough0 + nv2 * 0.1]


static func _panels_px(x: float, y: float, base: Color, nv1: float, nv2: float, nv3: float, rough0: float) -> Array:
	var seam_x := fposmod(x, 1.0)
	var seam_y := fposmod(y, 0.5)
	if seam_x < 0.025 or seam_y < 0.025:
		return [0.3, base.darkened(0.5), 0.7]
	var col := base * (0.95 + nv1 * 0.08)
	return [0.55 + nv2 * 0.1, col, rough0 + nv2 * 0.08]


static func _weave_px(x: float, y: float, base: Color, nv1: float, nv2: float, nv3: float, rough0: float, fine: bool) -> Array:
	var f := 160.0 if fine else 90.0
	var warp := sin(x * f) * 0.5 + 0.5
	var weft := sin(y * f) * 0.5 + 0.5
	var w := maxf(warp, weft)
	var h := 0.4 + w * 0.3 + nv2 * 0.15
	var col := base * (0.88 + w * 0.2 + nv1 * 0.08)
	return [h, col, rough0 + nv2 * 0.1]


static func _fuzz_px(nv1: float, nv2: float, nv3: float, base: Color, rough0: float) -> Array:
	var h := 0.45 + nv2 * 0.4
	var col := base * (0.85 + nv1 * 0.25 + nv3 * 0.08)
	return [h, col, 0.95]


static func _brushed_px(u: float, v: float, base: Color, nv1: float, nv3: float, rough0: float) -> Array:
	var streak := sin(u * 620.0 + nv1 * 30.0) * 0.5 + 0.5
	var col := base * (0.92 + streak * 0.12 + nv1 * 0.05)
	return [0.5 + nv3 * 0.2, col, rough0 + (streak - 0.5) * 0.1 + nv3 * 0.05]


static func _flat_px(nv1: float, nv2: float, base: Color, rough0: float) -> Array:
	var col := base * (0.97 + nv1 * 0.05)
	return [0.5 + nv1 * 0.1, col, rough0 + nv1 * 0.04]


# --- post ------------------------------------------------------------------

static func _apply_crevice_ao(c_img: Image, h_img: Image, strength: float) -> void:
	var w := c_img.get_width()
	var ht := c_img.get_height()
	var c_bytes: PackedByteArray = c_img.get_data()
	var h_bytes: PackedByteArray = h_img.get_data()
	for i in w * ht:
		var h := float(h_bytes[i]) / 255.0
		var ao := 1.0 - strength * clampf((0.45 - h) * 2.2, 0.0, 1.0)
		if ao < 0.999:
			var c3 := i * 3
			c_bytes[c3] = int(float(c_bytes[c3]) * ao)
			c_bytes[c3 + 1] = int(float(c_bytes[c3 + 1]) * ao)
			c_bytes[c3 + 2] = int(float(c_bytes[c3 + 2]) * ao)
	c_img.set_data(w, ht, false, Image.FORMAT_RGB8, c_bytes)


## Sobel height -> tangent-space normal map (tileable via wrap).
static func _height_to_normal(h_img: Image, strength: float) -> Image:
	var w := h_img.get_width()
	var ht := h_img.get_height()
	var src: PackedByteArray = h_img.get_data()
	var out_bytes := PackedByteArray()
	out_bytes.resize(w * ht * 3)
	var s := 2.0 * strength
	for y in ht:
		var y0 := (y - 1 + ht) % ht
		var y1 := (y + 1) % ht
		for x in w:
			var x0 := (x - 1 + w) % w
			var x1 := (x + 1) % w
			var tl := float(src[y0 * w + x0]) / 255.0
			var t := float(src[y0 * w + x]) / 255.0
			var tr := float(src[y0 * w + x1]) / 255.0
			var l := float(src[y * w + x0]) / 255.0
			var r := float(src[y * w + x1]) / 255.0
			var bl := float(src[y1 * w + x0]) / 255.0
			var b := float(src[y1 * w + x]) / 255.0
			var br := float(src[y1 * w + x1]) / 255.0
			var dx := (tr + 2.0 * r + br) - (tl + 2.0 * l + bl)
			var dy := (bl + 2.0 * b + br) - (tl + 2.0 * t + tr)
			var nx := -dx * s
			var ny := dy * s
			var nz := 1.0
			var inv := 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
			var c3 := (y * w + x) * 3
			out_bytes[c3] = int((nx * inv * 0.5 + 0.5) * 255.0)
			out_bytes[c3 + 1] = int((ny * inv * 0.5 + 0.5) * 255.0)
			out_bytes[c3 + 2] = int((nz * inv * 0.5 + 0.5) * 255.0)
	var out := Image.create_empty(w, ht, false, Image.FORMAT_RGB8)
	out.set_data(w, ht, false, Image.FORMAT_RGB8, out_bytes)
	return out
