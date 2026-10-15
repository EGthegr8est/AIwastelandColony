extends SceneTree
## Bakes the pixel-art look into art/atlas16.png and art/atlas16.json: one 16 x 16 picture for every ground, slope ledge, unit and
## tribe camp (26 of them, four to a row). The grounds and the two slope ledges are drawn here as text rows you can nudge, and so
## are the units and camps. The buildings are in make_buildings.gd.
##
## Run from the project folder (it works without Godot's editor, and can be run again any time):
##     godot --headless --path . -s res://tools/make_tiles16.gd
## then re-import so the game sees the new picture:   godot --headless --path . --import
##
## Each ground is a solid colour (every pixel of the tile is drawn) with one bold shape on it. The colours are the "dusk" look:
## the base colours darkened by DUSK and warmed. Letters in a ground's rows: a = dark shade, b = light shade, c = the deepest
## shade, d = the lightest, and for the things that glow (o = lit window, g = glow, h = glow centre) the colour is NOT darkened,
## so danger stands out from matte ground. A "." takes the ground's fill. Units and camps use the letters of UNIT_PALETTE, are
## see-through where they have no pixel and carry a dark outline (k), so they stand on any ground.

const PNG := "res://art/atlas16.png"
const JSON_FILE := "res://art/atlas16.json"
const SIZE := 16
const COLS := 4
const DUSK := 0.42
const WARM := Color(1.0, 0.97, 0.92)
const LIT := ["o", "g", "h"]

# The order of the pictures in the atlas, four to a row
const ORDER := ["ash_sand", "boat", "bomber", "builder_camp", "caravan", "crater", "dead_scrub", "dunes", "fallout_waste", "ford",
	"fused_glass", "gentle_slope", "green_grove", "petrified_wood", "raider_band", "raider_camp", "recon_plane", "river", "rock", "ruins",
	"scavenger", "scorched_ash", "scout", "steep_incline", "trader_camp", "war_rig"]

const LEGENDS := {
	"ash_sand": ["Ash sand", "terrain"], "boat": ["Boat", "unit"], "bomber": ["Bomber", "unit"], "builder_camp": ["Builder tribe camp", "unit"],
	"caravan": ["Trade caravan", "unit"], "crater": ["Glowing crater", "terrain"], "dead_scrub": ["Dead scrub", "terrain"],
	"dunes": ["Dunes", "terrain"], "fallout_waste": ["Fallout waste", "terrain"], "ford": ["Shallow ford", "terrain"],
	"fused_glass": ["Fused glass", "terrain"], "gentle_slope": ["Gentle slope", "overlay"], "green_grove": ["Green grove", "terrain"],
	"petrified_wood": ["Petrified wood", "terrain"], "raider_band": ["Raider band", "unit"], "raider_camp": ["Raider tribe camp", "unit"],
	"recon_plane": ["Recon plane", "unit"], "river": ["Murky river", "terrain"], "rock": ["Rock", "terrain"],
	"ruins": ["Pre-war ruins", "terrain"], "scavenger": ["Scavenger party", "unit"], "scorched_ash": ["Scorched ash sand", "terrain"],
	"scout": ["Scouting party", "unit"], "steep_incline": ["Steep incline", "overlay"], "trader_camp": ["Trader tribe camp", "unit"],
	"war_rig": ["War rig", "unit"],
}

# fill, and the letters each ground's rows use
const GROUNDS := {
	"ash_sand":       {"fill": "cdb98e", "a": "b39c70", "b": "e3d5b3", "c": "a4a07a", "d": "ede2c6"},
	"dunes":          {"fill": "e2bf7c", "a": "bd8f4c", "b": "f3dca6", "c": "9a6f38", "d": "fbeabd"},
	"dead_scrub":     {"fill": "8e9552", "a": "656c34", "b": "b4ba76", "c": "4a5126", "d": "cfd49a"},
	"petrified_wood": {"fill": "5b4a34", "a": "3d3022", "b": "9a784b", "c": "2a2116", "d": "c29a62"},
	"green_grove":    {"fill": "3f8a45", "a": "2a6030", "b": "86d474", "c": "1d4624", "d": "b6ee9f"},
	"rock":           {"fill": "8d939e", "a": "5c626e", "b": "c8cdd8", "c": "42464f", "d": "e6e9f2"},
	"ruins":          {"fill": "4d5059", "a": "30333b", "b": "737885", "c": "1f2127", "d": "8f94a3", "o": "ee8a3c"},
	"crater":         {"fill": "1a3210", "a": "10200a", "g": "7cfc00", "h": "caff7e", "dark_fill": true},
	"fused_glass":    {"fill": "5f45a8", "a": "43307a", "b": "ac92ea", "c": "2f2058", "d": "d4c4ff", "lit_b": true},
	"fallout_waste":  {"fill": "484b1d", "a": "33360f", "b": "ebe55e", "c": "23250a", "d": "fffaa0", "lit_b": true},
	"river":          {"fill": "2c6f8c", "a": "1d5570", "b": "74bdd4", "c": "144a60", "d": "b4e2f0"},
	"ford":           {"fill": "3f8fa8", "a": "2b6f86", "b": "8ccbd8", "c": "1d5a70", "d": "e8f2ec", "s": "d9c79a"},
	# the ground a blast leaves: its colours are final (no dusk), flecks of fallout glow in it
	"scorched_ash":   {"fill": "4c4843", "a": "2b2826", "b": "9e998e", "g": "c6ea3d", "raw": true},
}

