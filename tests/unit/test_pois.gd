extends "res://tests/framework/test_case.gd"
## The points of interest: ten 2 x 2 sites placed when the map is made, drawn as sprites, remembered by the fog,
## saved, and scavenged as one tile.

const Data = preload("res://scripts/data.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const Sprites = preload("res://scripts/sprites.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false


## Top-left tile of every site on the map, by kind: {"bunker": [Vector2i, ...], ...}.
func _sites() -> Dictionary:
	var out := {}
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		var kind := Game.poi_kind(c)
		if kind != "" and Game.poi_quadrant(c) == Vector2i.ZERO:
			if not out.has(kind):
				out[kind] = []
			out[kind].append(c)
	return out


func test_every_map_has_one_of_each_of_the_ten_sites() -> void:
	for s in SEEDS:
		World.new_game(s)
		var sites := _sites()
		assert_eq(sites.keys().size(), Data.POIS.size(), "seed %d has every kind" % s)
		for kind in Data.POIS:
			assert_eq(sites.get(kind, []).size(), 1, "seed %d: one %s" % [s, kind])


func test_a_site_is_four_tiles_that_all_carry_its_id() -> void:
	for kind in _sites():
		var a: Vector2i = _sites()[kind][0]
		for p in Game.poi_footprint(a):
			assert_eq(Game.tile(p)["b"], "poi_" + kind)
			assert_ne(Game.tile(p)["t"], "water")
			assert_eq(Game.tile(p)["o"], Data.NONE, "nobody owns it at the start")
			assert_eq(Game.poi_kind(p), kind)
			assert_eq(Game.poi_anchor(p), a)
		assert_eq(Game.poi_quadrant(a), Vector2i(0, 0))
		assert_eq(Game.poi_quadrant(a + Vector2i(1, 0)), Vector2i(1, 0))
		assert_eq(Game.poi_quadrant(a + Vector2i(0, 1)), Vector2i(0, 1))
		assert_eq(Game.poi_quadrant(a + Vector2i(1, 1)), Vector2i(1, 1))


func test_sites_keep_clear_of_the_camps_and_of_each_other() -> void:
	for s in SEEDS:
		World.new_game(s)
		var anchors := []
		for kind in _sites():
			anchors.append(_sites()[kind][0])
		for a in anchors:
			for b in Game.bases.values():
				assert_ge(Vector2(a).distance_to(Vector2(b)), float(Data.POI_BASE_GAP), "seed %d" % s)
		for i in anchors.size():
			for j in range(i + 1, anchors.size()):
				var d := maxi(absi(anchors[i].x - anchors[j].x), absi(anchors[i].y - anchors[j].y))
				assert_ge(d, Data.POI_GAP, "seed %d: two sites too close" % s)


func test_sites_stand_where_they_like_to() -> void:
	var liked := {}
	for s in SEEDS:
		World.new_game(s)
		var sites := _sites()
		for kind in sites:
			var a: Vector2i = sites[kind][0]
			if Game._poi_likes(kind, a):
				liked[kind] = liked.get(kind, 0) + 1
	for kind in Data.POIS:
		assert_ge(liked.get(kind, 0), SEEDS.size() - 2, "%s is where it likes to be on nearly every map" % kind)


func test_only_the_chemical_dump_may_stand_on_fallout_waste_and_the_rest_are_on_bare_sand() -> void:
	for s_seed in SEEDS:
		World.new_game(s_seed)
		for kind in _sites():
			var a: Vector2i = _sites()[kind][0]
			for p in Game.poi_footprint(a):
				var terrain: String = Game.tile(p)["t"]
				if kind == "chemical_dump":
					assert_has(["sand", "waste"], terrain)
				else:
					assert_eq(terrain, "sand", "seed %d: %s" % [s_seed, kind])


func test_a_site_cannot_be_demolished_even_when_you_own_it() -> void:
	var a: Vector2i = _sites()["bunker"][0]
	Game.tile(a)["o"] = Data.PLAYER
	Game.demolish(a)
	assert_eq(Game.tile(a)["b"], "poi_bunker")
	assert_eq(Game.build_status("farm", a), "Tile already has a building")


func test_tribe_camps_never_land_on_a_site() -> void:
	Units.tribes = []
	for i in 40:
		var t := Units._spawn_tribe()
		if not t.is_empty():
			assert_eq(Game.tile(t.pos)["b"], "", "a camp is on bare ground")


func test_every_site_has_its_art_and_a_quarter_for_each_tile() -> void:
	assert_true(Sprites.poi_available())
	assert_eq(Sprites.poi_kinds().size(), 10)
	for kind in Data.POIS:
		assert_ne(Sprites.poi_rect(kind).size, Vector2.ZERO, kind)
		assert_eq(Sprites.poi_rect(kind).size, Vector2(16, 16))
		assert_not_null(Sprites.poi_sprite(kind), kind)
		var seen := {}
		for q in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var r := Sprites.poi_quadrant_rect(kind, q)
			assert_eq(r.size, Vector2(8, 8))
			assert_true(Sprites.poi_rect(kind).encloses(r))
			seen[r.position] = true
		assert_eq(seen.size(), 4, "four different quarters")
		assert_has(Data.BUILDINGS, "poi_" + kind)


func test_the_fog_remembers_a_site_by_its_tiles() -> void:
	var a: Vector2i = _sites()["radio_tower"][0]
	assert_null(Game.memory[Data.PLAYER][Game.idx(a)])
	Game.reveal(Data.PLAYER, a, 2)
	assert_eq(Game.memory[Data.PLAYER][Game.idx(a)][1], "poi_radio_tower")
	assert_eq(Game.memory[Data.PLAYER][Game.idx(a + Vector2i(1, 1))][1], "poi_radio_tower")


func test_sites_and_picked_state_survive_saving() -> void:
	var a: Vector2i = _sites()["gas_station"][0]
	for p in Game.poi_footprint(a):
		Game.tile(p)["r"] = "picked"
	Game.save_game("poi_test")
	World.new_game(99)
	assert_true(Game.load_game("poi_test"))
	DirAccess.remove_absolute(Game._path("poi_test"))
	assert_eq(Game.poi_kind(a), "gas_station")
	assert_eq(Game.poi_anchor(a + Vector2i(1, 1)), a)
	assert_eq(Game.tile(a)["r"], "picked")


# ---------------------------------------------------------------- scavenging one

func _party_at(site: Vector2i, dice) -> Dictionary:
	Units.dice = dice
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", site, site)
	u.home = Game.home(Data.PLAYER)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = []
	Units.units.append(u)
	Units._begin_visit(u)
	return u


func test_a_party_works_a_site_as_one_tile_and_all_four_tiles_read_picked() -> void:
	var a: Vector2i = _sites()["weather_station"][0]
	var u := _party_at(a, ForcedDice.new([15], [2]))   # a 15 is a SUCCESS at DC 11 whatever the radiation
	assert_eq(u.stage, "site")
	assert_eq(u.visit.ruin, "poi")
	assert_eq(u.visit.poi, "weather_station")
	assert_eq(u.visit.stage, "site")
	assert_almost_eq(u.visit.scale, 3.0 * Data.POI_LOOT_MULT, 0.0001)
	Units.visit_do(u.id)   # the logbook: a small metal find, and the map is charted
	Units.visit_finish(u.id)
	assert_eq(u.carry, {"metal": 9}, "2 metal from the dice, times 3 and the site's 1.5")
	for p in Game.poi_footprint(a):
		assert_eq(Game.tile(p)["r"], "picked")
	var again := _party_at(a + Vector2i(1, 1), ForcedDice.new())
	assert_eq(again.stage, "back", "a picked-clean site sends the party straight home")


func test_clicking_any_of_a_sites_tiles_sends_the_party_to_the_same_place() -> void:
	var a: Vector2i = _sites()["cargo_yard"][0]
	assert_eq(Game.poi_anchor(a + Vector2i(1, 0)), a)
	Game.pop = 20
	var status := Units.send_status("scav", "foot", Game.poi_anchor(a + Vector2i(1, 1)))
	assert_true(status == "" or status.begins_with("Need") or status.begins_with("No way"), status)


func _known_tiles() -> int:
	var n := 0
	for m in Game.memory[Data.PLAYER]:
		if m != null:
			n += 1
	return n


## A party at the site of `kind` whose check rolls a natural 20 (a CRITICAL_SUCCESS), with these package totals,
## already through its roll and ready to head home.
func _crit_at(kind: String, totals := []) -> Dictionary:
	var a: Vector2i = _sites()[kind][0]
	var u := _party_at(a, ForcedDice.new([20], totals))
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "done", kind)
	return u


