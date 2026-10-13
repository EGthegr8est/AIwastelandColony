extends "res://tests/framework/test_case.gd"
## The real game's map and HUD playing a season back: the replay starts at END SEASON, runs on its own clock, can be skipped
## (a click, Space, Enter, or END SEASON again), raider bands in the fog stay hidden, the ground a party uncovers stays dark
## until it gets there, a raid sends a column of troops, and the ending screen waits for all of it.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Leaders = preload("res://scripts/leaders.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var main: Node2D
var hud: Node
var map: Node2D
var hq: Vector2i
var far: Vector2i


func before_each() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
		if child.has_method("pending_reveals"):
			map = child
	for b in main.find_children("*", "Button", true, false):
		if b.text == "New colony":
			b.pressed.emit()
	await wait_frames(2)
	for b in main.find_children("*", "Button", true, false):
		if b.text == "Choose" and b.is_visible_in_tree():
			b.pressed.emit()
			break
	await wait_frames(3)
	SeasonReplay.mode = "normal"   # after the HUD was built: it reads the saved choice when it starts
	Units.tribes = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	Game.res["grain"] = 200
	Game.res["fuel"] = 50
	far = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 12 and c.distance_to(hq) < 20 \
		and not Game.route("foot", hq, c).is_empty())


func after_each() -> void:
	if map != null and map.playing:
		map.finish_replay()
	SeasonReplay.mode = "off"
	SeasonReplay.save_mode()   # a test that changed the speed must not leave it in the scratch settings the next HUD reads


func _send_party() -> void:
	Units.send("scout", "foot", far)


# ---------------------------------------------------------------- starting and ending

func test_ending_the_season_with_a_party_walking_starts_a_replay() -> void:
	_send_party()
	var season := Game.season
	hud.end_season_pressed()
	assert_eq(Game.season, season + 1, "the season ended at once, as always")
	assert_true(map.playing)
	assert_true(Game.replaying)
	var walkers: Array = map.replay.actors.filter(func(a): return not a.get("wild", false))
	assert_eq(walkers.size(), 1, "the party is in it (the wandering animals are too, but they are not what it is about)")


func test_with_the_animation_off_nothing_plays() -> void:
	SeasonReplay.mode = "off"
	_send_party()
	hud.end_season_pressed()
	assert_false(map.playing)
	assert_false(Game.replaying)


func test_a_season_in_which_nothing_moves_plays_nothing() -> void:
	hud.end_season_pressed()
	assert_false(map.playing, "no party is out, so there is nothing to watch")


func test_the_replay_runs_by_itself_and_then_the_units_stand_where_the_season_left_them() -> void:
	SeasonReplay.mode = "fast"
	_send_party()
	var done := watch(Game, "replay_done")
	hud.end_season_pressed()
	assert_true(map.playing)
	assert_true(await wait_until(func(): return not map.playing, 3.0), "a fast season is over in about a second")
	assert_eq(done.count, 1)
	assert_false(Game.replaying)
	assert_eq(map.replay_ids.size(), 0)


func test_the_clock_runs_the_party_along_its_route() -> void:
	_send_party()
	hud.end_season_pressed()
	var trail: Array = map.replay.actors[0].trail
	assert_eq(map.replay_day(), 0.0)
	map.clock = 1.0
	assert_almost_eq(map.replay_day(), Data.SEASON_DAYS / 3.0, 0.0001, "a third of a season in the first second of Normal")
	var halfway := SeasonReplay.position_at(trail, map.replay_day())
	assert_ne(halfway, Vector2(trail[0][0]), "it has left the start")
	map.clock = map.replay_length
	assert_eq(SeasonReplay.position_at(trail, map.replay_day()), Vector2(trail.back()[0]), "at the end it has arrived")


# ---------------------------------------------------------------- skipping

func test_end_season_during_a_replay_only_skips_it() -> void:
	_send_party()
	hud.end_season_pressed()
	var season := Game.season
	assert_true(Game.replaying)
	hud.end_season_pressed()
	assert_eq(Game.season, season, "that press did not end another season")
	assert_false(map.playing)
	assert_false(Game.replaying)
	hud.end_season_pressed()
	assert_eq(Game.season, season + 1, "the next one does")


func test_a_click_skips_the_replay() -> void:
	_send_party()
	hud.end_season_pressed()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	map._unhandled_input(e)
	assert_false(map.playing)


func test_space_and_enter_skip_the_replay_but_other_keys_do_not() -> void:
	for key in [KEY_SPACE, KEY_ENTER]:
		_send_party()
		hud.end_season_pressed()
		var e := InputEventKey.new()
		e.keycode = key
		e.pressed = true
		map._unhandled_input(e)
		assert_false(map.playing, "%d skips" % key)
		Units.units = []
	_send_party()
	hud.end_season_pressed()
	var other := InputEventKey.new()
	other.keycode = KEY_A
	other.pressed = true
	map._unhandled_input(other)
	assert_true(map.playing, "panning with A does not skip")


