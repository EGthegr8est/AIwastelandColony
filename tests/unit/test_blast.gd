extends "res://tests/framework/test_case.gd"
## A nuke going off (Game.detonate): the 3 by 3 square round it turns to scorched ash and reads 120 R/h, every party, wild animal and camp in it is gone, the buildings fall
## (but not an HQ, a fort, Dustwell, the old bridge or a point of interest), water and glowing craters stay what they were, and the Giant Frog is not hurt.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var centre: Vector2i
var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.units = []
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	# an open stretch, well away from every camp: 5 x 5 tiles of plain ground with nothing built on it
	centre = World.find_tile(func(c, t): return _plain(c) and c.distance_to(hq) > 14 and c.distance_to(Game.home(Data.AI)) > 14)
	assert_ne(centre, Vector2i(-1, -1), "needs a clear stretch")


func _plain(c: Vector2i) -> bool:
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var p := c + Vector2i(dx, dy)
			if not Game.in_bounds(p):
				return false
			var t: Dictionary = Game.tile(p)
			if not t["t"] in ["sand", "dunes", "scrub"] or t["b"] != "" or Game.slopes[Game.idx(p)] != "":
				return false
	return true


func _party(at: Vector2i, mover := "foot", owner := Data.PLAYER, job := "scav") -> Dictionary:
	var u: Dictionary = Units._make_unit(job, owner, mover, at, at)
	u.crew = 3
	u.survivors = Units._make_crew(3) if owner == Data.PLAYER else []
	u.stage = "site"
	Units.units.append(u)
	return u


# ---------------------------------------------------------------- the square

func test_the_square_is_nine_tiles_and_less_at_the_edge() -> void:
	assert_eq(Game.blast_square(centre).size(), 9)
	assert_eq(Game.blast_square(Vector2i(0, 0)).size(), 4, "a corner of the map")
	assert_eq(Game.blast_square(Vector2i(5, 0)).size(), 6, "an edge")
	assert_eq(Game.blast_square(Vector2i(Game.w - 1, Game.h - 1)).size(), 4)
	for p in Game.blast_square(centre):
		assert_le(maxi(absi(p.x - centre.x), absi(p.y - centre.y)), 1)


func test_every_tile_of_the_square_turns_to_hot_ash() -> void:
	var varied := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var kinds := ["ruins", "rock", "trees", "glass"]
	for i in 4:
		Game.tile(centre + varied[i])["t"] = kinds[i]
	var version := Game.map_version
	var report := Game.detonate(centre, "bomber")
	assert_eq(report.cells.size(), 9)
	for p in Game.blast_square(centre):
		assert_eq(Game.tile(p)["t"], "ash", str(p))
		assert_ge(Game.radiation(p), 120, "extreme")
		assert_true(Game.is_measured(p), "everyone saw it: the reading is known")
	assert_gt(Game.map_version, version, "the map redraws its ground")
	for p in [centre + Vector2i(2, 0), centre + Vector2i(0, -2), centre + Vector2i(2, 2)]:
		assert_ne(Game.tile(p)["t"], "ash", "nothing outside the square")
		assert_lt(Game.radiation(p), 120)


func test_water_and_glowing_craters_stay_what_they_were() -> void:
	Game.tile(centre + Vector2i(1, 1))["t"] = "water"
	Game.tile(centre + Vector2i(-1, -1))["t"] = "crater"
	Game.detonate(centre, "bomber")
	assert_eq(Game.tile(centre + Vector2i(1, 1))["t"], "water")
	assert_eq(Game.tile(centre + Vector2i(-1, -1))["t"], "crater")
	assert_ge(Game.radiation(centre + Vector2i(1, 1)), 120, "but they are hot")
	assert_ge(Game.radiation(centre + Vector2i(-1, -1)), 120)
	assert_eq(Game.tile(centre)["t"], "ash")


