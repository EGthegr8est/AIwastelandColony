extends "res://tests/framework/test_case.gd"
## Forming a Scavenger Party at your HQ (Units.form_party): the survivors you choose, or the healthiest, a food pack, the next free number, and it
## waits there for orders until you send it by clicking where it should go. A party at home can be disbanded with a recall. The settlement is not
## somewhere to send a party, so no dotted route line is drawn to it.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	Game.pop = 30
	Game.res["grain"] = 100
	Game.res["fuel"] = 50


func _lead(perks := []) -> void:
	Game.leader_info = Leaders.fill("builder", {"name": "Test Leader", "perks": perks, "flaw": ""})


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


func test_a_party_is_formed_at_the_hq_and_waits_for_orders() -> void:
	var pop := Game.pop
	var grain: int = Game.res["grain"]
	var u := Units.form_party("foot")
	assert_false(u.is_empty())
	assert_eq(u.job, "scout")
	assert_eq(u.pos, hq)
	assert_eq(u.stage, "station")
	assert_eq(u.crew, 3)
	assert_eq(u.survivors.size(), 3)
	assert_eq(u.number, 1)
	assert_true(u.path.is_empty(), "no orders yet")
	assert_eq(u.move_left, float(Data.SEASON_DAYS))
	assert_eq(Game.pop, pop - 3, "three survivors are away")
	assert_eq(Units.food_total(u), Data.SCOUT_PACK)
	assert_eq(Game.res["grain"], grain - Data.SCOUT_PACK, "the pack comes from the stores")
	assert_true(Units.units.has(u))
	assert_true(_log_has("formed at your HQ"))
	for s in u.survivors:
		assert_eq(s.state, "away")
		assert_true(Game.roster.has(s), "the party holds the roster's own entries")


func test_the_uninjured_are_picked_when_you_leave_it_to_the_game() -> void:
	for i in 5:
		Game.roster[i].leg = true
	var u := Units.form_party("foot")
	for s in u.survivors:
		assert_false(s.leg or s.hurt, "%s is hurt" % s.name)


func test_the_survivors_you_choose_are_the_ones_who_go() -> void:
	var picked: Array = [Game.roster[4].sid, Game.roster[7].sid]
	var u := Units.form_party("foot", picked)
	assert_eq(u.crew, 2)
	assert_eq(u.survivors.map(func(s): return s.sid), picked)
	assert_eq(Game.roster[4].state, "away")
	assert_eq(Game.roster[0].state, "home")


func test_a_second_party_gets_the_next_number_and_a_freed_number_is_used_again() -> void:
	var first := Units.form_party("foot")
	var second := Units.form_party("foot")
	assert_eq([first.number, second.number], [1, 2])
	Units.recall_scouts(first.id)   # at home already: it is disbanded
	var third := Units.form_party("foot")
	assert_eq(third.number, 1, "the freed number")


func test_form_status_says_why_not() -> void:
	assert_eq(Units.form_status("foot"), "")
	var four: Array = [Game.roster[0].sid, Game.roster[1].sid, Game.roster[2].sid, Game.roster[3].sid]
	assert_eq(Units.form_status("foot", four), "A party takes at most 3 survivors")
	assert_eq(Units.form_status("horse"), "No free %s" % Data.VEHICLES.horse.name.to_lower())
	Game.vehicles["horse"] = 1
	assert_eq(Units.form_status("horse"), "")
	Game.roster[0].state = "away"
	assert_eq(Units.form_status("foot", [Game.roster[0].sid]), "%s is not at home" % Game.roster[0].name)
	assert_eq(Units.form_status("foot", [9999]), "Somebody is not at home")
	Game.pop = 4
	assert_eq(Units.form_status("foot"), "Need 3 colonists to spare")
	Game.pop = 30
	for k in Data.FOOD_KINDS:
		Game.res[k] = 0
	assert_eq(Units.form_status("foot"), "Need %d food for the pack (grain, veg or meat)" % Data.SCOUT_PACK)
	assert_true(Units.form_party("foot").is_empty(), "and nothing is formed")


