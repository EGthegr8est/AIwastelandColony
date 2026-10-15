extends "res://tests/framework/test_case.gd"
## The pixel-art look on the map: the ground pictures cover the whole tile and mirror on about half of them,
## height and ownership are faint washes laid over them, a feature (rock, water, ruins...) gets a dark rim where it meets
## plainer ground, and camps and buildings stand over the wash. Also the hover label. Most of this is checked on the data the
## map collects for a tile, so it runs without a GPU; the pixels themselves are in test_snapshots.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")
const MapView = preload("res://scripts/map_view.gd")

var fx: MapFixture
var shown := []   # what the last _draw() left to be written over the tile: [glyph, color], or empty


func before_all() -> void:
	World.new_game(3)


func before_each() -> void:
	Sprites.choose(Sprites.CLEAN)
	Game.view = Data.NONE
	Units.units = []
	Units.tribes = []
	fx = add_autofree(MapFixture.new())
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	fx.map._build_ground()


func after_each() -> void:
	Sprites.choose(Sprites.CLEAN)
	Game.view = Data.PLAYER


## A fresh batch that knows the clean look's atlas rectangles.
func _batch() -> MapView.Batch:
	var b := MapView.Batch.new()
	b.rects = Sprites.rects()
	return b


func _draw(c: Vector2i, owner := Data.NONE, building := "", overlay := {}, mem := [], out_of_sight := false) -> MapView.Batch:
	var b := _batch()
	shown = fx.map._draw_clean(c, c.y * Game.w + c.x, owner, building, out_of_sight, overlay, mem, b)
	return b


func _tile(pred: Callable) -> Vector2i:
	return World.find_tile(func(c, t): return c.x > 3 and c.y > 3 and c.x < Game.w - 4 and c.y < Game.h - 4 and pred.call(c, t))


# ---------------------------------------------------------------- the ground

func test_a_clean_tile_draws_its_ground_picture_over_the_whole_tile() -> void:
	var c := _tile(func(c, t): return t["t"] == "sand" and Game.slopes[c.y * Game.w + c.x] == "")
	var b := _draw(c)
	assert_eq(b.sprite_pos, PackedVector2Array([Vector2(c) * MapView.CELL]))
	assert_eq(b.sprite_src[0], Sprites.rects()["ash_sand"])


func test_a_slope_ledge_goes_over_the_ground_picture() -> void:
	for kind in ["gentle", "steep"]:
		var c := _tile(func(c, t): return Game.slopes[c.y * Game.w + c.x] == kind and t["t"] != "water")
		var b := _draw(c)
		assert_eq(b.sprite_pos.size(), 2, "%s: the ground, then its ledge" % kind)
		assert_eq(b.sprite_src[1], Sprites.rects()[Sprites.SLOPES[kind]], kind)


func test_about_half_the_tiles_are_mirrored() -> void:
	var flipped := 0
	for f in fx.map.ground_flip:
		flipped += f
	var share := flipped / float(fx.map.ground_flip.size())
	assert_gt(share, 0.4)
	assert_lt(share, 0.6)
	var c := _tile(func(c, t): return fx.map.ground_flip[c.y * Game.w + c.x] == 1)
	assert_eq(_draw(c).sprite_flip[0], 1)
	c = _tile(func(c, t): return fx.map.ground_flip[c.y * Game.w + c.x] == 0)
	assert_eq(_draw(c).sprite_flip[0], 0)


func test_height_comes_in_three_steps_and_water_has_none() -> void:
	var low := 0
	var high := 0
	var middle := 0
	for i in Game.tiles.size():
		var shade: Color = fx.map.ground_shade[i]
		if Game.tiles[i]["t"] == "water":
			assert_eq(shade.a, 0.0, "water has no height shade")
		elif shade == MapView.SHADE_LOW:
			low += 1
		elif shade == MapView.SHADE_HIGH:
			high += 1
		else:
			assert_eq(shade.a, 0.0, "a middling tile has no shade")
			middle += 1
	var land := low + high + middle
	for count in [low, high, middle]:
		assert_gt(count / float(land), 0.15, "each step covers a decent share of the land")


