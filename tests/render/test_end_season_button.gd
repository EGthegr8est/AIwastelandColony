extends "res://tests/framework/test_case.gd"
## The END SEASON button in the top bar: the artist's window (art/end_season_sheet.png, scripts/end_season_button.gd) over the wasteland. It shows the sky the season is in: the day in
## Spring and Autumn, the night in Summer and Winter. A click ends the season and plays the sun setting (to a night season) or the dawn (to a day one), stretched to the seconds the
## map takes to fade, so the window and the map turn together. The old text button and the Map button beside it are gone.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Sprites = preload("res://scripts/sprites.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")
const Daylight = preload("res://scripts/daylight.gd")
const EndSeasonButton = preload("res://scripts/end_season_button.gd")

var main: Node2D
var hud: Node
var window: Control


func before_each() -> void:
	Sprites.style = Sprites.CLEAN
	SeasonReplay.mode = "off"   # no walk to wait for; the light still fades (1.2 s here)
	Daylight.enabled = true
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
	window = hud.end_button


func after_each() -> void:
	Sprites.style = 1
	SeasonReplay.mode = "off"
	Daylight.enabled = true
	Game.replaying = false
	DirAccess.remove_absolute(Music.settings_path)


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _click() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	window._gui_input(e)


## The sky the season has: night in Summer and Winter.
func _night_now() -> bool:
	return Daylight.target_light(Game.season) < 0.5


# ---------------------------------------------------------------- in the top bar

func test_the_window_is_the_end_season_button_and_the_map_button_is_gone() -> void:
	assert_not_null(window)
	assert_eq(window.get_script(), EndSeasonButton)
	for b in main.find_children("*", "Button", true, false):
		assert_false(b.text.begins_with("Map:"), "the Map button is gone")
		assert_ne(b.text, "END SEASON", "and so is the text button")
	assert_false("view_button" in hud, "the HUD no longer keeps a Map button")


func test_it_sits_between_the_tablet_and_save_and_fits_the_bar() -> void:
	var row: Node = window.get_parent()
	assert_eq(row.get_child(window.get_index() - 2), hud.sonar_tablet, "after the field tablet, and its E cap")
	assert_eq(row.get_child(window.get_index() + 1), hud.save_button, "then Save")
	assert_almost_eq(window.size.x, 76.8, 0.5, "the art 20% bigger")
	assert_eq(window.size.y, 48.0)
	var bar: Rect2 = hud.game_ui[0].get_global_rect()
	assert_true(bar.encloses(window.get_global_rect()), "inside the top bar")
	assert_almost_eq(window.get_global_rect().get_center().y, bar.get_center().y, 1.5, "in the middle of the bar")
	assert_ne(window.tooltip_text, "")


func test_the_three_animated_buttons_are_20_percent_bigger_and_the_bar_did_not_grow() -> void:
	assert_almost_eq(hud.BAR_ART_SCALE, 1.2, 0.0001)
	for b in [hud.rad_meter, hud.sonar_tablet, hud.end_button]:
		assert_almost_eq(b.size.x, 76.8, 0.5, "the bar rounds it to a whole pixel")
		assert_almost_eq(b.size.y, 48.0, 0.01)
		assert_almost_eq(b._sprite.scale.x, 1.2, 0.0001, "the art is scaled with it")
	assert_eq(hud.game_ui[0].get_global_rect().size.y, 76.0, "the top bar is the same 76 px")
	assert_true(window._has_point(Vector2(46, 18)), "the clickable shape follows the picture: (46, 18) here is (38, 15) of the art")
	assert_false(window._has_point(Vector2(77, 18)), "just outside the right edge")


func test_it_does_not_take_the_keyboard_focus() -> void:
	assert_eq(window.focus_mode, Control.FOCUS_NONE, "Space and Enter must never end a season through a focused window")


func test_the_frame_table_fits_the_sheet() -> void:
	var sheet: Texture2D = window.sheet
	assert_eq(sheet.get_size(), Vector2(1088, 160))
	for anim in EndSeasonButton.ANIMS:
		for f in EndSeasonButton.ANIMS[anim]["frames"]:
			assert_le(f[0] + EndSeasonButton.FRAME_W, int(sheet.get_width()), "%s frame %s" % [anim, str(f)])
			assert_le(f[1] + EndSeasonButton.FRAME_H, int(sheet.get_height()), "%s frame %s" % [anim, str(f)])


func test_only_the_windows_own_pixels_are_clickable() -> void:
	var k: float = hud.BAR_ART_SCALE
	assert_false(window._has_point(Vector2(0, 0) * k), "the empty corner")
	assert_false(window._has_point(Vector2(70, 20) * k), "outside")
	assert_true(window._has_point(Vector2(32, 15) * k), "the glass")
	assert_true(window._has_point(Vector2(32, 32) * k), "the label on the sill")


# ---------------------------------------------------------------- the sky and the seasons

func test_it_starts_on_the_day_of_spring() -> void:
	assert_false(_night_now())
	assert_false(window.is_night)
	assert_false(window.is_busy())
	assert_eq(window.current_animation(), &"day")


func test_a_click_ends_the_season_and_the_sun_sets_to_a_night_season() -> void:
	var season := Game.season
	var landed := []
	window.settled.connect(func(night): landed.append(night))
	_click()
	assert_eq(Game.season, season + 1, "the click ends the season")
	assert_true(_night_now(), "Summer is night")
	assert_true(window.is_night, "the window heads for the night")
	assert_true(window.is_busy())
	assert_eq(window.current_animation(), &"end_season", "the sun sets")
	await wait_seconds(Daylight.fade_seconds() + 0.4)
	assert_false(window.is_busy())
	assert_eq(window.current_animation(), &"night", "the moon is up and the night loops")
	assert_eq(landed, [true], "it said when the night had come")


