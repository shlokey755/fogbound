extends Node
## SaveData
## Tiny local unlock-flag store, persisted per-device at
## user://fogbound_save.cfg. Nothing here is gameplay-authoritative or
## networked -- it only gates which levels a *local* player sees in
## their own lobby level picker (lobby.gd reads
## SaveData.is_unlocked(level_id) when building the list). Each host
## still only needs their own copy unlocked to pick a level for the
## match; clients don't need the secret level unlocked locally to
## join one the host already started.
##
## Deliberately file-based rather than going through GameState: unlocks
## are meant to survive across completely separate matches and even
## engine restarts, whereas GameState resets every match
## (GameState.reset_match()).

## Overridable so headless tests can point this at a throwaway path
## instead of silently reading/writing a real player's save file. A
## test sets this and then calls reload_for_test() to re-read from
## the new path (see tests/boot_game_smoketest.gd) -- safe to change
## at any time, unlike a value that only takes effect at _ready().
static var save_path_override: String = ""

func _save_path() -> String:
	return save_path_override if save_path_override != "" else "user://fogbound_save.cfg"

var _unlocked_levels: Dictionary = {}  # level_id (int, as String key) -> true
var _seen_commentary: Dictionary = {}  # commentary node id (String) -> true

## Set for exactly one frame-of-game-logic when unlock_level() flips a
## level from locked to unlocked, so score_screen.gd can show a
## one-time "you unlocked something" banner instead of silently
## writing the flag. Cleared by consume_just_unlocked() once read.
var _just_unlocked: int = -1


func _ready() -> void:
	_load()


func is_unlocked(level_id: int) -> bool:
	return _unlocked_levels.has(str(level_id))


func unlock_level(level_id: int) -> void:
	if is_unlocked(level_id):
		return
	_unlocked_levels[str(level_id)] = true
	_just_unlocked = level_id
	_save()


## Returns the level id that was just newly unlocked (if any) and
## clears the flag, so a UI can show a banner for it exactly once.
## Returns -1 if nothing was unlocked since the last call.
func consume_just_unlocked() -> int:
	var id := _just_unlocked
	_just_unlocked = -1
	return id


func has_seen_commentary(node_id: String) -> bool:
	return _seen_commentary.has(node_id)


func mark_commentary_seen(node_id: String) -> void:
	if _seen_commentary.has(node_id):
		return
	_seen_commentary[node_id] = true
	_save()


func commentary_seen_count() -> int:
	return _seen_commentary.size()


## Re-reads from whatever _save_path() currently resolves to,
## discarding in-memory state first. Tests use this after setting
## save_path_override, so a test run never touches a real save file
## at user://fogbound_save.cfg and never inherits state left over
## from a previous test in the same process.
func reload_for_test() -> void:
	_unlocked_levels.clear()
	_seen_commentary.clear()
	_just_unlocked = -1
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path()) != OK:
		return  # first run, or no save yet -- fine, defaults stand
	_unlocked_levels = cfg.get_value("levels", "unlocked", {})
	_seen_commentary = cfg.get_value("commentary", "seen", {})


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("levels", "unlocked", _unlocked_levels)
	cfg.set_value("commentary", "seen", _seen_commentary)
	var err := cfg.save(_save_path())
	if err != OK:
		push_warning("Fogbound: could not write save file (%s) -- unlocks won't persist this session" % err)
