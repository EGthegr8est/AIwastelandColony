extends RefCounted
## The season, played back. END SEASON still decides everything at once (units.gd walks every party its whole
## season in one go), but while it does, Units notes where each unit was and on which day. The map then replays those
## notes so you watch the parties walk, at their real speeds, instead of seeing them jump.
##
## A replay is a Dictionary:
##   actors     one per unit that was on the map at the start of the season:
##                {"id", "kind" (a key of Data.UNITS, Data.ANIMALS or "frog"), "owner", "mover", "parked" (a scouting party on station),
##                 "wild" (a wandering animal: it never decides how long the replay is, and a season where only animals moved plays nothing),
##                 "trail" ([[cell, day], ...] from day 0, one entry per tile reached), "gone_day" (the day it left
##                 the map, or -2.0 if it is still there)}
##   events     things that happen once the walking is done: {"kind": "clash"|"ruin"|"home"|"smoke"|"snap", "cell", "day"}
##   reveals    ground your parties uncovered, [[cell, day], ...]: it stays dark until the party gets there
##   sight_before   what the player could see when the season began (a band is shown while it was in sight then or is now)
##   end_day    the day the last unit stopped (settle() works it out)
## A march (troops going to raid something) is a replay too: see march().

const Data = preload("res://scripts/data.gd")

const MODES := ["normal", "fast", "off"]
const NAMES := {"normal": "Normal", "fast": "Fast", "off": "Off"}
## Real seconds a whole season (Data.SEASON_DAYS) takes to play. A walk of half a season takes half as long.
const SECONDS := {"normal": 3.0, "fast": 1.2}
const POP_SECONDS := 0.7       # a flash or a puff of smoke lasts this long, whatever the speed
const DUST_DAYS := 5.0         # how far behind a walking unit its dust trail reaches
const FADE_DAYS := 2.0         # a unit that leaves the map (home, wiped out) fades over this many days
const STILL := -2.0            # gone_day of a unit that stayed on the map
const AT_END := -1.0           # gone_day or event day meaning "when the walking is done"
const SETTINGS_SECTION := "display"
const SETTINGS_KEY := "season_replay"

# A march: up to MARCH_MAX troop markers walk a column from your HQ to the target (a new marker sets off every MARCH_STEP
# days), the fight flashes, and they come home. They go at MARCH_PACE tiles a day (a party on horseback does two), so the
# way out takes between MARCH_OUT_MIN and MARCH_OUT_MAX days (a far fort is a long, quick march), and the way back is a little quicker.
const MARCH_MAX := 6
const MARCH_STEP := 0.9
const MARCH_PACE := 2.0
const MARCH_OUT_MIN := 6.0
const MARCH_OUT_MAX := 24.0
const MARCH_PAUSE := 2.0
const MARCH_BACK_SHARE := 0.85

# The troop marker, 8 x 8 (1 = body, 2 = dark)
const SOLDIER := ["..1111..", ".111111.", "..1221..", "...11...", ".111111.", "1.1111.1", "..1111..", "..1..1.."]
const SOLDIER_COLORS := {"1": Color("c9e07a"), "2": Color("1d2814")}

static var mode := "normal"   # tests set "off"


static func seconds() -> float:
	return SECONDS.get(mode, 0.0)


static func mode_text() -> String:
	return NAMES[mode]


## Normal, then Fast, then Off, then Normal again.
static func cycle() -> void:
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	save_mode()


## The saved choice, if there is one (the file Music keeps its volume in, which tests point at a scratch file).
static func load_mode() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Music.settings_path) != OK or not cfg.has_section_key(SETTINGS_SECTION, SETTINGS_KEY):
		return
	var saved := str(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY))
	if saved in MODES:
		mode = saved


static func save_mode() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Music.settings_path)   # keep anything else in there
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, mode)
	cfg.save(Music.settings_path)


