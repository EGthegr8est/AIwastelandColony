extends RefCounted
## Small pixel-art icons (16 x 16) for the ways a party travels: a boot, a horse, a war rig, a
## boat and a plane. Each is drawn from rows of letters, one per pixel, and turned into a texture
## on first use. Show them with nearest-neighbour filtering to keep the pixels crisp.

const SIZE := 16
const PALETTE := {
	"o": Color("1a1208"),                                   # outline
	"n": Color("b07a44"), "N": Color("74482a"), "m": Color("d8a468"),   # leather
	"s": Color("3a3028"),                                   # sole
	"g": Color("b8b8c4"), "G": Color("62626e"), "W": Color("d8d8e0"),   # steel
	"r": Color("e0502a"), "R": Color("8c2a16"), "y": Color("f0c030"),   # war rig paint, lamp
	"w": Color("f4ecd8"), "c": Color("8fd0ff"), "C": Color("3a7aa8"),   # glass, water
	"h": Color("d09050"), "H": Color("80502a"), "k": Color("2a1c10"),   # horse
	"b": Color("b88444"), "B": Color("70461e"),             # wood
	"a": Color("ece0c4"), "A": Color("b8a880"),             # sail
}

const ART := {
	"foot": [
		"................",
		"....oooooo......",
		"...onmmmmno.....",
		"...onmmmnNo.....",
		"...onmmnNNo.....",
		"...onmmnNNo.....",
		"...onmnNNNo.....",
		"...onmnNNNo.....",
		"...onnnNNNoooo..",
		"...onnnNNNnnnoo.",
		"...onnnNNNnnnnno",
		"..oonnnnNNNnnnno",
		".onnnnnnNNnnnnno",
		".onnnnnnnnnnnnno",
		".osssssssssssso.",
		"..oooooooooooo..",
	],
	"horse": [
		"................",
		"...........oo...",
		"..........ohHo..",
		"....ooo..ohhhHo.",
		"...okkkoohhhhhHo",
		"..okHHhhhhhhhooo",
		"..okHhhhhhhhho..",
		"...oHhhhhhhhHo..",
		"...ohhhhhhhhHo..",
		"...ohhhhhhhhHo..",
		"...oHHoHHHoHHo..",
		"...ohHo.ohHohHo.",
		"...ohHo.ohHohHo.",
		"...ohHo.ohHohHo.",
		"...okko.okkokko.",
		"................",
	],
	"car": [
		"................",
		"................",
		"...ooooooo......",
		"...oRrrrrRo.....",
		"..oRrwwwwrRooo..",
		"..oRrwwwwrRrrRo.",
		".ooRrrrrrrrrrrRo",
		"oyoRrrrrrrrrrrRo",
		"oyoRrrrrrrrrrrRo",
		".ooRRRRRRRRRRRRo",
		"..oGGGo...oGGGo.",
		".oGWWWGo.oGWWWGo",
		".oGWssGo.oGWssGo",
		".oGWWWGo.oGWWWGo",
		"..oGGGo...oGGGo.",
		"...ooo.....ooo..",
	],
	"boat": [
		".......o........",
		".......oo.......",
		".......oaao.....",
		"......oaaaao....",
		"......oaaaaao...",
		"......oaaaaaao..",
		"......oaaAAAAo..",
		".......obo......",
		".......obo......",
		"oooooooobooooooo",
		"oBbbbbbbbbbbbbBo",
		".oBbbbbbbbbbbBo.",
		"..oBBBBBBBBBBo..",
		"...oooooooooo...",
		"CcCcCcCcCcCcCcCc",
		"................",
	],
	"plane": [
		".......ww.......",
		"......owwo......",
		"......owwo......",
		"......oWWo......",
		"......oWWo......",
		"oo....oWWo....oo",
		"oWoooooWWoooooWo",
		"oWWWWWWWWWWWWWWo",
		".oooooooWWooooo.",
		"......oWWo......",
		"......oWWo......",
		".....oWWWWo.....",
		"....oWWWWWWo....",
		"....oooWWooo....",
		"........oo......",
		"................",
	],
}

static var _cache := {}


## The icon for a way of travel ("foot", "horse", "car", "boat" or "plane").
static func texture(mover: String) -> ImageTexture:
	if not _cache.has(mover):
		_cache[mover] = ImageTexture.create_from_image(image(mover))
	return _cache[mover]


static func image(mover: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rows: Array = ART[mover]
	for y in SIZE:
		for x in SIZE:
			var key: String = rows[y][x]
			if key != ".":
				img.set_pixel(x, y, PALETTE[key])
	return img
