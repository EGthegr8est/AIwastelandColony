extends "res://tests/framework/test_case.gd"
## The mouse wheel zooms the map between whole steps, so every art pixel is a whole number of screen pixels (or an even half of one).

const Main = preload("res://scripts/main.gd")


func test_the_steps_are_whole_numbers_and_even_halves() -> void:
	assert_eq(Main.ZOOM_STEPS, [0.25, 0.5, 1.0, 2.0, 3.0])


func test_one_notch_in_goes_to_the_next_step_up() -> void:
	assert_eq(Main.zoom_step(0.25, true), 0.5)
	assert_eq(Main.zoom_step(0.5, true), 1.0)
	assert_eq(Main.zoom_step(1.0, true), 2.0)
	assert_eq(Main.zoom_step(2.0, true), 3.0)


func test_one_notch_out_goes_to_the_next_step_down() -> void:
	assert_eq(Main.zoom_step(3.0, false), 2.0)
	assert_eq(Main.zoom_step(2.0, false), 1.0)
	assert_eq(Main.zoom_step(1.0, false), 0.5)
	assert_eq(Main.zoom_step(0.5, false), 0.25)


func test_the_ends_stay_put() -> void:
	assert_eq(Main.zoom_step(3.0, true), 3.0)
	assert_eq(Main.zoom_step(0.25, false), 0.25)


func test_a_zoom_between_steps_snaps_to_the_next_one_in_that_direction() -> void:
	assert_eq(Main.zoom_step(1.3, true), 2.0)
	assert_eq(Main.zoom_step(1.3, false), 1.0)
	assert_eq(Main.zoom_step(0.34, false), 0.25)
