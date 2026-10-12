extends RefCounted
## Finds test (or benchmark) files, runs them and reports. run_tests.gd drives it from the
## command line; see that file for the options.

const TestCase = preload("res://tests/framework/test_case.gd")
const ErrorCatcher = preload("res://tests/framework/error_catcher.gd")
const SETUP := "res://tests/setup.gd"
const RESULTS_DIR := "res://tests/results/"

var tree: SceneTree
var root_dir := "res://tests"
var filter := ""
var bench := false
var list_only := false
var timeout := 30.0
var junit_path := ""
var save_name := ""
var compare_name := ""

var catcher := ErrorCatcher.new()
var cases: Array[Dictionary] = []   # {file, name, status, messages, msec, results}


func _init(scene_tree: SceneTree, args: PackedStringArray) -> void:
	tree = scene_tree
	for arg in args:
		var value := arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--dir": root_dir = value
			"--filter": filter = value.to_lower()
			"--bench": bench = true
			"--list": list_only = true
			"--timeout": timeout = value.to_float()
			"--junit": junit_path = value
			"--save": save_name = value
			"--compare": compare_name = value
			"--update-snapshots": pass   # read by tests/helpers/snapshots.gd
			_: push_warning("Unknown test runner option: " + arg)


## Runs everything and returns the process exit code: 0 all passed, 1 failures, 2 nothing ran.
func run() -> int:
	var started := Time.get_ticks_msec()
	var prefix := "bench_" if bench else "test_"
	var files := find_files(root_dir, prefix)
	if list_only:
		for path in files:
			for m in _methods(load(path), prefix):
				print("%s::%s" % [path, m])
		return 0
	print("Running %s in %s (%s, %s)\n" % ["benchmarks" if bench else "tests", root_dir,
		DisplayServer.get_name(), Engine.get_version_info().string])
	OS.add_logger(catcher)
	var setup: RefCounted = load(SETUP).new() if ResourceLoader.exists(SETUP) else null
	if setup and setup.has_method("before_run"):
		await setup.before_run(tree)
	for path in files:
		await _run_file(path, prefix)
	if setup and setup.has_method("after_run"):
		await setup.after_run(tree)
	OS.remove_logger(catcher)

	var counts := {"passed": 0, "failed": 0, "skipped": 0}
	for c in cases:
		counts[c.status] += 1
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [counts.passed, counts.failed, counts.skipped,
		(Time.get_ticks_msec() - started) / 1000.0])
	if bench:
		_bench_report()
	if junit_path != "":
		_write_junit(junit_path)
	if cases.is_empty():
		print("No %s*.gd files%s found under %s" % [prefix, " matching '%s'" % filter if filter != "" else "", root_dir])
		return 2
	return 1 if counts.failed > 0 else 0


