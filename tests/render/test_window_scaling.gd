extends "res://tests/framework/test_case.gd"
## The layout (designed for 1600 x 900) is always scaled to the window, so a maximized or fullscreen window shows it
## bigger instead of leaving it at its designed size in the middle of empty room.

const Leaders = preload("res://scripts/leaders.gd")
const Main = preload("res://scripts/main.gd")

var main: Node2D
var window: Window
var first_size: Vector2i
var first_mode: Window.Mode


func before_each() -> void:
	seed(5)
	window = get_window()
	first_size = window.size
	first_mode = window.mode
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for b in main.find_children("*", "Button", true, false):
		if b.text == "New colony":
			b.pressed.emit()
	await wait_frames(2)
	for b in main.find_children("*", "Button", true, false):
		if b.text == "Choose" and b.is_visible_in_tree():
			b.pressed.emit()
			break
	await wait_frames(4)


func after_each() -> void:
	window.mode = first_mode
	await wait_frames(3)
	window.size = first_size
	await wait_frames(2)


## The window is only fitted in a real one (a headless run has no screen to fit).
func _needs_window() -> bool:
	if DisplayServer.get_name() == "headless":
		skip("needs a real window: run with run.ps1 -Windowed")
		return true
	return false


func _menu_button() -> Button:
	for b in main.find_children("*", "Button", true, false):
		if b.text == "Menu" and b.is_visible_in_tree():
			return b
	return null


func test_the_window_always_scales_the_designed_layout_not_only_on_small_screens() -> void:
	if _needs_window():
		return
	assert_eq(window.content_scale_size, Main.design_size())
	assert_eq(window.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_EXPAND)


func test_a_window_twice_the_designed_size_shows_the_same_layout_filling_it() -> void:
	if _needs_window():
		return
	window.size = Main.design_size() * 2   # what a fullscreen 3200 x 1800 screen is
	await wait_frames(4)
	assert_eq(get_viewport().get_visible_rect().size, Vector2(Main.design_size()), "the layout is still 1600 x 900, scaled up 2x")
	assert_not_null(_menu_button())
	var right: float = _menu_button().get_global_rect().end.x
	assert_gt(right, 1600.0 - 40.0, "the top bar's last button is still at the right edge of the screen")
	assert_lt(right, 1600.0 + 1.0, "and not off it")


func test_a_wider_screen_gets_the_extra_room_on_the_long_side_and_the_bar_stretches_across_it() -> void:
	if _needs_window():
		return
	window.size = Vector2i(3200, 1350)   # an ultrawide (2.37 : 1)
	await wait_frames(4)
	var visible := get_viewport().get_visible_rect().size
	assert_almost_eq(visible.y, 900.0, 1.0, "the height is the designed one")
	assert_gt(visible.x, 2000.0, "and the width is the room that is left")
	assert_gt(_menu_button().get_global_rect().end.x, visible.x - 40.0, "the top bar fills the whole width")


func _press_f11() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_F11
	press.pressed = true
	Input.parse_input_event(press)
	await wait_frames(6)
	var release := InputEventKey.new()
	release.keycode = KEY_F11
	release.pressed = false
	Input.parse_input_event(release)
	await wait_frames(2)


func test_f11_toggles_fullscreen_and_back_and_the_layout_still_fills_the_window() -> void:
	if _needs_window():
		return
	window.mode = Window.MODE_WINDOWED
	await wait_frames(4)
	await _press_f11()
	assert_eq(window.mode, Window.MODE_FULLSCREEN, "F11 goes fullscreen")
	var visible := get_viewport().get_visible_rect().size
	assert_almost_eq(visible.x / visible.y, float(window.size.x) / float(window.size.y), 0.02, "the layout is scaled to the fullscreen window's shape")
	assert_gt(_menu_button().get_global_rect().end.x, visible.x - 40.0, "and the top bar reaches its right edge")
	await _press_f11()
	assert_eq(window.mode, Window.MODE_WINDOWED, "F11 again goes back")


func test_f11_goes_back_to_maximized_when_that_is_where_it_came_from() -> void:
	if _needs_window():
		return
	window.mode = Window.MODE_MAXIMIZED
	await wait_frames(4)
	await _press_f11()
	assert_eq(window.mode, Window.MODE_FULLSCREEN)
	await _press_f11()
	assert_eq(window.mode, Window.MODE_MAXIMIZED)