func test_a_site_charts_the_map_only_when_the_party_heads_home() -> void:
	var before := _known_tiles()
	var u := _crit_at("weather_station", [3])
	assert_eq(_known_tiles(), before, "nothing is charted until the party heads home")
	Units.visit_finish(u.id)
	assert_gt(_known_tiles(), before + 100, "a radius of 20 tiles is a lot of map")
	assert_true(Game.knows_tile(Data.PLAYER, Game.poi_anchor(u.target)))


func test_the_missile_silos_targeting_data_charts_the_rust_kings_fort() -> void:
	var u := _crit_at("missile_silo", [4])
	assert_false(Game.knows(Data.PLAYER, Data.AI))
	Units.visit_finish(u.id)
	assert_true(Game.knows_tile(Data.PLAYER, Game.home(Data.AI)))
	assert_true(Game.knows(Data.PLAYER, Data.AI), "seeing their land is first contact")


func test_a_bunkers_armory_adds_troops() -> void:
	var u := _crit_at("bunker", [5])
	var troops := Game.troops
	Units.visit_finish(u.id)
	assert_eq(Game.troops, troops + 4)


func test_a_cistern_garden_settles_colonists_up_to_the_population_cap() -> void:
	var u := _crit_at("water_tower", [5])
	assert_eq(u.visit.colonists, 2)
	Game.pop = Game.pop_cap() - 1
	Units.visit_finish(u.id)
	assert_eq(Game.pop, Game.pop_cap(), "two came but only one fits")
	Game.pop = Game.pop_cap()
	Units._site_rewards({"colonists": 2}, Vector2i.ZERO)
	assert_eq(Game.pop, Game.pop_cap(), "a full colony takes nobody")
	Game.pop = 5
	Units._site_rewards({"colonists": 2}, Vector2i.ZERO)
	assert_eq(Game.pop, 7)


