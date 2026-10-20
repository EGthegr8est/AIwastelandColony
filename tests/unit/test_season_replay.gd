extends "res://tests/framework/test_case.gd"
## The season as the map plays it back: the plain rules of a replay (where a unit is on a given day, how long it takes, the
## march of troops), what Units notes while it walks everybody, and what END SEASON and a raid hand over to the map.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var far: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	Units.crash_survival = Data.CRASH_SURVIVAL
	Game.res["grain"] = 200
	Game.res["fuel"] = 50
	hq = Game.home(Data.PLAYER)
	# Dry land 25 to 40 tiles out that a war rig and a party on foot can both reach
	far = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 25 and c.distance_to(hq) < 40 \
		and not Game.route("car", hq, c).is_empty() and not Game.route("foot", hq, c).is_empty())
	assert_ne(far, Vector2i(-1, -1), "needs a reachable tile far from home")


func after_each() -> void:
	SeasonReplay.mode = "off"
	Units.dice = load("res://scripts/dice.gd").new()


func _actor(id: int) -> Dictionary:
	for a in Units.replay.actors:
		if a.id == id:
			return a
	return {}


## A trade caravan walking toward `to`. Your Scavenger Parties walk when you order it, not at END SEASON, so a caravan is what the
## season's replay has to show.
func _walker(mover: String, to: Vector2i, from := Vector2i(-1, -1)) -> Dictionary:
	var start: Vector2i = hq if from == Vector2i(-1, -1) else from
	var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, mover, start, to)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.stage = "out"
	u.path = Game.route(mover, start, to).slice(1)
	Units.units.append(u)
	return u


func _events(kind: String) -> Array:
	return Units.replay.events.filter(func(e): return e.kind == kind)


# ---------------------------------------------------------------- where a unit is on a given day

func test_a_unit_is_between_two_tiles_halfway_through_a_step() -> void:
	var trail := [[Vector2i(0, 0), 0.0], [Vector2i(1, 0), 4.0], [Vector2i(1, 1), 8.0]]
	assert_eq(SeasonReplay.position_at(trail, 2.0), Vector2(0.5, 0.0))
	assert_eq(SeasonReplay.position_at(trail, 6.0), Vector2(1.0, 0.5))
	assert_eq(SeasonReplay.position_at(trail, 4.0), Vector2(1.0, 0.0))


func test_before_the_start_and_after_the_end_a_unit_stays_where_it_was() -> void:
	var trail := [[Vector2i(3, 3), 0.0], [Vector2i(4, 3), 4.0]]
	assert_eq(SeasonReplay.position_at(trail, -5.0), Vector2(3, 3))
	assert_eq(SeasonReplay.position_at(trail, 0.0), Vector2(3, 3))
	assert_eq(SeasonReplay.position_at(trail, 30.0), Vector2(4, 3))
	assert_eq(SeasonReplay.position_at([[Vector2i(7, 7), 0.0]], 12.0), Vector2(7, 7), "a unit that never moved")


func test_a_step_that_took_no_time_does_not_divide_by_zero() -> void:
	var trail := [[Vector2i(0, 0), 0.0], [Vector2i(1, 0), 0.0]]
	assert_eq(SeasonReplay.position_at(trail, 0.0), Vector2(0, 0))
	assert_eq(SeasonReplay.position_at(trail, 1.0), Vector2(1, 0))


func test_a_unit_is_walking_only_between_its_first_and_last_step() -> void:
	var trail := [[Vector2i(0, 0), 0.0], [Vector2i(1, 0), 4.0]]
	assert_false(SeasonReplay.moving_at(trail, 0.0))
	assert_true(SeasonReplay.moving_at(trail, 2.0))
	assert_false(SeasonReplay.moving_at(trail, 4.0))
	assert_false(SeasonReplay.moving_at([[Vector2i(0, 0), 0.0]], 2.0), "a unit with nowhere to go")


func test_the_dust_is_the_tiles_just_left_newest_first() -> void:
	var trail := [[Vector2i(0, 0), 0.0], [Vector2i(1, 0), 2.0], [Vector2i(2, 0), 4.0], [Vector2i(3, 0), 6.0]]
	var dust := SeasonReplay.recent(trail, 5.0, 4.0)
	assert_eq(dust.size(), 2, "the tile at day 4 and the one at day 2; day 0 is too long ago; day 6 hasn't happened")
	assert_eq(dust[0][0], Vector2i(2, 0))
	assert_eq(dust[0][1], 1.0)
	assert_eq(dust[1][0], Vector2i(1, 0))
	assert_eq(dust[1][1], 3.0)


# ---------------------------------------------------------------- when it ends, and how long it takes

