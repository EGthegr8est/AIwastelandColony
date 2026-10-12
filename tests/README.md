# Tests

A small test runner for Godot 4.7, written in GDScript. It has no addons or plugins.

## Running

```powershell
.\tests\run.ps1                       # every test, headless (no window)
.\tests\run.ps1 --filter=game         # only tests whose path::name contains "game"
.\tests\run.ps1 --list                # list tests without running them
```

`run.ps1` looks for Godot in `$env:GODOT`, then `Godot_v*_console.exe` on your Desktop, then `godot`
on PATH. Without the wrapper, run Godot's **console** executable from this project folder:

```
godot --headless --path . -s res://tests/run_tests.gd -- --filter=game
```

| Option | What it does |
|---|---|
| `--filter=TEXT` | Run tests whose `res://path::test_name` contains TEXT (case-insensitive) |
| `--dir=res://tests/unit` | Only look in this folder |
| `--timeout=30` | Seconds before a test counts as hung (default 30) |
| `--junit=res://tests/results/junit.xml` | Also write JUnit XML, for CI |
| `--bench` | Run benchmarks instead of tests (see below) |
| `--list` | Print the tests and stop |
| `--update-snapshots` | Remake the pixel snapshot baselines (see `render/README.md`) |

The exit code is 0 when everything passes, 1 when something fails, and 2 when no tests ran.

**Your saves are safe.** `setup.gd` points `Game.save_dir` at `user://test_saves/` before any test
runs, then deletes that folder afterward. `test_the_players_real_saves_are_untouched` checks this.

## Writing a test

Make a file named `test_<something>.gd` anywhere under `tests/`:

```gdscript
extends "res://tests/framework/test_case.gd"

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

func before_each() -> void:
	World.new_game(7)        # a fixed seed makes the same map every time

func test_claiming_costs_wood() -> void:
	var c := World.claimable_tile()
	var wood: int = Game.res.wood
	Game.claim(c)
	assert_eq(Game.tile(c)["o"], Data.PLAYER)
	assert_lt(Game.res.wood, wood)

func test_something_async() -> void:
	await wait_frames(2)     # tests are nodes in the scene tree, so they can await
```

Tests run in the order they're written. Each file gets one instance, added to the scene tree.

- **Hooks:** `before_all`, `before_each`, `after_each` and `after_all`. All are optional, and all may await.
- **Assertions:** `assert_eq`, `assert_ne`, `assert_true`, `assert_false`, `assert_almost_eq`,
  `assert_gt`, `assert_ge`, `assert_lt`, `assert_le`, `assert_null`, `assert_not_null`,
  `assert_has`, `assert_not_has` and `fail`. A failed assertion records the file and line, and the
  test keeps running.
- **Engine errors fail the test.** This includes null access, a bad dictionary key and `push_error`.
  Call `expect_error("text")` first when the error is the point of the test.
- **Helpers:**
  - `wait_frames(n)`, `wait_seconds(s)` and `wait_until(callable, timeout)` wait.
  - `watch(obj, "signal")` counts emissions.
  - `add_autofree(node)` frees the node after the test.
  - `skip("why")` marks the test skipped.

## Rendering tests and benchmarks

`tests/render/` holds the map-rendering tests. `tests/bench/` holds the benchmarks. See
[the render notes](render/README.md) for what they measure and how to use them while optimizing,
and `docs/rendering_perf.md` for the numbers so far.

## Layout

| Path | What |
|---|---|
| `run_tests.gd` | Command-line entry point (`-s res://tests/run_tests.gd`) |
| `run.ps1` | Finds Godot and runs the above |
| `setup.gd` | Project hooks that run once before and after all tests (save folder redirect, screen size) |
| `framework/` | The runner, `test_case.gd`, `bench_case.gd` and the error catcher |
| `helpers/` | Shared setup for tests (seeded new games, tile search, the map render fixture, snapshot compare) |
| `unit/` | Simulation tests, plus the framework's own tests |
| `render/` | Map-rendering behaviour tests, pixel snapshot tests and their baseline images |
| `bench/` | Benchmarks |
| `results/` | Saved benchmark runs, JUnit output and snapshot diffs (not committed) |
