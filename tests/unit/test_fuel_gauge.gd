extends "res://tests/framework/test_case.gd"
## The fuel gauges: three hand-drawn pixel instruments (a car's dashboard dial, a plane's cockpit
## dial, a boat's brass sight tube), drawn into an Image so we can look at the pixels.

const FuelGauge = preload("res://scripts/fuel_gauge.gd")


## The average position of the pixels that are exactly `color`, or (-1, -1) if there are none.
func _centre_of(img: Image, color: Color) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(color):
				sum += Vector2(x, y)
				n += 1
	return sum / n if n > 0 else Vector2(-1, -1)


func _count(img: Image, color: Color) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(color):
				n += 1
	return n


func test_every_gauge_is_the_same_size() -> void:
	for kind in FuelGauge.KINDS:
		assert_eq(FuelGauge.image(kind, 0.5).get_size(), Vector2i(FuelGauge.W, FuelGauge.H), kind)


func test_the_three_gauges_look_different() -> void:
	var seen := {}
	for kind in FuelGauge.KINDS:
		seen[FuelGauge.image(kind, 0.5).get_data()] = kind
	assert_eq(seen.size(), 3)


func test_they_are_pixel_art_with_no_blended_edges() -> void:
	for kind in FuelGauge.KINDS:
		var img := FuelGauge.image(kind, 0.37, true)
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				assert_true(a == 0.0 or a == 1.0, "%s pixel %d,%d is half transparent" % [kind, x, y])


func test_the_picture_changes_as_the_tank_empties() -> void:
	for kind in FuelGauge.KINDS:
		var shots := {}
		for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
			shots[FuelGauge.image(kind, f).get_data()] = true
		assert_eq(shots.size(), 5, "%s shows five different levels" % kind)


func test_the_same_level_always_draws_the_same_picture() -> void:
	for kind in FuelGauge.KINDS:
		assert_eq(FuelGauge.image(kind, 0.6).get_data(), FuelGauge.image(kind, 0.6).get_data())


func test_levels_outside_the_tank_are_clamped() -> void:
	for kind in FuelGauge.KINDS:
		assert_eq(FuelGauge.image(kind, 3.0).get_data(), FuelGauge.image(kind, 1.0).get_data())
		assert_eq(FuelGauge.image(kind, -2.0).get_data(), FuelGauge.image(kind, 0.0).get_data())


func test_the_warning_light_only_shows_when_asked() -> void:
	for kind in FuelGauge.KINDS:
		var calm := FuelGauge.image(kind, 0.1, false)
		var warning := FuelGauge.image(kind, 0.1, true)
		assert_ne(calm.get_data(), warning.get_data(), "%s lights up" % kind)
	# and a full tank with the light off is the picture you get without asking
	assert_eq(FuelGauge.image("car", 1.0).get_data(), FuelGauge.image("car", 1.0, false).get_data())


func test_the_car_needle_swings_from_E_on_the_left_to_F_on_the_right() -> void:
	var empty := _centre_of(FuelGauge.image("car", 0.0), FuelGauge.CAR_NEEDLE)
	var half := _centre_of(FuelGauge.image("car", 0.5), FuelGauge.CAR_NEEDLE)
	var full := _centre_of(FuelGauge.image("car", 1.0), FuelGauge.CAR_NEEDLE)
	assert_lt(empty.x, 17.0)
	assert_almost_eq(half.x, 20.0, 1.0)
	assert_lt(half.y, empty.y, "straight up is higher than pointing left")
	assert_gt(full.x, 23.0)


func test_the_plane_needle_sweeps_round_the_top_of_the_dial() -> void:
	var empty := _centre_of(FuelGauge.image("plane", 0.0), FuelGauge.PL_NEEDLE)
	var half := _centre_of(FuelGauge.image("plane", 0.5), FuelGauge.PL_NEEDLE)
	var full := _centre_of(FuelGauge.image("plane", 1.0), FuelGauge.PL_NEEDLE)
	assert_lt(empty.x, 20.0, "empty is at the lower left")
	assert_gt(empty.y, 16.0)
	assert_almost_eq(half.x, 20.0, 1.0)
	assert_lt(half.y, 16.0, "half is straight up")
	assert_gt(full.x, 20.0, "full is at the lower right")
	assert_gt(full.y, 16.0)


func test_the_boat_tube_fills_with_fuel() -> void:
	var empty := _count(FuelGauge.image("boat", 0.0), FuelGauge.FUEL)
	var half := _count(FuelGauge.image("boat", 0.5), FuelGauge.FUEL)
	var full := _count(FuelGauge.image("boat", 1.0), FuelGauge.FUEL)
	assert_eq(empty, 0)
	assert_gt(half, 0)
	assert_gt(full, half)
	# the surface of the fuel is where the scale says it is
	assert_eq(FuelGauge._boat_level(0.0), 25)
	assert_eq(FuelGauge._boat_level(1.0), 6)
	var img := FuelGauge.image("boat", 0.5)
	var level := FuelGauge._boat_level(0.5)
	assert_true(img.get_pixel(20, level + 2).is_equal_approx(FuelGauge.FUEL), "fuel below the float")
	assert_true(img.get_pixel(20, level - 3).is_equal_approx(FuelGauge.GLASS), "empty glass above it")


func test_every_gauge_marks_the_empty_end_in_red() -> void:
	for kind in FuelGauge.KINDS:
		assert_gt(_count(FuelGauge.image(kind, 1.0, true), FuelGauge.RED_ON), 0, "%s has red on it" % kind)


func test_the_gauge_widget_shows_the_picture_and_blinks_when_low() -> void:
	var gauge: FuelGauge = add_autofree(FuelGauge.new())
	gauge.setup("plane", 0.15, true)
	assert_eq(gauge.custom_minimum_size, Vector2(FuelGauge.W, FuelGauge.H) * FuelGauge.SHOW_SCALE)
	assert_eq(gauge.texture.get_image().get_data(), FuelGauge.image("plane", 0.15, true).get_data(), "lit at first")
	assert_true(gauge.is_processing(), "a low tank blinks")
	var lit := gauge.texture
	await wait_seconds(FuelGauge.BLINK_SECONDS + 0.2)
	assert_ne(gauge.texture, lit, "the light went out")
	assert_eq(gauge.texture.get_image().get_data(), FuelGauge.image("plane", 0.15, false).get_data())


func test_a_healthy_tank_does_not_blink() -> void:
	var gauge: FuelGauge = add_autofree(FuelGauge.new())
	gauge.setup("boat", 0.9, false)
	assert_false(gauge.is_processing())
	assert_eq(gauge.texture.get_image().get_data(), FuelGauge.image("boat", 0.9, false).get_data())
