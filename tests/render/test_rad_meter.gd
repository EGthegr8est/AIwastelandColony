extends "res://tests/framework/test_case.gd"
## The radiation view's switch in the top bar: the artist's survey meter (art/rad_meter_sheet.png) laid on its side, where the "Rad: off" button used to be. A click
## flips the radiation view at once and plays the meter's power-on or power-off animation; only the meter's own pixels are clickable; it follows the game when the
## view is changed some other way. The meter itself (turning, frames, clicks) is also tried standalone.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Sprites = preload("res://scripts/sprites.gd")
const RadMeter = preload("res://scripts/rad_meter_button.gd")

var main: Node2D
var hud: Node
var sheet: Image


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
	sheet = Sprites.picture(hud.RAD_METER_SHEET).get_image()
	sheet.convert(Image.FORMAT_RGBA8)


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _click(meter: Control) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	meter._gui_input(e)


## A standalone meter, in the tree, laid out as `turn`.
func _meter(turn: int, scale := 1) -> Control:
	var m: Control = RadMeter.new()
	m.turn = turn
	m.pixel_scale = scale
	m.sheet = Sprites.picture(hud.RAD_METER_SHEET)
	add_autofree(m)
	return m


# ---------------------------------------------------------------- in the top bar

func test_the_meter_stands_where_the_rad_button_was() -> void:
	assert_not_null(hud.rad_meter)
	assert_eq(hud.rad_meter.get_script(), RadMeter)
	for b in main.find_children("*", "Button", true, false):
		assert_false(b.text.begins_with("Rad:"), "the Rad button is gone")
	var row: Node = hud.rad_meter.get_parent()
	assert_true(row.get_child(hud.rad_meter.get_index() - 1) is HBoxContainer, "after the music slider, where the Map button was")
	assert_eq(row.get_child(hud.rad_meter.get_index() + 1), hud.sonar_tablet, "and before the map-art tablet, which took the Art button's place")


func test_it_lies_on_its_side_and_fits_the_bar() -> void:
	var m: Control = hud.rad_meter
	assert_almost_eq(m.size.x, 76.8, 0.5, "40 x 64 turned to 64 x 40, drawn 20% bigger in the bar (the bar rounds it to whole pixels)")
	assert_eq(m.size.y, 48.0)
	var bar: Rect2 = hud.game_ui[0].get_global_rect()
	assert_eq(bar.size.y, float(hud.BAR_HEIGHT), "the top bar is 76 px tall now")
	assert_true(bar.encloses(m.get_global_rect()), "inside the top bar")
	assert_gt(m.get_global_rect().position.y, bar.position.y)
	var middle := m.get_global_rect().get_center().y
	assert_almost_eq(middle, bar.get_center().y, 1.5, "in the middle of the bar, top to bottom")


func test_it_starts_off_to_match_the_radiation_view() -> void:
	assert_false(Game.show_radiation)
	assert_false(hud.rad_meter.is_on)
	assert_eq(hud.rad_meter._sprite.animation, &"off")
	assert_false(hud.rad_meter.is_busy())
	assert_ne(hud.rad_meter.tooltip_text, "", "and it says what it does")


func test_a_click_turns_the_radiation_view_on_at_once_and_plays_the_power_on() -> void:
	var m: Control = hud.rad_meter
	var flips := [0]
	var settles := [0]
	m.switched.connect(func(_on): flips[0] += 1)
	m.settled.connect(func(_on): settles[0] += 1)
	_click(m)
	assert_true(Game.show_radiation, "the view is on the moment you click")
	assert_true(m.is_on)
	assert_true(m.is_busy())
	assert_eq(m._sprite.animation, &"power_on")
	assert_eq(flips[0], 1)
	assert_eq(settles[0], 0)
	await wait_seconds(1.3)
	assert_eq(settles[0], 1, "the animation finished")
	assert_false(m.is_busy())
	assert_eq(m._sprite.animation, &"on", "and the meter idles with its needle wandering")
	assert_true(m._sprite.sprite_frames.get_animation_loop(&"on"))
	assert_true(Game.show_radiation)


