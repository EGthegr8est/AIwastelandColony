extends Node
## Autoload "Game": the whole simulation. The colony is simulated as one unit,
## not as individual colonists. Every player action is a function here, and the
## UI just calls them and redraws when `changed` fires.

signal changed
signal focus(cell: Vector2i)
signal tile_selected
signal game_ended(kind: String)   # the game has ended: "raiders_defeated", "colony_prospers" or "defeat"

const Data = preload("res://scripts/data.gd")
const SAVE_DIR := "user://saves/"

var save_dir := SAVE_DIR       # tests point this at their own folder so they never touch real saves

var w := Data.MAP_W
var h := Data.MAP_H
var tiles: Array = []          # each tile: {"t": terrain, "o": owner, "b": building, "z": height in m,
                               #             "r": ruins state: "safe", "rogue", "rogue_seen", "trap", "picked"}
var map_version := 0           # goes up whenever the tiles are replaced (new game, load)
var bases := {}                # owner -> the cell of their HQ (or Dustwell's center)
var contours: Array = []       # per tile: contour pipe glyph, or "" if no contour runs through it
var slopes: Array = []         # per tile: "", "gentle" or "steep"
var paths := {}                # mover ("foot", "horse", "car") -> AStarGrid2D route finder
var preview := {}              # mover -> route from your HQ to the selected tile
var selected_scout := -1       # id of the scouting party you have picked (-1 = none), see select()
var scout_route := {}          # that party's route to the selected tile: {"mover", "path", "days", "ratio"}, see refresh_scout_route()
var refinery_on := {}          # tile index -> true for each refinery you've switched on (new ones start off)
var res: Dictionary = {}
var pop := 10
var troops := 3
var prisoners := 0
var season := 1
var leader := "builder"
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

# Fog of war. memory[viewer] has one entry per tile: null if that colony has never
# seen it, otherwise [owner, building] as it looked the last time it was in sight.
# sight[viewer] marks the tiles that colony can see right now.
var memory := {}
var sight := {}
var contacts := {}             # "viewer:other" -> true once a colony has found another
var view := Data.PLAYER        # whose knowledge the map shows (Data.NONE = everything)
var measured := PackedByteArray()   # 1 where one of your parties has measured the radiation
var show_radiation := false    # tint the tiles you have measured by how hot they are


func _ready() -> void:
	changed.connect(update_fog)
	changed.connect(_keep_scout_route_fresh)


# ---------------------------------------------------------------- new game

func new_game(leader_id: String) -> void:
	leader = leader_id
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
	selected = Vector2i(-1, -1)
	selected_scout = -1
	preview = {}
	scout_route = {}
	refinery_on = {}
	res = {}
	for r in Data.RESOURCES:
		res[r] = 0
	res.merge({"wood": 30, "stone": 15, "metal": 5, "grain": 25, "veg": 10, "meat": 10, "gold": 15}, true)
	vehicles = {}
	for v in Data.VEHICLES:
		vehicles[v] = 0
	ai = {"name": "The Rust Kings", "troops": 6, "walls": 0, "food": 20, "wood": 20, "stone": 10,
		"metal": 5, "gold": 10, "relations": 0, "truce": 0, "raid_planned": false,
		"horse": 0, "car": 0, "boat": 0, "plane": 0}
	town = {"name": "Dustwell", "status": "neutral", "relations": 20}
	w = Data.MAP_W
	h = Data.MAP_H
	_generate_map()
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
	_pass_pois()   # last, so placing them leaves every earlier pass (and its random numbers) exactly as it was


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
			tiles.append({"t": t, "o": Data.NONE, "b": "", "r": "", "rad": 0})


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
		for p in poi_footprint(spot):
			var t := tile(p)
			if t["t"] != "waste":
				t["t"] = "sand"   # bare ground under the sprite (fallout waste stays: only the dump may stand on it)
			t["b"] = "poi_" + kind
			t["r"] = ""


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
	if tile(c)["t"] == "water":
		return m.water
	if tile(c)["b"] in ["hq", "ai_hq", "town"]:
		return m.land   # settlements always have a way in
	var s: String = slopes[idx(c)]
	return m[s] if s != "" else m.land


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


