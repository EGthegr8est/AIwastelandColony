extends "res://tests/framework/test_case.gd"
## What each of the 22 perks and 13 flaws actually does. Every test compares a colony with the quirk to one without,
## so the number it checks is the quirk's own doing.

const Data = preload("res://scripts/data.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const Leaders = preload("res://scripts/leaders.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i


func before_each() -> void:
	Leaders.offered = []


func after_each() -> void:
	Units.dice = load("res://scripts/dice.gd").new()


## A new colony from the same seed, led by someone with exactly these perks and this flaw.
func _new(perks := [], flaw := "") -> void:
	seed(7)
	Game.new_game("builder", {"name": "Test Leader", "perks": perks, "flaw": flaw})
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)


## Gives the colony these quirks without starting a new one.
func _lead(perks := [], flaw := "") -> void:
	Game.leader_info = Leaders.fill("builder", {"name": "Test Leader", "perks": perks, "flaw": flaw})


func _gather_delta() -> Dictionary:
	var before := Game.res.duplicate()
	Game._gather()
	var delta := {}
	for k in Game.res:
		delta[k] = Game.res[k] - before[k]
	Game.res = before
	return delta


func _tile_at(dx: int, dy: int) -> Vector2i:
	var c := Vector2i(hq.x + dx, hq.y + dy)
	Game.tile(c)["o"] = Data.PLAYER
	Game.tile(c)["t"] = "sand"
	return c


# ---------------------------------------------------------------- the start

func test_a_colony_with_no_leader_given_has_no_quirks() -> void:
	seed(7)
	Game.new_game("raider")
	assert_eq(Game.leader_info.perks, [])
	assert_eq(Game.leader_info.flaw, "")
	assert_false(Game.has_quirk("haggler"))


func test_the_start_quirks_change_stores_troops_and_standing() -> void:
	_new()
	var gold: int = Game.res["gold"]
	var metal: int = Game.res["metal"]
	var troops := Game.troops
	var dustwell: int = Game.town["relations"]
	var kings: int = Game.ai["relations"]
	_new(["old_stash", "veteran_band"])
	assert_eq(Game.res["gold"], gold + 20)
	assert_eq(Game.res["metal"], metal + 10)
	assert_eq(Game.troops, troops + 2)
	_new(["silver_tongue"])
	assert_eq(Game.town["relations"], dustwell + 20)
	assert_eq(Game.befriend_cost(), {"grain": 5, "gold": 3})
	_new([], "hard_to_like")
	assert_eq(Game.town["relations"], dustwell - 10)
	assert_eq(Game.befriend_cost(), {"grain": 10, "gold": 5})
	_new([], "bad_blood")
	assert_eq(Game.ai["relations"], kings - 15)


# ---------------------------------------------------------------- economy

func test_green_thumb_and_prospector_add_to_each_farm_and_mine() -> void:
	_new()
	for i in 3:
		Game.tile(_tile_at(i + 1, 0))["b"] = "farm"
	for i in 2:
		Game.tile(_tile_at(i + 1, 1))["b"] = "mine"
	Game.pop = 80   # plenty of workers, so nothing is left untended
	var plain := _gather_delta()
	_lead(["green_thumb"])
	assert_eq(_gather_delta()["veg"] - plain["veg"], 3, "3 farms, +1 veg each")
	_lead(["prospector"])
	assert_eq(_gather_delta()["stone"] - plain["stone"], 2, "2 mines, +1 stone each")


func test_haggler_and_poor_haggler_change_what_the_market_pays_and_costs() -> void:
	_new()
	assert_eq([Game.sell_gold("metal"), Game.buy_price("metal")], [4, 8])
	_lead(["haggler"])
	assert_eq([Game.sell_gold("metal"), Game.buy_price("metal")], [5, 6])
	_lead([], "poor_haggler")
	assert_eq(Game.sell_gold("metal"), 3)
	assert_eq(Game.buy_price("metal"), 8, "buying is unchanged")
	# and the sale really pays it
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.res["metal"] = 20
	var gold: int = Game.res["gold"]
	Game.sell("metal")
	assert_eq(Game.res["gold"], gold + 3)


func test_frugal_halves_the_starvation_losses() -> void:
	_new()
	Game.pop = 20
	Game.res["grain"] = 0
	Game.res["veg"] = 0
	Game.res["meat"] = 1000
	Game._upkeep()
	var plain := Game.pop
	_new(["frugal"])
	Game.pop = 20
	Game.res["grain"] = 0
	Game.res["veg"] = 0
	Game.res["meat"] = 1000
	Game._upkeep()
	assert_eq(plain, 14, "20 mouths and no food lose a third")
	assert_eq(Game.pop, 17, "a Frugal leader's colony loses half as many")