## Every <prefix>*.gd under `dir`, sorted, skipping the framework itself.
static func find_files(dir: String, prefix: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if sub != "framework" and not sub.begins_with("."):
			out.append_array(find_files(dir.path_join(sub), prefix))
	for f in d.get_files():
		if f.begins_with(prefix) and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	out.sort()
	return out


func _methods(script: Script, prefix: String) -> Array[String]:
	var out: Array[String] = []
	if script == null:
		return out
	for m in script.get_script_method_list():
		if m.name.begins_with(prefix) and not m.name in out:
			out.append(m.name)
	return out


func _run_file(path: String, prefix: String) -> void:
	catcher.listen()
	var script: Script = load(path)
	var load_errors := catcher.stop()
	if script == null or not script.can_instantiate() or not load_errors.is_empty():
		_report(path, "(load)", "failed", ["could not load the script"] + load_errors, 0)
		return
	if not _inherits(script, TestCase):
		_report(path, "(load)", "failed", ["must extend res://tests/framework/test_case.gd"], 0)
		return
	var methods := _methods(script, prefix).filter(func(m: String):
		return filter == "" or filter in ("%s::%s" % [path, m]).to_lower())
	if methods.is_empty():
		return
	print(path)
	var suite: Node = script.new()
	suite.name = path.get_file().get_basename()
	tree.root.add_child(suite)

	catcher.listen()
	var setup_ok := await _call(suite, "before_all")
	var setup_errors := catcher.stop()
	if not setup_ok or not setup_errors.is_empty():
		var why := ["before_all() failed"] + setup_errors
		for m in methods:
			_report(path, m, "failed", why, 0)
	else:
		for m in methods:
			await _run_one(suite, path, m)
		catcher.listen()
		await _call(suite, "after_all")
		for e in catcher.stop():
			_report(path, "(after_all)", "failed", [e], 0)
	suite.queue_free()
	await tree.process_frame


func _run_one(suite: Node, path: String, method: String) -> void:
	suite._begin()
	catcher.listen()
	var t0 := Time.get_ticks_usec()
	var finished := await _call(suite, "before_each")
	if finished:
		finished = await _call(suite, method)
	await _call(suite, "after_each")
	var msec := (Time.get_ticks_usec() - t0) / 1000.0
	var result: Array = suite._finish(catcher.stop())
	var messages: Array = result[1]
	if not finished:
		result[0] = "failed"
		messages = ["timed out after %d s" % timeout] + messages
	var c := _report(path, method, result[0], messages, msec)
	if bench and "results" in suite:
		c["results"] = suite.results.duplicate()
		suite.results.clear()
		_print_results(c.results)


## Calls `method` if the object has it and waits for it if it awaits. False if it hit the timeout.
func _call(obj: Object, method: String) -> bool:
	if not obj.has_method(method):
		return true
	var state = obj.call(method)
	if not (state is Object and state.get_class() == "GDScriptFunctionState"):
		return true
	var done := [false]
	state.completed.connect(func(_r): done[0] = true, CONNECT_ONE_SHOT)
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while not done[0]:
		if Time.get_ticks_msec() > end:
			return false
		await tree.process_frame
	return true


func _report(path: String, method: String, status: String, messages: Array, msec: float) -> Dictionary:
	var c := {"file": path, "name": method, "status": status, "messages": messages, "msec": msec}
	cases.append(c)
	var tag: String = {"passed": "PASS", "failed": "FAIL", "skipped": "SKIP"}[status]
	var time := "  (%.0f ms)" % msec if msec >= 1 and status != "skipped" else ""
	print("  %s  %s%s" % [tag, method, time])
	for m in messages:
		print("        %s" % m)
	return c


static func _inherits(script: Script, base: Script) -> bool:
	while script != null:
		if script == base:
			return true
		script = script.get_base_script()
	return false


# ---------------------------------------------------------------- benchmarks

func _print_results(results: Array) -> void:
	for r in results:
		print("        %-44s %12s %-3s %s" % [r.metric, _num(r.value), r.unit, r.note])


func _bench_report() -> void:
	var data := {"date": Time.get_datetime_string_from_system(), "env": _environment(), "results": {}}
	for c in cases:
		for r in c.get("results", []):
			data.results["%s::%s" % [c.name, r.metric]] = r
	if compare_name != "":
		_compare(data, compare_name)
	if save_name != "":
		DirAccess.make_dir_recursive_absolute(RESULTS_DIR)
		if not FileAccess.file_exists(RESULTS_DIR + ".gdignore"):
			FileAccess.open(RESULTS_DIR + ".gdignore", FileAccess.WRITE).store_string("")
		var path := RESULTS_DIR + save_name + ".json"
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data, "\t"))
		print("Saved benchmark results to %s" % ProjectSettings.globalize_path(path))


func _compare(data: Dictionary, name: String) -> void:
	var path := RESULTS_DIR + name + ".json"
	var old = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(old) != TYPE_DICTIONARY:
		print("No saved benchmark run '%s' to compare with (%s)" % [name, path])
		return
	print("\nCompared with '%s' (%s):" % [name, old.date])
	if old.env != data.env:
		print("  note: that run used %s" % [old.env])
	print("  %-62s %12s %12s  %s" % ["metric", name, "now", "change"])
	for key in data.results:
		var now: Dictionary = data.results[key]
		if not old.results.has(key):
			print("  %-62s %12s %12s  %s" % [key, "-", _num(now.value), "new"])
			continue
		var was: float = old.results[key].value
		var change := "same"
		if was != 0 and now.value != was:
			var pct: float = (now.value - was) / absf(was) * 100.0
			var better: bool = (pct < 0) == now.get("lower_is_better", true)
			change = "%+.0f%% %s" % [pct, "better" if better else "worse"]
		elif was == 0 and now.value != 0:
			change = "was 0"
		print("  %-62s %12s %12s  %s" % [key, _num(was), _num(now.value), change])


func _environment() -> Dictionary:
	return {"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info().string}


static func _num(v: float) -> String:
	return str(int(v)) if absf(v) >= 100 or v == int(v) else "%.2f" % v


# ---------------------------------------------------------------- JUnit XML (for CI)

func _write_junit(path: String) -> void:
	var by_file := {}
	for c in cases:
		if not by_file.has(c.file):
			by_file[c.file] = []
		by_file[c.file].append(c)
	var xml := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites>\n"
	for file in by_file:
		var list: Array = by_file[file]
		var failed := list.filter(func(c): return c.status == "failed").size()
		var skipped := list.filter(func(c): return c.status == "skipped").size()
		xml += "  <testsuite name=\"%s\" tests=\"%d\" failures=\"%d\" skipped=\"%d\">\n" % [
			_xml(file), list.size(), failed, skipped]
		for c in list:
			xml += "    <testcase classname=\"%s\" name=\"%s\" time=\"%.3f\"" % [
				_xml(file.get_file().get_basename()), _xml(c.name), c.msec / 1000.0]
			if c.status == "passed":
				xml += "/>\n"
				continue
			var tag := "failure" if c.status == "failed" else "skipped"
			xml += ">\n      <%s message=\"%s\"/>\n    </testcase>\n" % [tag, _xml("\n".join(c.messages))]
		xml += "  </testsuite>\n"
	xml += "</testsuites>\n"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(xml)


static func _xml(s: String) -> String:
	return s.xml_escape(true)