## The fastest route for this mover, or [] if there's no way through.
func route(mover: String, from: Vector2i, to: Vector2i) -> Array:
	return paths[mover].get_id_path(from, to)


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
			parts.append("%d %s" % [cost[k], k])
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
		var days := Units.arrival_days(u.mover, path, Units.load_slowdown(u))
		scout_route ={"mover": u.mover, "path": path, "days": days, "ratio": Units.food_ratios(u, days)}


# ---------------------------------------------------------------- land & buildings

func claim_cost(c: Vector2i) -> Dictionary:
	if tile(c)["o"] == Data.AI:
		return {"gold": 25}
	return {"wood": 3 + owned(Data.PLAYER).size() / 10, "gold": 1}


## Returns "" if the tile can be claimed, otherwise the reason it can't.
func claim_status(c: Vector2i) -> String:
	var t := tile(c)
	if t["o"] == Data.PLAYER:
		return "Already yours"
	if not borders(c, Data.PLAYER):
		return "Must border your land"
	if t["o"] == Data.AI:
		if not has("c5"):
			return "Enemy land (Merchant empire lets you buy it)"
		if ai["relations"] < 0 or t["b"] == "ai_hq":
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
		return "Not your land"
	if t["b"] != "":
		return "Tile already has a building"
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
	if id == "outpost":
		for y in range(c.y - 2, c.y + 3):
			for x in range(c.x - 2, c.x + 3):
				var p := Vector2i(x, y)
				if in_bounds(p) and tile(p)["o"] == Data.NONE:
					tile(p)["o"] = Data.PLAYER
	add_log("Built a %s.%s" % [Data.BUILDINGS[id].name, " It starts switched off: select it to start it." if id == "refinery" else ""])
	changed.emit()


func demolish(c: Vector2i) -> void:
	var t := tile(c)
	if t["o"] == Data.PLAYER and t["b"] != "" and t["b"] != "hq" and poi_kind(c) == "":
		t["b"] = ""
		refinery_on.erase(idx(c))
		changed.emit()


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
	return {"metal": 3, "meat": 2}


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
	if has("w4") or vehicles["plane"] > 0:
		return 0.5
	return 1.0


func player_wall_defense() -> float:
	var wall_each := 2 + (2 if has("f2") else 0)
	var d := count_building(Data.PLAYER, "wall") * wall_each
	for b in ["tower", "keep", "citadel"]:
		d += count_building(Data.PLAYER, b) * Data.BUILDINGS[b].defense
	if has("b_wf"):
		d += count_building(Data.PLAYER, "outpost") * wall_each
	return d


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
		if not keep_buildings:
			t["b"] = ""
		taken += 1
	return taken


func raid_ai() -> void:
	if troops <= 0 or raided_this_season or not knows(Data.PLAYER, Data.AI) or not ending.is_empty():
		return
	raided_this_season = true
	var att := player_attack(home(Data.AI))
	var def := ai_defense(wall_breach())
	if Units.free_vehicles("car") > 0 and route("car", home(Data.PLAYER), home(Data.AI)).is_empty():
		add_log("Your war rigs couldn't find a way around the steep inclines and stayed home.")
	ai["relations"] = maxi(ai["relations"] - 30, -100)
	ai["truce"] = 0
	if randf() * (att + def) < att:
		var loot := {}
		for k in ["wood", "stone", "metal", "gold"]:
			loot[k] = int(ai[k] * 0.25)
			ai[k] -= loot[k]
			res[k] += loot[k]
		var caught := 1 + randi() % 3 + (2 if has("w2") else 0)
		prisoners += caught
		note("prisoners_taken", caught)
		note("raids_won")
		ai["troops"] -= int(ceil(ai["troops"] * 0.3))
		troops -= int(troops * 0.15)
		var land := _take_land(Data.AI, Data.PLAYER, 3 if has("w5") else 1, has("w5"))
		add_log("RAID WON! Looted %s, took %d prisoners and %d tiles." % [cost_text(loot), caught, land])
		if att >= def * Data.ENDINGS.decisive_win:
			add_log("Your attack was overwhelming: the Rust Kings' fort has fallen.")
			_end("raiders_defeated", "stormed")
	else:
		var lost := int(ceil(troops * 0.4))
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
	if randf() * (att + def) < att:
		var loot := {}
		for k in ["wood", "stone", "metal", "gold", "grain", "fuel"]:
			loot[k] = int(res[k] * 0.2)
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
		if att >= def * Data.ENDINGS.decisive_loss and count_building(Data.PLAYER, "citadel") == 0:
			add_log("Their attack was overwhelming: the colony is overrun.")
			_end("defeat", "overrun")
	else:
		ai["troops"] -= int(ceil(ai["troops"] * 0.4))
		troops -= int(troops * 0.1)
		prisoners += 1
		note("prisoners_taken")
		note("raids_beaten_back")
		add_log("Rust Kings raid beaten back! You captured a raider.")
	# Either way, you can follow their tracks home
	if not knows(Data.PLAYER, Data.AI):
		reveal(Data.PLAYER, home(Data.AI), 3)
		add_log("You followed the raiders' tracks back to their fort in the east.")