func test_a_crater_search_spends_the_crater_it_went_off_in() -> void:
	Game.tile(centre)["t"] = "crater"
	Game.detonate(centre, "crater")
	assert_eq(Game.tile(centre)["t"], "crater", "still a crater")
	assert_eq(Game.tile(centre)["r"], "picked", "and spent")
	assert_eq(Game.tile(centre + Vector2i(1, 0))["t"], "ash")


func test_the_ash_is_its_own_ground_that_moves_like_sand_and_yields_nothing() -> void:
	assert_eq(Data.TERRAIN.ash.name, "Scorched ash sand")
	assert_true(Data.TERRAIN.ash.yield.is_empty())
	assert_eq(Game.ground_speed("ash", "foot"), 1.0)
	assert_false("ash" in Data.BUILDINGS.farm.on, "no farms on it")
	var c := centre + Vector2i(1, 0)
	Game.tile(c)["t"] = "ruins"
	Game._update_paths_at([c])
	assert_almost_eq(Game.move_mult("foot", c), 1.3, 0.0001, "ruins slow a party on foot")
	Game.detonate(centre, "bomber")
	assert_almost_eq(Game.move_mult("foot", c), 1.0, 0.0001, "the ash does not")
	assert_almost_eq(Game.paths["foot"].get_point_weight_scale(c), 1.0, 0.0001, "and the route finder knows it")


func test_a_blast_at_the_edge_of_the_map_works() -> void:
	var report := Game.detonate(Vector2i(0, 0), "bomber")
	assert_eq(report.cells.size(), 4)
	assert_has(["ash", "water", "crater"], Game.tile(Vector2i(0, 0))["t"])


func test_ending_the_season_cools_the_ash() -> void:
	Game.detonate(centre, "bomber")
	Game.end_season()
	assert_eq(Game.radiation(centre), 118)


func test_the_ash_cools_two_a_season_down_to_sixty() -> void:
	Game.detonate(centre, "bomber")
	Game._cool_ash()
	assert_eq(Game.radiation(centre), 118)
	for i in 40:
		Game._cool_ash()
	assert_eq(Game.radiation(centre), 60, "and no further")
	var plain := centre + Vector2i(3, 0)
	var before := Game.radiation(plain)
	Game._cool_ash()
	assert_eq(Game.radiation(plain), before, "nothing else cools")


# ---------------------------------------------------------------- who is caught

func test_every_party_of_every_owner_in_the_square_dies() -> void:
	var mine := _party(centre)
	var rig := _party(centre + Vector2i(1, 1), "car")
	Game.vehicles["car"] = 1
	var band := _party(centre + Vector2i(-1, 0), "foot", Data.NONE, "band")
	var far := _party(centre + Vector2i(2, 0))
	var spared := _party(centre + Vector2i(0, 1))
	var pop := Game.pop
	var lost: int = Game.stats.survivors_lost
	var report := Game.detonate(centre, "bomber", [spared.id])
	assert_eq(report.kills.parties, 3)
	assert_eq(report.kills.yours, 2)
	assert_eq(report.kills.people, 6)
	for u in [mine, rig, band]:
		assert_false(Units.units.has(u), "gone from the map")
	assert_true(Units.units.has(far), "two tiles away is safe")
	assert_true(Units.units.has(spared), "the bomber, or the party that rolled it, lives")
	assert_eq(Game.pop, pop, "the crew never come home")
	assert_eq(Game.stats.survivors_lost, lost + 6)
	assert_eq(Game.vehicles["car"], 0, "and the war rig is lost with its crew")
	assert_eq(mine.crew, 0)


func test_a_party_in_the_middle_of_a_visit_dies_too() -> void:
	var u := _party(centre + Vector2i(1, 0))
	u["visit"] = {"ruin": "safe", "stage": "event"}
	Game.detonate(centre, "bomber")
	assert_false(u.has("visit"), "its panel goes with it")
	assert_false(Units.units.has(u))


