extends RefCounted
## Pixel-art portraits for survivors, drawn in code. Every face comes from a seed, so the same
## survivor always looks the same. The look is a StarCraft unit portrait: a lit 3/4 face with a
## handful of shades per material, ordered dithering where the shades meet, and a colored rim
## light on the shadowed side. Age greys the hair and adds lines. Hunger hollows the cheeks, and
## radiation sickness turns the skin a sickly green and sinks the eyes.
##
## Everything is laid out on a 32 x 40 grid of "units" and drawn at K pixels per unit, so a bigger
## K just means a finer portrait (and the shown size, SHOW_SCALE, may need to come down).

const K := 1.5
const W := 48                  # 32 units
const H := 60                  # 40 units
const SHOW_SCALE := 2          # how many screen pixels each portrait pixel gets
const BG := Color("0b0b19")
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const SKIN := [Color("e8b890"), Color("d49c70"), Color("c28a5c"), Color("a46c44"), Color("7e4e30"), Color("573522")]
const HAIR := [Color("1a1620"), Color("36241a"), Color("5e3c24"), Color("8f5a2c"), Color("c8a45a"), Color("a8a8ae"), Color("6e2e22")]
const GREY := 5
const DYE := [Color("38d848"), Color("e0403c"), Color("38a8e8"), Color("d848d8")]
const CLOTH := [Color("6a4a2c"), Color("4e5e3c"), Color("5c5c66"), Color("7c3c2e"), Color("3c4c66"), Color("8a7a58")]
const EYES := [Color("2a1a10"), Color("2a4a6e"), Color("2e5e2e"), Color("6a5a1e")]
# Rim light, dark to bright: toxic green most of the time, sometimes ember or cold blue
const RIMS := [
	[Color("14602a"), Color("28c43a"), Color("88ff66")],
	[Color("6a2410"), Color("e0602a"), Color("ffb060")],
	[Color("14506a"), Color("2aa8d8"), Color("88e8ff")],
]
const STYLES := ["bald", "buzz", "short", "short", "swept", "swept", "mohawk", "long", "wrap"]
const KEY_LIGHT := Vector3(0.8, -0.45, 0.42)

static var _cache := {}


## The portrait as a texture for a TextureRect (use nearest filtering to keep the pixels crisp).
static func texture(face: int, age: int, hunger: int, sick := 0, hurt := false) -> ImageTexture:
	var key := "%d:%d:%d:%d:%d" % [face, age, mini(hunger, 2), mini(sick, 3), 1 if hurt else 0]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(image(face, age, hunger, sick, hurt))
	return _cache[key]


