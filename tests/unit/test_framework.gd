extends "res://tests/framework/test_case.gd"
## Tests for the test framework itself: assertions must fail when they should and pass when they
## should, or every other test is meaningless.

const ErrorCatcher = preload("res://tests/framework/error_catcher.gd")

signal pinged(a: int, b: String)

var hooks: Array[String] = []
var freed_later: Node


func before_all() -> void:
	hooks.append("before_all")


func before_each() -> void:
	hooks.append("before_each")


func after_each() -> void:
	hooks.append("after_each")


## Runs `assertion` and checks it recorded exactly one failure mentioning `text`, then removes
## that failure so this test still passes.
func _fails(assertion: Callable, text := "") -> void:
	var before := _failures.size()
	assertion.call()
	if _failures.size() != before + 1:
		_failures.resize(before)
		_fail("assertion should have failed but didn't", "")
		return
	var msg: String = _failures.pop_back()
	if text != "" and text not in msg:
		_fail("failure message %s should mention %s" % [_fmt(msg), _fmt(text)], "")


func test_hooks_run_in_order() -> void:
	assert_eq(hooks, ["before_all", "before_each"])


func test_assert_eq_passes_on_equal_values() -> void:
	assert_eq(1, 1)
	assert_eq(2, 2.0, "ints and floats compare by value")
	assert_eq("a", &"a", "String and StringName mix")
	assert_eq([1, [2, 3]], [1, [2, 3]])
	assert_eq({"k": Vector2i(1, 2)}, {"k": Vector2i(1, 2)})
	assert_eq(null, null)
	assert_eq(_failures.size(), 0)


func test_assert_eq_fails_with_a_useful_message() -> void:
	_fails(func(): assert_eq(3, 4), "expected 4, got 3")
	_fails(func(): assert_eq("x", "y", "names"), "names: expected \"y\", got \"x\"")
	_fails(func(): assert_eq([1], [2]), "expected [2]")
	_fails(func(): assert_eq(1, 2), "test_framework.gd:")


func test_assert_eq_never_errors_on_mixed_types() -> void:
	_fails(func(): assert_eq(1, "1"))
	_fails(func(): assert_eq(null, 0))
	_fails(func(): assert_eq(Vector2(1, 1), Vector2i(1, 1)))


func test_truthiness_is_strict() -> void:
	assert_true(true)
	assert_false(false)
	_fails(func(): assert_true(1), "expected true, got 1")
	_fails(func(): assert_false(null))
	_fails(func(): assert_true("yes"))


func test_comparisons() -> void:
	assert_gt(2, 1)
	assert_ge(2, 2)
	assert_lt(1, 2)
	assert_le(2, 2)
	assert_almost_eq(0.1 + 0.2, 0.3, 1e-9)
	_fails(func(): assert_gt(1, 1), "more than 1")
	_fails(func(): assert_le(3, 2), "at most 2")
	_fails(func(): assert_almost_eq(1.0, 1.5, 0.1))


func test_containers_and_null() -> void:
	assert_has([1, 2], 2)
	assert_has({"a": 1}, "a")
	assert_has("wasteland", "waste")
	assert_not_has([1, 2], 3)
	assert_null(null)
	assert_not_null(0)
	_fails(func(): assert_has([1], 5), "to contain 5")
	_fails(func(): assert_not_null(null))
	_fails(func(): fail("custom"), "custom")


func test_async_tests_are_awaited() -> void:
	var start := Engine.get_process_frames()
	await wait_frames(3)
	await get_tree().process_frame
	assert_ge(Engine.get_process_frames() - start, 4)


func test_wait_until() -> void:
	var start := Engine.get_process_frames()
	assert_true(await wait_until(func(): return Engine.get_process_frames() >= start + 2))
	assert_false(await wait_until(func(): return false, 0.05))


func test_watch_counts_signal_emissions() -> void:
	var w := watch(self, "pinged")
	pinged.emit(1, "a")
	pinged.emit(2, "b")
	assert_eq(w.count, 2)
	assert_eq(w.emissions[1], [2, "b"])


func test_expected_errors_do_not_fail_the_test() -> void:
	expect_error("deliberate")
	push_error("a deliberate error")
	expect_error()
	push_error("any error at all")


func test_error_catcher_sees_script_errors() -> void:
	var c := ErrorCatcher.new()
	OS.add_logger(c)
	c.listen()
	expect_error("caught me")
	push_error("caught me")
	var got := c.stop()
	OS.remove_logger(c)
	assert_eq(got.size(), 1)
	assert_has(got[0], "caught me")


func test_autofree_frees_after_the_test() -> void:
	freed_later = add_autofree(Node.new())
	assert_true(freed_later.is_inside_tree())


func test_autofree_freed_the_previous_node() -> void:
	assert_false(is_instance_valid(freed_later), "the node from the previous test should be freed")


func test_skip() -> void:
	skip("checks that skipping works")
