extends "res://tests/framework/test_case.gd"
## The legend in the side panel shows the pixel-art sprites in place of the text glyphs, with
## buttons to flip between the pixel art and the glyphs. Driven through the real game scene and its HUD.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Daylight = preload("res://scripts/daylight.gd")

var main: Node2D
var hud: CanvasLayer
var tile_box: VBoxContainer


func before_each() -> void:
	Sprites.style = 1
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	hud = main.get_child(main.get_child_count() - 1)
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	tile_box = hud.boxes["Tile"]
	assert_false(Game.in_bounds(Game.selected), "nothing selected, so the Tile tab shows the legend")


func after_each() -> void:
	Sprites.style = Sprites.CLEAN
	Daylight.enabled = false   # the test setup keeps it day
	DirAccess.remove_absolute(Music.settings_path)


## The pictures in the legend (16 x 16 sprites, not the animals, the sites, the portraits and icons elsewhere).
func _sprites() -> Array:
	return tile_box.find_children("*", "TextureRect", true, false).filter(func(r): return (r.texture.get_size() == Vector2(16, 16) or (r.texture is AtlasTexture and r.texture.atlas == Sprites.picture(Sprites.UNITS32_PNG))) and not (r.texture is AtlasTexture and r.texture.atlas == Sprites.animals_texture()))


func _labels() -> Array:
	return tile_box.find_children("*", "Label", true, false).map(func(l): return l.text)


func test_the_legend_has_a_sprite_for_every_ground_slope_unit_and_camp() -> void:
	var expected: int = Data.TERRAIN.size() + 1 + 2 + 2 + 2 + Data.UNITS.size() + Data.TRIBE_CLASSES.size()   # the grounds, the ford, the two slopes, the road and the highway, the two bridges, units and camps
	assert_eq(expected, 30)
	assert_eq(_sprites().size(), expected)


func test_the_text_glyphs_are_gone_from_the_legend() -> void:
	var glyphs := ["─│┌┐", "═║╔╗"]
	for id in Data.TERRAIN:
		glyphs.append(Data.TERRAIN[id].glyph[0])
	for id in Data.UNITS:
		glyphs.append(Data.UNITS[id].glyph)
	for id in Data.TRIBE_CLASSES:
		glyphs.append(Data.TRIBE_CLASSES[id].glyph)
	for text in _labels():
		for g in glyphs:
			assert_false(text.begins_with(g), "\"%s\" still starts with the glyph %s" % [text, g])


func test_the_names_and_meanings_are_still_there() -> void:
	var labels := _labels()
	for id in Data.TERRAIN:
		assert_true(labels.any(func(t): return t.begins_with(Data.TERRAIN[id].name)), Data.TERRAIN[id].name)
	for id in Data.UNITS:
		assert_has(labels, Data.UNITS[id].name)
	assert_true(labels.any(func(t): return t.begins_with("Gentle slope")))
	assert_true(labels.any(func(t): return t.begins_with("Steep incline")))
	assert_true(labels.any(func(t): return t.begins_with("Shallow ford")))
	assert_true(labels.any(func(t): return t.contains("Bridge")))
	assert_true(labels.any(func(t): return t.contains("Old bridge")))
	assert_true(labels.any(func(t): return t.begins_with("Road:")))
	assert_true(labels.any(func(t): return t.begins_with("Old highway:")))
	assert_true(labels.any(func(t): return t.begins_with("Raider tribe camp")))


func test_the_pixel_art_and_ascii_buttons_flip_the_whole_legend() -> void:
	assert_eq(Sprites.style, Sprites.CLEAN)
	assert_eq(_sprites().size(), 30, "a picture for everything, and the two bridges")
	_press("ASCII")
	await wait_frames(2)
	assert_eq(Sprites.state(), 0)
	_press("Pixel art")
	await wait_frames(2)
	assert_eq(Sprites.state(), Sprites.CLEAN)
	assert_eq(Sprites.CHOICES, [Sprites.CLEAN, 0], "the pixel art and the glyphs: no other buttons")
	var labels := []
	tile_box = hud.boxes["Tile"]
	for b in tile_box.find_children("*", "Button", true, false):
		labels.append(b.text)
	for old in ["1", "2", "3"]:
		assert_false(labels.has(old), "no button %s" % old)


