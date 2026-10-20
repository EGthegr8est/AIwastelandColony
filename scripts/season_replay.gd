extends RefCounted
## The walking, played back. END SEASON still decides everything at once (units.gd walks every caravan, boat, plane, raider band and
## animal its whole season in one go), and one of your Scavenger Parties walks the moment you order it (Units._go); either way Units notes
## where each unit was and on which day. The map then replays those notes so you watch them walk, at their real speeds and the same
## normal pace (a season's 40 days take 3 seconds), instead of seeing them jump.
##
## A replay is a Dictionary:
##   actors     one per unit that was on the map at the start of the season:
##                {"id", "kind" (a key of Data.UNITS, Data.ANIMALS or "frog"), "owner", "mover", "parked" (a scouting party on station),
##                 "wild" (a wandering animal: it never decides how long the replay is, and a season where only animals moved plays nothing),
##                 "trail" ([[cell, day], ...] from day 0, one entry per tile reached), "gone_day" (the day it left
##                 the map, or -2.0 if it is still there)}
##   events     things that happen once the walking is done: {"kind": "clash"|"ruin"|"home"|"smoke"|"snap"|"blast", "cell", "day"} (a blast is a bomber's nuke going off)
##   reveals    ground your parties uncovered, [[cell, day], ...]: it stays dark until the party gets there
##   sight_before   what the player could see when the season began (a band is shown while it was in sight then or is now)
##   end_day    the day the last unit stopped (settle() works it out)
##   walk       true for the walk of one of your parties (days counted from the start of that walk) rather than a season

const Data = preload("res://scripts/data.gd")

## Real seconds a whole season (Data.SEASON_DAYS) takes to play. A walk of half a season takes half as long.
const SECONDS := {"normal": 3.0, "fast": 1.2}
const POP_SECONDS := 0.7       # a flash or a puff of smoke lasts this long, whatever the speed
const BLAST_SECONDS := 2.8     # a nuke going off lasts this long, whatever the speed
const DUST_DAYS := 5.0         # how far behind a walking unit its dust trail reaches
const FADE_DAYS := 2.0         # a unit that leaves the map (home, wiped out) fades over this many days
const STILL := -2.0            # gone_day of a unit that stayed on the map
const AT_END := -1.0           # gone_day or event day meaning "when the walking is done"

static var mode := "normal"   # the game always plays the walk at normal speed (there is no setting for it any more); tests set "off" so they do not wait for it


static func seconds() -> float:
	return SECONDS.get(mode, 0.0)


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
	var tail := 0.0
	for e in r.events:
		tail = maxf(tail, BLAST_SECONDS if e.kind == "blast" else POP_SECONDS)
	return r.end_day / rate + tail


## How long a flash of this kind lasts, in real seconds.
static func pop_seconds(kind: String) -> float:
	return BLAST_SECONDS if kind == "blast" else POP_SECONDS