func test_a_second_click_turns_it_off_with_the_power_off() -> void:
	var m: Control = hud.rad_meter
	_click(m)
	await wait_seconds(1.3)
	_click(m)
	assert_false(Game.show_radiation, "off at once")
	assert_false(m.is_on)
	assert_eq(m._sprite.animation, &"power_off")
	await wait_seconds(0.9)
	assert_eq(m._sprite.animation, &"off")
	assert_false(m.is_busy())


func test_a_click_while_it_is_powering_up_does_nothing() -> void:
	var m: Control = hud.rad_meter
	var flips := [0]
	m.switched.connect(func(_on): flips[0] += 1)
	_click(m)
	_click(m)
	_click(m)
	assert_eq(flips[0], 1)
	assert_true(Game.show_radiation, "still on, not flipped back")


func test_the_view_is_really_on_the_map() -> void:
	_click(hud.rad_meter)
	await wait_frames(3)
	assert_true(Game.show_radiation)
	assert_true(hud.rad_meter.is_on)


func test_only_the_meters_own_pixels_are_clickable() -> void:
	var m: Control = hud.rad_meter
	var k: float = hud.BAR_ART_SCALE   # the art is drawn 20% bigger in the bar: a point on it is the art's point times k
	for corner in [Vector2(0, 0), Vector2(63, 0), Vector2(0, 39), Vector2(63, 39)]:
		assert_false(m._has_point(corner * k), "the empty corner %s" % str(corner))
	assert_true(m._has_point(Vector2(32, 20) * k), "the middle of the meter")
	assert_false(m._has_point(Vector2(-1, 20) * k))
	assert_false(m._has_point(Vector2(64, 20) * k))
	assert_false(m._has_point(Vector2(32, 40) * k))


func test_it_follows_the_game_when_the_view_is_changed_another_way() -> void:
	var m: Control = hud.rad_meter
	Game.show_radiation = true
	hud.refresh()
	assert_true(m.is_on, "on, with no animation")
	assert_eq(m._sprite.animation, &"on")
	assert_false(m.is_busy())
	Game.toggle_radiation_view()
	hud.refresh()
	assert_false(m.is_on)
	assert_eq(m._sprite.animation, &"off")


func test_a_new_game_starts_with_the_meter_off() -> void:
	_click(hud.rad_meter)
	await wait_seconds(1.3)
	assert_true(hud.rad_meter.is_on)
	Game.new_game("builder")
	hud.refresh()
	assert_false(Game.show_radiation)
	assert_false(hud.rad_meter.is_on)
	assert_eq(hud.rad_meter._sprite.animation, &"off")


func test_the_outline_shows_when_the_mouse_is_over_it_and_not_during_the_animation() -> void:
	var m: Control = hud.rad_meter
	assert_false(m._outline.visible)
	m.mouse_entered.emit()
	assert_true(m._outline.visible)
	_click(m)
	assert_false(m._outline.visible, "hidden while it powers up")
	await wait_seconds(1.3)
	assert_true(m._outline.visible, "and back, with the mouse still over it")
	m.mouse_exited.emit()
	assert_false(m._outline.visible)


func test_enter_on_the_focused_meter_flips_it_too() -> void:
	var m: Control = hud.rad_meter
	var e := InputEventAction.new()
	e.action = &"ui_accept"
	e.pressed = true
	m._gui_input(e)
	assert_true(Game.show_radiation)


# ---------------------------------------------------------------- the meter itself

func test_the_sheet_is_14_by_4_frames_of_40_by_64() -> void:
	assert_eq(sheet.get_size(), Vector2i(14 * 40, 4 * 64))


## Every pixel of the frame at grid cell (col, row) of the laid-out sheet, against the upright sheet turned: a quarter turn clockwise puts the old top left at the new top right.
func _same_turned(m: Control, col: int, row: int, turn: int) -> bool:
	var laid: Image = m._atlas.get_image()
	var cell: Vector2i = m.cell_size()
	for y in cell.y:
		for x in cell.x:
			var src := Vector2i(col * 40, row * 64)
			if turn == 1:
				src += Vector2i(y, 63 - x)
			else:
				src += Vector2i(39 - y, x)
			if laid.get_pixel(col * cell.x + x, row * cell.y + y) != sheet.get_pixelv(src):
				return false
	return true


