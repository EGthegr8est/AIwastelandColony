extends SceneTree
## Bakes the building pictures of the clean look (art style 4) into art/building_atlas.png and art/building_atlas.json:
## one row of 8 x 8 pictures, drawn here as text rows you can nudge. Only the clean look uses them; the other styles keep
## drawing a building as its letter. A picture is see-through where it has no pixel, so the ground shows around it, and each
## has a dark outline so it stands apart from whatever ground it is on.
##
## Run from the project folder, then re-import:
##     godot --headless --path . -s res://tools/make_buildings.gd
##     godot --headless --path . --import
##
## Letters: k ink (outline), K dark brown, w white, W light grey, s stone, d dark grey, y gold, Y dark gold, o orange, r red,
## R dark red, t tan wood, T dark wood, g green, G dark green, b blue, B dark blue, c cyan, p purple, P dark purple.

const PNG := "res://art/building_atlas.png"
const JSON_FILE := "res://art/building_atlas.json"
const SIZE := 8

const PALETTE := {
	"k": "1c1511", "K": "3a2a1c", "w": "f2ecda", "W": "c8c4b8", "s": "8a8780", "d": "55524c",
	"y": "ffd27a", "Y": "b8862e", "o": "e8803a", "r": "d8442c", "R": "8a2a1c", "t": "b88c52", "T": "6e4a2a",
	"g": "6aa84a", "G": "3f7a35", "b": "5a94d0", "B": "34567e", "c": "70c8c8", "p": "b878e8", "P": "6a3d9a",
}

