extends "res://tests/framework/test_case.gd"
## The menus: the game opens on the title screen (art/title.png with the buttons over it), "New colony" leads
## to the character selection screen with the slab-stack logo above the leaders, and the menu can be opened
## again in the middle of a game. Driven through the real game scene and its HUD.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const Leaders = preload("res://scripts/leaders.gd")

var main: Node2D
var hud: CanvasLayer


func before_each() -> void:
	Sprites.choose(1)
	Game.in_game = false   # a fresh start, whatever earlier tests left running
	Music.mode = ""
	Music._queue = []
	Music.starts = 0
	Music.set_volume(Music.DEFAULT_VOLUME)
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(3)
	hud = main.get_child(main.get_child_count() - 1)


func _buttons(box: Node) -> Array:
	return box.find_children("*", "Button", true, false).map(func(b): return b.text)


## The Choose button on each of the three leader cards of the character selection screen.
func _leader_buttons() -> Array:
	return hud.menu_box.find_children("*", "Button", true, false).filter(func(b): return b.text == "Choose")


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if (b.text == text or (text.length() > 4 and b.text.begins_with(text))) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button \"%s\"" % text)


# ---------------------------------------------------------------- the title screen

func test_the_game_opens_on_the_title_screen() -> void:
	assert_true(hud.title_screen.visible)
	assert_false(hud.menu.visible, "not the old text panel")
	assert_eq(hud.title_art.texture.get_size(), Vector2(1920, 1080), "art/title.png")
	assert_true(hud.title_art.texture == Sprites.title())
	for p in hud.game_ui:
		assert_false(p.visible, "none of the game's panels show yet")


func test_the_title_screen_has_new_colony_load_and_quit() -> void:
	assert_eq(_buttons(hud.title_buttons), ["New colony", "Load game", "Quit"])
	assert_eq(_leader_buttons().size(), 0, "the leaders come on the next screen")


func test_the_art_keeps_its_16_by_9_shape_in_any_window() -> void:
	var root := get_tree().root
	var size := root.size
	for shape in [Vector2i(1600, 900), Vector2i(1200, 900), Vector2i(1800, 700)]:
		root.size = shape
		await wait_frames(3)
		var stage: Control = hud.title_art.get_parent()
		var visible := root.get_visible_rect().size   # the layout is scaled to the window, so its room is in layout units
		assert_almost_eq(stage.size.x / stage.size.y, 16.0 / 9.0, 0.01, "window %s" % shape)
		assert_le(stage.size.x, visible.x + 0.5, "window %s" % shape)
		assert_le(stage.size.y, visible.y + 0.5, "window %s" % shape)
	root.size = size
	await wait_frames(2)


func test_the_buttons_sit_in_the_dark_band_under_the_lettering() -> void:
	await wait_frames(2)
	var stage: Control = hud.title_art.get_parent()
	var row: Control = hud.title_buttons
	assert_gt(row.position.y / stage.size.y, 0.86, "below COLONY (which ends at 86% of the way down)")
	assert_lt((row.position.y + row.size.y) / stage.size.y, 0.95, "above the credit line")
	assert_almost_eq(row.position.x + row.size.x / 2.0, stage.size.x / 2.0, 1.0, "centered")


func test_the_title_covers_the_screen_and_blocks_clicks() -> void:
	assert_eq(hud.title_screen.color, Color.BLACK)
	assert_eq(hud.title_screen.mouse_filter, Control.MOUSE_FILTER_STOP, "the map underneath mustn't get clicks")


# ---------------------------------------------------------------- character selection

func test_new_colony_opens_character_selection_with_the_logo_above_the_leaders() -> void:
	_press("New colony")
	assert_true(hud.menu.visible)
	assert_false(hud.title_screen.visible)
	var kids: Array = hud.menu_box.get_children()
	var logo: TextureRect = kids[0]
	assert_true(logo is TextureRect, "the logo is the first thing in the panel")
	assert_true(logo.texture == Sprites.logo())
	var cards: Node = kids.filter(func(k): return k is HBoxContainer)[0]   # the row of three leader cards
	assert_lt(kids.find(logo), kids.find(cards), "above the leaders")
	assert_eq(_leader_buttons().size(), Data.LEADERS.size())


