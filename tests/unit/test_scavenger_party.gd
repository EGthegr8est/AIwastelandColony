extends "res://tests/framework/test_case.gd"
## The Scavenger Party: scavenging, scouting and hunting are one kind of party of 3 survivors (4 with the Big party perk on scavenging and
## hunting runs), numbered 1, 2, 3..., and only the survivors at home limit how many you send.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i
var targets: Array = []


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	Game.res["grain"] = 200
	Game.res["veg"] = 200
	Game.pop = 40
	targets = []
	for i in 12:
		targets.append(World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 4 + i and c.distance_to(hq) < 6 + i \
			and not Game.route("foot", hq, c).is_empty() and not targets.has(c)))


func _lead(perks := []) -> void:
	Game.leader_info = Leaders.fill("builder", {"name": "Test Leader", "perks": perks, "flaw": ""})


func test_all_three_kinds_of_party_take_three_survivors() -> void:
	for job in ["scav", "scout", "hunters"]:
		assert_eq(Units.crew_for(job), 3, job)
		assert_eq(Data.EXPEDITIONS[job].name, "Scavenger Party")
	assert_eq(Units.crew_for("caravan"), 2, "a caravan is still two")


func test_big_party_adds_a_fourth_survivor_on_scavenging_and_hunting_runs_only() -> void:
	_lead(["big_party"])
	assert_eq(Units.crew_for("scav"), 4)
	assert_eq(Units.crew_for("hunters"), 4)
	assert_eq(Units.crew_for("scout"), 3, "a scouting party stays light")
	assert_eq(Units.crew_for("caravan"), 2)
	var pop := Game.pop
	Units.send("scav", "foot", targets[0])
	var u: Dictionary = Units.units[-1]
	assert_eq(u.crew, 4)
	assert_eq(u.survivors.size(), 4)
	assert_eq(Game.pop, pop - 4)


func test_the_perk_is_a_real_exploring_perk() -> void:
	assert_true(Leaders.PERKS.has("big_party"))
	assert_eq(Leaders.PERKS["big_party"].theme, "Exploring")
	_lead([])
	assert_eq(Units.crew_for("scav"), 3, "without it, three")


func test_parties_are_numbered_from_one_and_called_by_their_number() -> void:
	Units.send("scout", "foot", targets[0])
	Units.send("scav", "foot", targets[1])
	Units.send("hunters", "foot", targets[2])
	assert_eq(Units.units.map(func(u): return u.number), [1, 2, 3])
	assert_eq(Units.names_text(Units.units[1]), "Scavenger Party 2")
	assert_eq(Units.party_label(Units.units[2]), "Scavenger Party 3")
	assert_eq(Units.unit_title(Units.units[0]), "Scavenger Party 1")
	assert_true(Game.log_lines.any(func(l): return "Scavenger Party 1 (" in l and "set out" in l), "the log names the party and its people")


func test_a_number_is_given_to_the_next_party_when_a_party_comes_home() -> void:
	for i in 3:
		Units.send("scout", "foot", targets[i])
	var second: Dictionary = Units.units[1]
	Units._come_home(second)
	Units.units.erase(second)
	Units.send("scout", "foot", targets[3])
	assert_eq(Units.units[-1].number, 2, "the free number is used again")
	Units.send("scout", "foot", targets[4])
	assert_eq(Units.units[-1].number, 4)


func test_there_is_no_limit_on_how_many_parties_you_can_send() -> void:
	for i in 10:
		assert_eq(Units.send_status("scout", "foot", targets[i]), "", "party %d" % (i + 1))
		Units.send("scout", "foot", targets[i])
	assert_eq(Units.scouts_out(), 10)
	assert_eq(Units.units.map(func(u): return u.number), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])


func test_only_the_survivors_at_home_limit_the_parties() -> void:
	Game.pop = 7
	Units.send("scout", "foot", targets[0])   # 7 at home: three go, four stay
	assert_eq(Game.pop, 4)
	assert_eq(Units.send_status("scout", "foot", targets[1]), "Need 3 colonists to spare", "one has to stay home")
	Game.pop = 5
	assert_eq(Units.send_status("scout", "foot", targets[1]), "")


func test_the_numbers_survive_saving_and_an_old_save_gets_numbered() -> void:
	Units.send("scout", "foot", targets[0])
	Units.send("scav", "foot", targets[1])
	Game.save_game("number_test")
	assert_true(Game.load_game("number_test"))
	assert_eq(Units.units.map(func(u): return u.number), [1, 2])
	var path: String = Game.save_dir + "number_test.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	for u in data["units"]["units"]:
		u.erase("number")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(Game.load_game("number_test"))
	assert_eq(Units.units.map(func(u): return u.number), [1, 2], "numbered from one, in the order they were saved")
