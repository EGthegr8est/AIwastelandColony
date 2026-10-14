# Map rendering performance log

All numbers come from `.\tests\run.ps1 -Windowed --bench` on an RTX 3070 Ti (Vulkan, Forward+) with
Godot 4.7.2. The map is 120 x 72, mid-game, with everything explored. Vsync is off.
"Map CPU" is the time spent in GDScript building the map's draw commands.
Lower is better throughout.

## Results

| Metric | Baseline | 1. Overlay layer | 2. Chunks | 3. Batching | 4. Change tracking | 5. Tile CPU |
|---|---|---|---|---|---|---|
| Full redraw, zoom 1 (3,432 tiles visible) | 24.1 ms | 24.0 ms | 36.3 ms (5,120 tiles) | 37.7 ms | 38.0 ms | **19.4 ms** |
| Full redraw, whole map (8,640 tiles) | 59.7 ms | 59.6 ms | 60.9 ms | 63.7 ms | 64.0 ms | **32.9 ms** |
| Pan at zoom 1: frame time | 38.1 ms (26 fps) | 38.0 ms | **10.0 ms** | **2.7 ms** | 1.4 ms | 1.4 ms |
| Pan at zoom 0.5: frame time | 64.3 ms (16 fps) | 64.1 ms | **13.0 ms** | **1.4 ms** | 1.4 ms | 1.4 ms |
| Hover sweep: frame time | 30.4 ms | **6.1 ms** | 8.7 ms | **1.1 ms** | 1.1 ms | 1.1 ms |
| Hover sweep: map CPU per frame | 24.0 ms | **0.03 ms** | 0.04 ms | 0.03 ms | 0.03 ms | 0.03 ms |
| End season: map CPU | 23.1 ms | 23.2 ms | 35.3 ms | 36.7 ms | **3.6 ms** | 3.5 ms |
| Select a tile: map CPU | - | - | - | 38.5 ms | **3.5 ms** | 2.9 ms |
| Train a troop: map CPU | - | - | - | 38.6 ms | **4.2 ms** | 3.1 ms |
| Steady frame, zoom 1: render CPU / draw calls | 5.5 ms / 9,405 | 5.5 ms / 9,405 | 8.3 ms / 14,381 | **0.9 ms / 580** | 0.9 ms / 612 | 0.9 ms / 612 |
| Steady frame, whole map: render CPU / draw calls | 10.1 ms / 17,325 | 10.2 ms / 17,325 | 10.1 ms / 17,325 | **1.1 ms / 723** | 1.1 ms / 755 | 1.1 ms / 755 |

Where the time went at the baseline:
- **The map redraws on every camera move and every hover change.** One map node drew only the
  tiles on screen, so any pan or zoom, and any new hovered tile, rebuilt everything visible
  (about 24 ms).
- **Draw calls don't batch.** Each tile draws a rect, then a glyph, then lines, and scaled pipe
  glyphs set a transform. Every switch between those breaks the GPU batch, so there's roughly one
  draw call per primitive. That gives about 9,400 draw calls even on frames where nothing is redrawn.

## 1. Overlay layer

The hover box, selection box and route dots moved to a child canvas item (`OverlayLayer` in
`map_view.gd`). Hovering a new tile now redraws only those few shapes instead of every tile.
Snapshots are pixel-identical. What's left in a hover frame is the steady-frame cost: about
9,400 draw calls.

## 2. Chunks

The tile layer is now 16 x 16-tile chunks (`Chunk` in `map_view.gd`), each its own canvas item.
A chunk draws all its tiles once and keeps the result. The renderer skips chunks that are off
screen, so panning and zooming redraw nothing. After a game change, the chunks on screen redraw
right away and the rest redraw when they scroll into view. Snapshots are pixel-identical.

The tradeoff: a chunk that is only partly on screen still draws all its tiles. So a redraw at
zoom 1 builds about 5,100 tiles instead of 3,400, and idle frames send about 50% more draw calls.
That makes step 3 (batching) the priority.

## 3. Batching

Each chunk now draws in passes: every background rect first, then every glyph, then all border
lines in one `draw_multiline_colors` call. The renderer only batches runs of the same kind of
primitive, so the old per-tile order of rect, glyph and lines cost about one draw call per
primitive. Idle frames went from about 14,400 draw calls to about 580.

This is a small, intended visual change. A glyph's or border line's antialiased edge that spills
1 px into the next tile used to be painted over by that tile's background. Now it stays, because
backgrounds are drawn first. It touches 0.05-0.2% of pixels, mostly where contour pipes join, and
isn't visible at normal size. The snapshot baselines were updated.

