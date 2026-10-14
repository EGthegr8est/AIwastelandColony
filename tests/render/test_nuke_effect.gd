extends "res://tests/framework/test_case.gd"
## A nuke going off, on the map: the explosion is added light over the units and the night, it lasts its time and is gone, a bomber's plays in the season replay on its
## day, the ground it hit is drawn as ash that keeps its speckles at night, and the red square shows while the strike button is hovered. The pixels need a GPU.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")
const Daylight = preload("res://scripts/daylight.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var fx: MapFixture
var map: Node2D
var centre: Vector2i


func before_each() -> void:
	World.new_game(3)
	Sprites.choose(Sprites.CLEAN)
	Daylight.enabled = true
	SeasonReplay.mode = "off"
	Game.view = Data.NONE
	Game.season = 1
	Units.units = []
	Units.animals = []
	Units.tribes = []
	centre = World.find_tile(func(c, t): return c.x > 8 and c.y > 8 and c.x < Game.w - 8 and c.y < Game.h - 8 and _open(c))
	assert_ne(centre, Vector2i(-1, -1))
	fx = add_autofree(MapFixture.new(Vector2i(960, 540)))
	await fx.view_cell(centre, 3.0)
	map = fx.map
	map.set_process(false)
	map._tick_light(0.0)


func after_each() -> void:
	Daylight.enabled = false
	Sprites.choose(1)
	Game.view = Data.PLAYER
	Game.season = 1
	Game.set_strike_preview(Vector2i(-1, -1))


func _open(c: Vector2i) -> bool:
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var p := c + Vector2i(dx, dy)
			if not Game.tile(p)["t"] in ["sand", "dunes", "scrub"] or Game.tile(p)["b"] != "":
				return false
	return true


func _night() -> void:
	Game.season = 2
	map._tick_light(0.0)
	map._sync_night_layers()


# ---------------------------------------------------------------- the effect

func test_the_explosion_is_added_light_above_the_units_and_the_night() -> void:
	assert_eq(map.blast_layer.material.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	assert_gt(map.blast_layer.get_index(), map.unit_layer.get_index())
	assert_gt(map.blast_layer.get_index(), map.night_layer.get_index(), "so the night does not dim it")
	assert_gt(map.blast_layer.get_index(), map.halo_layer.get_index())
	assert_lt(map.blast_layer.get_index(), map.overlay_layer.get_index())


func test_a_live_blast_plays_for_its_time_and_is_then_gone() -> void:
	Game.blasted.emit(centre)
	assert_eq(map.live_blasts.size(), 1)
	var now: Array = map.blasts_now()
	assert_eq(now.size(), 1)
	assert_eq(now[0][0], centre)
	assert_lt(now[0][1], 0.2, "just begun")
	map.live_blasts[0].born -= SeasonReplay.BLAST_SECONDS * 0.5
	assert_almost_eq(map.blasts_now()[0][1], 0.5, 0.1, "half way")
	map.live_blasts[0].born -= SeasonReplay.BLAST_SECONDS
	assert_true(map.blasts_now().is_empty())
	assert_true(map.live_blasts.is_empty(), "and forgotten")


func test_each_explosion_sounds_its_boom_once() -> void:
	var before := Music.booms
	Game.blasted.emit(centre)
	map._tick_blasts()
	map._tick_blasts()
	assert_eq(Music.booms, before + 1, "once, not once a frame")
	Game.blasted.emit(centre + Vector2i(5, 0))
	map._tick_blasts()
	assert_eq(Music.booms, before + 2, "and once for each")
	map.live_blasts.clear()
	map._tick_blasts()   # all over
	Game.blasted.emit(centre)
	map._tick_blasts()
	assert_eq(Music.booms, before + 3, "a later one sounds again")


func test_a_bombers_blast_plays_in_the_season_replay_on_its_day() -> void:
	map.playing = true
	map.replay = {"actors": [], "events": [{"kind": "blast", "cell": centre, "day": 10.0}]}
	map.replay_secs = 3.0
	map.clock = 10.0 * 3.0 / Data.SEASON_DAYS - 0.5
	assert_true(map.blasts_now().is_empty(), "not yet")
	map.clock = 10.0 * 3.0 / Data.SEASON_DAYS + 1.4
	var now: Array = map.blasts_now()
	assert_eq(now.size(), 1)
	assert_almost_eq(now[0][1], 0.5, 0.01)
	map.clock = 10.0 * 3.0 / Data.SEASON_DAYS + 2.9
	assert_true(map.blasts_now().is_empty(), "over after its 2.8 seconds")
	map.playing = false


func test_a_blast_lasts_longer_than_a_flash_and_the_replay_waits_for_it() -> void:
	assert_eq(SeasonReplay.pop_seconds("blast"), SeasonReplay.BLAST_SECONDS)
	assert_eq(SeasonReplay.pop_seconds("clash"), SeasonReplay.POP_SECONDS)
	assert_gt(SeasonReplay.BLAST_SECONDS, SeasonReplay.POP_SECONDS)
	var r := {"end_day": 20.0, "events": [{"kind": "blast", "cell": centre, "day": 20.0}]}
	assert_almost_eq(SeasonReplay.length(r, 4.0), 2.0 + SeasonReplay.BLAST_SECONDS, 0.0001)
	var flash := {"end_day": 20.0, "events": [{"kind": "clash", "cell": centre, "day": 20.0}]}
	assert_almost_eq(SeasonReplay.length(flash, 4.0), 2.0 + SeasonReplay.POP_SECONDS, 0.0001, "unchanged for the others")


# ---------------------------------------------------------------- the ground

func test_the_hit_ground_is_drawn_as_scorched_ash() -> void:
	Game.detonate(centre, "bomber")
	map._build_ground()
	assert_eq(map.ground_sprite[Game.idx(centre)], "scorched_ash")
	assert_true(Sprites.rects().has("scorched_ash"))
	assert_eq(Sprites.TERRAIN["ash"], "scorched_ash")
	assert_ne(map.ground_sprite[Game.idx(centre + Vector2i(4, 0))], "scorched_ash")


func test_the_ash_keeps_its_speckles_at_night_like_waste_and_glass() -> void:
	Game.detonate(centre, "bomber")
	_night()
	map._build_glows()
	assert_true(map._glow_ground.any(func(g): return g[0] == centre and g[1] == ""), "no halo, but it stays lit")
	assert_true(map.glow_cells.any(func(g): return g[0] == centre))


func test_the_red_square_goes_with_the_hover() -> void:
	await fx.settle()
	var before: int = map.stats.overlay_draws
	Game.set_strike_preview(centre)
	await fx.settle()
	assert_gt(map.stats.overlay_draws, before, "the overlay redraws to outline the square")
	assert_eq(Game.strike_preview, centre)
	before = map.stats.overlay_draws
	Game.set_strike_preview(Vector2i(-1, -1))
	await fx.settle()
	assert_gt(map.stats.overlay_draws, before)


# ---------------------------------------------------------------- the pixels

func _shine_at(point: Vector2) -> float:
	var img: Image = await fx.capture()
	return img.get_pixel(int(point.x), int(point.y)).get_luminance()


func _blast_now(t: float) -> void:
	Game.blasted.emit(centre)
	map.live_blasts[0].born = Time.get_ticks_msec() / 1000.0 - SeasonReplay.BLAST_SECONDS * t


func test_the_explosion_glows_by_day() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return
	var at := fx.screen_pos(centre)
	var before: float = await _shine_at(at + Vector2(40, 30))
	_blast_now(0.12)
	map.blast_layer.queue_redraw()
	map.unit_layer.queue_redraw()
	await fx.settle(1)
	var shine: float = await _shine_at(at)
	assert_gt(shine, 0.85, "a white-hot centre")
	assert_gt(shine, before + 0.2)


func test_the_explosion_glows_by_night_as_brightly() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return
	_night()
	await fx.settle(3)
	var at := fx.screen_pos(centre)
	var dark: float = await _shine_at(at + Vector2(40, 30))
	assert_lt(dark, 0.4, "the night ground is dark")
	_blast_now(0.12)
	map.blast_layer.queue_redraw()
	map.unit_layer.queue_redraw()
	await fx.settle(1)
	var shine: float = await _shine_at(at)
	assert_gt(shine, 0.85, "as bright as by day: it is drawn over the night")
	var near: float = await _shine_at(at + Vector2(40, 30))
	assert_gt(near, dark + 0.15, "and it lights the ground round it")