func test_clockwise_turns_every_frame_a_quarter_to_the_right() -> void:
	var m := _meter(1)
	assert_eq(m.cell_size(), Vector2i(64, 40))
	assert_eq(m.size, Vector2(64, 40))
	assert_eq(Vector2(m._atlas.get_size()), Vector2(14 * 64, 4 * 40))
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 1), Vector2i(13, 1), Vector2i(7, 2), Vector2i(6, 3)]:
		assert_true(_same_turned(m, cell.x, cell.y, 1), "cell %s" % str(cell))


func test_anticlockwise_turns_the_other_way() -> void:
	var m := _meter(2)
	assert_eq(m.cell_size(), Vector2i(64, 40))
	for cell in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(7, 2), Vector2i(6, 3)]:
		assert_true(_same_turned(m, cell.x, cell.y, 2), "cell %s" % str(cell))


func test_upright_leaves_the_sheet_alone() -> void:
	var m := _meter(0, 3)
	assert_eq(m.cell_size(), Vector2i(40, 64))
	assert_eq(m.size, Vector2(120, 192), "40 x 64 at 3 times")
	var laid: Image = m._atlas.get_image()
	assert_eq(laid.get_size(), sheet.get_size())
	assert_eq(laid.get_data(), sheet.get_data(), "pixel for pixel")


func test_the_turned_meter_is_clickable_on_the_turned_shape() -> void:
	var up := _meter(0)
	var side := _meter(1)
	var cw := 0
	var on_side := 0
	for y in 64:
		for x in 40:
			if up._has_point(Vector2(x, y)):
				cw += 1
	for y in 40:
		for x in 64:
			if side._has_point(Vector2(x, y)):
				on_side += 1
	assert_gt(cw, 800, "a real shape")
	assert_eq(on_side, cw, "the same pixels, turned")
	assert_true(up._has_point(Vector2(20, 17)), "the dial, upright: near the top")
	assert_true(side._has_point(Vector2(63 - 17, 20)), "the dial, turned clockwise: near the right")


func test_every_animation_frame_is_on_the_sheet() -> void:
	for turn in [0, 1]:
		var m := _meter(turn)
		var cell: Vector2i = m.cell_size()
		for anim in RadMeter.ANIMS:
			var frames: Array = RadMeter.ANIMS[anim].frames
			assert_eq(m._sprite.sprite_frames.get_frame_count(anim), frames.size(), anim)
			for i in frames.size():
				var region: Rect2 = m._sprite.sprite_frames.get_frame_texture(anim, i).region
				assert_eq(region.size, Vector2(cell), "%s %d" % [anim, i])
				assert_true(Rect2(Vector2.ZERO, Vector2(m._atlas.get_size())).encloses(region), "%s %d is inside the sheet" % [anim, i])


func test_a_meter_with_no_sheet_says_so_and_does_not_crash() -> void:
	expect_error("assign rad_meter_sheet.png")
	var m: Control = RadMeter.new()
	add_autofree(m)
	m.set_on(true)
	assert_true(m.is_on)
	assert_false(m.is_busy())


# ---------------------------------------------------------------- the sounds

func test_the_meter_has_its_two_sounds_on_the_music_bus() -> void:
	var m: Control = hud.rad_meter
	assert_not_null(m.on_sound, "audio/rad_meter_on.wav")
	assert_not_null(m.off_sound, "audio/rad_meter_off.wav")
	assert_eq(m.sound_bus, Music.BUS, "the music slider is the one volume control")
	assert_eq(m._sfx_on.bus, Music.BUS)
	assert_eq(m._sfx_off.bus, Music.BUS)


func test_the_power_on_sound_ends_in_a_hum_that_loops() -> void:
	var on: AudioStreamWAV = hud.rad_meter.on_sound
	assert_eq(on.mix_rate, 44100)
	assert_eq(on.loop_mode, AudioStreamWAV.LOOP_FORWARD, "the loop point in the file was found")
	assert_eq(on.loop_begin, 39690, "the loop starts where the 0.9 s power-on animation ends")
	assert_gt(on.loop_end, on.loop_begin)
	var off: AudioStreamWAV = hud.rad_meter.off_sound
	assert_eq(off.loop_mode, AudioStreamWAV.LOOP_DISABLED, "the power-off plays once")


