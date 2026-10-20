# Wasteland Colony

A 2D post-nuclear colony sim for Godot 4.7, coded with AI by Eric B. You lead a band of survivors in the wastes: claim land, build, scout the fog, scavenge ruins with d20 rolls, trade, hunt, fight the
raider kingdom across the river, and try not to get nuked. Pixel-art tiles at 16 x 16 pixels (or ASCII ones, in the style of Dwarf Fortress) under an amber terminal UI.

**Status (2026-10-20): the turn overhaul is built.** Your parties walk on your orders with a days-per-turn budget and are numbered; the colony's people are named survivors who stay the same people
(and are remembered when they fall); raids are made by parties on both sides, through the building attack rolls, down to the hearths. What is left is under "What's next". The commit history
since `2ecf5b5` has one commit for each step. Tests: headless 1490 passed and 27 skipped (they need a GPU), windowed render 473, snapshots 12; a long soak of three
unattended games (one defended) ran with no errors.

- [How the game works](docs/GAME_REFERENCE.md): every system, with the code that does it and the tests that pin it.
- [`tools/PLAY_ME.txt`](tools/PLAY_ME.txt): the player's one-page guide that ships with the Windows build.
- [`tests/README.md`](tests/README.md) and [`tests/render/README.md`](tests/render/README.md): the test runner, the render tests and the snapshots.
- [`docs/rendering_perf.md`](docs/rendering_perf.md): map rendering numbers.

## Running it
1. Open Godot 4.7 (4.7.2 was used), click **Import**, and pick `project.godot`.
2. Press **F5**.