func test_an_owned_tile_takes_a_faint_tint_from_its_owner() -> void:
	var c := _tile(func(c, t): return fx.map.ground_shade[c.y * Game.w + c.x].a == 0.0 and t["t"] != "water")
	assert_eq(_draw(c).shade_pos.size(), 0, "a middling unowned tile has no wash at all")
	var b := _draw(c, Data.PLAYER)
	assert_eq(b.shade_pos.size(), 1)
	var tint: Color = b.shade_color[0]
	assert_almost_eq(tint.a, MapView.OWN_TINT, 0.001)
	assert_eq(Color(tint, 1.0), Color(MapView.OWNER_EDGE[Data.PLAYER], 1.0))
	var low := _tile(func(c, t): return fx.map.ground_shade[c.y * Game.w + c.x] == MapView.SHADE_LOW)
	var both := _draw(low, Data.PLAYER).shade_color[0]
	assert_gt(both.a, MapView.OWN_TINT, "a low owned tile has the shade and the tint together")


func test_a_tile_out_of_sight_is_dimmed_and_so_is_its_wash() -> void:
	var c := _tile(func(c, t): return fx.map.ground_shade[c.y * Game.w + c.x] == MapView.SHADE_HIGH)
	var seen := _draw(c)
	var dim := _draw(c, Data.NONE, "", {}, [], true)
	assert_eq(dim.sprite_tint[0], MapView.SPRITE_DIM)
	assert_eq(seen.sprite_tint[0], Color.WHITE)
	assert_lt(dim.shade_color[0].r, seen.shade_color[0].r)


# ---------------------------------------------------------------- what stands on a tile

func test_a_camp_stands_on_a_dark_patch_over_the_wash() -> void:
	var c := _tile(func(c, t): return Game.slopes[c.y * Game.w + c.x] != "" and t["t"] != "water")
	var b := _draw(c, Data.NONE, "", {c: ["^", Color.RED, "raider_camp"]})
	assert_eq(b.patch_pos, PackedVector2Array([Vector2(c) * MapView.CELL]))
	assert_eq(b.top_src[0], Sprites.rects()["raider_camp"])
	assert_eq(b.sprite_pos.size(), 1, "just the ground: no slope ledge under a camp")


func test_a_building_is_drawn_from_the_building_atlas() -> void:
	var c := _tile(func(c, t): return t["t"] == "sand" and t["b"] == "")
	var b := _draw(c, Data.PLAYER, "farm")
	assert_eq(b.bld_pos, PackedVector2Array([Vector2(c) * MapView.CELL]))
	assert_eq(b.bld_src[0], Sprites.building_rect("farm"))
	assert_eq(shown, [], "no letter on top of it")


func test_a_building_with_no_picture_falls_back_to_its_letter() -> void:
	var meta: Dictionary = Sprites._building_meta
	Sprites._building_meta = {"sprites": {}}
	var c := _tile(func(c, t): return t["t"] == "sand" and t["b"] == "")
	var b := _draw(c, Data.PLAYER, "farm")
	Sprites._building_meta = meta
	assert_eq(b.bld_pos.size(), 0)
	assert_eq(shown[0], Data.BUILDINGS["farm"].glyph)


func test_a_site_draws_its_quarter_of_the_big_picture() -> void:
	var c := World.find_tile(func(c, t): return t["b"].begins_with("poi_"))
	assert_true(Game.in_bounds(c), "the map has a site")
	var kind: String = Data.BUILDINGS[Game.tile(c)["b"]].poi
	var b := _draw(c, Game.tile(c)["o"], Game.tile(c)["b"])
	assert_eq(b.poi_pos.size(), 1)
	assert_eq(b.poi_src[0], Sprites.poi_quadrant_rect(kind, Game.poi_quadrant(c)))
	assert_eq(b.sprite_pos.size() >= 1, true, "and the ground under it")


