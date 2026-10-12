extends RefCounted
## Compares screenshots with the baseline images in tests/render/snapshots/. Baselines are made
## on one machine (GPU, driver and fonts all affect pixels): pass --update-snapshots to remake
## them after an intended visual change, or on a new machine.

const DIR := "res://tests/render/snapshots/"
const OUT := "res://tests/results/snapshots/"
const CHANNEL_TOLERANCE := 16     # out of 255, per channel: GPU rounding, not a visual change
const MAX_DIFF_FRACTION := 0.0005 # share of pixels allowed past the tolerance


static func updating() -> bool:
	return "--update-snapshots" in OS.get_cmdline_user_args()


## Compares `image` with the baseline called `name`.
## Returns ["match" | "created" | "differs", message]. When it differs, the actual image and a
## diff (changed pixels in red) are saved to tests/results/snapshots/.
static func check(name: String, image: Image) -> Array:
	image.convert(Image.FORMAT_RGBA8)
	var path := ProjectSettings.globalize_path(DIR + name + ".png")
	if updating() or not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		image.save_png(path)
		return ["created", "saved a new baseline: " + path]
	var want := Image.load_from_file(path)
	want.convert(Image.FORMAT_RGBA8)
	if want.get_size() != image.get_size():
		return _differs(name, image, null, "size %s, baseline is %s" % [image.get_size(), want.get_size()])
	var got_data := image.get_data()
	var want_data := want.get_data()
	if got_data == want_data:
		return ["match", ""]
	var diff := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	var bad := 0
	for i in range(0, got_data.size(), 4):
		var off := maxi(maxi(absi(got_data[i] - want_data[i]), absi(got_data[i + 1] - want_data[i + 1])),
			absi(got_data[i + 2] - want_data[i + 2]))
		var p := i / 4
		var x := p % image.get_width()
		var y := p / image.get_width()
		if off > CHANNEL_TOLERANCE:
			bad += 1
			diff.set_pixel(x, y, Color.RED)
		else:
			diff.set_pixel(x, y, Color8(got_data[i], got_data[i + 1], got_data[i + 2]).darkened(0.7))
	var fraction := bad / float(image.get_width() * image.get_height())
	if fraction <= MAX_DIFF_FRACTION:
		return ["match", ""]
	return _differs(name, image, diff, "%d pixels differ (%.3f%%)" % [bad, fraction * 100])


## How many pixels differ between two images of the same size by more than the tolerance.
static func count_differences(a: Image, b: Image) -> int:
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var da := a.get_data()
	var db := b.get_data()
	if da == db:
		return 0
	var bad := 0
	for i in range(0, da.size(), 4):
		if maxi(maxi(absi(da[i] - db[i]), absi(da[i + 1] - db[i + 1])), absi(da[i + 2] - db[i + 2])) > CHANNEL_TOLERANCE:
			bad += 1
	return bad


static func _differs(name: String, image: Image, diff: Image, why: String) -> Array:
	var out := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	image.save_png(out.path_join(name + ".actual.png"))
	if diff:
		diff.save_png(out.path_join(name + ".diff.png"))
	return ["differs", "%s: %s. See %s" % [name, why, out]]
