extends "res://tests/framework/test_case.gd"
## Day and night on the map: the light follows the season and fades (never snaps) at the turn change, the ground goes dark and
## what should glow keeps its light, and the things on the ground are treated as agreed:
##   - craters, ruins that raiders hold, and the camps your units can see glow (so do fallout waste and fused glass, without a halo);
##   - your own parties keep their colours and carry a small glow;
##   - wild animals and enemy parties never glow and go dark with the ground, except an enemy party standing in ruins, which are lit.
## The rules are in tests/unit/test_daylight.gd. Most checks here are on what the map works out, so they run without a GPU.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")
const MapView = preload("res://scripts/map_view.gd")
const Daylight = preload("res://scripts/daylight.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var fx: MapFixture
var map: Node2D


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
	fx = add_autofree(MapFixture.new())
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	map = fx.map
	map.set_process(false)   # the tests step the light themselves
	map._tick_light(0.0)


func after_each() -> void:
	Daylight.enabled = false
	Sprites.choose(1)
	Game.view = Data.PLAYER
	Game.season = 1


func _night() -> void:
	Game.season = 2
	map._tick_light(0.0)   # no fade running, so it goes straight to night


func _find(terrain: String) -> Vector2i:
	return World.find_tile(func(c, t): return t["t"] == terrain and t["b"] == "" and c.x > 4 and c.y > 4 and c.x < Game.w - 5 and c.y < Game.h - 5)


func _glows(kind: String) -> Array:
	return map.glow_cells.filter(func(g): return g[1] == kind)


func _has_glow(c: Vector2i, kind: String) -> bool:
	return map.glow_cells.any(func(g): return g[0] == c and g[1] == kind)


# ---------------------------------------------------------------- the light

func test_by_day_the_night_layers_are_hidden_and_the_light_is_full() -> void:
	assert_eq(map.light, 1.0)
	assert_false(map.night_layer.visible)
	assert_false(map.glow_layer.visible)
	assert_false(map.halo_layer.visible)


func test_a_night_season_darkens_the_map_and_shows_the_layers() -> void:
	_night()
	map._sync_night_layers()
	assert_eq(map.light, 0.0)
	assert_true(map.night_layer.visible)
	assert_true(map.halo_layer.visible)
	assert_true(map.glow_layer.visible, "the clean look redraws what glows")
	assert_eq(map.night_layer.self_modulate, Daylight.ground(0.0))


func test_the_night_layer_multiplies_into_what_is_under_it() -> void:
	var material: CanvasItemMaterial = map.night_layer.material
	assert_eq(material.blend_mode, CanvasItemMaterial.BLEND_MODE_MUL)


func test_the_halos_are_smooth_filtered_while_the_map_is_pixel_art() -> void:
	assert_eq(map.halo_layer.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR)


func test_the_text_glyphs_get_the_dark_and_the_halos_but_do_not_redraw_tiles() -> void:
	Sprites.choose(0)
	_night()
	map._sync_night_layers()
	assert_true(map.night_layer.visible)
	assert_true(map.halo_layer.visible)
	assert_false(map.glow_layer.visible, "only the pixel art has pictures that cover a whole tile")
	assert_eq(map.glow_batch.sprite_pos.size(), 0)


func test_the_turn_change_fades_over_the_fade_time_and_never_snaps() -> void:
	Game.season = 2
	Game.season_played.emit({})   # END SEASON has just been played
	var seconds := Daylight.fade_seconds()
	var seen := [map.light]
	for i in 12:
		map._tick_light(seconds / 12.0)
		seen.append(map.light)
	assert_eq(seen[0], 1.0, "it starts at the old light")
	assert_eq(seen[seen.size() - 1], 0.0, "and ends at the new one")
	for i in range(1, seen.size()):
		assert_le(seen[i], seen[i - 1], "it only ever gets darker")
		assert_lt(seen[i - 1] - seen[i], 0.5, "in small steps: no snap")
	assert_gt(seen[1], 0.9, "it starts gently")
	var middle: float = seen[6]
	assert_gt(middle, 0.2)
	assert_lt(middle, 0.8)


func test_morning_fades_back_the_same_way() -> void:
	_night()
	Game.season = 3
	Game.season_played.emit({})
	map._tick_light(Daylight.fade_seconds() / 2.0)
	assert_gt(map.light, 0.0)
	assert_lt(map.light, 1.0)
	map._tick_light(Daylight.fade_seconds())
	assert_eq(map.light, 1.0)
	map._sync_night_layers()
	assert_false(map.night_layer.visible, "the layers go away again by day")


func test_skipping_the_walk_does_not_cut_the_fade_short() -> void:
	Game.season = 2
	Game.season_played.emit({})
	map._tick_light(0.2)
	Game.skip_replay()
	map._tick_light(0.2)
	assert_gt(map.light, 0.0, "still fading")
	assert_gt(map._fade_clock, 0.0)


func test_a_new_game_or_a_loaded_one_goes_straight_to_its_light_with_no_fade() -> void:
	Game.season = 4   # nobody played the season: a load
	map._tick_light(0.016)
	assert_eq(map.light, 0.0)
	assert_lt(map._fade_clock, 0.0)


func test_the_switch_off_brings_the_day_back_at_once() -> void:
	_night()
	Daylight.enabled = false
	map._tick_light(0.016)
	assert_eq(map.light, 1.0)
	map._sync_night_layers()
	assert_false(map.night_layer.visible)


func test_a_season_that_leaves_the_light_alone_starts_no_fade() -> void:
	Daylight.enabled = false
	Game.season = 2
	Game.season_played.emit({})
	assert_lt(map._fade_clock, 0.0)


# ---------------------------------------------------------------- what glows

func test_craters_glow_with_a_halo_and_waste_and_glass_keep_their_speckles_without_one() -> void:
	_night()
	var crater := _find("crater")
	assert_true(_has_glow(crater, "crater"))
	var waste := _find("waste")
	assert_true(_has_glow(waste, ""), "waste")
	var glass := _find("glass")
	assert_true(_has_glow(glass, ""), "glass")
	assert_false(_has_glow(_find("sand"), ""), "plain ground does not glow")
	assert_false(_has_glow(_find("rock"), "crater"))


func test_a_glowing_tile_is_drawn_again_over_the_night_at_full_brightness() -> void:
	_night()
	var crater := _find("crater")
	var pos := Vector2(crater) * MapView.CELL
	assert_true(map.glow_batch.sprite_pos.has(pos), "its picture is in the glow layer's batch")
	var src: Rect2 = map.glow_batch.sprite_src[map.glow_batch.sprite_pos.find(pos)]
	assert_eq(src, Sprites.rects()["crater"])
	assert_eq(map.glow_batch.sprite_tint[map.glow_batch.sprite_pos.find(pos)], Color.WHITE)


func test_only_ruins_raiders_hold_and_you_know_about_glow() -> void:
	var ruin := _find("ruins")
	Game.tile(ruin)["r"] = "rogue"
	_night()
	assert_false(_has_glow(ruin, "ruins"), "held, but you do not know it yet")
	Game.tile(ruin)["r"] = "rogue_seen"
	map._build_glows()
	assert_true(_has_glow(ruin, "ruins"))
	assert_true(map.glow_lit.has(ruin))
	Game.tile(ruin)["r"] = "picked"
	map._build_glows()
	assert_false(_has_glow(ruin, "ruins"), "picked clean and empty")
	var other := World.find_tile(func(c, t): return t["t"] == "ruins" and c != ruin and t["r"] != "rogue_seen")
	assert_false(_has_glow(other, "ruins"), "an ordinary ruin stays dark")


func test_raider_trader_and_builder_camps_glow_in_their_own_colour() -> void:
	var at := Game.home(Data.PLAYER) + Vector2i(6, 3)
	for cls in Data.TRIBE_CLASSES:
		Units.tribes.append({"id": 900 + Units.tribes.size(), "class": cls, "name": cls, "pos": at, "strength": 5, "relations": 0, "found": true})
		at += Vector2i(2, 0)
	_night()
	for tribe in Units.tribes:
		assert_true(_has_glow(tribe.pos, tribe["class"]), tribe["class"])
		assert_eq(Daylight.halo(tribe["class"]).color, Daylight.HALOS[tribe["class"]].color)
	assert_ne(Daylight.halo("raider").color, Daylight.halo("trader").color)


func test_a_camp_glows_while_your_units_can_see_it_but_not_when_you_only_remember_it() -> void:
	Game.view = Data.PLAYER
	var camp := Game.home(Data.PLAYER) + Vector2i(3, 0)
	Units.tribes.append({"id": 901, "class": "raider", "name": "Rust", "pos": camp, "strength": 5, "relations": 0, "found": true})
	Game.sight[Data.PLAYER][Game.idx(camp)] = 1
	Game.memory[Data.PLAYER][Game.idx(camp)] = [Data.NONE, ""]
	_night()
	assert_true(_has_glow(camp, "raider"), "in sight")
	Game.sight[Data.PLAYER][Game.idx(camp)] = 0
	map._build_glows()
	assert_false(_has_glow(camp, "raider"), "remembered, out of sight: night shows you nothing you cannot see")
	assert_false(map.glow_lit.has(camp))


func test_a_camp_you_have_not_found_does_not_glow() -> void:
	var camp := Game.home(Data.PLAYER) + Vector2i(3, 0)
	Units.tribes.append({"id": 901, "class": "trader", "name": "Dust", "pos": camp, "strength": 5, "relations": 0, "found": false})
	_night()
	assert_false(_has_glow(camp, "trader"))


func test_a_remembered_crater_glows_a_little_and_one_you_have_never_seen_not_at_all() -> void:
	Game.view = Data.PLAYER
	var crater := _find("crater")
	Game.memory[Data.PLAYER][Game.idx(crater)] = null
	Game.sight[Data.PLAYER][Game.idx(crater)] = 0
	assert_eq(map._glow_strength(crater), 0.0)
	Game.memory[Data.PLAYER][Game.idx(crater)] = [Data.NONE, ""]
	assert_eq(map._glow_strength(crater), Daylight.REMEMBERED_GLOW)
	Game.sight[Data.PLAYER][Game.idx(crater)] = 1
	assert_eq(map._glow_strength(crater), 1.0)
	Game.view = Data.NONE
	assert_eq(map._glow_strength(crater), 1.0, "with no fog everything is known")


# ---------------------------------------------------------------- what stands on the ground

func test_your_own_parties_keep_their_colours() -> void:
	_night()
	assert_eq(map._night_tint(Data.PLAYER, Vector2i(10, 10)), Color.WHITE)


func test_wild_animals_and_enemy_parties_go_dark_with_the_ground() -> void:
	_night()
	var dim: Color = Daylight.things(0.0)
	assert_eq(map._night_tint(Data.NONE, Vector2i(10, 10)), dim, "a deer, a bear, the frog, a raider band")
	assert_eq(map._night_tint(Data.AI, Vector2i(10, 10)), dim, "a Rust Kings party")
	assert_lt(dim.r, 1.0)


func test_by_day_nothing_is_tinted() -> void:
	assert_eq(map._night_tint(Data.NONE, Vector2i(10, 10)), Color.WHITE)
	assert_eq(map._night_tint(Data.AI, Vector2i(10, 10)), Color.WHITE)


func test_an_enemy_party_standing_in_ruins_lights_them_and_is_lit_by_them() -> void:
	var ruin := _find("ruins")
	var band: Dictionary = Units._make_unit("band", Data.NONE, "foot", ruin, ruin)
	Units.units.append(band)
	_night()
	assert_true(_has_glow(ruin, "ruins"), "the ruins glow round the band")
	assert_eq(map._night_tint(Data.NONE, ruin), Color.WHITE, "so the band is lit")
	assert_ne(map._night_tint(Data.NONE, ruin + Vector2i(1, 0)), Color.WHITE, "but not the ground next to it")


func test_an_enemy_party_in_the_open_does_not_glow() -> void:
	var sand := _find("sand")
	Units.units.append(Units._make_unit("band", Data.NONE, "foot", sand, sand))
	_night()
	assert_false(map.glow_cells.any(func(g): return g[0] == sand))
	assert_ne(map._night_tint(Data.NONE, sand), Color.WHITE)


func test_an_enemy_party_in_ruins_you_cannot_see_does_not_give_the_ruins_away() -> void:
	Game.view = Data.PLAYER
	var ruin := _find("ruins")
	Game.memory[Data.PLAYER][Game.idx(ruin)] = [Data.NONE, ""]
	Game.sight[Data.PLAYER][Game.idx(ruin)] = 0
	Units.units.append(Units._make_unit("band", Data.NONE, "foot", ruin, ruin))
	_night()
	assert_false(_has_glow(ruin, "ruins"))


func test_one_of_your_parties_in_ruins_does_not_make_them_glow() -> void:
	var ruin := _find("ruins")
	Units.units.append(Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin))
	_night()
	assert_false(_has_glow(ruin, "ruins"), "only enemies light ruins; your own party carries its own glow")


