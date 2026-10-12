extends "res://tests/framework/test_case.gd"
## Base class for benchmarks. Name the file bench_<something>.gd and its methods bench_<something>().
## They run only with `--bench`, and their numbers are printed, saved and compared between runs
## instead of passing or failing (assertions still work for sanity checks).
##
## Run them windowed (no --headless) for real GPU numbers; headless only measures the CPU side.

var results: Array[Dictionary] = []   # {metric, value, unit, lower_is_better}; the runner reads these


## Runs `work` `warmup` times untimed, then `iterations` times timed, and records the median
## (plus min and max) in microseconds. `work` may await, so call this with await.
func measure(metric: String, work: Callable, iterations := 20, warmup := 2) -> Dictionary:
	for i in warmup:
		await work.call()
	var times: Array[float] = []
	for i in iterations:
		var t0 := Time.get_ticks_usec()
		await work.call()
		times.append(Time.get_ticks_usec() - t0)
	return record_samples(metric, times, "us")


## Records the median, min and max of samples you measured yourself.
func record_samples(metric: String, samples: Array[float], unit: String) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var out := {"median": sorted[sorted.size() / 2], "min": sorted[0], "max": sorted[-1]}
	record(metric, out.median, unit, "min %s  max %s" % [_num(out.min), _num(out.max)])
	return out


## Records one number. Counts and times are lower-is-better unless you say otherwise.
func record(metric: String, value: float, unit := "", note := "", lower_is_better := true) -> void:
	results.append({"metric": metric, "value": value, "unit": unit, "note": note, "lower_is_better": lower_is_better})


static func _num(v: float) -> String:
	return str(int(v)) if absf(v) >= 100 or v == int(v) else "%.2f" % v
