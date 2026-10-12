extends "res://tests/framework/test_case.gd"
## Building raids: each building's DC, the Rust Kings' Raider wall tiles (one per 4 of their walls), the attack roll for
## a raid or a raider band, the season cap on your losses, and a scouting party's Attack roll through the d20 visit.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	Units.dice = load("res://scripts/dice.gd").new()


## A free tile of yours to put a building on, the `n`th one found.
func _free_tile(n := 0) -> Vector2i:
	var found := 0
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water":
			if found == n:
				return c
			found += 1
	return Vector2i(-1, -1)


func _player_building(id: String, n := 0) -> Vector2i:
	var c := _free_tile(n)
	Game.tile(c)["b"] = id
	return c


## The Raider wall tiles now on the map.
func _wall_tiles() -> Array:
	return Game.owned(Data.AI).filter(func(c): return Game.tile(c)["b"] == "ai_wall")


# ---------------------------------------------------------------- DCs

func test_each_building_has_the_dc_in_the_plan() -> void:
	var expected := {"farm": 8, "lodge": 8, "horse_farm": 8, "salvage": 8, "market": 8, "mine": 10, "refinery": 10,
		"motor_pool": 10, "port": 10, "airfield": 10, "outpost": 11, "wall": 12, "tower": 12, "keep": 15}
	for id in expected:
		var c := _player_building(id)
		assert_eq(Game.building_dc(c), expected[id], id)
		Game.tile(c)["b"] = ""


func test_stone_walls_make_your_walls_harder_but_not_the_rust_kings() -> void:
	var c := _player_building("wall")
	assert_eq(Game.building_dc(c), 12)
	Game.upgrades.append("f2")
	assert_eq(Game.building_dc(c), 14)
	var tower := _player_building("tower", 1)
	assert_eq(Game.building_dc(tower), 12, "only walls")
	var theirs: Vector2i = Game.owned(Data.AI).filter(func(t): return Game.tile(t)["b"] == "")[0]
	Game.tile(theirs)["b"] = "ai_wall"
	assert_eq(Game.building_dc(theirs), 12)


func test_hqs_the_fort_dustwell_the_citadel_and_sites_cannot_be_destroyed() -> void:
	assert_eq(Game.building_dc(hq), 0)
	assert_eq(Game.building_dc(Game.home(Data.AI)), 0)
	assert_eq(Game.building_dc(Game.home(Data.TOWN)), 0)
	assert_eq(Game.building_dc(_player_building("citadel")), 0)
	for p in Game.poi_footprint(_poi_anchor()):
		assert_eq(Game.building_dc(p), 0)
	assert_eq(Game.building_dc(_free_tile(3)), 0, "an empty tile")
	var c := _player_building("citadel", 5)
	Game.destroy_building(c)
	assert_eq(Game.tile(c)["b"], "citadel", "destroying one does nothing")


func _poi_anchor() -> Vector2i:
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		if Game.poi_kind(c) != "":
			return Game.poi_anchor(c)
	return Vector2i(-1, -1)


func test_a_raid_modifier_comes_from_strength_against_defense() -> void:
	assert_eq(Game.raid_modifier(20.0, 10.0), 4, "double")
	assert_eq(Game.raid_modifier(30.0, 10.0), 4)
	assert_eq(Game.raid_modifier(15.0, 10.0), 2, "1.5 times")
	assert_eq(Game.raid_modifier(19.0, 10.0), 2)
	assert_eq(Game.raid_modifier(10.0, 10.0), 0, "even")
	assert_eq(Game.raid_modifier(14.0, 10.0), 0)
	assert_eq(Game.raid_modifier(9.0, 10.0), -2, "below")
	assert_eq(Game.raid_modifier(5.0, 0.0), 4, "nothing defending")


# ---------------------------------------------------------------- Raider walls

func test_no_walls_means_no_wall_tiles() -> void:
	assert_eq(Game.ai["walls"], 0)
	assert_eq(_wall_tiles().size(), 0)


func test_one_wall_tile_stands_for_four_walls_rounded_up() -> void:
	for pair in [[1, 1], [4, 1], [5, 2], [8, 2], [9, 3], [0, 0]]:
		Game.ai["walls"] = pair[0]
		Game._sync_ai_walls()
		assert_eq(_wall_tiles().size(), pair[1], "%d walls" % pair[0])