# ---------------------------------------------------------------- roads

func _road_tile() -> Vector2i:
	var c := Vector2i(30, 30)
	for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		Game.tile(c + d)["b"] = ""
	return c


func test_a_road_tile_is_drawn_from_rectangles_with_no_picture_and_no_letter() -> void:
	var c := _road_tile()
	Game.tile(c)["b"] = "road"
	var b := _draw(c, Data.NONE, "road")
	assert_eq(b.road_fill.size(), 1, "just the middle of the strip: nothing beside it")
	assert_eq(b.road_out.size(), 1)
	assert_eq(b.bld_pos.size(), 0, "not from the building atlas")
	assert_eq(shown, [], "and no letter")


func test_a_road_runs_on_to_each_neighbour_that_carries_a_road_a_bridge_or_a_ford() -> void:
	var c := _road_tile()
	Game.tile(c)["b"] = "road"
	Game.tile(c + Vector2i.RIGHT)["b"] = "road"
	Game.tile(c + Vector2i.UP)["b"] = "old_road"
	Game.tile(c + Vector2i.LEFT)["b"] = "bridge"
	assert_eq(_draw(c, Data.NONE, "road").road_fill.size(), 4, "the middle and three arms")
	Game.tile(c + Vector2i.LEFT)["b"] = ""
	Game.tile(c + Vector2i.DOWN)["t"] = "water"
	Game.tile(c + Vector2i.DOWN)["f"] = true
	assert_eq(_draw(c, Data.NONE, "road").road_fill.size(), 4, "a ford beside it takes the road on, in place of the bridge")
	Game.tile(c + Vector2i.DOWN)["t"] = "sand"
	Game.tile(c + Vector2i.DOWN)["f"] = false


func test_a_road_never_spills_out_of_its_tile() -> void:
	var c := _road_tile()
	Game.tile(c)["b"] = "road"
	for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		Game.tile(c + d)["b"] = "road"
	var b := _draw(c, Data.NONE, "road")
	var tile_rect := Rect2(Vector2(c) * MapView.CELL, MapView.CELL)
	for r in b.road_out + b.road_fill:
		assert_true(tile_rect.encloses(r), "%s is inside %s, so chunks never draw over each other's roads" % [r, tile_rect])


func test_the_old_highway_is_grey_and_a_road_is_pale_earth() -> void:
	var c := _road_tile()
	Game.tile(c)["b"] = "road"
	var road := _draw(c, Data.NONE, "road")
	Game.tile(c)["b"] = "old_road"
	var highway := _draw(c, Data.NONE, "old_road")
	assert_eq(road.road_fill_colors[0], MapView.ROAD_FILL)
	assert_eq(highway.road_fill_colors[0], MapView.HIGHWAY_FILL)
	assert_ne(road.road_out_colors[0], highway.road_out_colors[0])


func test_a_road_you_only_remember_is_drawn_darker() -> void:
	var c := _road_tile()
	Game.tile(c)["b"] = "road"
	var seen := _draw(c, Data.NONE, "road")
	var dim := _draw(c, Data.NONE, "road", {}, [], true)
	assert_lt(dim.road_fill_colors[0].get_luminance(), seen.road_fill_colors[0].get_luminance())


func test_a_neighbour_you_have_never_seen_gets_no_arm() -> void:
	var c := _road_tile()
	Game.tile(c)["b"] = "road"
	Game.tile(c + Vector2i.RIGHT)["b"] = "road"
	var mem := []
	mem.resize(Game.tiles.size())
	mem.fill([Data.NONE, ""])
	mem[(c.y) * Game.w + c.x + 1] = null
	assert_eq(_draw(c, Data.NONE, "road", {}, mem).road_fill.size(), 1, "the road beside it is unexplored")


