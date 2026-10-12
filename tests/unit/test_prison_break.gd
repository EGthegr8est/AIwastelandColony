extends "res://tests/framework/test_case.gd"
## Prison breaks: more than PRISON_HIGH prisoners and fewer than PRISON_OUTPOSTS of your outposts within
## PRISON_CIRCLE tiles of the HQ, checked when the season's upkeep runs.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	for r in ["grain", "veg", "meat", "wood", "stone", "metal", "gold", "fuel"]:
		Game.res[r] = 1000   # the upkeep must not starve anyone or desert any troops
	Game.troops = 10


## An outpost on a free tile of yours `dist` tiles from the HQ (on your land, so it can stand there).
func _outpost_at(dist: int) -> Vector2i:
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water" and int(round(c.distance_to(hq))) == dist and c.distance_to(hq) <= dist + 0.5:
			Game.tile(c)["b"] = "outpost"
			return c
	# no owned tile that far out: claim one
	var far := Vector2i(hq.x + dist, hq.y)
	Game.tile(far)["o"] = Data.PLAYER
	Game.tile(far)["b"] = "outpost"
	return far


func test_the_constants_are_the_ones_the_player_chose() -> void:
	assert_eq([Data.PRISON_HIGH, Data.PRISON_CIRCLE, Data.PRISON_OUTPOSTS], [4, 6, 2])


func test_four_prisoners_are_safe_and_five_are_not() -> void:
	Game.prisoners = 4
	assert_false(Game.prison_break_due())
	Game.prisoners = 5
	assert_true(Game.prison_break_due())


func test_two_outposts_in_the_circle_keep_the_pens_shut_but_one_does_not() -> void:
	Game.prisoners = 8
	_outpost_at(2)
	assert_eq(Game.outposts_in_circle(), 1)
	assert_true(Game.prison_break_due(), "one outpost is not enough")
	_outpost_at(3)
	assert_eq(Game.outposts_in_circle(), 2)
	assert_false(Game.prison_break_due())


func test_outposts_beyond_the_circle_do_not_count() -> void:
	Game.prisoners = 8
	var near := _outpost_at(2)
	var far := Vector2i(hq.x + Data.PRISON_CIRCLE + 2, hq.y)
	Game.tile(far)["o"] = Data.PLAYER
	Game.tile(far)["b"] = "outpost"
	assert_ne(near, far)
	assert_eq(Game.outposts_in_circle(), 1, "the far one is outside the circle")
	assert_true(Game.prison_break_due())
	var edge := Vector2i(hq.x + Data.PRISON_CIRCLE, hq.y)
	Game.tile(edge)["o"] = Data.PLAYER
	Game.tile(edge)["b"] = "outpost"
	assert_eq(Game.outposts_in_circle(), 2, "exactly 6 tiles out still counts")


func test_only_your_own_outposts_count() -> void:
	Game.prisoners = 8
	_outpost_at(2)
	var other := Vector2i(hq.x + 3, hq.y)
	Game.tile(other)["o"] = Data.AI
	Game.tile(other)["b"] = "outpost"
	assert_eq(Game.outposts_in_circle(), 1)


func test_a_break_frees_half_rounded_up_costs_a_guard_and_makes_a_raider_band() -> void:
	Game.prisoners = 5
	Game._prison_break()
	assert_eq(Game.prisoners, 2, "5 prisoners: 3 escape")
	assert_eq(Game.troops, 9)
	var bands := Units.units.filter(func(u): return u.job == "band")
	assert_eq(bands.size(), 1)
	assert_eq(bands[0].strength, 3, "as strong as they are many")
	assert_eq(bands[0].owner, Data.NONE)
	var spot: Vector2i = bands[0].pos
	assert_eq(Game.tile(spot)["o"], Data.NONE)
	assert_true(Game.borders(spot, Data.PLAYER), "at the edge of your land")
	assert_ne(Game.tile(spot)["t"], "water")
	assert_true(Game.log_lines.any(func(l): return l.contains("PRISON BREAK")))


func test_a_break_cannot_take_the_last_guard_below_zero() -> void:
	Game.troops = 0
	Game.prisoners = 6
	Game._prison_break()
	assert_eq(Game.troops, 0)
	assert_eq(Game.prisoners, 3)


func test_the_season_upkeep_runs_a_break_when_it_is_due() -> void:
	Game.prisoners = 6
	Game._upkeep()
	assert_eq(Game.prisoners, 3)
	assert_eq(Units.units.filter(func(u): return u.job == "band").size(), 1)


func test_the_season_upkeep_leaves_a_guarded_pen_alone() -> void:
	Game.prisoners = 6
	_outpost_at(2)
	_outpost_at(3)
	Game.troops = 10   # and the old revolt (prisoners over 3 times the troops) is not in play either
	Game._upkeep()
	assert_eq(Game.prisoners, 6)
	assert_eq(Units.units.filter(func(u): return u.job == "band").size(), 0)


func test_the_old_revolt_still_happens_when_the_new_rule_does_not_apply() -> void:
	_outpost_at(2)
	_outpost_at(3)
	Game.troops = 1
	Game.prisoners = 20   # more than 3 times the troops
	seed(3)
	var revolted := false
	for i in 40:
		Game.prisoners = 20
		Game.troops = 1
		Game._upkeep()
		if Game.prisoners < 20:
			revolted = true
			break
	assert_true(revolted, "a 30% chance a season turns up within 40 seasons")
	assert_eq(Units.units.filter(func(u): return u.job == "band").size(), 0, "the old revolt makes no band")


func test_a_season_with_a_break_skips_the_old_revolt() -> void:
	Game.troops = 1
	Game.prisoners = 20   # a break is due AND the old revolt could fire
	seed(1)
	Game._upkeep()
	assert_eq(Game.prisoners, 10, "only the break happened: half, once")
	assert_eq(Game.troops, 0, "and one guard, once")


func test_a_break_with_nowhere_to_stand_scatters_the_prisoners() -> void:
	for c in Game.owned(Data.PLAYER):
		for n in Game.neighbors(c):
			if Game.tile(n)["o"] == Data.NONE:
				Game.tile(n)["o"] = Data.TOWN   # nothing free borders your land
	Game.prisoners = 6
	Game._prison_break()
	assert_eq(Game.prisoners, 3)
	assert_eq(Units.units.filter(func(u): return u.job == "band").size(), 0)
	assert_true(Game.log_lines.any(func(l): return l.contains("scattered")))
