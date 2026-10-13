extends "res://tests/framework/test_case.gd"
## Day and night (daylight.gd): which seasons are day, how the light is worked out, what the ground and the things on it are multiplied by,
## and the saved Night switch. The drawing is tested in tests/render/test_night.gd.

const Data = preload("res://scripts/data.gd")
const Daylight = preload("res://scripts/daylight.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")


func before_each() -> void:
	Daylight.enabled = true


func after_each() -> void:
	Daylight.enabled = false   # the test setup keeps it day
	SeasonReplay.mode = "off"
	DirAccess.remove_absolute(Music.settings_path)


func test_spring_and_autumn_are_day_and_summer_and_winter_are_night() -> void:
	for season in range(1, 13):
		var name: String = Data.SEASONS[(season - 1) % 4]
		var want := name in ["Spring", "Autumn"]
		assert_eq(Daylight.is_day(season), want, "season %d (%s)" % [season, name])
		assert_eq(Daylight.word(season), "day" if want else "night")


func test_the_light_a_season_ends_up_with_is_one_or_zero() -> void:
	assert_eq(Daylight.target_light(1), 1.0)
	assert_eq(Daylight.target_light(2), 0.0)
	assert_eq(Daylight.target_light(3), 1.0)
	assert_eq(Daylight.target_light(4), 0.0)


func test_with_the_night_switched_off_it_is_always_day() -> void:
	Daylight.enabled = false
	for season in 8:
		assert_eq(Daylight.target_light(season + 1), 1.0)


func test_the_fade_takes_as_long_as_the_walk_on_normal_and_the_fast_length_otherwise() -> void:
	SeasonReplay.mode = "normal"
	assert_eq(Daylight.fade_seconds(), 3.0)
	SeasonReplay.mode = "fast"
	assert_eq(Daylight.fade_seconds(), 1.2)
	SeasonReplay.mode = "off"
	assert_eq(Daylight.fade_seconds(), 1.2, "no walk, but you still see the turn change")


func test_the_ground_runs_from_untouched_by_day_to_moon_blue_at_night() -> void:
	assert_eq(Daylight.ground(1.0), Color.WHITE)
	assert_eq(Daylight.ground(0.0), Daylight.NIGHT)
	var half := Daylight.ground(0.5)
	assert_almost_eq(half.r, (1.0 + Daylight.NIGHT.r) / 2.0, 0.001)
	assert_eq(Daylight.ground(2.0), Color.WHITE, "the light is kept between 0 and 1")
	assert_eq(Daylight.ground(-1.0), Daylight.NIGHT)


func test_night_is_dark_but_every_channel_stays_readable_and_it_leans_blue() -> void:
	var n := Daylight.NIGHT
	assert_gt(minf(n.r, minf(n.g, n.b)), 0.2, "not black")
	assert_gt(n.b, n.g)
	assert_gt(n.g, n.r)


func test_things_take_only_part_of_the_dimness_so_they_stay_easy_to_see() -> void:
	assert_eq(Daylight.things(1.0), Color.WHITE)
	var ground := Daylight.ground(0.0)
	var things := Daylight.things(0.0)
	for channel in ["r", "g", "b"]:
		assert_gt(things[channel], ground[channel], "%s: brighter than the ground" % channel)
		assert_lt(things[channel], 1.0, "%s: but still dimmed" % channel)


func test_darkness_is_the_other_way_round_from_light() -> void:
	assert_eq(Daylight.darkness(1.0), 0.0)
	assert_eq(Daylight.darkness(0.0), 1.0)
	assert_almost_eq(Daylight.darkness(0.25), 0.75, 0.0001)


func test_a_halo_flickers_a_little_and_differently_from_its_neighbour() -> void:
	var low := 10.0
	var high := 0.0
	var differs := false
	for i in 400:
		var t := i * 0.037
		var a := Daylight.flicker(t, 3)
		low = minf(low, a)
		high = maxf(high, a)
		if absf(a - Daylight.flicker(t, 4)) > 0.01:
			differs = true
	assert_gt(low, 0.84, "it never gutters out")
	assert_le(high, 1.031)
	assert_gt(high - low, 0.05, "it does move")
	assert_true(differs, "each fire has its own flicker")


func test_craters_ruins_every_camp_and_your_parties_have_a_halo() -> void:
	for kind in ["crater", "ruins", "party"] + Data.TRIBE_CLASSES.keys():
		var h := Daylight.halo(kind)
		assert_false(h.is_empty(), kind)
		assert_gt(h.radius, 0.5, kind)
		assert_gt(h.alpha, 0.0, kind)
		assert_le(h.alpha, 1.0, kind)
	assert_true(Daylight.halo("deer").is_empty(), "a wild animal has none")
	assert_true(Daylight.halo("band").is_empty(), "nor does an enemy party")
	assert_true(Daylight.halo("").is_empty(), "nor fallout waste and fused glass: they only keep their speckles")


func test_your_own_glow_is_smaller_and_dimmer_than_a_fires() -> void:
	var party := Daylight.halo("party")
	for kind in ["crater", "ruins"] + Data.TRIBE_CLASSES.keys():
		assert_lt(party.radius, Daylight.halo(kind).radius, kind)
		assert_lt(party.alpha, Daylight.halo(kind).alpha, kind)


func test_the_switch_is_saved_and_read_back() -> void:
	Daylight.set_enabled(false)
	Daylight.enabled = true
	Daylight.load_setting()
	assert_false(Daylight.enabled, "off was saved")
	Daylight.set_enabled(true)
	Daylight.enabled = false
	Daylight.load_setting()
	assert_true(Daylight.enabled, "and on")


func test_saving_the_switch_keeps_the_other_settings_in_the_file() -> void:
	SeasonReplay.mode = "fast"
	SeasonReplay.save_mode()
	Daylight.set_enabled(false)
	SeasonReplay.mode = "normal"
	SeasonReplay.load_mode()
	assert_eq(SeasonReplay.mode, "fast", "the walk speed is still there")
	Daylight.enabled = true
	Daylight.load_setting()
	assert_false(Daylight.enabled)


func test_with_nothing_saved_the_night_is_on() -> void:
	DirAccess.remove_absolute(Music.settings_path)
	Daylight.enabled = true
	Daylight.load_setting()
	assert_true(Daylight.enabled)