func test_wall_tiles_go_on_their_land_nearest_you_and_no_water() -> void:
	Game.ai["walls"] = 12
	Game._sync_ai_walls()
	var walls := _wall_tiles()
	assert_eq(walls.size(), 3)
	var worst := 0.0
	for c in walls:
		assert_eq(Game.tile(c)["o"], Data.AI)
		assert_ne(Game.tile(c)["t"], "water")
		worst = maxf(worst, Vector2(c - hq).length())
	for c in Game.owned(Data.AI):
		if Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water":
			assert_ge(Vector2(c - hq).length(), worst, "no free tile is closer to you than a wall")


func test_syncing_twice_changes_nothing_and_fewer_walls_remove_the_far_tiles() -> void:
	Game.ai["walls"] = 12
	Game._sync_ai_walls()
	var before := _wall_tiles()
	Game._sync_ai_walls()
	assert_eq(_wall_tiles().size(), 3)
	Game.ai["walls"] = 5
	Game._sync_ai_walls()
	var left := _wall_tiles()
	assert_eq(left.size(), 2)
	for c in left:
		assert_has(before, c)


func test_their_season_turn_builds_a_wall_and_its_tile() -> void:
	Game.ai["truce"] = 99   # no raid this season
	Game.ai["wood"] = 50
	Game.ai["stone"] = 50
	Game._ai_turn()
	assert_eq(Game.ai["walls"], 1)
	assert_eq(_wall_tiles().size(), 1)


func test_you_cannot_buy_a_raider_wall_tile() -> void:
	Game.upgrades.append("c5")
	Game.ai["relations"] = 50
	var wall: Vector2i = Game.owned(Data.AI).filter(func(c): return Game.tile(c)["b"] == "")[0]
	Game.tile(wall)["b"] = "ai_wall"
	for n in Game.neighbors(wall):
		Game.tile(n)["o"] = Data.PLAYER
	Game.res["wood"] = 100
	Game.res["gold"] = 100
	assert_eq(Game.claim_status(wall), "They won't sell this tile")


func test_taking_land_with_a_raider_wall_takes_its_four_walls_with_it() -> void:
	Game.ai["walls"] = 8
	Game._sync_ai_walls()
	var wall: Vector2i = _wall_tiles()[0]
	for n in Game.neighbors(wall):
		if Game.tile(n)["o"] != Data.AI:
			Game.tile(n)["o"] = Data.PLAYER
	# make sure one of its neighbours is yours so it borders you
	Game.tile(Game.neighbors(wall)[0])["o"] = Data.PLAYER
	var taken := Game._take_land(Data.AI, Data.PLAYER, 200, false)
	assert_gt(taken, 0)
	assert_eq(Game.tile(wall)["o"], Data.PLAYER)
	assert_eq(Game.tile(wall)["b"], "", "gone, not kept")
	assert_lt(Game.ai["walls"], 8)
	assert_eq(Game.ai["walls"], 8 - 4 * (2 - _wall_tiles().size()), "four walls went with each wall tile that changed hands")


# ---------------------------------------------------------------- the attack roll

func test_a_hit_destroys_the_building_and_a_miss_leaves_it() -> void:
	var farm := _player_building("farm")
	var other := _player_building("farm", 1)
	Units.dice = ForcedDice.new([8, 7])
	assert_true(Game.attack_building(farm, 0, "A test party"), "d20 8 meets DC 8")
	assert_eq(Game.tile(farm)["b"], "")
	assert_eq(Game.tile(farm)["o"], Data.PLAYER, "the tile stays yours")
	assert_false(Game.attack_building(other, 0, "A test party"), "d20 7 misses")
	assert_eq(Game.tile(other)["b"], "farm")
	assert_true(Game.log_lines.any(func(l): return l.contains("d20 8 +0 vs DC 8, destroyed")))
	assert_true(Game.log_lines.any(func(l): return l.contains("d20 7 +0 vs DC 8, it held")))