## 4. Change tracking

Most game changes don't touch the map: selecting a tile, training troops, trading, upgrades. Yet
each one redrew every chunk on screen (about 38 ms, a visible hitch per click). Now each chunk
keeps a hash of everything that decides its look: what the viewer remembers and sees of its
tiles, the ring of tiles around it (border lines depend on neighbours), and the units and camps
standing in it. After a change, only chunks whose hash moved are redrawn. Switching the view or
loading a new map (`Game.map_version`) redraws everything.

The remaining ~3.5 ms is the hashing itself, which slices the fog arrays for all 40 chunks. A
windowed test plays through claims across a chunk edge, a band moving in sight, a scout walking
away and seasons passing off screen. After each step it compares the live map with a fresh
draw, pixel for pixel. It catches each missing ingredient of the hash: sight, memory, the border
ring and units were each removed in turn to check.

## 5. Tile CPU

The look of a tile with nothing built or standing on it depends only on terrain and contours,
which change only with a new map. So its glyph and both shades (in sight and remembered) are now
worked out once per `Game.map_version`. Drawing also reads the viewer's memory and sight arrays
directly, instead of through per-tile calls, and checks border sides without allocating a
Dictionary per tile.

Profiling before this step put a tile at about 5.4 us. Fog and sight lookups, recomputing the
ground glyph and building the border Dictionary each took about 1.2 us. `draw_string` took
0.9 us; `draw_char` would save only 0.2 us, so it wasn't worth the risk of shifting pixels.
Redraws now cost half as much. Snapshots are byte-identical.

## 6. Pixel-art sprites

The map now draws pixel art instead of text glyphs (`art/atlas.png`, see the README). Each chunk gets one more pass,
between the backgrounds and the text: every ground sprite, slope mark, unit and camp, drawn with
`draw_texture_rect_region` from the single atlas texture, so the renderer batches the lot. Buildings are still text.
The cell went from 18 to 16 pixels so an 8 x 8 sprite is exactly 2x. That shows more of the map at zoom 1 (5,760 tiles
get drawn per full redraw instead of 5,120), so that number isn't comparable. Switching the art redraws every chunk, via the
same change tracking as a view switch. Measured with `--bench --compare`, same machine, text glyphs before and sprites after:

| Metric | Text glyphs | Sprites |
|---|---|---|
| Full redraw, zoom 1: map CPU | 21.3 ms | 21.4 ms |
| Full redraw, whole map: map CPU | 35.6 ms | 32.4 ms |
| Select a tile / train a troop: map CPU | 3.3 / 3.3 ms | 2.5 / 2.3 ms |
| End season: map CPU | 3.6 ms | 3.5 ms |
| Steady frame, zoom 1: draw calls | 382 | **101** |
| Steady frame, whole map: draw calls | 524 | **111** |
| Pan at zoom 1: frame time | 1.19 ms | 1.2 to 1.6 ms (it varies that much between identical runs) |

Pixel art has to be sampled with nearest-neighbour filtering to stay crisp, so the tile layer is set to that while sprites are
showing (the glyphs keep the default). That also makes the building text blockier at zoom levels other than 1.

## What's next

- **The hashing in change tracking (~3 ms per change).** It slices the fog arrays for all 40
  chunks. Hashing each 16-tile row segment once and combining those would roughly halve it.
- **Outside the map:** `hud.gd` rebuilds every panel on each `Game.changed`. `Game.update_fog()`
  also runs on every change and re-remembers every visible tile. Neither is measured yet; a
  benchmark that clicks through the real `main.tscn` would show whether they now dominate a click.


## The game's turn and the side panel (2026-10-12)

Not drawing but the work around it. Measured with `.	estsun.ps1 -Windowed --bench --filter=bench_game_logic` (the new
`tests/bench/bench_game_logic.gd`) on the same machine, a mid-game colony: 25 seasons in, 36 buildings, 60 Rust Kings walls, the whole map
explored.

| What | Before | After | Change |
|---|---|---|---|
| One change to the game (select, build, anything): fog, map and every panel | 88 ms | 27 ms | The side panel rebuilt all four tabs, three out of sight. Only the tab in view is rebuilt now; the others are marked stale and rebuild when opened. |
| Rebuild the whole HUD | 84 ms | 26 ms | (same) |
| One Rust Kings scout (2 to 4 a season) | 28.5 ms | 2.1 ms | The map scan for their frontier asked `knows_tile` and `neighbors` for each of the 8,640 tiles. It reads the memory array directly now. |
| The Rust Kings' whole turn | 149 ms | 18 ms | (same) |
| End a season | 177 ms | 81 ms | Of the 81 ms, about 42 is the autosave. |