func test_big_families_grow_from_a_smaller_surplus() -> void:
	_new()
	Game.pop = 10
	Game.res["grain"] = 16   # 6 more than the 10 mouths need
	Game.res["veg"] = 0
	Game.res["meat"] = 1000
	Game._upkeep()
	assert_eq(Game.pop, 10, "6 is not a surplus of 10")
	_new(["big_families"])
	Game.pop = 10
	Game.res["grain"] = 16
	Game.res["veg"] = 0
	Game.res["meat"] = 1000
	Game._upkeep()
	assert_eq(Game.pop, 11)


func test_big_appetites_feed_a_fifth_more_mouths() -> void:
	_new()
	Game.pop = 10
	assert_eq(Game.mouths(), 10)
	Game.prisoners = 3
	_lead([], "big_appetites")
	assert_eq(Game.mouths(), 15, "10 + 3 prisoners + 2 more for every 5 colonists")
	Game.res["grain"] = 100
	Game.res["veg"] = 0
	Game.res["meat"] = 1000
	Game.troops = 0
	Game._upkeep()
	assert_eq(Game.res["grain"], 85)


func test_pack_rat_and_poor_packers_change_what_a_party_carries() -> void:
	_new()
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	u.crew = 3
	assert_eq(Units.load_capacity(u), 30.0)
	_lead(["pack_rat"])
	assert_eq(Units.load_capacity(u), 37.5)
	_lead([], "poor_packers")
	assert_almost_eq(Units.load_capacity(u), 25.5, 0.0001)


func test_mechanic_makes_vehicles_cheaper_and_thriftier_with_fuel() -> void:
	_new()
	var plain := Game.vehicle_cost("car")
	assert_eq(Units.fuel_mult(), 1.0)
	_lead(["mechanic"])
	var cheaper := Game.vehicle_cost("car")
	assert_eq([cheaper.metal, cheaper.wood], [9, 4], "20% off 11 metal and 4 wood, rounded up")
	assert_lt(cheaper.metal, plain.metal)
	assert_eq(Units.fuel_mult(), 0.8)
	var a := Units.boat_trip_fuel(hq)
	_lead()
	assert_almost_eq(Units.boat_trip_fuel(hq), a / 0.8, 0.0001)


func test_spendthrift_adds_a_wood_to_every_claim() -> void:
	_new()
	var plain: int = Game.claim_cost(hq + Vector2i(5, 0)).wood
	_lead([], "spendthrift")
	assert_eq(Game.claim_cost(hq + Vector2i(5, 0)).wood, plain + 1)


# ---------------------------------------------------------------- war

func test_drill_sergeant_trims_a_troops_metal() -> void:
	_new()
	assert_eq(Game.train_troop_cost(), {"metal": 3, "meat": 2})
	_lead(["drill_sergeant"])
	assert_eq(Game.train_troop_cost(), {"metal": 2, "meat": 2})


func test_warden_and_lax_guards_move_the_prison_rules() -> void:
	_new()
	assert_eq([Game.prison_high(), Game.guard_ratio()], [4, 3])
	_lead(["warden"])
	assert_eq([Game.prison_high(), Game.guard_ratio()], [6, 4])
	Game.prisoners = 6
	assert_false(Game.prison_break_due(), "6 is not more than 6")
	Game.prisoners = 7
	assert_true(Game.prison_break_due())
	_lead([], "lax_guards")
	assert_eq(Game.prison_high(), 3)
	Game.prisoners = 4
	assert_true(Game.prison_break_due(), "4 is more than 3")


func test_ransom_broker_pays_a_gold_more_a_prisoner() -> void:
	_new()
	assert_eq(Game.ransom_price(), 3)
	_lead(["ransom_broker"])
	assert_eq(Game.ransom_price(), 4)


func test_siege_breaker_makes_their_walls_count_less() -> void:
	_new()
	assert_eq(Game.wall_breach(), 1.0)
	_lead(["siege_breaker"])
	assert_almost_eq(Game.wall_breach(), 0.8, 0.0001)


func test_stonemason_and_shaky_buildings_move_your_buildings_dc_but_not_theirs() -> void:
	_new()
	var farm := _tile_at(2, 0)
	Game.tile(farm)["b"] = "farm"
	var theirs: Vector2i = Game.owned(Data.AI).filter(func(c): return Game.tile(c)["b"] == "")[0]
	Game.tile(theirs)["b"] = "ai_wall"
	assert_eq(Game.building_dc(farm), 8)
	_lead(["stonemason"])
	assert_eq(Game.building_dc(farm), 9)
	_lead([], "shaky_buildings")
	assert_eq(Game.building_dc(farm), 7)
	assert_eq(Game.building_dc(theirs), 12, "the Rust Kings' walls are not yours")


