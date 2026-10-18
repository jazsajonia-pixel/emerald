# Graph

## What it shows

- **Global graph** (Graph tab): every note is a dot; every line is an
  **explicit link** between two notes (a wiki link or a Markdown link that
  resolves to a note, in either direction). Links appearing several times
  are drawn once; self-links are not drawn.
- **Local graph**: the notes directly linked to/from one note
  ("Direct links only"), or two steps away ("Links of links"). Open it by
  tapping a dot → *Focus local graph*, or from a note's ⋮ menu → *Local graph*.

| Look | Meaning |
| --- | --- |
| Solid coloured dot | A note. Colour = its top-level folder (or its cluster of linked notes when the vault has no folders); bigger = more connections |
| Grey dot | Unlinked (isolated) note |
| Violet ring | Focus note of a local graph |
| Glowing links + bright neighbours | The note you are holding or last tapped; everything else dims |
| Solid line | Explicit link written in your notes |
| Dashed line | Reserved for future AI-suggested links (not produced today) |

## Interaction

- **Hold a dot**: it pops with a springy bounce and a ripple, its links light
  up in its colour and its neighbours grow slightly.
- **Drag it**: the note sticks to your finger and its linked notes follow
  elastically (two steps away a little), like Obsidian. Release and the graph
  settles with a soft wobble.
- **Tap a dot**: actions (open, focus local graph, pin).
- **3D** (default): notes float in a 3D cloud. Drag empty space to orbit
  (with inertia), pinch to zoom; it slowly auto-orbits when idle (toggle in
  the toolbar). Far dots are shaded darker for depth.
- **2D**: drag empty space to pan, pinch to zoom. Switching 2D ↔ 3D morphs
  smoothly between the flat map and the cloud.

The search icon highlights notes by title. ⋮ → *Show unlinked notes* hides or
shows isolated notes. The graph refreshes automatically when the index
changes and keeps existing dots in place. With Android's "Remove animations"
setting, all motion is skipped.

## Implementation and package choice

Custom implementation (`lib/features/graph/`): an initial force-directed
(Fruchterman–Reingold) layout in pure Dart, then a live d3-style simulation
(repulsion — exact up to 260 notes, grid-local above — link springs, centring
gravity, velocity damping, cooling "temperature") in 2D or 3D, rendered with
a perspective camera by a single `CustomPainter` driven by one ticker that
stops when everything is at rest. Graphs above
150 notes are laid out on a background isolate (`Isolate.run`) so the UI does
not freeze.

Packages reviewed (October 2026) and not used:
- `graphview` 1.5.1 (MIT, last release Oct 2025): each node is a widget and
  layout runs on the UI thread, which scales poorly to large vaults.
- `flutter_graph_view` 2.1.0 (Apache-2.0): built on the Flame game engine — a
  large dependency for this use.
- `force_directed_graphview`, `flutter_force_directed_graph`: low adoption /
  infrequent maintenance.

## Limits

- The global graph shows at most **2,500 notes**; above that the most
  connected notes are kept and a banner says how many are hidden.
- Measured layout time in CI-like conditions: ~0.3 s for 1,500 notes and
  1,500 links (unit test `graph_model_test.dart` prints the timing). Phones
  are slower; the layout runs off the UI thread.
- Labels are shown for small graphs or when zoomed in, to stay readable.
- No folder/tag filters or colour groups yet.
