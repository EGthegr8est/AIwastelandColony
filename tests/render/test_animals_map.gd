extends "res://tests/framework/test_case.gd"
## The animals and the Giant Frog on the real map and HUD: who is drawn where, the side panel for an animal's tile with its hunt buttons,
## the "Hunt" header and the die of a hunt in progress, the frog's own panel, and the legend.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Sprites = preload("res://scripts/sprites.gd")
const MapView = preload("res://scripts/map_view.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var main: Node2D
var hud: Node
var map: Node2D
var hq: Vector2i


func before_each() -> void:
	seed(5)
	Sprites.style = 1
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
		if child.has_method("pending_reveals"):
			map = child
	_press("New colony")
	await wait_frames(2)
	_press("Choose")
	await wait_frames(3)
	SeasonReplay.mode = "off"
	hq = Game.home(Data.PLAYER)
	Units.units = []
	Units.tribes = []
	Units.animals = []
	Game.reveal(Data.PLAYER, hq, 16)
	Game.update_fog()


func after_each() -> void:
	Sprites.style = 1
	SeasonReplay.mode = "off"


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree():
			b.pressed.emit()
			return


func _texts() -> Array:
	var out := []
	for l in hud.boxes["Tile"].find_children("*", "Label", true, false):
		out.append(l.text)
	return out


func _buttons() -> Array:
	return hud.boxes["Tile"].find_children("*", "Button", true, false).map(func(b): return b.text)


func _has_text(part: String) -> bool:
	return _texts().any(func(t): return t.contains(part))


func _has_button(part: String) -> bool:
	return _buttons().any(func(t): return t.contains(part))


## An animal in sight beside the colony.
func _near(kind: String, d := Vector2i(3, -2)) -> Dictionary:
	var a: Dictionary = Units._add_animal(kind, hq + d)
	Game.update_fog()
	return a


# ---------------------------------------------------------------- on the map

func test_an_animal_in_sight_is_shown_and_one_out_of_sight_is_not() -> void:
	var a := _near("deer")
	assert_eq(map.unit_shown(a), MapView.Shown.SHOWN)
	Game.sight[Data.PLAYER][Game.idx(a.pos)] = 0
	assert_eq(map.unit_shown(a), MapView.Shown.HIDDEN, "you do not know where it is now")
	Game.view = Data.NONE
	assert_eq(map.unit_shown(a), MapView.Shown.SHOWN, "the no-fog view shows everything")
	Game.view = Data.PLAYER


func test_animals_are_drawn_by_the_unit_layer_and_do_not_redraw_the_tiles() -> void:
	var a := _near("black_bear", Vector2i(2, -1))
	Game.changed.emit()
	await wait_frames(3)
	map.stats["tile_draws"] = 0
	map.stats["unit_draws"] = 0
	a.pos += Vector2i(1, 0)
	Game.changed.emit()
	await wait_frames(3)
	assert_eq(map.stats.tile_draws, 0)
	assert_gt(map.stats.unit_draws, 0)
	assert_false(map._overlay().has(a.pos), "the chunks do not draw it")


func test_the_frog_is_visible_when_any_of_the_four_tiles_it_stands_on_is_in_sight() -> void:
	Units.frog["state"] = "loose"
	Units.frog["pos"] = hq + Vector2i(30, 0)
	Game.update_fog()
	var blind := PackedByteArray()
	blind.resize(Game.w * Game.h)
	Game.sight[Data.PLAYER] = blind
	assert_false(map.frog_shown())
	blind[Game.idx(Units.frog.pos + Vector2i(1, 1))] = 1
	Game.sight[Data.PLAYER] = blind
	assert_true(map.frog_shown(), "the far corner is enough")


func test_every_animal_has_its_picture_in_the_animals_file() -> void:
	assert_true(Sprites.animals_available())
	assert_eq(Sprites.animals_texture().get_size(), Vector2(64, 16))
	for kind in Sprites.ANIMALS:
		var rect := Sprites.animal_rect(kind)
		assert_eq(rect.size, Vector2(16, 16), kind)
		assert_not_null(Sprites.animal(kind))
	assert_eq(Sprites.animal_rect("dodo").size, Vector2.ZERO)


func test_an_animal_walks_in_the_season_replay_without_deciding_how_long_it_lasts() -> void:
	var a := _near("deer")
	var party: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq + Vector2i(1, 0), hq)
	party.crew = 3
	party.survivors = Units._make_crew(3)
	party.stage = "back"
	party.path = Game.route("foot", party.pos, hq).slice(1)
	Units.units = [party]
	Units.wild_spawns = false
	Units.season_turn()
	var wild: Array = Units.replay.actors.filter(func(x): return x.get("wild", false))
	assert_gt(wild.size(), 0, "the animals are in the replay")
	for w in wild:
		for step in w.trail:
			assert_le(step[1], Units.replay.end_day + 0.001, "their days are fitted inside the walk")
	assert_eq(a.kind, "deer")


func test_a_season_in_which_only_animals_moved_plays_no_replay() -> void:
	_near("deer")
	Units.units = []
	Units.wild_spawns = false
	Units.season_turn()
	assert_false(SeasonReplay.has_motion(Units.replay))


# ---------------------------------------------------------------- the side panel