# ---------------------------------------------------------------- trade & diplomacy

func caravan_slots() -> int:
	var water_route := 1 if has("cv4") and count_building(Data.PLAYER, "port") > 0 else 0
	return Data.LEADERS[leader].caravans + (1 if has("c1") else 0) + count_building(Data.PLAYER, "market") + water_route


func can_trade() -> bool:
	return ai["relations"] > -30 and knows(Data.PLAYER, Data.AI)


func sell(r: String) -> void:
	var amount: int = Data.MARKET[r][0]
	if can_trade() and res[r] >= amount:
		res[r] -= amount
		res["gold"] += Data.MARKET[r][1]
		ai["relations"] = mini(ai["relations"] + 1, 100)
		changed.emit()


func buy(r: String) -> void:
	var price: int = Data.MARKET[r][1] * 2
	if can_trade() and res["gold"] >= price:
		res["gold"] -= price
		res[r] += Data.MARKET[r][0]
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
	return 8 if has("b_wc") else 3


func ransom_prisoners() -> void:
	if prisoners <= 0 or not knows(Data.PLAYER, Data.AI):
		return
	res["gold"] += prisoners * ransom_price()
	ai["relations"] = mini(ai["relations"] + 5, 100)
	add_log("Ransomed %d prisoners for %d gold." % [prisoners, prisoners * ransom_price()])
	prisoners = 0
	changed.emit()


func befriend_cost() -> Dictionary:
	return {"grain": 10, "gold": 5}


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


func conquer_town() -> void:
	if town["status"] != "neutral" or troops <= 0 or raided_this_season or not knows(Data.PLAYER, Data.TOWN):
		return
	raided_this_season = true
	var att := player_attack(home(Data.TOWN))
	var def := 8.0
	if randf() * (att + def) < att:
		for c in owned(Data.TOWN):
			tile(c)["o"] = Data.PLAYER
		prisoners += 5
		note("prisoners_taken", 5)
		town["status"] = "conquered"
		ai["relations"] = maxi(ai["relations"] - 15, -100)
		add_log("You took Dustwell by force. Its land and 5 prisoners are yours. Your name darkens.")
	else:
		var lost := int(ceil(troops * 0.4))
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


## Mark an area as explored (remembered) without it staying in sight.
func reveal(viewer: int, c: Vector2i, r: int) -> void:
	for p in _circle(c, r):
		_remember(viewer, idx(p))


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


func _near_known(viewer: int, c: Vector2i) -> bool:
	if knows_tile(viewer, c):
		return true
	for n in neighbors(c):
		if knows_tile(viewer, n):
			return true
	return false


## How many scouting parties you can have in the field at once.
func scout_parties() -> int:
	return 2 + mini(vehicles["horse"] + vehicles["car"], 3)


## Rust Kings outriders push into the unknown, heading west toward you.
func _ai_scout() -> void:
	var frontier := []
	var min_x := w
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if not knows_tile(Data.AI, c) and _near_known(Data.AI, c):
				frontier.append(c)
				min_x = mini(min_x, x)
	var west := frontier.filter(func(c): return c.x <= min_x + 2)
	if not west.is_empty():
		reveal(Data.AI, west.pick_random(), 5)


func cycle_view() -> void:
	var order := [Data.PLAYER, Data.AI, Data.NONE]
	view = order[(order.find(view) + 1) % order.size()]
	changed.emit()


