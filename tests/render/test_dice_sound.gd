extends "res://tests/framework/test_case.gd"
## The sound of the die, through the real HUD: the roll's sound is the one for the number it lands on (the plain 8-bit roll with the chips and cracks a low roll breaks off
## the die mixed in; a 20 is clean), on the music bus, at the animation's speed. Space is the die's key: it rolls the die on the panel of the party at a site, and moves on
## once the number has landed.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Leaders = preload("res://scripts/leaders.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var main: Node2D
var hud: Node
var home: Vector2i
var site: Vector2i


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
	Game.hollow_found = true
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	home = Game.home(Data.PLAYER)
	site = World.find_tile(func(c, t): return t["b"] == "poi_missile_silo" or t["b"] == "poi_weather_station" or t["b"] == "poi_water_tower" or t["b"] == "poi_cargo_yard")
	assert_ne(site, Vector2i(-1, -1), "this map has a site")
	site = Game.poi_anchor(site)


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _space() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	hud._input(e)


## A party of three at the site, ready to roll, with the site picked and the Tile panel showing its die.
func _party_roll(d20: Array, other := [2]) -> Dictionary:
	Game.reveal(Data.PLAYER, site, 2)
	Units.dice = ForcedDice.new(d20, other)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", site, site)
	u.home = home
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = []
	Units.units.append(u)
	Units._begin_visit(u)
	Game.select(site)
	Game.changed.emit()
	await wait_frames(4)
	return u


# ---------------------------------------------------------------- the sound for each number

func test_all_twenty_rolls_have_a_sound_of_the_right_length() -> void:
	for n in range(1, 21):
		var stream: AudioStreamWAV = load(hud.DICE_ROLL_SOUND % n)
		assert_not_null(stream, "roll %d" % n)
		if stream != null:
			assert_almost_eq(stream.get_length(), 0.75, 0.01, "roll %d is the 750 ms roll" % n)
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "plays once")


func test_a_low_roll_sounds_different_from_a_high_one() -> void:
	var one: PackedByteArray = (load(hud.DICE_ROLL_SOUND % 1) as AudioStreamWAV).data
	var ten: PackedByteArray = (load(hud.DICE_ROLL_SOUND % 10) as AudioStreamWAV).data
	var twenty: PackedByteArray = (load(hud.DICE_ROLL_SOUND % 20) as AudioStreamWAV).data
	assert_ne(one, twenty, "a 1 has chips and cracks a 20 does not")
	assert_ne(ten, twenty)
	assert_ne(one, ten)
	assert_eq(twenty, (load("res://d20_dice/audio/dice_roll.wav") as AudioStreamWAV).data, "a 20 is the plain roll")


func test_the_die_throws_the_sound_for_the_number_it_lands_on() -> void:
	for n in [1, 7, 13, 20]:
		hud._on_dice_started(n)
		assert_eq(hud.dice_sfx.stream.resource_path, hud.DICE_ROLL_SOUND % n, "a %d" % n)
		assert_true(hud.dice_sfx.playing, "and it is playing")
	assert_eq(hud.dice_sfx.bus, Music.BUS, "on the music bus, so the slider covers it")
	assert_eq(hud.dice_sfx.pitch_scale, hud.DICE_SPEED, "at the speed of the animation")
	assert_eq(hud.dice_sfx.volume_db, hud.DICE_SOUND_DB)


func test_numbers_outside_the_die_are_kept_to_1_to_20() -> void:
	hud._on_dice_started(0)
	assert_eq(hud.dice_sfx.stream.resource_path, hud.DICE_ROLL_SOUND % 1)
	hud._on_dice_started(25)
	assert_eq(hud.dice_sfx.stream.resource_path, hud.DICE_ROLL_SOUND % 20)


func test_a_real_roll_plays_the_sound_of_what_the_die_shows() -> void:
	var u: Dictionary = await _party_roll([4])
	assert_true(hud._die_is_up())
	hud.dice.clicked.emit()   # a click on the die
	assert_eq(hud.dice_phase, "rolling")
	assert_eq(hud.dice_sfx.stream.resource_path, hud.DICE_ROLL_SOUND % 4, "the die was thrown to land on a 4")
	assert_true(hud.dice_sfx.playing)
	assert_eq(u.stage, "site")


# ---------------------------------------------------------------- Space rolls the die

func test_space_rolls_the_die_and_it_sounds_like_a_click() -> void:
	await _party_roll([13])
	assert_true(hud._die_is_up())
	_space()
	assert_eq(hud.dice_phase, "rolling", "Space rolled it")
	assert_eq(hud.dice_sfx.stream.resource_path, hud.DICE_ROLL_SOUND % 13)
	assert_true(hud.dice_sfx.playing)


func test_space_during_the_roll_does_nothing_and_after_the_hold_moves_on() -> void:
	await _party_roll([15])
	_space()
	var stream: AudioStream = hud.dice_sfx.stream
	_space()
	_space()
	assert_eq(hud.dice_phase, "rolling", "pressing it again does not roll twice")
	assert_eq(hud.dice_sfx.stream, stream)
	await wait_seconds(1.0)
	assert_eq(hud.dice_phase, "landed")
	_space()
	assert_eq(hud.dice_phase, "landed", "the number sits for a moment first")
	hud.dice_hold_until = 0
	_space()
	assert_eq(hud.dice_phase, "idle", "then Space moves on, as a click does")


func test_space_with_no_die_on_screen_does_nothing() -> void:
	assert_false(hud._die_is_up())
	_space()
	assert_eq(hud.dice_phase, "idle")


func test_space_does_not_skip_the_walk_but_enter_does() -> void:
	var map: Node = main.find_children("*", "Node2D", true, false).filter(func(n): return n.has_method("finish_replay"))[0]
	map.playing = true
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	map._unhandled_input(space)
	assert_true(map.playing, "Space leaves the walk alone")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	map._unhandled_input(enter)
	assert_false(map.playing, "Enter still skips it")


func test_space_is_not_a_die_key_over_a_menu() -> void:
	await _party_roll([9])
	hud.show_main_menu()
	assert_false(hud._die_is_up())
	_space()
	assert_eq(hud.dice_phase, "idle")
	hud._close_menu()