func test_scrolling_to_zoom_does_not_skip_the_replay() -> void:
	_send_party()
	hud.end_season_pressed()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP
	e.pressed = true
	map._unhandled_input(e)
	assert_true(map.playing)


func test_the_next_season_replaces_a_replay_still_playing() -> void:
	_send_party()
	Game.end_season()
	assert_true(map.playing)
	Game.end_season()   # called straight, not through the button
	assert_false(map.playing and map.replay_season != Game.season, "the old replay is not left playing over the new season")


func test_leaving_the_game_ends_the_replay() -> void:
	_send_party()
	hud.end_season_pressed()
	Game.leave_game()
	await wait_frames(2)
	assert_false(map.playing)
	assert_false(Game.replaying)


func test_a_map_that_goes_away_mid_replay_does_not_leave_the_game_waiting() -> void:
	_send_party()
	hud.end_season_pressed()
	assert_true(Game.replaying)
	var done := watch(Game, "replay_done")
	map.get_parent().remove_child(map)
	assert_false(Game.replaying)
	assert_eq(done.count, 1, "anything waiting for the replay (the ending screen) is let go")
	map.free()
	map = null


func test_loading_a_game_ends_the_replay() -> void:
	Game.save_game("slot1")
	_send_party()
	hud.end_season_pressed()
	assert_true(map.playing)
	assert_true(Game.load_game("slot1"))
	assert_false(map.playing, "the replay was of the game that was left")
	assert_false(Game.replaying)


# ---------------------------------------------------------------- the speed button

func test_the_walk_button_goes_normal_fast_off_and_is_remembered() -> void:
	hud._refresh_top()
	assert_eq(hud.walk_button.text, "Walk: Normal")
	hud.walk_button.pressed.emit()
	assert_eq(hud.walk_button.text, "Walk: Fast")
	assert_eq(SeasonReplay.mode, "fast")
	hud.walk_button.pressed.emit()
	assert_eq(hud.walk_button.text, "Walk: Off")
	SeasonReplay.mode = "normal"
	SeasonReplay.load_mode()
	assert_eq(SeasonReplay.mode, "off", "it was saved when it changed")


func test_changing_the_speed_skips_a_replay_in_progress() -> void:
	_send_party()
	hud.end_season_pressed()
	hud.walk_button.pressed.emit()
	assert_false(map.playing)


# ---------------------------------------------------------------- what the replay shows

func _band_replay(band_cell: Vector2i) -> Dictionary:
	var party := {"id": 1, "kind": "scout", "owner": Data.PLAYER, "mover": "foot", "parked": false,
		"trail": [[hq, 0.0], [hq + Vector2i(0, 1), 5.0]], "gone_day": SeasonReplay.STILL}
	var band := {"id": 2, "kind": "band", "owner": Data.NONE, "mover": "foot", "parked": false,
		"trail": [[band_cell, 0.0], [band_cell + Vector2i(1, 0), 5.0]], "gone_day": SeasonReplay.STILL}
	return SeasonReplay.settle({"actors": [party, band], "events": [], "reveals": [],
		"sight_before": PackedByteArray([0]).duplicate()})


func test_your_own_parties_are_always_there_but_a_band_in_the_fog_is_not() -> void:
	var cell := hq + Vector2i(10, 10)
	var r := _band_replay(cell)
	var blind := PackedByteArray()
	blind.resize(Game.w * Game.h)
	Game.sight[Data.PLAYER] = blind
	r.sight_before = blind
	map._begin_replay(r, 3.0)
	assert_false(map._fade.has(1), "your party needs no fading: it is always drawn")
	assert_eq(map._fade[2], 0.0, "nobody can see the band")


func test_a_band_is_shown_if_you_could_see_it_when_the_season_began_or_can_now() -> void:
	var cell := hq + Vector2i(10, 10)
	var r := _band_replay(cell)
	var blind := PackedByteArray()
	blind.resize(Game.w * Game.h)
	var before := blind.duplicate()
	before[Game.idx(cell)] = 1
	r.sight_before = before
	Game.sight[Data.PLAYER] = blind
	map._begin_replay(r, 3.0)
	assert_eq(map._fade[2], 1.0, "in sight when the season began")
	map.finish_replay()
	var now := blind.duplicate()
	now[Game.idx(cell)] = 1
	r.sight_before = blind
	Game.sight[Data.PLAYER] = now
	map._begin_replay(r, 3.0)
	assert_eq(map._fade[2], 1.0, "in sight now")