# In the order the file lists them: the keys are the building ids in Data.BUILDINGS
const SPRITES := {
	"hq": [
		"...kk...",
		"..kyyk..",
		".kyyyyk.",
		"kyyyYyyk",
		"kkkkkkkk",
		"ktkttktk",
		"ktkttktk",
		"kkkkkkkk"],
	"ai_hq": [
		"k..kk..k",
		"krkkkkrk",
		"krrrrrrk",
		"kRRRRRRk",
		"kRkRRkRk",
		"kRRkkRRk",
		"kRRkkRRk",
		"kkkkkkkk"],
	"town": [
		".bb..bb.",
		"bbbbbbbb",
		"kBBkkBBk",
		"kwwkkwwk",
		"kwkkkwkk",
		"kttkkttk",
		"kttkkttk",
		"kkkkkkkk"],
	"ai_wall": [
		"r.r.r.r.",
		"RrRrRrRr",
		"RRRRRRRR",
		"RdRdRdRd",
		"RRRRRRRR",
		"RdRdRdRd",
		"RRRRRRRR",
		"kkkkkkkk"],
	"farm": [
		"kkkkkkkk",
		"kg.g.g.k",
		"kGgGgGgk",
		"kyyyyyyk",
		"kYyYyYyk",
		"kyyyyyyk",
		"ktTtTtTk",
		"kkkkkkkk"],
	"lodge": [
		".w....w.",
		".kw..wk.",
		"..kttk..",
		".kttttk.",
		"kttttttk",
		"kTTttTTk",
		"kTkTTkTk",
		"kkkkkkkk"],
	"mine": [
		"..kkkk..",
		".kssssk.",
		"kssddssk",
		"ksdkkdsk",
		"ksdkkdsk",
		"ksdkkdsk",
		"kkkkkkkk",
		"........"],
	"salvage": [
		".....o..",
		"....o...",
		".kkkko..",
		"kdsdsdsk",
		"ksdsWdsk",
		"kdsodsdk",
		"ksdsdsok",
		"kkkkkkkk"],
	"refinery": [
		"...o....",
		"..oyo...",
		"..kyk...",
		".kkkkkk.",
		"kyyyyyyk",
		"kyYyyYyk",
		"kyyyyyyk",
		"kkkkkkkk"],
	"outpost": [
		"..ooo...",
		"..ook...",
		"..k.....",
		".kkkkk..",
		"..ktk...",
		"..ktk...",
		".kktkk..",
		"kkkkkkk."],
	"market": [
		"........",
		"wrwrwrwr",
		"rwrwrwrw",
		"kkkkkkkk",
		"kt.yy.tk",
		"kt.yy.tk",
		"kttttttk",
		"kkkkkkkk"],
	"wall": [
		"WW.WW.WW",
		"WWWWWWWW",
		"WdWdWdWd",
		"WWWWWWWW",
		"dWdWdWdW",
		"WWWWWWWW",
		"kkkkkkkk",
		"........"],
	"tower": [
		".s.ss.s.",
		".ssssss.",
		"..kssk..",
		"..ksWk..",
		"..kssk..",
		"..kdsk..",
		".kssssk.",
		"kkkkkkkk"],
	"keep": [
		"..s..s..",
		"..ssss..",
		"s.sWWs.s",
		"ssssssss",
		"sdsddsds",
		"sdskksds",
		"sdskksds",
		"kkkkkkkk"],
	"citadel": [
		"...yy...",
		"...kk...",
		"..kwwk..",
		".kwwwwk.",
		".kwWWwk.",
		"kwwWWwwk",
		"kwWwwWwk",
		"kkkkkkkk"],
	"drug_factory": [
		"..d..d.p",
		"..d..d..",
		".kdkkdk.",
		"kPPPPPPk",
		"kPpPPpPk",
		"kPPPPPPk",
		"kPpPPpPk",
		"kkkkkkkk"],
	"horse_farm": [
		"..kk....",
		".kttk...",
		"kttktkkk",
		"kttttttk",
		".kttttk.",
		".kt..tk.",
		".k....k.",
		"tttttttt"],
	"motor_pool": [
		"..kkkk..",
		".kddddk.",
		"kddddddk",
		"kdoooodk",
		"kdoWWodk",
		"kdoooodk",
		"kdoooodk",
		"kkkkkkkk"],
	"port": [
		"........",
		".....w..",
		"....www.",
		"...kkkk.",
		"bbbbbbbb",
		"BtBtBtBt",
		"tTtTtTtT",
		"kkkkkkkk"],
	"airfield": [
		"...w....",
		"..www...",
		".wwwww..",
		"...w....",
		"kkkkkkkk",
		"kdwddwdk",
		"kddddddk",
		"kkkkkkkk"],
	# the two bridges stand on river tiles, so the water shows at the sides; the planks run north to south, across the river
	"bridge": [
		".kttttk.",
		".kTTTTk.",
		".kttttk.",
		".kTTTTk.",
		".kttttk.",
		".kTTTTk.",
		".kttttk.",
		".kTTTTk."],
	"old_bridge": [
		".kddwdk.",
		".kddddk.",
		".kddwdk.",
		".kddddk.",
		".kddwdk.",
		".kddddk.",
		".kddwdk.",
		".kddddk."],
}


func _initialize() -> void:
	var names: Array = SPRITES.keys()
	var img := Image.create(SIZE * names.size(), SIZE, false, Image.FORMAT_RGBA8)
	var meta := {"sprite_size_px": SIZE, "sprites": {}}
	for n in names.size():
		var rows: Array = SPRITES[names[n]]
		assert(rows.size() == SIZE, "%s needs %d rows" % [names[n], SIZE])
		for y in SIZE:
			assert(rows[y].length() == SIZE, "%s row %d needs %d letters" % [names[n], y, SIZE])
			for x in SIZE:
				var ch: String = rows[y][x]
				if ch != ".":
					img.set_pixel(n * SIZE + x, y, Color("#" + PALETTE[ch]))
		meta.sprites[names[n]] = {"x": n * SIZE, "y": 0, "w": SIZE, "h": SIZE}
	img.save_png(PNG)
	var f := FileAccess.open(JSON_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("make_buildings: wrote ", img.get_size(), " with ", names.size(), " pictures")
	quit()