func test_thin_walls_take_a_tenth_off_your_wall_defense() -> void:
	_new()
	for i in 5:
		Game.tile(_tile_at(i + 1, 2))["b"] = "wall"
	assert_eq(Game.player_wall_defense(), 10.0)
	_lead([], "thin_walls")
	assert_almost_eq(Game.player_wall_defense(), 9.0, 0.0001)


# ---------------------------------------------------------------- exploring

func test_eagle_eyes_and_short_sight_change_how_far_scouts_see() -> void:
	_new()
	var scout: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", hq, hq)
	assert_eq(Units.sight_of(scout), Data.SCOUT_SIGHT["foot"])
	_lead(["eagle_eyes"])
	assert_eq(Units.sight_of(scout), Data.SCOUT_SIGHT["foot"] + 1)
	_lead([], "short_sight")
	assert_eq(Units.sight_of(scout), Data.SCOUT_SIGHT["foot"] - 1)
	var scav: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	_lead(["eagle_eyes"])
	assert_eq(Units.sight_of(scav), Data.UNITS["scav"].sight, "only scouting parties")


func test_rad_proof_and_frail_colonists_change_the_dose_rate() -> void:
	_new()
	assert_almost_eq(Game.dose_rate(), Data.RAD_DOSE_RATE, 0.0001)
	_lead(["rad_proof"])
	assert_almost_eq(Game.dose_rate(), Data.RAD_DOSE_RATE * 0.75, 0.0001)
	_lead([], "frail_colonists")
	assert_almost_eq(Game.dose_rate(), Data.RAD_DOSE_RATE * 1.15, 0.0001)
	# and a party standing in the heat really takes the dose
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", hq, hq)
	u.survivors = Units._make_crew(1)
	u.crew = 1
	u.rad_days = 80.0 * Data.SEASON_DAYS
	u.moved = true
	Units.units.append(u)
	Units._expose(u)
	var frail: float = u.survivors[0].dose
	u.survivors[0].dose = 0.0
	u.rad_days = 80.0 * Data.SEASON_DAYS
	u.moved = true
	_lead(["rad_proof"])
	Units._expose(u)
	assert_gt(frail, u.survivors[0].dose)


func test_trailblazer_and_slow_marchers_change_travel_time() -> void:
	_new()
	var path := [hq, hq + Vector2i(1, 0), hq + Vector2i(2, 0), hq + Vector2i(3, 0)]
	var plain := Game.party_route_days("foot", path)
	assert_almost_eq(plain, Game.route_days("foot", path), 0.0001)
	var plain_arrival: float = Units.arrival_days("foot", path)[-1]
	_lead(["trailblazer"])
	assert_almost_eq(Game.party_route_days("foot", path), plain * 0.85, 0.0001)
	assert_almost_eq(Units.arrival_days("foot", path)[-1], plain_arrival * 0.85, 0.0001)
	assert_almost_eq(Game.route_days("foot", path), plain, 0.0001, "the march fatigue sum is the same for everyone")
	_lead([], "slow_marchers")
	assert_almost_eq(Game.party_route_days("foot", path), plain * 1.10, 0.0001)


func test_a_trailblazers_party_really_walks_further_in_a_season() -> void:
	_new()
	var far := Vector2i(hq.x + 30, hq.y)
	var steps := []
	for quirk in [[], ["trailblazer"]]:
		_lead(quirk)
		var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", hq, far)
		u.path = []
		for i in 30:
			u.path.append(Vector2i(hq.x + i + 1, hq.y))
		Units._advance(u)
		steps.append(u.pos.x - hq.x)
	assert_gt(steps[1], steps[0])


func _ctx(check: String) -> int:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	u.crew = 1
	u.survivors = Units._make_crew(1)
	var parts := D20Visit.situation_parts({"name": "A", "traits": []}, Units.visit_ctx(u), check)
	return D20Visit.parts_total(parts)


func test_sharp_nose_and_butterfingers_change_the_rolls_they_name() -> void:
	_new()
	Game.tile(hq)["rad"] = 0
	var plain := {"cache": _ctx("cache"), "trap": _ctx("trap"), "site": _ctx("site"), "combat": _ctx("combat")}
	_lead(["sharp_nose"])
	assert_eq([_ctx("cache") - plain.cache, _ctx("trap") - plain.trap, _ctx("site") - plain.site, _ctx("combat") - plain.combat], [1, 1, 1, 0])
	_lead([], "butterfingers")
	assert_eq([_ctx("cache") - plain.cache, _ctx("trap") - plain.trap, _ctx("site") - plain.site, _ctx("combat") - plain.combat], [-1, -1, 0, 0])


