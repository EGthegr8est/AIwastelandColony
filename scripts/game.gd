extends Node
## Autoload "Game": the whole simulation. The colony is simulated as one unit,
## not as individual colonists. Every player action is a function here, and the
## UI just calls them and redraws when `changed` fires.

signal changed
signal focus(cell: Vector2i)
signal tile_selected
signal game_ended(kind: String)   # the game has ended: "raiders_defeated", "colony_prospers" or "defeat"
signal season_played(replay: Dictionary)   # END SEASON is done: here is how the units walked it, for the map to play back (season_replay.gd)
signal troops_marched(path: Array, count: int)   # a raid is under way: a column of troops walks `path` (cells, HQ to target) and back
signal replay_skip     # finish the replay or march that is playing at once
signal replay_done     # the map has finished playing (or skipped) a replay or march
signal blasted(cell: Vector2i)   # a nuke went off here: the map plays the explosion (a crater's once the die has landed, a bomber's in the season replay instead)
signal strike_preview_changed    # the red square over the tile a Nuclear strike would hit (strike_preview) has moved
signal hollow_mile_found(cell: Vector2i, hot: bool)   # your scouts saw the first tile of the old highway (once a game): the HUD shows its picture; `hot` is whether the party that found it is taking high radiation

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const Leaders = preload("res://scripts/leaders.gd")
const SAVE_DIR := "user://saves/"

var save_dir := SAVE_DIR       # tests point this at their own folder so they never touch real saves

var w := Data.MAP_W
var h := Data.MAP_H
var tiles: Array = []          # each tile: {"t": terrain, "o": owner, "b": building, "z": height in m,
                               #             "r": ruins state: "safe", "rogue", "rogue_seen", "trap", "picked"}
var map_version := 0           # goes up whenever the tiles are replaced (new game, load) or the ground changes (a blast)
var bases := {}                # owner -> the cell of their HQ (or Dustwell's center)
var contours: Array = []       # per tile: contour pipe glyph, or "" if no contour runs through it
var slopes: Array = []         # per tile: "", "gentle" or "steep"
var paths := {}                # mover ("foot", "horse", "car") -> AStarGrid2D route finder
var preview := {}              # mover -> route from your HQ to the selected tile
var selected_scout := -1       # id of the scouting party you have picked (-1 = none), see select()
var scout_route := {}          # that party's route to the selected tile: {"mover", "path", "days", "ratio"}, see refresh_scout_route()
var refinery_on := {}          # tile index -> true for each refinery you've switched on (new ones start off)
var res: Dictionary = {}
var salt_on := false           # "Take Salt": parties take a dose for each survivor when they leave, if there is enough
var items: Dictionary = {}     # what the colony keeps that is not a resource (Data.ITEMS): frog hides, Salt. No line in the top bar.
var pop := 10
var troops := 3
var prisoners := 0
var season := 1
var leader := "builder"          # the class: a key of Data.LEADERS
var leader_info: Dictionary = {}  # the person: name, picture, perks and flaw (see leaders.gd)
var upgrades: Array = []
var vehicles: Dictionary = {}
var raided_this_season := false
var ai: Dictionary = {}
var town: Dictionary = {}
var log_lines: Array = []
var fertility_map := PackedFloat32Array()   # scratch from generation: how green each tile could be
var catastrophes: Array = []   # one per epicenter: {"pos", "radius", "crater", "kind", "year", "name", ...}
var selected := Vector2i(-1, -1)
var in_game := false
var ending := {}               # {} while the game runs; {"kind", "why", "season"} once it has ended (it only ever ends once)
var stats := {}                # what the stats screen after an ending shows, see new_stats()
var prosper_streak := 0        # seasons in a row the Rust Kings have been too weak to threaten you
var starved_now := false       # the colony starved this season
var buildings_lost := 0        # your buildings destroyed this season, by anyone (capped by RAID_LOSS_CAP)
var replaying := false         # the map is playing back a season or a march (the map sets it); END SEASON then skips it

# Fog of war. memory[viewer] has one entry per tile: null if that colony has never
# seen it, otherwise [owner, building] as it looked the last time it was in sight.
# sight[viewer] marks the tiles that colony can see right now.
var memory := {}
var sight := {}
var contacts := {}             # "viewer:other" -> true once a colony has found another
var hollow_found := false      # your scouts have seen a tile of the old highway (the Hollow Mile)
var view := Data.PLAYER        # whose knowledge the map shows (Data.NONE = everything)
var measured := PackedByteArray()   # 1 where one of your parties has measured the radiation
var show_radiation := false    # tint the tiles you have measured by how hot they are
var strike_preview := Vector2i(-1, -1)   # the tile whose 3 x 3 blast square the map outlines in red (the Nuclear strike button is being hovered)
var held_blasts: Array = []    # blasts whose explosion waits for the die to land (release_blasts)


func _ready() -> void:
	changed.connect(update_fog)
	changed.connect(_keep_scout_route_fresh)


# ---------------------------------------------------------------- new game

## Starts a colony led by a class of leader (and, from the selection screen, a particular person: see leaders.gd).
func new_game(leader_id: String, info := {}) -> void:
	skip_replay()   # a replay from the game before is over
	leader = leader_id
	leader_info = Leaders.fill(leader_id, info)
	season = 1
	pop = 10
	troops = 3
	prisoners = 0
	upgrades = []
	raided_this_season = false
	log_lines = []
	ending = {}
	stats = new_stats()
	prosper_streak = 0
	starved_now = false
	buildings_lost = 0
	selected = Vector2i(-1, -1)
	selected_scout = -1
	preview = {}
	scout_route = {}
	refinery_on = {}
	res = {}
	for r in Data.RESOURCES:
		res[r] = 0
	res.merge({"wood": 30, "stone": 15, "metal": 5, "grain": 25, "veg": 10, "meat": 10, "gold": 15}, true)
	items = {}
	for item in Data.ITEMS:
		items[item] = 0
	salt_on = false
	vehicles = {}
	for v in Data.VEHICLES:
		vehicles[v] = 0
	ai = {"name": "The Rust Kings", "troops": 6, "walls": 0, "food": 20, "wood": 20, "stone": 10,
		"metal": 5, "gold": 10, "relations": 0, "truce": 0, "raid_planned": false,
		"horse": 0, "car": 0, "boat": 0, "plane": 0, "salt_stock": 0,
		"bomber": 0, "nukes": 0, "airfield_wait": 0, "airfield_x": -1, "airfield_y": -1, "airfield_seen": 0, "nuke_x": -1, "nuke_y": -1, "last_strike": -99}
	town = {"name": "Dustwell", "status": "neutral", "relations": 20}
	_apply_start_quirks()
	w = Data.MAP_W
	h = Data.MAP_H
	_generate_map()
	_sync_ai_walls()
	measured = PackedByteArray()
	measured.resize(w * h)
	show_radiation = false
	Units.new_world()
	_reset_fog()
	view = Data.PLAYER
	in_game = true
	add_log("You lead a band of %s survivors into the wastes." % Data.LEADERS[leader].name)
	add_log("Rumor says a settlement lies north and raiders hold the east. Scout the fog to find them.")
	add_log("Click a tile to build or scout. End Season when ready.")
	changed.emit()
	focus.emit(home(Data.PLAYER))


## Does this colony's leader have the perk or flaw `id`? (Their effects are worked out where the game already
## does the sum, like the upgrades are.)
func has_quirk(id: String) -> bool:
	return id in leader_info.get("perks", []) or leader_info.get("flaw", "") == id


## What a leader's perks and flaws change before the first season: stores, troops and standing with the neighbours.
func _apply_start_quirks() -> void:
	if has_quirk("old_stash"):
		res["gold"] += 20
		res["metal"] += 10
	if has_quirk("veteran_band"):
		troops += 2
	if has_quirk("silver_tongue"):
		town["relations"] += 20
	if has_quirk("hard_to_like"):
		town["relations"] -= 10
	if has_quirk("bad_blood"):
		ai["relations"] -= 15


## Builds the map in passes, each layered over the last:
##   1. base terrain from noise            2. smoothing, so each kind of ground clumps
##   3. the river's course                 4. trees: scarce, clumped, richest by the river
##   5. epicenters: ruin fields and craters
##   6. a catastrophe at each epicenter (firestorm, fallout, glassing or quake)
##   7. oases: the few green groves, on fertile ground the catastrophes missed
##   8. lone ruins   9. the river itself   10. the camps   11. radiation   12. heights, scarred by the catastrophes
func _generate_map() -> void:
	tiles.clear()
	map_version += 1
	catastrophes = []
	_pass_base_terrain()
	_pass_smooth(Data.SMOOTH_PASSES)
	var river := _plan_river()
	_pass_greenery(river)
	_pass_epicenters(river)
	_pass_catastrophes()
	_pass_oases(river)
	_pass_lone_ruins()
	_paint_river(river)
	_clear_starts()
	_make_base(Data.PLAYER_START, 3, Data.PLAYER, "hq")
	_make_base(Data.AI_START, 3, Data.AI, "ai_hq")
	_make_base(Data.TOWN_START, 2, Data.TOWN, "town")
	_pass_radiation()
	_generate_heights()
	_seed_ruins()
	_pass_pois()   # nearly last, so placing them leaves every earlier pass (and its random numbers) exactly as it was
	_pass_crossings()   # and this really is last: it has random numbers of its own
	_pass_highway()     # the old highway, which needs the old bridge
	_pass_spurs()       # and the stretches of it that fray out into the wastes from the cities (own random numbers again)
	_pass_crater_wear() # and the craters, which destroyed the road around them (and a third set of random numbers)
	_pass_gas_station() # and last, the gas station moves to the roadside (a fourth set)


## Pass 1: dunes, sand, scrub and rock from slow noise.
func _pass_base_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.08
	for y in h:
		for x in w:
			var n := noise.get_noise_2d(x, y)
			var t := "rock"
			if n < -0.3:
				t = "dunes"
			elif n < 0.05:
				t = "sand"
			elif n < 0.3:
				t = "scrub"
			tiles.append({"t": t, "o": Data.NONE, "b": "", "r": "", "rad": 0, "f": false})


## Pass 2: a tile swaps to the kind most of its 8 neighbors are (5 or more), which dissolves
## speckles and leaves clean patches. Run a few times it clumps the whole map.
func _pass_smooth(passes: int) -> void:
	for step in passes:
		var kinds := PackedStringArray()
		kinds.resize(tiles.size())
		for i in tiles.size():
			kinds[i] = tiles[i]["t"]
		for y in h:
			for x in w:
				var counts := {}
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var p := Vector2i(x + dx, y + dy)
						if (dx != 0 or dy != 0) and in_bounds(p):
							var k := kinds[idx(p)]
							counts[k] = counts.get(k, 0) + 1
				for k in counts:
					if counts[k] >= 5:
						tiles[y * w + x]["t"] = k


## Pass 13: the points of interest. One of each kind in Data.POIS gets a 2 x 2 site on open ground that fits its
## taste, away from the camps and from each other. The site's four tiles are cleared to bare ground (waste for
## the chemical dump) and all carry the same "poi_<kind>" building id, so fog, saves and the map's drawing treat it
## like a building. Scavenged as one tile: its state ("" or "picked") lives on all four.
func _pass_pois() -> void:
	poi_sites = {}
	_gas_ground = {}
	var placed: Array = []
	var kinds: Array = Data.POIS.keys()
	kinds.shuffle()
	for kind in kinds:
		var spot := _find_poi_spot(kind, placed, false)
		if spot.x < 0:
			spot = _find_poi_spot(kind, placed, true)   # no spot liked it: take any that fits
		if spot.x < 0:
			continue
		placed.append(spot)
		poi_sites[kind] = spot
		for p in poi_footprint(spot):
			var t := tile(p)
			if kind == "gas_station":
				_gas_ground[p] = t["t"]
			if t["t"] != "waste":
				t["t"] = "sand"   # bare ground under the sprite (fallout waste stays: only the dump may stand on it)
			t["b"] = "poi_" + kind
			t["r"] = ""


## After the highway: a ruined gas station stands by the old road, as one would (Data.GAS_STATION). It was placed with the other sites, before the highway existed, so if it is not
## within `reach` tiles of a highway tile it moves to free ground that is (touching one, if there is any), drawn with random numbers of its own so no other pass changes. It never
## stands on the highway: a site needs free ground, and the highway goes round the sites anyway. If nothing suits, it stays where it was.
func _pass_gas_station() -> void:
	var from: Vector2i = poi_sites.get("gas_station", Vector2i(-1, -1))
	var reach: int = Data.GAS_STATION.reach
	if from.x < 0 or highway_gap(from) <= reach:
		return
	var others := []
	for kind in poi_sites:
		if kind != "gas_station":
			others.append(poi_sites[kind])
	var touching := []
	var near := []
	for y in range(3, h - 4):
		for x in range(3, w - 5):
			var c := Vector2i(x, y)
			if not _poi_fits("gas_station", c, others):
				continue
			var gap := highway_gap(c)
			if gap == 1:
				touching.append(c)
			elif gap <= reach:
				near.append(c)
	var pool: Array = touching if not touching.is_empty() else near
	if pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _crossing_seed() + 15485863
	var spot: Vector2i = pool[rng.randi_range(0, pool.size() - 1)]
	for p in poi_footprint(from):   # the old site comes down and its ground comes back
		tile(p)["b"] = ""
		tile(p)["t"] = _gas_ground.get(p, "sand")
	for p in poi_footprint(spot):
		var t := tile(p)
		t["t"] = "sand"
		t["b"] = "poi_gas_station"
		t["r"] = ""
	poi_sites["gas_station"] = spot


## How many tiles from the 2 x 2 site at `anchor` the nearest old highway tile is: 1 when one touches it (corners too), 2 with one tile between, and so on up to 4
## (99 when there is none that close).
func highway_gap(anchor: Vector2i) -> int:
	for gap in range(1, 5):
		for dx in range(-gap, 2 + gap):
			for dy in range(-gap, 2 + gap):
				var off_x := -dx if dx < 0 else (dx - 1 if dx > 1 else 0)
				var off_y := -dy if dy < 0 else (dy - 1 if dy > 1 else 0)
				if maxi(off_x, off_y) != gap:
					continue
				var p := anchor + Vector2i(dx, dy)
				if in_bounds(p) and tile(p)["b"] == "old_road":
					return gap
	return 99


## The four tiles of a site whose top-left tile is `anchor`.
static func poi_footprint(anchor: Vector2i) -> Array:
	return [anchor, anchor + Vector2i(1, 0), anchor + Vector2i(0, 1), anchor + Vector2i(1, 1)]


func _find_poi_spot(kind: String, placed: Array, any_spot: bool) -> Vector2i:
	for attempt in Data.POI_TRIES:
		var c := Vector2i(randi_range(3, w - 5), randi_range(3, h - 5))
		if _poi_fits(kind, c, placed) and (any_spot or _poi_likes(kind, c)):
			return c
	return Vector2i(-1, -1)


## Can a 2 x 2 site stand with its top-left at c: open land nobody owns, clear of the camps and of other sites?
func _poi_fits(kind: String, c: Vector2i, placed: Array) -> bool:
	for p in poi_footprint(c):
		var t := tile(p)
		if not t["t"] in Data.POI_TERRAIN or t["o"] != Data.NONE or t["b"] != "":
			return false
		if t["t"] == "waste" and kind != "chemical_dump":
			return false   # fallout waste is the plume's: only the chemical dump stands in it
	for b in bases.values():
		if Vector2(c).distance_to(Vector2(b)) < Data.POI_BASE_GAP:
			return false
	for other in placed:
		if maxi(absi(c.x - other.x), absi(c.y - other.y)) < Data.POI_GAP:
			return false
	return true


## Does this spot suit the kind's taste (Data.POIS "near")?
func _poi_likes(kind: String, c: Vector2i) -> bool:
	match Data.POIS[kind].near:
		"river":
			var d := _nearest_terrain(c, ["water"], 7)
			return d >= 2.0 and d <= 7.0
		"rock":
			return _nearest_terrain(c, ["rock"], 2) <= 2.0
		"waste":
			return _nearest_terrain(c, ["waste"], 4) <= 4.0
		"crater":
			for cat in catastrophes:
				var d := Vector2(c).distance_to(Vector2(cat.pos))
				if d >= 6.0 and d <= 16.0:
					return true
			return false
		"open":
			return _nearest_terrain(c, ["ruins", "crater", "waste", "water", "glass"], 8) > 8.0
	return true


## How far (in tiles) the nearest tile of any of these terrains is from c, looking out to `reach` (a bigger
## number than `reach` means none was found).
func _nearest_terrain(c: Vector2i, kinds: Array, reach: int) -> float:
	var best := reach + 1.0
	for y in range(c.y - reach, c.y + reach + 2):
		for x in range(c.x - reach, c.x + reach + 2):
			var p := Vector2i(x, y)
			if in_bounds(p) and tile(p)["t"] in kinds:
				best = minf(best, Vector2(c).distance_to(Vector2(p)))
	return best


## The kind of site on this tile ("bunker", "water_tower", ...), or "" if there isn't one.
func poi_kind(c: Vector2i) -> String:
	if not in_bounds(c):
		return ""
	var b: String = tile(c)["b"]
	return Data.BUILDINGS[b].get("poi", "") if b != "" and Data.BUILDINGS.has(b) else ""


## Which quarter of its 2 x 2 site this tile is: (0, 0) the top-left, (1, 0) the top-right, and so on.
func poi_quadrant(c: Vector2i) -> Vector2i:
	var b: String = tile(c)["b"]
	var q := Vector2i.ZERO
	if in_bounds(c + Vector2i(-1, 0)) and tile(c + Vector2i(-1, 0))["b"] == b:
		q.x = 1
	if in_bounds(c + Vector2i(0, -1)) and tile(c + Vector2i(0, -1))["b"] == b:
		q.y = 1
	return q


## The top-left tile of the site that includes c.
func poi_anchor(c: Vector2i) -> Vector2i:
	return c - poi_quadrant(c)


