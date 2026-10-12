extends "res://tests/framework/test_case.gd"
## Survivor portraits: drawn from a seed, so each person always looks the same.

const Portrait = preload("res://scripts/portrait.gd")
const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")


func test_portrait_has_the_expected_size() -> void:
	var img := Portrait.image(12345, 30, 0)
	assert_eq(img.get_size(), Vector2i(Portrait.W, Portrait.H))


func test_same_survivor_always_looks_the_same() -> void:
	assert_eq(Portrait.image(777, 30, 0).get_data(), Portrait.image(777, 30, 0).get_data())


func test_different_faces_look_different() -> void:
	var seen := {}
	for face in 20:
		seen[Portrait.image(face * 7919 + 1, 30, 0).get_data()] = true
	assert_gt(seen.size(), 17)


func test_hunger_and_age_change_the_portrait() -> void:
	var fed := Portrait.image(4242, 30, 0).get_data()
	assert_ne(Portrait.image(4242, 30, 2).get_data(), fed)
	assert_ne(Portrait.image(4242, 60, 0).get_data(), fed)


func test_an_injured_survivor_wears_a_bandage() -> void:
	var well := Portrait.image(4242, 30, 0)
	var hurt := Portrait.image(4242, 30, 0, 0, true)
	assert_eq(hurt.get_size(), well.get_size())
	assert_ne(hurt.get_data(), well.get_data())
	assert_eq(Portrait.image(4242, 30, 0, 0, true).get_data(), hurt.get_data(), "the same bandage every time")
	assert_ne(Portrait.texture(4242, 30, 0, 0, true), Portrait.texture(4242, 30, 0, 0, false), "cached apart")


func test_portrait_does_not_disturb_the_games_random_numbers() -> void:
	seed(5)
	var expected := randi()
	seed(5)
	Portrait.image(99, 40, 1)
	assert_eq(randi(), expected)


func test_textures_are_cached() -> void:
	assert_true(Portrait.texture(31337, 25, 1) == Portrait.texture(31337, 25, 1))


func test_every_survivor_gets_a_portrait_seed() -> void:
	World.new_game(7)
	Game.res["grain"] = 50
	var hq := Game.home(Data.PLAYER)
	var target := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 5 and c.distance_to(hq) < 9 \
		and not Game.route("foot", hq, c).is_empty())
	Units.send("scout", "foot", target)
	var faces: Array = Units.units[-1].survivors.map(func(s): return s.face)
	assert_eq(faces.size(), 2)
	assert_ne(faces[0], faces[1])
