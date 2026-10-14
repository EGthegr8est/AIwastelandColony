extends RefCounted
## Whether the key caps show on the buttons (the "Key hints" switch in the menus and the legend). It is saved in settings.cfg with the other display settings, on by default.

const SETTINGS_SECTION := "display"
const SETTINGS_KEY := "key_hints"

static var enabled := true


static func load_setting() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Music.settings_path) != OK or not cfg.has_section_key(SETTINGS_SECTION, SETTINGS_KEY):
		return
	enabled = bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY))


static func save_setting() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Music.settings_path)   # keep anything else in there
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, enabled)
	cfg.save(Music.settings_path)


static func set_enabled(on: bool) -> void:
	enabled = on
	save_setting()