func test_the_modifier_counts_and_is_clamped() -> void:
	var mine := _player_building("mine")   # DC 10
	Units.dice = ForcedDice.new([6, 6])
	assert_false(Game.attack_building(mine, 3, "A test party"), "6 + 3 = 9 misses DC 10")
	assert_true(Game.attack_building(mine, 4, "A test party"), "6 + 4 = 10 hits")
	var farm := _player_building("farm", 1)
	Units.dice = ForcedDice.new([3])
	assert_true(Game.attack_building(farm, 40, "A test party"), "a modifier of 40 is clamped to +5, and 3 + 5 hits DC 8")
	assert_true(Game.log_lines.any(func(l): return l.contains("d20 3 +5 vs DC 8")))


func test_a_natural_20_always_hits_and_a_natural_1_always_misses() -> void:
	var keep := _player_building("keep")   # DC 15
	Units.dice = ForcedDice.new([20])
	assert_true(Game.attack_building(keep, -5, "A test party"))
	var farm := _player_building("farm", 1)
	Units.dice = ForcedDice.new([1])
	assert_false(Game.attack_building(farm, 5, "A test party"))


func test_a_building_that_cannot_be_hit_uses_no_dice() -> void:
	Units.dice = ForcedDice.new([])   # any roll would be an error
	assert_false(Game.attack_building(hq, 5, "A test party"))
	assert_false(Game.attack_building(_free_tile(4), 5, "A test party"))


func test_only_three_of_your_buildings_fall_a_season_and_the_count_resets() -> void:
	var farms := []
	for i in 4:
		farms.append(_player_building("farm", i))
	Units.dice = ForcedDice.new([20, 20, 20])
	for i in 3:
		assert_true(Game.attack_building(farms[i], 0, "A test party"))
	assert_eq(Game.buildings_lost, 3)
	assert_false(Game.can_hit(farms[3]), "the cap is reached")
	assert_false(Game.attack_building(farms[3], 0, "A test party"), "no roll is made")
	assert_eq(Game.tile(farms[3])["b"], "farm")
	assert_eq(Game.stats.buildings_lost, 3)
	Game.end_season()
	assert_eq(Game.buildings_lost, 0)
	assert_true(Game.can_hit(farms[3]))


func test_the_cap_does_not_protect_the_rust_kings() -> void:
	Game.ai["walls"] = 20
	Game._sync_ai_walls()
	Game.buildings_lost = 3
	assert_true(Game.can_hit(_wall_tiles()[0]))


func test_destroying_a_refinery_resets_its_switch() -> void:
	var c := _player_building("refinery")
	Game.refinery_on[Game.idx(c)] = true
	Game.destroy_building(c)
	assert_false(Game.refinery_on.has(Game.idx(c)))


func test_destroying_a_raider_wall_removes_four_walls_and_ten_relations() -> void:
	Game.ai["walls"] = 9
	Game.ai["relations"] = 20
	Game._sync_ai_walls()
	var wall: Vector2i = _wall_tiles()[0]
	Game.destroy_building(wall)
	assert_eq(Game.ai["walls"], 5)
	assert_eq(Game.ai["relations"], 10)
	assert_eq(Game.tile(wall)["b"], "", "or it was rebuilt a moment later on the next free tile, which is fine too")
	assert_eq(_wall_tiles().size(), 2, "ceil(5 / 4) tiles")
	assert_eq(Game.stats.enemy_buildings_destroyed, 1)
	Game.destroy_building(_wall_tiles()[0])
	Game.destroy_building(_wall_tiles()[0])
	assert_eq(Game.ai["walls"], 0, "never below zero")
	assert_eq(_wall_tiles().size(), 0)


# ---------------------------------------------------------------- raids and bands

func test_a_raider_band_that_wins_rolls_at_the_building_nearest_it() -> void:
	var near := _player_building("farm", 0)
	var far := _player_building("farm", 12)
	assert_ne(near, far)
	Units.dice = ForcedDice.new([20])
	Game.raider_strike(near + Vector2i(1, 0), 6.0, 3.0)   # strength twice the defense: +4
	assert_eq(Game.tile(near)["b"], "", "the near one fell")
	assert_eq(Game.tile(far)["b"], "farm")
	assert_true(Game.log_lines.any(func(l): return l.contains("A raider band struck the farm")))
	assert_true(Game.log_lines.any(func(l): return l.contains("+4 vs DC 8")))