## Pass 4: the most fertile land grows trees. Fertility is slow noise plus a bonus beside the
## river, so the trees gather in a few big clumps there.
func _pass_greenery(river: Array) -> void:
	var fertility := FastNoiseLite.new()
	fertility.seed = randi()
	fertility.frequency = 0.035
	fertility.fractal_octaves = 2
	var camps := [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]
	var score := PackedFloat32Array()
	score.resize(w * h)
	for y in h:
		for x in w:
			var span: Vector2i = river[x]
			var by_river := 1.0 - absf(y - (span.x + span.y) * 0.5) / 12.0
			var s := fertility.get_noise_2d(x, y) + Data.RIVER_FERTILITY * clampf(by_river, 0.0, 1.0)
			for camp in camps:
				if Vector2i(x, y).distance_to(camp) < Data.GREEN_CAMP_GAP:
					s = -10.0
			score[y * w + x] = s
	fertility_map = score   # kept for the oases pass
	var sorted := Array(score)
	sorted.sort()
	var cut: float = sorted[int(sorted.size() * (1.0 - Data.TREE_SHARE))]
	for i in tiles.size():
		if score[i] >= cut:
			tiles[i]["t"] = "trees"


## Pass 7: the oases. Green groves grow at the most fertile spots that the catastrophes spared:
## clear of every ruin field (and of a firestorm's whole burn zone), and back from the river so
## it doesn't cut them in half. They're kept well apart.
func _pass_oases(river: Array) -> void:
	var order := range(fertility_map.size())
	order.sort_custom(func(a, b): return fertility_map[a] > fertility_map[b])
	var oases := []
	for i in order:
		if oases.size() >= Data.GROVE_COUNT:
			break
		var c := Vector2i(i % w, i / w)
		var span: Vector2i = river[c.x]
		var ok: bool = fertility_map[i] > -5.0 and (c.y < span.x - 8 or c.y >= span.y + 8)
		for cat in catastrophes:
			var spared: float = cat.radius * (Data.BURN_REACH if cat.kind == "firestorm" else 1.3) + 6.0
			ok = ok and c.distance_to(cat.pos) >= spared
		ok = ok and oases.all(func(o): return c.distance_to(o) >= Data.GROVE_SPACING)
		if not ok:
			continue
		oases.append(c)
		var radius := randf_range(Data.GROVE_RADIUS[0], Data.GROVE_RADIUS[1])
		for p in _circle(c, ceili(radius * 1.5)):
			var d := c.distance_to(p)
			if d <= radius * randf_range(0.8, 1.05) and randf() < 0.92:
				tile(p)["t"] = "grove"
			elif d <= radius * 1.5 and randf() < 0.6 and tile(p)["t"] in ["sand", "dunes", "scrub", "rock"]:
				tile(p)["t"] = "trees"


## The river's course: for each column, the Vector2i(first row, one past the last row) of water.
## It follows a slanted line across the map with a gentle random wander, and each column also
## covers the rows of the one before so the channel never breaks into diagonal-only steps.
func _plan_river() -> Array:
	var spans := []
	var wander := 0
	var width: int = Data.RIVER_WIDTH[0]
	var prev := Vector2i(-1, -1)
	for x in w:
		if randf() < 0.3:
			wander = clampi(wander + randi_range(-1, 1), -Data.RIVER_WIGGLE, Data.RIVER_WIGGLE)
		if randf() < 0.3:
			width = clampi(width + randi_range(-1, 1), Data.RIVER_WIDTH[0], Data.RIVER_WIDTH[1])
		var top := roundi(Data.RIVER_MID_Y + Data.RIVER_SLOPE * (x - w / 2)) + wander
		var span := Vector2i(top, top + width)
		if prev.x >= 0:
			span = Vector2i(mini(span.x, prev.x), maxi(span.y, prev.y))
		span = Vector2i(clampi(span.x, 1, h - 3), clampi(span.y, 2, h - 1))
		spans.append(span)
		prev = Vector2i(top, top + width)
	return spans


func _paint_river(spans: Array) -> void:
	for x in w:
		for y in range(spans[x].x, spans[x].y):
			tile(Vector2i(x, y))["t"] = "water"


# ---------------------------------------------------------------- crossings

## The old highway, one long ruined road through every city and over the old bridge (the craters at the cities' centres take the road again afterwards: _pass_crater_wear). On each bank it goes from the bridge to the
## nearest city, then the next nearest, along the cheapest ground (round rock, steep inclines and craters where it can, never through water or round
## a building). It takes no random numbers. It keeps off tiles that already hold something.
func _pass_highway() -> void:
	var bridge := []
	for i in tiles.size():
		if tiles[i]["b"] == "old_bridge":
			bridge.append(Vector2i(i % w, i / w))
	if bridge.is_empty():
		return
	_label_banks()
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, w, h)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER   # a road runs in straight lines
	grid.update()
	for i in tiles.size():
		var c := Vector2i(i % w, i / w)
		var t: Dictionary = tiles[i]
		if t["t"] == "water" and t["b"] != "old_bridge":
			grid.set_point_solid(c)
			continue
		var weight := 1.0
		if slopes[i] == "steep":
			weight = 6.0
		elif t["t"] == "rock" or t["t"] == "crater" or t["t"] == "glass":
			weight = 3.0
		elif t["t"] == "trees" or t["t"] == "grove":
			weight = 2.0
		if t["b"] != "" and t["b"] != "old_bridge":
			weight = 20.0   # round sites and bases when it can
		grid.set_point_weight_scale(c, weight)
	var top: Vector2i = bridge[0]
	var bottom: Vector2i = bridge[bridge.size() - 1]
	var ends := [Vector2i(top.x, top.y - 1), Vector2i(bottom.x, bottom.y + 1)]
	var cities := []
	for cat in catastrophes:
		cities.append(Vector2i(cat.pos))
	var cells := {}
	for end in ends:
		if not in_bounds(end) or banks[idx(end)] == 0:
			continue
		var here: Vector2i = end
		cells[end] = true
		var left: Array = cities.filter(func(city): return banks[idx(city)] == banks[idx(end)])
		while not left.is_empty():
			left.sort_custom(func(a, b): return a.distance_to(here) < b.distance_to(here))
			var next: Vector2i = left.pop_front()
			for c in grid.get_id_path(here, next):
				cells[c] = true
			here = next
	var laid := []
	for c in cells:
		if tile(c)["t"] != "water" and tile(c)["b"] == "":
			tile(c)["b"] = "old_road"
			laid.append(c)
	_update_paths_at(laid)


var poi_sites := {}    # kind -> the top-left tile of its site, as the map was made (not saved: the tiles are)
var _gas_ground := {}  # the ground under the gas station's first spot, to put back if it moves
var worn := []    # the old road tiles the craters took (_pass_crater_wear), for tests: not saved either
var spurs := []   # what _pass_spurs laid, for tests and the curious: {"city": cell, "heading": direction, "laid": [cells]} (not saved: the tiles are)


## After the highway: the roads that lead out of the city centres into the wastes where there is no city to join, and fray away. See Data.SPURS. Each is a
## solid stretch of real highway joined to its city, then fragments with gaps between them that get shorter, until nothing is left or the ground ends it.
## Scouts who see a fragment can follow it back to the highway. It has a random number generator of its own (seeded from the map), so no other pass changes.
func _pass_spurs() -> void:
	spurs = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _crossing_seed() + 7919
	var cities := []
	for cat in catastrophes:
		cities.append(Vector2i(cat.pos))
	var laid := []
	for city in cities:
		if tile(city)["b"] != "old_road":
			continue   # the highway did not come to this city (there is no old bridge)
		var taken := []
		for k in rng.randi_range(Data.SPURS.per_city[0], Data.SPURS.per_city[1]):
			var heading := _spur_heading(city, cities, taken, rng)
			if heading == Vector2i.ZERO:
				break
			taken.append(heading)
			var cells := _lay_spur(city, heading, rng)
			spurs.append({"city": city, "heading": heading, "laid": cells})
			laid.append_array(cells)
	_update_paths_at(laid)


## A way out of `city` that no other spur of it takes, that points at no other city and that has open ground for its first few tiles. (0, 0) if there is none.
func _spur_heading(city: Vector2i, cities: Array, taken: Array, rng: RandomNumberGenerator) -> Vector2i:
	var options := []
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if d in taken:
			continue
		var toward := false
		for other in cities:
			if other != city and Vector2(other - city).normalized().dot(Vector2(d)) > Data.SPURS.away:
				toward = true
		if toward:
			continue
		var open := true
		for k in range(1, 4):
			if not _spur_ok(city + d * k):
				open = false
		if open:
			options.append(d)
	if options.is_empty():
		return Vector2i.ZERO
	return options[rng.randi_range(0, options.size() - 1)]


## Lay one spur from `city` towards `heading` and return the tiles it laid: the solid stretch, then the fragments.
func _lay_spur(city: Vector2i, heading: Vector2i, rng: RandomNumberGenerator) -> Array:
	var plan := []   # one entry for each step: true lays the tile, false leaves a gap
	for i in rng.randi_range(Data.SPURS.solid[0], Data.SPURS.solid[1]):
		plan.append(true)
	for k in rng.randi_range(Data.SPURS.fragments[0], Data.SPURS.fragments[1]):
		for i in rng.randi_range(Data.SPURS.gap[0], Data.SPURS.gap[1]):
			plan.append(false)
		for i in rng.randi_range(1, maxi(Data.SPURS.fragment_length - k, 1)):
			plan.append(true)
	var out := []
	var at := city
	var side := Vector2i(heading.y, heading.x)
	for lay in plan:
		var step: Array = [heading]
		if rng.randf() < Data.SPURS.jog:
			step = [side if rng.randf() < 0.5 else -side, heading]
		for d in step:
			at += d
			if not in_bounds(at) or tile(at)["t"] == "water" or not _clear_of_bases(at):
				return out   # the river, the edge of the map or a base ends it
			if lay and tile(at)["b"] == "":   # a building on the way has swallowed the road under it
				tile(at)["b"] = "old_road"
				out.append(at)
	return out


## Can a spur run over tile `c`? Open land: not water, nothing built on it, and well away from the bases. (The rim of a crater is steep and the highway runs
## over it, so a spur can too.)
func _spur_ok(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var t := tile(c)
	return t["t"] != "water" and t["b"] == "" and _clear_of_bases(c)


func _clear_of_bases(c: Vector2i) -> bool:
	for base in [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]:
		if Vector2(c).distance_to(Vector2(base)) < Data.SPURS.keep:
			return false
	return true


## The craters destroyed the old road around them long ago. After the highway and its spurs are laid, no old road is left on a crater, and the nearer a tile of it
## is to one the less likely it survives: (distance to the nearest crater tile) / Data.CRATER_WEAR.radius is its chance, up to that distance, so the road gets
## patchier and patchier towards each crater. It has random numbers of its own (seeded from the map) and takes what is lost out of the spurs' lists too.
func _pass_crater_wear() -> void:
	worn = []
	var craters := []
	for i in tiles.size():
		if tiles[i]["t"] == "crater":
			craters.append(Vector2i(i % w, i / w))
	if craters.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _crossing_seed() + 104729
	var radius: float = Data.CRATER_WEAR.radius
	var gone := {}
	for i in tiles.size():
		if tiles[i]["b"] != "old_road":
			continue
		var c := Vector2i(i % w, i / w)
		var d := radius
		for k in craters:
			var between := Vector2(c).distance_to(Vector2(k))
			if between < d:
				d = between
		if d >= radius:
			continue
		if rng.randf() >= d / radius:
			tiles[i]["b"] = ""
			gone[c] = true
	for s in spurs:
		s["laid"] = s.laid.filter(func(c): return not gone.has(c))
	worn = gone.keys()
	_update_paths_at(worn)


## The old highway tiles that lie in a stretch of road at least Data.SPURS.piece tiles long (counting roads you or the Rust Kings built and repaired, and the
## old bridge): worth heading for, unlike the fragments lying out in the wastes.
func _highway_pieces() -> Dictionary:
	var seen := {}
	var out := {}
	for i in tiles.size():
		var start := Vector2i(i % w, i / w)
		if seen.has(start) or not _carries_road_tile(start):
			continue
		var piece := [start]
		seen[start] = true
		var head := 0
		while head < piece.size():
			for n in neighbors(piece[head]):
				if not seen.has(n) and _carries_road_tile(n):
					seen[n] = true
					piece.append(n)
			head += 1
		if piece.size() >= Data.SPURS.piece:
			for c in piece:
				out[c] = true
	return out


func _carries_road_tile(c: Vector2i) -> bool:
	var b: String = tile(c)["b"]
	return b != "" and (Data.BUILDINGS[b].get("road", false) or Data.BUILDINGS[b].get("bridge", false))


## The river is a wall for everything on the ground (Data.MOVERS water = 0), so the map needs ways across it. This is the last pass of map
## making, and it has a random number generator of its own (seeded from the map), so nothing made before or after it changes:
##   the old bridge   one tile wide, in the middle of the map: every kind of party can use it, so it is a chokepoint;
##   two fords        wadeable strips of river (foot and horseback only), one on the way to Dustwell, one on the way to the fort;
##   a third ford     at random.
## Then it checks that your home can reach the fort and Dustwell on foot, and adds fords until it can.
func _pass_crossings() -> void:
	_crossing_cells = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _crossing_seed()
	var rows := _river_rows()
	var cols := []   # the first column of every crossing, to keep them apart
	var bridge := _pick_bridge_column(rows)
	if bridge >= 0:
		_set_old_bridge(bridge, rows)
		cols.append(bridge)
	for share in Data.FORDS:
		var x := _free_column(roundi(w * share) + rng.randi_range(-Data.FORD_JITTER, Data.FORD_JITTER), cols, Data.CROSSING_GAP, rows)
		if x >= 0:
			_set_ford(x, rows)
			cols.append(x)
	var options := []
	for x in range(Data.FORD_EXTRA_EDGE, w - Data.FORD_EXTRA_EDGE):
		if _column_ok(x, rows) and cols.all(func(o): return absi(x - o) >= Data.FORD_EXTRA_GAP):
			options.append(x)
	if not options.is_empty():
		var x: int = options[rng.randi_range(0, options.size() - 1)]
		_set_ford(x, rows)
		cols.append(x)
	for attempt in 8:   # the guarantee: your home reaches the fort and Dustwell on foot
		var seen := _reach(Data.PLAYER_START, false, true)
		if seen[idx(Data.AI_START)] == 1 and seen[idx(Data.TOWN_START)] == 1:
			break
		var x := _free_column(w / 2 + (attempt - 4) * 7, cols, 4, rows)
		if x < 0:
			break
		_set_ford(x, rows)
		cols.append(x)
	_update_paths_at(_crossing_cells)


## A number made from the map's own tiles: the same map always gets the same crossings.
func _crossing_seed() -> int:
	var n := 17
	for i in range(0, tiles.size(), 5):
		n = (n * 31 + hash(tiles[i]["t"]) + int(tiles[i].get("z", 0))) & 0x3fffffff
	return n


## For each column, Vector2i(first row, last row) of the river's water, or (-1, -1) where there is none.
func _river_rows() -> Array:
	var rows := []
	for x in w:
		var first := -1
		var last := -1
		for y in h:
			if tiles[y * w + x]["t"] == "water":
				if first < 0:
					first = y
				last = y
		rows.append(Vector2i(first, last))
	return rows


## Can a crossing start at column x (the river is there, in this and the next FORD_WIDTH - 1 columns)?
func _column_ok(x: int, rows: Array) -> bool:
	for k in Data.FORD_WIDTH:
		if x + k < 0 or x + k >= w or rows[x + k].x < 0:
			return false
	return true


## The column nearest `ideal` (looking outward, up to 12 either way) where a ford fits and keeps `gap` columns from every crossing in `cols`.
func _free_column(ideal: int, cols: Array, gap: int, rows: Array) -> int:
	for step in range(0, 13):
		for side in ([1] if step == 0 else [1, -1]):
			var x: int = ideal + side * step
			if x >= 0 and x < w and _column_ok(x, rows) and cols.all(func(o): return absi(x - o) >= gap):
				return x
	return -1


## The old bridge's column: the middle one, or the nearest (within BRIDGE_SEARCH) where a war rig can drive from your HQ to the Rust Kings'
## fort over a one-tile bridge. Steep inclines can wall off an end of the bridge, which is why it may have to move.
func _pick_bridge_column(rows: Array) -> int:
	var mid := w / 2
	var from_you := _reach(Data.PLAYER_START, true, false)
	var from_them := _reach(Data.AI_START, true, false)
	for step in range(0, Data.BRIDGE_SEARCH + 1):
		for side in ([1] if step == 0 else [1, -1]):
			var x: int = mid + side * step
			if x < 0 or x >= w or rows[x].x < 1 or rows[x].y >= h - 1:
				continue
			var north := idx(Vector2i(x, rows[x].x - 1))
			var south := idx(Vector2i(x, rows[x].y + 1))
			if (from_you[north] == 1 and from_them[south] == 1) or (from_you[south] == 1 and from_them[north] == 1):
				return x
	return mid if rows[mid].x >= 0 else -1   # no column suits a war rig: it goes in the middle anyway, and foot parties use it


func _set_old_bridge(x: int, rows: Array) -> void:
	for y in range(rows[x].x, rows[x].y + 1):
		tile(Vector2i(x, y))["b"] = "old_bridge"
		_crossing_cells.append(Vector2i(x, y))


func _set_ford(x: int, rows: Array) -> void:
	for k in Data.FORD_WIDTH:
		for y in range(rows[x + k].x, rows[x + k].y + 1):
			tile(Vector2i(x + k, y))["f"] = true
			_crossing_cells.append(Vector2i(x + k, y))


var _crossing_cells: Array = []   # the tiles the crossing pass changed, so only their route costs are redone


## Redoes the route costs of just these tiles for every way of travel (a bridge went up or came down, or the crossing pass ran).
func _update_paths_at(cells: Array) -> void:
	for mover in Data.MOVERS:
		var grid: AStarGrid2D = paths[mover]
		for c in cells:
			var mult := move_mult(mover, c)
			grid.set_point_solid(c, mult <= 0.0)
			if mult > 0.0:
				grid.set_point_weight_scale(c, mult)


## Every tile that can be walked to from `start` with the river a wall (4 directions). A war rig also avoids steep inclines.
## With `through_crossings` the fords and bridges are open (as they are for a foot party).
func _reach(start: Vector2i, rig: bool, through_crossings: bool) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(tiles.size())
	var queue := [start]
	seen[idx(start)] = 1
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for n in neighbors(c):
			var i := idx(n)
			if seen[i] == 1:
				continue
			var t: Dictionary = tiles[i]
			if t["t"] == "water" and not (through_crossings and (t.get("f", false) or t["b"] in ["old_bridge", "bridge"])):
				continue
			if rig and not slopes.is_empty() and slopes[i] == "steep" and not t["b"] in ["hq", "ai_hq", "town"]:
				continue
			seen[i] = 1
			queue.append(n)
	return seen


## Pass 5: big clusters of pre-war ruins, each with a glowing crater at its center where the
## bomb hit. The ruins thin out toward the edge, and the outline is ragged. Epicenters keep clear
## of the camps and the river. Each one is recorded in `catastrophes`.
func _pass_epicenters(river: Array) -> void:
	var shape := FastNoiseLite.new()
	shape.seed = randi()
	shape.frequency = 0.9
	var camps := [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]
	for attempt in 300:
		if catastrophes.size() >= Data.EPICENTERS:
			break
		var radius := randi_range(Data.EPICENTER_RADIUS[0], Data.EPICENTER_RADIUS[1])
		var c := Vector2i(randi_range(radius, w - radius - 1), randi_range(radius, h - radius - 1))
		var clear := true
		for camp in camps:
			clear = clear and c.distance_to(camp) >= radius + Data.EPICENTER_CAMP_GAP
		for other in catastrophes:
			clear = clear and c.distance_to(other.pos) >= radius + other.radius + 3
		for x in [c.x - radius, c.x, c.x + radius]:
			var span: Vector2i = river[clampi(x, 0, w - 1)]
			clear = clear and (c.y < span.x - radius - Data.EPICENTER_RIVER_GAP or c.y >= span.y + radius + Data.EPICENTER_RIVER_GAP)
		if not clear:
			continue
		var crater := randf_range(Data.CRATER_RADIUS[0], Data.CRATER_RADIUS[1])
		catastrophes.append({"pos": c, "radius": radius, "crater": crater})
		for p in _circle(c, radius + 1):
			var d := c.distance_to(p)
			# The edge wobbles with the angle, so a cluster is a blob rather than a disc
			var angle := atan2(p.y - c.y, p.x - c.x)
			var reach := radius * (0.75 + 0.35 * (shape.get_noise_2d(c.x + cos(angle) * 4.0, c.y + sin(angle) * 4.0) + 1.0))
			if d <= crater:
				tile(p)["t"] = "crater"
			elif d <= reach and randf() < lerpf(0.95, 0.3, d / reach):
				tile(p)["t"] = "ruins"


## Pass 6: every epicenter suffered one catastrophe, so the four kinds all turn up on a normal
## map. Each leaves its mark on the land (and the quake on the heights, later).
func _pass_catastrophes() -> void:
	var kinds: Array = Data.CATASTROPHES.keys()
	kinds.shuffle()
	for i in catastrophes.size():
		var cat: Dictionary = catastrophes[i]
		cat["kind"] = kinds[i] if i < kinds.size() else kinds.pick_random()
		cat["year"] = randi_range(Data.CATASTROPHE_YEARS[0], Data.CATASTROPHE_YEARS[1])
		cat["name"] = "The %s %s" % [Data.CATASTROPHE_NAMES[0].pick_random(), Data.CATASTROPHE_NAMES[1].pick_random()]
		match cat.kind:
			"firestorm":
				_burn(cat)
			"fallout":
				_blow_fallout(cat)
			"glassing":
				_fuse_glass(cat)
			"quake":
				cat["faults"] = []
				for f in randi_range(Data.FAULTS[0], Data.FAULTS[1]):
					cat["faults"].append(randf() * TAU)


## Firestorm: greenery out to BURN_REACH x the ruin field's radius is ash.
func _burn(cat: Dictionary) -> void:
	var reach: float = cat.radius * Data.BURN_REACH
	for p in _circle(cat.pos, ceili(reach * 1.1)):
		if tile(p)["t"] in ["scrub", "trees", "grove"] and cat.pos.distance_to(p) <= reach * randf_range(0.8, 1.1):
			tile(p)["t"] = "sand"


## Fallout: the plume blows in whichever direction keeps it furthest from the camps.
func _blow_fallout(cat: Dictionary) -> void:
	var c: Vector2 = cat.pos
	var best_gap := -1.0
	for attempt in 12:
		var angle := randf() * TAU
		var length := randf_range(Data.PLUME_LENGTH[0], Data.PLUME_LENGTH[1])
		var gap := 1000.0
		for camp in [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]:
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(camp), c, c + Vector2.from_angle(angle) * length)
			gap = minf(gap, Vector2(camp).distance_to(nearest))
		if gap > best_gap:
			best_gap = gap
			cat["angle"] = angle
			cat["length"] = length
		if gap >= Data.PLUME_CAMP_GAP:
			break
	for p in _circle(cat.pos, ceili(cat.length) + 5):
		if in_plume(cat, p) and tile(p)["t"] in ["sand", "dunes", "scrub", "rock", "trees", "grove"] and randf() < 0.8:
			tile(p)["t"] = "waste"


