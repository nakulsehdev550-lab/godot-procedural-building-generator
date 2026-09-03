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
