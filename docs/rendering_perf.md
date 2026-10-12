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