## Whether tile `p` lies in a fallout plume (the plume tapers from the epicenter).
func in_plume(cat: Dictionary, p: Vector2i) -> bool:
	return plume_depth(cat, p) >= 0.0


## How far into a fallout plume tile `p` is: 1 at the epicenter, 0 at the far tip, -1 if outside.
func plume_depth(cat: Dictionary, p: Vector2i) -> float:
	var rel := Vector2(p - cat.pos)
	var dir := Vector2.from_angle(cat.angle)
	var along := rel.dot(dir)
	if along < 0.0 or along > cat.length:
		return -1.0
	if absf(rel.dot(dir.orthogonal())) > Data.PLUME_WIDTH * (1.0 - 0.75 * along / cat.length):
		return -1.0
	return 1.0 - along / cat.length


## Glassing: the ground around the crater is fused, ruins and all.
func _fuse_glass(cat: Dictionary) -> void:
	var reach: float = cat.crater * Data.GLASS_REACH + 1.5
	for p in _circle(cat.pos, ceili(reach * 1.1)):
		if tile(p)["t"] != "crater" and cat.pos.distance_to(p) <= reach * randf_range(0.8, 1.1):
			tile(p)["t"] = "glass"


## The catastrophe whose mark is on this tile (its ruin field, or the fallout plume), or {}.
func catastrophe_at(c: Vector2i) -> Dictionary:
	for cat in catastrophes:
		if c.distance_to(cat.pos) <= cat.radius * 1.1:
			return cat
		if cat.kind == "fallout" and in_plume(cat, c):
			return cat
	return {}


## Pass 7: a scattering of lone ruins, away from the big fields.
func _pass_lone_ruins() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.15
	for i in tiles.size():
		if noise.get_noise_2d(i % w, i / w) > Data.SCATTERED_RUINS and tiles[i]["t"] in ["sand", "dunes", "scrub", "rock"]:
			tiles[i]["t"] = "ruins"


## Pass 11: how hot each tile is. A faint random background, plus what the terrain left behind
## (craters, glass, waste, ruins), plus the glow of each epicenter falling off with distance and
## the fallout plume, strongest at its source. The starting areas stay at background level.
func _pass_radiation() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.05
	var level := PackedFloat32Array()
	level.resize(w * h)
	for i in tiles.size():
		level[i] = 1.5 + 1.5 * noise.get_noise_2d(i % w, i / w) + Data.RAD_TERRAIN.get(tiles[i]["t"], 0) * randf_range(0.8, 1.2)
	for cat in catastrophes:
		var reach := ceili(cat.radius * 1.6)
		if cat.kind == "fallout":
			reach = maxi(reach, ceili(cat.length) + 5)
		for p in _circle(cat.pos, reach):
			var i := idx(p)
			level[i] += Data.RAD_CRATER * exp(-cat.pos.distance_to(p) / (cat.radius * Data.RAD_FALLOFF))
			if cat.kind == "fallout":
				level[i] += Data.RAD_PLUME * maxf(plume_depth(cat, p), 0.0)
	for camp in [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]:
		for p in _circle(camp, Data.START_CLEAR):
			level[idx(p)] = minf(level[idx(p)], 3.0)
	for i in tiles.size():
		tiles[i]["rad"] = clampi(roundi(level[i]), 0, Data.RAD_MAX)


# ---------------------------------------------------------------- radiation

## The tile's true radiation in R/h. Only the game should use this: show the player
## reading_text(), which hides it until the tile has been measured.
func radiation(c: Vector2i) -> int:
	return tile(c)["rad"]


## A scouting party standing on (or passing over) a tile takes a reading, kept for the whole run.
func measure(c: Vector2i) -> void:
	if in_bounds(c) and measured.size() == w * h:
		measured[idx(c)] = 1


## Whether you know the exact radiation here: a party has measured it, or it's your own land.
func is_measured(c: Vector2i) -> bool:
	return measured.size() == w * h and (measured[idx(c)] == 1 or tile(c)["o"] == Data.PLAYER)


## [name, color] of the band a reading falls in.
func rad_band(reading: int) -> Array:
	var band: Array = Data.RAD_BANDS[0]
	for b in Data.RAD_BANDS:
		if reading >= b[0]:
			band = b
	return [band[1], band[2]]


## What the player is told about a tile's radiation: the exact figure if it's been measured,
## otherwise only a wide range.
func reading_text(c: Vector2i) -> String:
	var r := radiation(c)
	if is_measured(c):
		return "%d R/h (%s)" % [r, rad_band(r)[0]]
	var hi := int(ceil(r * 1.6 / 5.0)) * 5
	if hi <= Data.RAD_SAFE:
		return "not measured, probably safe"
	return "not measured, roughly %d-%d R/h" % [int(r * 0.5 / 5.0) * 5, hi]


func _measured_cells() -> Array:
	var cells := []
	for i in measured.size():
		if measured[i] == 1:
			cells.append(i)
	return cells


func toggle_radiation_view() -> void:
	show_radiation = not show_radiation
	changed.emit()


## Keeps the starting areas open desert: no craters, ruins, glass or fallout right around a camp.
## (The river is planned to pass them, so it never needs clearing.)
func _clear_starts() -> void:
	for camp in [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]:
		for p in _circle(camp, Data.START_CLEAR):
			if in_bounds(p) and tile(p)["t"] in ["crater", "ruins", "glass", "waste"]:
				tile(p)["t"] = "sand"


## Pre-war ruins hide dangers for scavengers. Ruins near the settlements are always safe.
func _seed_ruins() -> void:
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		if t["t"] != "ruins" or t["r"] != "":
			continue
		var c := Vector2i(i % w, i / w)
		var roll := randf()
		if bases.values().any(func(b): return c.distance_to(b) < 6):
			t["r"] = "safe"
		elif roll < Data.RUIN_ROGUE_CHANCE:
			t["r"] = "rogue"
		elif roll < Data.RUIN_ROGUE_CHANCE + Data.RUIN_TRAP_CHANCE:
			t["r"] = "trap"
		else:
			t["r"] = "safe"


## Find each settlement's center on the map (used when loading a save).
func _find_bases() -> void:
	bases = {}
	var centers := {"hq": Data.PLAYER, "ai_hq": Data.AI, "town": Data.TOWN}
	for i in tiles.size():
		if tiles[i]["b"] in centers:
			bases[centers[tiles[i]["b"]]] = Vector2i(i % w, i / w)


## Where a colony's HQ (or Dustwell) is.
func home(owner: int) -> Vector2i:
	return bases[owner]


func _make_base(c: Vector2i, radius: int, owner: int, hq: String) -> void:
	for y in range(c.y - radius, c.y + radius + 1):
		for x in range(c.x - radius, c.x + radius + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and c.distance_to(p) <= radius + 0.5:
				tile(p)["o"] = owner
	bases[owner] = c
	# Guarantee some useful terrain next to every base
	tile(c)["t"] = "sand"
	tile(c)["b"] = hq
	tile(c + Vector2i(2, 1))["t"] = "rock"
	tile(c + Vector2i(-2, -1))["t"] = "trees"
	tile(c + Vector2i(1, -2))["t"] = "ruins"
	tile(c + Vector2i(-1, 2))["t"] = "sand"


# ---------------------------------------------------------------- height & contours

## Height in meters. Rolling hills, plus mesas (flat-topped plateaus) and canyons whose edges
## are steep inclines. Those are kept away from the settlements so nobody starts walled in.
func _generate_heights() -> void:
	var hills := FastNoiseLite.new()
	hills.seed = randi()
	hills.frequency = 0.025
	hills.fractal_octaves = 3
	var cliffs := FastNoiseLite.new()
	cliffs.seed = randi()
	cliffs.frequency = 0.06
	cliffs.fractal_octaves = 2
	for i in tiles.size():
		var c := Vector2i(i % w, i / w)
		var z := int(round(hills.get_noise_2d(c.x, c.y) * 45))
		var near_base := false
		for base in bases.values():
			if c.distance_to(base) < 6:
				near_base = true
		var m := cliffs.get_noise_2d(c.x, c.y)
		if not near_base and tiles[i]["t"] != "water":
			if m > 0.45:
				z += 25   # mesa
			elif m < -0.5:
				z -= 25   # canyon
		if tiles[i]["t"] == "crater":
			z -= 8
		elif tiles[i]["t"] == "water":
			z -= 6
		tiles[i]["z"] = z
	_scar_heights()
	_build_contours()


## The catastrophes leave their marks on the ground: a raised rim round each crater, and
## deep faults running out from a quake's epicenter.
func _scar_heights() -> void:
	for cat in catastrophes:
		var c: Vector2i = cat.pos
		for p in _circle(c, ceili(cat.crater) + 3):
			var d := c.distance_to(p)
			if d > cat.crater and d <= cat.crater + 1.6 and tile(p)["t"] != "water":
				tile(p)["z"] += 7
		var reach: float = cat.radius * Data.FAULT_REACH
		for angle in cat.get("faults", []):
			var dir := Vector2.from_angle(angle)
			for p in _circle(c, ceili(reach) + 1):
				var rel := Vector2(p - c)
				var along := rel.dot(dir)
				if along >= 0.0 and along <= reach and absf(rel.dot(dir.orthogonal())) <= 1.0 and tile(p)["t"] != "water":
					tile(p)["z"] -= Data.FAULT_DROP


## The biggest height drop from this tile to any of its 8 neighbors.
func _drop(c: Vector2i) -> int:
	var drop := 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := c + Vector2i(dx, dy)
			if in_bounds(n):
				drop = maxi(drop, tile(c)["z"] - tile(n)["z"])
	return drop


func _build_contours() -> void:
	var bits := {Vector2i.UP: 1, Vector2i.DOWN: 2, Vector2i.LEFT: 4, Vector2i.RIGHT: 8}
	# Which 10 m height band each tile is in (0 = 0..9 m, -1 = -10..-1 m, ...)
	var band := PackedInt32Array()
	band.resize(tiles.size())
	for i in tiles.size():
		band[i] = floori(tiles[i]["z"] / float(Data.CONTOUR_STEP))
	# A contour runs along the high side of every 10 m step, checked against all 8 neighbors
	# so diagonal slopes still form a connected line.
	var on := PackedByteArray()
	on.resize(tiles.size())
	for i in tiles.size():
		var c := Vector2i(i % w, i / w)
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and band[idx(n)] < band[i]:
					on[i] = 1
	contours = []
	slopes = []
	for i in tiles.size():
		var c := Vector2i(i % w, i / w)
		if on[i] == 0 or tiles[i]["t"] == "water":   # rivers are fords, not slopes
			contours.append("")
			slopes.append("")
			continue
		# Join to neighbors that sit on the same contour line
		var mask := 0
		for d in bits:
			var n: Vector2i = c + d
			if in_bounds(n) and band[idx(n)] == band[i] and on[idx(n)] == 1:
				mask |= bits[d]
		if mask == 0:
			contours.append("")   # a lone one-tile bump: not worth a line
			slopes.append("")
			continue
		var steep := _drop(c) >= Data.STEEP_DROP
		slopes.append("steep" if steep else "gentle")
		contours.append((Data.CONTOUR_STEEP if steep else Data.CONTOUR_GENTLE)[mask])
	_build_paths()


# ---------------------------------------------------------------- travel

## How many times slower a mover is on this tile than on flat ground (0 = can't enter).
func move_mult(mover: String, c: Vector2i) -> float:
	var m: Dictionary = Data.MOVERS[mover]
	var t := tile(c)
	if t["t"] == "water":
		if t["b"] != "" and Data.BUILDINGS[t["b"]].get("bridge", false):
			return m.bridge
		return m.ford if t.get("f", false) else m.water
	if tile(c)["b"] in ["hq", "ai_hq", "town"]:
		return m.land   # settlements always have a way in
	var s: String = slopes[idx(c)]
	var base: float = m[s] if s != "" else m.land
	var b: String = t["b"]
	if b != "" and Data.BUILDINGS[b].get("road", false):
		if base <= 0.0:
			return 0.0   # a boat still cannot sail over land, nor a war rig climb a steep incline
		return float(Data.HIGHWAY.speed if Data.BUILDINGS[b].get("highway", false) else Data.ROAD.speed)
	return base * ground_speed(t["t"], mover)


## How many times longer than sand a tile of this ground takes (Data.TERRAIN_SPEED); 1.0 for a boat or a plane.
func ground_speed(terrain_id: String, mover: String) -> float:
	return Data.TERRAIN_SPEED.get(terrain_id, {}).get(mover, 1.0)


## "foot 1.3x, horse 1.5x, war rig 1.8x slower", or "" for ground that is as quick as sand.
func speed_text(terrain_id: String) -> String:
	var parts := []
	for mover in ["foot", "horse", "car"]:
		var k := ground_speed(terrain_id, mover)
		if k > 1.0:
			parts.append("%s %sx" % [Data.MOVERS[mover].name.to_lower(), str(k)])
	return "" if parts.is_empty() else ", ".join(parts) + " slower"


## One route finder per way of travel. Steep inclines are walls for war rigs, land for boats.
func _build_paths() -> void:
	for mover in Data.MOVERS:
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(0, 0, w, h)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		for i in tiles.size():
			var c := Vector2i(i % w, i / w)
			var mult := move_mult(mover, c)
			if mult <= 0.0:
				grid.set_point_solid(c)
			else:
				grid.set_point_weight_scale(c, mult)
		paths[mover] = grid


## The nearest tile a party on foot can stand on, looking outward from `c` up to `reach` tiles: `c` itself if it is one. (-1, -1) if there is none.
## With `toward` set, only a tile with a way on foot to `toward` counts, so a crew wading ashore does not land on the wrong bank.
func nearest_walkable(c: Vector2i, reach := 8, toward := Vector2i(-1, -1)) -> Vector2i:
	if move_mult("foot", c) > 0.0 and (toward.x < 0 or not route("foot", c, toward).is_empty()):
		return c
	for r in range(1, reach + 1):
		var found: Array = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := c + Vector2i(dx, dy)
				if in_bounds(p) and move_mult("foot", p) > 0.0:
					found.append(p)
		found.sort_custom(func(a, b): return Vector2(a - c).length() < Vector2(b - c).length())
		for p in found:
			if toward.x < 0 or not route("foot", p, toward).is_empty():
				return p
	return Vector2i(-1, -1)


## True for a river tile that can be waded.
## Every tile of the road network that joins `owner`'s land: road tiles on it or beside it, and everything of the same kind that touches those
## (roads, bridges and fords all carry it on). The old highway counts, so a road out to it and the highway are one network.
func road_network(owner: int) -> Dictionary:
	var net := {}
	var queue := []
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		if t["b"] != "" and Data.BUILDINGS[t["b"]].get("road", false):
			var c := Vector2i(i % w, i / w)
			if t["o"] == owner or borders(c, owner):
				net[c] = true
				queue.append(c)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for n in neighbors(c):
			if net.has(n):
				continue
			var t: Dictionary = tile(n)
			var carries: bool = t.get("f", false) or (t["b"] != "" and (Data.BUILDINGS[t["b"]].get("road", false) or Data.BUILDINGS[t["b"]].get("bridge", false)))
			if carries:
				net[n] = true
				queue.append(n)
	return net


## Would a road tile on free land `c` join `owner`'s land or a road that reaches it?
func road_reaches(c: Vector2i, owner: int) -> bool:
	if borders(c, owner):
		return true
	var net := road_network(owner)
	for n in neighbors(c):
		if net.has(n):
			return true
	return false


## The Rust Kings lay a few road tiles each season (Data.AI_ROAD): out from their fort along the route to the old highway first, then Dustwell,
## then your land. It stops at the first tile it cannot build on (a building, your land) and waits.
func _ai_roads() -> void:
	var cost: Dictionary = Data.BUILDINGS["road"].cost
	if ai["stone"] < Data.AI_ROAD.stone or ai["food"] < Data.AI_ROAD.food:
		return
	var net := road_network(Data.AI)   # kept up to date as they lay and repair, so the highway tiles on the way can be told from the ones out of reach
	for target in _ai_road_targets():
		var laid := 0
		var path := _road_path(bases[Data.AI], target, Data.AI)
		for c in path:
			if laid >= Data.AI_ROAD.tiles or ai["stone"] < cost.stone or ai["food"] < cost.grain:
				break
			var t: Dictionary = tile(c)
			if t["b"] == "old_road" and c != target and ai["stone"] >= Data.HIGHWAY.repair.stone and (t["o"] == Data.AI or (t["o"] == Data.NONE \
					and (borders(c, Data.AI) or neighbors(c).any(func(n): return net.has(n))))):
				t["b"] = "road"   # a stretch of the old highway on the way: they pay to repair it, which ends the ambushes there
				ai["stone"] -= Data.HIGHWAY.repair.stone
				net[c] = true
				_update_paths_at([c])
				laid += 1
				continue
			if t["b"] != "" and Data.BUILDINGS[t["b"]].get("road", false):
				continue   # already road
			if t["t"] == "water" or c == target or t["b"] != "":
				continue   # the river (a ford or bridge carries the road on), the target itself, or a building: walk on past it
			if slopes[idx(c)] == "steep" or not (t["o"] == Data.AI or (t["o"] == Data.NONE and road_reaches(c, Data.AI))):
				break
			t["b"] = "road"
			ai["stone"] -= cost.stone
			ai["food"] -= cost.grain
			net[c] = true
			_update_paths_at([c])
			laid += 1
		if laid > 0:
			return


## A route for laying road from `from` to `to`, in straight lines (four directions, so each tile joins the last) that a road can really follow: it
## never uses a steep incline, water without a ford or a bridge, or land that belongs to somebody else, and it keeps round buildings. `to` is open.
func _road_path(from: Vector2i, to: Vector2i, owner: int) -> Array:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, w, h)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for i in tiles.size():
		var c := Vector2i(i % w, i / w)
		var t: Dictionary = tiles[i]
		var spans: bool = t.get("f", false) or (t["b"] != "" and Data.BUILDINGS[t["b"]].get("bridge", false))
		if (t["t"] == "water" and not spans) or slopes[i] == "steep" or (t["o"] != Data.NONE and t["o"] != owner and not spans):
			grid.set_point_solid(c)
			continue
		var weight := 1.0
		if t["t"] == "rock" or t["t"] == "crater" or t["t"] == "glass":
			weight = 3.0
		elif t["t"] == "trees" or t["t"] == "grove":
			weight = 2.0
		if t["b"] != "" and not spans and not Data.BUILDINGS[t["b"]].get("road", false):
			weight = 25.0
		grid.set_point_weight_scale(c, weight)
	grid.set_point_solid(from, false)
	grid.set_point_solid(to, false)
	return grid.get_id_path(from, to)