func test_a_sharp_noses_bonus_shows_in_the_panel_as_the_leader() -> void:
	_new(["sharp_nose"])
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	u.crew = 1
	u.survivors = Units._make_crew(1)
	var parts := D20Visit.situation_parts({"name": "A", "traits": []}, Units.visit_ctx(u), "cache")
	assert_true(parts.any(func(p): return p.label == "leader" and p.value == 1))


func test_lucky_streak_gives_every_party_a_reroll_but_not_two() -> void:
	_new()
	var plain := _survivors([[]])
	var lucky := _survivors([["lucky"]])
	var dice := ForcedDice.new()
	assert_eq(D20Visit.begin("safe", Units.visit_ctx(_unit()), 1.0, dice, plain).rerolls, 0)
	_lead(["lucky_streak"])
	assert_eq(D20Visit.begin("safe", Units.visit_ctx(_unit()), 1.0, dice, plain).rerolls, 1)
	assert_eq(D20Visit.begin("safe", Units.visit_ctx(_unit()), 1.0, dice, lucky).rerolls, 1, "like the Lucky trait, not on top of it")


func _unit() -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	u.crew = 1
	u.survivors = Units._make_crew(1)
	return u


func _survivors(trait_lists: Array) -> Array:
	var out := []
	for traits in trait_lists:
		out.append({"name": "A", "age": 30, "traits": traits.duplicate(), "injury": "none", "hunger": 0, "hp": 100.0, "dose": 0.0, "hurt": false, "face": 1, "sick": 0})
	return out


func test_field_medic_makes_injuries_one_step_lighter() -> void:
	_new()
	var hurt: Dictionary = _survivors([[]])[0]
	var visit := D20Visit.begin("safe", Units.visit_ctx(_unit()), 1.0, ForcedDice.new(), [hurt])
	D20Visit._hurt(visit, hurt, "severe")
	assert_eq(hurt.injury, "severe", "without a medic")
	_lead(["field_medic"])
	var fine: Dictionary = _survivors([[]])[0]
	var visit2 := D20Visit.begin("safe", Units.visit_ctx(_unit()), 1.0, ForcedDice.new(), [fine])
	D20Visit._hurt(visit2, fine, "severe")
	assert_eq(fine.injury, "light")
	var fine2: Dictionary = _survivors([[]])[0]
	D20Visit._hurt(visit2, fine2, "light")
	assert_eq(fine2.injury, "none")


func test_the_quirks_in_a_visit_survive_a_json_round_trip() -> void:
	_new(["sharp_nose", "field_medic"])
	var visit := D20Visit.begin("safe", Units.visit_ctx(_unit()), 1.0, ForcedDice.new(), _survivors([[]]))
	var back: Dictionary = JSON.parse_string(JSON.stringify(visit))
	D20Visit.normalize(back)
	assert_eq(back.ctx.leader.cache, 1)
	assert_eq(typeof(back.ctx.leader.medic), TYPE_INT)


# ---------------------------------------------------------------- trade

func test_caravan_master_adds_a_quarter_to_the_gold_a_trade_run_brings() -> void:
	_new()
	assert_eq(Game.trade_gold(8), 8)
	_lead(["caravan_master"])
	assert_eq(Game.trade_gold(8), 10)
	var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", hq, hq)
	u.dest = -1
	u.crew = 1
	Units._trade(u)
	assert_eq(u.carry["gold"], 10, "a plain Rust Kings run brings 8")


# ---------------------------------------------------------------- saving

func test_the_leader_is_saved_with_the_game_and_shows_on_the_save_slot() -> void:
	_new(["haggler", "frugal"], "slow_marchers")
	Game.leader_info["name"] = "Sheriff Cole Harlan"
	Game.leader_info["image"] = "raider_1"
	Game.save_game("leader_test")
	World.new_game(99)
	assert_false(Game.has_quirk("haggler"))
	assert_true(Game.load_game("leader_test"))
	assert_true(Game.has_quirk("haggler"))
	assert_true(Game.has_quirk("frugal"))
	assert_true(Game.has_quirk("slow_marchers"))
	assert_eq(Game.leader_info.name, "Sheriff Cole Harlan")
	assert_eq(Game.leader_info.image, "raider_1")
	assert_has(Game.save_info("leader_test"), "Sheriff Cole Harlan (Builder)")
	DirAccess.remove_absolute(Game._path("leader_test"))


func test_a_save_from_before_named_leaders_still_loads() -> void:
	_new()
	Game.save_game("old_leader_test")
	var path: String = Game._path("old_leader_test")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("leader_info")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	World.new_game(99)
	assert_true(Game.load_game("old_leader_test"))
	DirAccess.remove_absolute(path)
	assert_eq(Game.leader, "builder")
	assert_eq(Game.leader_info.perks, [])
	assert_eq(Game.save_info("old_leader_test"), "empty", "(the slot is gone now)")
