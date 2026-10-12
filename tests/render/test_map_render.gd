extends "res://tests/framework/test_case.gd"
## How the map view redraws. Building the map's draw commands is the expensive part of a frame
## (thousands of glyphs, rects and lines in GDScript), so the map should redraw as little as
## possible: only when something changed, and only what changed.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")

var fx: MapFixture


func before_all() -> void:
	World.new_game(3)


func before_each() -> void:
	Game.view = Data.PLAYER
	fx = add_autofree(MapFixture.new())
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	fx.reset_stats()


func test_nothing_redraws_while_idle() -> void:
	await fx.settle(10)
	assert_eq(fx.map.stats.tile_draws, 0)
	assert_eq(fx.map.stats.overlay_draws, 0)


func test_map_is_blank_before_a_game_starts() -> void:
	Game.in_game = false
	fx.map.redraw_all()
	await fx.settle()
	Game.in_game = true
	assert_eq(fx.map.stats.tiles, 0)


func test_redraw_all_draws_every_tile_on_screen() -> void:
	fx.map.redraw_all()
	await fx.settle()
	assert_gt(fx.map.stats.tile_draws, 0)
	assert_ge(fx.map.stats.tiles, fx.visible_tile_count())


func test_changing_the_map_redraws_it() -> void:
	Game.claim(World.claimable_tile())
	await fx.settle()
	assert_gt(fx.map.stats.tile_draws, 0)


func test_many_changes_in_one_frame_redraw_each_chunk_once() -> void:
	Game.res.wood += 50
	Game.claim(World.claimable_tile())
	for i in 5:
		Game.changed.emit()
	await fx.settle()
	assert_between_chunks(1, 4)


func test_switching_whose_map_you_see_redraws_it() -> void:
	Game.cycle_view()
	await fx.settle()
	assert_gt(fx.map.stats.tile_draws, 0)
	Game.view = Data.PLAYER


func test_clicking_a_tile_selects_it() -> void:
	var c := Game.home(Data.PLAYER) + Vector2i(2, 0)
	fx.click(c)
	await fx.settle()
	assert_eq(Game.selected, c)
	assert_has(Game.preview, "foot", "clicking shows travel routes from your HQ")


func test_hovering_redraws_only_the_overlay() -> void:
	var hq := Game.home(Data.PLAYER)
	for i in 5:
		fx.hover(hq + Vector2i(i, 1))
		await fx.settle(1)
	await fx.settle()
	assert_eq(fx.map.stats.tile_draws, 0, "moving the mouse must not rebuild the tiles")
	assert_ge(fx.map.stats.overlay_draws, 1)


func test_hovering_the_same_tile_again_draws_nothing() -> void:
	var c := Game.home(Data.PLAYER) + Vector2i(1, 1)
	fx.hover(c)
	await fx.settle()
	fx.reset_stats()
	fx.hover(c)
	await fx.settle()
	assert_eq(fx.map.stats.overlay_draws, 0)
	assert_eq(fx.map.stats.tile_draws, 0)


func test_selecting_a_tile_redraws_the_overlay() -> void:
	fx.click(Game.home(Data.PLAYER) + Vector2i(6, 2))
	await fx.settle()
	assert_ge(fx.map.stats.overlay_draws, 1)


func test_panning_over_drawn_map_redraws_nothing() -> void:
	await _tour()   # the first pass may draw parts of the map it hadn't drawn yet
	fx.reset_stats()
	await _tour()
	assert_eq(fx.map.stats.tile_draws, 0, "panning must reuse what was already drawn")


func test_zooming_redraws_nothing() -> void:
	for zoom in [0.25, 0.5, 2.0, 1.0]:
		fx.camera.zoom = Vector2(zoom, zoom)
		await fx.settle(1)
	fx.reset_stats()
	for zoom in [0.25, 0.5, 2.0, 1.0]:
		fx.camera.zoom = Vector2(zoom, zoom)
		await fx.settle(1)
	assert_eq(fx.map.stats.tile_draws, 0)


func test_changes_off_screen_are_drawn_when_scrolled_into_view() -> void:
	fx.map.redraw_all()
	await fx.settle()
	assert_lt(fx.map.stats.tiles, Game.w * Game.h, "only what's on screen redraws right away")
	fx.reset_stats()
	await fx.view_cell(Game.home(Data.AI), 1.0)
	assert_gt(fx.map.stats.tile_draws, 0, "the stale far side redraws once it comes into view")
	fx.reset_stats()
	await fx.view_cell(Game.home(Data.AI) + Vector2i(1, 0), 1.0)
	assert_eq(fx.map.stats.tile_draws, 0, "...and only once")


func test_tile_layer_hides_when_no_game_is_running() -> void:
	Game.in_game = false
	await fx.settle()
	var shown := _tiles_visible()
	Game.in_game = true
	await fx.settle()
	assert_false(shown, "the main menu shows no map")
	assert_true(_tiles_visible())


func test_selecting_a_tile_redraws_no_tiles() -> void:
	fx.click(Game.home(Data.PLAYER) + Vector2i(5, 1))
	await fx.settle()
	assert_eq(fx.map.stats.tile_draws, 0, "selection only changes the overlay")


func test_actions_that_leave_the_map_alone_redraw_no_tiles() -> void:
	Game.pop += 5
	Game.res.metal += 10
	Game.res.meat += 10
	Game.train_troop()
	await fx.settle()
	assert_eq(fx.map.stats.tile_draws, 0)


func test_claiming_a_tile_redraws_only_the_chunks_around_it() -> void:
	Game.res.wood += 50
	Game.claim(World.claimable_tile())
	await fx.settle()
	assert_between_chunks(1, 4)


func test_a_moving_unit_redraws_only_the_chunks_around_it() -> void:
	var start := Game.home(Data.PLAYER) + Vector2i(4, 3)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", start, start)
	Units.units.append(u)
	Game.changed.emit()
	await fx.settle()
	fx.reset_stats()
	u.pos += Vector2i(1, 0)
	Game.changed.emit()
	await fx.settle()
	Units.units.erase(u)
	Game.changed.emit()
	assert_between_chunks(1, 4)


func test_a_new_map_redraws_everything_on_screen() -> void:
	World.new_game(4)
	await fx.settle()
	var tiles: int = fx.map.stats.tiles
	World.new_game(3)
	await fx.settle()
	assert_ge(tiles, fx.visible_tile_count())


func assert_between_chunks(low: int, high: int) -> void:
	assert_ge(fx.map.stats.tile_draws, low, "the change must show")
	assert_le(fx.map.stats.tile_draws, high, "only chunks near the change should redraw")


## Pans the camera across the map and back at zoom 1, one screen-third per frame.
func _tour() -> void:
	var start := fx.camera.position
	for step in [Vector2(540, 0), Vector2(540, 0), Vector2(0, 300), Vector2(-540, 0), Vector2(-540, -300)]:
		fx.camera.position += step
		await fx.settle(1)
	fx.camera.position = start
	await fx.settle(1)


## Whether anything in the map's tile layer is visible.
func _tiles_visible() -> bool:
	return fx.map.tile_layer.is_visible_in_tree()
