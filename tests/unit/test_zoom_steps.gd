extends "res://tests/framework/test_case.gd"
## The mouse wheel zooms the map between fixed steps: the even ones (0.5, 1, 2, 3) keep every art pixel the same size, the ones between are smoother.

const Main = preload("res://scripts/main.gd")


func test_the_steps_run_from_a_quarter_to_three_and_include_the_even_ones() -> void:
	assert_eq(Main.ZOOM_STEPS, [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0])
	for even in [0.5, 1.0, 2.0, 3.0]:
		assert_has(Main.ZOOM_STEPS, even)


func test_one_notch_in_goes_to_the_next_step_up() -> void:
	assert_eq(Main.zoom_step(0.25, true), 0.5)
	assert_eq(Main.zoom_step(0.5, true), 0.75)
	assert_eq(Main.zoom_step(1.0, true), 1.25)
	assert_eq(Main.zoom_step(1.5, true), 2.0)
	assert_eq(Main.zoom_step(2.5, true), 3.0)


func test_one_notch_out_goes_to_the_next_step_down() -> void:
	assert_eq(Main.zoom_step(3.0, false), 2.5)
	assert_eq(Main.zoom_step(2.0, false), 1.5)
	assert_eq(Main.zoom_step(1.0, false), 0.75)
	assert_eq(Main.zoom_step(0.5, false), 0.25)


func test_the_ends_stay_put() -> void:
	assert_eq(Main.zoom_step(3.0, true), 3.0)
	assert_eq(Main.zoom_step(0.25, false), 0.25)


func test_a_zoom_between_steps_snaps_to_the_next_one_in_that_direction() -> void:
	assert_eq(Main.zoom_step(1.3, true), 1.5)
	assert_eq(Main.zoom_step(1.3, false), 1.25)
	assert_eq(Main.zoom_step(0.34, false), 0.25)



func test_one_notch_moves_one_step() -> void:
	var main = Main.new()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	main._unhandled_input(wheel)
	assert_eq(main.cam.zoom.x, 1.25)
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	main._unhandled_input(wheel)
	main._unhandled_input(wheel)
	assert_eq(main.cam.zoom.x, 0.75)
	main.cam.free()
	main.free()