func test_a_small_dim_glow_goes_round_each_of_your_own_parties_only() -> void:
	var home := Game.home(Data.PLAYER)
	Units.units.append(Units._make_unit("scav", Data.PLAYER, "foot", home + Vector2i(3, 0), home))
	Units.units.append(Units._make_unit("caravan", Data.PLAYER, "horse", home + Vector2i(5, 0), home))
	Units.units.append(Units._make_unit("band", Data.NONE, "foot", home + Vector2i(7, 0), home))
	Units._add_animal("deer", home + Vector2i(9, 0))
	_night()
	var spots: PackedVector2Array = map._party_spots()
	assert_eq(spots.size(), 2, "the scavengers and the caravan, not the band or the deer")
	assert_true(spots.has((Vector2(home + Vector2i(3, 0)) + Vector2(0.5, 0.5)) * MapView.CELL))


func test_halos_are_only_drawn_in_the_dark_and_never_for_nothing() -> void:
	assert_false(map.is_dark())
	_night()
	assert_true(map.is_dark())
	assert_gt(map.glow_cells.size(), 0)
	assert_not_null(map._halo(), "the soft round light is made")
	assert_eq(map._halo().get_size(), Vector2(128, 128))
	var img: Image = map._halo().get_image()
	assert_gt(img.get_pixel(64, 64).a, 0.95, "bright in the middle")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "clear at the edge")