func test_a_raider_band_with_nothing_to_hit_rolls_nothing() -> void:
	for c in Game.owned(Data.PLAYER):
		if Game.building_dc(c) > 0:
			Game.tile(c)["b"] = ""
	Units.dice = ForcedDice.new([])
	Game.raider_strike(hq, 6.0, 3.0)
	assert_eq(Game.buildings_lost, 0)


func test_a_won_raid_rolls_once_at_the_wall_nearest_you_and_twice_at_double_their_defense() -> void:
	Game.ai["walls"] = 12
	Game._sync_ai_walls()
	Units.dice = ForcedDice.new([20])
	Game._raid_strikes(15.0, 10.0)
	assert_eq(Game.ai["walls"], 8, "one roll, one tile")
	Units.dice = ForcedDice.new([20, 20])
	Game._raid_strikes(25.0, 10.0)
	assert_eq(Game.ai["walls"], 0, "two rolls, two tiles")
	assert_eq(_wall_tiles().size(), 0)


func test_a_won_raid_rolls_at_their_walls_through_the_real_raid() -> void:
	var struck := false
	for s in range(1, 60):
		World.new_game(7)
		Units.tribes = []
		Units.wild_spawns = false
		Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
		Game.ai["walls"] = 8
		Game._sync_ai_walls()
		Game.troops = 1
		var per_troop := Game.player_attack(Game.home(Data.AI))   # the march to their fort takes some of it
		Game.troops = ceili(2.2 * Game.ai_defense(Game.wall_breach()) / per_troop)   # double their defense, but not a decisive win
		Units.dice = ForcedDice.new([20, 20])
		seed(s)
		Game.raid_ai()
		if Game.stats.raids_won == 1:
			struck = true
			assert_false(Game.ended(), "not overwhelming")
			assert_eq(Game.ai["walls"], 0, "both rolls hit")
			assert_true(Game.log_lines.any(func(l): return l.contains("Your raid struck the raider wall")))
			break
	assert_true(struck, "a 69% raid is won within 60 seeds")


# ---------------------------------------------------------------- scouting parties

func _scout_next_to_a_wall(traits := []) -> Dictionary:
	Game.ai["walls"] = 8
	Game._sync_ai_walls()
	var wall: Vector2i = _wall_tiles()[0]
	var spot := Vector2i(wall.x + 1, wall.y)
	if not Game.in_bounds(spot) or Game.tile(spot)["t"] == "water":
		spot = Vector2i(wall.x - 1, wall.y)
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", spot, spot)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = traits.duplicate()
	u.stage = "station"
	u.food = {"grain": 5}
	Units.units.append(u)
	return u


func test_a_stationed_party_can_attack_a_raider_wall_it_stands_next_to() -> void:
	var u := _scout_next_to_a_wall()
	var wall: Vector2i = _wall_tiles()[0]
	assert_has(Units.strike_targets(u), wall)
	u.stage = "out"
	assert_eq(Units.strike_targets(u), [], "only a party keeping watch")
	u.stage = "station"
	u.pos = hq
	assert_eq(Units.strike_targets(u), [], "nothing next to it")
	var scav: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", wall, wall)
	scav.stage = "station"
	assert_eq(Units.strike_targets(scav), [], "scouts only")


func test_a_party_on_the_wall_tile_itself_can_attack_it() -> void:
	var u := _scout_next_to_a_wall()
	var wall: Vector2i = _wall_tiles()[0]
	u.pos = wall
	assert_has(Units.strike_targets(u), wall)


func test_a_winning_attack_brings_the_wall_down_pays_a_package_and_costs_relations() -> void:
	var u := _scout_next_to_a_wall()
	var wall: Vector2i = _wall_tiles()[0]
	Game.ai["relations"] = 30
	Units.dice = ForcedDice.new([20, 5], [4])   # a natural 20, then the spoils roll (5 is metal), 4 on the dice
	assert_true(Units.begin_strike(u.id, wall))
	assert_eq(u.stage, "site")
	assert_eq(u.visit.ruin, "building")
	assert_eq(u.visit.stage, "strike")
	var view := Units.visit_view(u)
	assert_eq(view.check, "Attack")
	assert_eq(view.dc, 12)
	assert_eq(Units.stage_text(u), "attacking a building")
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "done")
	assert_true(u.visit.destroyed)
	assert_eq(Game.tile(wall)["b"], "ai_wall", "it comes down when the party presses Continue")
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station")
	assert_false(u.has("visit"))
	assert_eq(Game.ai["walls"], 4)
	assert_eq(Game.ai["relations"], 20)
	assert_eq(u.carry, {"metal": 12}, "4 metal on the dice, times the loot scale of 3")
	assert_eq(Game.tile(wall)["b"], "", "gone")


