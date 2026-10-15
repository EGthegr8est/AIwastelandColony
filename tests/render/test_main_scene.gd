extends "res://tests/framework/test_case.gd"
## Smoke test of the real game scene (main.tscn: map, camera and HUD together), driven through the
## HUD's own buttons like a player would. The other render tests use a stand-in fixture, so this
## catches the map and the rest of the game falling out of step.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Daylight = preload("res://scripts/daylight.gd")

var main: Node2D
var map: Node2D


func before_each() -> void:
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	map = main.get_child(0)


func test_starting_a_colony_draws_the_map() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	assert_true(Game.in_game)
	assert_gt(map.stats.tile_draws, 0, "starting a game draws the map")
	assert_true(map.tile_layer.is_visible_in_tree())


func test_zooming_and_ending_a_season_with_the_window() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	var cam: Camera2D = main.cam
	var zoom := cam.zoom
	for i in 3:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		get_tree().root.push_input(wheel)
	await wait_frames(2)
	assert_lt(cam.zoom.x, zoom.x, "the wheel zooms out")
	Daylight.enabled = true   # a saved setting could have the night off
	var window: Control = _hud().end_button
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	window._gui_input(click)   # a click on the END SEASON window
	await wait_frames(3)
	assert_eq(Game.season, 2)
	assert_true(window.is_night, "Summer is night: the window is setting into it")


func _hud() -> Node:
	for child in main.get_children():
		if child.has_method("end_season_pressed"):
			return child
	return null


## Presses the first HUD button whose text starts with `text`.
func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)
