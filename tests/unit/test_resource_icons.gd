extends "res://tests/framework/test_case.gd"
## The little pictures beside each resource in the top bar (art/icons/res_<id>.png, 8 x 8, and res_<id>_bar.png, 18 x 16: doubled with a 2 px gap).

const Data = preload("res://scripts/data.gd")


func test_every_resource_has_an_8_by_8_picture_and_a_bar_copy() -> void:
	for id in Data.RESOURCES:
		var small: Texture2D = load("res://art/icons/res_%s.png" % id)
		var big: Texture2D = load("res://art/icons/res_%s_bar.png" % id)
		assert_not_null(small, id)
		assert_not_null(big, id)
		assert_eq(small.get_size(), Vector2(8, 8), "%s as drawn" % id)
		assert_eq(big.get_size(), Vector2(18, 16), "%s doubled, with its gap" % id)


func test_the_pictures_are_see_through_at_the_corners_and_all_different() -> void:
	var seen := {}
	for id in Data.RESOURCES:
		var img: Image = (load("res://art/icons/res_%s_bar.png" % id) as Texture2D).get_image()
		assert_eq(img.get_pixel(0, 0).a, 0.0, "%s has a clear corner" % id)
		var solid := 0
		for y in 16:
			assert_eq(img.get_pixel(16, y).a + img.get_pixel(17, y).a, 0.0, "%s keeps a clear gap on the right" % id)
			for x in 16:
				if img.get_pixel(x, y).a > 0.5:
					solid += 1
		assert_gt(solid, 20, "%s is something, not a blank" % id)
		var key := img.get_data().hex_encode()
		assert_false(seen.has(key), "%s is not the same picture as another resource" % id)
		seen[key] = id


func test_the_bar_copy_is_the_small_one_with_every_pixel_doubled() -> void:
	for id in Data.RESOURCES:
		var small: Image = (load("res://art/icons/res_%s.png" % id) as Texture2D).get_image()
		var big: Image = (load("res://art/icons/res_%s_bar.png" % id) as Texture2D).get_image()
		for y in 8:
			for x in 8:
				var c := small.get_pixel(x, y)
				for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					var doubled := big.get_pixel(x * 2 + d.x, y * 2 + d.y)
					assert_eq(doubled.a, c.a, "%s at %d,%d: the same see-through" % [id, x, y])
					if c.a > 0.0:   # (the colour of a clear pixel is nothing: the importer changes it)
						assert_true(doubled.is_equal_approx(c), "%s at %d,%d: the same colour" % [id, x, y])