func test_the_replay_ends_when_the_last_unit_stops_and_fills_in_the_end_markers() -> void:
	var r := {"actors": [
			{"id": 1, "trail": [[Vector2i(0, 0), 0.0], [Vector2i(2, 0), 14.0]], "gone_day": SeasonReplay.AT_END},
			{"id": 2, "trail": [[Vector2i(5, 5), 0.0], [Vector2i(5, 6), 9.0]], "gone_day": SeasonReplay.STILL}],
		"events": [{"kind": "clash", "cell": Vector2i(2, 0), "day": SeasonReplay.AT_END}, {"kind": "ruin", "cell": Vector2i(5, 6), "day": 9.0}]}
	SeasonReplay.settle(r)
	assert_eq(r.end_day, 14.0)
	assert_eq(r.actors[0].gone_day, 14.0, "left when the walking was done")
	assert_eq(r.actors[1].gone_day, SeasonReplay.STILL, "this one never left")
	assert_eq(r.events[0].day, 14.0)
	assert_eq(r.events[1].day, 9.0)
	SeasonReplay.settle(r)
	assert_eq(r.end_day, 14.0, "settling twice changes nothing")


func test_a_season_where_nobody_walks_and_nothing_happens_has_nothing_to_play() -> void:
	assert_false(SeasonReplay.has_motion({}))
	var still := {"actors": [{"trail": [[Vector2i(1, 1), 0.0]]}], "events": []}
	assert_false(SeasonReplay.has_motion(still))
	var walks := {"actors": [{"trail": [[Vector2i(1, 1), 0.0], [Vector2i(2, 1), 1.0]]}], "events": []}
	assert_true(SeasonReplay.has_motion(walks))
	var fight := {"actors": [{"trail": [[Vector2i(1, 1), 0.0]]}], "events": [{"kind": "clash"}]}
	assert_true(SeasonReplay.has_motion(fight), "an ambush on a party standing still is worth showing")


func test_a_whole_season_takes_the_chosen_time_and_half_a_season_half_that() -> void:
	var whole := {"end_day": Data.SEASON_DAYS, "events": []}
	var half := {"end_day": Data.SEASON_DAYS / 2.0, "events": []}
	assert_almost_eq(SeasonReplay.length(whole, SeasonReplay.SECONDS["normal"]), 3.0, 0.0001)
	assert_almost_eq(SeasonReplay.length(half, SeasonReplay.SECONDS["normal"]), 1.5, 0.0001)
	assert_almost_eq(SeasonReplay.length(whole, SeasonReplay.SECONDS["fast"]), 1.2, 0.0001)
	var flash := {"end_day": Data.SEASON_DAYS, "events": [{"kind": "clash"}]}
	assert_almost_eq(SeasonReplay.length(flash, 3.0), 3.0 + SeasonReplay.POP_SECONDS, 0.0001, "the last flash gets its moment")


func test_the_walk_plays_at_normal_speed_and_has_no_setting() -> void:
	SeasonReplay.mode = "normal"
	assert_eq(SeasonReplay.seconds(), 3.0, "a whole season takes 3 seconds to play")
	SeasonReplay.mode = "off"
	assert_eq(SeasonReplay.seconds(), 0.0, "tests turn the walk off so they do not wait for it")
	var names: Array = SeasonReplay.new().get_method_list().map(func(method): return method.name)
	for gone in ["cycle", "mode_text", "load_mode", "save_mode"]:
		assert_false(names.has(gone), "SeasonReplay no longer has %s: the speed is not a setting" % gone)


# ---------------------------------------------------------------- what Units notes while it walks

func test_a_walk_is_noted_tile_by_tile_with_the_day_each_tile_was_reached() -> void:
	var u := _walker("foot", far)
	var start: Vector2i = u.pos
	Units.season_turn()
	var a := _actor(u.id)
	assert_false(a.is_empty(), "the caravan is in the replay")
	assert_eq(a.kind, "caravan")
	assert_eq(a.owner, Data.PLAYER)
	assert_eq(a.trail[0], [start, 0.0], "it starts where it was, on day 0")
	assert_gt(a.trail.size(), 5, "a season's walk is many tiles")
	assert_eq(a.trail.back()[0], u.pos, "and ends where the party now stands")
	for i in range(1, a.trail.size()):
		assert_ge(a.trail[i][1], a.trail[i - 1][1], "the days only go up")
		assert_le(Vector2(a.trail[i][0] - a.trail[i - 1][0]).length(), 1.5, "one tile at a time")
	assert_le(a.trail.back()[1], Data.SEASON_DAYS, "all within the season")
	assert_eq(Units.replay.end_day, a.trail.back()[1])


func test_a_war_rig_gets_through_each_tile_faster_than_a_party_on_foot() -> void:
	var foot := _walker("foot", far)
	var rig := _walker("car", far)
	Units.season_turn()
	var on_foot := _actor(foot.id)
	var in_rig := _actor(rig.id)
	var foot_pace: float = on_foot.trail.back()[1] / (on_foot.trail.size() - 1)
	var rig_pace: float = in_rig.trail.back()[1] / (in_rig.trail.size() - 1)
	assert_lt(rig_pace, foot_pace / 2.0, "days a tile: the rig is far quicker")
	assert_lt(in_rig.trail.back()[1], on_foot.trail.back()[1], "so it is in place days before the party on foot")


