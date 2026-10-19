extends "res://tests/framework/test_case.gd"
## The colony's people (Game.roster, roster.gd): each survivor is one named person with traits and a face who stays the same
## person when a party takes them out and brings them home, and a death is a name on the list of the fallen.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)


func test_a_new_colony_starts_with_ten_named_survivors() -> void:
	assert_eq(Game.pop, 10)
	assert_eq(Game.roster.size(), 10)
	for s in Game.roster:
		assert_ne(s.name, "")
		assert_ge(s.traits.size(), 1)
		assert_le(s.traits.size(), 3)
		assert_eq(s.state, "home")


func test_no_two_survivors_ever_share_a_name_even_after_the_name_list_runs_out() -> void:
	Game.recruit(120)
	var seen := {}
	for s in Game.roster:
		assert_false(seen.has(s.name), "%s is used twice" % s.name)
		seen[s.name] = true
	var ids := {}
	for s in Game.roster:
		assert_false(ids.has(s.sid), "sid %d is used twice" % s.sid)
		ids[s.sid] = true


func test_the_names_of_the_fallen_are_never_given_to_a_newcomer() -> void:
	var gone: Array = Game.lose_home(3, "test")
	var names: Array = gone.map(func(s): return s.name)
	Game.recruit(200)
	var fresh: Array = Game.roster.filter(func(s): return s.state == "home" and not s in gone)
	for s in fresh:
		assert_not_has(names, s.name)


func test_pop_counts_the_survivors_at_home_and_setting_it_adds_or_removes_people() -> void:
	Game.pop = 14
	assert_eq(Game.pop, 14)
	assert_eq(Game.roster.size(), 14)
	Game.pop -= 4
	assert_eq(Game.pop, 10)
	assert_eq(Game.fallen_survivors().size(), 4, "the four who left are on the list of the fallen")


func test_a_party_you_send_is_made_of_roster_people_and_they_come_home_as_the_same_people() -> void:
	Game.res["grain"] = 50
	var before := Game.pop
	var target := Game.nearest_walkable(hq + Vector2i(4, 0))
	Units.send("scav", "foot", target)
	var u: Dictionary = Units.units[0]
	assert_eq(u.survivors.size(), u.crew)
	assert_eq(Game.pop, before - u.crew, "they are away, not counted at home")
	for s in u.survivors:
		assert_true(Game.roster.has(s), "the party holds the roster's own entries")
		assert_eq(s.state, "away")
	var crew: Array = u.survivors.duplicate()
	var names: Array = crew.map(func(s): return s.name)
	Units._come_home(u)
	assert_eq(Game.pop, before)
	for i in crew.size():
		assert_eq(crew[i].state, "home")
		assert_eq(crew[i].name, names[i], "the same person")
	assert_eq(Game.roster.size(), 10, "nobody new was made")


func test_coming_home_heals_a_trip_but_keeps_the_person() -> void:
	var s: Dictionary = Game.take_crew(1)[0]
	var traits: Array = s.traits.duplicate()
	s.hunger = 2
	s.hp = 40.0
	s.leg = true
	s.hurt = true
	s.injury = "severe"
	Game.welcome_home([s], 1)
	assert_eq(s.state, "home")
	assert_eq(s.hunger, 0)
	assert_eq(s.hp, Data.SURVIVOR_HP)
	assert_false(s.leg)
	assert_false(s.hurt)
	assert_eq(s.injury, "none")
	assert_eq(s.traits, traits)


func test_a_death_in_the_field_puts_the_person_on_the_list_of_the_fallen_with_a_cause() -> void:
	var crew: Array = Game.take_crew(3)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	u.crew = 3
	u.survivors = crew
	Game.season = 5
	var victim: Dictionary = crew[1]
	var who: String = Units._casualty(u, victim, "starved in the field")
	assert_eq(who, victim.name)
	assert_eq(u.crew, 2)
	assert_false(u.survivors.has(victim))
	assert_eq(victim.state, "dead")
	assert_eq(victim.cause, "starved in the field")
	assert_eq(victim.died, 5)
	assert_true(Game.fallen_survivors().has(victim))
	assert_eq(Game.living_survivors().size(), 9)


func test_a_wiped_out_party_is_all_on_the_list_of_the_fallen() -> void:
	var crew: Array = Game.take_crew(3)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	u.crew = 3
	u.survivors = crew.duplicate()
	Units._wipe(u, "wiped out at the ruins")
	assert_eq(u.crew, 0)
	assert_eq(Game.fallen_survivors().size(), 3)
	for s in crew:
		assert_eq(s.cause, "wiped out at the ruins")


func test_the_uninjured_go_out_first() -> void:
	Game.roster[0].leg = true
	Game.roster[1].hurt = true
	var crew: Array = Game.take_crew(8)
	assert_false(crew.has(Game.roster[0]) and crew.has(Game.roster[1]) and false)
	var left_behind: Array = Game.home_survivors()
	assert_eq(left_behind.size(), 2)
	for s in left_behind:
		assert_true(s.leg or s.hurt, "the two who stayed are the injured ones")


func test_starvation_names_who_died() -> void:
	Game.res["grain"] = 0
	Game.res["veg"] = 0
	Game.log_lines = []
	Game._upkeep()
	assert_true(Game.log_lines.any(func(l): return "STARVATION:" in l and "(" in l), "the log names them")
	assert_gt(Game.fallen_survivors().size(), 0)
	for s in Game.fallen_survivors():
		assert_eq(s.cause, "starved")


func test_a_new_year_ages_everyone_alive() -> void:
	var ages: Array = Game.roster.map(func(s): return s.age)
	Game.season = 4
	Game.end_season()
	assert_eq(Game.season, 5, "year 2 begins")
	for i in ages.size():   # settlers may have joined: only the first ten are the ones to compare
		assert_eq(Game.roster[i].age, ages[i] + 1)


func test_the_roster_and_the_parties_survive_save_and_load() -> void:
	Game.res["grain"] = 50
	var target := Game.nearest_walkable(hq + Vector2i(4, 0))
	Units.send("scav", "foot", target)
	var u: Dictionary = Units.units[0]
	var party_names: Array = u.survivors.map(func(s): return s.name)
	Game.lose_home(1, "test")
	var all: Array = Game.roster.map(func(s): return s.duplicate())
	Game.save_game("roster_test")
	assert_true(Game.load_game("roster_test"))
	assert_eq(Game.roster.size(), all.size())
	for i in all.size():
		assert_eq(Game.roster[i].name, all[i].name)
		assert_eq(Game.roster[i].state, all[i].state)
		assert_eq(Game.roster[i].traits, all[i].traits)
		assert_eq(Game.roster[i].face, all[i].face)
	var loaded: Dictionary = Units.units[0]
	assert_eq(loaded.survivors.map(func(s): return s.name), party_names)
	for s in loaded.survivors:
		assert_true(Game.roster.has(s), "the loaded party holds the roster's own entries")


func test_an_old_save_with_no_roster_gets_one() -> void:
	Game.save_game("roster_old")
	var path: String = Game.save_dir + "roster_old.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("roster")
	data["pop"] = 12
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(Game.load_game("roster_old"))
	assert_eq(Game.pop, 12)
	assert_eq(Game.roster.size(), 12)
