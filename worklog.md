# BuildingForge — Work Log

---
Task ID: 8
Agent: main
Task: Make repo public, restore project after sandbox wipe, re-verify, ship v1.0.0 release

Work Log:
- Sandbox deleted the local project directory (predicted risk); cloned it back from GitHub backup — zero data loss (7 commits intact)
- Changed repo visibility from private → public via PATCH /repos (user request: access from other devices)
- Re-downloaded Godot 4.7.1-stable binary to /home/z/my-project/tools/godot, verified `4.7.1.stable.official.a13da4feb`
- Rebuilt .godot caches via `--headless --import` (class_name registry restored)
- Re-ran tests on restored project: geo_smoke ALL PASSED; e2e 28/28 PASSED
- Found + fixed latent warning: finalize() reparent() called get_global_transform on out-of-tree nodes → now `reparent(standalone, is_inside_tree())`
- Committed generated .import files (locks texture import settings for end users)
- Built release zips: building_forge_plugin_v1.0.0.zip (extract-to-project-root, addons/ at root) + building_forge_full_project_v1.0.0.zip (full project)
- Created GitHub Release v1.0.0 (id 381828791) with both zips as assets (42.9 MB each, state: uploaded)
- Zips gitignored (release assets are the distribution channel, keeps repo lean)

Stage Summary:
- Repo PUBLIC: https://github.com/nakulsehdev550-lab/godot-procedural-building-generator
- Release: https://github.com/nakulsehdev550-lab/godot-procedural-building-generator/releases/tag/v1.0.0
- All tests green post-restore; project considered shipped. User should revoke the PAT token now that public access is configured.

---
Task ID: 9
Agent: main
Task: v1.1 overhaul — fix architecture bugs reported by user (stairs, room kinds, doors, balconies, z-fighting, regenerate)

Work Log:
- Read all core sources (3734 LOC). Root causes identified:
  R1 REGENERATE: generate() queue_free's old "Generated" then adds new same-name child in same frame -> Godot renames new node to @Generated@N -> next regen never finds "Generated" -> buildings pile up. Same for "Collision" node.
  R2 SEALED STAIRS: partition() carves the stair cell out of candidates; boundary walls face the shaft and never get doors -> stairwell unreachable. Spanning tree only connects regular rooms.
  R3 SEALED FACADE: bounds pre-shrunk (grow(-0.1)/grow(-0.05)) -> rooms sit 0.15 m inside facade; _edge_facing_void adds boundary walls along facade edges -> windows/balcony/entrance doors open into dead 0.15 m gaps.
  R4 ALL BEDROOMS: assign_kinds() final loop converts "living"->"bedroom"; upper floors never get kitchen; floors w/o small rooms get no bath.
  R5 BALCONY OVERLAP: layout_floor doesn't reserve balcony door span -> window punched at same spot as balcony door -> double frames, z-fight, blocked opening.
  R6 Z-FIGHT: floor-0 global finish and room finishes at identical y=0.021; flat-roof railing floats 0.55 m above deck (base_y=base+0.6 instead of deck top).
  R7 STAIR PLACEMENT: narrow/irregular footprints fail rect_in_polygon -> "skipping stairs" but stairs still built at bad centered cell; no rotation candidates; stairs also built on TOP floor into solid ceiling; straight-stair slab hole starts too far up run (headroom<2.05 mid-flight).
  R8 EAVE SOFFIT missing on gable/hip/cone -> see-through under overhang from below.
  R9 PROPS ignore doors -> furniture can block doorways.
- Plan: shaft becomes a real Room (kind stair) so spanning tree doors reach it; rooms touch facade (boundary walls only face true interior voids); robust stair placement with rotation+grid+fit; layout_floor reserves balcony span; kind program (living/kitchen/dining/bath/office per floor); z-fight offsets; soffits; door-aware prop layout; free() instead of queue_free.

---
Task ID: 10
Agent: main
Task: v1.1 QA gauntlet — agent-rated visual tours, root-cause fixes, release

Work Log:
- Ran 3 agent review rounds + own verification on every critical claim (agents caught real bugs; several "missing" items were camera-angle artifacts — verified by re-rendering face-on)
- FIXED (critical): interior door frame basis confusion — jambs offset ACROSS the wall (floating columns in every doorway since v1.0) + top bar at mid-height; spiral steps orbited cell corner instead of pole; regenerate pile-up (queue_free + same-frame add_child name collision)
- FIXED (arch): stairwell as first-class room; rooms touch facade; room-kind program per floor w/ guaranteed bath; door T-junction avoidance; short-seam walls + sub-span coverage pass (no open holes between misaligned rooms); hall-bridge safety net
- FIXED (visual): mipmaps enabled (facade moire), ray-cast soffits to real roof extent, ellipsoid domes, slab band outset, circular facade even windows, no balconies on circles
- Test suites: geo_smoke ALL + e2e 28/28 + connectivity 76/76 (new suite)
- Zoo: 12 buildings x (4 exterior + every-room interior tours) = 335 renders; reviewed by agents each round
Stage Summary:
- v1.1.0 ready. Release: plugin zip WITHOUT baked textures (unchanged from v1.0.0 per user request)

