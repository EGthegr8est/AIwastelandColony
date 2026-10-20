extends "res://tests/framework/test_case.gd"
## The walk animation on the real map: a party you order to walk is seen walking at once, at the normal pace (a season's 40 days take
## 3 seconds), several parties walk together, a party sent on again carries on along one trail, END SEASON during a walk skips it and
## goes on, and what walks at END SEASON (caravans, boats, planes, raider bands, animals) is still replayed as before.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Leaders = preload("res://scripts/leaders.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var main: Node2D
var hud: Node
var map: Node2D
var hq: Vector2i
var near: Vector2i    # a walk of a day or two
var near2: Vector2i   # another one, in another direction
var far: Vector2i     # a walk that takes more than a turn


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
	Game.pop = 40
	Game.res["grain"] = 300
	Game.res["fuel"] = 50
	near = World.find_tile(func(c, t): return t["t"] == "sand" and c.distance_to(hq) > 8 and c.distance_to(hq) < 14 and Game.poi_kind(c) == "" \
		and not Game.route("foot", hq, c).is_empty())
	near2 = World.find_tile(func(c, t): return t["t"] == "sand" and c.distance_to(hq) > 8 and c.distance_to(hq) < 14 and Game.poi_kind(c) == "" \
		and not Game.route("foot", hq, c).is_empty() and c.distance_to(near) > 6)
	far = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 30 and c.distance_to(hq) < 45 \
		and not Game.route("foot", hq, c).is_empty())
	assert_ne(near, Vector2i(-1, -1))
	assert_ne(near2, Vector2i(-1, -1))
	assert_ne(far, Vector2i(-1, -1))


func after_each() -> void:
	if map != null and map.playing:
		map.finish_replay()
	SeasonReplay.mode = "off"


## A trade caravan walking toward `to`: what still walks at END SEASON.
func _caravan(to: Vector2i) -> Dictionary:
	var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", hq, to)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.stage = "out"
	u.path = Game.route("foot", hq, to).slice(1)
	Units.units.append(u)
	return u


func test_ordering_a_party_to_walk_plays_the_walk_at_once() -> void:
	assert_false(map.playing)
	Units.send("scout", "foot", near)
	var u: Dictionary = Units.units[-1]
	assert_true(map.playing, "no END SEASON needed")
	assert_true(Game.replaying)
	assert_true(Game.replay_is_walk)
	assert_true(map.replay.get("walk", false))
	assert_eq(map.replay.actors.size(), 1)
	assert_true(map.replay_ids.has(u.id))
	assert_eq(map.replay.actors[0].kind, "scav")


func test_the_walk_plays_at_the_normal_pace() -> void:
	Units.send("scout", "foot", near)
	var days: float = map.replay.actors[0].trail.back()[1]
	assert_eq(map.replay_secs, SeasonReplay.SECONDS["normal"], "the same pace as a season's replay")
	var tail := SeasonReplay.POP_SECONDS if not map.replay.events.is_empty() else 0.0
	assert_almost_eq(map.replay_length, days / (Data.SEASON_DAYS / 3.0) + tail, 0.001, "a season's 40 days take 3 seconds")
	assert_lt(map.replay_length, 3.0, "a walk of a day or two is much shorter than a season")


func test_the_clock_runs_the_party_along_its_route_and_the_walk_ends_by_itself() -> void:
	Units.send("scout", "foot", near)
	var trail: Array = map.replay.actors[0].trail
	assert_eq(map.replay_day(), 0.0)
	map.clock = map.replay_length / 2.0
	var halfway := SeasonReplay.position_at(trail, map.replay_day())
	assert_ne(halfway, Vector2(trail[0][0]), "it has left the start")
	assert_ne(halfway, Vector2(trail.back()[0]), "and has not arrived")
	map.clock = 0.0
	var done := watch(Game, "replay_done")
	assert_true(await wait_until(func(): return not map.playing, 8.0), "the walk finishes by itself")
	assert_eq(done.count, 1)
	assert_false(Game.replaying)
	assert_false(Game.replay_is_walk)
	assert_eq(map.replay_ids.size(), 0)


func test_with_the_animation_off_nothing_plays() -> void:
	SeasonReplay.mode = "off"
	Units.send("scout", "foot", near)
	assert_false(map.playing)
	assert_false(Game.replaying)


func test_two_parties_sent_one_after_the_other_are_seen_walking_together() -> void:
	Units.send("scout", "foot", near)
	var first: Dictionary = Units.units[-1]
	map.clock = 0.5   # half a second into the first one's walk
	var offset: float = map.replay_day()
	Units.send("scav", "foot", near2)
	var second: Dictionary = Units.units[-1]
	assert_eq(map.replay.actors.size(), 2, "both are in the one replay")
	assert_true(map.replay_ids.has(first.id))
	assert_true(map.replay_ids.has(second.id))
	var joined: Dictionary = map._replay_actor(second.id)
	assert_almost_eq(joined.trail[0][1], offset, 0.001, "the second sets off from the day the first had got to")
	var latest := 0.0
	for a in map.replay.actors:
		latest = maxf(latest, a.trail.back()[1])
	assert_almost_eq(map.replay.end_day, latest, 0.001)
	assert_almost_eq(map.replay_length, SeasonReplay.length(map.replay, 3.0), 0.001, "and the replay lasts until the last has stopped")
	assert_true(map.playing)


func test_a_party_that_walks_again_while_its_walk_plays_carries_on_along_one_trail() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.stage, "out", "the walk is longer than a turn")
	var before: int = map.replay.actors[0].trail.size()
	u.move_left = float(Data.SEASON_DAYS)
	Units.continue_orders(u.id)
	assert_eq(map.replay.actors.size(), 1, "still one party in it")
	var trail: Array = map.replay.actors[0].trail
	assert_gt(trail.size(), before, "its trail grew")
	for i in range(1, trail.size()):
		assert_ge(trail[i][1], trail[i - 1][1], "the days only go up")
	assert_eq(trail.back()[0], u.pos, "and it ends where the party stands")


func test_end_season_during_a_walk_skips_it_and_ends_the_season() -> void:
	Units.send("scout", "foot", near)
	assert_true(Game.replay_is_walk)
	var season := Game.season
	hud.end_season_pressed()
	assert_eq(Game.season, season + 1, "a walk is not a season: the press ended it")
	assert_false(map.playing, "and the walk is over")


func test_a_click_or_enter_skips_a_walk() -> void:
	Units.send("scout", "foot", near)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	map._unhandled_input(click)
	assert_false(map.playing)
	Units.send("scav", "foot", near2)
	assert_true(map.playing)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	map._unhandled_input(enter)
	assert_false(map.playing)


func test_a_season_still_replays_what_walks_at_end_season_and_a_new_walk_ends_it() -> void:
	var caravan := _caravan(far)
	hud.end_season_pressed()
	assert_true(map.playing, "a caravan walked at END SEASON")
	assert_false(Game.replay_is_walk, "that is a season's replay")
	assert_true(map.replay_ids.has(caravan.id))
	Units.send("scout", "foot", near)
	assert_true(Game.replay_is_walk, "a walk started now replaces it")
	assert_false(map.replay_ids.has(caravan.id))
	assert_eq(map.replay.actors.size(), 1)


func test_a_parked_party_bobs_while_it_waits_for_orders() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.stage, "out")
	map.finish_replay()
	assert_true(map._is_parked(u), "waiting for the next turn's days")
	u.stage = "site"
	assert_false(map._is_parked(u), "but not in the middle of a search")