func test_a_failed_attack_leaves_the_wall_and_hurts_the_roller_and_it_can_be_tried_again() -> void:
	var u := _scout_next_to_a_wall()
	var wall: Vector2i = _wall_tiles()[0]
	Units.dice = ForcedDice.new([10, 20, 5], [3])   # a miss (DC 12), then a natural 20 on the second go
	Units.begin_strike(u.id, wall)
	Units.visit_do(u.id)
	assert_false(u.visit.destroyed)
	assert_eq(u.survivors.filter(func(s): return s.injury == "light").size(), 1, "a light injury")
	Units.visit_finish(u.id)
	assert_eq(Game.tile(wall)["b"], "ai_wall")
	assert_eq(u.stage, "station")
	assert_has(Units.strike_targets(u), wall, "it stands, so the party can try again")
	Units.begin_strike(u.id, wall)
	Units.visit_do(u.id)
	Units.visit_finish(u.id)
	assert_eq(Game.tile(wall)["b"], "", "the second attack worked")


func test_a_bad_miss_costs_half_of_what_the_party_carries() -> void:
	var u := _scout_next_to_a_wall()
	var wall: Vector2i = _wall_tiles()[0]
	u.carry = {"metal": 11, "gold": 4}
	Units.dice = ForcedDice.new([1])
	Units.begin_strike(u.id, wall)
	Units.visit_do(u.id)
	Units.visit_finish(u.id)
	assert_eq(u.carry, {"metal": 6, "gold": 2}, "half of each, rounded down off what is lost")
	assert_eq(u.survivors.filter(func(s): return s.injury == "severe").size(), 1)


func test_backing_off_leaves_the_wall_and_the_party_unhurt() -> void:
	var u := _scout_next_to_a_wall()
	var wall: Vector2i = _wall_tiles()[0]
	Units.dice = ForcedDice.new([])
	Units.begin_strike(u.id, wall)
	assert_eq(Units.visit_view(u).buttons.map(func(b): return b.id), ["roll", "home"])
	Units.visit_do(u.id, "home")
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station")
	assert_eq(Game.tile(wall)["b"], "ai_wall")
	assert_eq(u.survivors.filter(func(s): return s.injury != "none").size(), 0)


func test_an_attack_in_progress_waits_through_the_season_and_cannot_be_recalled() -> void:
	var u := _scout_next_to_a_wall()
	Units.begin_strike(u.id, _wall_tiles()[0])
	Units.recall_scouts(u.id)
	assert_eq(u.stage, "site", "finish the attack first")
	Units.season_turn()
	assert_eq(u.stage, "site")
	assert_true(u.has("visit"))


func test_an_attack_in_progress_survives_saving() -> void:
	var u := _scout_next_to_a_wall()
	var wall: Vector2i = _wall_tiles()[0]
	Units.begin_strike(u.id, wall)
	Game.save_game("strike_test")
	World.new_game(99)
	assert_true(Game.load_game("strike_test"))
	DirAccess.remove_absolute(Game._path("strike_test"))
	var loaded: Dictionary = Units.units[0]
	assert_eq(loaded.stage, "site")
	assert_eq(loaded.visit.ruin, "building")
	assert_eq(loaded.visit.cell, [wall.x, wall.y])
	assert_eq(typeof(loaded.visit.cell[0]), TYPE_INT)
	assert_eq(typeof(loaded.visit.strike_dc), TYPE_INT)
	assert_eq(Units.visit_view(loaded).dc, 12, "the panel can still be built")
	assert_eq(Game.ai["walls"], 8)
	assert_eq(_wall_tiles().size(), 2)