---
Task ID: 11
Agent: main
Task: Release v1.1.0

Work Log:
- Release created: https://github.com/nakulsehdev550-lab/godot-procedural-building-generator/releases/tag/v1.1.0
- Assets: building_forge_plugin_v1.1.0.zip (77.6KB, code-only) + building_forge_full_project_v1.1.0.zip (115.6KB) — baked textures EXCLUDED per user request (unchanged from v1.0.0; noted in release body)
- All work pushed incrementally; final renders in renders/zoo/
Stage Summary:
- v1.1.0 shipped. Todo: user should revoke the PAT token when done.

---
Task ID: 1
Agent: research
Task: Research procedural building tools for feature inspiration

Work Log:
- Read worklog + README to ground research in current v1.1.0 feature set (drawn footprints, 5 facades, 5 roofs, BSP rooms, 24 props, baked PBR)
- Ran 15+ targeted web searches (Blender Building Tools/Archipack/Buildify/PBG2, Unity BuildR 2/3, Houdini Labs Building Generator + Utility, CityEngine CGA, Townscaper, SketchUp/Medeek/Revit wall UX, Godot Asset Library, floor-plan algorithms)
- Fetched + extracted full text of: Archipack features page, Archipack manipulate-mode manual, SideFX Labs Building Generator 4.0 + Utility 2.0 docs, ranjian0 Building Tools wiki (Roof/Multigroup/Floorplan/Window), 80.lv Houdini building generator interview, Townscaper GDC case study, Medeek Wall (SketchUp) docs, BuildR 2 forum thread, CGA component-split docs
- Mapped findings to BuildingForge's Geometry3D/ArrayMesh architecture and rated each idea by implementation difficulty
- Saved raw results in /tmp/bf_research/ (19 JSON files)

Stage Summary:
- Biggest steals: (1) face-driven incremental building (Blender Building Tools), (2) Archipack-style live manipulator handles with snap/constraints/numeric entry, (3) Houdini Labs "Expanded Form" facade pattern grammar with per-floor overrides + corner modules, (4) BuildR-style overhanging floors/setbacks, (5) corridor+core floor plans for towers (BuildR 3 / TU Delft A* corridor paper)
- Godot Asset Library has NO competing full architecture generator (only grid-placement/dungeon tools) — green field
- Key pitfalls: single-style tunnel vision (THE FINALS postmortem), fragile hidden helper state (Archipack collections), UV blowup without per-part material indices + UV randomization, regeneration vs. hand-edits conflict (bake-out option needed)
- Full ranked list of 18 feature ideas with difficulty ratings delivered in final report

---
Task ID: 12
Agent: main
Task: v1.2 — interactive editing suite, FPS zoo map, custom models, research-driven features

Work Log:
- Sandbox wiped again; restored from GitHub (clone) + re-downloaded Godot 4.7.1; baseline green (geo/e2e 28/28/connectivity 76/76)
- Research agent reviewed Blender Building Tools/Archipack, BuildR, Houdini Labs BG, CityEngine CGA, Townscaper -> top-18 feature list (per-floor overrides, custom openings, prop swapping, more roofs, bands, chimney, fence, presets)
- Plan: M1 glass transparency/z-fight fix; M2 parametric features; M3 gizmo v2 + right-click wall editing; M4 FPS zoo map; M5 tests+visual QA; M6 release v1.2.0 (code-only)

Stage Summary:
- In progress

---
Task ID: 13
Agent: main
Task: v1.2.0 release — QA, version bump, push, zip upload to GitHub release

Work Log:
- Sandbox wiped again; restored via shallow clone (1.3GB, renders heavy) + re-downloaded Godot 4.3-stable (project features tag says 4.7 but 4.3 API-compatible, all tests green)
- Baseline verified: geo_smoke ALL PASSED, e2e 63/63, connectivity 76/76, zoo_runtime ALL PASSED (16 buildings, player, camera, collision, runtime restyle)
- Visual QA: wrote tests/qa_v12_shots.gd (loads real zoo_map.tscn, 6 overview + 4 street + 1 facade close-up); renders/qa_v12/ reviewed — windows have real thickness, no z-fighting, no residue
- plugin.cfg 1.0.0 -> 1.2.0; README: added "What changed in v1.2" section + 4-suite test matrix
- Next: commit, tag v1.2.0, build code-only zips (textures excluded per user instruction), create release, upload zips

Stage Summary:
- v1.2.0 verified release-ready; zips exclude baked textures (unchanged since v1.0.0, user already has them)
