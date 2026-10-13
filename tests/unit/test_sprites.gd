extends "res://tests/framework/test_case.gd"
## The pixel-art sprites in art/atlas.png: every legend entry has one, in four styles (4 is the clean look).

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")


func after_each() -> void:
	Sprites.style = 1


func test_the_atlas_loads_with_every_sprite() -> void:
	assert_true(Sprites.available())
	assert_eq(Sprites.names().size(), 24, "23 and the ford")


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


func test_sprites_are_8_by_8_pictures_with_something_in_them() -> void:
	for sprite in Sprites.names():
		for n in range(1, Sprites.STYLES + 1):
			var img := Sprites.image(sprite, n)
			assert_eq(img.get_size(), Vector2i(8, 8), "%s style %d" % [sprite, n])
			var drawn := 0
			for y in 8:
				for x in 8:
					if img.get_pixel(x, y).a > 0.0:
						drawn += 1
			assert_gt(drawn, 3, "%s style %d is blank" % [sprite, n])


## What a picture shows: its visible pixels (the colour of a see-through one is meaningless, and the import changes it).
func _seen(img: Image) -> Array:
	var out := []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			out.append(c if c.a > 0.0 else Color(0, 0, 0, 0))
	return out


func test_the_four_styles_of_each_ground_and_slope_look_different() -> void:
	for sprite in Sprites.TERRAIN.values() + Sprites.SLOPES.values() + [Sprites.FORD]:
		var seen := {}
		for n in range(1, Sprites.STYLES + 1):
			seen[Sprites.image(sprite, n).get_data()] = true
		assert_eq(seen.size(), Sprites.STYLES, sprite)


func test_units_and_camps_keep_their_style_1_pictures_in_the_clean_look() -> void:
	for sprite in Sprites.UNITS.values() + Sprites.CAMPS.values():
		var seen := {}
		for n in range(1, Sprites.STYLES):
			seen[Sprites.image(sprite, n).get_data()] = true
		assert_eq(seen.size(), 3, "%s: styles 1 to 3 differ" % sprite)
		assert_eq(_seen(Sprites.image(sprite, Sprites.CLEAN)), _seen(Sprites.image(sprite, 1)), "%s: style 4 is style 1's" % sprite)


func test_every_sprite_lies_inside_the_atlas_picture() -> void:
	var atlas: Image = Sprites._atlas
	for sprite in Sprites.names():
		for o in Sprites._meta.sprites[sprite].options:
			assert_ge(o.x, 0)
			assert_ge(o.y, 0)
			assert_le(o.x + o.w, atlas.get_width(), sprite)
			assert_le(o.y + o.h, atlas.get_height(), sprite)


func test_the_style_setting_picks_which_version_you_get() -> void:
	for n in range(1, Sprites.STYLES + 1):
		Sprites.style = n
		assert_eq(Sprites.terrain("sand").get_image().get_data(), Sprites.image("ash_sand", n).get_data(), "style %d" % n)
		assert_eq(Sprites.unit("car").get_image().get_data(), Sprites.image("war_rig", n).get_data(), "style %d" % n)


func test_a_style_can_be_asked_for_directly() -> void:
	Sprites.style = 3
	assert_eq(Sprites.texture("scout", 1).get_image().get_data(), Sprites.image("scout", 1).get_data())


func test_the_art_cycles_through_the_styles_and_then_the_text_glyphs() -> void:
	Sprites.choose(1)
	var seen := []
	for i in 5:
		seen.append(Sprites.state())
		Sprites.cycle()
	assert_eq(seen, [1, 2, 3, 4, 0])
	assert_eq(Sprites.state(), 1, "and round again to the first")


func test_choosing_is_limited_to_what_exists() -> void:
	Sprites.choose(9)
	assert_eq(Sprites.state(), Sprites.STYLES)
	Sprites.choose(-4)
	assert_eq(Sprites.state(), 0)
	assert_eq(Sprites.choice_name(0), "text glyphs")
	assert_eq(Sprites.choice_name(2), "style 2")


func test_with_the_text_glyphs_chosen_there_are_no_pictures_to_draw() -> void:
	Sprites.choose(0)
	assert_null(Sprites.terrain("sand"))
	assert_null(Sprites.unit("scav"))
	assert_true(Sprites.rects().is_empty())
	assert_not_null(Sprites.texture("scout", 2), "asking for a style by name still works")


func test_every_sprite_has_a_rectangle_inside_the_atlas() -> void:
	Sprites.choose(1)
	var atlas := Sprites.atlas_texture()
	assert_eq(atlas.get_size(), Vector2(32, 192))
	var rects := Sprites.rects()
	assert_eq(rects.size(), 24)
	for sprite in rects:
		var r: Rect2 = rects[sprite]
		assert_eq(r.size, Vector2(Sprites.SIZE, Sprites.SIZE), sprite)
		assert_true(Rect2(Vector2.ZERO, atlas.get_size()).encloses(r), sprite)


func test_the_rectangles_follow_the_style() -> void:
	Sprites.choose(1)
	var one: Rect2 = Sprites.rects()["dunes"]
	Sprites.choose(3)
	var three: Rect2 = Sprites.rects()["dunes"]
	assert_ne(one, three)
	assert_eq(three, Sprites.rect("dunes", 3))
	assert_eq(one, Sprites.rect("dunes", 1))
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
	assert_false(Sprites.unit("boat") == Sprites.texture("boat", 2))


