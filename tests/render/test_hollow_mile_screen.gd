extends "res://tests/framework/test_case.gd"
## The Hollow Mile screen through the real HUD: it comes up when your scouts first see the old highway, shows the day picture in a day season and
## the night picture in a night season, waits for a season's walk to finish, and a click (or Enter, Space, Escape) closes it. The title card stands in
## for a picture that is missing, so these tests hold with or without the two files in art/.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Daylight = preload("res://scripts/daylight.gd")
const Sprites = preload("res://scripts/sprites.gd")

var main: Node2D
var hud: Node


func before_each() -> void:
	seed(5)
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	Daylight.enabled = true   # the tests normally run in daylight with the night switched off


func after_each() -> void:
	Daylight.enabled = false
	Game.replaying = false


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _click(control: Control) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	control.gui_input.emit(e)


func _key(keycode: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	Input.parse_input_event(e)


func _highway_cell() -> Vector2i:
	for i in Game.tiles.size():
		if Game.tiles[i]["b"] == "old_road":
			return Vector2i(i % Game.w, i / Game.w)
	return Vector2i(-1, -1)


func _forget_the_mile() -> void:
	for i in Game.tiles.size():
		if Game.tiles[i]["b"] in ["old_road", "old_bridge"]:
			Game.memory[Data.PLAYER][i] = null
	Game.hollow_found = false


func test_the_screen_is_hidden_until_the_mile_is_found() -> void:
	assert_false(hud.hollow_screen.visible)
	assert_eq(hud.hollow_screen.mouse_filter, Control.MOUSE_FILTER_STOP, "nothing under it can be clicked")


func test_a_day_season_shows_the_day_picture() -> void:
	Game.season = 1
	assert_true(Daylight.is_day(Game.season))
	hud.show_hollow_mile()
	assert_true(hud.hollow_screen.visible)
	assert_true(hud.hollow_art.texture == Sprites.picture(Data.HOLLOW_MILE.day), "the day picture (or none, if the file is not in art/ yet)")
	assert_eq(hud.hollow_title.get_theme_color("font_color"), Data.HOLLOW_MILE.day_color, "and the day colour on the title card")


func test_a_night_season_shows_the_night_picture() -> void:
	Game.season = 2
	assert_false(Daylight.is_day(Game.season))
	hud.show_hollow_mile()
	assert_true(hud.hollow_screen.visible)
	assert_true(hud.hollow_art.texture == Sprites.picture(Data.HOLLOW_MILE.night), "the night picture (or none, if the file is not in art/ yet)")
	assert_eq(hud.hollow_title.get_theme_color("font_color"), Data.HOLLOW_MILE.night_color)


func test_with_the_night_switched_off_it_is_always_the_day_picture() -> void:
	Daylight.enabled = false
	Game.season = 2
	hud.show_hollow_mile()
	assert_true(hud.hollow_art.texture == Sprites.picture(Data.HOLLOW_MILE.day))
	assert_eq(hud.hollow_title.get_theme_color("font_color"), Data.HOLLOW_MILE.day_color)


func test_a_night_find_in_high_radiation_shows_the_fallout_picture() -> void:
	Game.season = 2
	hud.show_hollow_mile(true)
	assert_true(hud.hollow_screen.visible)
	assert_true(hud.hollow_art.texture == Sprites.picture(Data.HOLLOW_MILE.fallout), "the green high-radiation picture")
	assert_eq(hud.hollow_title.get_theme_color("font_color"), Data.HOLLOW_MILE.fallout_color)


func test_a_day_find_stays_the_day_picture_even_in_high_radiation() -> void:
	Game.season = 1
	hud.show_hollow_mile(true)
	assert_true(hud.hollow_art.texture == Sprites.picture(Data.HOLLOW_MILE.day), "there is no high-radiation picture for the day: it is the day one")


func test_a_night_find_on_cool_ground_is_the_dusk_picture() -> void:
	Game.season = 2
	hud.show_hollow_mile(false)
	assert_true(hud.hollow_art.texture == Sprites.picture(Data.HOLLOW_MILE.night))


func test_the_three_pictures_are_different_and_the_same_size() -> void:
	var seen := []
	for version in ["day", "night", "fallout"]:
		var pic: Texture2D = Sprites.picture(Data.HOLLOW_MILE[version])
		assert_not_null(pic, version)
		assert_eq(pic.get_size(), Vector2(1152, 768), "the same size, so the screen does not jump (%s)" % version)
		var bytes: PackedByteArray = pic.get_image().get_data()
		assert_false(bytes in seen, "%s is its own picture" % version)
		seen.append(bytes)


func test_no_title_card_is_needed_now_the_pictures_are_in() -> void:
	Game.season = 1
	hud.show_hollow_mile()
	assert_not_null(hud.hollow_art.texture)
	assert_eq(hud.hollow_title.text, "", "the pictures carry their own title")


func test_a_find_in_high_radiation_at_night_comes_all_the_way_from_the_game_to_the_screen() -> void:
	Game.season = 2
	_forget_the_mile()
	var spot := _highway_cell()
	Game.tile(spot)["rad"] = 120
	var party: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", spot, Game.home(Data.PLAYER))
	Units.units.append(party)
	Game.update_fog()
	await wait_frames(3)
	assert_true(hud.hollow_screen.visible)
	assert_true(hud.hollow_art.texture == Sprites.picture(Data.HOLLOW_MILE.fallout))
	Units.units.erase(party)


func test_a_missing_picture_leaves_a_title_card() -> void:
	Game.season = 1
	hud.show_hollow_mile()
	if hud.hollow_art.texture == null:
		assert_eq(hud.hollow_title.text, "THE HOLLOW MILE")
		assert_ne(hud.hollow_note.text, "")
	else:
		assert_eq(hud.hollow_title.text, "", "the picture carries its own title")
		assert_eq(hud.hollow_note.text, "")


func test_a_click_closes_it() -> void:
	hud.show_hollow_mile()
	assert_true(hud.hollow_screen.visible)
	_click(hud.hollow_screen)
	assert_false(hud.hollow_screen.visible)


func test_enter_space_and_escape_close_it_too() -> void:
	for key in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
		hud.show_hollow_mile()
		assert_true(hud.hollow_screen.visible)
		_key(key)
		await wait_frames(3)
		assert_false(hud.hollow_screen.visible, "key %d" % key)


func test_seeing_the_highway_for_the_first_time_brings_the_picture_up() -> void:
	_forget_the_mile()
	assert_false(hud.hollow_screen.visible)
	Game.reveal(Data.PLAYER, _highway_cell(), 1)
	Units.check_discoveries()
	await wait_frames(3)
	assert_true(hud.hollow_screen.visible)
	_click(hud.hollow_screen)
	Game.reveal(Data.PLAYER, _highway_cell() + Vector2i(3, 0), 1)
	Units.check_discoveries()
	await wait_frames(3)
	assert_false(hud.hollow_screen.visible, "it does not come back")


func test_the_picture_waits_for_a_season_that_is_still_walking() -> void:
	_forget_the_mile()
	Game.replaying = true
	Game.reveal(Data.PLAYER, _highway_cell(), 1)
	Units.check_discoveries()
	await wait_frames(3)
	assert_false(hud.hollow_screen.visible, "the season is still walking")
	Game.replaying = false
	Game.replay_done.emit()
	await wait_frames(2)
	assert_true(hud.hollow_screen.visible, "and now the picture comes")


func test_it_never_comes_up_over_the_ending() -> void:
	Game._end("defeat", "overrun")
	await wait_frames(2)
	assert_true(hud.ending_screen.visible)
	hud.show_hollow_mile()
	assert_false(hud.hollow_screen.visible)


func test_it_fits_the_window_whatever_its_shape() -> void:
	hud.show_hollow_mile()
	assert_eq(hud.hollow_fit.stretch_mode, AspectRatioContainer.STRETCH_FIT)
	assert_eq(hud.hollow_art.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
	assert_gt(hud.hollow_fit.ratio, 1.0)