const ROWS := {
	"ash_sand": [
		"................",
		"..b........a....",
		".....b..........",
		"...a..........b.",
		"........b.......",
		"..............a.",
		".b..a...........",
		"..........b.....",
		"....b...........",
		".a.........a..b.",
		"........a.......",
		"..b.............",
		".......b....a...",
		"a.....b.........",
		"...a......b..b..",
		"..........a....."],
	"dunes": [
		"................",
		"..dddd..........",
		".d....dd........",
		"d......ddd......",
		"........bb.d....",
		"..........bb....",
		"..aaaa..........",
		".a....aa........",
		"a......aaa..bbb.",
		"........cc.b...b",
		".....d..........",
		"...dddd.....aaaa",
		"..d....dd..a....",
		".a.....aaa.a....",
		"...aaaa...c.....",
		"................"],
	"dead_scrub": [
		"................",
		"......c.....a...",
		"...a..c..a..a...",
		"...a.ac.aa.a....",
		"....a.c.a.a.....",
		".....aca.a......",
		"......c.........",
		"..a...c...b.....",
		"...a..c..a......",
		"..a.a.c.a.......",
		"...a.ca.a....b..",
		"....aca.a.......",
		".....c.a...b.b..",
		".b...c..........",
		"......c....b....",
		"................"],
	"petrified_wood": [
		"................",
		"..d...d...d.....",
		"..db..db..d.b...",
		"..bb..bb..bb....",
		"..b...bb..b.....",
		"..b...b...b.....",
		"..b..ab..ab.....",
		"..b..aa..aa.....",
		"..a..aa..aa.....",
		"..a..ac..ac.....",
		".aaa.aaa.aaa....",
		".ccc.ccc.ccc....",
		"................",
		"...........b....",
		"..b.............",
		"................"],
	"green_grove": [
		"....dd....dd....",
		"...dbbd..dbbd...",
		"..dbbbbddbbbbd..",
		"..bbbbbbbbbbbb..",
		"..bbbabbbbabbb..",
		"...bbaabbaabb...",
		"....bbabbabb....",
		".....bb..bb.....",
		".....a....a.....",
		".....a....a.....",
		"..d.......c.....",
		"..bd..bd........",
		".dbbd.bbd...dd..",
		"dbbbbdbbbd.dbbd.",
		".......a........",
		"..........a....."],
	"rock": [
		"................",
		".......dd.......",
		"......dbbd......",
		".....dbbbbd.....",
		"....dbbbbbbd....",
		"....bbbbbbabb...",
		"...dbbbbbaaab...",
		"...bbbbbbaaaab..",
		"..bbbbbbaaaaab..",
		"..bbbbbaaaaaac..",
		".dbbbbaaaaaaacc.",
		".bbbbaaaaaaaacc.",
		".bbbaaaaaaaaccc.",
		"aaaaaaaaaaaccccc",
		"cccccccccccccccc",
		"................"],
	"ruins": [
		"................",
		"..bbbbb.........",
		"..baaaab........",
		"..baoaab........",
		"..baaaab........",
		"..baoaab...bb...",
		"..baaaab..baab..",
		"..baoaab..baoab.",
		"..baaaab..baaab.",
		"..baoaab..baaab.",
		"..baaaab..baoab.",
		".aaaaaaaaaaaaaa.",
		".aab.aaaaaab.aa.",
		"cccccccccccccccc",
		"................",
		"................"],
	"crater": [
		"................",
		"....gggggggg....",
		"...gggggggggg...",
		"..gg........gg..",
		".gg..........gg.",
		".gg...hhhh...gg.",
		".g...hhhhhh...g.",
		".g...hhhhhh...g.",
		".g...hhhhhh...g.",
		".g....hhhh....g.",
		".gg..........gg.",
		".gg..........gg.",
		"..gg........gg..",
		"...gggggggggg...",
		"....gggggggg....",
		"................"],
	"fused_glass": [
		"....d...........",
		"...dbb......d...",
		"...bbb.....dbb..",
		"..dbba.....bbba.",
		"..bbba.....bba..",
		"..bba.......aa..",
		"...aa.....d.....",
		"..........bb....",
		".d..b.....bba...",
		".bb.bb.....aa...",
		".bba.bb....b....",
		"..aa.bba..bb....",
		".....ba..dbba...",
		"..d..a....bba...",
		".dbb.......aa...",
		"..ba............"],
	"fallout_waste": [
		".b...b..b.......",
		"..d....b....b...",
		"b....b.....b.b.b",
		"....b.....b.....",
		"..b......b...b..",
		".....b..........",
		".b..........b...",
		"...b....b.b.....",
		"b.....b....b....",
		"..b...........b.",
		"....b.b.....b...",
		".b..........b...",
		"......b.b.......",
		"b....b.....b..b.",
		"...b..........b.",
		"b.....b...b....."],
	"river": [
		"................",
		"..bb..bbb.......",
		".b..bb....bb....",
		"b......b....bb..",
		"................",
		"...bb....bb.....",
		"..b..bb.b..bb...",
		"......b.....b...",
		"................",
		"bb.....b.bb.....",
		"..bb.bb....bb...",
		"....b......b....",
		"................",
		".....bb....bb...",
		"..bb..bb..b..b..",
		"................"],
	"ford": [
		"b..s..b...s...b.",
		".s....s..b...s..",
		"..b..b.....b..s.",
		"s...s..s..b.....",
		".b.s..b..s...b..",
		"...b.s....b..s..",
		"s..b.....s....b.",
		".b...bs....b....",
		"...s..b.s....s..",
		"b.....s...b..b..",
		"..s.b....s...s..",
		".s....b..b......",
		"...b.s....s..b..",
		"b..s....b.....s.",
		"..b....s...b.b..",
		".s..b..b........"],
	"scorched_ash": [
		"ab.a..a.a.a.a..a",
		"b...a....a...a.b",
		"....a..b..a.....",
		"a.a...a..a.a.b.a",
		"a..g....a....ab.",
		"a.b..a..a..b....",
		"..a..a.a....a..a",
		".a..b.a..a.a..a.",
		"..a...a...a....b",
		"a.b.a....g.a.a..",
		"...a..a.b.a...a.",
		"a..a.a....a.a...",
		".a....a.a..a..b.",
		"..b.a...a..a.a..",
		"a.a..a...b...a.g",
		"..a.a..a.a..a..."],
}