## Where a trail has put its unit on `day`, in map cells (fractional between two tiles).
static func position_at(trail: Array, day: float) -> Vector2:
	if trail.is_empty():
		return Vector2.ZERO
	if day <= trail[0][1]:
		return Vector2(trail[0][0])
	for i in range(1, trail.size()):
		var b: Array = trail[i]
		if day <= b[1]:
			var a: Array = trail[i - 1]
			var span: float = b[1] - a[1]
			return Vector2(a[0]).lerp(Vector2(b[0]), 1.0 if span <= 0.0 else (day - a[1]) / span)
	return Vector2(trail.back()[0])


## Is the unit walking on `day` (rather than waiting at the start or finished)?
static func moving_at(trail: Array, day: float) -> bool:
	return trail.size() > 1 and day > trail[0][1] and day < trail.back()[1]


## The tiles a unit left behind in the last `span` days: [[cell, age in days], ...], newest first.
static func recent(trail: Array, day: float, span: float) -> Array:
	var out := []
	for i in range(trail.size() - 1, -1, -1):
		var d: float = trail[i][1]
		if d >= day:
			continue
		if day - d > span:
			break
		out.append([trail[i][0], day - d])
	return out


## Works out end_day (the day the last unit stopped walking) and fills in the days that were left as "when the
## walking is done". Safe to call twice.
static func settle(r: Dictionary) -> Dictionary:
	var end := 0.0
	for a in r.actors:
		if not a.get("wild", false):
			end = maxf(end, a.trail.back()[1])
	for e in r.events:
		if e.day >= 0.0:
			end = maxf(end, e.day)
	r["end_day"] = end
	if not r.get("wilds_fitted", false) and end > 0.0:
		r["wilds_fitted"] = true   # the animals' days are fitted into the walking, so the replay ends when the walkers do
		for a in r.actors:
			if a.get("wild", false):
				for step in a.trail:
					step[1] = step[1] * end / Data.SEASON_DAYS
	for a in r.actors:
		if a.gone_day == AT_END:
			a.gone_day = end
	for e in r.events:
		if e.day == AT_END:
			e.day = end
	return r


## Is there anything to watch? A season where nobody walks and nothing happens plays no replay at all.
static func has_motion(r: Dictionary) -> bool:
	if r.is_empty():
		return false
	for a in r.actors:
		if a.trail.size() > 1 and not a.get("wild", false):
			return true
	return not r.events.is_empty()


## How many real seconds the replay takes at `secs` for a whole season: the walking, then the last flash.
static func length(r: Dictionary, secs: float) -> float:
	var rate: float = Data.SEASON_DAYS / secs
	return r.end_day / rate + (POP_SECONDS if not r.events.is_empty() else 0.0)


## The replay of a column of troops going down `path` (cells from your HQ to the target) and back: the
## fight is already decided, this is only the picture.
static func march(path: Array, count: int) -> Dictionary:
	if path.size() < 2:
		path = [path[0], path[0]]
	var n := clampi(count, 1, MARCH_MAX)
	var last := path.size() - 1
	var out_days := clampf(float(last) / MARCH_PACE, MARCH_OUT_MIN, MARCH_OUT_MAX)
	var back_days := out_days * MARCH_BACK_SHARE
	var turn := out_days + float(n - 1) * MARCH_STEP + MARCH_PAUSE
	var actors := []
	for k in n:
		var delay := float(k) * MARCH_STEP
		var trail := [[path[0], 0.0]]
		for i in range(1, path.size()):
			trail.append([path[i], delay + out_days * float(i) / float(last)])
		for i in range(path.size() - 2, -1, -1):
			trail.append([path[i], turn + back_days * float(last - i) / float(last)])
		actors.append({"id": -1 - k, "kind": "soldier", "owner": Data.PLAYER, "mover": "foot", "parked": false,
			"trail": trail, "gone_day": AT_END})
	var r := {"actors": actors, "events": [{"kind": "clash", "cell": path[last], "day": turn - MARCH_PAUSE * 0.5}],
		"reveals": [], "sight_before": PackedByteArray(), "march": true}
	return settle(r)
