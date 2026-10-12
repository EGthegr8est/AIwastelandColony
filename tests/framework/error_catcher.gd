extends Logger
## Collects engine and script errors (null access, bad keys, push_error, ...) while a test runs,
## so a test that crashes fails instead of passing silently. Errors can arrive from any thread.

var _mutex := Mutex.new()
var _errors: Array[String] = []
var _listening := false


func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := rationale if rationale != "" else code
	_mutex.lock()
	if _listening:
		_errors.append("%s (%s:%d)" % [text, file.get_file(), line])
	_mutex.unlock()


## Start collecting, dropping anything logged before now.
func listen() -> void:
	_mutex.lock()
	_listening = true
	_errors.clear()
	_mutex.unlock()


## Stop collecting and return what was logged since listen().
func stop() -> Array[String]:
	_mutex.lock()
	_listening = false
	var out := _errors.duplicate()
	_errors.clear()
	_mutex.unlock()
	return out
