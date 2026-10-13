extends "res://tests/framework/test_case.gd"
## The map drawn with the pixel-art sprites (art/atlas.png) in place of the text glyphs: which sprite
## goes where, that changing the art redraws the map (and nothing else does), and, with a GPU, that the
## pixels on screen really are the atlas art at exactly twice its size.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")

var fx: MapFixture


func before_all() -> void:
	World.new_game(3)


func before_each() -> void:
	Sprites.choose(1)
	Game.view = Data.PLAYER
	Game.show_radiation = false
	Units.units = []
	Units.tribes = []   # the generated map may have camps standing about
	fx = add_autofree(MapFixture.new())
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	fx.reset_stats()


func after_each() -> void:
	Sprites.choose(1)
	Game.show_radiation = false
	Game.view = Data.PLAYER
	Units.units = []
	Units.tribes = []


func _needs_gpu() -> bool:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return true
	return false


# ---------------------------------------------------------------- what goes where

func test_every_tile_knows_its_ground_sprite_and_slope_sprite() -> void:
	fx.map._build_ground()
	for i in Game.tiles.size():
		var ford: bool = Game.tiles[i]["t"] == "water" and Game.tiles[i].get("f", false)
		assert_eq(fx.map.ground_sprite[i], Sprites.FORD if ford else Sprites.TERRAIN[Game.tiles[i]["t"]])
		var slope: String = Game.slopes[i]
		assert_eq(fx.map.ground_slope[i], Sprites.SLOPES[slope] if slope != "" else "")


func test_water_has_no_slope_sprite() -> void:
	fx.map._build_ground()
	for i in Game.tiles.size():
		if Game.tiles[i]["t"] == "water":
			assert_eq(fx.map.ground_slope[i], "", "rivers are fords, not slopes")


func test_units_and_camps_carry_their_sprite() -> void:
	Game.view = Data.NONE   # no fog, so even a raider band outside your sight is shown
	var hq := Game.home(Data.PLAYER)
	var kinds := {"scav": ["foot", "scavenger"], "scout": ["foot", "scout"], "caravan": ["horse", "caravan"],
		"band": ["foot", "raider_band"]}
	var at := hq + Vector2i(3, -3)
	for job in kinds:
		var u: Dictionary = Units._make_unit(job, Data.NONE if job == "band" else Data.PLAYER, kinds[job][0], at, at)
		Units.units.append(u)
		at += Vector2i(1, 0)
	var car: Dictionary = Units._make_unit("scav", Data.PLAYER, "car", at, at)
	Units.units.append(car)
	at += Vector2i(1, 0)
	var plane: Dictionary = Units._make_unit("plane", Data.PLAYER, "plane", at, at)
	Units.units.append(plane)
	# Units are drawn by the unit layer, not baked into the chunks: they carry their sprite through glyph_kind()
	var sprite := func(u: Dictionary) -> String: return Sprites.UNITS[Units.glyph_kind(u)]
	assert_eq(sprite.call(Units.units_at(hq + Vector2i(3, -3))[0]), "scavenger")
	assert_eq(sprite.call(Units.units_at(hq + Vector2i(4, -3))[0]), "scout")
	assert_eq(sprite.call(Units.units_at(hq + Vector2i(5, -3))[0]), "caravan")
	assert_eq(sprite.call(Units.units_at(hq + Vector2i(6, -3))[0]), "raider_band")
	assert_eq(sprite.call(car), "war_rig")
	assert_eq(sprite.call(plane), "recon_plane")
	var out: Dictionary = fx.map._overlay()
	assert_false(out.has(car.pos), "a unit is not part of what the chunks draw")
	for cls in Data.TRIBE_CLASSES:
		var pos := hq + Vector2i(3, 5 + Data.TRIBE_CLASSES.keys().find(cls))
		Units.tribes.append({"id": 900, "class": cls, "name": cls, "pos": pos, "strength": 5, "relations": 0, "found": true})
	out = fx.map._overlay()
	for cls in Data.TRIBE_CLASSES:
		var pos := hq + Vector2i(3, 5 + Data.TRIBE_CLASSES.keys().find(cls))
		assert_eq(out[pos][2], Sprites.CAMPS[cls])


# ---------------------------------------------------------------- redrawing

func test_choosing_other_art_redraws_every_tile_on_screen() -> void:
	Sprites.choose(2)
	Game.changed.emit()
	await fx.settle()
	assert_gt(fx.map.stats.tile_draws, 0)
	assert_ge(fx.map.stats.tiles, fx.visible_tile_count())


func test_going_back_to_text_glyphs_redraws_every_tile_on_screen() -> void:
	Sprites.choose(0)
	Game.changed.emit()
	await fx.settle()
	assert_ge(fx.map.stats.tiles, fx.visible_tile_count())


func test_a_change_that_leaves_the_art_alone_redraws_no_tiles() -> void:
	Game.changed.emit()
	await fx.settle()
	assert_eq(fx.map.stats.tile_draws, 0)