After adding an asset or a script, run `godot --headless --path . --import` once, so Godot writes its `.import` and `.uid` files; commit those too.
Saves live in `%APPDATA%\Godot\app_userdata\Wasteland Colony\saves\` (and the settings in `settings.cfg` beside them).

## Controls and interface
The layout is designed for 1600 x 900 and scaled to the window (`Main._fit_window`, content scale mode `canvas_items`); **F11** toggles fullscreen.

- **The map:** WASD or arrows pan, the wheel zooms (9 steps from 0.25x to 3x, a notch a step), right-drag pans. Left-click a tile to inspect, claim or build on it; click one of your Scavenger Parties to pick it. Hover a tile for a label.
- **The top bar** (76 px): the status line and the eight resources, a music slider, then three animated pixel-art buttons drawn 20% bigger (`Hud.BAR_ART_SCALE`) and the text buttons:
  - the **radiation meter** (**R**) flips the radiation view; the **field tablet** (**M**) flips the map between pixel art and ASCII; the **END SEASON window** (**E**) ends the season;
  - **Save** (F5), **Load** (F9), **Menu** (Esc).
- **Your parties walk when you order it**, spending the days they have left this turn (40 a turn), and the map plays each walk at once at the normal pace (3 seconds for 40 days); a walk that
  runs out of days waits for **Continue** (G). A numbered **party bar** along the bottom of the map has a button for each party (Shift+its number or its number on the numpad picks it).
- **END SEASON** runs gather, upkeep and the AI turn (the Rust Kings' raiding parties, caravans, boats, planes, bands and animals walk now), gives every party its 40 days back, then autosaves, and the map plays
  that season's walking back (3 seconds; a click on the map or Enter skips it, and while it plays END SEASON only skips; during one of your party's walks it skips it and ends the season). The window shows the sky the season is in (day in Spring and Autumn, night in Summer and Winter); ending the season plays the sun setting or the dawn, stretched to the map's fade,
  with a door click when it settles. With the Night switch off the sky never changes and the window just takes a press.
- **The side panel** (460 px) has four tabs: **Tile** (what you know about the picked tile, what to build, who to send), **Upgrades** (one block per branch, showing the next tier), **Colony** (leader, the survivors and the fallen, forming parties, troops, vehicles) and **Diplomacy**. A **?** at the top of each tab shows or hides its explanations. A building or a send is **one row**: name left, cost right, what it does on hover; one you
  cannot use yet is a dim row in the same place that says why. Buttons are 40 px tall with 17 px text. The log under the map shows 5 lines; click it to expand.
- **Corner pictures:** pick a discovered point of interest, or a seen tile of the old highway, and its picture shows in the bottom right corner (day, night and radiation variants).
- **Sounds** all go through the Music bus, so the one volume slider covers them (down to 0 is silent): the nuke's boom, the die (one sound per number rolled), the radiation meter, the tablet's blip,
  the END SEASON door click.

### Keys
Every button shows its key on a small cap (switch them off with **Key hints: Off** in the legend or a menu; saved as `display/key_hints`). **?** opens a sheet listing all of them (also the
legend's "All the keys (?)" button); **?**, **Esc** or a click closes it. Keys do nothing over a menu, the title, an ending or a picture, and none works with Ctrl, Alt or Meta held.

| Key | Does |
|---|---|
| **1 to 9, 0** | press the open tab's first ten buttons, from the top (0 is the tenth); a locked one says why in the log |
| **Backspace** / **Del** | leave or back off a party's panel / demolish the picked tile's building |
| **F**, **P**, **O**, **L** | build a farm, palisade wall, road (a bridge on a river tile), hunting lodge on the picked tile |
| **Z**, **X**, **C** | send, on foot / on horseback / by war rig, the party the picked tile calls for: scavengers to a ruin, site or crater; a hunting party to an animal or the Giant Frog; scouts to any other ground that is not yours |
| **Q** | form a Scavenger Party on foot at your HQ from the survivors you picked on the Colony tab (or the healthiest), and pick it |
| **Shift+1 to 9, 0** / **numpad** | pick Scavenger Party 1 to 9 (0 is the tenth) |
| **[**, **]** | pick the party before / after the picked one |
| **G**, **B** | the picked party walks on along its route / turns for home (disbanded, if it is at home) |
| **Space** / **Enter** | roll the die of the party at a site, and move on once the number has landed / skip the season's walk |
| **E**, **R**, **M**, **N** | end the season, radiation view, map art (pixel art or ASCII), night on or off |
| **F1 to F4**, **Tab**, **Shift+Tab** | open the Tile, Upgrades, Colony, Diplomacy tabs; next tab, previous tab |
| **F5**, **F9**, **Esc**, **F11** | save menu, load menu, let go of a picked party and then open the menu, fullscreen |

## Tests
```powershell
.\tests\run.ps1                                    # everything, headless (about 35 minutes)
.\tests\run.ps1 -Windowed --filter=render          # the render tests, GPU ones included
.\tests\run.ps1 -Windowed --filter=snapshot        # pixel snapshots of the map (--update-snapshots after an intended visual change)
.\tests\run.ps1 --filter=test_hotkeys              # one file or name
```
Run the three in that order and never two at once (they share the same Godot user folder). Details, the test API and the benchmarks are in [`tests/README.md`](tests/README.md).

## Sending it to a friend (Windows)
Run `.\tools\build_windows.ps1`. It exports a single `WastelandColony.exe` (art and music inside), runs the game's own self-check on it (`WastelandColony.exe -- --selftest`: one ok/FAIL line per thing the
game loads), and zips it with `tools/PLAY_ME.txt` into `..\WastelandColony-release\`.
- It needs Godot's Windows **export templates** once (Editor > Manage Export Templates) and the `Windows Desktop` preset in `export_presets.cfg`. Files the game reads at run time that are not
  pictures or sound (`art/*.json`: the atlases' descriptions) must be in that preset's include filter; the tests and docs are left out. A sprite that works in the editor but shows as text in the built game means a file
  did not make it: run the self-check.
- The exe has Godot's default icon and is not code-signed. **Rebuild before sharing**: an exe built earlier does not have the newest features.

## Project layout
| Path | What |
|---|---|
| `scripts/game.gd` | Autoload `Game`: the whole simulation (map making, economy, diplomacy, the AI turn, endings), plus save/load (JSON in `user://saves/`). |
| `scripts/units.gd` | Autoload `Units`: every unit on the map (your Scavenger Parties, caravans, boats, planes, raider bands and the Rust Kings' raiding parties), animals, the Giant Frog, the season turn, party walking (`_go`) and forming. |
| `scripts/roster.gd` | The colony's people: `Game.roster` makes survivors with a unique name, traits and a face, and remembers the fallen. |
| `scripts/data.gd`, `d20_data.gd` | Every number in the game: terrain, buildings, leaders, upgrades, vehicles, market, the dice tables. Rebalance here. |
| `scripts/d20.gd`, `d20_visit.gd`, `dice.gd` | The d20 roll system: the rules, one ruin or site visit as a series of rolls, and the dice. |
| `scripts/hud.gd` | All the UI, built in code (panels, top bar, key caps, key sheet, menus). Sizes and key tables are constants at the top. |
| `scripts/map_view.gd` | Draws the map (pixel art or glyphs), plays the season and party-walk replays, draws the night, glows and hover label. |
| `scripts/season_replay.gd`, `daylight.gd` | The replay's rules; day and night's rules. |
| `scripts/sprites.gd` | Finds the pixel art in `art/` (atlas, buildings, animals, sites, the title and logo, button sheets). |
| `scripts/rad_meter_button.gd`, `sonar_tablet_button.gd`, `end_season_button.gd` | The three animated top-bar buttons (the tablet extends the meter). |
| `scripts/leaders.gd`, `portrait.gd`, `icons.gd`, `geiger.gd`, `fuel_gauge.gd`, `key_hints.gd` | Leaders and their perks, survivor portraits, travel icons, the Geiger dial, the fuel gauges, the Key hints setting. |
| `scripts/music.gd` | Autoload `Music`: which track plays when, the volume, the sound bus. |
| `scripts/main.gd`, `selftest.gd` | Puts the map, camera and UI together (and fullscreen); the `--selftest` check. |
| `art/`, `audio/`, `d20_dice/` | Pictures (atlases, scenes, leaders, button sheets), music and sounds, the pixel-art die and its sounds. |
| `tools/` | Generators for the art and sounds (`make_*.gd` run in Godot; `make_*.py` need Python, and Pillow where they draw), `build_windows.ps1`, `PLAY_ME.txt`. |
| `tests/` | `unit/` (50 files, the simulation), `render/` (31 files, the real HUD and map), `bench/`, `framework/`, `helpers/`. |
| `docs/` | The game reference, rendering notes, the unit glyph picture. |

## Working on it: things that will bite
- **Engine errors fail a test**, including `push_error`, a null access and a bad dictionary key. If the error is the point, call `expect_error("text")` first.
- **The roster has its own random numbers** (`Roster`), so making a survivor never moves a seeded map; the test runner pins them (`Roster.fixed_seed`), so tests that depend on a survivor's traits stay the same.
- **One audio test is timing-sensitive.** `test_a_click_plays_the_blip_either_way` (sonar tablet) asks whether a 90 ms blip is still playing right after the click; it failed once in a
  full headless run and passes on its own, so run it again before suspecting a change.
- **Settings leak into tests.** `Daylight.enabled` (the Night switch), `KeyHints.enabled` and the music volume are saved to `settings.cfg`, and `SeasonReplay.mode` is a static. A test that depends on one sets it
  itself (the tests set the walk to `"off"`; the light still fades, in 1.2 s).
- `Input.parse_input_event` mouse events do not move the viewport's mouse: use `Input.warp_mouse`. `watch()` on a node that is freed with the scene prints "Lambda capture freed": count in an array from a lambda.
  `RegEx.sub` uses `$1`, not `\1`. A helper must not be named `_same` in a test (the framework has one).
- `Sprites._pictures` caches a missing picture as null for the rest of the run.
- GDScript files use tabs. The working tree is CRLF (`autocrlf`), so git prints line-ending warnings; that is expected.
- **`export_presets.cfg` is rewritten by Godot whenever it opens; do not commit its changes.**
- Do not add `dead_prez` music to the project. A new `wasteland_OST_*.wav` must be added to `Music.GAME` (a test fails until it is).
- Godot keeps only five logs in `%APPDATA%\Godot\app_userdata\Wasteland Colony\logs`.

## What's next
The turn overhaul (days a turn, parties that walk on your orders, the party bar), the survivor roster, the single Scavenger Party, hearths and the raids made by parties are built, in that
order, one commit each. What they leave to do:
- **The Warfare upgrades and vehicle attack no longer do anything for you.** `w1` to `w5`, `wv1` to `wv4` and `Game.vehicle_attack` boosted the army raids, which are gone. They should become modifiers on a
  party's strike and fight rolls (or be reworked); the Rust Kings' own vehicles still count in `Game.ai_attack`.
- **Balance of the new numbers**, all in `scripts/data.gd` and `d20_data.gd`: `AI_RAID` (readiness 40, three quarters of their troops, two parties at most), the 40-day turn (`Data.SEASON_DAYS`), `SCOUT_PACK` 10, the hearth DCs and
  `HEARTH_GUARD_RADIUS`. None of it has been played for long.
- **Caravans, boats, planes and bombers still travel at END SEASON.** They could take the same days-and-Continue treatment as the parties.
- **Unused art and data.** Every party is drawn as the scavenger now, so the teal scout and lime troop pictures in `art/units32.png`, `Data.UNITS["scout"]` and its legend row, and the `scout` sprite in the 16 x 16 atlas are
  not used by anything (the war rig and raider band 32 x 32 pictures are).
- **Parties could be given a name of their own** (the number is all they have), and the roster could show a survivor's history.
- **UI: Cleaner Panels, Bigger Buttons, Hotkeys: Plan** (https://claude.ai/code/artifact/eed252ba-a59d-483d-b935-dc481923b526), private to Eric's claude.ai account. Built, except two unticked options: folding the
  locked buildings into one "Locked (n)" row (5b, not recommended: the numbers would shift) and a 125% UI scale in windows taller than 1080 px (18).

Smaller loose ends:
- A point of interest's corner picture is chosen at random per site (`Game.poi_scene`); a later pass could pick by the surrounding biome.
- The Giant Frog and the 10 sites (32 x 32) are Scale2x upscales of their 16 x 16 originals in `art/source/` (`tools/upscale_sites.py`): the right size but no new detail. Redraw them by hand, then drop the script.
- The 16 x 16 grounds, ledges, units, camps and buildings were drawn in one pass (rows in `tools/make_tiles16.gd` and `tools/make_buildings.gd`); expect to nudge some (ruins, fused glass, the units) after looking at them in play.
- `Game.view` and `Game.cycle_view()` (the Rust Kings' view, no fog) have no button or key any more; they were a debug tool and only the tests use them.
- The three animated buttons are drawn at 1.2x, which is not a whole number, so some of their pixels are a little wider than others. Whole-number sizes (1x, 2x) are cleaner but 2x does not fit the bar.