func test_the_legend_pictures_of_a_road_and_the_highway_are_16_by_16() -> void:
	Sprites.choose(Sprites.CLEAN)
	for highway in [false, true]:
		var icon := Sprites.road_icon(highway)
		assert_eq(icon.get_size(), Vector2(16, 16))
	assert_ne(Sprites.road_icon(false).get_image().get_data(), Sprites.road_icon(true).get_image().get_data())
	Sprites.choose(0)
	assert_null(Sprites.road_icon(false), "the text glyphs have none")
	Sprites.choose(Sprites.CLEAN)


# ---------------------------------------------------------------- the rim where a feature meets plainer ground

## Sets two neighbouring tiles' ground for a test and puts them back afterwards.
func _with_ground(c: Vector2i, here: String, east: String, body: Callable) -> void:
	var a: Dictionary = Game.tiles[c.y * Game.w + c.x]
	var b: Dictionary = Game.tiles[c.y * Game.w + c.x + 1]
	var was := [a["t"], b["t"]]
	a["t"] = here
	b["t"] = east
	body.call()
	a["t"] = was[0]
	b["t"] = was[1]


func test_a_feature_gets_a_dark_rim_on_the_side_that_meets_plainer_ground() -> void:
	var c := Vector2i(30, 30)
	var pos := Vector2(c) * MapView.CELL
	_with_ground(c, "rock", "sand", func():
		var b := _draw(c)
		assert_gt(b.edge_rects.size(), 0)
		var right := b.edge_rects.filter(func(r): return r.position.x == pos.x + MapView.CELL.x - MapView.RIM)
		assert_eq(right.size(), 1, "one rim on the right, where the sand is")
		assert_eq(right[0].size.x, MapView.RIM)
		assert_eq(b.edge_colors[0], MapView.RIM_INK))


func test_plain_ground_has_no_rim() -> void:
	var c := Vector2i(30, 30)
	_with_ground(c, "sand", "scrub", func():
		assert_eq(_draw(c).edge_rects.size(), 0)
		assert_eq(_draw(c + Vector2i(1, 0)).edge_rects.size(), 0))


func test_two_features_share_one_rim_drawn_by_the_higher_ranked() -> void:
	var c := Vector2i(30, 30)
	var pos := Vector2(c) * MapView.CELL
	_with_ground(c, "rock", "water", func():
		var rock := _draw(c).edge_rects.filter(func(r): return r.position.x == pos.x + MapView.CELL.x - MapView.RIM)
		var water := _draw(c + Vector2i(1, 0)).edge_rects.filter(func(r): return r.size.x == MapView.RIM and r.position.x == pos.x + MapView.CELL.x)
		assert_eq(rock.size(), 0, "rock leaves it to the water")
		assert_eq(water.size(), 1, "water draws the rim on its left"))


func test_a_rim_never_peeks_at_unexplored_ground() -> void:
	var c := Vector2i(30, 30)
	var j := c.y * Game.w + c.x + 1
	var mem := []
	mem.resize(Game.tiles.size())
	mem.fill([Data.NONE, ""])
	mem[j] = null
	var pos := Vector2(c) * MapView.CELL
	_with_ground(c, "rock", "sand", func():
		var right := _draw(c, Data.NONE, "", {}, mem).edge_rects.filter(func(r): return r.position.x == pos.x + MapView.CELL.x - MapView.RIM)
		assert_eq(right.size(), 0, "the sand beside it was never seen"))


func test_the_rims_of_vertical_sides_stop_short_of_the_corners_a_horizontal_rim_covers() -> void:
	var c := Vector2i(30, 30)
	var j := c.y * Game.w + c.x
	var north: Dictionary = Game.tiles[j - Game.w]
	var was: String = north["t"]
	north["t"] = "sand"
	_with_ground(c, "rock", "sand", func():
		var b := _draw(c)
		var pos := Vector2(c) * MapView.CELL
		var right := b.edge_rects.filter(func(r): return r.position.x == pos.x + MapView.CELL.x - MapView.RIM)
		assert_eq(right[0].position.y, pos.y + MapView.RIM, "it starts below the rim along the top"))
	north["t"] = was