func test_the_logo_is_the_slab_stack_without_its_frame() -> void:
	_press("New colony")
	var logo: TextureRect = hud.menu_box.get_child(0)
	var crop: Rect2 = logo.texture.region
	assert_eq(crop, Sprites.LOGO_CROP)
	assert_eq(logo.texture.atlas.get_size(), Vector2(960, 540), "art/logo.png")
	assert_almost_eq(logo.custom_minimum_size.x / logo.custom_minimum_size.y, crop.size.x / crop.size.y, 0.02, "not squashed")
	assert_eq(logo.custom_minimum_size.x, float(hud.LOGO_WIDTH))
	assert_le(logo.custom_minimum_size.x, hud.menu_box.get_parent().custom_minimum_size.x, "fits the panel")


func test_the_panel_matches_the_logos_background_so_there_is_no_box() -> void:
	_press("New colony")
	var style: StyleBoxFlat = hud.menu_panel.get_theme_stylebox("panel")
	assert_eq(style.bg_color, Sprites.logo_background())
	assert_gt(style.border_width_left, 0, "it keeps the amber border")
	_press("Back")
	_press("Load game")
	assert_false(hud.menu_panel.has_theme_stylebox_override("panel"), "other menus keep the usual panel")


func test_the_text_banner_is_gone_from_character_selection() -> void:
	_press("New colony")
	for l in hud.menu_box.find_children("*", "Label", true, false):
		assert_false(l.text.contains("WASTELAND COLONY"), "the logo says it now")


func test_back_returns_to_the_title_screen() -> void:
	_press("New colony")
	_press("Back")
	assert_true(hud.title_screen.visible)
	assert_false(hud.menu.visible)


func test_picking_a_leader_starts_the_colony_and_closes_the_menus() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("raider"), Leaders.fill("builder"), Leaders.fill("trader")]
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	assert_true(Game.in_game)
	assert_eq(Game.leader, "raider")
	assert_false(hud.title_screen.visible)
	assert_false(hud.menu.visible)
	for p in hud.game_ui:
		assert_true(p.visible)


# ---------------------------------------------------------------- the menu during a game

func _start_colony() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(3)


func test_the_menu_button_brings_back_the_title_with_resume() -> void:
	await _start_colony()
	_press("Menu")
	assert_true(hud.title_screen.visible)
	assert_eq(_buttons(hud.title_buttons), ["Resume", "New colony", "Load game", "Quit"])
	_press("Resume")
	await wait_frames(2)
	assert_false(hud.title_screen.visible)
	assert_true(Game.in_game)
	for p in hud.game_ui:
		assert_true(p.visible)


func test_load_from_the_title_screen_goes_back_to_it() -> void:
	_press("Load game")
	assert_true(hud.menu.visible)
	assert_false(hud.title_screen.visible)
	_press("Back")
	assert_true(hud.title_screen.visible)
	assert_false(hud.menu.visible)


func test_load_from_the_title_during_a_game_also_goes_back_to_the_title() -> void:
	await _start_colony()
	_press("Menu")
	_press("Load game")
	_press("Back")
	assert_true(hud.title_screen.visible, "back to the title, not straight into the game")
	assert_eq(Game.in_game, true)


func test_the_top_bars_load_button_still_goes_back_to_the_game() -> void:
	await _start_colony()
	for b in hud.root.find_children("*", "Button", true, false):
		if b.text == "Load":
			b.pressed.emit()
			break
	assert_true(hud.menu.visible)
	_press("Back")
	await wait_frames(2)
	assert_false(hud.menu.visible)
	assert_false(hud.title_screen.visible)


# ---------------------------------------------------------------- without the art

func test_without_the_title_art_the_main_menu_is_a_plain_panel() -> void:
	var art: Texture2D = hud.title_art.texture
	hud.title_art.texture = null
	hud.show_main_menu()
	assert_true(hud.menu.visible)
	assert_false(hud.title_screen.visible)
	var buttons := _buttons(hud.menu_box)
	assert_has(buttons, "New colony")
	assert_has(buttons, "Load game")
	assert_has(buttons, "Quit")
	hud.title_art.texture = art


