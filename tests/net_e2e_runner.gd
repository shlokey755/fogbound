extends Node
## Plays one side of a real hosted game against a second Godot process.
## Started twice by tests/net_e2e.sh: `--role=host` and `--role=client`.
## It drives the REAL scenes the way a person would (menu shortcuts, lobby
## buttons, the keyboard action), and only reads state to check it:
##
##   host:   opens a room -> sees the client arrive and its name -> picks a level
##           -> waits for the client's Ready -> presses START -> checks the game
##           and that the client's player really moves on the host
##   client: finds the room by discovery -> joins -> sees the host's name and
##           level -> taps Ready -> checks the game, holds "right" for a moment
##           and checks its own player moved and the rope is drawn

const HOST_NAME := "Hosty"
const CLIENT_NAME := "Clienty"

var role := ""
var failures := 0
var _other_level := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
	if role != "host" and role != "client":
		print("net_e2e: pass --role=host or --role=client after --")
		get_tree().quit(2)
		return
	# Never touch a real player's save file.
	SaveData.save_path_override = "user://fogbound_e2e_%s.cfg" % role
	var abs_path := ProjectSettings.globalize_path(SaveData.save_path_override)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	SaveData.reload_for_test()
	for lvl in LevelData.selectable_levels():
		if lvl.id != GameState.DEFAULT_LEVEL_ID:
			_other_level = lvl.id
			break
	if role == "host":
		_run_host.call_deferred()
	else:
		_run_client.call_deferred()


# ---------------------------------------------------------------------------

func _check(label: String, condition: bool) -> bool:
	print("%s: [%s] %s" % ["PASS" if condition else "FAIL", role, label])
	if not condition:
		failures += 1
	return condition


func _scene() -> Node:
	return get_tree().current_scene


func _in_game() -> bool:
	var scene := _scene()
	return scene != null and "player_nodes" in scene and scene.player_nodes.size() > 0


