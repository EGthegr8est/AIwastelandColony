extends "res://tests/framework/test_case.gd"
## The Rust Kings' nukes, the late game only (Data.AI_NUKES, Game._ai_nukes): an airfield at season 46, a bomber at 50, warheads from 52, a strike planned and then landed
## the season after, the counters (watchtowers warn, flak towers shoot the bomber down), and the airfield that you can destroy to stop it all.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const World = preload("res://tests/helpers/world.gd")

var fort: Vector2i
var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.units = []
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	fort = Game.home(Data.AI)
	hq = Game.home(Data.PLAYER)
	Game.season = 40
	for k in ["metal", "stone", "gold"]:
		Game.ai[k] = 500
	# Rust Kings land a good way round the fort, all free
	for dx in range(-8, 9):
		for dy in range(-8, 9):
			var c := fort + Vector2i(dx, dy)
			if Game.in_bounds(c) and Game.tile(c)["t"] != "water" and Game.tile(c)["b"] == "":
				Game.tile(c)["o"] = Data.AI


func _airfields() -> Array:
	var out := []
	for i in Game.tiles.size():
		if Game.tiles[i]["b"] == "ai_airfield":
			out.append(Vector2i(i % Game.w, i / Game.w))
	return out


## An airfield, a bomber and a warhead, all ready: what a strike needs.
func _ready_to_strike() -> Vector2i:
	Game.season = 60
	Game._ai_nukes()
	var spots := _airfields()
	assert_eq(spots.size(), 1)
	Game.ai["bomber"] = 1
	Game.ai["nukes"] = 1
	return spots[0]


## Your buildings, in a cluster well away from everything: `n` farms in the 3 x 3 round `at`.
func _cluster(at: Vector2i, n: int) -> void:
	var cells := Game.blast_square(at)
	for i in n:
		Game.tile(cells[i])["b"] = "farm"
		Game.tile(cells[i])["o"] = Data.PLAYER


func _open_spot(from: Vector2i) -> Vector2i:
	return World.find_tile(func(c, t): return c.distance_to(hq) > 8 and c.distance_to(fort) > 12 and c.distance_to(from) > 6 and _plain(c))


func _plain(c: Vector2i) -> bool:
	for p in Game.blast_square(c):
		var t: Dictionary = Game.tile(p)
		if t["t"] != "sand" or t["b"] != "" or t["o"] != Data.NONE:
			return false
	return Game.blast_square(c).size() == 9


# ---------------------------------------------------------------- the schedule

func test_the_airfield_comes_at_season_46_on_their_land_by_the_fort_away_from_you() -> void:
	Game.season = 45
	Game._ai_nukes()
	assert_eq(_airfields().size(), 0, "not yet")
	Game.season = 46
	var before: Dictionary = Game.ai.duplicate()
	Game._ai_nukes()
	var spots := _airfields()
	assert_eq(spots.size(), 1)
	var spot: Vector2i = spots[0]
	assert_eq(Game.tile(spot)["o"], Data.AI)
	assert_ge(Vector2(spot).distance_to(Vector2(fort)), 3.0)
	assert_le(Vector2(spot).distance_to(Vector2(fort)), 6.0)
	for c in Game.owned(Data.AI):
		var d := Vector2(c).distance_to(Vector2(fort))
		if d >= 3.0 and d <= 6.0 and c != spot and Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water" and Game.slopes[Game.idx(c)] != "steep":
			assert_ge(Vector2(spot).distance_to(Vector2(hq)), Vector2(c).distance_to(Vector2(hq)), "no free tile of theirs in range is further from you")
	assert_eq(before.stone - Game.ai.stone, 40)
	assert_eq(before.gold - Game.ai.gold, 40)
	assert_eq(before.metal, Game.ai.metal, "no metal: they have none to spare")
	Game.season = 47
	Game._ai_nukes()
	assert_eq(_airfields().size(), 1, "one is all they build")


func test_they_cannot_build_what_they_cannot_pay_for() -> void:
	Game.season = 46
	Game.ai["gold"] = 39
	Game._ai_nukes()
	assert_eq(_airfields().size(), 0)
	Game.ai["gold"] = 40
	Game._ai_nukes()
	assert_eq(_airfields().size(), 1)