# The slope ledges are not solid: they are dark shades the map lays over any ground, along the tile's lower edge.
# Digits are how dark: 1 = light shade, 2 = medium, 3 = deep.
const LEDGES := {
	"gentle_slope": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"1111111111111111",
		"2222222222222222"],
	"steep_incline": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"...1.....1....1.",
		"..212...212..212",
		"2.2222.2.2222.22",
		"2222222222222222",
		"3333333333333333"],
}
const LEDGE_ALPHA := {"1": 0.25, "2": 0.45, "3": 0.65}

# Letters of the units' and camps' pictures: k is the ink outline, the rest are their own colours (not darkened)
const UNIT_PALETTE := {
	"k": "1c1511", "w": "f0f0f0", "W": "b8a888", "s": "707070", "S": "4a4846", "c": "7fe0c0", "C": "3a9a7e",
	"y": "f0c030", "Y": "b8862e", "o": "e08030", "O": "a85a1c", "r": "e03a30", "R": "8a2a1c", "b": "5aa0e0", "B": "34567e",
	"e": "e8e4d8", "d": "3a3733", "t": "b88c52", "T": "6e4a2a", "g": "c9e07a",
}

const UNITS := {
	"scavenger": [
		"................",
		"......kkkk......",
		".....kwwwwk.....",
		".....kwwwwk.....",
		"......kkkk......",
		".....kssssk.....",
		"..kkkkssssk.....",
		".kWWWkssssskk...",
		".kWWWkssssssk...",
		".kWWWkssssk.....",
		"..kkkkssssk.....",
		"......ksskk.....",
		".....kssksk.....",
		".....kssksk.....",
		"....kssk.kssk...",
		"....kkk...kkk..."],
	"scout": [
		"................",
		"......kkkk......",
		".....kccccck....",
		".....kccccck..kk",
		"......kkkk...kwk",
		"....kkcccckk.kwk",
		"...kcccccccckkwk",
		"..kccckccccck.k.",
		"..kcck.kccck....",
		"...kk..kcck.....",
		"......kcck......",
		".....kcckcck....",
		"....kcck.kcck...",
		"...kcck...kcck..",
		"...kkk.....kkk..",
		"................"],
	"caravan": [
		"................",
		"......kkkk......",
		"....kkyyyykk....",
		"...kyyyyyyyyk...",
		"..kyyyoooyyyyk..",
		"..kyyyoooyyyyk..",
		"..kyyyyyyyyyyk..",
		"..kkkkkkkkkkkk..",
		"..kooooooooook..",
		"..kOoOoOoOoOok..",
		"..kkkkkkkkkkkk..",
		"...kddk..kddk...",
		"..kdwwdkkdwwdk..",
		"..kdwwdkkdwwdk..",
		"...kddk..kddk...",
		"................"],
	"war_rig": [
		"................",
		"................",
		"................",
		"....kkkkkkkk.kk.",
		"...koooooook.ook",
		"..koooooooookook",
		"..kooooooooooook",
		"..kooooooooooook",
		"..kkkkkkkkkkkkk.",
		"..kwswwwwwwswwk.",
		"..kkkkkkkkkkkkk.",
		"...kdsdk..kdsdk.",
		"..kdsssdkkdsssdk",
		"..kdsssdkkdsssdk",
		"...kdddk..kdddk.",
		"................"],
	"boat": [
		"................",
		".......kk.......",
		"......kwwk......",
		"......kwwwk.....",
		".....kwwwwk.....",
		".....kwwwwwk....",
		"....kwwwwwwk....",
		".....kkkkkk.....",
		"..kkkkkkkkkkkk..",
		".kbbbbbbbbbbbbk.",
		".kbbbbbbbbbbbbk.",
		"..kBbbbbbbbbBk..",
		"...kkBBBBBBkk...",
		".....kkkkkk.....",
		"................",
		"................"],
	"recon_plane": [
		"................",
		".......kk.......",
		"......kwwk......",
		"......kwwk......",
		"......kwwk......",
		"kkkkkkkwwkkkkkkk",
		"kwwwwwwwwwwwwwwk",
		".kwwwwwwwwwwwwk.",
		"..kkkkkwwkkkkk..",
		"......kwwk......",
		"......kwwk......",
		".....kwwwwk.....",
		"....kkkwwkkk....",
		"....kwwwwwwk....",
		".....kkkkkk.....",
		"................"],
	"bomber": [
		"................",
		".......kk.......",
		"......krrk......",
		"......krrk......",
		".....krRRrk.....",
		"....kkrRRrkk....",
		"kkkkrrrRRrrrkkkk",
		"krrrrRRRRRRrrrrk",
		"kRRRRRReeRRRRRRk",
		".kkkkkReeRkkkkk.",
		"......kRRk......",
		".....krRRrk.....",
		"....kkrRRrkk....",
		"...krrrRRrrrk...",
		"...kkkkkkkkkk...",
		"................"],
	"raider_band": [
		"................",
		"....kkkkkkkk....",
		"...kwwwwwwwwk...",
		"..kwwwwwwwwwwk..",
		"..kwwwwwwwwwwk..",
		"..kwrrrwwrrrwk..",
		"..kwrrrwwrrrwk..",
		"..kwwrrwwrrwwk..",
		"..kwwwwkkwwwwk..",
		"...kwwwkkwwwk...",
		"....kwwwwwwk....",
		"....kwkwkwkwk...",
		"....kwkwkwkwk...",
		".....kkkkkkk....",
		"................",
		"................"],
	"raider_camp": [
		"................",
		"......krk.......",
		"......krrk......",
		".......krrk.....",
		".......kk.......",
		".......kk.......",
		".....kkrrkk.....",
		"....krrrrrrk....",
		"...krrrrrrrrk...",
		"..krrrrRRrrrrk..",
		".krrrrrRRrrrrrk.",
		"krrrrrrRRrrrrrrk",
		"krrrrrkddkrrrrrk",
		"krrrrkddddkrrrrk",
		"krrrrkddddkrrrrk",
		"kkkkkkkkkkkkkkkk"],
	"trader_camp": [
		"................",
		"................",
		".......kk.......",
		"......kyyk......",
		".....kyyyyk.....",
		"....kyyyyyyk....",
		"...kyyyyyyyyk...",
		"..kyyyyYYyyyyk..",
		".kyyyyyyYYyyyyyk",
		".kyyyyyyYYyyyyyk",
		"kyyyyyykddkyyyyk",
		"kyyyyykddddkyyyk",
		"kyyyyykddddkyyyk",
		"kkkkkkkddddkkkkk",
		"................",
		"................"],
	"builder_camp": [
		"................",
		"................",
		".......kk.......",
		"......kbbk......",
		".....kbbbbk.....",
		"....kbbbbbbk....",
		"...kbbbbbbbbk...",
		"..kbbbbBBbbbbk..",
		".kbbbbbbBBbbbbbk",
		".kbbbbbbBBbbbbbk",
		"kbbbbbbkddkbbbbk",
		"kbbbbbkddddkbbbk",
		"kbbbbbkddddkbbbk",
		"kkkkkkkddddkkkkk",
		"................",
		"................"],
}