func test_pixel_art_is_filtered_with_the_nearest_pixel_and_text_is_not() -> void:
	assert_eq(fx.map.tile_layer.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	Sprites.choose(0)
	Game.changed.emit()
	await fx.settle()
	assert_eq(fx.map.tile_layer.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	Sprites.choose(3)
	Game.changed.emit()
	await fx.settle()
	assert_eq(fx.map.tile_layer.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func test_a_cell_is_twice_a_sprite() -> void:
	assert_eq(fx.map.CELL, Vector2(Sprites.SIZE, Sprites.SIZE) * 2.0, "so every art pixel is two screen pixels")


# ---------------------------------------------------------------- real pixels (needs a GPU)

## A tile in the open, with a plain sprite: nothing built or standing on it, no slope over it, and no
## claimed land next to it (territory borders draw 1 pixel lines over the edge of the tiles).
func _open_tile(terrain: String) -> Vector2i:
	return World.find_tile(func(c, t): return t["t"] == terrain and t["b"] == "" and t["o"] == Data.NONE \
		and Game.slopes[Game.idx(c)] == "" and c.x > 2 and c.y > 2 and c.x < Game.w - 3 and c.y < Game.h - 3 \
		and Game.neighbors(c).all(func(n): return Game.tile(n)["o"] == Data.NONE))


## How many opaque pixels of `sprite` (in `style`) aren't on screen at twice the size with their
## top-left at `origin` (to within a couple of shades), in `shot`.
func _wrong_pixels(shot: Image, sprite: String, style: int, origin: Vector2i, shade := Color.WHITE) -> int:
	var art := Sprites.image(sprite, style)
	var wrong := 0
	for sy in 8:
		for sx in 8:
			var want := art.get_pixel(sx, sy)
			if want.a < 1.0:
				continue
			want = Color(want.r * shade.r, want.g * shade.g, want.b * shade.b)
			for dy in 2:
				for dx in 2:
					var got := shot.get_pixel(origin.x + sx * 2 + dx, origin.y + sy * 2 + dy)
					if absf(got.r - want.r) > 0.02 or absf(got.g - want.g) > 0.02 or absf(got.b - want.b) > 0.02:
						wrong += 1
	return wrong


func test_a_ground_tile_on_screen_is_its_sprite_at_exactly_twice_the_size() -> void:
	if _needs_gpu():
		return
	Game.view = Data.NONE   # no fog: nothing dimmed
	for style in [1, 2, 3]:
		Sprites.choose(style)
		Game.changed.emit()   # the map only redraws when told the game changed
		for terrain in ["rock", "water", "ruins", "sand"]:
			var c := _open_tile(terrain)
			assert_ne(c, Vector2i(-1, -1), "this map needs some %s" % terrain)
			await fx.view_cell(c, 1.0)
			var shot: Image = await fx.capture()
			var origin := Vector2i(fx.screen_pos(c) - Vector2(8, 8))
			assert_eq(_wrong_pixels(shot, Sprites.TERRAIN[terrain], style, origin), 0, "%s, style %d" % [terrain, style])


func test_a_unit_on_screen_is_its_sprite() -> void:
	if _needs_gpu():
		return
	Game.view = Data.NONE
	var c := _open_tile("sand")
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "car", c, c)
	Units.units.append(u)
	Game.changed.emit()   # the map only redraws when told the game changed
	await fx.view_cell(c, 1.0)
	var shot: Image = await fx.capture()
	var origin := Vector2i(fx.screen_pos(c) - Vector2(8, 8))
	assert_eq(_wrong_pixels(shot, "war_rig", 1, origin), 0)
	Units.units.erase(u)


func test_remembered_ground_is_dimmed() -> void:
	if _needs_gpu():
		return
	# a tile your colony explored but can't see now: remembered, out of sight, on open ground
	Game.view = Data.PLAYER
	Game.reveal(Data.PLAYER, Game.home(Data.AI), 9)
	Game.update_fog()
	var c := World.find_tile(func(cell, t): return t["t"] == "sand" and t["b"] == "" and Game.slopes[Game.idx(cell)] == "" \
		and Game.memory[Data.PLAYER][Game.idx(cell)] != null and not Game.in_sight(Data.PLAYER, cell) \
		and Game.tile(cell)["o"] == Data.NONE and Game.neighbors(cell).all(func(n): return Game.tile(n)["o"] == Data.NONE))
	assert_ne(c, Vector2i(-1, -1), "needs remembered open ground")
	Game.changed.emit()
	await fx.view_cell(c, 1.0)
	var shot: Image = await fx.capture()
	var origin := Vector2i(fx.screen_pos(c) - Vector2(8, 8))
	assert_eq(_wrong_pixels(shot, "ash_sand", 1, origin, fx.map.SPRITE_DIM), 0)


func test_the_radiation_tint_still_shows_over_the_sprites() -> void:
	if _needs_gpu():
		return
	Game.view = Data.NONE
	Game.changed.emit()
	var c := _open_tile("rock")
	await fx.view_cell(c, 1.0)
	var plain: Image = await fx.capture()
	Game.show_radiation = true
	Game.changed.emit()
	await fx.view_cell(c, 1.0)
	var tinted: Image = await fx.capture()
	# a pixel where the rock sprite is solid: a tint drawn underneath it couldn't show there
	var art := Sprites.image("rock", 1)
	var solid := Vector2i(-1, -1)
	for sy in 8:
		for sx in 8:
			if solid.x < 0 and art.get_pixel(sx, sy).a == 1.0:
				solid = Vector2i(sx, sy)
	assert_ne(solid, Vector2i(-1, -1))
	var at := Vector2i(fx.screen_pos(c) - Vector2(8, 8)) + solid * 2
	assert_ne(tinted.get_pixel(at.x, at.y), plain.get_pixel(at.x, at.y), "the tint must be drawn on top of the sprite")
	Game.show_radiation = false