func test_with_big_party_a_party_takes_four() -> void:
	_lead(["big_party"])
	var u := Units.form_party("foot")
	assert_eq(u.crew, 4)
	var five: Array = [Game.roster[0].sid, Game.roster[1].sid, Game.roster[2].sid, Game.roster[3].sid, Game.roster[4].sid]
	assert_eq(Units.form_status("foot", five), "A party takes at most 4 survivors")


func test_a_party_takes_salt_when_the_switch_is_on() -> void:
	Game.salt_on = true
	Game.items["salt"] = 5
	var u := Units.form_party("foot")
	assert_eq(Game.items["salt"], 2, "a dose for each of the three")
	for s in u.survivors:
		assert_eq(s.salted, Data.SALT_SEASONS)


func test_a_war_rig_party_takes_a_full_tank() -> void:
	Game.vehicles["car"] = 1
	var u := Units.form_party("car")
	assert_eq(u.mover, "car")
	assert_eq(u.fuel, float(Data.VEHICLE_FUEL.car.tank))
	assert_eq(Game.res["fuel"], 50 - Data.VEHICLE_FUEL.car.tank)


func test_a_formed_party_is_sent_by_ordering_it_and_walks_at_once() -> void:
	var u := Units.form_party("foot")
	var far := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 6 and c.distance_to(hq) < 10 \
		and not Game.route("foot", hq, c).is_empty())
	assert_eq(Units.order_status(u, far), "")
	Units.order_scouts(u.id, far)
	assert_ne(u.pos, hq, "it set off the moment it was ordered")
	assert_lt(u.move_left, float(Data.SEASON_DAYS))


func test_recalling_a_party_that_is_at_home_disbands_it_and_returns_its_people_and_food() -> void:
	var pop := Game.pop
	var grain: int = Game.res["grain"]
	var u := Units.form_party("foot")
	var crew: Array = u.survivors.duplicate()
	Units.recall_scouts(u.id)
	assert_false(Units.units.has(u))
	assert_eq(Game.pop, pop)
	assert_eq(Game.res["grain"], grain, "the pack went back into the stores")
	for s in crew:
		assert_eq(s.state, "home")


func test_a_survivor_is_found_by_number_and_the_season_is_written_out() -> void:
	assert_eq(Game.survivor_by_sid(Game.roster[3].sid), Game.roster[3])
	assert_eq(Game.survivor_by_sid(99999), {})
	assert_eq(Game.season_text(1), "Year 1, Spring")
	assert_eq(Game.season_text(2), "Year 1, Summer")
	assert_eq(Game.season_text(5), "Year 2, Spring")
	assert_eq(Game.season_name(), Game.season_text(Game.season))


func test_taking_chosen_survivors_skips_the_ones_who_are_away_or_dead_and_repeats() -> void:
	Game.roster[1].state = "away"
	Game.fall(Game.roster[2], "test")
	var crew := Game.take_chosen([Game.roster[0].sid, Game.roster[0].sid, Game.roster[1].sid, Game.roster[2].sid, Game.roster[3].sid])
	assert_eq(crew.map(func(s): return s.sid), [Game.roster[0].sid, Game.roster[3].sid])


func test_no_dotted_route_line_is_drawn_to_your_settlement() -> void:
	var far := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 6 and c.distance_to(hq) < 10 \
		and not Game.route("foot", hq, c).is_empty())
	var u := Units.form_party("foot")
	Units.order_scouts(u.id, far)
	var other := World.find_tile(func(c, t): return t["t"] != "water" and Game.tile(c)["o"] == Data.NONE and c.distance_to(u.pos) > 3 \
		and not Game.route("foot", u.pos, c).is_empty() and c.distance_to(hq) > 6)
	Game.pick_scout(u.id)
	Game.selected = other
	Game.refresh_scout_route()
	assert_false(Game.scout_route.is_empty(), "a route to somewhere you could send it is drawn")
	Game.selected = hq
	Game.refresh_scout_route()
	assert_true(Game.scout_route.is_empty(), "but none to the settlement")
	var at_home := Units.form_party("foot")
	at_home.path = [hq + Vector2i(1, 0), hq + Vector2i(2, 0)]
	Game.pick_scout(at_home.id)
	Game.selected = hq
	Game.refresh_scout_route()
	assert_true(Game.scout_route.is_empty(), "not even for a party standing there with orders pending")