func test_wall_tiles_and_the_season_count_survive_saving() -> void:
	Game.ai["walls"] = 12
	Game._sync_ai_walls()
	Game.buildings_lost = 2
	var before := _wall_tiles()
	Game.save_game("wall_test")
	World.new_game(99)
	assert_true(Game.load_game("wall_test"))
	DirAccess.remove_absolute(Game._path("wall_test"))
	assert_eq(_wall_tiles(), before)
	assert_eq(Game.buildings_lost, 2)


# ---------------------------------------------------------------- the Rust Kings attack your buildings

## A farm on one of your tiles `dx` tiles east of the HQ (east is toward their fort).
func _farm_east(dx: int) -> Vector2i:
	var c := Vector2i(hq.x + dx, hq.y)
	Game.tile(c)["o"] = Data.PLAYER
	Game.tile(c)["t"] = "sand"
	Game.tile(c)["b"] = "farm"
	return c


## Seeds the random numbers so the next randf() is (or is not) under the scouts' strike chance.
func _seed_scout_chance(fires: bool) -> void:
	for s in range(1, 500):
		seed(s)
		if (randf() < Data.AI_SCOUT_STRIKE) == fires:
			seed(s)
			return


func test_a_winning_rust_kings_raid_rolls_once_at_the_building_nearest_their_fort() -> void:
	Game.season = 10
	var east := _farm_east(2)
	var west := _farm_east(-2)
	Units.dice = ForcedDice.new([20])
	Game._ai_strikes(10.0, 10.0)
	assert_eq(Game.tile(east)["b"], "", "the one toward their fort fell")
	assert_eq(Game.tile(west)["b"], "farm")
	assert_true(Game.log_lines.any(func(l): return l.contains("The Rust Kings struck the farm")))


func test_double_your_defense_gets_them_a_second_roll_each_at_a_different_building() -> void:
	Game.season = 10
	var a := _farm_east(2)
	var b := _farm_east(1)
	var c := _farm_east(-2)
	Units.dice = ForcedDice.new([20, 20])
	Game._ai_strikes(20.0, 10.0)
	assert_eq([Game.tile(a)["b"], Game.tile(b)["b"], Game.tile(c)["b"]], ["", "", "farm"])


func test_their_planes_add_a_roll_unless_you_have_flak_towers() -> void:
	Game.season = 10
	Game.ai["plane"] = 1
	var farms := [_farm_east(3), _farm_east(2), _farm_east(1), _farm_east(-2)]
	Units.dice = ForcedDice.new([20, 20, 20])
	Game._ai_strikes(20.0, 10.0)   # one, one for double the defense, one for the planes
	assert_eq(farms.filter(func(c): return Game.tile(c)["b"] == "").size(), 3)
	for c in farms:
		Game.tile(c)["b"] = "farm"
	Game.buildings_lost = 0
	Game.upgrades.append("fv4")
	Units.dice = ForcedDice.new([20, 20])
	Game._ai_strikes(20.0, 10.0)
	assert_eq(farms.filter(func(c): return Game.tile(c)["b"] == "").size(), 2, "flak towers stop the bombers' roll")


func test_the_rust_kings_make_no_building_attacks_before_season_6() -> void:
	Game.season = 5
	var farm := _farm_east(2)
	Units.dice = ForcedDice.new([])   # any roll would be an error
	Game._ai_strikes(100.0, 1.0)
	assert_eq(Game.tile(farm)["b"], "farm")
	Game._ai_scout_strike(farm + Vector2i(1, 0))
	assert_eq(Game.tile(farm)["b"], "farm")


func test_the_season_cap_stops_their_raid_too() -> void:
	Game.season = 10
	var farm := _farm_east(2)
	Game.buildings_lost = Data.RAID_LOSS_CAP
	Units.dice = ForcedDice.new([])
	Game._ai_strikes(100.0, 1.0)
	assert_eq(Game.tile(farm)["b"], "farm")


func test_a_real_winning_raid_destroys_a_building_and_a_lost_one_does_not() -> void:
	Game.season = 10
	var farm := _farm_east(2)
	Game.ai["troops"] = 1000   # their raid wins
	Units.dice = ForcedDice.new([20, 20])
	seed(1)
	Game._ai_raid()
	assert_eq(Game.tile(farm)["b"], "", "a won raid also brought a building down")
	Game.ended()
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	Game.season = 10
	var other := _farm_east(2)
	Game.ai["troops"] = 0   # nothing to raid with: it is beaten back
	Units.dice = ForcedDice.new([])
	Game._ai_raid()
	assert_eq(Game.tile(other)["b"], "farm")