## Where the Rust Kings' road is heading: the old highway tile nearest their fort, then Dustwell, then the nearest tile of yours.
func _ai_road_targets() -> Array:
	var fort: Vector2i = bases[Data.AI]
	var out := []
	var best := INF
	var nearest := Vector2i(-1, -1)
	var pieces := _highway_pieces()   # not a fragment out in the wastes
	for i in tiles.size():
		var c := Vector2i(i % w, i / w)
		if tiles[i]["b"] == "old_road" and pieces.has(c) and c.distance_to(fort) < best:
			best = c.distance_to(fort)
			nearest = c
	if nearest.x >= 0:
		out.append(nearest)
	for i in tiles.size():
		if tiles[i]["b"] == "town":
			out.append(Vector2i(i % w, i / w))
			break
	best = INF
	nearest = Vector2i(-1, -1)
	for c in owned(Data.PLAYER):
		if c.distance_to(fort) < best:
			best = c.distance_to(fort)
			nearest = c
	if nearest.x >= 0:
		out.append(nearest)
	return out


func is_ford(c: Vector2i) -> bool:
	return tile(c)["t"] == "water" and tile(c).get("f", false)


## What the ground on tile c is called: "Shallow ford" for a wadeable river tile, otherwise the terrain's name.
func terrain_name(c: Vector2i) -> String:
	return Data.FORD.name if is_ford(c) else Data.TERRAIN[tile(c)["t"]].name


var banks := PackedInt32Array()   # per tile: 0 for water, otherwise which stretch of land it is on with the river as a wall
var _banks_map := -1


func _label_banks() -> void:
	if _banks_map == map_version and banks.size() == tiles.size():
		return
	banks.resize(tiles.size())
	banks.fill(0)
	var next := 0
	for i in tiles.size():
		if banks[i] != 0 or tiles[i]["t"] == "water":
			continue
		next += 1
		banks[i] = next
		var queue := [i]
		var head := 0
		while head < queue.size():
			var c := Vector2i(queue[head] % w, queue[head] / w)
			head += 1
			for n in neighbors(c):
				var k := idx(n)
				if banks[k] == 0 and tiles[k]["t"] != "water":
					banks[k] = next
					queue.append(k)
	_banks_map = map_version


## Why this mover has no way from `from` to `to`: "the river" when they are on different banks (or the target is in the water), "steep
## inclines" for a war rig that is held up on the same bank, or "" for a boat or plane.
func no_way_reason(mover: String, from: Vector2i, to: Vector2i) -> String:
	if mover in ["boat", "plane"]:
		return ""
	_label_banks()
	if banks[idx(from)] != banks[idx(to)] or tile(to)["t"] == "water":
		return "the river"
	return "steep inclines" if mover == "car" else ""


## "No way there (the river)", "No way there (steep inclines)" or just "No way there".
func no_way_text(mover: String, from: Vector2i, to: Vector2i) -> String:
	var why := no_way_reason(mover, from, to)
	return "No way there" + (" (%s)" % why if why != "" else "")


## The fastest route for this mover, or [] if there's no way through.
func route(mover: String, from: Vector2i, to: Vector2i) -> Array:
	return paths[mover].get_id_path(from, to)


## route_days() as one of your parties lives it: a Trailblazer's parties are quicker and Slow marchers' are slower.
func party_route_days(mover: String, path: Array) -> float:
	return route_days(mover, path) * travel_mult()


func route_days(mover: String, path: Array) -> float:
	var days := 0.0
	for i in range(1, path.size()):
		var step := Vector2(path[i] - path[i - 1]).length()
		days += step * move_mult(mover, path[i]) * Data.MOVERS[mover].days
	return days


## 1.0 = arrives fresh, less after a long march, 0 = can't get there at all.
func march_factor(mover: String, from: Vector2i, to: Vector2i) -> float:
	var path := route(mover, from, to)
	if path.is_empty():
		return 0.0
	return clampf(1.0 - route_days(mover, path) / Data.MARCH_FATIGUE_DAYS, 0.6, 1.0)


# ---------------------------------------------------------------- helpers

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func tile(c: Vector2i) -> Dictionary:
	return tiles[c.y * w + c.x]


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func neighbors(c: Vector2i) -> Array:
	var out := []
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if in_bounds(c + d):
			out.append(c + d)
	return out


func borders(c: Vector2i, owner: int) -> bool:
	for n in neighbors(c):
		if tile(n)["o"] == owner:
			return true
	return false


func owned(owner: int) -> Array:
	var out := []
	for i in tiles.size():
		if tiles[i]["o"] == owner:
			out.append(Vector2i(i % w, i / w))
	return out


func count_building(owner: int, b: String) -> int:
	var n := 0
	for t in tiles:
		if t["o"] == owner and t["b"] == b:
			n += 1
	return n


func has(upgrade_id: String) -> bool:
	return upgrade_id in upgrades


func season_name() -> String:
	return "Year %d, %s" % [(season - 1) / 4 + 1, Data.SEASONS[(season - 1) % 4]]


func add_log(text: String) -> void:
	log_lines.append("[%s] %s" % [season_name(), text])
	if log_lines.size() > 80:
		log_lines.pop_front()


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if res.get(k, 0) < cost[k]:
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		res[k] -= cost[k]
	return true


func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		if cost[k] != 0:
			parts.append("%d %s" % [cost[k], k if k != "nuke" or cost[k] == 1 else "nukes"])
	return ", ".join(parts) if parts.size() > 0 else "free"


func pop_cap() -> int:
	return 8 + owned(Data.PLAYER).size() / 3 + (10 if has("basics") else 0)


## Clicking a tile selects it. Clicking one of your scouting parties also picks that party, and it
## stays picked while you click around for somewhere to send it (Esc, or clicking your own land,
## lets go). While a party is picked the map shows its route from where it stands, not from your HQ.
func select(c: Vector2i) -> void:
	selected = c
	if in_bounds(c):
		var here := Units.units_at(c).filter(func(u): return u.owner == Data.PLAYER and u.job == "scout")
		if not here.is_empty():
			if not here.any(func(u): return u.id == selected_scout):
				selected_scout = here[0].id
		elif tile(c)["o"] == Data.PLAYER:
			selected_scout = -1   # scouts can't be sent to your own land, so you're not choosing a destination
	_refresh_previews()
	tile_selected.emit()
	changed.emit()


## Picks a party by id (two parties can stand on one tile, and clicking it picks the first).
func pick_scout(id: int) -> void:
	selected_scout = id
	_refresh_previews()
	changed.emit()


func deselect_scout() -> void:
	if selected_scout == -1:
		return
	selected_scout = -1
	_refresh_previews()
	changed.emit()


## The party moves and eats between seasons, so its route (and how far its food goes) changes.
func _keep_scout_route_fresh() -> void:
	var had_pick := selected_scout != -1
	refresh_scout_route()
	if had_pick and selected_scout == -1:
		_refresh_previews()   # the party is gone: back to routes from your HQ


## The routes the map draws for the selected tile: from your HQ, or from the picked scouting party.
func _refresh_previews() -> void:
	preview = {}
	refresh_scout_route()
	if selected_scout == -1 and in_bounds(selected) and selected != home(Data.PLAYER):
		for mover in Data.TRAVEL_PREVIEW:
			preview[mover] = route(mover, home(Data.PLAYER), selected)


## The picked party's route from where it stands to the selected tile, or on to wherever it is already
## heading when you click its own tile. Per cell, "days" is when it gets there and "ratio" how much of
## its food would be eaten by then (see Units.food_ratios): the map fades the dots from white to
## yellow to red by it.
func refresh_scout_route() -> void:
	scout_route = {}
	var u := Units.unit_by_id(selected_scout)
	if u.is_empty():
		selected_scout = -1
		return
	var path: Array = [u.pos] + u.path
	if in_bounds(selected) and selected != u.pos:
		path = route(u.mover, u.pos, selected)
	if path.size() > 1:
		var days := Units.arrival_days(u.mover, path, Units.party_slowdown(u))
		scout_route ={"mover": u.mover, "path": path, "days": days, "ratio": Units.food_ratios(u, days)}


# ---------------------------------------------------------------- land & buildings

func claim_cost(c: Vector2i) -> Dictionary:
	if tile(c)["o"] == Data.AI:
		return {"gold": 25}
	return {"wood": 3 + owned(Data.PLAYER).size() / 10 + (1 if has_quirk("spendthrift") else 0), "gold": 1}


## Returns "" if the tile can be claimed, otherwise the reason it can't.
func claim_status(c: Vector2i) -> String:
	var t := tile(c)
	if t["o"] == Data.PLAYER:
		return "Already yours"
	if t["b"] == "old_bridge":
		return "The old bridge belongs to nobody"
	if not borders(c, Data.PLAYER):
		return "Must border your land"
	if t["o"] == Data.AI:
		if not has("c5"):
			return "Enemy land (Merchant empire lets you buy it)"
		if ai["relations"] < 0 or t["b"] in ["ai_hq", "ai_wall"]:
			return "They won't sell this tile"
	elif t["o"] != Data.NONE:
		return "Owned by Dustwell"
	if not can_afford(claim_cost(c)):
		return "Need " + cost_text(claim_cost(c))
	return ""


func claim(c: Vector2i) -> void:
	if claim_status(c) != "":
		return
	pay(claim_cost(c))
	note("tiles_claimed")
	if tile(c)["o"] == Data.AI:
		add_log("You bought a tile from the Rust Kings.")
	tile(c)["o"] = Data.PLAYER
	changed.emit()


func highest_tier() -> int:
	var best := 0
	for id in upgrades:
		var u: Dictionary = Data.UPGRADES[id]
		if u.branch in Data.BRANCHES:
			best = maxi(best, u.tier)
	return best


## Returns "" if the building can go on this tile, otherwise the reason it can't.
func build_status(id: String, c: Vector2i) -> String:
	var b: Dictionary = Data.BUILDINGS[id]
	var t := tile(c)
	if not b.get("buildable", true):
		return "Can't be built"
	if t["o"] != Data.PLAYER:
		# a bridge goes out from your land: the free water tile beside it can be built on (and becomes yours); a road goes out over free
		# land from your land or from a road that reaches it, and leaves the land free
		var reaches: bool = t["o"] == Data.NONE and ((b.get("bridge", false) and borders(c, Data.PLAYER)) or (b.get("road", false) and road_reaches(c, Data.PLAYER)))
		if not reaches:
			return "Not your land"
	if t["b"] != "":
		return "Tile already has a building"
	if b.get("road", false) and slopes[idx(c)] == "steep":
		return "Too steep for a road"
	var on: Array = b.get("on", [])
	if on.is_empty() and t["t"] == "water":
		return "Can't build on water"
	if not on.is_empty() and not t["t"] in on:
		return "Wrong terrain"
	if b.get("shore", false) and not neighbors(c).any(func(n): return tile(n)["t"] == "water"):
		return "Must stand on the riverbank"
	if b.has("req") and not has(b.req):
		return "Needs upgrade: " + Data.UPGRADES[b.req].name
	if highest_tier() < b.get("tier", 0):
		return "Needs a tier %d upgrade in any branch" % b.tier
	if not can_afford(b.cost):
		return "Need " + cost_text(b.cost)
	return ""


func build(id: String, c: Vector2i) -> void:
	if build_status(id, c) != "":
		return
	pay(Data.BUILDINGS[id].cost)
	note("buildings_built")
	tile(c)["b"] = id
	refinery_on.erase(idx(c))   # a new refinery starts off
	if Data.BUILDINGS[id].get("bridge", false):
		tile(c)["o"] = Data.PLAYER
		_update_paths_at([c])   # the new way across
	elif Data.BUILDINGS[id].get("road", false):
		_update_paths_at([c])   # the new quick way (free land stays free)
	if id == "outpost":
		for y in range(c.y - 2, c.y + 3):
			for x in range(c.x - 2, c.x + 3):
				var p := Vector2i(x, y)
				if in_bounds(p) and tile(p)["o"] == Data.NONE and tile(p)["b"] != "old_bridge":
					tile(p)["o"] = Data.PLAYER
	add_log("Built a %s.%s" % [Data.BUILDINGS[id].name, " It starts switched off: select it to start it." if id == "refinery" else ""])
	changed.emit()


## Why a tile of the old highway cannot be repaired into a road yet, or "" if it can: it must be free land or yours, joined to your land or to a
## road that reaches it (the highway counts once your road meets it), and the stone must be in the stores.
func repair_status(c: Vector2i) -> String:
	var t := tile(c)
	if t["b"] != "old_road":
		return "Not part of the old highway"
	if t["o"] != Data.NONE and t["o"] != Data.PLAYER:
		return "Not your land"
	if t["o"] != Data.PLAYER and not road_reaches(c, Data.PLAYER):
		return "Not joined to your land or a road of yours"
	if not can_afford(Data.HIGHWAY.repair):
		return "Need " + cost_text(Data.HIGHWAY.repair)
	return ""