## Polls every frame until `cond` is true. Records a failure on timeout.
func _wait_until(label: String, cond: Callable, timeout_s: float = 25.0) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_s * 1000.0:
		if cond.call():
			return true
		await get_tree().process_frame
	_check("timed out waiting for: " + label, false)
	return false


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _finish() -> void:
	print("E2E %s %s" % [role, "OK" if failures == 0 else "FAILED (%d)" % failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Host side
# ---------------------------------------------------------------------------

func _run_host() -> void:
	if not await _wait_until("the lobby to open after --auto-host", func(): return _scene() is Lobby, 20.0):
		return _finish()
	var lobby: Lobby = _scene()
	_check("host: hosting with the test port", NetLocal.hosting and NetLocal.game_port != NetLocal.DEFAULT_GAME_PORT)

	if not await _wait_until("a device to join", func(): return multiplayer.get_peers().size() == 1 and GameState.player_names.size() == 2, 40.0):
		return _finish()
	var client_id: int = multiplayer.get_peers()[0]
	_check("host: the joiner's name arrived", GameState.display_name(client_id) == CLIENT_NAME)
	_check("host: our own name is shown", GameState.display_name(1) == HOST_NAME)
	_check("host: both start in the same pod", GameState.player_team.get(1, -1) == GameState.player_team.get(client_id, -2))
	_check("host: the room is named after the host", GameState.room_title == "%s's room" % HOST_NAME)

	# Choose another level the way a person would: through the dropdown.
	var index := -1
	for i in range(lobby._levels.size()):
		if lobby._levels[i].id == _other_level:
			index = i
	_check("host: a second level exists to choose", index != -1)
	lobby._level_picker.select(index)
	lobby._level_picker.item_selected.emit(index)
	_check("host: choosing a level in the lobby sets it", GameState.level_id == _other_level)

	if not await _wait_until("the joiner to tap Ready", func(): return GameState.player_ready.get(client_id, false), 40.0):
		return _finish()
	_check("host: with everyone ready the match can start", NetRouter.host_check_can_start()["ok"])
	lobby._seed_field.text = "4242"
	lobby._on_start_pressed()

	if not await _wait_until("the game scene", _in_game, 20.0):
		return _finish()
	var game: Node = _scene()
	_check("host: the game uses the level the host chose", GameState.level_id == _other_level)
	_check("host: both players spawned", game.player_nodes.size() == 2 and game.player_nodes.has(client_id))
	_check("host: one rope links them", game.tether_system.links.size() == 1)
	_check("host: the seed from the lobby field was used", GameState.match_seed == 4242)

	await _sleep(0.8)
	var remote: Player = game.player_nodes[client_id]
	var start := remote.position
	var moved := await _wait_until("the client's player to move on the host", func(): return remote.position.distance_to(start) > 8.0, 30.0)
	if moved:
		_check("host: the client's input moved its player (%.0f px)" % remote.position.distance_to(start), true)
	_check("host: the rope is still intact", game.tether_system.links[0].alive)

	# Courtesy wait: let the client finish its own checks and say goodbye.
	# Running out of patience here is not a failure of the game.
	var waited := Time.get_ticks_msec()
	while not multiplayer.get_peers().is_empty() and Time.get_ticks_msec() - waited < 20000:
		await get_tree().process_frame
	_finish()


# ---------------------------------------------------------------------------
# Client side
# ---------------------------------------------------------------------------

func _run_client() -> void:
	if not await _wait_until("to find the host's room and land in the lobby", func(): return _scene() is Lobby, 40.0):
		return _finish()
	var lobby: Lobby = _scene()
	var found := false
	for room in NetLocal.rooms.values():
		if room["name"] == "%s's room" % HOST_NAME:
			found = true
	_check("client: discovery listed the host's room by name", found)
	var my_id := multiplayer.get_unique_id()
	_check("client: has a real network id (not 1)", my_id > 1)

	if not await _wait_until("the lobby to sync names", func(): return GameState.player_names.size() == 2, 20.0):
		return _finish()
	_check("client: sees the host's name", GameState.display_name(1) == HOST_NAME)
	_check("client: sees its own name", GameState.display_name(my_id) == CLIENT_NAME)
	_check("client: starts in the host's pod", GameState.player_team.get(my_id, -1) == GameState.player_team.get(1, -2))

	if not await _wait_until("the host's level choice", func(): return GameState.level_id == _other_level, 20.0):
		return _finish()
	_check("client: the lobby tells the player which level the host picked",
			lobby._level_label.text.contains(LevelData.get_level(_other_level).name))

	lobby._ready_button.button_pressed = true  # tap "Ready"

	if not await _wait_until("the match to start", _in_game, 30.0):
		return _finish()
	var game: Node = _scene()
	_check("client: uses the host's level", GameState.level_id == _other_level and GameState.match_seed == 4242)
	_check("client: both players are drawn", game.player_nodes.size() == 2 and game.player_nodes.has(1) and game.player_nodes.has(my_id))
	var me: Player = game.player_nodes[my_id]
	_check("client: our player is the local one and has the camera", me.is_local and me.get_children().any(func(c): return c is Camera2D))
	_check("client: the host's player is not ours", not game.player_nodes[1].is_local)
	_check("client: the game runs no rules here (the host does)", game.tether_system == null)

	await _sleep(1.2)
	_check("client: the rope appears from the host's snapshots", game._client_links.size() == 1 and game.link_lines.size() == 1)
	_check("client: the HUD shows a pod of 2", game.hud_text().begins_with("Pod 2"))

	var start := me.position
	Input.action_press("ui_right")  # same path a keyboard takes
	await _sleep(0.7)
	Input.action_release("ui_right")
	await _sleep(0.6)
	var moved := me.position.distance_to(start)
	_check("client: holding a key moves our own player on screen (%.0f px)" % moved, moved > 8.0)
	_check("client: the rope survived a short walk", game._client_links.size() == 1 and game._client_links[0]["state"] != game.LINK_SNAPPED)

	NetLocal.stop()
	_finish()