func test_a_click_on_starts_the_sound_and_the_hum_goes_on_while_it_is_on() -> void:
	var m: Control = hud.rad_meter
	assert_false(m.is_humming())
	_click(m)
	assert_true(m.is_humming(), "the power-on sound plays from the click")
	assert_eq(m._sfx_on.stream, m.on_sound)
	await wait_seconds(1.3)
	assert_true(m.is_humming(), "and the idle hum carries on (the file loops)")


func test_a_click_off_plays_the_power_off_and_stops_the_hum() -> void:
	var m: Control = hud.rad_meter
	_click(m)
	await wait_seconds(1.3)
	_click(m)
	assert_true(m._sfx_off.playing, "the power-off sound")
	assert_eq(m._sfx_off.stream, m.off_sound)
	await wait_seconds(0.2)
	assert_false(m.is_humming(), "the hum is faded out and stopped")


func test_a_meter_found_on_hums_straight_from_the_idle_loop() -> void:
	var m: Control = hud.rad_meter
	Game.show_radiation = true
	hud.refresh()
	assert_true(m.is_on)
	assert_true(m.is_humming(), "no intro: it was already on")
	assert_false(m._sfx_off.playing)
	Game.toggle_radiation_view()
	hud.refresh()
	await wait_seconds(0.2)
	assert_false(m.is_humming())
	assert_false(m._sfx_off.playing, "switched off by the game, not flicked: no click sound")


func test_the_hum_waits_while_a_menu_is_up_and_a_game_that_is_left_has_it_off() -> void:
	var m: Control = hud.rad_meter
	_click(m)
	await wait_seconds(1.3)
	hud.show_main_menu()
	assert_true(m._sfx_on.stream_paused, "held still under the menu")
	hud._close_menu()
	assert_false(m._sfx_on.stream_paused)
	assert_true(m.is_humming())
	Game.leave_game()
	hud.show_main_menu()
	assert_false(m.is_on, "no game, so the meter is off")
	await wait_seconds(0.2)
	assert_false(m.is_humming())


# ---------------------------------------------------------------- the hotkey

func _key(keycode: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	e.ctrl_pressed = ctrl
	hud._input(e)


func test_r_flips_the_radiation_view_like_a_click() -> void:
	var m: Control = hud.rad_meter
	assert_eq(hud.RADIATION_KEY, KEY_R)
	_key(KEY_R)
	assert_true(Game.show_radiation, "on at once")
	assert_eq(m._sprite.animation, &"power_on", "the meter plays its power-on")
	assert_true(m.is_humming(), "with its sound")
	await wait_seconds(1.3)
	_key(KEY_R)
	assert_false(Game.show_radiation)
	assert_eq(m._sprite.animation, &"power_off")
	assert_true(m._sfx_off.playing)


func test_r_while_the_meter_is_still_powering_up_does_nothing() -> void:
	_key(KEY_R)
	_key(KEY_R)
	_key(KEY_R)
	assert_true(Game.show_radiation, "still on, not flipped back")


func test_r_works_on_every_tab() -> void:
	for i in 4:
		hud.tabs.current_tab = i
		await wait_frames(2)
		var before := Game.show_radiation
		_key(KEY_R)
		assert_ne(Game.show_radiation, before, "tab %d" % i)
		await wait_seconds(1.3)


func test_other_keys_and_ctrl_r_do_not() -> void:
	_key(KEY_T)
	_key(KEY_R, true)
	assert_false(Game.show_radiation)


func test_r_does_nothing_over_a_menu_the_title_or_the_ending() -> void:
	hud.show_main_menu()
	_key(KEY_R)
	assert_false(Game.show_radiation, "the title screen is up")
	hud._close_menu()
	hud.ending_screen.visible = true
	_key(KEY_R)
	assert_false(Game.show_radiation, "the ending is up")
	hud.ending_screen.visible = false
	_key(KEY_R)
	assert_true(Game.show_radiation, "and it works again once they are gone")


func test_the_tooltip_names_the_key() -> void:
	assert_has(hud.rad_meter.tooltip_text, "(R)")
