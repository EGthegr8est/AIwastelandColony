extends "res://tests/framework/test_case.gd"
## The pixel-art sprites in art/atlas16.png: every legend entry has one, 16 x 16 pixels.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")


func after_each() -> void:
	Sprites.style = Sprites.CLEAN


func test_the_atlas_loads_with_every_sprite() -> void:
	assert_true(Sprites.available())
	assert_eq(Sprites.names().size(), 26, "23 and the ford, the scorched ash and the bomber")


func test_everything_in_the_game_that_the_legend_lists_has_a_sprite() -> void:
	for id in Data.TERRAIN:
		assert_not_null(Sprites.terrain(id), "terrain %s" % id)
	for id in Data.UNITS:
		assert_not_null(Sprites.unit(id), "unit %s" % id)
	for id in Data.TRIBE_CLASSES:
		assert_not_null(Sprites.camp(id), "tribe camp %s" % id)
	for id in ["gentle", "steep"]:
		assert_not_null(Sprites.slope(id), "slope %s" % id)


func test_every_sprite_in_the_atlas_is_used_by_something() -> void:
	var used := {}
	for table in [Sprites.TERRAIN, Sprites.SLOPES, Sprites.UNITS, Sprites.CAMPS, {"ford": Sprites.FORD}]:
		for id in table:
			used[table[id]] = true
	for sprite in Sprites.names():
		assert_true(used.has(sprite), "%s isn't mapped to anything in the game" % sprite)
	for sprite in used:
		assert_has(Sprites.names(), sprite)


func test_sprites_are_16_by_16_pictures_with_something_in_them() -> void:
	for sprite in Sprites.names():
		var img := Sprites.image(sprite)
		assert_eq(img.get_size(), Vector2i(16, 16), sprite)
		var drawn := 0
		for y in 16:
			for x in 16:
				if img.get_pixel(x, y).a > 0.0:
					drawn += 1
		assert_gt(drawn, 6, "%s is blank" % sprite)


func test_every_ground_and_slope_looks_different() -> void:
	var seen := {}
	for sprite in Sprites.TERRAIN.values() + Sprites.SLOPES.values() + [Sprites.FORD]:
		seen[Sprites.image(sprite).get_data()] = true
	assert_eq(seen.size(), Sprites.TERRAIN.size() + Sprites.SLOPES.size() + 1)


func test_every_sprite_lies_inside_the_atlas_picture() -> void:
	var atlas: Image = Sprites._atlas
	for sprite in Sprites.names():
		var o: Dictionary = Sprites._meta.sprites[sprite]
		assert_ge(o.x, 0)
		assert_ge(o.y, 0)
		assert_le(o.x + o.w, atlas.get_width(), sprite)
		assert_le(o.y + o.h, atlas.get_height(), sprite)


func test_the_pictures_are_what_you_get_for_a_ground_or_a_unit() -> void:
	assert_eq(Sprites.terrain("sand").get_image().get_data(), Sprites.image("ash_sand").get_data())
	assert_eq(Sprites.unit("boat").get_image().get_data(), Sprites.image("boat").get_data())


func test_the_scavenger_scout_war_rig_and_troop_have_32_pixel_pictures() -> void:
	for kind in Sprites.UNITS32:
		var r := Sprites.unit32_rect(kind)
		assert_eq(r.size, Vector2(32, 32), kind)
		var img := Sprites.picture(Sprites.UNITS32_PNG).get_image().get_region(Rect2i(r))
		assert_false(img.get_used_rect().size == Vector2i.ZERO, "%s is drawn" % kind)
		assert_eq(Sprites.unit(kind).get_size(), Vector2(32, 32), kind)
	assert_eq(Sprites.unit32_rect("boat"), Rect2(), "the others keep their 16 x 16 picture")


func test_the_art_switches_between_the_pixel_art_and_the_text_glyphs() -> void:
	Sprites.choose(Sprites.CLEAN)
	var seen := []
	for i in 4:
		seen.append(Sprites.state())
		Sprites.cycle()
	assert_eq(seen, [Sprites.CLEAN, 0, Sprites.CLEAN, 0], "the pixel art, the glyphs, and round again")


func test_choosing_is_limited_to_what_exists() -> void:
	Sprites.choose(9)
	assert_eq(Sprites.state(), Sprites.CLEAN, "anything above 0 is the pixel art")
	Sprites.choose(-4)
	assert_eq(Sprites.state(), 0)


func test_with_the_text_glyphs_chosen_there_are_no_pictures_to_draw() -> void:
	Sprites.choose(0)
	assert_null(Sprites.terrain("sand"))
	assert_null(Sprites.unit("scav"))
	assert_true(Sprites.rects().is_empty())


func test_every_sprite_has_a_rectangle_inside_the_atlas() -> void:
	Sprites.choose(Sprites.CLEAN)
	var atlas := Sprites.atlas_texture()
	var rects := Sprites.rects()
	assert_eq(rects.size(), 26)
	for sprite in rects:
		var r: Rect2 = rects[sprite]
		assert_eq(r.size, Vector2(Sprites.SIZE, Sprites.SIZE), sprite)
		assert_true(Rect2(Vector2.ZERO, atlas.get_size()).encloses(r), sprite)
	assert_eq(Sprites.rect("dunes"), rects["dunes"])
	assert_eq(Sprites.rect("no_such_sprite"), Rect2())