func test_a_party_standing_still_is_in_the_replay_but_does_not_move() -> void:
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", hq + Vector2i(3, 0), hq + Vector2i(3, 0))
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.stage = "station"
	u.food = {"grain": 50}
	Units.units.append(u)
	Units.season_turn()
	var a := _actor(u.id)
	assert_eq(a.trail.size(), 1)
	assert_true(a.parked, "on station")
	assert_false(SeasonReplay.has_motion(Units.replay), "nobody walks, so there is nothing to play")


func test_a_party_that_gets_home_with_loot_leaves_the_map_there_with_a_glint() -> void:
	var from := hq + Vector2i(6, 0)
	var u := _walker("foot", hq, from)
	u.stage = "back"
	u.carry = {"gold": 5}
	Units.season_turn()
	assert_true(u.get("gone", false), "it got home")
	var a := _actor(u.id)
	assert_eq(a.trail.back()[0], hq)
	assert_eq(a.gone_day, a.trail.back()[1], "it leaves the map the moment it arrives")
	var home := _events("home")
	assert_eq(home.size(), 1)
	assert_eq(home[0].cell, hq)
	assert_eq(home[0].day, a.gone_day)


func test_a_party_that_comes_home_empty_handed_has_no_glint() -> void:
	var from := hq + Vector2i(6, 0)
	var u := _walker("foot", hq, from)
	u.stage = "back"
	Units.season_turn()
	assert_true(u.get("gone", false))
	assert_eq(_events("home").size(), 0)


func test_a_fight_at_the_end_of_the_season_is_shown_once_the_walking_is_done() -> void:
	var party: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq + Vector2i(4, 0), hq)
	party.crew = 3
	party.survivors = Units._make_crew(3)
	Units.units.append(party)
	Units._spawn_band(hq + Vector2i(5, 0), 2)
	var band: Dictionary = Units.units[-1]
	Units.dice = ForcedDice.new([15, 5], [3])   # the party beats the band
	Units._record_start()
	Units._ambushes()
	Units._recording = false
	SeasonReplay.settle(Units.replay)
	assert_true(band.get("gone", false), "the band is driven off")
	var clash := _events("clash")
	assert_eq(clash.size(), 1)
	assert_eq(clash[0].cell, party.pos)
	assert_eq(clash[0].day, Units.replay.end_day, "when the walking is done")
	assert_eq(_actor(band.id).gone_day, Units.replay.end_day, "and the band is on the map until then")


func test_a_vehicle_that_runs_dry_puffs_smoke() -> void:
	Game.vehicles["car"] = 1
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "car", hq + Vector2i(2, 0), hq + Vector2i(2, 0))
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.stage = "station"
	u.fuel = 0.0
	u.food = {"grain": 50}
	Units.units.append(u)
	Units.season_turn()
	var smoke := _events("smoke")
	assert_eq(smoke.size(), 1)
	assert_eq(smoke[0].cell, hq + Vector2i(2, 0))


func test_nothing_is_noted_outside_the_season() -> void:
	Units.replay = {}
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	u.crew = 1
	u.survivors = Units._make_crew(1)
	u.carry = {"gold": 3}
	Units.units.append(u)
	Units._come_home(u)   # a party that gets home when you press a button, not when the season turns
	assert_eq(Units.replay, {}, "no replay was started, and none was written to")


func test_ground_a_party_uncovers_is_noted_with_the_day_it_was_reached() -> void:
	_walker("foot", far)
	Units.season_turn()
	var reveals: Array = Units.replay.reveals
	assert_gt(reveals.size(), 20, "a party walking into the unknown uncovers ground")
	var seen := {}
	var last := 0.0
	for r in reveals:
		assert_false(seen.has(r[0]), "each tile is uncovered once")
		seen[r[0]] = true
		assert_not_null(Game.memory[Data.PLAYER][Game.idx(r[0])], "and it is now known")
		assert_ge(r[1], last, "in the order the party walked")
		assert_le(r[1], Data.SEASON_DAYS)
		last = r[1]


func test_revealing_ground_says_which_tiles_were_new() -> void:
	var c := World.find_tile(func(cell, t): return Game.memory[Data.PLAYER][Game.idx(cell)] == null \
		and Game.in_bounds(cell + Vector2i(3, 3)))
	assert_ne(c, Vector2i(-1, -1))
	var fresh := Game.reveal(Data.PLAYER, c, 2)
	assert_gt(fresh.size(), 0)
	assert_has(fresh, c)
	assert_eq(Game.reveal(Data.PLAYER, c, 2), [], "nothing is new the second time")


# ---------------------------------------------------------------- what END SEASON hands to the map

func test_ending_the_season_hands_the_replay_to_the_map_with_the_old_sight() -> void:
	var before: PackedByteArray = Game.sight[Data.PLAYER].duplicate()
	var w := watch(Game, "season_played")
	Game.end_season()
	assert_eq(w.count, 1)
	assert_eq(w.emissions[0][0], Units.replay)
	assert_eq(Units.replay.sight_before, before, "what you could see when the season began")


func test_ending_the_season_does_not_wait_for_a_replay() -> void:
	assert_false(Game.replaying)
	var season := Game.season
	Game.end_season()
	assert_eq(Game.season, season + 1)