# ---------------------------------------------------------------- one art pixel

func test_what_the_code_draws_is_one_art_pixel_wide() -> void:
	assert_eq(MapView.ART_PIXEL, 1.0, "the pictures are 16 x 16 on a 16 pixel cell")
	assert_eq(MapView.RIM, MapView.ART_PIXEL)
	assert_eq(MapView.HOP, MapView.ART_PIXEL)


# ---------------------------------------------------------------- the text glyphs are left alone

func test_only_the_pixel_art_uses_the_extra_passes() -> void:
	Sprites.choose(0)
	assert_false(Sprites.clean())
	Sprites.choose(Sprites.CLEAN)
	assert_true(Sprites.clean())


# ---------------------------------------------------------------- the hover label

func test_the_label_names_the_ground_and_its_height() -> void:
	var c := _tile(func(c, t): return t["t"] == "dunes" and t["b"] == "")
	assert_eq(fx.map.hover_text(c), "Dunes, %+d m" % Game.tile(c)["z"])


func test_the_label_names_what_stands_there() -> void:
	var c := _tile(func(c, t): return t["t"] == "sand" and t["b"] == "")
	Game.tiles[c.y * Game.w + c.x]["b"] = "farm"
	assert_eq(fx.map.hover_text(c), "Farm on Ash sand, %+d m" % Game.tile(c)["z"])
	Game.tiles[c.y * Game.w + c.x]["b"] = ""


func test_the_label_says_unexplored_for_ground_you_have_never_seen() -> void:
	Game.view = Data.PLAYER
	var far := Game.home(Data.AI)
	assert_false(Game.knows_tile(Data.PLAYER, far))
	assert_eq(fx.map.hover_text(far), "Unexplored")
	assert_eq(fx.map.hover_text(Game.home(Data.PLAYER)).begins_with("Colony HQ on "), true)


func test_there_is_no_label_off_the_map() -> void:
	assert_eq(fx.map.hover_text(Vector2i(-1, -1)), "")
	assert_eq(fx.map.hover_text(Vector2i(Game.w, 0)), "")


func test_the_label_sits_below_and_right_of_the_tile_unless_it_would_leave_the_window() -> void:
	var cell := Vector2(40, 20)
	var size := Vector2(32, 32)
	var box := Vector2(120, 26)
	var view := Vector2(800, 450)
	assert_eq(MapView.label_position(cell, size, box, view), Vector2(78, 56), "the usual place")
	assert_eq(MapView.label_position(Vector2(760, 20), size, box, view), Vector2(634, 56), "too far right: to the left of the tile")
	assert_eq(MapView.label_position(Vector2(40, 430), size, box, view), Vector2(78, 400), "too low: above the tile")
	assert_eq(MapView.label_position(Vector2(2, 2), Vector2(4, 4), Vector2(2000, 26), view), Vector2(0, 10), "never off the top or left edge")


func test_the_label_is_drawn_by_the_hover_and_hidden_over_a_panel() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return
	var c := Game.home(Data.PLAYER) + Vector2i(3, 2)
	fx.hover(c)
	await fx.settle()
	var with_label: Image = await fx.capture()
	# a panel under the mouse: the label goes (the real check is the viewport's own idea of what the mouse is over)
	var panel := Control.new()
	panel.size = Vector2(1600, 900)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	fx.viewport.add_child(panel)
	fx.hover(c)
	await fx.settle()
	assert_true(fx.map.over_panel)
	var without: Image = await fx.capture()
	panel.free()
	fx.hover(c)
	await fx.settle()
	assert_false(fx.map.over_panel, "and it is back once the panel is gone")
	var Snapshots = load("res://tests/helpers/snapshots.gd")
	assert_gt(Snapshots.count_differences(with_label, without), 300, "the label is a box of text, hundreds of pixels")
