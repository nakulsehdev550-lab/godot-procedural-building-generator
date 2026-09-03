# BuildingForge — Procedural Building Generator for Godot 4

**BuildingForge** is a fully procedural 3D building generator plugin for Godot 4.3+
(tested on 4.7.1). Draw a footprint of any shape — rectangle, L, T, U, circle or a
free-form polygon — and the plugin generates a complete building: exterior walls
with punched windows or glass curtain walls, floor slabs, stairs, balconies,
roofs, a full interior with partitioned rooms, doors and furniture, and baked PBR
textures. Everything is parameterized in the inspector and every generated part
can be moved, rotated or deleted by hand afterwards.

![house](../renders/house_05.png)

## Features

- **Draw footprints in the viewport** — drag rectangles and circles, click
  polygons, or pick preset shapes (Rect / L / T / U / Circle). 0.5 m snapping.
- **Any scale** — 1 to 50 floors, from cottages to towers, real-world meters.
- **Facade styles** — Classic (punched windows, frames, sills), Modern (glass
  curtain walls with mullions), Tall windows, Brick apartment, Office tower.
- **Roofs** — Gable, Hip, Cone (round buildings), Dome, Flat (parapet + railing
  + rooftop equipment).
- **Full interiors** — BSP room partitioning that always respects the footprint,
  interior walls with door openings, per-room floor finishes (wood / tile /
  carpet), staircases (straight, dogleg, spiral) with slab openings and rails.
- **24 furniture props** — beds, wardrobes, sofas, TV consoles, desks + PCs,
  kitchen counters / stove / fridge, bathroom fixtures, plants, rugs, lamps.
- **Baked PBR textures** — 23 tileable material sets (albedo + normal +
  roughness) generated procedurally and shipped pre-baked. Realistic style by
  default; swap the whole look by pointing one property at another texture
  folder (make it stylized or low-poly — missing textures fall back to clean
  flat colors automatically).
- **Manual editing that survives regeneration** — every generated part is a
  regular node. Move anything; regenerating keeps your changes (matched by
  part id). A "finalize" option converts the whole building to a plain editable
  scene.
- **Performance options** — per-part nodes for maximum editability or one merged
  mesh per floor; optional trimesh collision; 12-floor tower generates in
  ~0.3 s.

## Install

1. Copy `addons/building_forge/` into your project (or grab the zip from
   Releases).
2. Enable **Project ▸ Project Settings ▸ Plugins ▸ BuildingForge**.
3. Open the **BuildingForge** dock (right side).

## Quick start

1. Click **Create Building** in the dock — a `ProceduralBuilding` node appears.
2. Click **Draw Footprint**, then **drag in the 3D viewport** (rectangle; pick
   Circle or Polygon in the dock for other shapes, Enter/right-click finishes a
   polygon).
3. Tweak parameters in the Inspector: floors, floor height, architecture,
   facade material, windows, roof, interior, props, seed...
4. Select footprint vertices with the move tool to reshape the building, or
   drag the top handle to change the floor count.
5. Move any generated part by hand — your edits are kept when the building
   regenerates.

## Inspector parameters (overview)

| Group | Parameters |
|---|---|
| Shape | footprint polygon, floors (1–50), floor height, rotation |
| Style | architecture, facade material, interior material, roof kind / pitch / overhang, window style, texture style folder |
| Walls & Openings | wall thickness, window width/height/sill/spacing, door size, frames, sills |
| Interior | generate interior, generate props, max room area, stair kind, balconies + frequency |
| Roof Extras | roof railing, rooftop equipment |
| Output | merge geometry per floor, generate collision, props collision, seed |

### Swapping texture styles

`params.texture_style_dir` points at a folder of material sets
(`brick_red/brick_red_albedo.png` + `_normal` + `_rough`, etc.). Duplicate the
shipped `textures/baked` folder, repaint the PNGs (or delete individual
materials — they fall back to flat colors), and point the property at your
folder. The dock's **Rebake Textures** button regenerates all sets in-editor.

## Architecture (for contributors)

```
addons/building_forge/
├── plugin.gd               editor entry: dock, draw tool, gizmos, undo/redo
├── editor/                 dock UI + Node3D gizmo plugin
├── core/
│   ├── building_generator.gd   ProceduralBuilding orchestrator (@tool)
│   ├── params.gd               BFParams resource (all inspector knobs)
│   ├── footprint.gd            polygon resource: shapes, validation, insets
│   ├── geometry/               mesh_util, wall bands, slabs, roofs, stairs
│   ├── facade/                 window/door layouts + assemblies
│   ├── interior/               BSP room partitioner
│   ├── props/                  furniture factory + room layouts
│   └── materials/              texture baker + material library
└── textures/baked/         23 shipped PBR material sets (PNG)
```

Wall bands are built per polygon edge between the outer edge and a
miter-inset inner edge, so corners are watertight by construction; openings
subdivide the band and their reveals come from the piece caps. All meshes use
Godot's clockwise front-face winding with explicit outward normals.

## Testing

Headless test suites (run from the project root):

```bash
godot --headless --path . --script res://tests/geo_smoke.gd   # geometry invariants (analytic volumes)
godot --headless --path . --script res://tests/e2e_test.gd    # full building generation + edit preservation
```

## License

MIT — see [LICENSE](LICENSE).
