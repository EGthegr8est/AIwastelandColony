extends Node
## Base class for every test file. Name the file test_<something>.gd, extend this script by path
## (class_name would need an editor rescan before new tests are found):
##     extends "res://tests/framework/test_case.gd"
## and write methods named test_<something>(). The runner adds one instance of the file to the
## scene tree, so tests can add nodes and await frames, then calls each test in the order written.
##
## Optional hooks run around the tests, and any of them may await:
##     before_all()  before_each()  after_each()  after_all()
##
## A failed assertion records a message and the test keeps going. A test also fails if it logs an
## engine or script error (null access, push_error, ...), unless it called expect_error() first.

const _THIS := "res://tests/framework/test_case.gd"


## Counts emissions of a signal. Make one with watch().
class SignalWatcher:
	extends RefCounted
	var count := 0
	var emissions: Array = []   # the arguments of each emission, oldest first

	func _on_emit(...args: Array) -> void:
		count += 1
		emissions.append(args)


var _failures: Array[String] = []
var _skip_reason := ""
var _expected_errors: Array[String] = []
var _autofree: Array = []   # nodes to free and disconnect callables to run after each test


# ---------------------------------------------------------------- assertions

func assert_true(value, msg := "") -> void:
	if not _same(value, true):
		_fail("expected true, got %s" % _fmt(value), msg)


func assert_false(value, msg := "") -> void:
	if not _same(value, false):
		_fail("expected false, got %s" % _fmt(value), msg)


func assert_eq(got, expected, msg := "") -> void:
	if not _same(got, expected):
		_fail("expected %s, got %s" % [_fmt(expected), _fmt(got)], msg)


func assert_ne(got, not_expected, msg := "") -> void:
	if _same(got, not_expected):
		_fail("expected anything but %s" % _fmt(not_expected), msg)


func assert_almost_eq(got: float, expected: float, tolerance: float, msg := "") -> void:
	if absf(got - expected) > tolerance:
		_fail("expected %s +/- %s, got %s" % [expected, tolerance, got], msg)


func assert_gt(got, than, msg := "") -> void:
	if not got > than:
		_fail("expected more than %s, got %s" % [_fmt(than), _fmt(got)], msg)


func assert_ge(got, than, msg := "") -> void:
	if not got >= than:
		_fail("expected at least %s, got %s" % [_fmt(than), _fmt(got)], msg)


func assert_lt(got, than, msg := "") -> void:
	if not got < than:
		_fail("expected less than %s, got %s" % [_fmt(than), _fmt(got)], msg)


func assert_le(got, than, msg := "") -> void:
	if not got <= than:
		_fail("expected at most %s, got %s" % [_fmt(than), _fmt(got)], msg)


func assert_null(value, msg := "") -> void:
	if value != null:
		_fail("expected null, got %s" % _fmt(value), msg)


func assert_not_null(value, msg := "") -> void:
	if value == null:
		_fail("expected a value, got null", msg)


## `container` is anything `in` works on: Array, Dictionary (keys), String, Packed*Array.
func assert_has(container, item, msg := "") -> void:
	if not item in container:
		_fail("expected %s to contain %s" % [_fmt(container), _fmt(item)], msg)


func assert_not_has(container, item, msg := "") -> void:
	if item in container:
		_fail("expected %s not to contain %s" % [_fmt(container), _fmt(item)], msg)


func fail(msg: String) -> void:
	_fail(msg, "")


## Mark the test skipped (say why), then return from it.
func skip(reason: String) -> void:
	_skip_reason = reason


## The next logged error containing `text` is expected: it won't fail the test. If it never
## comes, the test fails instead.
func expect_error(text := "") -> void:
	_expected_errors.append(text)


# ---------------------------------------------------------------- helpers

func wait_frames(frames := 1) -> void:
	for i in frames:
		await get_tree().process_frame


func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits until `condition` returns true or `timeout` seconds pass. Returns whether it came true.
func wait_until(condition: Callable, timeout := 2.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while not condition.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


## Counts how often `object` emits `signal_name` from now until the test ends.
func watch(object: Object, signal_name: StringName) -> SignalWatcher:
	var w := SignalWatcher.new()
	object.connect(signal_name, w._on_emit)
	_autofree.append(func(): if is_instance_valid(object): object.disconnect(signal_name, w._on_emit))
	return w


## Adds `node` under this test and frees it when the test ends.
func add_autofree(node: Node) -> Node:
	add_child(node)
	_autofree.append(node)
	return node


# ---------------------------------------------------------------- runner interface

func _begin() -> void:
	_failures = []
	_skip_reason = ""
	_expected_errors = []


## Called by the runner after the test and after_each(). `errors` is what the engine logged.
## Returns ["passed" | "failed" | "skipped", messages].
func _finish(errors: Array[String]) -> Array:
	for item in _autofree:
		if item is Callable:
			item.call()
		elif is_instance_valid(item):
			item.free()
	_autofree = []
	for e in errors:
		var allowed := -1
		for i in _expected_errors.size():
			if _expected_errors[i] == "" or _expected_errors[i] in e:   # "" in s is false in GDScript
				allowed = i
				break
		if allowed >= 0:
			_expected_errors.remove_at(allowed)
		else:
			_failures.append("engine error: " + e)
	for text in _expected_errors:
		_failures.append("expected an error containing \"%s\", none was logged" % text)
	if not _failures.is_empty():
		return ["failed", _failures]
	if _skip_reason != "":
		return ["skipped", [_skip_reason]]
	return ["passed", []]


func _fail(what: String, msg: String) -> void:
	_failures.append("%s%s  [%s]" % [msg + ": " if msg != "" else "", what, _where()])


## The test file and line that called the assertion.
func _where() -> String:
	for bt in Engine.capture_script_backtraces():
		for f in bt.get_frame_count():
			var file := bt.get_frame_file(f)
			if file != _THIS and file.begins_with("res://"):
				return "%s:%d" % [file.get_file(), bt.get_frame_line(f)]
	return "?"


## == that never errors: ints and floats compare by value, String and StringName mix,
## anything else must be the same type.
static func _same(a, b) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var numbers := [TYPE_INT, TYPE_FLOAT]
	var strings := [TYPE_STRING, TYPE_STRING_NAME]
	if (ta in numbers and tb in numbers) or (ta in strings and tb in strings):
		return a == b
	if ta != tb:
		return false
	return a == b


static func _fmt(v) -> String:
	var s := ("\"%s\"" % v) if v is String else str(v)
	return s if s.length() <= 160 else s.left(157) + "..."
