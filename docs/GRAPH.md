# Graph

## What it shows

- **Global graph** (Graph tab): every note is a dot; every line is an
  **explicit link** between two notes (a wiki link or a Markdown link that
  resolves to a note, in either direction). Links appearing several times
  are drawn once; self-links are not drawn.
- **Local graph**: the notes directly linked to/from one note
  ("Direct links only"), or two steps away ("Links of links"). Open it by
  long-pressing a dot or from a note's ⋮ menu → *Local graph*.

| Look | Meaning |
| --- | --- |
| Filled emerald dot | Note with at least one link; bigger = more connections |
| Hollow grey dot | Unlinked (isolated) note |
| Orange ring | Focus note of a local graph |
| Ring + full colour while highlighting | Title matches the highlight text; others are dimmed |
| Solid line | Explicit link written in your notes |
| Dashed line | Reserved for future AI-suggested links (not produced today) |

## Interaction

Pinch to zoom, drag to pan, tap a dot to open the note, long-press for its
local graph. The search icon highlights notes by title. ⋮ → *Show unlinked
notes* hides or shows isolated notes. The graph refreshes automatically when
the index changes (after saving in Emerald, or after **Rescan** for outside
edits) and keeps existing dots roughly in place.

## Implementation and package choice

Custom implementation (`lib/features/graph/`): a force-directed
(Fruchterman–Reingold) layout in pure Dart with grid-based repulsion, drawn
by a single `CustomPainter` inside Flutter's `InteractiveViewer`. Graphs above
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