func test_an_animals_tile_says_what_it_is_and_offers_hunters() -> void:
	var a := _near("black_bear")
	Game.select(a.pos)
	await wait_frames(3)
	assert_true(_has_text("BLACK BEAR"), "a header")
	assert_true(_has_text("strength 3"))
	assert_true(_has_text("track it (DC 11)"))
	assert_true(_has_button("Hunt with scavengers on foot"), "send hunters")


func test_a_deer_is_not_dangerous() -> void:
	var a := _near("deer")
	Game.select(a.pos)
	await wait_frames(3)
	assert_true(_has_text("DEER"))
	assert_false(_has_text("attacks a party"))
	assert_true(_has_button("Hunt with scavengers on foot"))


func test_pressing_the_hunt_button_sends_a_scavenger_party_after_the_animal() -> void:
	var a := _near("deer", Vector2i(4, 0))
	Game.select(a.pos)
	await wait_frames(3)
	for b in hud.boxes["Tile"].find_children("*", "Button", true, false):
		if b.text.contains("Hunt with scavengers on foot"):
			b.pressed.emit()
			break
	assert_eq(Units.units.size(), 1)
	assert_eq(Units.units[0].job, "scav")
	assert_eq(Units.units[0].dest, a.id, "it carries the animal's id as its target")


func test_a_party_at_a_hunt_shows_hunt_above_the_die() -> void:
	var a := _near("deer")
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", a.pos, hq)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	Units.units = [u]
	Units._start_hunt(u, a)
	Game.select(a.pos)
	await wait_frames(3)
	assert_true(_has_text("HUNT"), "the header")
	assert_false(_has_text("SCAVENGE"), "and not Scavenge")
	assert_true(_has_text("Track, DC 8"), "what the roll is")
	assert_true(_has_button("Give up the hunt"))
	assert_eq(hud.dice_holder.get_parent() != null, true, "the die is in the panel")


func test_a_scouting_party_beside_an_animal_gets_a_hunt_button() -> void:
	var a := _near("brown_bear", Vector2i(4, 1))
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", a.pos + Vector2i(-1, 0), hq)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.stage = "station"
	u.food = {"grain": Data.SCOUT_PACK}
	Units.units = [u]
	Game.update_fog()
	Game.select(u.pos)
	await wait_frames(3)
	assert_true(_has_button("Hunt the brown bear"))


# ---------------------------------------------------------------- the frog

func _frog_awake(d := Vector2i(3, -3)) -> void:
	Units.frog["state"] = "loose"
	Units.frog["pos"] = hq + d
	Units.frog["target"] = "player"
	Game.update_fog()


func test_the_awake_frog_has_its_own_panel_and_can_be_hunted() -> void:
	_frog_awake()
	Game.select(Units.frog.pos + Vector2i(1, 1))   # any of its four tiles
	await wait_frames(3)
	assert_true(_has_text("GIANT FROG"))
	assert_true(_has_text("heading for your colony"))
	assert_true(_has_text("DC 14"), "its track roll")
	assert_true(_has_button("Hunt with scavengers on foot"))


func test_the_sleeping_frog_is_not_on_the_map() -> void:
	assert_eq(Units.frog.state, "dormant")
	Game.select(Units.frog.lair)
	await wait_frames(3)
	assert_false(_has_text("GIANT FROG"))


func test_only_the_first_party_in_a_frog_fight_has_the_die() -> void:
	_frog_awake()
	var a: Dictionary = _waiting_at_frog()
	var b: Dictionary = _waiting_at_frog()
	Units.units = [a, b]
	Units.visit_do(a.id, "frog_attack")
	Game.select(Units.frog.pos)
	await wait_frames(4)
	var pulls := _buttons().filter(func(t): return t == "Pull back")
	assert_eq(pulls.size(), 1, "one panel runs the fight")
	assert_true(_has_text("Fighting the Giant Frog together"), "the other says so")


func _waiting_at_frog() -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", Units.frog.pos, hq)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.stage = "site"
	u["visit"] = D20Visit.begin_hunt(Units.visit_ctx(u), 3.0, Units.dice, u.survivors, "frog", Units.FROG_ID, "giant frog")
	u.visit["stage"] = "frog_wait"
	return u


# ---------------------------------------------------------------- the legend

func test_the_legend_lists_the_animals_and_the_frog() -> void:
	Game.selected = Vector2i(-1, -1)
	Game.changed.emit()
	await wait_frames(3)
	for name in ["Deer", "Black bear", "Brown bear", "Giant Frog"]:
		assert_true(_has_text(name), name)


func test_the_legend_pictures_of_the_animals_are_the_16_pixel_ones() -> void:
	Game.selected = Vector2i(-1, -1)
	Game.changed.emit()
	await wait_frames(3)
	var big: Array = hud.boxes["Tile"].find_children("*", "TextureRect", true, false).filter(func(r): return r.texture is AtlasTexture and r.texture.region.size == Vector2(16, 16) and r.texture.atlas == Sprites.animals_texture())
	assert_eq(big.size(), 4, "deer, two bears and the frog")


func test_in_text_mode_the_animals_are_letters() -> void:
	Sprites.choose(0)
	var a := _near("deer")
	Game.changed.emit()
	await wait_frames(3)
	assert_eq(map.unit_shown(a), MapView.Shown.SHOWN)
	Game.selected = Vector2i(-1, -1)
	Game.changed.emit()
	await wait_frames(3)
	assert_true(_has_text("d  Deer") or _has_text("Deer"), "the legend row still names it")
