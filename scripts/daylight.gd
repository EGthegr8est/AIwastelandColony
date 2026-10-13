extends RefCounted
## Day and night. Every season the map fades between daylight and moonlight, slowly (never a snap), so you notice the turn change.
## Spring and Autumn are day, Summer and Winter are night: the light follows the season number, so it needs nothing in a save.
## The rules live here, apart from the drawing (map_view.gd), the way season_replay.gd keeps the replay's rules. It is looks only:
## nothing in the game's rules reads it.
##
## `light` runs from 1.0 (full day) to 0.0 (full night). At night:
##   - the ground and buildings are multiplied by a moon-blue (ground()), dark but readable;
##   - wild animals and enemy parties take part of that dimness (things()) and never glow, except an enemy party standing in ruins,
##     which is lit by them;
##   - your own parties carry a small, dim glow (HALOS.party) and keep their colours;
##   - what glows stays at full brightness with a halo: craters, ruins that raiders hold, the camps your units can see (and fallout waste and
##     fused glass, which keep their bright speckles without a halo).

const SeasonReplay = preload("res://scripts/season_replay.gd")

## What a pixel of ground is multiplied by at full night.
const NIGHT := Color(0.30, 0.36, 0.58)
## How much of that dimming a wild animal or an enemy party takes (1.0 would be as dark as the ground): they stay easy to see.
const THINGS_SHARE := 0.65
## A remembered glowing tile (out of sight) glows this much as one you can see, matching how remembered ground is dimmed.
const REMEMBERED_GLOW := 0.4
## How far the halo of a glowing tile reaches (in tiles), its color and how strongly it shows at full night.
const HALOS := {
	"crater":  {"color": Color("7cfc00"), "radius": 2.0, "alpha": 0.55},
	"ruins":   {"color": Color("ee8a3c"), "radius": 1.9, "alpha": 0.55},
	"raider":  {"color": Color("ff6a3c"), "radius": 2.1, "alpha": 0.60},
	"trader":  {"color": Color("ffd060"), "radius": 2.1, "alpha": 0.60},
	"builder": {"color": Color("8fc8ff"), "radius": 2.1, "alpha": 0.60},
	"party":   {"color": Color("ffe0a0"), "radius": 1.25, "alpha": 0.30},
}
const SETTINGS_SECTION := "display"
const SETTINGS_KEY := "night"

## The Night: on / off switch. Off keeps it day all the time.
static var enabled := true


static func is_day(season: int) -> bool:
	return season % 2 == 1


## The word the top bar shows after the season's name.
static func word(season: int) -> String:
	return "day" if is_day(season) else "night"


## The light a season ends up with: 1 for day, 0 for night, and always 1 with the switch off.
static func target_light(season: int) -> float:
	if not enabled:
		return 1.0
	return 1.0 if is_day(season) else 0.0


## Real seconds the turn change takes to fade: as long as the season replay takes on Normal, and the Fast length on Fast or Off.
static func fade_seconds() -> float:
	return SeasonReplay.SECONDS.get(SeasonReplay.mode, SeasonReplay.SECONDS["fast"])


## What the ground is multiplied by when the light is `light`.
static func ground(light: float) -> Color:
	return NIGHT.lerp(Color.WHITE, clampf(light, 0.0, 1.0))


## What a wild animal or an enemy party is multiplied by: part of the ground's dimming.
static func things(light: float) -> Color:
	return Color.WHITE.lerp(ground(light), THINGS_SHARE)


## How dark it is, 0 (day) to 1 (night). Halos show this strongly.
static func darkness(light: float) -> float:
	return 1.0 - clampf(light, 0.0, 1.0)


## A slow, gentle flicker for a halo (about 0.88 to 1.0), different for each `seed` (a tile or a camp), so fires do not pulse together.
static func flicker(seconds: float, seed_value: int) -> float:
	return 0.94 + 0.06 * sin(seconds * 5.3 + seed_value * 1.7) + 0.03 * sin(seconds * 11.1 + seed_value * 0.9)


## The halo for a glowing thing: "crater", "ruins", a camp's class ("raider", "trader", "builder") or "party". {} for anything else.
static func halo(kind: String) -> Dictionary:
	return HALOS.get(kind, {})


static func load_setting() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Music.settings_path) != OK or not cfg.has_section_key(SETTINGS_SECTION, SETTINGS_KEY):
		return
	enabled = bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY))


static func save_setting() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Music.settings_path)   # keep anything else in there
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, enabled)
	cfg.save(Music.settings_path)


static func set_enabled(on: bool) -> void:
	enabled = on
	save_setting()