func test_the_atlas_texture_is_one_cached_picture() -> void:
	assert_true(Sprites.atlas_texture() == Sprites.atlas_texture())


func test_the_title_screen_and_logo_pictures_load() -> void:
	assert_eq(Sprites.title().get_size(), Vector2(1920, 1080))
	var logo := Sprites.logo()
	assert_true(logo is AtlasTexture)
	assert_eq(logo.get_size(), Sprites.LOGO_CROP.size)
	assert_eq(logo.atlas.get_size(), Vector2(960, 540))
	assert_true(Rect2(Vector2.ZERO, logo.atlas.get_size()).encloses(Sprites.LOGO_CROP), "the crop is inside the picture")


func test_the_logo_crop_has_the_logo_in_it_and_no_frame() -> void:
	var img := Sprites.logo().get_image()
	var bright := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).get_luminance() > 0.12:
				bright += 1
	assert_gt(bright, img.get_width() * img.get_height() / 4, "lots of orange lettering")
	# the frame sits well outside the crop: no lit pixels on its outer edge
	for x in img.get_width():
		assert_lt(img.get_pixel(x, 0).get_luminance(), 0.12)
		assert_lt(img.get_pixel(x, img.get_height() - 1).get_luminance(), 0.12)


func test_the_logos_background_is_nearly_black() -> void:
	var bg := Sprites.logo_background()
	var corner := Sprites.logo().get_image().get_pixel(0, 0)
	assert_eq(bg, Color(corner.r, corner.g, corner.b, 1.0), "it's the picture's own corner")
	assert_eq(bg.a, 1.0)
	assert_lt(bg.get_luminance(), 0.05)


func test_pictures_are_cached_and_missing_ones_are_null() -> void:
	assert_true(Sprites.title() == Sprites.title())
	assert_true(Sprites.logo() == Sprites.logo())
	assert_null(Sprites.picture("res://art/no_such_picture.png"))
	assert_null(Sprites.picture("res://art/no_such_picture.png"), "and asking again is still fine")


func test_unknown_things_have_no_sprite() -> void:
	assert_null(Sprites.texture("no_such_sprite"))
	assert_null(Sprites.terrain("no_such_terrain"))
	assert_null(Sprites.unit("no_such_unit"))


func test_textures_are_cached() -> void:
	assert_true(Sprites.unit("boat") == Sprites.unit("boat"))
	assert_true(Sprites.unit("boat") == Sprites.texture("boat"))


# ---------------------------------------------------------------- the look

func test_the_pixel_art_is_the_one_look_and_the_glyphs_the_other() -> void:
	assert_eq(Sprites.CHOICES, [Sprites.CLEAN, 0])
	assert_eq(Sprites.SIZE, 16)


func test_every_ground_covers_its_whole_tile() -> void:
	var grounds: Dictionary = Sprites.TERRAIN.duplicate()
	grounds["ford"] = Sprites.FORD
	for id in grounds:
		var img := Sprites.image(grounds[id])
		for y in 16:
			for x in 16:
				assert_eq(img.get_pixel(x, y).a, 1.0, "%s pixel %d,%d is see-through" % [id, x, y])


func test_the_grounds_are_told_apart_by_colour() -> void:
	# the whole point: two different grounds never share a tile colour (the most common pixel)
	var common := {}
	var every: Dictionary = Sprites.TERRAIN.duplicate()
	every["ford"] = Sprites.FORD
	for id in every:
		var counts := {}
		var img := Sprites.image(every[id])
		for y in 16:
			for x in 16:
				var c := img.get_pixel(x, y).to_html(false)
				counts[c] = counts.get(c, 0) + 1
		var best := ""
		for c in counts:
			if best == "" or counts[c] > counts[best]:
				best = c
		assert_false(common.has(best), "%s and %s are both mostly %s" % [id, common.get(best, ""), best])
		common[best] = id


func test_only_the_hazards_glow() -> void:
	var glows := ["crater", "glass", "waste", "ruins", "ash"]   # the ash keeps its green-yellow flecks lit
	for id in Sprites.TERRAIN:
		var img := Sprites.image(Sprites.TERRAIN[id])
		var brightest := 0.0
		for y in 16:
			for x in 16:
				brightest = maxf(brightest, img.get_pixel(x, y).v)
		if id in glows:
			assert_gt(brightest, 0.85, "%s should glow" % id)
		else:
			assert_lt(brightest, 0.7, "%s should be matte" % id)