func test_without_the_logo_character_selection_keeps_the_text_banner() -> void:
	var cache := Sprites._pictures.duplicate()
	Sprites._pictures["logo"] = null
	_press("New colony")
	var pictures: Array = hud.menu_box.find_children("*", "TextureRect", true, false)
	assert_eq(pictures.size(), 3, "only the three leaders' faces")
	assert_false(pictures.any(func(t): return t.texture == Sprites.logo()), "no logo")
	assert_true(hud.menu_box.find_children("*", "Label", true, false).any(func(l): return l.text.contains("WASTELAND COLONY")))
	Sprites._pictures = cache


# ---------------------------------------------------------------- the music

func test_the_title_screen_plays_the_menu_music() -> void:
	assert_eq(Music.mode, "menu")
	assert_eq(Music.track, Music.MENU)


func test_the_menu_music_carries_on_through_character_selection_and_load() -> void:
	var starts: int = Music.starts
	_press("New colony")
	assert_eq(Music.track, Music.MENU, "still the menu track on the character selection screen")
	_press("Back")
	_press("Load game")
	_press("Back")
	assert_eq(Music.track, Music.MENU)
	assert_eq(Music.starts, starts, "it wasn't restarted on the way")


func test_starting_a_colony_switches_to_the_game_music() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(2)
	assert_eq(Music.mode, "game")
	assert_has(Music.GAME, Music.track)


func test_the_menu_in_the_middle_of_a_game_keeps_the_game_music() -> void:
	await _start_colony()
	var track: String = Music.track
	var starts: int = Music.starts
	_press("Menu")
	_press("New colony")
	_press("Back")
	assert_eq(Music.mode, "game")
	assert_eq(Music.track, track)
	assert_eq(Music.starts, starts, "the music doesn't change just because the menu is open")


# ---------------------------------------------------------------- the volume slider

func _sliders() -> Array:
	return hud.root.find_children("*", "HSlider", true, false).filter(func(s): return s.is_visible_in_tree())


func test_there_is_a_music_slider_on_the_title_screen() -> void:
	var on_title: Array = hud.title_screen.find_children("*", "HSlider", true, false)
	assert_eq(on_title.size(), 1)
	assert_eq(on_title[0].min_value, 0.0, "all the way down is off")
	assert_eq(on_title[0].max_value, 1.0)
	assert_almost_eq(on_title[0].value, Music.volume, 0.001, "it starts at the current volume")


func test_the_slider_is_on_the_menu_screens_and_in_the_game() -> void:
	_press("New colony")
	assert_gt(hud.menu_box.find_children("*", "HSlider", true, false).size(), 0, "character selection")
	_press("Back")
	_press("Load game")
	assert_gt(hud.menu_box.find_children("*", "HSlider", true, false).size(), 0, "load")
	_press("Back")
	await _start_colony()
	assert_eq(_sliders().size(), 1, "the top bar's, once the game is running")


func test_moving_the_slider_sets_the_music_volume() -> void:
	var slider: HSlider = hud.title_screen.find_children("*", "HSlider", true, false)[0]
	slider.value = 0.25
	assert_almost_eq(Music.volume, 0.25, 0.001)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(Music.BUS)))


func test_all_the_way_down_is_off_and_says_so() -> void:
	var slider: HSlider = hud.title_screen.find_children("*", "HSlider", true, false)[0]
	slider.value = 0.0
	assert_eq(Music.volume, 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(Music.BUS)), "completely off")
	var reading := _reading_next_to(slider)
	assert_eq(reading.text, "off")
	slider.value = 0.8
	assert_eq(reading.text, "80%")


func test_every_slider_follows_the_one_that_moved() -> void:
	await _start_colony()
	var top: HSlider = _sliders()[0]
	var title: HSlider = hud.title_screen.find_children("*", "HSlider", true, false)[0]
	top.value = 0.4
	assert_almost_eq(title.value, 0.4, 0.001, "the title screen's slider moved too")
	_press("Menu")
	title.value = 0.1
	assert_almost_eq(top.value, 0.1, 0.001, "and the top bar's")


func test_the_top_bars_slider_leaves_room_for_the_resource_line() -> void:
	await _start_colony()
	await wait_frames(3)
	var top: RichTextLabel = hud.top_text
	var line := top.get_content_height() / top.get_line_count()
	assert_eq(top.get_line_count(), 2, "the status text is two lines (the date, and the resources) and fits the bar")
	assert_le(top.get_content_height(), 2 * line + 2)


func _reading_next_to(slider: HSlider) -> Label:
	var row := slider.get_parent()
	return row.get_child(row.get_child_count() - 1)
