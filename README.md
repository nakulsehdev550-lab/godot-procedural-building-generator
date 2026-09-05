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
- **Roofs** — Gable, Hip, Mansard, Gambrel (barn), Shed, Cone (round
  buildings), Dome, Flat (parapet + railing + rooftop equipment) — each with
  pitch + secondary-pitch controls and a draggable roof-pitch handle.
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
- **Interactive editing suite** (see below) — draggable corner / roof / bend
  point handles, right-click wall editing, live regeneration while you drag.
- **Per-floor overrides** — every floor can have its own facade material,
  window style, balcony switch and footprint outset (overhang or setback):
  build "shop base + apartments + penthouse setback" in one building.
- **Custom openings & entrance** — cut your own windows/doors anywhere on any
  wall (right-click) and move the entrance to any facade.
- **Paint** — facade and roof tint colors multiply over the textures; repaint
  at runtime in the zoo map.
- **Facade detail** — stone plinth + cornice bands, brick chimneys, site pad,
  picket fence with a gate at the entrance.
- **House-type interiors** — furniture theming per architecture: village
  houses get fireplaces, offices get lobbies with reception desks, modern
  villas get armchair corners.
- **Custom model slots** — swap ANY generated prop (sofa, bed, fridge...), the
  window assembly or the door assembly with your own PackedScene (glTF, FBX,
  anything Godot imports). Instances are placed at generation time and baked
  into the scene — nothing is generated at game runtime.
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

## Interactive editing (v1.2)

Select a building and use the viewport handles — the whole building
(interiors, windows, stairs) regenerates live while you drag:

- **Wall corner handles** (bottom) and **roof corner handles** (at the roof
  line) — drag any corner to reshape the footprint. Every wall, window, room
  and stair follows.
- **Edge midpoint handles** — drag one OUTWARD to insert a new bend point in
  a wall (works on any facade, any angle).
- **Roof pitch handle** (at the ridge) — drag up/down to change the roof
  pitch. Cone roofs get an apex handle.
- **Height handle** — drag vertically to add/remove whole floors.
- **Right-click any wall** for the context menu: *Add Bend Point Here*,
  *Delete Nearest Corner*, **Cut Window in Wall** / **Cut Door in Wall** (cut
  at the exact clicked position and floor — openings follow their wall when
  you edit the footprint later), *Remove Openings Here*, *Set Entrance Here*,
  *Clear All Custom Openings*, *Finalize (Bake Static)*.
- **Move any part by hand** — walls, props, roofs, even meshes inside your
  custom scenes: manual transforms survive regeneration.
- While a handle drag is active the generator runs in fast mode (no
  props/collision) and does a full rebuild on release, so dragging stays
  fluid even on towers.

## Custom models (props / windows / doors)

1. Import your model as a PackedScene (e.g. drag a `.glb` into the project,
   or save a scene of your own).
2. Select the building ▸ Inspector ▸ **Custom Models**:
   - `Prop Scenes` — dictionary: key = prop id (`bed_double`, `sofa`,
     `fridge`, `toilet`, ...), value = your scene. The generated boxes for
     that prop are skipped and your scene is instanced instead (position =
     the prop spot, facing into the room).
   - `Window Scene` / `Door Scene` — replaces EVERY generated window/door
     assembly. Author the model with its origin at the **center of the
     opening, +Z facing outdoors**; it is auto-placed into every opening.
3. Everything is instanced during generation (editor-time) and saved into the
   scene — at game runtime it is plain geometry, nothing is procedural.

## The walkable zoo map

`demo/zoo_map.tscn` — 16 buildings covering the settings matrix on a plaza
with a first-person player:

- **WASD** move, **Shift** sprint, **Space** jump, mouse look (click to
  capture, **ESC** to release).
- Aim at any building: **E** cycle facade material, **R** cycle roof style,
  **G** cycle facade paint, **F** flashlight.
- Walk inside every building — collision is generated for walls, floors,
  stairs and props.

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

## What changed in v1.2 (interactive editing + FPS test map)

- **Interactive editing suite** — draggable corner / roof / bend-point / pitch
  / height handles with live regeneration and full undo integration; edge
  midpoint handles insert new bend points mid-drag.
- **Right-click wall editing** — cut windows/doors at the exact clicked point
  and floor, remove openings, move the entrance, add/delete corners; custom
  openings follow their wall when the footprint is reshaped later.
- **Walkable FPS zoo map** (`demo/zoo_map.tscn`) — 16 seeded buildings on a
  plaza, first-person player (WASD / mouse / sprint / jump), aim-and-restyle:
  E facade, R roof, G paint, F flashlight. Buildings regenerate from params at
  load — no baked geometry in the scene.
- **Real window glazing** — glass panes are now solid 5 cm boxes centered in
  the wall depth: no more one-face see-through from inside, and no glass
  z-fighting.
- **11 one-click presets** — suburban house, cottage, village house, modern
  villa, mansion, townhouse, apartment block, shop+apartments, office tower,
  setback tower, circular tower.
- **Custom model slots** — swap any prop, or the whole window/door assembly,
  with your own PackedScene (instanced at generation time, runtime stays
  static).
- **Facade detail kit** — stone plinth / cornice bands, brick chimneys, site
  pad, picket fence with a gate at the entrance, per-floor overrides with
  outset (overhang) and setback floors.
- **Fast-drag mode** — while you drag a handle the generator skips props and
  collision, then does a full rebuild on release (fluid on 10+ floor towers).

## What changed in v1.1 (architecture overhaul)

- **Every room is door-reachable** — the stairwell is a first-class room on the
  room-adjacency graph, doors follow a penalty-aware spanning tree (bedroom to
  bedroom doors are a last resort, like real plans), and a connectivity
  verifier grows the hall to bridge any stranded room.
- **Rooms open onto the facade** — windows, entrance and balcony doors open
  into rooms (no more dead wall skin behind the glass).
- **Real room programs** — ground floor: living + kitchen + dining; upper
  floors: bedrooms + office/lounge variety; every floor gets a guaranteed
  bathroom; office towers get desks, meeting and break rooms. Floor finishes
  follow the room type (tile / carpet / wood).
- **Stairs that always work** — polygon-aware placement with 0/90 deg
  orientations, tread refitting for narrow footprints, correct 2 m headroom
  slab openings, no stairs into the top ceiling, fixed spiral helix.
- **Balconies are accessible** — the balcony door span is reserved in the
  facade layout (no window overlaps it), glass door + railing + slab land in
  the room behind.
- **Z-fighting pass** — floor finishes offset from the sub-finish, slab bands
  outset as visible floor ledges, texture mipmaps enabled (no more distant
  moire).
- **Sealed roofs** — ray-cast eave soffits close the overhang wedge on any
  footprint shape; ovals get ellipsoid domes.
- **Door frames** — proper 2-jamb + lintel frames on every interior door,
  placed clear of wall T-junctions; furniture keeps clear of door swings.

## Testing

Headless test suites (run from the project root):

```bash
godot --headless --path . --script res://tests/geo_smoke.gd        # geometry invariants (analytic volumes)
godot --headless --path . --script res://tests/e2e_test.gd         # 63 checks: generation + edit preservation
godot --headless --path . --script res://tests/connectivity_test.gd # 76 checks: door reachability, stairs, balconies
godot --headless --path . --script res://tests/zoo_runtime_test.gd  # zoo map: 16 buildings + player + restyle
```

## License

MIT — see [LICENSE](LICENSE).