func test_the_sunset_takes_as_long_as_the_map_fades() -> void:
	_click()
	var native: float = window._length_seconds("end_season")
	assert_almost_eq(window._sprite.speed_scale * Daylight.fade_seconds(), native, 0.01, "the animation is stretched to the fade")
	assert_gt(native, 1.0, "the artist's own sunset is about 1.4 seconds")


func test_the_next_click_at_night_brings_the_dawn_to_a_day_season() -> void:
	_click()
	await wait_seconds(Daylight.fade_seconds() + 0.4)
	_click()
	assert_eq(Game.season, 3)
	assert_false(_night_now(), "Autumn is day")
	assert_false(window.is_night)
	assert_eq(window.current_animation(), &"new_day", "the dawn")
	await wait_seconds(Daylight.fade_seconds() + 0.4)
	assert_false(window.is_busy())
	assert_eq(window.current_animation(), &"day")


func test_the_window_and_the_map_agree_on_the_sky_through_a_year() -> void:
	for i in 4:
		_click()
		assert_eq(window.is_night, _night_now(), "season %d" % Game.season)
		await wait_seconds(Daylight.fade_seconds() + 0.3)
		assert_eq(window.current_animation(), &"night" if _night_now() else &"day")


func test_two_quick_clicks_land_the_first_change_and_play_the_second() -> void:
	_click()
	_click()
	assert_eq(Game.season, 3)
	assert_false(window.is_night, "Autumn is day")
	assert_eq(window.current_animation(), &"new_day")
	await wait_seconds(Daylight.fade_seconds() + 0.4)
	assert_eq(window.current_animation(), &"day")


func test_a_new_season_found_in_a_load_puts_the_window_on_that_sky_without_playing() -> void:
	Game.season = 2   # as a loaded game would
	Game.changed.emit()
	await wait_frames(3)
	assert_true(window.is_night)
	assert_false(window.is_busy(), "nothing plays for a load")
	assert_eq(window.current_animation(), &"night")
	Game.season = 3
	Game.changed.emit()
	await wait_frames(3)
	assert_false(window.is_night)
	assert_eq(window.current_animation(), &"day")


func test_with_the_night_switched_off_the_window_stays_day_and_only_takes_a_press() -> void:
	Daylight.enabled = false
	Game.changed.emit()
	await wait_frames(3)
	_click()
	assert_eq(Game.season, 2, "the season still ends")
	assert_false(window.is_night, "the sky never changes")
	assert_eq(window.current_animation(), &"press")
	await wait_seconds(0.4)
	assert_false(window.is_busy())
	assert_eq(window.current_animation(), &"day")


func test_while_the_walk_plays_a_click_only_skips_it() -> void:
	Game.replaying = true
	var season := Game.season
	_click()
	assert_eq(Game.season, season, "it does not end another season")
	assert_false(window.is_busy(), "and the window does nothing")
	Game.replaying = false


func test_the_e_key_plays_the_window_too() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_E
	e.pressed = true
	hud._input(e)
	assert_eq(Game.season, 2)
	assert_true(window.is_night)
	assert_eq(window.current_animation(), &"end_season")


# ---------------------------------------------------------------- the door click

func test_the_door_click_is_a_short_8_bit_sound_loaded_into_the_window() -> void:
	var click := window.latch_sound as AudioStreamWAV
	assert_not_null(click, "audio/end_season_click.wav is there")
	assert_eq(click.mix_rate, 22050)
	assert_false(click.stereo)
	assert_gt(click.get_length(), 0.05)
	assert_lt(click.get_length(), 0.3, "very simple: a click, not a clip")
	assert_eq(window.sound_bus, Music.BUS, "on the music bus, so the one volume slider covers it")


func test_the_click_sounds_after_the_sunset_not_when_it_is_pressed() -> void:
	var at_settle := []
	window.settled.connect(func(_night): at_settle.append(window._sfx.playing))
	_click()
	assert_false(window._sfx.playing, "nothing sounds as the sun starts to set")
	await wait_seconds(Daylight.fade_seconds() * 0.5)
	assert_false(window._sfx.playing, "nor halfway through")
	await wait_seconds(Daylight.fade_seconds() * 0.5 + 0.4)
	assert_eq(at_settle, [true], "the door clicks as the window comes to rest")


func test_the_click_also_follows_a_dawn_and_a_press() -> void:
	var heard := []
	window.settled.connect(func(_night): heard.append(window._sfx.playing))
	_click()
	await wait_seconds(Daylight.fade_seconds() + 0.4)
	_click()
	await wait_seconds(Daylight.fade_seconds() + 0.4)
	Daylight.enabled = false
	Game.changed.emit()
	await wait_frames(3)
	_click()
	await wait_seconds(0.4)
	assert_eq(heard, [true, true, true], "after the sunset, after the dawn and after the press with the night off")


# ---------------------------------------------------------------- hover

func test_the_hover_outline_shows_when_the_mouse_is_over_an_idle_window() -> void:
	assert_false(window._outline.visible)
	window._on_mouse_entered()
	assert_true(window._outline.visible)
	_click()
	assert_false(window._outline.visible, "not while it is playing")
	await wait_seconds(Daylight.fade_seconds() + 0.4)
	assert_true(window._outline.visible, "back when it has settled, if the mouse is still there")
	window._on_mouse_exited()
	assert_false(window._outline.visible)
