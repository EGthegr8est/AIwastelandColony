extends SceneTree
## Bakes the four 32 x 32 unit pictures into art/units32.png: the scavenger party, the scouting party, the war rig and the troop
## marker (a hunting party), drawn at twice the pixel detail of the 16 x 16 atlas and shown in the same one-tile space.
## The pictures are text rows you can nudge, in the letters of make_tiles16.gd's UNIT_PALETTE (k is the ink outline) plus
## G, n, u for the troops' greens and the scouts' deep teal. Run from the project folder, then re-import:
##     godot --headless --path . -s res://tools/make_units32.gd
##     godot --headless --path . --import

const PNG := "res://art/units32.png"
const SIZE := 32
const ORDER := ["scavenger", "scout", "war_rig", "soldier", "band"]   # left to right; Sprites.UNITS32 names the same order
const PALETTE := {
	"k": "1c1511", "w": "f0f0f0", "W": "b8a888", "s": "707070", "S": "4a4846", "c": "7fe0c0", "C": "3a9a7e",
	"y": "f0c030", "Y": "b8862e", "o": "e08030", "O": "a85a1c", "r": "e03a30", "R": "8a2a1c", "b": "5aa0e0", "B": "34567e",
	"e": "e8e4d8", "d": "3a3733", "t": "b88c52", "T": "6e4a2a", "g": "c9e07a", "G": "7d9a3c", "n": "1d2814", "u": "256b58",
}

## The scout, the troop and the raider band are the scavenger's picture in other colours: each letter of the scavenger's rows is
## swapped for the one listed here (letters not listed stay as they are).
const RECOLORS := {
	"scout": {"W": "c", "s": "C", "S": "u", "o": "r", "O": "R", "t": "W", "Y": "w"},
	"soldier": {"W": "g", "s": "G", "S": "n", "o": "W", "O": "Y", "b": "y", "t": "Y"},
	"band": {"W": "R", "s": "S", "S": "d", "o": "r", "O": "R", "b": "r", "t": "Y", "e": "t"},
}

const UNITS := {
	"scavenger": [
		"................................",
		"...............kkkkk............",
		"..............kWWWWWk...........",
		".............kWWWWWWWk..........",
		"............kWWWWWWWWWkk........",
		"...........kWWWWWWWSSSSSk.......",
		"...........kdddddddSbwbSk.......",
		"...........kdddddddSbbbSkkkk....",
		"....kkkkkkkkWWWWWWWeeeeekYYYk...",
		"...kOoooooooWWWWWWWwwwwekYYYk...",
		"...kOoooooooOWWWWWWwwwwekkTk....",
		"...kOOOOOOOOOkWWWWWWWkkk.kTk....",
		"...kOOOOOOOOoooooooooook.kTk....",
		"....kttWWWWWoooooooooookkkTk....",
		"....kttWWWWWswwwssssssssskTk....",
		"....kttWTTWWswwwssssssssskTk....",
		"....kttWTTWWswwwssssssssskTk....",
		"....kttWTTWWswwwssssssssskTk....",
		"....kYtWTTWWssssssssssssskTk....",
		"...kYYYWTTWWddddddddddseeeTk....",
		"...kYYYWTTWWssssssssssseeeTk....",
		"...kYYYWTTWWssssssssssskkTk.....",
		"....kYtWTTWWSSSSSSSSSSSkkTk.....",
		"....kttWTTWWSSSSSSSSSSSkkTk.....",
		"....kttWWWWWSSSSSSSSSSSkkTk.....",
		".....kkkkkkkSSSSSSSSSSSkkTk.....",
		"............kSSSSkkSSSSkkTk.....",
		"............kSSSSkkSSSSkkTk.....",
		"............kSSSSkkSSSSkkTk.....",
		"...........kdddddkkddddddTk.....",
		"...........kddddddkkkkkkkTk.....",
		"............kkkkkk......kTk....."],
	"war_rig": [
		"................................",
		"................................",
		"................k...............",
		"kk............kkwk..............",
		"eek.........kkssk...............",
		"eek.......kksskk................",
		"kSSk.....kSsSSk..kkkkkkkkkkk....",
		"kSSk.....kSSSSk.koooooooooook...",
		"kSSk.....kSSSSk.kooBBBBBBBBok...",
		"kSSkkkkkkkSSSSkkkooBbbbbbbBok...",
		"kSSOoooooooooooOkooBbbbbbbBok...",
		"kSSOoooooooooooOkooBbbbbbbBok...",
		"kSSdddddddddddddkooBBBBBBBBok...",
		"kSSOOOOOOOOOOOOOkOOOOOOOOOOOk...",
		"kSSOOOOOOOOOOOOOkOOOOOOOOOOOkkkk",
		"kSSoooooooooooooooooooooooooosss",
		".kooooooooooooooooooooooooooyssk",
		".kooooooooooooooooooooooooooyssk",
		".kooooooooooooooooooooooooooossk",
		".kOOOOOOOOOOOOOOOOOOOOOOOOOOOsss",
		".kdddddddddddddddddddddddddddssk",
		".kOOOOOOOOOOOOOOOOOOOOOOOOOOOssk",
		".kOOOOOOOOOOOOOOOOOOOOOOOOOOOSSk",
		"..kddddsssddddkkkkddddsssddddsss",
		"..kdddsssssdddk..kdddsssssdddssk",
		"..kdddsswssdddk..kdddsswssdddkk.",
		"..kdddsssssdddk..kdddsssssdddk..",
		"..kddddsssddddk..kddddsssddddk..",
		"...kdddddddddk....kdddddddddk...",
		"....kdddddddk......kdddddddk....",
		".....kdddddk........kdddddk.....",
		"......kkkkk..........kkkkk......"],
}


func _init() -> void:
	var img := Image.create(SIZE * ORDER.size(), SIZE, false, Image.FORMAT_RGBA8)
	for i in ORDER.size():
		var rows: Array = UNITS[ORDER[i]] if UNITS.has(ORDER[i]) else _recolor(UNITS["scavenger"], RECOLORS[ORDER[i]])
		assert(rows.size() == SIZE, "%s needs %d rows" % [ORDER[i], SIZE])
		for y in SIZE:
			assert(rows[y].length() == SIZE, "%s row %d needs %d columns" % [ORDER[i], y, SIZE])
			for x in SIZE:
				var ch: String = rows[y][x]
				if ch != ".":
					img.set_pixel(i * SIZE + x, y, Color(PALETTE[ch]))
	img.save_png(ProjectSettings.globalize_path(PNG))
	print("wrote %s (%d pictures)" % [PNG, ORDER.size()])
	quit()


func _recolor(rows: Array, swap: Dictionary) -> Array:
	return rows.map(func(row: String) -> String:
		var out := ""
		for ch in row:
			out += swap.get(ch, ch)
		return out)