func test_a_clean_slope_is_a_dark_see_through_ledge_along_the_bottom() -> void:
	for id in ["gentle_slope", "steep_incline"]:
		var img := Sprites.image(id)
		for x in 16:
			var c := img.get_pixel(x, 15)
			assert_gt(c.a, 0.0, "%s has a ledge pixel at the bottom" % id)
			assert_lt(c.a, 1.0, "%s is see-through" % id)
			assert_lt(c.v, 0.2, "%s is dark" % id)
		for y in 8:
			for x in 16:
				assert_eq(img.get_pixel(x, y).a, 0.0, "%s leaves the top of the tile alone" % id)
	assert_gt(Sprites.image("steep_incline").get_pixel(0, 15).a, Sprites.image("gentle_slope").get_pixel(0, 15).a,
		"a steep incline is darker than a gentle slope")


func test_the_legend_shows_a_clean_slope_over_sand() -> void:
	Sprites.choose(Sprites.CLEAN)
	var on_sand := Sprites.slope("gentle").get_image()
	assert_eq(on_sand.get_pixel(0, 0), Sprites.image("ash_sand").get_pixel(0, 0), "the ground is the sand picture")
	assert_ne(on_sand.get_pixel(0, 15), Sprites.image("ash_sand").get_pixel(0, 15), "with the ledge laid over it")
	assert_eq(on_sand.get_pixel(0, 15).a, 1.0)


# ---------------------------------------------------------------- building pictures

func test_every_building_you_can_put_up_has_a_picture() -> void:
	for id in Data.BUILDINGS:
		var b: Dictionary = Data.BUILDINGS[id]
		if b.has("poi"):
			assert_eq(Sprites.building_rect(id), Rect2(), "%s is a site: it has its own 16 x 16 picture" % id)
		elif b.get("road", false):
			assert_eq(Sprites.building_rect(id), Rect2(), "%s is drawn from rectangles that join up, not from a picture" % id)
		else:
			assert_ne(Sprites.building_rect(id), Rect2(), "%s has no building picture" % id)


func test_the_building_pictures_lie_inside_their_atlas_and_have_a_dark_outline() -> void:
	var atlas := Sprites.building_atlas_texture()
	assert_not_null(atlas)
	var img := atlas.get_image()
	assert_eq(img.get_height(), 16)
	for id in Sprites.building_ids():
		var r := Sprites.building_rect(id)
		assert_eq(r.size, Vector2(16, 16), id)
		assert_true(Rect2(Vector2.ZERO, atlas.get_size()).encloses(r), id)
		var drawn := 0
		var dark := 0
		for y in 16:
			for x in 16:
				var c := img.get_pixel(int(r.position.x) + x, y)
				if c.a > 0.0:
					drawn += 1
					if c.v < 0.2:
						dark += 1
		assert_gt(drawn, 60, "%s is nearly blank" % id)
		assert_gt(dark, 12, "%s has no dark outline, so it would melt into the ground" % id)


func test_an_unknown_building_has_no_picture() -> void:
	assert_eq(Sprites.building_rect("no_such_building"), Rect2())


# ---------------------------------------------------------------- the animals and the sites

func test_the_frog_is_32_by_32_and_the_deer_and_bears_16_by_16() -> void:
	assert_eq(Sprites.animals_texture().get_size(), Vector2(80, 32))
	assert_eq(Sprites.animal_rect("frog"), Rect2(48, 0, 32, 32))
	for kind in ["deer", "black_bear", "brown_bear"]:
		assert_eq(Sprites.animal_rect(kind).size, Vector2(16, 16), kind)
	var img := Sprites.animals_texture().get_image()
	var drawn := 0
	for y in 32:
		for x in range(48, 80):
			if img.get_pixel(x, y).a > 0.0:
				drawn += 1
	assert_gt(drawn, 300, "the frog fills its 32 x 32 square")


func test_every_site_is_a_32_by_32_picture_of_four_16_by_16_tiles() -> void:
	assert_eq(Sprites.POI_SIZE, 32)
	assert_eq(Sprites.poi_atlas_texture().get_size(), Vector2(320, 32))
	for kind in Sprites.poi_kinds():
		assert_eq(Sprites.poi_rect(kind).size, Vector2(32, 32), kind)
		for q in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var piece := Sprites.poi_quadrant_rect(kind, q)
			assert_eq(piece.size, Vector2(16, 16), "%s %s" % [kind, q])
			assert_true(Sprites.poi_rect(kind).encloses(piece))


func test_the_16_by_16_originals_of_the_sites_are_kept_for_the_upscale_tool() -> void:
	assert_true(FileAccess.file_exists("res://art/source/poi_atlas_16.png"))
	assert_true(FileAccess.file_exists("res://art/source/animals_16.png"))
	assert_true(FileAccess.file_exists("res://tools/upscale_sites.py"))


func test_units_and_camps_have_a_dark_outline_so_they_stand_on_any_ground() -> void:
	for sprite in Sprites.UNITS.values() + Sprites.CAMPS.values():
		var img := Sprites.image(sprite)
		var dark := 0
		for y in 16:
			for x in 16:
				var c := img.get_pixel(x, y)
				if c.a > 0.0 and c.v < 0.2:
					dark += 1
		assert_gt(dark, 8, "%s has no outline" % sprite)