func _initialize() -> void:
	var rows := (ORDER.size() + COLS - 1) / COLS
	var atlas := Image.create(SIZE * COLS, SIZE * rows, false, Image.FORMAT_RGBA8)
	var sprites := {}
	for i in ORDER.size():
		var name: String = ORDER[i]
		var pic := _picture(name)
		var at := Vector2i((i % COLS) * SIZE, (i / COLS) * SIZE)
		atlas.blit_rect(pic, Rect2i(0, 0, SIZE, SIZE), at)
		sprites[name] = {"legend": LEGENDS[name][0], "kind": LEGENDS[name][1], "x": at.x, "y": at.y, "w": SIZE, "h": SIZE}
	atlas.save_png(ProjectSettings.globalize_path(PNG))
	var f := FileAccess.open(JSON_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"sprite_size_px": SIZE, "sprites": sprites}, "  ", true))
	f.close()
	print("make_tiles16: wrote ", atlas.get_size(), " with ", sprites.size(), " sprites")
	quit()


## One sprite's picture: a ground, a slope ledge, or a unit or camp.
func _picture(sprite: String) -> Image:
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if GROUNDS.has(sprite):
		var look: Dictionary = GROUNDS[sprite]
		_check(sprite, ROWS[sprite])
		out.fill(_tone(look, "fill"))
		for y in SIZE:
			for x in SIZE:
				var ch: String = ROWS[sprite][y][x]
				if ch != "." and look.has(ch):
					out.set_pixel(x, y, _tone(look, ch))
	elif LEDGES.has(sprite):
		_check(sprite, LEDGES[sprite])
		for y in SIZE:
			for x in SIZE:
				var ch: String = LEDGES[sprite][y][x]
				if ch != ".":
					out.set_pixel(x, y, Color(0.04, 0.03, 0.02, LEDGE_ALPHA[ch]))
	else:
		_check(sprite, UNITS[sprite])
		for y in SIZE:
			for x in SIZE:
				var ch: String = UNITS[sprite][y][x]
				if ch != ".":
					out.set_pixel(x, y, Color("#" + UNIT_PALETTE[ch]))
	return out


func _check(sprite: String, rows: Array) -> void:
	if rows.size() != SIZE:
		push_error("make_tiles16: %s has %d rows, not %d" % [sprite, rows.size(), SIZE])
	for r in rows:
		if r.length() != SIZE:
			push_error("make_tiles16: %s has a row of %d characters, not %d: %s" % [sprite, r.length(), SIZE, r])


## A letter's colour in the dusk look: darkened and warmed, except the glowing letters (and a ground's lit shade).
func _tone(look: Dictionary, letter: String) -> Color:
	var c := Color("#" + look[letter])
	if look.get("raw", false):
		return c
	var lit: bool = letter in LIT or (letter == "b" and look.get("lit_b", false)) or (letter == "d" and look.get("lit_b", false)) or (letter == "fill" and look.get("dark_fill", false))
	return c if lit else c.darkened(DUSK) * WARM