## Pay the stone and turn a tile of the old highway into a road: no more ambush rolls there, and it is 0.6 times as long instead of 0.8. A repaired
## tile on free land stays free, like any road there, so everyone can use it.
func repair(c: Vector2i) -> void:
	if repair_status(c) != "":
		return
	pay(Data.HIGHWAY.repair)
	tile(c)["b"] = "road"
	_update_paths_at([c])
	add_log("Repaired a stretch of the Hollow Mile into a road. Raiders can no longer lie in wait on it.")
	changed.emit()


func demolish(c: Vector2i) -> void:
	var t := tile(c)
	if t["o"] == Data.PLAYER and t["b"] != "" and t["b"] != "hq" and poi_kind(c) == "" and Data.BUILDINGS[t["b"]].get("buildable", true):
		var bridge: bool = Data.BUILDINGS[t["b"]].get("bridge", false)
		var way: bool = bridge or Data.BUILDINGS[t["b"]].get("road", false)
		if bridge and not Units.units_at(c).is_empty():
			add_log("The bridge can't come down with a party on it.")
			changed.emit()
			return
		t["b"] = ""
		refinery_on.erase(idx(c))
		if way:
			_update_paths_at([c])   # the way across (or the quick way) is gone
		changed.emit()


# ---------------------------------------------------------------- destroying buildings

## The DC to destroy the building on tile `c`, or 0 if it can't be destroyed (an HQ, the Rust Kings' fort, the
## citadel, Dustwell, a point of interest, or no building at all).
func building_dc(c: Vector2i) -> int:
	var b: String = tile(c)["b"]
	var dc: int = D20Data.BUILDING_DC.get(b, 0)
	if b == "wall" and tile(c)["o"] == Data.PLAYER and has("f2"):
		dc += D20Data.STONE_WALL_DC
	if dc > 0 and tile(c)["o"] == Data.PLAYER:
		if has_quirk("stonemason"):
			dc += 1
		if has_quirk("shaky_buildings"):
			dc = maxi(dc - 1, 1)
	return dc


## Can `c` be attacked now? Your own buildings stop being targets once RAID_LOSS_CAP of them fell this season.
func can_hit(c: Vector2i) -> bool:
	if building_dc(c) <= 0:
		return false
	return tile(c)["o"] != Data.PLAYER or buildings_lost < Data.RAID_LOSS_CAP


## What a raid or a raider band brings to an attack roll: RAID_BONUS for the first row its strength reaches, in
## multiples of the defense it meets, and RAID_PENALTY below the last row.
func raid_modifier(att: float, def: float) -> int:
	if def <= 0.0:
		return D20Data.RAID_BONUS[0][1]
	var ratio := att / def
	for row in D20Data.RAID_BONUS:
		if ratio >= row[0]:
			return row[1]
	return D20Data.RAID_PENALTY


## The DC of a fight between armies (D20Data.RAID_DICE): 21 - round(20 * attack / (attack + defense)), so a d20 of at least
## the DC wins about as often as attack / (attack + defense) always did, to the nearest 5%.
func raid_dc(att: float, def: float) -> int:
	var rules: Dictionary = D20Data.RAID_DICE
	if att <= 0.0:
		return rules.dc_max
	if def <= 0.0:
		return rules.dc_min
	return clampi(21 - roundi(20.0 * att / (att + def)), rules.dc_min, rules.dc_max)


## The chance, in percent, that one d20 wins against `dc` (a natural 20 always wins and a natural 1 never does).
func raid_chance(dc: int) -> int:
	return clampi(21 - dc, 1, 19) * 5


## What an army-fight button says before you commit: the DC and the chance.
func raid_odds_text(att: float, def: float) -> String:
	var dc := raid_dc(att, def)
	return "DC %d, %d%% to win" % [dc, raid_chance(dc)]


## One d20 for a fight between armies, written to the log: {"d20", "dc", "won", "crit"} where crit is "success" for a natural
## 20, "fail" for a natural 1 and "" otherwise. `who` heads the log line ("Your attack on the Ash Walkers").
func raid_roll(att: float, def: float, who: String) -> Dictionary:
	var dc := raid_dc(att, def)
	var d20: int = Units.dice.d20()
	var crit := "success" if d20 == D20Data.NAT_CRIT else ("fail" if d20 == D20Data.NAT_FAIL else "")
	var won := d20 != D20Data.NAT_FAIL and d20 >= dc
	var verdict := "won"
	if crit == "success":
		verdict = "natural 20, a critical win"
	elif crit == "fail":
		verdict = "natural 1, a critical loss"
	elif not won:
		verdict = "lost"
	add_log("%s: d20 %d vs DC %d (%d%% to win), %s." % [who, d20, dc, raid_chance(dc), verdict])
	return {"d20": d20, "dc": dc, "won": won, "crit": crit}


## The buildings of `owner` that can be destroyed, nearest to `from` first.
func buildings_of(owner: int, from: Vector2i) -> Array:
	var out := []
	for c in owned(owner):
		if building_dc(c) > 0:
			out.append(c)
	out.sort_custom(func(a, b):
		var da := Vector2(a - from).length()
		var db := Vector2(b - from).length()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return out


## One attack roll at the building on `c` by a party that is only a number (a raid, a raider band): d20 plus `mod`
## against the building's DC, written to the log with the numbers. A hit destroys it. False if it can't be attacked.
func attack_building(c: Vector2i, mod: int, who: String) -> bool:
	if not can_hit(c):
		return false
	var dc := building_dc(c)
	var total_mod := D20.clamp_mod(mod)
	var d20: int = Units.dice.d20()
	var tier := D20.tier_from_roll(d20, total_mod, dc)
	var hit := tier == D20Data.SUCCESS or tier == D20Data.CRITICAL_SUCCESS
	add_log("%s struck the %s at %d,%d: d20 %d %+d vs DC %d, %s." % [who, Data.BUILDINGS[tile(c)["b"]].name.to_lower(), c.x, c.y,
		d20, total_mod, dc, "destroyed" if hit else "it held"])
	if hit:
		destroy_building(c)
	return hit


## Removes the building on `c` (the tile stays with its owner). Losing one of yours counts toward the season's cap;
## a Raider wall takes its walls with it and costs you relations with the Rust Kings.
func destroy_building(c: Vector2i) -> void:
	if building_dc(c) <= 0:
		return
	var t := tile(c)
	var b: String = t["b"]
	t["b"] = ""
	refinery_on.erase(idx(c))
	if t["o"] == Data.PLAYER:
		buildings_lost += 1
		note("buildings_lost")
	elif t["o"] == Data.AI:
		note("enemy_buildings_destroyed")
		ai["relations"] = maxi(ai["relations"] - Data.RAID_RELATIONS, -100)
		if b == "ai_wall":
			ai["walls"] = maxi(ai["walls"] - Data.WALLS_PER_TILE, 0)
			_sync_ai_walls()
		_after_ai_loss(b)
	changed.emit()


## A raider band that has beaten your guards at the edge of your land also rolls at the building nearest it.
func raider_strike(from: Vector2i, att: float, def: float) -> void:
	for c in buildings_of(Data.PLAYER, from).slice(0, 1):
		attack_building(c, raid_modifier(att, def), "A raider band")


## A winning Rust Kings raid also rolls at your buildings nearest their fort: once, once more at double your defense,
## once more if they have planes (and no Flak towers), at most AI_RAID_ROLLS, each at a different building. Not before
## season AI_BUILDING_ATTACKS_FROM.
func _ai_strikes(att: float, def: float) -> void:
	if season < Data.AI_BUILDING_ATTACKS_FROM:
		return
	var rolls := 1
	if att >= def * 2.0:
		rolls += 1
	if ai["plane"] > 0 and not has("fv4"):
		rolls += 1
	var mod := raid_modifier(att, def)
	for c in buildings_of(Data.PLAYER, home(Data.AI)).slice(0, mini(rolls, Data.AI_RAID_ROLLS)):
		attack_building(c, mod, "The Rust Kings")


## A Rust Kings scout that has just ended its move at `at`: if one of your buildings is within AI_SCOUT_REACH tiles of it
## (and more than AI_SCOUT_HOME_GAP tiles from your HQ) there is an AI_SCOUT_STRIKE chance of one attack roll at it.
func _ai_scout_strike(at: Vector2i) -> void:
	if season < Data.AI_BUILDING_ATTACKS_FROM:
		return
	var hq := home(Data.PLAYER)
	var near := buildings_of(Data.PLAYER, at).filter(func(c):
		return Vector2(c - at).length() <= Data.AI_SCOUT_REACH and Vector2(c - hq).length() > Data.AI_SCOUT_HOME_GAP)
	if near.is_empty() or randf() >= Data.AI_SCOUT_STRIKE:
		return
	attack_building(near[0], 0, "A Rust Kings scout")


## A won raid on the Rust Kings also rolls at their walls nearest your HQ: once, twice if you had double their defense, and
## `extra` more after a natural 20.
func _raid_strikes(att: float, def: float, extra := 0) -> void:
	var rolls := (2 if att >= def * 2.0 else 1) + extra
	var mod := raid_modifier(att, def)
	for c in buildings_of(Data.AI, home(Data.PLAYER)).slice(0, rolls):
		attack_building(c, mod, "Your raid")


## The Rust Kings' walls are a number, and one Raider wall tile stands for WALLS_PER_TILE of them. This makes the tiles
## match the number: any missing ones go on their land nearest your HQ (the side facing you), any extra ones go.
func _sync_ai_walls() -> void:
	if tiles.is_empty() or ai.is_empty():
		return
	var want := ceili(float(ai["walls"]) / Data.WALLS_PER_TILE)
	var from := home(Data.PLAYER)
	var standing := []
	var free := []
	for c in owned(Data.AI):
		if tile(c)["b"] == "ai_wall":
			standing.append(c)
		elif tile(c)["b"] == "" and tile(c)["t"] != "water":
			free.append(c)
	var nearer := func(a: Vector2i, b: Vector2i) -> bool:
		var da := Vector2(a - from).length()
		var db := Vector2(b - from).length()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x)))
	if standing.size() > want:
		standing.sort_custom(func(a, b): return nearer.call(b, a))   # the ones furthest from you go first
		for c in standing.slice(0, standing.size() - want):
			tile(c)["b"] = ""
	elif standing.size() < want:
		free.sort_custom(nearer)
		for c in free.slice(0, want - standing.size()):
			tile(c)["b"] = "ai_wall"


# ---------------------------------------------------------------- nukes

## The tiles a blast at `c` wipes: the square within Data.NUKE.reach of it, as far as the map goes.
func blast_square(c: Vector2i) -> Array:
	var out := []
	var reach: int = Data.NUKE.reach
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var p := c + Vector2i(dx, dy)
			if in_bounds(p):
				out.append(p)
	return out


## Does a blast bring this kind of building down? Not an HQ, the Raider fort, Dustwell, the old bridge or a point of interest.
func blast_takes_building(b: String) -> bool:
	return b != "" and not b in Data.NUKE.spares and not Data.BUILDINGS[b].has("poi")


## A nuke goes off at `center`. The square round it becomes scorched ash (water and glowing craters stay as they are) and reads Data.NUKE.rad R/h at least,
## the buildings in it fall (but not Data.NUKE.spares or a point of interest), every party and wild animal in it dies and every camp is wiped out (Units.blast_kills).
## `source` is "crater" (a search went wrong: the crater is spent) or "bomber" (your strike: each Rust Kings building that falls costs relations, as in a raid). `spare`
## holds ids of units that live. `day` is when in the season's walk it went off (a bomber's drop), so the replay plays it then; `hold` waits for the die to land
## (release_blasts). Returns what it did.
func detonate(center: Vector2i, source: String, spare := [], day := -1.0, hold := false) -> Dictionary:
	var cells := blast_square(center)
	var report := {"cells": cells, "buildings": 0, "theirs": 0, "kills": {}}
	var walls_gone := false
	var airfield_gone := false
	for c in cells:
		var t := tile(c)
		t["rad"] = maxi(int(t["rad"]), int(Data.NUKE.rad))
		if measured.size() == w * h:
			measured[idx(c)] = 1   # everyone saw it: the reading is known
		if t["t"] != "water" and t["t"] != "crater":
			t["t"] = "ash"
			if poi_kind(c) == "":
				t["r"] = ""
		if blast_takes_building(t["b"]):
			var b: String = t["b"]
			t["b"] = ""
			refinery_on.erase(idx(c))
			report.buildings += 1
			if t["o"] == Data.PLAYER:
				note("buildings_lost")
			elif t["o"] == Data.AI:
				report.theirs += 1
				note("enemy_buildings_destroyed")
				if source == "bomber":
					ai["relations"] = maxi(ai["relations"] - Data.RAID_RELATIONS, -100)
				if b == "ai_wall":
					ai["walls"] = maxi(ai["walls"] - Data.WALLS_PER_TILE, 0)
					walls_gone = true
				elif b == "ai_airfield":
					airfield_gone = true
	if source == "crater":
		tile(center)["r"] = "picked"   # its nuke is gone
	if walls_gone:
		_sync_ai_walls()
	if airfield_gone:
		_after_ai_loss("ai_airfield")
	_update_paths_at(cells)   # the ground is quicker or slower now, and a bridge or a road may be gone
	map_version += 1          # the map redraws its ground
	report["kills"] = Units.blast_kills(cells, spare, day)
	note("blasts")
	var bits := []
	if report.buildings > 0:
		bits.append("%d building%s fell" % [report.buildings, "" if report.buildings == 1 else "s"])
	var k: Dictionary = report.kills
	if k.parties > 0:
		bits.append("%d part%s died" % [k.parties, "y" if k.parties == 1 else "ies"])
	if k.animals > 0:
		bits.append("%d animal%s died" % [k.animals, "" if k.animals == 1 else "s"])
	if k.camps > 0:
		bits.append("%d camp%s wiped out" % [k.camps, "" if k.camps == 1 else "s"])
	add_log("A NUKE WENT OFF %s. The ground round it is scorched ash, %d R/h.%s" % [
		{"crater": "under your scavengers at %d,%d", "bomber": "at %d,%d, dropped by your bomber", "rust_kings": "at %d,%d, dropped by the Rust Kings' bomber"}[source] % [center.x, center.y],
		int(Data.NUKE.rad), " " + ", ".join(bits) + "." if not bits.is_empty() else ""])
	if day >= 0.0 and Units.is_recording():
		Units.note_blast(center, day)
	elif hold:
		held_blasts.append(center)
	else:
		blasted.emit(center)
	changed.emit()
	return report


## The explosions that were waiting for the die to land play now.
func release_blasts() -> void:
	var list := held_blasts
	held_blasts = []
	for c in list:
		blasted.emit(c)


## The ash cools a little every season, down to Data.NUKE.floor.
func _cool_ash() -> void:
	for t in tiles:
		if t["t"] == "ash" and int(t["rad"]) > int(Data.NUKE.floor):
			t["rad"] = maxi(int(t["rad"]) - int(Data.NUKE.cool), int(Data.NUKE.floor))


## What a blast at `c` would take, as far as you know it: {"yours": building names, "theirs": building names, "parties": text, "camps": names}.
func blast_report(c: Vector2i) -> Dictionary:
	var out := {"yours": [], "theirs": [], "parties": [], "camps": []}
	var mine: Array = memory[Data.PLAYER] if memory.has(Data.PLAYER) else []
	for p in blast_square(c):
		var known = mine[idx(p)] if mine.size() == w * h else null
		if known != null and blast_takes_building(known[1]):
			(out.yours if known[0] == Data.PLAYER else out.theirs).append(Data.BUILDINGS[known[1]].name.to_lower())
		for u in Units.units_at(p):
			if u.owner == Data.PLAYER:
				out.parties.append("your %s at %d,%d" % [Data.EXPEDITIONS[u.job].name.to_lower(), p.x, p.y])
			elif in_sight(Data.PLAYER, p):
				out.parties.append("a raider band at %d,%d" % [p.x, p.y])
		var tribe := Units.tribe_at(p)
		if not tribe.is_empty() and knows_tile(Data.PLAYER, p):
			out.camps.append(tribe.name)
	return out


func set_strike_preview(c: Vector2i) -> void:
	if strike_preview != c:
		strike_preview = c
		strike_preview_changed.emit()


## How many unfired nukes a missile silo still holds for a later party to fetch (an earlier one found more than it could carry): its tiles read "stock3".
func silo_stock(anchor: Vector2i) -> int:
	var r: String = tile(anchor)["r"]
	return int(r.substr(5)) if r.begins_with("stock") else 0


## Leaves `n` nukes in the silo (none: it is picked clean).
func set_silo_stock(anchor: Vector2i, n: int) -> void:
	for p in poi_footprint(anchor):
		tile(p)["r"] = "stock%d" % n if n > 0 else "picked"


# ---------------------------------------------------------------- upgrade tree

## Branches with any tier 3+ node: those count as "committed".
func committed_branches() -> Array:
	var out := []
	for id in upgrades:
		var u: Dictionary = Data.UPGRADES[id]
		if u.branch in Data.BRANCHES and u.tier >= 3 and not u.branch in out:
			out.append(u.branch)
	return out


func upgrade_cost(id: String) -> Dictionary:
	var u: Dictionary = Data.UPGRADES[id]
	var mult := 1.0
	if u.branch == Data.LEADERS[leader].branch:
		mult *= 0.75
	# Divided focus rule: each committed branch beyond the first adds +30% to tier 4-5
	if u.tier >= 4:
		var c := committed_branches()
		if not u.branch in c:
			c.append(u.branch)
		mult *= 1.0 + 0.3 * (c.size() - 1)
	return _scaled(u.cost, mult)


func _scaled(cost: Dictionary, mult: float) -> Dictionary:
	var out := {}
	for k in cost:
		out[k] = int(ceil(cost[k] * mult))
	return out


