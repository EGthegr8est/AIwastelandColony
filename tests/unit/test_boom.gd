extends "res://tests/framework/test_case.gd"
## The boom of a nuke going off: a rumble made in code (there are no sound files for it), played on the Music bus so the volume slider mutes it too.


func test_the_boom_is_a_second_and_a_half_of_sixteen_bit_mono_that_starts_quick_and_fades() -> void:
	var stream := Music.make_boom()
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_false(stream.stereo)
	assert_eq(stream.mix_rate, Music.BOOM_RATE)
	assert_almost_eq(stream.get_length(), Music.BOOM_SECONDS, 0.01)
	var n := stream.data.size() / 2
	var peak := 0
	var tail := 0
	for i in n:
		var v := absi(stream.data.decode_s16(i * 2))
		peak = maxi(peak, v)
		if i > n - Music.BOOM_RATE / 10:
			tail = maxi(tail, v)
	assert_gt(peak, 8000, "loud enough to hear")
	assert_lt(tail, peak / 10, "gone by the end")
	assert_lt(absi(stream.data.decode_s16(0)), peak / 4, "it builds in a few thousandths of a second, not a click")


func test_it_is_the_same_every_time() -> void:
	assert_eq(Music.make_boom().data, Music.make_boom().data)


func test_a_boom_is_counted_and_makes_no_sound_when_nothing_is_audible() -> void:
	assert_false(Music.audible, "the tests are silent")
	var before := Music.booms
	Music.boom()
	assert_eq(Music.booms, before + 1)