func test_the_look_you_are_on_cannot_be_pressed_again() -> void:
	Sprites.choose(Sprites.CLEAN)
	hud.refresh()
	await wait_frames(2)
	tile_box = hud.boxes["Tile"]
	for b in tile_box.find_children("*", "Button", true, false):
		if b.text == "Pixel art":
			assert_true(b.disabled)
		elif b.text == "ASCII":
			assert_false(b.disabled)


func test_the_ascii_button_brings_back_the_text_glyphs_everywhere() -> void:
	_press("ASCII")
	await wait_frames(3)
	assert_eq(Sprites.state(), 0)
	tile_box = hud.boxes["Tile"]
	assert_eq(_sprites().size(), 0, "no pictures left in the legend")
	assert_true(_labels().any(func(t): return t.begins_with(Data.UNITS["scav"].glyph)))
	assert_true(hud.sonar_tablet.is_on, "the tablet in the top bar shows the glyphs are on")
	_press("Pixel art")
	await wait_frames(3)
	assert_eq(Sprites.state(), Sprites.CLEAN)
	assert_false(hud.sonar_tablet.is_on)


func test_without_the_art_the_legend_falls_back_to_the_old_glyphs() -> void:
	var atlas: Image = Sprites._atlas
	Sprites._atlas = null
	hud.refresh()
	tile_box = hud.boxes["Tile"]
	Sprites._atlas = atlas
	assert_eq(_sprites().size(), 0)
	assert_true(_labels().any(func(t): return t.begins_with(Data.UNITS["scav"].glyph)))
	assert_true(_labels().any(func(t): return t.begins_with("─│┌┐")))
	hud.refresh()


func test_the_legend_has_a_night_switch_beside_the_art_buttons() -> void:
	assert_true(_labels().has("Night:"))
	var found := 0
	for b in tile_box.find_children("*", "Button", true, false):
		if b.text in ["On", "Off"]:
			found += 1
	assert_eq(found, 2)


func test_the_night_switch_you_are_on_cannot_be_pressed_again() -> void:
	Daylight.enabled = true
	hud.refresh()
	await wait_frames(2)
	tile_box = hud.boxes["Tile"]
	for b in tile_box.find_children("*", "Button", true, false):
		if b.text == "On":
			assert_true(b.disabled)
		elif b.text == "Off":
			assert_false(b.disabled)


func test_the_night_switch_turns_the_night_off_and_on_and_remembers_it() -> void:
	Daylight.enabled = true
	hud.refresh()
	await wait_frames(2)
	tile_box = hud.boxes["Tile"]
	_press("Off")
	await wait_frames(2)
	assert_false(Daylight.enabled)
	Daylight.enabled = true
	Daylight.load_setting()
	assert_false(Daylight.enabled, "it was saved")
	tile_box = hud.boxes["Tile"]
	_press("On")
	await wait_frames(2)
	assert_true(Daylight.enabled)


func test_the_top_bar_says_day_or_night_beside_the_season() -> void:
	Daylight.enabled = true
	Game.season = 3
	hud._refresh_top()
	assert_true(hud.top_text.text.contains("Autumn (day)"), hud.top_text.text)
	Game.season = 2
	hud._refresh_top()
	assert_true(hud.top_text.text.contains("Summer (night)"), hud.top_text.text)
	Game.season = 1
	hud._refresh_top()
	assert_true(hud.top_text.text.contains("Spring (day)"))


func test_with_the_night_off_the_top_bar_is_just_the_season() -> void:
	Daylight.enabled = false
	Game.season = 2
	hud._refresh_top()
	assert_true(hud.top_text.text.contains("Summer"))
	assert_false(hud.top_text.text.contains("(night)"))
	assert_false(hud.top_text.text.contains("(day)"))
	Game.season = 1


## Presses the first visible, enabled HUD button whose text is exactly `text` (or starts with it, for the long ones).
func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if (b.text == text or (text.length() > 1 and b.text.begins_with(text))) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button \"%s\"" % text)