func upgrade_status(id: String) -> String:
	var u: Dictionary = Data.UPGRADES[id]
	if has(id):
		return "Owned"
	for n in u.get("needs", []):
		if not has(n):
			return "Needs " + Data.UPGRADES[n].name
	for b in u.get("both", []):
		if not b in committed_branches():
			return "Needs tier 3 in %s" % b
	if not can_afford(upgrade_cost(id)):
		return "Need " + cost_text(upgrade_cost(id))
	return ""


func buy_upgrade(id: String) -> void:
	if upgrade_status(id) != "":
		return
	pay(upgrade_cost(id))
	note("upgrades")
	upgrades.append(id)
	add_log("Researched %s." % Data.UPGRADES[id].name)
	changed.emit()


# ---------------------------------------------------------------- military

func train_troop_cost() -> Dictionary:
	return {"metal": 2 if has_quirk("drill_sergeant") else 3, "meat": 2}


func train_troop() -> void:
	if pop > 2 and pay(train_troop_cost()):
		pop -= 1
		troops += 1
		note("troops_trained")
		changed.emit()


func disband_troop() -> void:
	if troops > 0:
		troops -= 1
		pop += 1
		changed.emit()


## Raid strength once your forces reach `target`. Troops march on foot, horses take their own
## route, and war rigs that can't find a way around steep inclines stay home. Boats and planes
## don't care about slopes. With no target, it's your strength at home.
func player_attack(target := Vector2i(-1, -1)) -> float:
	var foot: float = troops * Data.LEADERS[leader].attack
	if has("w1"):
		foot *= 1.25
	if has("w3"):
		foot *= 1.5
	# Vehicles away on expeditions can't fight
	var horse: float = Units.free_vehicles("horse") * vehicle_attack("horse")
	var car: float = Units.free_vehicles("car") * vehicle_attack("car")
	if in_bounds(target):
		foot *= march_factor("foot", home(Data.PLAYER), target)
		horse *= march_factor("horse", home(Data.PLAYER), target)
		car *= march_factor("car", home(Data.PLAYER), target)
	return foot + horse + car + Units.free_vehicles("boat") * vehicle_attack("boat") + Units.free_vehicles("plane") * vehicle_attack("plane")


## How much of the Rust Kings' walls still count when you attack.
func wall_breach() -> float:
	if has("wv4") and vehicles["plane"] > 0:
		return 0.0
	var left := 0.5 if has("w4") or vehicles["plane"] > 0 else 1.0
	return left * (0.8 if has_quirk("siege_breaker") else 1.0)


func player_wall_defense() -> float:
	var wall_each := 2 + (2 if has("f2") else 0)
	var d := count_building(Data.PLAYER, "wall") * wall_each
	for b in ["tower", "keep", "citadel", "drug_factory"]:
		d += count_building(Data.PLAYER, b) * Data.BUILDINGS[b].defense
	if has("b_wf"):
		d += count_building(Data.PLAYER, "outpost") * wall_each
	return d * (0.9 if has_quirk("thin_walls") else 1.0)


func player_troop_defense() -> float:
	var d: float = 2 + troops * 0.75 * Data.LEADERS[leader].defense
	if has("f3"):
		d *= 1.1
	return d


## Rust Kings raid strength once they reach your HQ. Enemy vehicles add to it unless your
## fortification counters stop them, and their war rigs need a route around steep inclines too.
func ai_attack() -> float:
	var from := home(Data.AI)
	var to := home(Data.PLAYER)
	var land: float = ai["horse"] * Data.VEHICLES.horse.attack * march_factor("horse", from, to) \
		+ ai["car"] * Data.VEHICLES.car.attack * march_factor("car", from, to)
	if has("fv1"):
		land *= 0.5
	var a: float = ai["troops"] * 1.2 * march_factor("foot", from, to) + land
	if not has("fv2"):
		a += ai["boat"] * Data.VEHICLES.boat.attack
	if not has("fv4"):
		a += ai["plane"] * Data.VEHICLES.plane.attack
	return a


func ai_defense(wall_mult: float) -> float:
	var vehicle_def: float = (ai["horse"] * Data.VEHICLES.horse.attack + ai["car"] * Data.VEHICLES.car.attack) * 0.5
	return ai["walls"] * 2 * wall_mult + 2 + ai["troops"] * 0.75 + vehicle_def


## Move up to `count` tiles from loser to winner, picking tiles on the shared border.
func _take_land(from: int, to: int, count: int, keep_buildings: bool) -> int:
	var taken := 0
	for c in owned(from):
		if taken >= count:
			break
		var t := tile(c)
		if t["b"] in ["hq", "ai_hq", "town", "citadel"] or not borders(c, to):
			continue
		t["o"] = to
		if t["b"] == "ai_wall":
			ai["walls"] = maxi(ai["walls"] - Data.WALLS_PER_TILE, 0)   # a Raider wall that changes hands takes its walls with it
			t["b"] = "wall" if keep_buildings else ""
		elif not keep_buildings:
			t["b"] = ""
		taken += 1
	return taken


func raid_ai() -> void:
	if troops <= 0 or raided_this_season or not knows(Data.PLAYER, Data.AI) or not ending.is_empty():
		return
	raided_this_season = true
	_march_to(home(Data.AI))
	var att := player_attack(home(Data.AI))
	var def := ai_defense(wall_breach())
	if Units.free_vehicles("car") > 0 and route("car", home(Data.PLAYER), home(Data.AI)).is_empty():
		add_log("Your war rigs couldn't find a way around the steep inclines and stayed home.")
	ai["relations"] = maxi(ai["relations"] - 30, -100)
	ai["truce"] = 0
	var roll := raid_roll(att, def, "Your raid on the Rust Kings")
	var rules: Dictionary = D20Data.RAID_DICE.fort
	if roll.won:
		var loot := {}
		for k in ["wood", "stone", "metal", "gold"]:
			loot[k] = int(ai[k] * 0.25)
			ai[k] -= loot[k]
			res[k] += loot[k]
		var caught := 1 + randi() % 3 + (2 if has("w2") else 0)
		if roll.crit == "success":
			caught += rules.crit_prisoners
		prisoners += caught
		note("prisoners_taken", caught)
		note("raids_won")
		ai["troops"] -= int(ceil(ai["troops"] * 0.3))
		troops -= int(troops * 0.15)
		var land := _take_land(Data.AI, Data.PLAYER, 3 if has("w5") else 1, has("w5"))
		add_log("RAID WON! Looted %s, took %d prisoners and %d tiles." % [cost_text(loot), caught, land])
		_raid_strikes(att, def, rules.crit_strikes if roll.crit == "success" else 0)
		if att >= def * Data.ENDINGS.decisive_win:
			add_log("Your attack was overwhelming: the Rust Kings' fort has fallen.")
			_end("raiders_defeated", "stormed")
	else:
		var lost := int(ceil(troops * (rules.crit_troops_lost if roll.crit == "fail" else rules.troops_lost)))
		troops -= lost
		ai["troops"] -= int(ai["troops"] * 0.1)
		note("raids_lost")
		add_log("Raid failed. %d troops lost in the dust." % lost)
	check_ending()
	changed.emit()


func _ai_raid() -> void:
	var att := ai_attack()
	if ai["car"] > 0 and route("car", home(Data.AI), home(Data.PLAYER)).is_empty():
		add_log("The Rust Kings' war rigs couldn't get past the steep inclines. Only riders and foot soldiers came.")
	var walls := player_wall_defense()
	if ai["plane"] > 0 and not has("fv4"):
		walls *= 0.5   # enemy bombers
	var def := walls + player_troop_defense()
	var roll := raid_roll(att, def, "The Rust Kings' raid on your colony")
	var rules: Dictionary = D20Data.RAID_DICE.their_raid
	if roll.won:
		var loot := {}
		for k in ["wood", "stone", "metal", "gold", "grain", "fuel"]:
			loot[k] = int(res[k] * (rules.crit_loot if roll.crit == "success" else rules.loot))
			res[k] -= loot[k]
		troops -= int(ceil(troops * 0.3))
		pop = maxi(pop - 1, 1)
		ai["troops"] -= int(ai["troops"] * 0.2)
		var land := 0
		if count_building(Data.PLAYER, "citadel") > 0:
			pass
		elif has("f4") and att < def * 2:
			pass
		else:
			land = _take_land(Data.PLAYER, Data.AI, 1, false)
		add_log("The Rust Kings RAIDED you! They took %s and %d tiles." % [cost_text(loot), land])
		note("raids_suffered")
		_ai_strikes(att, def)
		if att >= def * Data.ENDINGS.decisive_loss and count_building(Data.PLAYER, "citadel") == 0:
			add_log("Their attack was overwhelming: the colony is overrun.")
			_end("defeat", "overrun")
	else:
		ai["troops"] -= int(ceil(ai["troops"] * (rules.crit_their_troops_lost if roll.crit == "fail" else rules.their_troops_lost)))
		troops -= int(troops * 0.1)
		var caught: int = rules.crit_caught if roll.crit == "fail" else rules.caught
		prisoners += caught
		note("prisoners_taken", caught)
		note("raids_beaten_back")
		add_log("Rust Kings raid beaten back! You captured %s." % ("a raider" if caught == 1 else "%d raiders" % caught))
	# Either way, you can follow their tracks home
	if not knows(Data.PLAYER, Data.AI):
		reveal(Data.PLAYER, home(Data.AI), 3)
		add_log("You followed the raiders' tracks back to their fort in the east.")


# ---------------------------------------------------------------- trade & diplomacy

## What a trader camp asks for its warhead: Data.TRADERS.warhead_price gold, and a Trader leader gets it for the discount.
func warhead_price() -> int:
	var price: int = Data.TRADERS.warhead_price
	if leader == "trader":
		price = int(ceil(price * float(Data.TRADERS.trader_discount)))
	return price


func caravan_slots() -> int:
	var water_route := 1 if has("cv4") and count_building(Data.PLAYER, "port") > 0 else 0
	return Data.LEADERS[leader].caravans + (1 if has("c1") else 0) + count_building(Data.PLAYER, "market") + water_route


func can_trade() -> bool:
	return ai["relations"] > -30 and knows(Data.PLAYER, Data.AI)


## The gold selling a lot of `r` pays: the market's price, a Haggler's 25% more or a Poor haggler's 15% less.
func sell_gold(r: String) -> int:
	var gold: float = Data.MARKET[r][1]
	if has_quirk("haggler"):
		gold *= 1.25
	elif has_quirk("poor_haggler"):
		gold *= 0.85
	return maxi(roundi(gold), 1)


## What buying a lot of `r` costs: twice the selling price, less 20% for a Haggler.
func buy_price(r: String) -> int:
	var price: float = Data.MARKET[r][1] * 2
	if has_quirk("haggler"):
		price *= 0.8
	return maxi(roundi(price), 1)


func sell(r: String) -> void:
	var amount: int = Data.MARKET[r][0]
	if can_trade() and res[r] >= amount:
		res[r] -= amount
		res["gold"] += sell_gold(r)
		ai["relations"] = mini(ai["relations"] + 1, 100)
		changed.emit()


func buy(r: String) -> void:
	var price := buy_price(r)
	if can_trade() and res["gold"] >= price:
		res["gold"] -= price
		res[r] += Data.MARKET[r][0]
		ai["relations"] = mini(ai["relations"] + 1, 100)
		changed.emit()


## Each Drug Factory turns one raw frog hide from the stores into HIDE_TO_SALT Salt, for as long as there are hides.
func _drug_factories() -> void:
	var hides := 0
	for c in owned(Data.PLAYER):
		if tile(c)["b"] == "drug_factory" and int(items.get("hide", 0)) > 0:
			items["hide"] = int(items["hide"]) - 1
			items["salt"] = int(items.get("salt", 0)) + Data.HIDE_TO_SALT
			hides += 1
	if hides > 0:
		note("salt_made", hides * Data.HIDE_TO_SALT)
		add_log("Drug Factory: %d frog %s processed into %d Salt (%d hides left)." % [hides, "hide" if hides == 1 else "hides", hides * Data.HIDE_TO_SALT, items["hide"]])


## The Rust Kings' market sometimes has Salt for sale.
func _restock_salt() -> void:
	if int(ai.get("salt_stock", 0)) <= 0 and randf() < Data.SALT_STOCK_CHANCE:
		ai["salt_stock"] = randi_range(Data.SALT_STOCK_DOSES[0], Data.SALT_STOCK_DOSES[1])


func salt_for_sale() -> int:
	return int(ai.get("salt_stock", 0))


## What a dose of Salt sells for (a Haggler's 25% more, a Poor haggler's 15% less) and costs to buy (twice that, less 20% for a Haggler).
func salt_sell_gold() -> int:
	var gold := float(Data.SALT_PRICE)
	if has_quirk("haggler"):
		gold *= 1.25
	elif has_quirk("poor_haggler"):
		gold *= 0.85
	return maxi(roundi(gold), 1)


func salt_buy_price() -> int:
	var price := float(Data.SALT_PRICE) * 2.0
	if has_quirk("haggler"):
		price *= 0.8
	return maxi(roundi(price), 1)


func sell_salt() -> void:
	if can_trade() and int(items.get("salt", 0)) >= 1:
		items["salt"] = int(items["salt"]) - 1
		res["gold"] += salt_sell_gold()
		ai["relations"] = mini(ai["relations"] + 1, 100)
		changed.emit()


func buy_salt() -> void:
	var price := salt_buy_price()
	if can_trade() and salt_for_sale() > 0 and res["gold"] >= price:
		res["gold"] -= price
		items["salt"] = int(items.get("salt", 0)) + 1
		ai["salt_stock"] = salt_for_sale() - 1
		ai["relations"] = mini(ai["relations"] + 1, 100)
		changed.emit()


func bribe() -> void:
	if has("c4") and pay({"gold": 20}):
		ai["truce"] = 3
		ai["raid_planned"] = false
		ai["relations"] = mini(ai["relations"] + 30, 100)
		add_log("The Rust Kings take your gold. No raids for 3 seasons.")
		changed.emit()


func ransom_price() -> int:
	return (8 if has("b_wc") else 3) + (1 if has_quirk("ransom_broker") else 0)


func ransom_prisoners() -> void:
	if prisoners <= 0 or not knows(Data.PLAYER, Data.AI):
		return
	res["gold"] += prisoners * ransom_price()
	ai["relations"] = mini(ai["relations"] + 5, 100)
	add_log("Ransomed %d prisoners for %d gold." % [prisoners, prisoners * ransom_price()])
	prisoners = 0
	changed.emit()


func befriend_cost() -> Dictionary:
	return {"grain": 5, "gold": 3} if has_quirk("silver_tongue") else {"grain": 10, "gold": 5}


## Gold a trade run brings home: a Caravan master's runs bring 25% more.
func trade_gold(gold: int) -> int:
	return roundi(gold * 1.25) if has_quirk("caravan_master") else gold


func befriend_town() -> void:
	if town["status"] != "neutral" or not knows(Data.PLAYER, Data.TOWN) or not pay(befriend_cost()):
		return
	town["relations"] += 20
	if town["relations"] >= 60:
		town["status"] = "ally"
		add_log("Dustwell is now your ally! They will send tribute each season.")
	else:
		add_log("Dustwell appreciates your gifts. (Relations %d/60)" % town["relations"])
	changed.emit()


const TOWN_DEFENSE := 8.0   # what Dustwell's militia count for against your attack


func conquer_town() -> void:
	if town["status"] != "neutral" or troops <= 0 or raided_this_season or not knows(Data.PLAYER, Data.TOWN):
		return
	raided_this_season = true
	_march_to(home(Data.TOWN))
	var att := player_attack(home(Data.TOWN))
	var def := TOWN_DEFENSE
	var roll := raid_roll(att, def, "Your attack on Dustwell")
	var rules: Dictionary = D20Data.RAID_DICE.town
	if roll.won:
		for c in owned(Data.TOWN):
			tile(c)["o"] = Data.PLAYER
		var caught: int = rules.crit_prisoners if roll.crit == "success" else rules.prisoners
		prisoners += caught
		note("prisoners_taken", caught)
		town["status"] = "conquered"
		ai["relations"] = maxi(ai["relations"] - 15, -100)
		add_log("You took Dustwell by force. Its land and %d prisoners are yours. Your name darkens." % caught)
	else:
		var lost := int(ceil(troops * (rules.crit_troops_lost if roll.crit == "fail" else rules.troops_lost)))
		troops -= lost
		town["relations"] -= 30
		add_log("Dustwell's militia held. You lost %d troops." % lost)
	changed.emit()


func ally_count() -> int:
	return (1 if town["status"] == "ally" else 0) + (1 if ai["relations"] >= 50 else 0)


# ---------------------------------------------------------------- vehicles

func vehicle_status(v: String) -> String:
	var d: Dictionary = Data.VEHICLES[v]
	if count_building(Data.PLAYER, d.building) == 0:
		return "Needs a " + Data.BUILDINGS[d.building].name
	if d.has("req") and not has(d.req):
		return "Needs " + Data.UPGRADES[d.req].name
	if highest_tier() < d.tier:
		return "Needs a tier %d upgrade" % d.tier
	if d.has("max") and vehicles[v] >= d.max:
		return "Fleet limit reached"
	if not can_afford(vehicle_cost(v)):
		return "Need " + cost_text(vehicle_cost(v))
	return ""


func build_vehicle(v: String) -> void:
	if vehicle_status(v) == "" and pay(vehicle_cost(v)):
		vehicles[v] += 1
		note("vehicles_built")
		changed.emit()


# The vehicle upgrades in each leader branch change these four numbers.

func vehicle_cost(v: String) -> Dictionary:
	var mult := 1.0
	if v == "car" and has("wv2"):
		mult = 0.75
	if v == "boat" and has("cv4"):
		mult = 0.75
	if has_quirk("mechanic"):
		mult *= 0.8
	return _scaled(Data.VEHICLES[v].cost, mult)


func vehicle_upkeep(v: String) -> Dictionary:
	if v == "boat" and has("fv3"):
		return {}
	return Data.VEHICLES[v].upkeep


func vehicle_attack(v: String) -> int:
	var a: int = Data.VEHICLES[v].attack
	if v == "horse" and has("wv1"):
		a += 1
	if v == "car" and has("wv2"):
		a += 1
	if v == "boat" and has("wv3"):
		a += 2
	if v == "plane" and has("wv4"):
		a += 2
	return a


