# Map rendering: tests and benchmarks

The map is ~8,600 tiles. Each tile has a background, a sprite (or a text glyph) and border lines, all drawn from
GDScript in `scripts/map_view.gd`. Rendering is cheap only if the map rarely rebuilds those
draw commands and the GPU gets them in large batches.

## The checks

**Behaviour tests** (`test_map_render.gd`) run headless, so they're fast. They use the map's counters
(`map.stats`): how many tile-layer and overlay redraws happened, how many tiles were drawn, and the
CPU time spent. They pin down rules like these, so an optimization can't quietly regress:

- Hovering redraws only the overlay.
- Panning and zooming redraw nothing.
- Selecting a tile or training troops redraws no tiles.
- A claim redraws at most the 4 chunks around it.

**Smoke test** (`test_main_scene.gd`) runs the real `main.tscn` with its map, camera and HUD. It starts
a colony, zooms and ends a season by clicking the END SEASON window, as a player would.

**Map art tests** (`test_map_art.gd`) check which sprite goes where and that changing the art redraws the map. With a
GPU they also check the pixels on screen: a ground tile or unit is exactly the atlas sprite at 2x.

**GPU tests** need a window. Headless runs skip them.

- `test_snapshots.gd` renders the map in a dozen views and compares them with the images in `snapshots/`: your home area
  (in the clean pixel art, the older sprite styles and text glyphs), the whole map, contours up close, buildings, roads and the highway,
  the selection with routes, remembered enemy land, and units. It also plays through claims, moving units and seasons, and after each step
  checks the live map against a fresh draw, pixel for pixel. That catches chunks that should have
  redrawn but didn't.
- `test_gpu_budget.gd` fails if an idle frame needs more than about 2x today's draw calls, which
  means batching broke.

```powershell
.\tests\run.ps1 -Windowed --filter=render                          # all render tests, GPU ones included
.\tests\run.ps1 -Windowed --filter=snapshot --update-snapshots    # after an intended visual change
```

When a snapshot fails, the test saves `NAME.actual.png` and `NAME.diff.png` to `tests/results/snapshots/`.
In the diff, changed pixels are red. Baselines depend on the GPU, driver and fonts, so remake
them when you move to another machine.

**Benchmarks** (`tests/bench/bench_map_render.gd`) start a mid-game map with everything explored.
They time full redraws, panning, a hover sweep, selecting a tile, training a troop and ending a
season. Windowed runs also give frame times, GPU time and draw calls.

```powershell
.\tests\run.ps1 -Windowed --bench --save=before     # before a change
.\tests\run.ps1 -Windowed --bench --compare=before  # after it: prints each metric's change
```

## Workflow for an optimization

1. Save a benchmark run: `--bench --save=before`.
2. Write the behaviour test for the rule you're adding, for example "panning doesn't redraw tiles".
   Watch it fail.
3. Make the change. Run the whole suite headless, then `-Windowed --filter=render` for the GPU tests.
4. Compare the benchmarks with `--compare=before`, then record the numbers in `docs/rendering_perf.md`.