func test_one_bomber_at_season_50_and_only_with_an_airfield() -> void:
	Game.season = 46
	Game._ai_nukes()
	Game.season = 49
	Game._ai_nukes()
	assert_eq(Game.ai["bomber"], 0)
	Game.season = 50
	var gold: int = Game.ai.gold
	var stone: int = Game.ai.stone
	Game._ai_nukes()
	assert_eq(Game.ai["bomber"], 1)
	assert_eq(gold - Game.ai.gold, 60)
	assert_eq(stone - Game.ai.stone, 25)
	Game.season = 51
	Game._ai_nukes()
	assert_eq(Game.ai["bomber"], 1, "never more than one")
	# without an airfield there is nothing to build it at
	for c in _airfields():
		Game.tile(c)["b"] = ""
	Game.ai["bomber"] = 0
	Game.ai["airfield_wait"] = 99
	Game._ai_nukes()
	assert_eq(Game.ai["bomber"], 0)


func test_warheads_from_season_52_one_every_twelve_seasons_two_at_most() -> void:
	var seen := {}
	for s in range(40, 100):
		Game.season = s
		Game.ai["bomber"] = 0   # no bomber: nothing is planned or launched, the count is all there is to see
		Game.ai["airfield_wait"] = 99
		Game._ai_nukes()
		seen[s] = Game.ai["nukes"]
	assert_eq(seen[51], 0)
	assert_eq(seen[52], 1, "the first")
	assert_eq(seen[63], 1)
	assert_eq(seen[64], 2, "the second")
	assert_eq(seen[76], 2, "a third is not kept")


# ---------------------------------------------------------------- the strike

func test_a_strike_is_planned_about_three_seasons_in_ten_and_never_in_the_four_after_the_last() -> void:
	_ready_to_strike()
	_cluster(_open_spot(fort), 3)
	Game.season = 61
	seed(99)
	var planned := 0
	for i in 1000:
		Game.ai["nuke_x"] = -1
		Game.ai["nuke_y"] = -1
		Game.ai["last_strike"] = -99
		Game._ai_nukes()
		if Game.ai["nuke_x"] >= 0:
			planned += 1
	assert_ge(planned, 250, "about 300 of 1000")
	assert_le(planned, 350)
	for i in 200:
		Game.ai["nuke_x"] = -1
		Game.ai["last_strike"] = 61 - 3
		Game._ai_nukes()
		assert_eq(Game.ai["nuke_x"], -1, "three seasons after the last is too soon")


func test_it_aims_at_the_square_with_most_of_your_buildings_and_at_least_two() -> void:
	_ready_to_strike()
	var a := _open_spot(fort)
	_cluster(a, 3)
	var b := World.find_tile(func(c, t): return c.distance_to(a) > 12 and c.distance_to(hq) > 8 and c.distance_to(fort) > 12 and _plain(c))
	_cluster(b, 2)
	assert_ne(b, Vector2i(-1, -1))
	var target := Game._ai_nuke_target()
	assert_eq(Game.blast_square(target).filter(func(p): return Game.tile(p)["b"] == "farm").size(), 3, "the square with three")
	assert_le(maxi(absi(target.x - a.x), absi(target.y - a.y)), 1)
	for p in Game.blast_square(a):
		Game.tile(p)["b"] = ""
	for p in Game.blast_square(b):
		Game.tile(p)["b"] = ""
	var one := _open_spot(fort)
	_cluster(one, 1)
	assert_eq(Game._ai_nuke_target(), Vector2i(-1, -1), "one building is not worth a warhead")


func test_your_hq_and_other_peoples_buildings_do_not_count() -> void:
	_ready_to_strike()
	var at := _open_spot(fort)
	var cells := Game.blast_square(at)
	Game.tile(cells[0])["b"] = "hq"
	Game.tile(cells[0])["o"] = Data.PLAYER
	Game.tile(cells[1])["b"] = "farm"
	Game.tile(cells[1])["o"] = Data.NONE
	Game.tile(cells[2])["b"] = "farm"
	Game.tile(cells[2])["o"] = Data.PLAYER
	assert_eq(Game._ai_nuke_target(), Vector2i(-1, -1), "an HQ cannot be taken and a free farm is nobody's")