# ---------------------------------------------------------------- real pixels (needs a GPU)

func _mean_light(img: Image, centre: Vector2) -> float:
	var total := 0.0
	var n := 0
	for y in range(int(centre.y) - 12, int(centre.y) + 12):
		for x in range(int(centre.x) - 12, int(centre.x) + 12):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				total += img.get_pixel(x, y).get_luminance()
				n += 1
	return total / maxf(n, 1)


func test_at_night_the_ground_is_dark_and_a_crater_keeps_its_light() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return
	var crater := _find("crater")
	var sand := Vector2i(-1, -1)
	for dy in range(-9, 10):
		for dx in range(-9, 10):
			var c := crater + Vector2i(dx, dy)
			if sand.x < 0 and Game.in_bounds(c) and Game.tile(c)["t"] == "sand" and Game.tile(c)["b"] == "" and Game.slopes[Game.idx(c)] == "":
				sand = c
	assert_true(Game.in_bounds(sand), "found plain sand near the crater")
	await fx.view_cell(crater, 2.0)
	map.set_process(true)
	await fx.settle(3)
	var day: Image = await fx.capture()
	Game.season = 2
	Game.changed.emit()
	await fx.settle(4)
	var night: Image = await fx.capture()
	assert_ge(_mean_light(night, fx.screen_pos(crater)), _mean_light(day, fx.screen_pos(crater)) * 0.9, "the crater keeps its light")
	assert_lt(_mean_light(night, fx.screen_pos(sand)), _mean_light(day, fx.screen_pos(sand)) * 0.6, "the sand is much darker")