# ---------------------------------------------------------------- season

func end_season() -> void:
	if not ending.is_empty():
		return
	_gather()
	_upkeep()
	_ai_turn()
	Units.season_turn()
	season += 1
	raided_this_season = false
	update_fog()
	_update_peaks()
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
	var eaters := pop + prisoners
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
	var eaters := pop + prisoners
	var food: int = res["grain"] + res["veg"]
	if food >= eaters:
		var from_grain := mini(res["grain"], eaters)
		res["grain"] -= from_grain
		res["veg"] -= eaters - from_grain
		var surplus := food - eaters
		if surplus >= 10 and pop < pop_cap():
			var growth := mini(1 + surplus / 20, pop_cap() - pop)
			pop += growth
			add_log("Food surplus: %d new settlers join." % growth)
	else:
		res["grain"] = 0
		res["veg"] = 0
		var lost := maxi(1, (eaters - food) / 3)
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

	# Prisoners revolt if under-guarded
	if prisoners > troops * 3 and randf() < 0.3:
		var escaped := prisoners / 2
		prisoners -= escaped
		troops = maxi(troops - 1, 0)
		add_log("PRISONER REVOLT! %d escaped." % escaped)


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
	for i in 2 + mini(ai["horse"], 2):
		_ai_scout()

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


# ---------------------------------------------------------------- how the game ends

## What the stats screen shows, all counted from the start of the colony.
func new_stats() -> Dictionary:
	return {"raids_won": 0, "raids_lost": 0, "raids_beaten_back": 0, "raids_suffered": 0, "bands_driven_off": 0,
		"tribes_scattered": 0, "tribes_joined": 0, "prisoners_taken": 0, "troops_trained": 0, "survivors_lost": 0,
		"colonists_starved": 0, "ruins_scavenged": 0, "sites_scavenged": 0, "rolls": 0, "natural_20s": 0, "natural_1s": 0,
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
		packed.append([t["t"], t["o"], t["b"], t["z"], t["r"], t["rad"]])
	var data := {
		"version": 3, "w": w, "h": h, "leader": leader, "season": season, "pop": pop, "troops": troops,
		"prisoners": prisoners, "res": res, "upgrades": upgrades, "vehicles": vehicles,
		"units": Units.to_save(), "raided": raided_this_season, "ai": ai, "town": town,
		"log": log_lines, "catastrophes": catastrophes.map(_pack_catastrophe), "tiles": packed, "contacts": contacts,
		"refineries_on": refinery_on.keys(), "stats": stats, "prosper_streak": prosper_streak,
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
	# JSON stores every number as a float, so turn them back into ints
	leader = data["leader"]
	season = int(data["season"])
	pop = int(data["pop"])
	troops = int(data["troops"])
	prisoners = int(data["prisoners"])
	w = int(data.get("w", 60))   # saves from before the bigger map were 60 x 36
	h = int(data.get("h", 36))
	raided_this_season = data["raided"]
	res = _ints(data["res"])
	for k in res.keys():
		if not k in Data.RESOURCES:
			res.erase(k)   # scrap and silver are gone: a save from before that just loses them
	vehicles = _ints(data["vehicles"])
	ai = _ints(data["ai"])
	ai.merge({"horse": 0, "car": 0, "boat": 0, "plane": 0})   # saves from before enemy vehicles
	town = _ints(data["town"])
	upgrades = data["upgrades"]
	log_lines = data["log"]
	tiles = []
	map_version += 1
	for t in data["tiles"]:
		tiles.append({"t": t[0], "o": int(t[1]), "b": {"dock": "port", "scrapyard": "motor_pool"}.get(t[2], t[2]), "z": int(t[3]) if t.size() > 3 else 0,
			"r": t[4] if t.size() > 4 else "", "rad": int(t[5]) if t.size() > 5 else 0})
	preview = {}
	catastrophes = data.get("catastrophes", []).map(_unpack_catastrophe)   # none in older saves
	_find_bases()
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
	ending = {}
	stats = _load_stats(data.get("stats", {}))
	prosper_streak = int(data.get("prosper_streak", 0))
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
	return "%s - Year %d %s" % [Data.LEADERS[data["leader"]].name, (s - 1) / 4 + 1, Data.SEASONS[(s - 1) % 4]]