func test_wild_animals_die_and_camps_are_wiped_out_but_the_frog_is_not_hurt() -> void:
	Units.animals.append({"id": 900, "kind": "deer", "pos": centre, "home": centre})
	Units.animals.append({"id": 901, "kind": "deer", "pos": centre + Vector2i(3, 0), "home": centre})
	Units.tribes.append({"id": 902, "class": "raider", "name": "Ash Walkers", "pos": centre + Vector2i(1, 0), "strength": 5, "relations": 0, "found": true})
	Units.tribes.append({"id": 903, "class": "trader", "name": "Far camp", "pos": centre + Vector2i(4, 4), "strength": 1, "relations": 0, "found": true})
	var frog_before: Dictionary = Units.frog.duplicate()
	Units.frog["state"] = "loose"
	Units.frog["pos"] = centre
	var report := Game.detonate(centre, "bomber")
	assert_eq(report.kills.animals, 1)
	assert_eq(report.kills.camps, 1)
	assert_eq(Units.animals.size(), 1, "the deer outside lives")
	assert_eq(Units.tribes.size(), 1)
	assert_eq(Units.tribes[0].name, "Far camp")
	assert_eq(Units.frog.get("state"), "loose", "the frog is too big for it")
	assert_eq(Units.frog.get("pos"), centre)
	Units.frog = frog_before


# ---------------------------------------------------------------- what falls

func _build(c: Vector2i, building: String, owner: int) -> void:
	Game.tile(c)["b"] = building
	Game.tile(c)["o"] = owner


func test_buildings_fall_and_the_old_highway_goes_with_them() -> void:
	_build(centre, "farm", Data.PLAYER)
	_build(centre + Vector2i(1, 0), "wall", Data.PLAYER)
	_build(centre + Vector2i(0, 1), "old_road", Data.NONE)
	_build(centre + Vector2i(-1, 0), "road", Data.PLAYER)
	Game.refinery_on[Game.idx(centre)] = true
	var lost: int = Game.stats.buildings_lost
	var report := Game.detonate(centre, "bomber")
	assert_eq(report.buildings, 4)
	for p in [centre, centre + Vector2i(1, 0), centre + Vector2i(0, 1), centre + Vector2i(-1, 0)]:
		assert_eq(Game.tile(p)["b"], "", str(p))
	assert_eq(Game.stats.buildings_lost, lost + 3, "the three of yours are counted")
	assert_false(Game.refinery_on.has(Game.idx(centre)))
	assert_eq(Game.tile(centre)["o"], Data.PLAYER, "the land is still yours: ash sand")


func test_an_hq_a_fort_dustwell_the_old_bridge_and_a_site_stand() -> void:
	_build(centre, "hq", Data.PLAYER)
	_build(centre + Vector2i(1, 0), "ai_hq", Data.AI)
	_build(centre + Vector2i(-1, 0), "town", Data.TOWN)
	_build(centre + Vector2i(0, 1), "old_bridge", Data.NONE)
	_build(centre + Vector2i(0, -1), "poi_bunker", Data.NONE)
	var report := Game.detonate(centre, "bomber")
	assert_eq(report.buildings, 0)
	assert_eq(Game.tile(centre)["b"], "hq")
	assert_eq(Game.tile(centre + Vector2i(1, 0))["b"], "ai_hq")
	assert_eq(Game.tile(centre + Vector2i(-1, 0))["b"], "town")
	assert_eq(Game.tile(centre + Vector2i(0, 1))["b"], "old_bridge")
	assert_eq(Game.tile(centre + Vector2i(0, -1))["b"], "poi_bunker")
	assert_eq(Game.tile(centre)["t"], "ash", "though the ground under them is ash like the rest")