## `sick` is the radiation sickness level, 0 (healthy) to 3 (critical). `hurt` bandages the head
## (a crash survivor, until they heal).
static func image(face: int, age: int, hunger: int, sick := 0, hurt := false) -> Image:
	var hungry := mini(hunger, 2)
	var ill := mini(sick, 3)
	var gaunt := hungry + 0.5 * ill   # how hollow the face looks
	var rng := RandomNumberGenerator.new()
	rng.seed = face
	# Everything about the face is rolled up front, in a fixed order, so branches below can't
	# change who comes out.
	var skin_base: Color = SKIN[rng.randi() % SKIN.size()]
	var rx := rng.randf_range(8.2, 10.0)
	var ry := rng.randf_range(11.0, 12.2)
	var jaw_p := rng.randf_range(2.8, 4.6)
	var yaw := rng.randf_range(2.0, 3.4)
	var heavy_brow := rng.randf() < 0.45
	var style: String = STYLES[rng.randi() % STYLES.size()]
	var hair_col: Color = HAIR[rng.randi() % HAIR.size()]
	var dye_roll := rng.randf()
	var dye_col: Color = DYE[rng.randi() % DYE.size()]
	var grey_roll := rng.randf()
	var beard_kind := rng.randi() % 6   # 0-2 clean, 3 stubble, 4 mustache, 5 full beard
	var eye_col: Color = EYES[rng.randi() % EYES.size()]
	var mouth_w := rng.randf_range(5.0, 7.0)
	var cloth_col: Color = CLOTH[rng.randi() % CLOTH.size()]
	var kind := rng.randi() % 3   # 0 bare chest with a strap, 1 jacket, 2 scrap armor
	var goggles := rng.randf() < 0.16
	var scar := rng.randf() < 0.2
	var rim: Array = RIMS[0 if rng.randf() < 0.6 else rng.randi_range(1, 2)]
	var face_right := rng.randf() < 0.5

	if dye_roll < 0.1:
		hair_col = dye_col
	elif age >= 40 and grey_roll < 0.25 + (age - 40) * 0.03:
		hair_col = HAIR[GREY]
	skin_base = skin_base.lerp(Color("8c8c82"), 0.16 * hungry).darkened(0.06 * hungry)
	skin_base = skin_base.lerp(Color("8ca85a"), 0.2 * ill)

	var skin := _ramp(skin_base, 6)
	var hair := _ramp(hair_col, 4)
	var cloth := _ramp(cloth_col, 4)
	var leather := _ramp(Color("6a4428"), 4)
	var pix := PackedColorArray()
	pix.resize(W * H)
	pix.fill(BG)
	var solid := PackedByteArray()
	solid.resize(W * H)
	var cx := 16.0
	var cy := 17.0
	var fx := cx - yaw            # the middle line of the face, turned toward the left
	var ey := cy - 1.0            # eye row
	var nose_y := cy + 4.0
	var mouth_y := cy + 8.0
	var key := KEY_LIGHT.normalized()
	var hl_py := -ry * 0.36       # hairline, relative to the middle of the head

	# ---- long hair hangs behind the head and over the shoulders
	if style == "long":
		for y in H:
			var v := (y + 0.5) / K
			if v < cy - ry * 0.4 or v > cy + ry + 8.0:
				continue
			for x in W:
				var px := (x + 0.5) / K - cx
				var half := rx + 3.6 - maxf(0.0, v - (cy + ry - 3.0)) * 0.22
				if absf(px) <= half and v > cy - ry * 0.4 + absf(px) * 0.1:
					var lit := 0.25 + 0.55 * clampf(0.5 + px / half * 0.5, 0.0, 1.0)
					lit += 0.1 * sin(x * 1.3 + _noise(x / 3, 2, face) * 4.0)
					_put(pix, solid, x, y, hair[_level(lit, 4, x, y)])

	# ---- shoulders and chest
	for y in H:
		var v := (y + 0.5) / K
		if v < 30.0:
			continue
		var sw := minf(6.0 + (v - 30.0) * 2.6, 15.9)
		for x in W:
			var u := (x + 0.5) / K
			var px := u - cx
			if absf(px - 0.5) > sw:
				continue
			var nx := clampf((px - 1.0) / 17.0, -1.0, 1.0)
			var lit := (0.06 + 0.95 * clampf(nx * key.x + sqrt(1.0 - nx * nx) * key.z, 0.0, 1.0)) * 0.82
			var in_neck := absf(px - 0.5) < 5.4 - (v - 30.0) * 0.5
			var c: Color
			if kind == 0:
				var s := lit - (0.14 if absf(px) < 0.9 and v > 33.0 else 0.0)
				c = skin[_level(s * 0.8, 6, x, y)]
				# a strap across the chest, up toward the left shoulder
				if absf(v - (35.0 + (cx + 8.0 - u) * 0.5)) < 1.7:
					c = leather[_level(lit + 0.05, 4, x, y)]
			elif kind == 1:
				c = cloth[_level(lit, 4, x, y)]
				if in_neck and v < 35.0:
					c = skin[_level(lit * 0.55, 6, x, y)]
				elif absf(px - 0.5) < 8.2 and v < 34.0 and absf(px - 0.5) > 4.6 - (v - 30.0) * 0.3:
					c = cloth[mini(_level(lit + 0.28, 4, x, y), 3)]   # the collar
				if absf(px - 0.5) < 0.5 and v >= 35.0:
					c = cloth[0]   # zip
			else:
				c = cloth[_level(lit * 0.9, 4, x, y)]
				if in_neck and v < 34.0:
					c = skin[_level(lit * 0.5, 6, x, y)]
				# a scrap plate over the lit shoulder
				var pd := pow((px - 9.0) / 6.5, 2.0) + pow((v - 34.0) / 3.6, 2.0)
				if pd <= 1.0:
					c = cloth[_level(lit + 0.35 - pd * 0.3, 4, x, y)]
					if pd > 0.78:
						c = cloth[0]
					elif absf(px - 9.0) < 0.5 and absf(v - 34.0) < 0.5:
						c = Color("e8e0c8")   # a rivet
			_put(pix, solid, x, y, c)

	# ---- neck, dark under the jaw
	for y in H:
		var v := (y + 0.5) / K
		if v < cy + ry * 0.45 or v > 32.0:
			continue
		for x in W:
			var px := (x + 0.5) / K - cx - 0.5
			if absf(px) > 4.6:
				continue
			var nx := px / 4.6
			var lit := 0.05 + 0.7 * clampf(0.5 + nx * 0.5, 0.0, 1.0)
			var below_jaw := clampf((v - (cy + ry - 4.0)) / 8.0, 0.0, 1.0)
			_put(pix, solid, x, y, skin[_level(lit * (0.22 + 0.6 * below_jaw), 6, x, y)])

	# ---- the head
	var eyes := [Vector2(fx + 4.0, ey + 0.5), Vector2(fx - 3.2, ey + 0.5)]   # near, far
	for y in H:
		var v := (y + 0.5) / K
		var t := (v - cy) / ry
		if absf(t) > 1.0:
			continue
		var half := rx * (sqrt(1.0 - t * t) if t <= 0.0 else sqrt(1.0 - pow(t, jaw_p)))
		for x in W:
			var u := (x + 0.5) / K
			var px := u - cx
			if absf(px) > half:
				continue
			var nx := clampf(px / rx, -1.0, 1.0)
			var ny := t * 0.9
			var nz := sqrt(maxf(0.03, 1.0 - nx * nx * 0.85 - ny * ny * 0.4))
			var shade := pow(0.1 + 0.95 * clampf(Vector3(nx, ny, nz).normalized().dot(key), 0.0, 1.0), 1.3)
			# eye sockets and the brow above them
			for e in eyes:
				var d := pow((u - e.x) / 3.4, 2.0) + pow((v - e.y) / 2.5, 2.0)
				shade -= (0.3 + 0.12 * gaunt) * exp(-d)
			if v > ey - 3.6 and v < ey - 0.6 and absf(u - fx) < 9.0:
				shade -= 0.17 if heavy_brow else 0.08
			# forehead and cheek highlights, hollows when hungry
			shade += 0.12 * exp(-(pow((u - fx - 3.0) / 5.0, 2.0) + pow((v - cy + 7.0) / 3.5, 2.0)))
			shade += 0.1 * exp(-(pow((u - fx - 5.0) / 3.5, 2.0) + pow((v - cy - 3.0) / 3.0, 2.0)))
			shade -= 0.16 * gaunt * exp(-(pow((u - fx - 5.5) / 3.0, 2.0) + pow((v - cy - 6.0) / 3.5, 2.0)))
			shade -= 0.16 * gaunt * exp(-(pow((u - fx + 5.0) / 3.0, 2.0) + pow((v - cy - 6.0) / 3.5, 2.0)))
			# the nose: shadow on its far side, a bright ridge on the near side
			if v >= ey and v <= nose_y + 0.5:
				if absf(u - (fx - 1.2)) < 0.7:
					shade -= 0.2
				elif absf(u - (fx + 1.6)) < 0.7:
					shade += 0.1
			if v > nose_y + 0.5 and v <= nose_y + 2.5 and absf(u - fx) < 3.4:
				shade -= 0.24
			if v >= mouth_y + 2.0 and v <= mouth_y + 4.0 and absf(u - fx) < 3.0:
				shade -= 0.14
			shade += 0.08 * exp(-(pow((u - fx - 1.5) / 2.5, 2.0) + pow((v - cy - ry + 2.5) / 2.0, 2.0)))
			_put(pix, solid, x, y, skin[_level(shade, 6, x, y)])

	# ---- the near ear, on the back of the head
	var ear_x := cx + rx - 0.8
	_fill(pix, solid, ear_x, ey - 1.0, ear_x + 2.0, ey + 4.0, skin[3])
	_fill(pix, solid, ear_x + 2.0, ey, ear_x + 3.0, ey + 3.0, skin[2])
	_fill(pix, solid, ear_x + 0.8, ey + 0.8, ear_x + 1.8, ey + 2.4, skin[1])

	# ---- wrinkles and a scar
	if age >= 38:
		for i in 3:
			for dx in range(-3, 4, 2):
				_fill(pix, solid, fx + dx, cy - ry * 0.55 + i * 2.0, fx + dx + 1.0, cy - ry * 0.55 + i * 2.0 + 0.5, skin[2])
	if age >= 48:
		_fill(pix, solid, fx + 6.0, ey + 1.0, fx + 7.0, ey + 1.6, skin[1])
		_fill(pix, solid, fx + 7.0, ey + 2.0, fx + 8.0, ey + 2.6, skin[1])
		_fill(pix, solid, fx + 3.0, nose_y + 2.0, fx + 4.0, nose_y + 2.6, skin[1])
		_fill(pix, solid, fx + 4.0, nose_y + 3.0, fx + 5.0, nose_y + 3.6, skin[1])
	if scar:
		for i in 8:
			_fill(pix, solid, fx + 4.0 + i * 0.5, ey - 3.5 + i * 0.9, fx + 4.6 + i * 0.5, ey - 3.0 + i * 0.9, skin[5])
			_fill(pix, solid, fx + 4.6 + i * 0.5, ey - 3.5 + i * 0.9, fx + 5.0 + i * 0.5, ey - 3.0 + i * 0.9, skin[5] if i % 2 == 0 else skin[4])

	# ---- hair (the cap, in front of the face)
	for y in H:
		var v := (y + 0.5) / K
		var py := v - cy
		for x in W:
			var u := (x + 0.5) / K
			var px := u - cx
			var jitter := (_noise(x / 2, 3, face) - 0.5) * 1.6
			var inside := _in_ellipse(px, py, rx, ry)
			var covered := false
			match style:
				"short":
					covered = (_in_ellipse(px, py, rx + 1.3, ry + 1.4) and py < hl_py + jitter) \
						or (inside and px > rx * 0.55 and py < 1.0)
				"swept":
					covered = (_in_ellipse(px, py, rx + 1.8, ry + 2.6) and py < hl_py + px * 0.12 + jitter) \
						or (_in_ellipse(px, py, rx + 2.0, ry + 1.0) and px > rx * 0.3 and py < 2.0)
				"mohawk":
					covered = absf(px + 0.5) < 2.4 and py < 0.0 and py > -ry - 4.2 + 0.05 * px * px
				"long":
					covered = (_in_ellipse(px, py, rx + 1.4, ry + 1.6) and py < hl_py + jitter) \
						or (inside and absf(px) > rx * 0.82 and py < 3.0)
				"wrap":
					covered = _in_ellipse(px, py, rx + 1.2, ry + 1.4) and py < hl_py - 0.5 + px * 0.1
					# the knot at the back
					if px > rx - 0.5 and px < rx + 3.6 and absf(py - hl_py * 0.9) < 2.4 - (px - rx) * 0.5:
						covered = true
				"buzz":
					if inside and py < hl_py + jitter + 2.0:
						var thr: float = (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0
						if thr < 0.55:
							_put(pix, solid, x, y, hair[1] if thr < 0.3 else hair[2])
			if not covered:
				continue
			var ex := rx + (2.0 if style == "swept" else 1.3)
			var ny := clampf(py / (ry + 1.5), -1.0, 1.0)
			var nx := clampf(px / ex, -1.0, 1.0)
			var nz := sqrt(maxf(0.03, 1.0 - nx * nx * 0.85 - ny * ny * 0.4))
			var lit := 0.08 + 0.98 * clampf(Vector3(nx, ny, nz).normalized().dot(key), 0.0, 1.0)
			lit += (_noise(x * 3 + 1, 5, face) - 0.5) * 0.22 + 0.1 * sin(x * 1.3 + _noise(x / 2, 1, face) * 3.0)
			if style == "wrap":
				var c: Color = cloth[_level(lit, 4, x, y)]
				if absf(py - (hl_py - 0.5 + px * 0.1)) < 1.2 and px < rx:
					c = cloth[0]   # the band's lower edge
				_put(pix, solid, x, y, c)
			else:
				_put(pix, solid, x, y, hair[_level(lit, 4, x, y)])

	# ---- facial hair
	if beard_kind >= 3:
		for y in H:
			var v := (y + 0.5) / K
			var t := (v - cy) / ry
			if v < cy + 2.0 or t > 1.0:
				continue
			var half := rx * sqrt(1.0 - pow(maxf(t, 0.0), jaw_p))
			for x in W:
				var u := (x + 0.5) / K
				var px := u - cx
				if absf(px) > half - 0.4:
					continue
				var thr: float = (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0
				var in_mustache := v >= nose_y + 2.0 and v <= mouth_y - 0.5 and absf(u - fx - 0.5) < 4.2
				var in_jaw := v >= mouth_y - 0.5 and t > 0.1
				var lit := 0.3 + 0.5 * clampf(0.5 + px / rx * 0.5, 0.0, 1.0)
				match beard_kind:
					3:
						if (in_jaw or in_mustache) and thr < 0.5:
							_put(pix, solid, x, y, hair[1 if lit < 0.5 else 2])
					4:
						if in_mustache:
							_put(pix, solid, x, y, hair[_level(lit, 4, x, y)])
					5:
						if in_jaw or in_mustache:
							_put(pix, solid, x, y, hair[_level(lit - 0.1 * _noise(x, y, face), 4, x, y)])

	# ---- eyes, brows, nose and mouth
	var brow_col: Color = hair[1] if style != "bald" else skin[1]
	for i in eyes.size():
		var near := i == 0
		var w := 3.0 if near else 2.0
		var x0: float = eyes[i].x - 1.5
		_fill(pix, solid, x0, ey - 1.0, x0 + w, ey, skin[0])                                  # upper lid in shadow
		_fill(pix, solid, x0, ey, x0 + w, ey + 1.0, Color("e8e4d4") if near else Color("c8c4b4"))
		_fill(pix, solid, x0, ey, x0 + 1.0, ey + 1.0, eye_col)                                # iris, looking left
		if near:
			_fill(pix, solid, x0 + w - 1.0, ey, x0 + w, ey + 1.0, Color("9a968a"))
		_fill(pix, solid, x0, ey + 1.0, x0 + w, ey + 1.7, skin[1 if hungry > 0 or age >= 45 else 2])   # under the eye
		var brow_y := ey - (3.4 if heavy_brow else 2.6)
		_fill(pix, solid, x0 - 1.0, brow_y + 0.4, x0 + w + (1.0 if near else 0.0), brow_y + 1.4, brow_col)
	# nose tip and nostrils
	_fill(pix, solid, fx + 0.6, nose_y, fx + 1.6, nose_y + 0.8, skin[4])
	_fill(pix, solid, fx - 1.0, nose_y + 1.0, fx + 2.0, nose_y + 1.8, skin[1])
	_fill(pix, solid, fx - 1.0, nose_y + 1.0, fx, nose_y + 1.8, skin[0])
	# mouth: a dark line, a lit lower lip and the shadow under it
	var mx := fx - mouth_w / 2.0 + 1.0
	_fill(pix, solid, mx, mouth_y, mx + mouth_w, mouth_y + 0.8, skin[0])
	_fill(pix, solid, mx + 1.0, mouth_y - 0.8, mx + mouth_w - 1.0, mouth_y, skin[1])
	_fill(pix, solid, mx + 1.5, mouth_y + 0.8, mx + mouth_w - 1.0, mouth_y + 1.7, skin[3])
	_fill(pix, solid, mx + 2.0, mouth_y + 2.0, mx + mouth_w - 2.0, mouth_y + 2.8, skin[1])
	if hungry > 0:
		_fill(pix, solid, mx, mouth_y + 0.8, mx + 1.0, mouth_y + 1.6, skin[0])   # corners turn down

	# ---- goggles pushed up on the forehead
	if goggles:
		var gy := cy - ry * 0.52
		_fill(pix, solid, fx - 6.0, gy - 0.4, fx + 8.0, gy + 0.6, Color("2a2622"))
		for lens_x: float in [fx - 1.0, fx + 4.6]:
			for y in H:
				for x in W:
					var du := (x + 0.5) / K - lens_x
					var dv := (y + 0.5) / K - gy
					var d := sqrt(du * du + dv * dv)
					if d > 2.3:
						continue
					var c := Color("2a2622") if d > 1.6 else Color("38a8a0")
					if du < -0.2 and dv < -0.2 and d < 1.4:
						c = Color("b8fff0")
					_put(pix, solid, x, y, c)

	# ---- a bandage across the forehead, with blood soaking through, for the injured
	if hurt:
		var by := cy - ry * 0.34
		for i in 14:
			var bx := fx - 6.5 + i
			var bandage_y := by + i * 0.1
			_fill(pix, solid, bx, bandage_y, bx + 1.0, bandage_y + 1.7, Color("e8e2d0"))
			_fill(pix, solid, bx, bandage_y + 1.2, bx + 1.0, bandage_y + 1.7, Color("b8b0a0"))
		_fill(pix, solid, fx + 1.5, by + 0.6, fx + 3.5, by + 2.4, Color("b02a2a"))

	# ---- the rim light on the shadowed (left) edge, in broken arcs rather than a full outline
	var out := pix.duplicate()
	for y in H:
		var arc := _noise(0, int(y / (K * 3.0)), face)
		for x in range(1, W):
			var i := y * W + x
			if solid[i] == 0:
				continue
			var d := 0
			while d < 4 and x - 1 - d >= 0 and solid[i - 1 - d] == 1:
				d += 1
			if x - 1 - d < 0:
				continue   # cut off by the frame, not a real edge
			var lum := pix[i].get_luminance()
			var thr: float = (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0
			var strength := 0.35 + 0.65 * arc
			if d == 0 and lum < 0.6 and arc > 0.15:
				out[i] = rim[2] if thr < strength * 0.6 else rim[1]
			elif d == 1 and lum < 0.5 and arc > 0.3:
				out[i] = rim[1] if thr < strength * 0.5 else rim[0]
			elif d <= 3 and lum < 0.3 and thr < strength * 0.6 and arc > 0.5:
				out[i] = rim[0]

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			img.set_pixel(x, y, out[y * W + x])
	if face_right:
		img.flip_x()
	return img


## `n` shades of a color from deep shadow to highlight. The shadows lean purple and the lights
## warm, which keeps flat bands of pixels from looking muddy.
static func _ramp(base: Color, n: int) -> Array:
	var shadow := base.darkened(0.74).lerp(Color("2a1038"), 0.3)
	var light := base.lightened(0.5).lerp(Color("fff0c0"), 0.22)
	var out := []
	for i in n:
		var t := i / float(n - 1)
		out.append(shadow.lerp(base, t * 2.0) if t < 0.5 else base.lerp(light, (t - 0.5) * 2.0))
	return out


## Which of `n` shades a brightness 0..1 falls in. Between two shades the pixels alternate in a
## 4x4 dither pattern, in a narrow band, so most of a surface is flat color.
static func _level(shade: float, n: int, x: int, y: int) -> int:
	var v := clampf(shade, 0.0, 1.0) * (n - 1)
	var low := int(floor(v))
	if low >= n - 1:
		return n - 1
	var frac := smoothstep(0.3, 0.7, v - low)
	return low + (1 if frac > (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0 else 0)


static func _in_ellipse(px: float, py: float, a: float, b: float) -> bool:
	return (px * px) / (a * a) + (py * py) / (b * b) <= 1.0


## Repeatable noise 0..1 for a pixel.
static func _noise(x: int, y: int, seed_value: int) -> float:
	return float(hash(Vector3i(x, y, seed_value)) & 1023) / 1023.0


static func _put(pix: PackedColorArray, solid: PackedByteArray, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	pix[y * W + x] = c
	solid[y * W + x] = 1


## Fills a rectangle given in units. It snaps to whole pixels and is never thinner than one.
static func _fill(pix: PackedColorArray, solid: PackedByteArray, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	var px0 := roundi(x0 * K)
	var py0 := roundi(y0 * K)
	var px1 := maxi(roundi(x1 * K), px0 + 1)
	var py1 := maxi(roundi(y1 * K), py0 + 1)
	for y in range(py0, py1):
		for x in range(px0, px1):
			_put(pix, solid, x, y, c)