func vehicle_trade(v: String) -> int:
	var t: int = Data.VEHICLES[v].trade
	if v == "horse" and has("cv1"):
		t += 2
	return t


# ---------------------------------------------------------------- fog of war

func _reset_fog() -> void:
	contacts = {}
	hollow_found = false
	for viewer in Data.FOG_VIEWERS:
		var m := []
		m.resize(w * h)   # every entry starts as null: never seen
		memory[viewer] = m
	update_fog()


## Recompute what every colony can see right now, and remember it.
func update_fog() -> void:
	if tiles.is_empty() or memory.is_empty():
		return
	for viewer in Data.FOG_VIEWERS:
		var seen := PackedByteArray()
		seen.resize(w * h)
		var planes: int = vehicles["plane"] if viewer == Data.PLAYER else ai["plane"]
		var eyes := []   # [cell, sight radius]
		for c in owned(viewer):
			var b: String = tile(c)["b"]
			var r: int = Data.BUILDINGS[b].get("sight", Data.BASE_SIGHT) if b != "" else Data.BASE_SIGHT
			if b in ["hq", "ai_hq"]:
				r += planes * 4
			eyes.append([c, r])
		for u in Units.units:
			if u.owner == viewer:
				eyes.append([u.pos, Units.sight_of(u)])
		for e in eyes:
			for p in _circle(e[0], e[1]):
				var i := idx(p)
				if seen[i] == 0:
					seen[i] = 1
					_remember(viewer, i)
		sight[viewer] = seen
	Units.check_discoveries()


func _circle(c: Vector2i, r: int) -> Array:
	var out := []
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) <= r * r + r:
				out.append(p)
	return out


## Mark an area as explored (remembered) without it staying in sight. Returns the tiles this explored for the first time.
func reveal(viewer: int, c: Vector2i, r: int) -> Array:
	var fresh := []
	var mem: Array = memory[viewer]
	for p in _circle(c, r):
		var i := idx(p)
		if mem[i] == null:
			fresh.append(p)
		_remember(viewer, i)
	return fresh


## Store what a tile looks like now, and note first contact with whoever owns it.
func _remember(viewer: int, i: int) -> void:
	var t: Dictionary = tiles[i]
	memory[viewer][i] = [t["o"], t["b"]]
	var other: int = t["o"]
	if other != Data.NONE and other != viewer and not knows(viewer, other):
		contacts["%d:%d" % [viewer, other]] = true
		_contact_log(viewer, other)


func knows_tile(viewer: int, c: Vector2i) -> bool:
	return memory[viewer][idx(c)] != null


var _hollow_cells := []
var _hollow_map := -1


## Every tile of the old highway and of the old bridge it runs over, worked out once for each map.
func _hollow_tiles() -> Array:
	if _hollow_map != map_version:
		_hollow_cells = []
		for i in tiles.size():
			if tiles[i]["b"] in ["old_road", "old_bridge"]:
				_hollow_cells.append(Vector2i(i % w, i / w))
		_hollow_map = map_version
	return _hollow_cells


func _hollow_known() -> bool:
	return _hollow_tiles().any(func(c): return knows_tile(Data.PLAYER, c))


## The first tile of the old highway (or its bridge) your colony sees finds the Hollow Mile: once a game, with a log line and a signal for the picture.
func check_hollow_mile() -> void:
	if hollow_found:
		return
	for c in _hollow_tiles():
		if knows_tile(Data.PLAYER, c):
			hollow_found = true
			add_log("Your scouts found the Hollow Mile at %d,%d: the old pre-war highway. It runs through the cities, and raiders lie in wait on it." % [c.x, c.y])
			hollow_mile_found.emit(c, _finders_heat() >= Data.HOLLOW_MILE.rad_high)
			return


## The most radiation (R/h on the tile it stands on, after the shielding of how it travels) that any party of yours with a tile of the old highway in sight
## is taking right now: the party that found the Hollow Mile. 0 if none of them sees it (a building's sight found it, or a flight).
func _finders_heat() -> float:
	var hottest := 0.0
	for u in Units.units:
		if u.owner != Data.PLAYER:
			continue
		var r: int = Units.sight_of(u)
		for c in _hollow_tiles():
			var d: Vector2i = c - u.pos
			if d.x * d.x + d.y * d.y <= r * r + r:
				hottest = maxf(hottest, radiation(u.pos) * Data.MOVERS[u.mover].shield)
				break
	return hottest


func in_sight(viewer: int, c: Vector2i) -> bool:
	return sight[viewer][idx(c)] == 1


func knows(viewer: int, other: int) -> bool:
	return contacts.get("%d:%d" % [viewer, other], false)


func _contact_log(viewer: int, other: int) -> void:
	if viewer == Data.PLAYER and other == Data.AI:
		add_log("FIRST CONTACT: your scouts found the Rust Kings' land. Raids and trade are now possible.")
	elif viewer == Data.PLAYER and other == Data.TOWN:
		add_log("Your scouts found Dustwell, a small settlement. Befriend it or take it.")
	elif viewer == Data.AI and other == Data.PLAYER:
		add_log("Strange riders were seen watching your borders...")


## How many scouting parties you can have in the field at once.
func scout_parties() -> int:
	return 2 + mini(vehicles["horse"] + vehicles["car"], 3)


## Rust Kings outriders push into the unknown, heading west toward you. Returns where this one ended its move (off the
## map, (-1, -1), if there was nowhere left to go).
func _ai_scout() -> Vector2i:
	# The frontier is every unexplored tile with an explored tile beside it. It is worked out straight from the memory
	# array: asking knows_tile() and neighbors() for each of the 8,640 tiles took about 28 ms a scout (2 to 4 a season).
	var mem: Array = memory[Data.AI]
	var frontier := []
	var min_x := w
	for y in h:
		var row := y * w
		for x in w:
			var i := row + x
			if mem[i] != null:
				continue
			if (x > 0 and mem[i - 1] != null) or (x < w - 1 and mem[i + 1] != null) \
					or (y > 0 and mem[i - w] != null) or (y < h - 1 and mem[i + w] != null):
				frontier.append(Vector2i(x, y))
				min_x = mini(min_x, x)
	var west := frontier.filter(func(c): return c.x <= min_x + 2)
	if west.is_empty():
		return Vector2i(-1, -1)
	var at: Vector2i = west.pick_random()
	reveal(Data.AI, at, 5)
	return at


## Ends a replay or march the map is playing (it finishes at once) and does nothing if none is.
func skip_replay() -> void:
	if replaying:
		replay_skip.emit()


## A column of troops sets out for `target`: the map plays them walking there and back. The fight itself is already
## decided where this is called; troops stay a number, this is only the picture.
func _march_to(target: Vector2i) -> void:
	var from := home(Data.PLAYER)
	var path := route("foot", from, target)
	if path.size() < 2:
		path = [from, target]
	troops_marched.emit(path, troops)


func cycle_view() -> void:
	var order := [Data.PLAYER, Data.AI, Data.NONE]
	view = order[(order.find(view) + 1) % order.size()]
	changed.emit()


# ---------------------------------------------------------------- season

func end_season() -> void:
	if not ending.is_empty():
		return
	skip_replay()   # a replay still playing from the last season is over now
	_gather()
	_upkeep()
	_ai_turn()
	_cool_ash()
	_restock_salt()
	var sight_before: PackedByteArray = sight[Data.PLAYER].duplicate() if sight.has(Data.PLAYER) else PackedByteArray()
	Units.season_turn()
	season += 1
	raided_this_season = false
	buildings_lost = 0
	update_fog()
	_update_peaks()
	Units.replay["sight_before"] = sight_before
	season_played.emit(Units.replay)   # before check_ending(): the ending screen waits for the replay
	check_ending()
	if ending.is_empty():
		save_game("autosave")   # a finished game is not saved: Resume has nothing to come back to
	changed.emit()


func _add(into: Dictionary, add: Dictionary, times := 1) -> void:
	for k in add:
		into[k] = into.get(k, 0) + add[k] * times


func _gather() -> void:
	var gain := {}
	var producing := 0
	for c in owned(Data.PLAYER):
		var t := tile(c)
		var y: Dictionary = Data.TERRAIN[t["t"]].yield
		var by: Dictionary = Data.BUILDINGS[t["b"]].get("yield", {}) if t["b"] != "" else {}
		if not y.is_empty() or not by.is_empty():
			producing += 1
		_add(gain, y)
		_add(gain, by)
		if t["b"] == "lodge" and t["t"] == "grove":
			_add(gain, {"meat": 2})   # untouched woods are full of game
	if has("farming"):
		_add(gain, {"grain": 1}, count_building(Data.PLAYER, "farm"))
	if has("hunting"):
		_add(gain, {"meat": 1}, count_building(Data.PLAYER, "lodge"))
	if has("mining"):
		_add(gain, {"metal": 1}, count_building(Data.PLAYER, "mine"))
	if has_quirk("green_thumb"):
		_add(gain, {"veg": 1}, count_building(Data.PLAYER, "farm"))
	if has_quirk("prospector"):
		_add(gain, {"stone": 1}, count_building(Data.PLAYER, "mine"))
	if has("b_fc"):
		_add(gain, {"gold": 1}, count_building(Data.PLAYER, "wall") / 2)   # a toll for every 2 walls
	# Not enough workers (colonists + prisoner labor) means tiles go untended
	var workers := pop + prisoners
	var eff := 1.0 if producing == 0 else clampf(workers * 1.5 / producing, 0.25, 1.0)
	for k in gain.keys():
		gain[k] = int(round(gain[k] * eff))
		res[k] += gain[k]
		if gain[k] == 0:
			gain.erase(k)
	for k in gain:
		stats["gathered"][k] = stats["gathered"].get(k, 0) + gain[k]
	add_log("Gathered: %s%s" % [cost_text(gain), "" if eff >= 1.0 else " (short on workers)"])

	_refine()
	_drug_factories()

	# Hunting is risky
	for i in count_building(Data.PLAYER, "lodge"):
		if randf() < (0.03 if has("hunting") else 0.08) and pop > 1:
			pop -= 1
			add_log("A hunting party didn't come back from the wastes.")

	if has("c3"):
		res["gold"] += 3 * ally_count()
	if town["status"] == "ally":
		res["gold"] += 2
		res["grain"] += 3
	if has("cv5") and vehicles["plane"] > 0:
		res["gold"] += 6 * vehicles["plane"]
	if has("c5") and ai["relations"] >= 50:
		res["gold"] += 5
		add_log("The Rust Kings pay tribute to your merchant empire.")


## Each refinery you've switched on turns veg into fuel. This runs before the colony eats, so a
## refinery holds back when taking its veg would leave grain + veg short of feeding everyone.
func _refine() -> void:
	for i in refinery_on.keys():   # drop switches for refineries that are gone or no longer yours
		var c := Vector2i(i % w, i / w)
		if tile(c)["o"] != Data.PLAYER or tile(c)["b"] != "refinery":
			refinery_on.erase(i)
	var eaters := mouths()
	var veg_used := 0
	var fuel_made := 0
	var no_veg := 0
	var no_food := 0
	for c in running_refineries():
		if res["veg"] < Data.REFINERY_VEG:
			no_veg += 1
		elif res["grain"] + res["veg"] - Data.REFINERY_VEG < eaters:
			no_food += 1
		else:
			res["veg"] -= Data.REFINERY_VEG
			res["fuel"] += refinery_fuel()
			veg_used += Data.REFINERY_VEG
			fuel_made += refinery_fuel()
	if fuel_made > 0:
		add_log("Refineries turned %d veg into %d fuel." % [veg_used, fuel_made])
	if no_food > 0:
		add_log("%d running refinery held back: taking its veg would leave too little to eat." % no_food if no_food == 1 \
			else "%d running refineries held back: taking their veg would leave too little to eat." % no_food)
	if no_veg > 0:
		add_log("%d running refinery had no veg to refine." % no_veg if no_veg == 1 else "%d running refineries had no veg to refine." % no_veg)


## Fuel one refinery makes a season.
func refinery_fuel() -> int:
	return Data.REFINERY_FUEL_ETHANOL if has("cv3") else Data.REFINERY_FUEL


## Is the refinery on this tile yours and switched on? (They start off.)
func refinery_running(c: Vector2i) -> bool:
	return refinery_on.has(idx(c)) and tile(c)["o"] == Data.PLAYER and tile(c)["b"] == "refinery"


func running_refineries() -> Array:
	var out := []
	for i in refinery_on:
		var c := Vector2i(i % w, i / w)
		if refinery_running(c):
			out.append(c)
	return out


## Switches one of your refineries on or off.
func set_refinery(c: Vector2i, on: bool) -> void:
	if not in_bounds(c) or tile(c)["o"] != Data.PLAYER or tile(c)["b"] != "refinery":
		return
	if on:
		refinery_on[idx(c)] = true
	else:
		refinery_on.erase(idx(c))
	add_log("Refinery at %d,%d switched %s." % [c.x, c.y, "on" if on else "off"])
	changed.emit()


func _upkeep() -> void:
	starved_now = false
	# Everyone eats grain, then vegetables
	var eaters := mouths()
	var food: int = res["grain"] + res["veg"]
	if food >= eaters:
		var from_grain := mini(res["grain"], eaters)
		res["grain"] -= from_grain
		res["veg"] -= eaters - from_grain
		var surplus := food - eaters
		if surplus >= (6 if has_quirk("big_families") else 10) and pop < pop_cap():
			var growth := mini(1 + surplus / 20, pop_cap() - pop)
			pop += growth
			add_log("Food surplus: %d new settlers join." % growth)
	else:
		res["grain"] = 0
		res["veg"] = 0
		var lost := maxi(1, (eaters - food) / 3)
		if has_quirk("frugal"):
			lost = maxi(1, lost / 2)
		pop = maxi(pop - lost, 1)
		add_log("STARVATION: %d colonists died or fled." % lost)
		starved_now = true
		note("colonists_starved", lost)

	# Troops eat meat
	var per := 2 if has("w3") else 1
	var need := troops * per
	if res["meat"] >= need:
		res["meat"] -= need
	else:
		var deserters := int(ceil(float(need - res["meat"]) / per))
		res["meat"] = 0
		troops -= deserters
		add_log("No meat! %d troops deserted." % deserters)

	# Vehicle upkeep, for the ones at home: a vehicle out on a trip lives off its own tank
	for v in vehicles:
		var count: int = Units.free_vehicles(v)
		for i in count:
			if not pay(vehicle_upkeep(v)):
				vehicles[v] -= 1
				add_log("Couldn't maintain %s: one was lost." % Data.VEHICLES[v].name)

	# Too many prisoners and too few outposts round the HQ: a prison break. Otherwise they revolt if under-guarded
	if prison_break_due():
		_prison_break()
	elif prisoners > troops * guard_ratio() and randf() < 0.3:
		var escaped := prisoners / 2
		prisoners -= escaped
		troops = maxi(troops - 1, 0)
		add_log("PRISONER REVOLT! %d escaped." % escaped)


## Mouths to feed: the colonists and the prisoners, and for Big appetites 1 more for every 5 colonists.
func mouths() -> int:
	return pop + prisoners + (pop / 5 if has_quirk("big_appetites") else 0)


## The prisoner count a prison break needs to beat: 4, 2 more for a Warden, 1 fewer for Lax guards.
func prison_high() -> int:
	return Data.PRISON_HIGH + (2 if has_quirk("warden") else 0) - (1 if has_quirk("lax_guards") else 0)


## Prisoners one troop can guard before the old revolt can start: 3, or 4 for a Warden.
func guard_ratio() -> int:
	return 4 if has_quirk("warden") else 3


## How fast radiation poisons your people: Data.RAD_DOSE_RATE, 25% slower for Rad-proof, 15% faster for Frail colonists.
func dose_rate() -> float:
	if has_quirk("rad_proof"):
		return Data.RAD_DOSE_RATE * 0.75
	if has_quirk("frail_colonists"):
		return Data.RAD_DOSE_RATE * 1.15
	return Data.RAD_DOSE_RATE


## How long your parties take compared with the usual: 15% less for a Trailblazer, 10% more for Slow marchers.
func travel_mult() -> float:
	if has_quirk("trailblazer"):
		return 0.85
	if has_quirk("slow_marchers"):
		return 1.10
	return 1.0


## Your outposts inside the circle of control round the HQ (PRISON_CIRCLE tiles).
func outposts_in_circle() -> int:
	var n := 0
	for c in owned(Data.PLAYER):
		if tile(c)["b"] == "outpost" and c.distance_to(home(Data.PLAYER)) <= Data.PRISON_CIRCLE:
			n += 1
	return n


## More than PRISON_HIGH prisoners and fewer than PRISON_OUTPOSTS outposts in the circle: the pens will not hold.
func prison_break_due() -> bool:
	return prisoners > prison_high() and outposts_in_circle() < Data.PRISON_OUTPOSTS


## Half the prisoners (rounded up) get out and you lose a guard. They form a raider band at the edge of your land.
func _prison_break() -> void:
	var escaped := ceili(prisoners * Data.PRISON_ESCAPE)
	prisoners -= escaped
	troops = maxi(troops - 1, 0)
	if Units.spawn_escaped_band(escaped):
		add_log("PRISON BREAK! %d prisoners got out of the overfull pens and gathered at the edge of your land as a raider band." % escaped)
	else:
		add_log("PRISON BREAK! %d prisoners got out of the overfull pens and scattered into the wastes." % escaped)