func test_a_strike_on_the_rust_kings_costs_ten_relations_a_building_but_an_accident_does_not() -> void:
	_build(centre, "ai_wall", Data.AI)
	_build(centre + Vector2i(1, 0), "ai_wall", Data.AI)
	_build(centre + Vector2i(0, 1), "tower", Data.AI)
	Game.ai["walls"] = 8
	Game.ai["relations"] = 0
	var theirs: int = Game.stats.enemy_buildings_destroyed
	Game.detonate(centre, "crater")
	assert_eq(Game.ai["relations"], 0, "a search that went wrong at their wall costs nothing")
	_build(centre, "ai_wall", Data.AI)
	_build(centre + Vector2i(1, 0), "ai_wall", Data.AI)
	_build(centre + Vector2i(0, 1), "tower", Data.AI)
	Game.ai["walls"] = 8
	Game.detonate(centre, "bomber")
	assert_eq(Game.ai["relations"], -30, "ten for each of the three")
	assert_eq(Game.ai["walls"], 0, "each wall tile stands for four of their walls")
	assert_eq(Game.stats.enemy_buildings_destroyed, theirs + 6)


# ---------------------------------------------------------------- how it shows

func test_a_live_blast_tells_the_map_and_a_held_one_waits() -> void:
	var seen := watch(Game, "blasted")
	Game.detonate(centre, "bomber")
	assert_eq(seen.count, 1)
	assert_eq(seen.emissions[0][0], centre)
	Game.detonate(centre + Vector2i(5, 0), "bomber", [], -1.0, true)
	assert_eq(seen.count, 1, "held until the die lands")
	assert_eq(Game.held_blasts.size(), 1)
	Game.release_blasts()
	assert_eq(seen.count, 2)
	assert_true(Game.held_blasts.is_empty())


func test_in_a_season_the_replay_plays_the_blast_on_the_day_it_happened() -> void:
	Units._record_start()
	var seen := watch(Game, "blasted")
	Game.detonate(centre, "bomber", [], 12.5)
	Units._recording = false
	assert_eq(seen.count, 0, "the replay shows it, not the live effect")
	var blasts: Array = Units.replay.events.filter(func(e): return e.kind == "blast")
	assert_eq(blasts.size(), 1)
	assert_eq(blasts[0].cell, centre)
	assert_eq(blasts[0].day, 12.5)


func test_a_party_killed_in_the_replay_leaves_the_map_when_the_bomb_falls() -> void:
	var u := _party(centre + Vector2i(1, 0))
	Units._record_start()
	Game.detonate(centre, "bomber", [], 9.0)
	var actor: Dictionary = Units._actors[u.id]
	Units._recording = false
	assert_eq(actor.gone_day, 9.0)
	assert_true(u.get("gone", false), "gone, to be dropped at the end of the season")


func test_the_log_says_what_happened() -> void:
	_build(centre, "farm", Data.PLAYER)
	_party(centre)
	Game.detonate(centre, "bomber")
	assert_true(Game.log_lines.any(func(l): return l.contains("A NUKE WENT OFF") and l.contains("dropped by your bomber") and l.contains("1 building fell") and l.contains("1 party died")))
	Game.detonate(centre + Vector2i(6, 0), "crater")
	assert_true(Game.log_lines.any(func(l): return l.contains("under your scavengers")))
	assert_eq(Game.stats.blasts, 2)


# ---------------------------------------------------------------- saving

func test_a_save_keeps_the_ash_the_nukes_and_the_bombers() -> void:
	Game.items["nuke"] = 2
	Game.vehicles["bomber"] = 1
	Game.detonate(centre, "bomber")
	Game.save_game("nukes")
	World.new_game(3)
	assert_eq(Game.items["nuke"], 0)
	assert_true(Game.load_game("nukes"))
	assert_eq(Game.items["nuke"], 2)
	assert_eq(Game.vehicles["bomber"], 1)
	assert_eq(Game.tile(centre)["t"], "ash")
	assert_ge(Game.radiation(centre), 120)
	DirAccess.remove_absolute(Game.save_dir + "nukes.json")


func test_a_save_from_before_bombers_loads_with_none() -> void:
	Game.save_game("old")
	var path := Game.save_dir + "old.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["vehicles"].erase("bomber")
	data["items"].erase("nuke")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(Game.load_game("old"))
	assert_eq(Game.vehicles["bomber"], 0)
	assert_eq(Game.items["nuke"], 0)
	DirAccess.remove_absolute(path)
