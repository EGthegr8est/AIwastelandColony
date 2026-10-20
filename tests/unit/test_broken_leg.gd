extends "res://tests/framework/test_case.gd"
## The broken leg: a foot or horseback party that enters rock or a steep incline may lose someone to one (Data.LEG). It slows the whole party
## until the party gets home, or until that person dies. A Clumsy survivor is more likely to be the one, a Light-Footed party less likely.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i
var rock: Vector2i
var steep: Vector2i
var sand: Vector2i


func before_each() -> void:
	World.new_game(3)
	Units.units = []
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	rock = _make("rock", "")
	steep = _make("rock", "steep")
	sand = _make("sand", "")


## A land tile of the given ground and slope, made by changing a plain one a safe way from home.
func _make(ground: String, slope: String) -> Vector2i:
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		var t: Dictionary = Game.tiles[i]
		if t["t"] in ["sand", "scrub", "dunes"] and t["b"] == "" and Game.slopes[i] == slope and c.distance_to(Vector2(hq)) > 8 \
				and not (c == rock or c == steep or c == sand):
			t["t"] = ground
			return c
	return Vector2i(-1, -1)


## A party of `crew` going `mover`, everyone with just the Veteran trait (no luck with the feet either way).
func _party(mover := "foot", crew := 3) -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, mover, hq, hq)
	u.crew = crew
	u.survivors = Units._make_crew(crew)
	for s in u.survivors:
		s.traits = ["veteran"]
	Units.units.append(u)
	return u


func _heal(u: Dictionary) -> void:
	for s in u.survivors:
		s["leg"] = false


## How many times out of `n` a fresh party that has just entered `c` loses someone to a broken leg.
func _breaks(u: Dictionary, c: Vector2i, n: int) -> int:
	seed(20261013)
	var count := 0
	for k in n:
		_heal(u)
		if Units._climb_check(u, c):
			count += 1
	return count


# ---------------------------------------------------------------- the chance

func test_a_foot_party_has_two_chances_in_a_hundred_on_each_rock_tile() -> void:
	var count := _breaks(_party(), rock, 6000)
	assert_between(count, 90, 150, "about 2% of 6000 is 120")


func test_a_steep_incline_is_twice_as_dangerous_as_rock() -> void:
	var count := _breaks(_party(), steep, 6000)
	assert_between(count, 200, 280, "about 4% of 6000 is 240")


func test_a_horseback_party_runs_the_same_risk() -> void:
	var count := _breaks(_party("horse"), rock, 6000)
	assert_between(count, 90, 150)


func test_plain_ground_is_safe() -> void:
	assert_eq(_breaks(_party(), sand, 3000), 0)


func test_war_rigs_boats_and_planes_never_break_a_leg() -> void:
	for mover in ["car", "boat", "plane"]:
		var u := _party(mover)
		assert_eq(_breaks(u, steep, 2000), 0, mover)


func test_a_light_footed_party_has_half_the_chance() -> void:
	var u := _party()
	u.survivors[0].traits = ["light_footed"]
	var count := _breaks(u, rock, 8000)
	assert_between(count, 60, 140, "about 1% of 8000 is 80")


func test_a_party_with_nobody_named_in_it_is_left_alone() -> void:
	var u := _party()
	u.survivors = []
	assert_false(Units._climb_check(u, steep))


# ---------------------------------------------------------------- who

func test_a_clumsy_survivor_is_twice_as_likely_to_be_the_one() -> void:
	var u := _party()
	u.survivors[0].traits = ["clumsy"]
	seed(77)
	var hits := {0: 0, 1: 0, 2: 0}
	var done := 0
	while done < 600:
		_heal(u)
		if Units._climb_check(u, steep):
			for k in 3:
				if u.survivors[k].get("leg", false):
					hits[k] += 1
			done += 1
	var share: float = hits[0] / 600.0
	assert_between(share, 0.42, 0.58, "the Clumsy one is 2 of 4 shares: %s" % hits)


func test_nobody_breaks_a_second_leg_and_a_party_of_cripples_is_left_alone() -> void:
	var u := _party()
	for s in u.survivors:
		s["leg"] = true
	assert_false(Units._climb_check(u, steep))
	seed(5)
	for k in 200:
		assert_false(Units._climb_check(u, steep))


# ---------------------------------------------------------------- the slowdown

func test_the_slowdown_grows_with_each_broken_leg_but_stops_at_double() -> void:
	var u := _party("foot", 5)
	assert_eq(Units.leg_slowdown(u), 1.0)
	var wanted := [1.5, 1.75, 2.0, 2.0, 2.0]
	for k in 5:
		u.survivors[k]["leg"] = true
		assert_eq(Units.broken_legs(u), k + 1)
		assert_eq(Units.leg_slowdown(u), wanted[k], "%d broken" % (k + 1))


func test_the_party_speed_is_the_load_times_the_leg() -> void:
	var u := _party()
	u.survivors[0]["leg"] = true
	assert_eq(Units.party_slowdown(u), Units.load_slowdown(u) * 1.5)