func test_the_strike_lands_the_season_after_it_is_planned() -> void:
	_ready_to_strike()
	var at := _open_spot(fort)
	_cluster(at, 3)
	var victim: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", at, at)
	victim.crew = 3
	victim.survivors = Units._make_crew(3)
	Units.units.append(victim)
	Game.season = 61
	Game.ai["last_strike"] = -99
	seed(3)
	for i in 100:   # until it is planned
		Game._ai_nukes()
		if Game.ai["nuke_x"] >= 0:
			break
	assert_ge(Game.ai["nuke_x"], 0, "planned")
	assert_eq(Game.stats.nukes_suffered, 0, "and not landed in the same turn")
	var target := Vector2i(Game.ai["nuke_x"], Game.ai["nuke_y"])
	var seen := watch(Game, "focus")
	Game.season = 62
	var land := Game.owned(Data.PLAYER).size()
	Game._ai_nukes()
	assert_eq(Game.tile(target)["t"], "ash")
	assert_eq(Game.ai["nukes"], 0)
	assert_eq(Game.ai["bomber"], 1, "the bomber comes home")
	assert_eq(Game.ai["last_strike"], 62)
	assert_eq(Game.ai["nuke_x"], -1)
	assert_eq(Game.stats.nukes_suffered, 1)
	assert_eq(Game.stats.blasts, 1)
	assert_true(victim.get("gone", false), "the party in the square died")
	assert_eq(Game.blast_square(target).filter(func(p): return Game.tile(p)["b"] == "farm").size(), 0, "and the buildings fell")
	assert_eq(Game.owned(Data.PLAYER).size(), land, "but the land is still yours")
	assert_eq(seen.count, 1, "the camera jumps to it")
	assert_eq(seen.emissions[0][0], target)
	assert_true(Game.log_lines.any(func(l): return l.contains("dropped by the Rust Kings' bomber")))


func test_flak_towers_shoot_it_down_about_seven_times_in_ten() -> void:
	var spot := _ready_to_strike()
	Game.upgrades.append("fv4")
	var target := _open_spot(fort)
	seed(7)
	var down := 0
	for i in 300:
		Game.ai["bomber"] = 1
		Game.ai["nukes"] = 1
		Game._ai_launch(target)
		if Game.ai["bomber"] == 0:
			down += 1
	assert_ge(down, 170, "about 210 of 300")
	assert_le(down, 250)
	Game.ai["bomber"] = 1
	Game.ai["nukes"] = 1
	Game.upgrades.erase("fv4")
	for i in 20:
		Game.ai["bomber"] = 1
		Game.ai["nukes"] = 1
		Game._ai_launch(target)
		assert_eq(Game.ai["bomber"], 1, "no flak, nothing is shot down")
	assert_true(Game.log_lines.any(func(l): return l.contains("FLAK") and l.contains("shot down")))
	assert_eq(spot, _airfields()[0])


func test_watchtowers_warn_with_the_tile_and_nothing_else_does() -> void:
	_ready_to_strike()
	_cluster(_open_spot(fort), 3)
	Game.season = 61
	seed(5)
	for i in 100:
		Game._ai_nukes()
		if Game.ai["nuke_x"] >= 0:
			break
	assert_false(Game.log_lines.any(func(l): return l.contains("WATCHTOWER: a Rust Kings bomber")), "no watchtower, no warning")
	Game.ai["nuke_x"] = -1
	Game.ai["last_strike"] = -99
	Game.upgrades.append("f3")
	for i in 100:
		Game._ai_nukes()
		if Game.ai["nuke_x"] >= 0:
			break
	var line := ""
	for l in Game.log_lines:
		if l.contains("WATCHTOWER: a Rust Kings bomber"):
			line = l
	assert_has(line, "%d,%d" % [Game.ai["nuke_x"], Game.ai["nuke_y"]])


# ---------------------------------------------------------------- their airfield

func test_the_airfield_is_a_building_you_can_attack_with_a_dc_of_12() -> void:
	var spot := _ready_to_strike()
	assert_eq(Game.building_dc(spot), 12)
	assert_true(Game.can_hit(spot))
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", spot + Vector2i(1, 0), spot + Vector2i(1, 0))
	u.stage = "station"
	u.crew = 2
	u.survivors = Units._make_crew(2)
	Units.units.append(u)
	assert_has(Units.strike_targets(u), spot)


