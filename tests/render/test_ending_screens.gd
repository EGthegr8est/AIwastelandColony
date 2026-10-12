extends "res://tests/framework/test_case.gd"
## The ending through the real HUD: the picture, a click, the stats, a click, the main menu, with the win or defeat
## music playing the whole way until the menu takes over.

const Leaders = preload("res://scripts/leaders.gd")

var main: Node2D
var hud: Node


func before_each() -> void:
	seed(5)
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(3)


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


func _texts(node: Node) -> String:
	var text := ""
	for l in node.find_children("*", "Label", true, false):
		text += l.text + "\n"
	for b in node.find_children("*", "Button", true, false):
		text += b.text + "\n"
	return text


func test_a_defeat_shows_its_picture_with_defeat_music_then_the_stats_then_the_menu() -> void:
	assert_false(hud.ending_screen.visible)
	Game._end("defeat", "overrun")
	await wait_frames(2)
	assert_true(hud.ending_screen.visible)
	assert_false(hud.stats_screen.visible)
	assert_eq(hud.ending_art.texture.resource_path, "res://art/end_defeat.png")
	assert_eq(hud.ending_screen.mouse_filter, Control.MOUSE_FILTER_STOP, "nothing under it can be clicked")
	assert_eq(Music.mode, "lose")
	assert_eq(Music.track, Music.LOSE)
	_click(hud.ending_screen)   # acknowledge the picture
	await wait_frames(2)
	assert_false(hud.ending_screen.visible)
	assert_true(hud.stats_screen.visible)
	var text := _texts(hud.stats_screen)
	assert_has(text, "THE COLONY HAS FALLEN")
	assert_has(text, "The Rust Kings overran the colony.")
	assert_has(text, "Seasons survived")
	assert_has(text, "Raids on the Rust Kings")
	assert_has(text, "d20 rolls")
	assert_has(text, "Return to main menu")
	assert_eq(Music.mode, "lose", "the defeat music plays through the stats")
	assert_true(Game.in_game, "still the colony until the player leaves")
	_press("Return to main menu")
	await wait_frames(3)
	assert_false(hud.stats_screen.visible)
	assert_false(Game.in_game)
	assert_eq(Game.ending, {})
	assert_true(hud.title_screen.visible, "back at the main menu")
	assert_eq(Music.mode, "menu", "the menu music takes over")
	for b in main.find_children("*", "Button", true, false):
		assert_false(b.text == "Resume" and b.is_visible_in_tree(), "there is no game to resume")


func test_both_wins_show_their_own_picture_with_the_victory_music() -> void:
	Game._end("raiders_defeated", "stormed")
	await wait_frames(2)
	assert_eq(hud.ending_art.texture.resource_path, "res://art/end_raiders_defeated.png")
	assert_eq(Music.mode, "win")
	assert_eq(Music.track, Music.WIN)
	_click(hud.ending_screen)
	await wait_frames(2)
	assert_has(_texts(hud.stats_screen), "RAIDERS DEFEATED")
	_press("Return to main menu")
	await wait_frames(3)
	assert_eq(Music.mode, "menu")
	# and the long game
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	Game._end("colony_prospers", "long game")
	await wait_frames(2)
	assert_eq(hud.ending_art.texture.resource_path, "res://art/end_victory.png")
	assert_eq(Music.mode, "win")
	_click(hud.ending_screen)
	await wait_frames(2)
	assert_has(_texts(hud.stats_screen), "THE COLONY PROSPERS")


func test_enter_also_moves_on_from_the_picture() -> void:
	Game._end("defeat", "starved")
	await wait_frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await wait_frames(3)
	assert_true(hud.stats_screen.visible)
	assert_has(_texts(hud.stats_screen), "The colony starved.")


func test_the_screens_are_shown_once_even_if_the_game_tries_to_end_again() -> void:
	Game._end("defeat", "overrun")
	await wait_frames(2)
	_click(hud.ending_screen)
	await wait_frames(2)
	Game._end("raiders_defeated", "stormed")
	Game.check_ending()
	await wait_frames(2)
	assert_false(hud.ending_screen.visible, "the picture does not come back")
	assert_has(_texts(hud.stats_screen), "THE COLONY HAS FALLEN")


func test_a_new_colony_after_an_ending_plays_normally_again() -> void:
	Game._end("defeat", "overrun")
	await wait_frames(2)
	_click(hud.ending_screen)
	await wait_frames(2)
	_press("Return to main menu")
	await wait_frames(3)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	assert_true(Game.in_game)
	assert_false(hud.ending_screen.visible)
	assert_false(hud.stats_screen.visible)
	assert_eq(Music.mode, "game")
	assert_eq(Game.stats.raids_won, 0)
