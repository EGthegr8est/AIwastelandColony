extends "res://tests/framework/test_case.gd"
## Units are drawn by a layer of their own above the cached map chunks, so a unit that moves (or a camp fire that flickers)
## costs a few sprites a frame and no tile redraws; who is shown, hidden or dimmed follows what the viewer can see.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")
const MapView = preload("res://scripts/map_view.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")
const Sprites = preload("res://scripts/sprites.gd")

var fx: MapFixture
var hq: Vector2i


func before_all() -> void:
	World.new_game(3)


func before_each() -> void:
	Game.view = Data.PLAYER
	Units.units = []
	Units.tribes = []
	hq = Game.home(Data.PLAYER)
	Game.update_fog()   # the world is built once for the file, and a test that hid tiles from you must not leave them hidden
	fx = add_autofree(MapFixture.new())
	await fx.view_cell(hq, 1.0)
	fx.reset_stats()


func after_each() -> void:
	SeasonReplay.mode = "off"
	Units.units = []
	Units.tribes = []
	Game.view = Data.PLAYER


func _party(at: Vector2i, job := "scav", owner := Data.PLAYER) -> Dictionary:
	var u: Dictionary = Units._make_unit(job, owner, "foot", at, at)
	Units.units.append(u)
	return u


func test_the_unit_layer_sits_above_the_tiles_and_below_the_selection_boxes() -> void:
	var order := fx.map.get_children()
	assert_lt(order.find(fx.map.tile_layer), order.find(fx.map.unit_layer))
	assert_lt(order.find(fx.map.unit_layer), order.find(fx.map.overlay_layer))


func test_a_unit_that_moves_redraws_no_tiles_only_the_unit_layer() -> void:
	var u := _party(hq + Vector2i(1, 0))
	Game.changed.emit()
	await fx.settle()
	fx.reset_stats()
	u.pos = hq + Vector2i(2, 0)   # still inside the HQ's own sight, so nothing about what is seen changes
	Game.changed.emit()
	await fx.settle()
	assert_eq(fx.map.stats.tile_draws, 0, "the cached chunks are left alone")
	assert_gt(fx.map.stats.unit_draws, 0, "the unit layer moved the unit")


func test_the_chunks_do_not_draw_units() -> void:
	var u := _party(hq + Vector2i(1, 0))
	assert_false(fx.map._overlay().has(u.pos), "only camps are part of what the chunks draw")


func test_the_unit_layer_uses_the_same_pixel_filter_as_the_tiles() -> void:
	Sprites.choose(Sprites.CLEAN)
	Game.changed.emit()
	await fx.settle()
	assert_eq(fx.map.unit_layer.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	Sprites.choose(0)
	Game.changed.emit()
	await fx.settle()
	assert_eq(fx.map.unit_layer.texture_filter, fx.map.tile_layer.texture_filter)
	Sprites.choose(1)


func test_your_party_in_sight_is_shown_and_out_of_sight_it_is_dimmed() -> void:
	var u := _party(hq + Vector2i(1, 0))
	var i := Game.idx(u.pos)
	assert_eq(fx.map.unit_shown(u), MapView.Shown.SHOWN, "in your sight")
	Game.sight[Data.PLAYER][i] = 0
	assert_eq(fx.map.unit_shown(u), MapView.Shown.DIM, "yours, but out of sight")
	Game.memory[Data.PLAYER][i] = null
	assert_eq(fx.map.unit_shown(u), MapView.Shown.HIDDEN, "on ground you have never explored")


func test_a_raider_band_shows_only_while_you_can_see_it() -> void:
	var band := _party(hq + Vector2i(1, 0), "band", Data.NONE)
	var i := Game.idx(band.pos)
	assert_eq(fx.map.unit_shown(band), MapView.Shown.SHOWN)
	Game.sight[Data.PLAYER][i] = 0
	assert_eq(fx.map.unit_shown(band), MapView.Shown.HIDDEN, "known ground, but out of sight: you don't know where the band is")


func test_with_no_fog_everything_shows() -> void:
	var band := _party(hq + Vector2i(1, 0), "band", Data.NONE)
	Game.view = Data.NONE
	Game.sight[Data.PLAYER][Game.idx(band.pos)] = 0
	assert_eq(fx.map.unit_shown(band), MapView.Shown.SHOWN)


func test_camp_fires_and_parked_parties_keep_the_layer_alive_unless_the_animation_is_off() -> void:
	Units.tribes.append({"id": 3, "class": "raider", "name": "camp", "pos": hq + Vector2i(4, 0), "strength": 3, "relations": 0, "found": true})
	fx.reset_stats()
	SeasonReplay.mode = "off"
	fx.map._tick_replay(0.5)
	await fx.settle()
	assert_eq(fx.map.stats.unit_draws, 0, "off means a calm map")
	SeasonReplay.mode = "normal"
	fx.map._tick_replay(0.5)
	await fx.settle()
	assert_gt(fx.map.stats.unit_draws, 0, "the fire flickers")


func test_with_no_camps_and_nobody_parked_nothing_is_redrawn_while_idle() -> void:
	SeasonReplay.mode = "normal"
	_party(hq + Vector2i(1, 0))   # on its way somewhere, not parked
	fx.reset_stats()
	fx.map._tick_replay(0.5)
	await fx.settle()
	assert_eq(fx.map.stats.unit_draws, 0)


func test_a_parked_scouting_party_keeps_the_layer_alive() -> void:
	SeasonReplay.mode = "normal"
	var u := _party(hq + Vector2i(1, 0), "scout")
	u.stage = "station"
	fx.reset_stats()
	fx.map._tick_replay(0.5)
	await fx.settle()
	assert_gt(fx.map.stats.unit_draws, 0)