func test_a_band_fades_instead_of_blinking_in_and_out() -> void:
	var cell := hq + Vector2i(10, 10)
	var r := _band_replay(cell)
	var seen := PackedByteArray()
	seen.resize(Game.w * Game.h)
	seen[Game.idx(cell)] = 1
	r.sight_before = seen
	Game.sight[Data.PLAYER] = seen
	map._begin_replay(r, 3.0)
	assert_eq(map._fade[2], 1.0)
	seen[Game.idx(cell)] = 0   # it walks out of sight (the next tile along is not in sight either)
	r.actors[1].trail = [[cell + Vector2i(5, 0), 0.0], [cell + Vector2i(6, 0), 5.0]]
	map._update_fades(0.05)
	assert_lt(map._fade[2], 1.0, "starting to fade")
	assert_gt(map._fade[2], 0.0, "not gone in one frame")


func test_ground_a_party_uncovers_stays_dark_until_it_gets_there() -> void:
	var a := hq + Vector2i(3, 0)
	var b := hq + Vector2i(4, 0)
	var r := {"actors": [{"id": 1, "kind": "scout", "owner": Data.PLAYER, "mover": "foot", "parked": false,
		"trail": [[hq, 0.0], [b, 20.0]], "gone_day": SeasonReplay.STILL}], "events": [], "reveals": [[a, 5.0], [b, 20.0]],
		"sight_before": PackedByteArray()}
	SeasonReplay.settle(r)
	map._begin_replay(r, 3.0)
	assert_eq(map.pending_reveals(0.0).size(), 2, "both start dark")
	assert_eq(map.pending_reveals(10.0), [b], "the nearer one has been uncovered")
	assert_eq(map.pending_reveals(30.0), [], "all uncovered by the end")
	Game.view = Data.AI
	assert_eq(map.pending_reveals(0.0), [], "only your own map is kept dark")
	Game.view = Data.PLAYER


func test_a_flash_shows_for_its_moment_when_the_walking_is_done() -> void:
	var r := {"actors": [{"id": 1, "kind": "scout", "owner": Data.PLAYER, "mover": "foot", "parked": false,
		"trail": [[hq, 0.0], [hq + Vector2i(2, 0), 20.0]], "gone_day": SeasonReplay.STILL}],
		"events": [{"kind": "clash", "cell": hq + Vector2i(2, 0), "day": SeasonReplay.AT_END}], "reveals": [], "sight_before": PackedByteArray()}
	SeasonReplay.settle(r)
	map._begin_replay(r, 3.0)
	var at: float = 20.0 * 3.0 / Data.SEASON_DAYS   # real seconds
	map.clock = at - 0.1
	assert_eq(map.active_pops().size(), 0, "not yet")
	map.clock = at + 0.1
	assert_eq(map.active_pops().size(), 1)
	assert_lt(map.active_pops()[0][1], 0.5, "just begun")
	map.clock = at + SeasonReplay.POP_SECONDS + 0.1
	assert_eq(map.active_pops().size(), 0, "and gone again")


func test_a_party_that_left_the_map_fades_away_after_it_goes() -> void:
	var r := {"actors": [{"id": 1, "kind": "scout", "owner": Data.PLAYER, "mover": "foot", "parked": false,
		"trail": [[hq, 0.0], [hq + Vector2i(1, 0), 10.0]], "gone_day": 10.0}], "events": [], "reveals": [], "sight_before": PackedByteArray()}
	SeasonReplay.settle(r)
	map._begin_replay(r, 3.0)
	var a: Dictionary = r.actors[0]
	assert_eq(map._actor_alpha(a, 9.0), 1.0)
	assert_almost_eq(map._actor_alpha(a, 11.0), 0.5, 0.001)
	assert_le(map._actor_alpha(a, 13.0), 0.0, "gone")


# ---------------------------------------------------------------- a march of troops

func test_a_raid_sends_a_column_of_troops_across_the_map() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.troops = 4
	Game.raid_ai()
	assert_true(map.playing)
	assert_true(map.replay.get("march", false))
	assert_eq(map.replay.actors.size(), 4, "a marker for each troop")
	assert_eq(map.replay.actors[0].kind, "soldier")
	assert_true(Game.replaying)


func test_a_raid_with_the_animation_off_sends_nobody() -> void:
	SeasonReplay.mode = "off"
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.troops = 4
	Game.raid_ai()
	assert_false(map.playing)


func test_end_season_while_the_troops_march_only_skips_the_march() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.troops = 3
	Game.raid_ai()
	var season := Game.season
	hud.end_season_pressed()
	assert_eq(Game.season, season)
	assert_false(map.playing)


# ---------------------------------------------------------------- the ending

func test_the_ending_screen_waits_for_the_walk_to_finish() -> void:
	_send_party()
	hud.end_season_pressed()
	assert_true(map.playing)
	Game._end("defeat", "overrun")
	await wait_frames(2)
	assert_false(hud.ending_screen.visible, "the season is still walking")
	map.finish_replay()
	await wait_frames(2)
	assert_true(hud.ending_screen.visible, "and now the screen comes")


func test_the_ending_screen_does_not_wait_when_nothing_is_playing() -> void:
	Game._end("defeat", "overrun")
	await wait_frames(2)
	assert_true(hud.ending_screen.visible)