func test_a_scout_that_ends_its_move_next_to_an_outlying_building_may_attack_it() -> void:
	Game.season = 10
	var farm := Vector2i(hq.x + 3, hq.y + 1)   # 3.16 tiles from the HQ: outside the 3 tile core
	Game.tile(farm)["o"] = Data.PLAYER
	Game.tile(farm)["t"] = "sand"
	Game.tile(farm)["b"] = "farm"
	Units.dice = ForcedDice.new([20])
	_seed_scout_chance(true)
	Game._ai_scout_strike(farm + Vector2i(1, 1))
	assert_eq(Game.tile(farm)["b"], "", "the 10% came up and the roll hit")
	assert_true(Game.log_lines.any(func(l): return l.contains("A Rust Kings scout struck the farm") and l.contains("+0 vs DC 8")))


func test_a_scout_usually_leaves_it_alone() -> void:
	Game.season = 10
	var farm := Vector2i(hq.x + 3, hq.y + 1)
	Game.tile(farm)["o"] = Data.PLAYER
	Game.tile(farm)["t"] = "sand"
	Game.tile(farm)["b"] = "farm"
	Units.dice = ForcedDice.new([])
	_seed_scout_chance(false)
	Game._ai_scout_strike(farm + Vector2i(1, 1))
	assert_eq(Game.tile(farm)["b"], "farm")


func test_scouts_leave_the_core_and_far_away_buildings_alone() -> void:
	Game.season = 10
	var core := _farm_east(2)   # within 3 tiles of the HQ
	var lone := Vector2i(hq.x + 3, hq.y + 1)
	Game.tile(lone)["o"] = Data.PLAYER
	Game.tile(lone)["t"] = "sand"
	Game.tile(lone)["b"] = "farm"
	Units.dice = ForcedDice.new([])
	_seed_scout_chance(true)
	Game._ai_scout_strike(core + Vector2i(0, -1))   # next to the core one only (and 3+ tiles from the lone one)
	assert_eq(Game.tile(core)["b"], "farm", "the HQ's core is out of their reach")
	_seed_scout_chance(true)
	Game._ai_scout_strike(lone + Vector2i(0, 3))   # 3 tiles from it: too far
	assert_eq(Game.tile(lone)["b"], "farm")


func test_a_scout_reports_where_it_ended_its_move() -> void:
	var at := Game._ai_scout()
	assert_true(Game.in_bounds(at))
	assert_true(Game.knows_tile(Data.AI, at))


func test_a_scouts_frontier_is_every_unexplored_tile_beside_an_explored_one() -> void:
	# the brute force way, one tile at a time through the public calls
	var frontier := []
	var min_x := Game.w
	for y in Game.h:
		for x in Game.w:
			var c := Vector2i(x, y)
			if not Game.knows_tile(Data.AI, c) and Game.neighbors(c).any(func(n): return Game.knows_tile(Data.AI, n)):
				frontier.append(c)
				min_x = mini(min_x, x)
	assert_gt(frontier.size(), 0)
	for s in range(1, 30):
		seed(s)
		var at := Game._ai_scout()
		assert_has(frontier, at, "the scout picks a frontier tile (seed %d)" % s)
		assert_le(at.x, min_x + 2, "on the western edge")
		assert_true(Game.knows_tile(Data.AI, at), "and now knows it")
		# put the world back for the next draw
		World.new_game(7)
		Units.tribes = []
		Units.wild_spawns = false
		frontier = []
		min_x = Game.w
		for y in Game.h:
			for x in Game.w:
				var c := Vector2i(x, y)
				if not Game.knows_tile(Data.AI, c) and Game.neighbors(c).any(func(n): return Game.knows_tile(Data.AI, n)):
					frontier.append(c)
					min_x = mini(min_x, x)


func test_a_scout_with_nothing_unexplored_beside_anything_goes_nowhere() -> void:
	var mem: Array = Game.memory[Data.AI]
	for i in mem.size():
		mem[i] = [Data.NONE, ""]
	assert_eq(Game._ai_scout(), Vector2i(-1, -1))
