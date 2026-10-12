extends "res://tests/framework/test_case.gd"
## The legend in the side panel shows the pixel-art sprites in place of the text glyphs, with
## buttons to flip between the three styles. Driven through the real game scene and its HUD.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const Leaders = preload("res://scripts/leaders.gd")

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
	Sprites.style = 1


## The pictures in the legend (8 x 8 sprites, not the portraits and icons elsewhere).
func _sprites() -> Array:
	return tile_box.find_children("*", "TextureRect", true, false).filter(func(r): return r.texture.get_size() == Vector2(8, 8))


func _labels() -> Array:
	return tile_box.find_children("*", "Label", true, false).map(func(l): return l.text)


func test_the_legend_has_a_sprite_for_every_ground_slope_unit_and_camp() -> void:
	var expected: int = Data.TERRAIN.size() + 2 + Data.UNITS.size() + Data.TRIBE_CLASSES.size()
	assert_eq(expected, 23)
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
	assert_true(labels.any(func(t): return t.begins_with("Raider tribe camp")))


func test_the_style_buttons_flip_the_whole_legend() -> void:
	var before: Array = _sprites().map(func(r): return r.texture.get_image().get_data())
	_press("2")
	await wait_frames(2)
	assert_eq(Sprites.style, 2)
	tile_box = hud.boxes["Tile"]
	var after: Array = _sprites().map(func(r): return r.texture.get_image().get_data())
	assert_eq(after.size(), before.size())
	for i in before.size():
		assert_ne(after[i], before[i], "sprite %d changed style" % i)
	_press("3")
	await wait_frames(2)
	assert_eq(Sprites.style, 3)
	_press("1")
	await wait_frames(2)
	assert_eq(Sprites.style, 1)


func test_the_style_you_are_on_cannot_be_pressed_again() -> void:
	for b in tile_box.find_children("*", "Button", true, false):
		if b.text == "1":
			assert_true(b.disabled)
		elif b.text in ["2", "3", "ASCII"]:
			assert_false(b.disabled)


func test_the_ascii_button_brings_back_the_text_glyphs_everywhere() -> void:
	_press("ASCII")
	await wait_frames(3)
	assert_eq(Sprites.state(), 0)
	tile_box = hud.boxes["Tile"]
	assert_eq(_sprites().size(), 0, "no pictures left in the legend")
	assert_true(_labels().any(func(t): return t.begins_with(Data.UNITS["scav"].glyph)))
	assert_eq(hud.art_button.text, "Art: text glyphs")
	_press("2")
	await wait_frames(3)
	assert_eq(Sprites.state(), 2)
	assert_eq(hud.art_button.text, "Art: style 2")


func test_the_art_button_in_the_top_bar_cycles_the_map_and_legend() -> void:
	assert_eq(hud.art_button.text, "Art: style 1")
	var seen := []
	for i in 4:
		_press("Art:")
		await wait_frames(3)
		seen.append(Sprites.state())
	assert_eq(seen, [2, 3, 0, 1])
	tile_box = hud.boxes["Tile"]
	assert_eq(_sprites().size(), 23, "back on style 1: the pictures are back")


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


## Presses the first visible, enabled HUD button whose text is exactly `text` (or starts with it, for the long ones).
func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if (b.text == text or (text.length() > 1 and b.text.begins_with(text))) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button \"%s\"" % text)