Map drawing against version 3, with `--compare`: every number within 3%, so the points of interest and the new tiles cost nothing
measurable. Other costs, for scale (per call): `owned()` and `count_building()` scan the whole map in about 1.2 ms each; `update_fog` 4.6 ms;
saving 40 ms (282 KB), loading 317 ms; opening the leader screen 13 ms; making three leaders 0.14 ms.

Left alone: the tile panel (15 ms) and the Colony and Upgrades panels (31 and 22 ms) are slow to build when they are the tab in view, and a
whole-map scan like `count_building` is called several times by one panel. Caching the counts would need every place that changes a tile to
clear the cache, which is easy to get wrong, so it is not done.


## Fullscreen and window size (2026-10-13)

Measured with `.	estsun.ps1 -Windowed --bench --filter=bench_fullscreen` (new: `tests/bench/bench_fullscreen.gd`) on the same RTX 3070 Ti and a 4K
screen. It runs the real `main.tscn` (map, top bar, side panel, log) windowed at 1600 x 900, maximized (3840 x 2054) and fullscreen
(3840 x 2160), by day and by night, with vsync off. It really does go fullscreen for a few seconds.

**Steady frames cost the same at every size.** The game is CPU-bound at about 1 ms a frame and the GPU hardly notices 4K:

| Frame, median | 1600 x 900 | maximized | fullscreen 4K |
|---|---|---|---|
| Standing still, zoom 1 (day) | 1.03 ms | 1.01 ms | 1.01 ms |
| Standing still, night | 1.05 ms | 1.04 ms | 1.04 ms |
| Panning, zoom 1 | 1.13 ms | 1.12 ms | 1.12 ms |
| Whole map, zoom 0.25 | 1.28 ms | 1.27 ms | 1.27 ms |
| Hovering the map | 1.16 ms | | 1.08 ms |
| GPU time, standing still | 0.08 ms | 0.27 ms | 0.26 ms (night 0.32) |
| Draw calls | 164 | 164 | 164 |

Not one of 400 idle frames went over 8 ms in either mode, and a whole season's walk (day into night) ran at 1.46 ms a frame windowed and 1.48 fullscreen.
Clicking a tile costs about 22 ms in both (the side panel rebuilds: see "The game's turn" above), which is the same hitch windowed.

**Changing the window size was the one thing that cost more than it should.** Going fullscreen, going back, maximizing or dragging an edge each cost
about 200 ms over two frames (about 140 ms of it on the first). The cause: **the engine redraws every `_draw` node whenever the window changes
size** (a throwaway test showed it for any node, in every stretch mode, even inside a SubViewport), and the map's 40 chunks are `_draw` nodes. All 40
redrew each time, 8,640 tiles and about 80 ms of map CPU, with nothing about the map having changed. An empty scene costs 60 to 90 ms on the first frame and
about 50 on the second for the swapchain alone, so the map was most of what the game added.

The chunks now draw on a rendering item of their own (`Chunk.art`, a child canvas item made with `RenderingServer.canvas_item_create`) with the same commands
(`canvas_item_add_rect`, `canvas_item_add_texture_rect_region`, `canvas_item_add_multiline`, `Font.draw_string(rid, ...)`), cleared and redone only when the chunk's
hash changes. The engine has no `_draw` to redo for them. Snapshots are pixel-identical (all 13, including the text-glyph style), and the chunks that hold text
glyphs (the ASCII look, a few building letters) are still redone when the window's scale changes, because text is drawn for the scale it has.

| Window size change | Before | After |
|---|---|---|
| Chunk redraws on a size change | 40 (8,640 tiles, 80 ms map CPU) | **0** |
| Going fullscreen or back: the two frames after | about 200 ms (150 + 55) | **about 145 to 170 ms** (an empty scene is about 140) |
| Dragging a window edge: each step | about 145 ms | **about 68 ms** |

What is left of the mode change is the engine and the driver recreating the window's surface; it is the same whatever the vsync mode (enabled, disabled, mailbox,
adaptive: 133 to 173 ms for the first three frames in an empty scene).

**The legend** (the Tile tab with nothing picked: about 40 rows with pictures) took about 22 ms to build, on every change of the game while nothing was picked.
It only changes with the art style and the Night switch, so `Hud._legend()` keeps it between rebuilds: a change with nothing picked went from about 42 ms to about 19 ms.

Left alone: a tile click (about 17 to 23 ms: the panel's controls are made fresh each time, around 0.35 ms each), the 100 to 120 ms of `end_season` (about 40 of it the
autosave), and the first frame of a season replay.