func test_destroying_the_last_airfield_calls_off_a_planned_strike_and_stops_launches() -> void:
	var spot := _ready_to_strike()
	Game.ai["nuke_x"] = 5
	Game.ai["nuke_y"] = 5
	Game.destroy_building(spot)
	assert_eq(Game.tile(spot)["b"], "")
	assert_eq(Game.ai["airfield_wait"], 8)
	assert_eq(Game.ai["nuke_x"], -1, "called off")
	assert_eq(Game.stats.airfields_destroyed, 1)
	assert_eq(Game.stats.enemy_buildings_destroyed, 1)
	assert_true(Game.log_lines.any(func(l): return l.contains("airfield is destroyed")))
	assert_eq(Game.ai["bomber"], 1, "the bomber and the warhead wait on the ground")
	assert_eq(Game.ai["nukes"], 1)
	for i in 5:
		Game.season = 61 + i
		Game._ai_nukes()
		assert_eq(Game.stats.nukes_suffered, 0, "nothing launches")
		assert_eq(Game.ai["nuke_x"], -1)


func test_they_rebuild_after_eight_seasons_if_they_can_pay_and_not_before() -> void:
	var spot := _ready_to_strike()
	Game.destroy_building(spot)
	for i in 7:
		Game.season = 61 + i
		Game._ai_nukes()
		assert_eq(_airfields().size(), 0, "season %d after it fell" % (i + 1))
	Game.ai["gold"] = 0
	Game.season = 68
	Game._ai_nukes()
	assert_eq(_airfields().size(), 0, "eight seasons, but they cannot pay")
	Game.ai["gold"] = 500
	Game.season = 69
	Game._ai_nukes()
	assert_eq(_airfields().size(), 1, "and now they can")
	assert_eq(Game.ai["bomber"], 1, "the bomber was kept")
	assert_ge(Game.ai["nukes"], 1, "and the warheads (a second came at season 64)")


func test_a_nuke_of_yours_on_the_airfield_takes_it_down_too() -> void:
	var spot := _ready_to_strike()
	Game.detonate(spot, "bomber")
	assert_eq(Game.tile(spot)["b"], "")
	assert_eq(Game.ai["airfield_wait"], 8)
	assert_eq(Game.stats.airfields_destroyed, 1)


func test_diplomacy_says_whether_you_have_found_it_and_when_it_is_rebuilt() -> void:
	var spot := _ready_to_strike()
	assert_eq(Game.airfield_text(), "Their airfield: not found.")
	Game.memory[Data.PLAYER][Game.idx(spot)] = [Data.AI, "ai_airfield"]
	Game.check_airfield()
	assert_eq(Game.ai["airfield_seen"], 1)
	assert_has(Game.airfield_text(), "Their airfield stands at %d,%d" % [spot.x, spot.y])
	assert_has(Game.airfield_text(), "DC 12")
	assert_true(Game.log_lines.any(func(l): return l.contains("found the Rust Kings' airfield")))
	Game.destroy_building(spot)
	assert_eq(Game.airfield_text(), "Their airfield is destroyed: they rebuild it in 8 seasons.")


func test_it_all_survives_a_save_and_an_old_save_has_none_of_it() -> void:
	var spot := _ready_to_strike()
	Game.ai["nuke_x"] = 9
	Game.ai["nuke_y"] = 8
	Game.ai["last_strike"] = 55
	Game.save_game("rk_nukes")
	World.new_game(3)
	assert_true(Game.load_game("rk_nukes"))
	assert_eq(Game.tile(spot)["b"], "ai_airfield")
	assert_eq([Game.ai["bomber"], Game.ai["nukes"], Game.ai["nuke_x"], Game.ai["nuke_y"], Game.ai["last_strike"]], [1, 1, 9, 8, 55])
	var path := Game.save_dir + "rk_nukes.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	for k in ["bomber", "nukes", "airfield_wait", "airfield_x", "airfield_y", "airfield_seen", "nuke_x", "nuke_y", "last_strike"]:
		data["ai"].erase(k)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(Game.load_game("rk_nukes"))
	assert_eq([Game.ai["bomber"], Game.ai["nukes"], Game.ai["nuke_x"], Game.ai["last_strike"]], [0, 0, -1, -99])
	DirAccess.remove_absolute(path)
