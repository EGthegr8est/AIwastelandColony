extends "res://tests/framework/test_case.gd"
## Picking a scouting party: its route is drawn from where it stands, and fades from white to red
## as its food runs out.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i
var party: Dictionary   # a foot party keeping watch a few tiles from home
var far: Vector2i       # a tile well beyond it, more than a pack's worth of days away when the pack is small


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false   # no raiders wander into the middle of a test
	Game.res["grain"] = 100
	hq = Game.home(Data.PLAYER)
	var near := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 6 and c.distance_to(hq) < 10 \
		and not Game.route("foot", hq, c).is_empty())
	Units.send("scout", "foot", near)
	party = Units.units[-1]
	for i in 12:
		if party.stage == "station":
			break
		Units.season_turn()
	assert_eq(party.stage, "station")
	far = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(party.pos) > 45 and c.distance_to(party.pos) < 70 \
		and not Game.route("foot", party.pos, c).is_empty())
	assert_ne(far, Vector2i(-1, -1), "needs a reachable tile a long way out")


func test_clicking_a_scouting_party_picks_it() -> void:
	assert_eq(Game.selected_scout, -1)
	Game.select(party.pos)
	assert_eq(Game.selected_scout, party.id)
	assert_true(Game.preview.is_empty(), "routes from your HQ give way to the party's own")
	assert_true(Game.scout_route.is_empty(), "nowhere to go yet: it's keeping watch right here")


func test_the_route_starts_where_the_party_stands() -> void:
	Game.select(party.pos)
	Game.select(far)
	assert_eq(Game.selected_scout, party.id, "it stays picked while you choose where to send it")
	var route: Dictionary = Game.scout_route
	assert_eq(route.mover, "foot")
	assert_eq(route.path[0], party.pos)
	assert_eq(route.path[-1], far)
	assert_eq(route.ratio.size(), route.path.size())
	assert_eq(route.days.size(), route.path.size())
	assert_eq(route.ratio[0], 0.0)
	assert_true(Game.preview.is_empty())
	for i in range(1, route.ratio.size()):
		assert_ge(route.ratio[i], route.ratio[i - 1], "food only goes down")


func test_the_route_turns_red_where_the_food_runs_out() -> void:
	party.food = {"grain": 2}   # two eaters: lasts SEASON_DAYS / SCOUT_RATION days
	var lasts := Units.food_days(party)
	Game.select(party.pos)
	Game.select(far)
	var route: Dictionary = Game.scout_route
	assert_gt(route.days[-1], lasts, "the trip is longer than the pack lasts")
	var out: int = route.ratio.find_custom(func(r): return r >= 1.0)
	assert_gt(out, 0, "it runs out somewhere along the way")
	assert_ge(route.days[out], lasts)
	assert_lt(route.days[out - 1], lasts, "the tile before it is still fed")
	assert_ge(route.ratio[-1], 1.0)
	# and what the map would draw there
	var MapView = preload("res://scripts/map_view.gd")
	assert_eq(MapView.food_color(route.ratio[out]), MapView.FOOD_OUT)
	assert_ne(MapView.food_color(route.ratio[out - 1]), MapView.FOOD_OUT)
	assert_eq(MapView.food_color(route.ratio[1]), MapView.food_color(route.days[1] / lasts))


func test_a_full_pack_keeps_a_short_route_white_to_yellow() -> void:
	var short := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(party.pos) > 3 and c.distance_to(party.pos) < 6 \
		and not Game.route("foot", party.pos, c).is_empty())
	Game.select(party.pos)
	Game.select(short)
	assert_lt(Game.scout_route.ratio[-1], 1.0, "plenty of food for a short walk")


func test_an_empty_pack_makes_the_whole_route_red() -> void:
	party.food = {}
	Game.select(party.pos)
	Game.select(far)
	var ratios: Array = Game.scout_route.ratio
	assert_eq(ratios[0], 0.0)
	for i in range(1, ratios.size()):
		assert_true(is_inf(ratios[i]))


func test_the_route_follows_the_food_as_seasons_pass() -> void:
	Game.select(party.pos)
	Game.select(far)
	var before: float = Game.scout_route.ratio[1]
	party.food = {"grain": 1}
	Game.changed.emit()
	assert_gt(Game.scout_route.ratio[1], before)


func test_a_party_on_the_way_shows_the_rest_of_its_path() -> void:
	Units.send("scout", "foot", far)
	var out: Dictionary = Units.units[-1]
	assert_eq(out.stage, "out")
	Game.select(out.pos)   # still at your HQ: it's only just left
	assert_eq(Game.selected_scout, out.id)
	var route: Dictionary = Game.scout_route
	assert_eq(route.path[0], out.pos)
	assert_eq(route.path[-1], far)


func test_deselecting_brings_back_the_routes_from_your_hq() -> void:
	Game.select(party.pos)
	Game.select(far)
	Game.deselect_scout()
	assert_eq(Game.selected_scout, -1)
	assert_true(Game.scout_route.is_empty())
	assert_eq(Game.selected, far, "the tile stays selected")
	assert_has(Game.preview, "foot")
	assert_eq(Game.preview["foot"][0], hq)


func test_clicking_your_own_land_lets_go_of_the_party() -> void:
	Game.select(party.pos)
	Game.select(far)
	assert_eq(Game.selected_scout, party.id)
	Game.select(hq + Vector2i(1, 0))
	assert_eq(Game.tile(Game.selected)["o"], Data.PLAYER)
	assert_eq(Game.selected_scout, -1)
	assert_has(Game.preview, "foot", "you're choosing where to build: routes from home")


func test_clicking_another_party_picks_that_one_instead() -> void:
	Units.send("scout", "foot", far)
	var other: Dictionary = Units.units[-1]
	Game.select(party.pos)
	assert_eq(Game.selected_scout, party.id)
	Game.select(other.pos)
	assert_eq(Game.selected_scout, other.id)
	Game.pick_scout(party.id)
	assert_eq(Game.selected_scout, party.id)


func test_a_party_that_is_gone_is_dropped() -> void:
	Game.select(party.pos)
	Game.select(far)
	Units.units.erase(party)
	Game.changed.emit()
	assert_eq(Game.selected_scout, -1)
	assert_true(Game.scout_route.is_empty())
	assert_has(Game.preview, "foot", "back to routes from your HQ")


func test_other_expeditions_do_not_pick_a_scout() -> void:
	var ruins := World.find_tile(func(c, t): return t["t"] == "ruins" and not Game.route("foot", hq, c).is_empty())
	assert_ne(ruins, Vector2i(-1, -1))
	Units.send("scav", "foot", ruins)
	Game.select(Units.units[-1].pos)
	assert_eq(Game.selected_scout, -1)
