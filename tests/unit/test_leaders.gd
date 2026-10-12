extends "res://tests/framework/test_case.gd"
## The leader maker (scripts/leaders.gd): three random people, one per class, each with a name, a picture, two perks from
## different themes and a flaw from a third theme, and no two sharing a name, perk or flaw.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")


func before_each() -> void:
	Leaders.offered = []


func after_each() -> void:
	Leaders.offered = []


func test_there_are_22_perks_and_13_flaws_in_the_four_themes() -> void:
	assert_eq(Leaders.PERKS.size(), 22)
	assert_eq(Leaders.FLAWS.size(), 13)
	for table in [Leaders.PERKS, Leaders.FLAWS]:
		for id in table:
			assert_has(Leaders.THEMES, table[id].theme, id)
			assert_ne(table[id].name, "", id)
			assert_ne(table[id].text, "", id)
	for id in Leaders.PERKS:
		assert_false(Leaders.FLAWS.has(id), "a perk and a flaw never share an id: %s" % id)
	for theme in Leaders.THEMES:
		assert_gt(Leaders.FLAWS.keys().filter(func(id): return Leaders.FLAWS[id].theme == theme).size(), 1, "flaws in %s" % theme)


func test_three_leaders_one_per_class_in_the_screens_order() -> void:
	var three := Leaders.make_three()
	assert_eq(three.map(func(l): return l["class"]), ["raider", "builder", "trader"])


func test_a_name_is_a_title_a_first_name_and_a_surname_and_the_title_fits_the_class() -> void:
	for s in range(1, 40):
		seed(s)
		for leader in Leaders.make_three():
			var parts: PackedStringArray = leader.name.split(" ")
			assert_eq(parts.size(), 3, leader.name)
			if Leaders.PICTURE_TITLES.has(leader.image):
				assert_eq(parts[0], Leaders.PICTURE_TITLES[leader.image], "a picture's own title")
			else:
				assert_has(Leaders.TITLES[leader["class"]], parts[0])
				assert_false(parts[0] in Leaders.PICTURE_TITLES.values(), "%s is kept for a picture" % parts[0])
			assert_has(Data.SURVIVOR_NAMES, parts[1])
			assert_has(Leaders.SURNAMES, parts[2])


func test_perks_and_flaws_follow_the_rules_over_many_screens() -> void:
	for s in range(1, 300):
		seed(s)
		var three := Leaders.make_three()
		var names := {}
		var perks := {}
		var flaws := {}
		for leader in three:
			assert_eq(leader.perks.size(), 2, "seed %d" % s)
			var themes: Array = leader.perks.map(func(id): return Leaders.PERKS[id].theme)
			assert_ne(themes[0], themes[1], "two perks from different themes (seed %d)" % s)
			assert_true(Leaders.FLAWS.has(leader.flaw), leader.flaw)
			assert_false(Leaders.FLAWS[leader.flaw].theme in themes, "the flaw is in a theme neither perk is in (seed %d)" % s)
			assert_false(names.has(leader.name), "no repeated name")
			names[leader.name] = true
			for id in leader.perks:
				assert_false(perks.has(id), "no repeated perk: %s (seed %d)" % [id, s])
				perks[id] = true
			assert_false(flaws.has(leader.flaw), "no repeated flaw")
			flaws[leader.flaw] = true


func test_new_leaders_each_time_and_the_same_three_until_a_reroll() -> void:
	seed(5)
	var first := Leaders.offer()
	var again := Leaders.offer()
	assert_eq(first.map(func(l): return l.name), again.map(func(l): return l.name), "asking twice gives the same three")
	var rerolled := Leaders.offer(true)
	assert_ne(first.map(func(l): return l.name), rerolled.map(func(l): return l.name), "a reroll draws new people")
	assert_eq(Leaders.offer().map(func(l): return l.name), rerolled.map(func(l): return l.name), "and those stay")


func test_each_class_has_three_pictures_and_a_leader_gets_one_of_their_class() -> void:
	for cls in Data.LEADERS:
		assert_eq(Leaders.pictures(cls), ["%s_1" % cls, "%s_2" % cls, "%s_3" % cls], cls)
	for leader in Leaders.make_three():
		assert_has(Leaders.pictures(leader["class"]), leader.image)


func test_every_picture_loads_big_and_small_and_a_leader_without_one_gets_a_drawn_face() -> void:
	for cls in Data.LEADERS:
		for id in Leaders.pictures(cls):
			var big := Leaders.portrait({"image": id})
			var small := Leaders.portrait({"image": id}, true)
			assert_eq(big.get_size(), Vector2(480, 480), id)
			assert_eq(small.get_size(), Vector2(48, 48), id)
	var drawn := Leaders.portrait({"image": "", "face": 1234})
	assert_not_null(drawn)
	assert_ne(drawn.get_size(), Vector2(480, 480), "it is the survivor face generator's")
	assert_not_null(Leaders.portrait({"image": "nobody_9", "face": 1}), "a picture that is gone falls back too")


func test_fill_keeps_only_known_perks_and_a_known_flaw() -> void:
	var leader := Leaders.fill("raider", {"perks": ["haggler", "nonsense"], "flaw": "nope", "name": "Sheriff Cole Harlan"})
	assert_eq(leader.perks, ["haggler"])
	assert_eq(leader.flaw, "")
	assert_eq(leader["class"], "raider")
	var blank := Leaders.fill("builder")
	assert_eq([blank.name, blank.perks, blank.flaw], ["", [], ""])


func test_the_label_is_the_name_and_class_or_just_the_class() -> void:
	assert_eq(Leaders.label(Leaders.fill("raider", {"name": "Sheriff Cole Harlan"})), "Sheriff Cole Harlan (Raider)")
	assert_eq(Leaders.label(Leaders.fill("trader")), "Trader")


func test_quirk_lines_list_the_perks_then_the_flaw_with_their_effects() -> void:
	var lines := Leaders.quirk_lines(Leaders.fill("builder", {"perks": ["green_thumb", "sharp_nose"], "flaw": "poor_haggler"}))
	assert_eq(lines.map(func(l): return l.kind), ["perk", "perk", "flaw"])
	assert_eq(lines[0].name, "Green thumb")
	assert_eq(lines[0].text, "Each farm gives +1 veg.")
	assert_eq(lines[2].text, "Market sales pay 15% less gold.")
	assert_eq(Leaders.quirk_lines(Leaders.fill("builder")), [])


func test_the_general_is_always_a_general_and_nobody_else_is() -> void:
	var generals := 0
	for s in range(1, 200):
		seed(s)
		for leader in Leaders.make_three():
			var title: String = leader.name.get_slice(" ", 0)
			if leader.image == "raider_3":
				generals += 1
				assert_eq(title, "General", "the monocle general (seed %d)" % s)
				assert_eq(leader["class"], "raider")
			else:
				assert_ne(title, "General", "only his picture is a General")
	assert_gt(generals, 20, "he turns up now and then (a third of the raider draws)")


func test_the_sheriff_elder_and_executive_keep_their_titles_too() -> void:
	assert_eq(Leaders.title_for("raider", "raider_1"), "Sheriff")
	assert_eq(Leaders.title_for("builder", "builder_3"), "Elder")
	assert_eq(Leaders.title_for("trader", "trader_3"), "Executive")
	for i in 100:
		assert_false(Leaders.title_for("raider", "raider_9") in ["Sheriff", "General"])
		assert_ne(Leaders.title_for("builder", "builder_1"), "Elder")
