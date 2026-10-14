extends "res://tests/framework/test_case.gd"
## What the screen shows of a roll: who rolled, their perks, the die and what came of it, with the DC, the modifier, the sum and the odds left out. The game's own lines keep
## the numbers (`D20.plain` is only applied to what is drawn).

const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")


func after_each() -> void:
	D20.show_math = false


func _plain_is(from: String, to: String) -> void:
	assert_eq(D20.plain(from), to, from)


func test_a_roll_line_keeps_the_roller_their_perks_and_the_tier() -> void:
	_plain_is("Mara (Sharp-Eyed) trap: d20 8 +4 = 12 vs DC 11 -> SUCCESS", "Mara (Sharp-Eyed) trap: success")
	_plain_is("Pike (Magpie, Light-Footed, Sharp-Eyed, Lucky) site: d20 4 +3 = 7 vs DC 14 -> CRITICAL_FAILURE (rerolled from 10) [+3 traits]",
		"Pike (Magpie, Light-Footed, Sharp-Eyed, Lucky) site: critical failure (rerolled)")
	_plain_is("Mara trap: d20 11 +0 = 11 vs DC 11 -> SUCCESS (raw FAILURE) [+1 traits, -1 radiation (35 R/h)]", "Mara trap: success")
	_plain_is("Hazel cache: d20 20 +2 = 22 vs DC 11 -> CRITICAL_SUCCESS", "Hazel cache: critical success")
	_plain_is("Faye ambush: d20 3 -1 = 2 vs DC 14 -> FAILURE", "Faye ambush: failure")


func test_the_real_roll_line_reads_plain() -> void:
	var scout := {"name": "Mara", "traits": []}
	var line := D20.log_line(scout, {"check": "trap", "d20": 8, "mod": 4, "total": 12, "dc": 11, "tier": "SUCCESS", "rerolled": false, "shifted": false, "parts": [{"label": "traits", "value": 4}], "first_d20": 8, "raw": "SUCCESS"})
	assert_true(line.contains("vs DC 11"), "the game's line has the sum")
	assert_eq(D20.plain(line), "Mara trap: success")


func test_the_panel_header_and_the_buttons_lose_their_numbers() -> void:
	_plain_is("Pike rolls. Site check, DC 14, +3", "Pike rolls. Site check")
	_plain_is("Pike rolls. Crater search, DC 11, +2. A natural 1 sets the nuke off, a natural 20 disarms it", "Pike rolls. Crater search. A natural 1 sets the nuke off, a natural 20 disarms it")
	_plain_is("Pike rolls. Attack, DC 16, -2 (enemy strength 5)", "Pike rolls. Attack (enemy strength 5)")
	_plain_is("Roll d20 (+3 vs DC 14)", "Roll d20")
	_plain_is("Run (-1 vs DC 12)", "Run")
	_plain_is("Spotted in time. Fight (DC 12) or slip away?", "Spotted in time. Fight or slip away?")
	_plain_is("A rich find. Search deeper at DC 15, or head home with it?", "A rich find. Search deeper, or head home with it?")
	_plain_is("Search deeper (DC 15)", "Search deeper")
	_plain_is("You search deeper (DC 13). It holds metal.", "You search deeper. It holds metal.")


func test_attack_hunt_and_frog_texts() -> void:
	_plain_is("Attack the farm at 3,4 (DC 8)", "Attack the farm at 3,4")
	_plain_is("Attack the Ash Walkers at 5,6 (DC 12, strength 5)", "Attack the Ash Walkers at 5,6 (strength 5)")
	_plain_is("Hunt the black bear at 1,2 (track DC 11, kill DC 14)", "Hunt the black bear at 1,2")
	_plain_is("Two rolls: track it (DC 11), then the kill shot (DC 14).", "Two rolls: track it, then the kill shot.")
	_plain_is("Track it (DC 12) with each party, then attack with everyone who found it: 12 wounds to take.", "Track it with each party, then attack with everyone who found it: 12 wounds to take.")
	_plain_is("THE GIANT FROG! 6 of you against it. Pike rolls to run: DC 12, +2. Or stand and fight.", "THE GIANT FROG! 6 of you against it. Pike rolls to run. Or stand and fight.")
	_plain_is("The Giant Frog has taken 3 of 12 wounds. 5 of your people still stand, and each rolls to hit (DC 13). Then it slams 3 times.",
		"The Giant Frog has taken 3 of 12 wounds. 5 of your people still stand, and each rolls to hit. Then it slams 3 times.")
	_plain_is("Pike: d20 14 +2 vs DC 12: hit", "Pike: hit")


func test_raid_lines_keep_the_result_and_the_chance_stays_on_the_odds() -> void:
	_plain_is("Your raid on the Ash Walkers: d20 14 vs DC 9 (60% to win), won.", "Your raid on the Ash Walkers: won.")
	_plain_is("A test party struck the farm at 3,4: d20 8 +0 vs DC 8, destroyed.", "A test party struck the farm at 3,4: destroyed.")
	_plain_is("A Rust Kings scout struck the farm at 3,4: d20 7 +0 vs DC 8, it held.", "A Rust Kings scout struck the farm at 3,4: it held.")
	_plain_is("DC 11, 50% to win", "50% to win")
	_plain_is("Their airfield stands at 5,6 (DC 12: a scouting party beside it, a raid, or a nuke).", "Their airfield stands at 5,6 (a scouting party beside it, a raid, or a nuke).")


func test_text_without_a_roll_is_left_alone() -> void:
	for text in ["", "Search: d20 12 -> Minor find", "Pike fumbles: d20 4", "Click the die to roll", "Traits: Magpie, Lucky", "A fight is forced on you (enemy strength 5).", "SUCCESS stories"]:
		_plain_is(text, text)


func test_show_math_puts_every_number_back() -> void:
	D20.show_math = true
	for text in ["Mara (Sharp-Eyed) trap: d20 8 +4 = 12 vs DC 11 -> SUCCESS", "Pike rolls. Site check, DC 14, +3", "Attack the farm at 3,4 (DC 8)"]:
		_plain_is(text, text)


func test_what_the_visit_asks_for_reads_plain_too() -> void:
	var party := Units._make_crew(3)
	for s in party:
		s.traits = []
	var visit := D20Visit.begin("poi", {"radiation": 0.0, "party_strength": 3}, 1.0, Units.dice, party, "weather_station")
	var view := D20Visit.pending(visit, party)
	assert_true(view.text.contains("DC"), "the game's own text has the DC")
	assert_false(D20.plain(view.text).contains("DC"), "the screen's does not")
	for b in view.buttons:
		assert_false(D20.plain(b.label).contains("DC"), b.label)
	assert_ne(view.traits, null)