func test_the_radio_relay_raises_dustwells_trust_unless_it_is_already_settled() -> void:
	var relations: int = Game.town["relations"]
	var gas := _crit_at("gas_station", [5, 5])
	Units.visit_finish(gas.id)
	assert_eq(Game.town["relations"], relations, "no other site touches it")
	var u := _crit_at("radio_tower")
	Units.visit_finish(u.id)
	assert_eq(Game.town["relations"], relations + 20)
	Game.town["status"] = "ally"
	Units._site_rewards({"trust": 20}, Vector2i.ZERO)
	assert_eq(Game.town["relations"], relations + 20, "an ally's trust is not raised further")


func test_a_party_that_leaves_a_site_unsearched_gets_nothing_and_it_stays_unsearched() -> void:
	var a: Vector2i = _sites()["radio_tower"][0]
	var u := _party_at(a, ForcedDice.new())
	Units.visit_do(u.id, "home")
	var relations: int = Game.town["relations"]
	Units.visit_finish(u.id)
	assert_ne(Game.tile(a)["r"], "picked")
	assert_eq(Game.town["relations"], relations)


func test_a_site_fight_in_progress_survives_saving() -> void:
	var a: Vector2i = _sites()["bunker"][0]
	var u := _party_at(a, ForcedDice.new([1]))   # a natural 1: squatters, a fight at strength 5
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "fight")
	for s in u.survivors:
		s["dose"] = 12.0
	Game.save_game("poi_fight_test")
	World.new_game(99)
	assert_true(Game.load_game("poi_fight_test"))
	DirAccess.remove_absolute(Game._path("poi_fight_test"))
	var loaded: Dictionary = Units.units[0]
	assert_eq(loaded.visit.poi, "bunker")
	assert_eq(loaded.visit.stage, "fight")
	assert_eq(loaded.visit.enemy, 5)
	assert_eq(typeof(loaded.visit.enemy), TYPE_INT)
	assert_eq(typeof(loaded.visit.reveal), TYPE_INT)
	assert_eq(loaded.survivors[0].dose, 12.0)
	assert_eq(Units.visit_view(loaded).dc, 16, "the panel can still be built")


func test_a_site_measures_its_radiation_on_arrival() -> void:
	var a: Vector2i = _sites()["chemical_dump"][0]
	var u := _party_at(a, ForcedDice.new())
	assert_true(Game.is_measured(u.pos))