func _ai_turn() -> void:
	var land := owned(Data.AI)
	for c in land:
		var y: Dictionary = Data.TERRAIN[tile(c)["t"]].yield
		ai["wood"] += y.get("wood", 0)
		ai["stone"] += y.get("stone", 0)
		ai["metal"] += y.get("metal", 0)
	ai["food"] += 2 + land.size() / 4
	ai["gold"] += 1 + land.size() / 10
	# Fixed "raider" personality: vehicles, then troops, then walls, always grabbing land
	for v in Data.AI_VEHICLES:
		var plan: Dictionary = Data.AI_VEHICLES[v]
		if season >= plan.season and ai[v] < plan.max and plan.cost.keys().all(func(k): return ai[k] >= plan.cost[k]):
			for k in plan.cost:
				ai[k] -= plan.cost[k]
			ai[v] += 1
	while ai["food"] >= 5 and ai["troops"] < 4 + land.size() / 4:
		ai["food"] -= 5
		ai["troops"] += 1
	if ai["wood"] >= 8 and ai["stone"] >= 6:
		ai["wood"] -= 8
		ai["stone"] -= 6
		ai["walls"] += 1
	var free := []
	for c in land:
		for n in neighbors(c):
			if tile(n)["o"] == Data.NONE:
				free.append(n)
	if not free.is_empty():
		tile(free.pick_random())["o"] = Data.AI
	ai["relations"] = maxi(ai["relations"] - 2, -100)
	_sync_ai_walls()
	_ai_roads()
	_ai_nukes()
	for i in 2 + mini(ai["horse"], 2):
		var at := _ai_scout()
		if in_bounds(at):
			_ai_scout_strike(at)

	if ai["truce"] > 0:
		ai["truce"] -= 1
	if ai["raid_planned"]:
		ai["raid_planned"] = false
		_ai_raid()
	elif ai["truce"] == 0 and season >= 4 and knows(Data.AI, Data.PLAYER):
		var chance := clampf(0.2 - ai["relations"] / 200.0, 0.05, 0.7)
		if randf() < chance:
			ai["raid_planned"] = true
			if has("f3"):
				add_log("WATCHTOWER: Rust Kings war party massing. Raid coming next season!")


# ---------------------------------------------------------------- the Rust Kings' nukes

## Can the Rust Kings pay this out of their stores?
func _ai_can_pay(cost: Dictionary) -> bool:
	return cost.keys().all(func(k): return ai[k] >= cost[k])


func _ai_pay(cost: Dictionary) -> void:
	for k in cost:
		ai[k] -= cost[k]


## Once a season, in their turn (Data.AI_NUKES): the airfield, the bomber, the warheads, and the strike planned last season going in, or a new one being planned.
func _ai_nukes() -> void:
	var rules: Dictionary = Data.AI_NUKES
	if ai["airfield_wait"] > 0:
		ai["airfield_wait"] -= 1
	var fields := count_building(Data.AI, "ai_airfield")
	if fields == 0 and season >= rules.airfield_season and ai["airfield_wait"] == 0 and _ai_can_pay(rules.airfield_cost):
		var spot := _ai_airfield_spot()
		if in_bounds(spot):
			_ai_pay(rules.airfield_cost)
			tile(spot)["b"] = "ai_airfield"
			ai["airfield_x"] = spot.x
			ai["airfield_y"] = spot.y
			ai["airfield_seen"] = 0
			fields = 1
	if fields > 0 and season >= rules.bomber_season and ai["bomber"] < 1 and _ai_can_pay(rules.bomber_cost):
		_ai_pay(rules.bomber_cost)
		ai["bomber"] += 1
	if season >= rules.warhead_season and (season - int(rules.warhead_season)) % int(rules.warhead_every) == 0:
		ai["nukes"] = mini(ai["nukes"] + 1, int(rules.warheads_max))
	var ready: bool = fields > 0 and ai["bomber"] > 0 and ai["nukes"] > 0
	if ai["nuke_x"] >= 0:   # planned last season: it goes now, if it still can
		var target := Vector2i(ai["nuke_x"], ai["nuke_y"])
		ai["nuke_x"] = -1
		ai["nuke_y"] = -1
		if ready:
			_ai_launch(target)
		return
	if ready and season - ai["last_strike"] >= int(rules.gap) and randf() < float(rules.chance):
		var target := _ai_nuke_target()
		if in_bounds(target):
			ai["nuke_x"] = target.x
			ai["nuke_y"] = target.y
			if has("f3"):
				add_log("WATCHTOWER: a Rust Kings bomber is on its way to %d,%d. Nukes next season: move your parties." % [target.x, target.y])


## The tile for a new airfield: free Rust Kings land a few tiles from their fort, as far from your HQ as there is. (-1, -1) if there is none.
func _ai_airfield_spot() -> Vector2i:
	var fort := home(Data.AI)
	var mine := home(Data.PLAYER)
	var span: Array = Data.AI_NUKES.fort_distance
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for c in owned(Data.AI):
		var d := Vector2(c).distance_to(Vector2(fort))
		if d < float(span[0]) or d > float(span[1]) or tile(c)["b"] != "" or tile(c)["t"] == "water" or slopes[idx(c)] == "steep":
			continue
		var away := Vector2(c).distance_to(Vector2(mine))
		if away > best_d or (away == best_d and (c.y < best.y or (c.y == best.y and c.x < best.x))):
			best = c
			best_d = away
	return best


## The centre of the 3 x 3 square that holds the most of your buildings a blast can take (at least Data.AI_NUKES.min_buildings; a tie goes to the one nearest their fort).
## (-1, -1) if no square holds enough.
func _ai_nuke_target() -> Vector2i:
	var fort := home(Data.AI)
	var best := Vector2i(-1, -1)
	var best_n := 0
	var seen := {}
	for c in owned(Data.PLAYER):
		if not blast_takes_building(tile(c)["b"]):
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var centre: Vector2i = c + Vector2i(dx, dy)
				if seen.has(centre) or not in_bounds(centre):
					continue
				seen[centre] = true
				var n := 0
				for p in blast_square(centre):
					if tile(p)["o"] == Data.PLAYER and blast_takes_building(tile(p)["b"]):
						n += 1
				if n > best_n or (n == best_n and n > 0 and Vector2(centre).distance_to(Vector2(fort)) < Vector2(best).distance_to(Vector2(fort))):
					best = centre
					best_n = n
	return best if best_n >= int(Data.AI_NUKES.min_buildings) else Vector2i(-1, -1)


## Their bomber takes off with a warhead for `target`. Flak towers may shoot it down first; otherwise the nuke goes off.
func _ai_launch(target: Vector2i) -> void:
	ai["last_strike"] = season
	ai["nukes"] -= 1
	if has("fv4") and randf() < float(Data.AI_NUKES.flak):
		ai["bomber"] -= 1
		add_log("FLAK: your flak towers shot down a Rust Kings bomber over %d,%d. It was carrying a nuke." % [target.x, target.y])
		return
	note("nukes_suffered")
	detonate(target, "rust_kings")
	focus.emit(target)


## A Rust Kings building was destroyed (by your scouts, a raid or a blast). With the last airfield gone nothing launches: a planned strike is called off, and they wait
## Data.AI_NUKES.rebuild seasons before they build another.
func _after_ai_loss(b: String) -> void:
	if b != "ai_airfield" or count_building(Data.AI, "ai_airfield") > 0:
		return
	ai["airfield_wait"] = int(Data.AI_NUKES.rebuild)
	ai["nuke_x"] = -1
	ai["nuke_y"] = -1
	note("airfields_destroyed")
	add_log("The Rust Kings' airfield is destroyed. Nothing of theirs can launch a nuke until they rebuild it (about %d seasons)." % int(Data.AI_NUKES.rebuild))


## Has your colony seen their airfield yet? (The Diplomacy tab says so.)
func check_airfield() -> void:
	if int(ai.get("airfield_seen", 0)) > 0 or int(ai.get("airfield_x", -1)) < 0 or not memory.has(Data.PLAYER):
		return
	var at := Vector2i(int(ai["airfield_x"]), int(ai["airfield_y"]))
	var known = memory[Data.PLAYER][idx(at)] if memory[Data.PLAYER].size() == w * h else null
	if known != null and known[1] == "ai_airfield":
		ai["airfield_seen"] = 1
		add_log("Your people found the Rust Kings' airfield at %d,%d. While it stands they can launch nukes: destroy it." % [at.x, at.y])


## What the Diplomacy tab says of their airfield.
func airfield_text() -> String:
	if int(ai.get("airfield_wait", 0)) > 0:
		return "Their airfield is destroyed: they rebuild it in %d seasons." % int(ai["airfield_wait"]) if int(ai.get("airfield_seen", 0)) > 0 else "Their airfield: not found."
	if int(ai.get("airfield_seen", 0)) > 0 and count_building(Data.AI, "ai_airfield") > 0:
		return "Their airfield stands at %d,%d (DC %d: a scouting party beside it, a raid, or a nuke)." % [int(ai["airfield_x"]), int(ai["airfield_y"]), D20Data.BUILDING_DC["ai_airfield"]]
	return "Their airfield: not found."


# ---------------------------------------------------------------- how the game ends

## What the stats screen shows, all counted from the start of the colony.
func new_stats() -> Dictionary:
	return {"raids_won": 0, "raids_lost": 0, "raids_beaten_back": 0, "raids_suffered": 0, "bands_driven_off": 0,
		"tribes_scattered": 0, "tribes_joined": 0, "prisoners_taken": 0, "troops_trained": 0, "survivors_lost": 0,
		"colonists_starved": 0, "buildings_lost": 0, "enemy_buildings_destroyed": 0, "ruins_scavenged": 0, "sites_scavenged": 0,
		"craters_searched": 0, "nukes_found": 0, "nukes_dropped": 0, "blasts": 0, "nukes_suffered": 0, "airfields_destroyed": 0, "nukes_bought": 0, "rolls": 0, "natural_20s": 0, "natural_1s": 0,
		"buildings_built": 0, "tiles_claimed": 0, "upgrades": 0, "vehicles_built": 0, "trade_runs": 0,
		"peak_pop": pop, "peak_land": 0, "peak_troops": troops,
		"sent": {"scav": 0, "scout": 0, "caravan": 0, "boat": 0, "plane": 0}, "gathered": {}}


## Adds `n` to a counter on the stats screen.
func note(key: String, n := 1) -> void:
	stats[key] = stats.get(key, 0) + n


func note_sent(job: String) -> void:
	stats["sent"][job] = stats["sent"].get(job, 0) + 1


## Stats from a save: JSON gives every number back as a float.
func _load_stats(d: Dictionary) -> Dictionary:
	var out := new_stats()
	for k in d:
		if d[k] is Dictionary:
			out[k] = _ints(d[k])
		else:
			out[k] = int(d[k])
	return out


func _update_peaks() -> void:
	stats["peak_pop"] = maxi(stats.get("peak_pop", 0), pop)
	stats["peak_troops"] = maxi(stats.get("peak_troops", 0), troops)
	stats["peak_land"] = maxi(stats.get("peak_land", 0), owned(Data.PLAYER).size())


## Raids fought between you and the Rust Kings, whoever won.
func battles() -> int:
	return stats.get("raids_won", 0) + stats.get("raids_lost", 0) + stats.get("raids_beaten_back", 0) + stats.get("raids_suffered", 0)


## Your defense as the Rust Kings meet it: walls and towers plus your troops.
func player_defense() -> float:
	return player_wall_defense() + player_troop_defense()


## Is the Rust Kings' raid strength a small enough share of your defense that they can no longer threaten you?
func rust_kings_broken() -> bool:
	return ai_attack() < player_defense() * Data.ENDINGS.prosper.ratio


## Called at the end of each season (and after a raid): has the game been won or lost? It can only end once.
func check_ending() -> void:
	if not ending.is_empty() or not in_game:
		return
	var rule: Dictionary = Data.ENDINGS
	if starved_now and pop <= rule.lose_pop:
		_end("defeat", "starved")
	elif owned(Data.PLAYER).size() <= rule.lose_land:
		_end("defeat", "overrun")
	elif owned(Data.AI).size() <= rule.broken_land:
		_end("raiders_defeated", "broken")
	else:
		var p: Dictionary = rule.prosper
		var healthy: bool = pop >= p.pop and owned(Data.PLAYER).size() >= p.land and not starved_now
		if season >= p.season and healthy and battles() >= p.battles and rust_kings_broken():
			prosper_streak += 1
		else:
			prosper_streak = 0
		if prosper_streak >= p.streak:
			_end("colony_prospers", "long game")


func _end(kind: String, why: String) -> void:
	if not ending.is_empty():
		return
	ending = {"kind": kind, "why": why, "season": season}
	add_log("THE END: %s." % Data.ENDING_SCREENS[kind].title)
	game_ended.emit(kind)
	changed.emit()


func ended() -> bool:
	return not ending.is_empty()


## After the ending screens: back to the main menu with no game running.
func leave_game() -> void:
	skip_replay()
	in_game = false
	ending = {}
	selected = Vector2i(-1, -1)
	changed.emit()


# ---------------------------------------------------------------- saving

func _path(slot: String) -> String:
	return save_dir + slot + ".json"


func save_game(slot: String) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var packed := []
	for t in tiles:
		packed.append([t["t"], t["o"], t["b"], t["z"], t["r"], t["rad"], 1 if t.get("f", false) else 0])
	var data := {
		"version": 3, "w": w, "h": h, "leader": leader, "season": season, "pop": pop, "troops": troops,
		"prisoners": prisoners, "res": res, "items": items, "salt_on": salt_on, "upgrades": upgrades, "vehicles": vehicles,
		"units": Units.to_save(), "raided": raided_this_season, "ai": ai, "town": town,
		"log": log_lines, "catastrophes": catastrophes.map(_pack_catastrophe), "tiles": packed, "contacts": contacts, "hollow_found": hollow_found,
		"refineries_on": refinery_on.keys(), "stats": stats, "prosper_streak": prosper_streak, "buildings_lost": buildings_lost, "leader_info": leader_info,
		"memory": Data.FOG_VIEWERS.map(func(v): return memory[v]), "measured": _measured_cells(),
	}
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	if slot != "autosave":
		add_log("Game saved to %s." % slot)
		changed.emit()


func load_game(slot: String) -> bool:
	if not FileAccess.file_exists(_path(slot)):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(_path(slot)))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	skip_replay()   # the replay of the game being left is over
	# JSON stores every number as a float, so turn them back into ints
	leader = data["leader"]
	leader_info = Leaders.fill(leader, data.get("leader_info", {}))   # none in saves from before named leaders
	season = int(data["season"])
	pop = int(data["pop"])
	troops = int(data["troops"])
	prisoners = int(data["prisoners"])
	w = int(data.get("w", 60))   # saves from before the bigger map were 60 x 36
	h = int(data.get("h", 36))
	raided_this_season = data["raided"]
	res = _ints(data["res"])
	items = {}
	for item in Data.ITEMS:   # saves from before frog hides and Salt have none
		items[item] = int(data.get("items", {}).get(item, 0))
	salt_on = bool(data.get("salt_on", false))
	for k in res.keys():
		if not k in Data.RESOURCES:
			res.erase(k)   # scrap and silver are gone: a save from before that just loses them
	vehicles = _ints(data["vehicles"])
	for v in Data.VEHICLES:   # a save from before bombers has none
		if not vehicles.has(v):
			vehicles[v] = 0
	ai = _ints(data["ai"])
	ai.merge({"horse": 0, "car": 0, "boat": 0, "plane": 0})   # saves from before enemy vehicles
	ai.merge({"bomber": 0, "nukes": 0, "airfield_wait": 0, "airfield_x": -1, "airfield_y": -1, "airfield_seen": 0, "nuke_x": -1, "nuke_y": -1, "last_strike": -99})   # and before nukes
	town = _ints(data["town"])
	upgrades = data["upgrades"]
	log_lines = data["log"]
	tiles = []
	map_version += 1
	for t in data["tiles"]:
		tiles.append({"t": t[0], "o": int(t[1]), "b": {"dock": "port", "scrapyard": "motor_pool"}.get(t[2], t[2]), "z": int(t[3]) if t.size() > 3 else 0,
			"r": t[4] if t.size() > 4 else "", "rad": int(t[5]) if t.size() > 5 else 0, "f": t.size() > 6 and int(t[6]) == 1})
	preview = {}
	catastrophes = data.get("catastrophes", []).map(_unpack_catastrophe)   # none in older saves
	_find_bases()
	_sync_ai_walls()   # saves from before the Raider walls get their tiles
	_seed_ruins()   # fills in ruins dangers for saves from before they existed
	if data["tiles"][0].size() <= 5:
		_pass_radiation()   # saves from before radiation
	measured = PackedByteArray()
	measured.resize(w * h)
	for i in data.get("measured", []):
		measured[int(i)] = 1
	show_radiation = false
	if data["tiles"][0].size() > 3:
		_build_contours()
	else:
		_generate_heights()   # old save from before heights existed
	view = Data.PLAYER
	if data.has("memory"):
		contacts = data["contacts"]
		for i in Data.FOG_VIEWERS.size():
			memory[Data.FOG_VIEWERS[i]] = data["memory"][i].map(func(e): return null if e == null else [int(e[0]), e[1]])
	else:
		_reset_fog()   # old save without fog of war
	hollow_found = bool(data.get("hollow_found", _hollow_known()))   # a save from before the picture counts it as found if you have seen the highway
	ending = {}
	stats = _load_stats(data.get("stats", {}))
	prosper_streak = int(data.get("prosper_streak", 0))
	buildings_lost = int(data.get("buildings_lost", 0))
	starved_now = false
	refinery_on = {}
	for i in data.get("refineries_on", []):   # saves from before the switch have every refinery off
		refinery_on[int(i)] = true
	Units.load_from(data.get("units", {}))
	selected = Vector2i(-1, -1)
	selected_scout = -1
	scout_route = {}
	in_game = true
	add_log("Game loaded.")
	changed.emit()
	focus.emit(home(Data.PLAYER))
	return true


func _pack_catastrophe(cat: Dictionary) -> Dictionary:
	var out := cat.duplicate()
	out["pos"] = [cat.pos.x, cat.pos.y]
	return out


func _unpack_catastrophe(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out["pos"] = Vector2i(int(d["pos"][0]), int(d["pos"][1]))
	out["radius"] = int(d["radius"])
	out["year"] = int(d["year"])
	return out


func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k]) if typeof(d[k]) == TYPE_FLOAT else d[k]
	return out


func save_info(slot: String) -> String:
	if not FileAccess.file_exists(_path(slot)):
		return "empty"
	var data = JSON.parse_string(FileAccess.get_file_as_string(_path(slot)))
	if typeof(data) != TYPE_DICTIONARY:
		return "corrupt"
	var s := int(data["season"])
	var who := Leaders.label(Leaders.fill(data["leader"], data.get("leader_info", {})))
	return "%s - Year %d %s" % [who, (s - 1) / 4 + 1, Data.SEASONS[(s - 1) % 4]]