func test_a_slowed_party_takes_longer_over_the_same_ground() -> void:
	var u := _party()
	var path := []
	for k in 8:
		path.append(sand + Vector2i(k, 0))
		Game.tile(path[k])["t"] = "sand"
	var fast: float = Units.arrival_days("foot", path, Units.party_slowdown(u))[-1]
	u.survivors[1]["leg"] = true
	var slow: float = Units.arrival_days("foot", path, Units.party_slowdown(u))[-1]
	assert_almost_eq(slow, fast * 1.5, 0.001)


func test_a_broken_leg_slows_the_walk_in_the_middle_of_a_season() -> void:
	# a long road of rock. A season is 40 days and a rock tile costs 1.4 on foot, so a party covers 28 tiles a season: with a 2% chance a
	# tile, a break is likely but not certain, so try a few seasons until one happens
	var u := _party()
	var path := []
	var start := Vector2i(hq.x, hq.y + 6)
	for k in 90:
		var c := start + Vector2i(k % 30, k / 30)
		Game.tile(c)["t"] = "rock"
		Game.slopes[Game.idx(c)] = ""
		Game.tile(c)["b"] = ""
		path.append(c)
	var broke := false
	for sd in range(1, 80):
		seed(sd)
		_heal(u)
		u.pos = start
		u.path = path.slice(1)
		u.move_left = float(Data.SEASON_DAYS)
		Units._advance(u)
		if Units.broken_legs(u) > 0:
			broke = true
			var covered: int = path.find(u.pos)
			assert_lt(covered, 28, "slower than a party that never breaks a leg, which covers 28 tiles in 40 days")
			assert_gt(Units.party_slowdown(u), 1.4, "and the party is slowed from then on")
			break
	assert_true(broke, "somebody broke a leg within 79 seasons of rock")


func test_the_log_says_who_where_and_what_happens() -> void:
	var u := _party()
	Game.log_lines = []
	seed(11)
	while not Units._climb_check(u, rock):
		_heal(u)
	var line: String = Game.log_lines[-1]
	assert_true(" broke a leg on the rocks at %d,%d." % [rock.x, rock.y] in line, line)
	assert_true("slows down until it gets home" in line, line)


func test_a_horse_goes_lame_instead() -> void:
	var u := _party("horse")
	Game.log_lines = []
	seed(11)
	while not Units._climb_check(u, steep):
		_heal(u)
	var line: String = Game.log_lines[-1]
	assert_true("'s horse went lame on the steep slope" in line, line)


# ---------------------------------------------------------------- how it ends

func test_it_heals_when_the_party_gets_home() -> void:
	var u := _party()
	u.survivors[0]["leg"] = true
	u.stage = "back"
	u.pos = hq
	u.carry = {}
	Game.log_lines = []
	var pop: int = Game.pop
	Units._come_home(u)
	assert_eq(Game.pop, pop + 3, "they rejoin the colony")
	assert_true(Game.log_lines.any(func(l): return "healed at home" in l), "and the log says the leg healed")


func test_it_ends_if_the_injured_survivor_dies_on_the_road() -> void:
	var u := _party()
	u.survivors[2]["leg"] = true
	assert_eq(Units.leg_slowdown(u), 1.5)
	Units._casualty(u, u.survivors[2])
	assert_eq(Units.broken_legs(u), 0)
	assert_eq(Units.leg_slowdown(u), 1.0, "nobody left to carry")


func test_the_survivor_line_says_broken_leg() -> void:
	var u := _party()
	assert_false(", broken leg" in Units.survivor_line(u.survivors[0]))
	u.survivors[0]["leg"] = true
	assert_true(", broken leg" in Units.survivor_line(u.survivors[0]))


func test_the_leg_is_saved_with_the_party() -> void:
	var u := _party()
	u.survivors[1]["leg"] = true
	Game.save_game("leg_test")
	World.new_game(21)
	assert_true(Game.load_game("leg_test"))
	var found := false
	for p in Units.units:
		if p.job == "scav":
			found = Units.broken_legs(p) == 1
	assert_true(found, "the loaded party still has its broken leg")


func test_a_new_party_has_nobody_with_a_broken_leg() -> void:
	var u := _party()
	for s in u.survivors:
		assert_false(s.get("leg", true), s.name)


# ---------------------------------------------------------------- the flash

func test_a_break_during_a_season_replay_flashes_the_tile() -> void:
	var u := _party()
	Units._recording = true
	Units.replay = {"actors": [], "events": [], "reveals": []}
	seed(11)
	while not Units._climb_check(u, rock):
		_heal(u)
	Units._recording = false
	assert_true(Units.replay.events.any(func(e): return e.kind == "snap" and e.cell == rock), "a snap flash is recorded at the tile")


func assert_between(got, low, high, msg := "") -> void:
	assert_true(got >= low and got <= high, "%s (got %s, wanted %s to %s)" % [msg, got, low, high])