# ---------------------------------------------------------------- the clean look (style 4)

func test_the_clean_look_is_style_4_and_the_last_picture_choice() -> void:
	assert_eq(Sprites.CLEAN, 4)
	assert_eq(Sprites.STYLES, 4)
	assert_eq(Sprites.CHOICES, [1, 2, 3, 4, 0])


func test_every_clean_ground_covers_its_whole_tile() -> void:
	var grounds: Dictionary = Sprites.TERRAIN.duplicate()
	grounds["ford"] = Sprites.FORD
	for id in grounds:
		var img := Sprites.image(grounds[id], Sprites.CLEAN)
		for y in 8:
			for x in 8:
				assert_eq(img.get_pixel(x, y).a, 1.0, "%s pixel %d,%d is see-through" % [id, x, y])


func test_the_old_looks_leave_the_ground_see_through_so_their_wash_shows() -> void:
	for id in Sprites.TERRAIN:
		var img := Sprites.image(Sprites.TERRAIN[id], 1)
		var clear := 0
		for y in 8:
			for x in 8:
				if img.get_pixel(x, y).a < 1.0:
					clear += 1
		assert_gt(clear, 0, id)


func test_the_clean_grounds_are_told_apart_by_colour() -> void:
	# the whole point: two different grounds never share a tile colour (the most common pixel)
	var common := {}
	var every: Dictionary = Sprites.TERRAIN.duplicate()
	every["ford"] = Sprites.FORD
	for id in every:
		var counts := {}
		var img := Sprites.image(every[id], Sprites.CLEAN)
		for y in 8:
			for x in 8:
				var c := img.get_pixel(x, y).to_html(false)
				counts[c] = counts.get(c, 0) + 1
		var best := ""
		for c in counts:
			if best == "" or counts[c] > counts[best]:
				best = c
		assert_false(common.has(best), "%s and %s are both mostly %s" % [id, common.get(best, ""), best])
		common[best] = id


func test_only_the_hazards_glow_in_the_clean_look() -> void:
	var glows := ["crater", "glass", "waste", "ruins"]
	for id in Sprites.TERRAIN:
		var img := Sprites.image(Sprites.TERRAIN[id], Sprites.CLEAN)
		var brightest := 0.0
		for y in 8:
			for x in 8:
				brightest = maxf(brightest, img.get_pixel(x, y).v)
		if id in glows:
			assert_gt(brightest, 0.85, "%s should glow" % id)
		else:
			assert_lt(brightest, 0.7, "%s should be matte" % id)


func test_a_clean_slope_is_a_dark_see_through_ledge_along_the_bottom() -> void:
	for id in ["gentle_slope", "steep_incline"]:
		var img := Sprites.image(id, Sprites.CLEAN)
		for x in 8:
			var c := img.get_pixel(x, 7)
			assert_gt(c.a, 0.0, "%s has a ledge pixel at the bottom" % id)
			assert_lt(c.a, 1.0, "%s is see-through" % id)
			assert_lt(c.v, 0.2, "%s is dark" % id)
		for y in 4:
			for x in 8:
				assert_eq(img.get_pixel(x, y).a, 0.0, "%s leaves the top of the tile alone" % id)
	assert_gt(Sprites.image("steep_incline", Sprites.CLEAN).get_pixel(0, 7).a, Sprites.image("gentle_slope", Sprites.CLEAN).get_pixel(0, 7).a,
		"a steep incline is darker than a gentle slope")


func test_the_legend_shows_a_clean_slope_over_sand() -> void:
	Sprites.choose(Sprites.CLEAN)
	var on_sand := Sprites.slope("gentle").get_image()
	assert_eq(on_sand.get_pixel(0, 0), Sprites.image("ash_sand", Sprites.CLEAN).get_pixel(0, 0), "the ground is the sand picture")
	assert_ne(on_sand.get_pixel(0, 7), Sprites.image("ash_sand", Sprites.CLEAN).get_pixel(0, 7), "with the ledge laid over it")
	assert_eq(on_sand.get_pixel(0, 7).a, 1.0)
	Sprites.choose(1)
	assert_eq(Sprites.slope("gentle").get_image().get_data(), Sprites.image("gentle_slope", 1).get_data(), "the old looks show the plain slope")
	assert_true(Sprites.clean() == false)


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
	assert_eq(img.get_height(), 8)
	for id in Sprites.building_ids():
		var r := Sprites.building_rect(id)
		assert_eq(r.size, Vector2(8, 8), id)
		assert_true(Rect2(Vector2.ZERO, atlas.get_size()).encloses(r), id)
		var drawn := 0
		var dark := 0
		for y in 8:
			for x in 8:
				var c := img.get_pixel(int(r.position.x) + x, y)
				if c.a > 0.0:
					drawn += 1
					if c.v < 0.2:
						dark += 1
		assert_gt(drawn, 20, "%s is nearly blank" % id)
		assert_gt(dark, 3, "%s has no dark outline, so it would melt into the ground" % id)


func test_an_unknown_building_has_no_picture() -> void:
	assert_eq(Sprites.building_rect("no_such_building"), Rect2())
