extends Node
## NetRouter
## Game-level RPCs sit here rather than scattered across scene
## scripts, so the authority rules (design doc section 4.4) are all
## in one place. Transport-agnostic: works the same whether
## multiplayer.multiplayer_peer is the local ENet peer (NetLocal) or,
## in a future build, a WebRTC peer -- see docs/WALKTHROUGH.md.
##
## Host validates every incoming request using
## multiplayer.get_remote_sender_id() rather than trusting any peer
## id in the payload itself.

signal lobby_state_changed
signal match_start_requested
signal link_snapped_visual(a_id: int, b_id: int)
signal fragment_revealed(fragment_id: int, symbol: String)
signal match_finished
signal pod_unlocked(pod_members: Array)

var game_node: Node = null  # set by game.tscn on _ready so RPCs can reach scene state


func register_game_node(node: Node) -> void:
	game_node = node


# ---------------------------------------------------------------------------
# JSON round-trip normalization
#
# Godot's JSON encodes every number as a JSON number and decodes every
# JSON number back as a float, and every JSON object's keys come back
# as Strings -- never ints, even if they started as ints. Every RPC
# below that does JSON.stringify(...)/JSON.parse_string(...) on
# GameState data (teams, player_team, final_scores -- all keyed or
# filled with peer/team ids) MUST pass the result through one of
# these before anything calls .has()/indexes it with an int, because
# Dictionary/Array lookups compare by exact Variant type: 1 != 1.0 for
# Array.has(), and "0" != 0 for Dictionary key lookup, even though the
# == operator alone would say they're equal. This bit a real feature
# (the secret-level unlock check, which does pod.has(my_id) against
# JSON-decoded data) in testing -- see tests/boot_game_smoketest.gd.
# ---------------------------------------------------------------------------

## Recursively converts a JSON.parse_string() result back toward int
## where Godot's JSON round-trip turned an original int into a float
## (any float with no fractional part) or a Dictionary key into a
## String (any string that parses cleanly as an int). Leaves
## everything else (actual floats with a fractional part, non-numeric
## string keys like "name") untouched.
static func _denormalize_json_ints(value):
	if value is Dictionary:
		var out := {}
		for k in value:
			var new_key = k
			if k is String and k.is_valid_int():
				new_key = k.to_int()
			out[new_key] = _denormalize_json_ints(value[k])
		return out
	elif value is Array:
		var out := []
		for item in value:
			out.append(_denormalize_json_ints(item))
		return out
	elif value is float and value == floor(value) and not is_inf(value) and not is_nan(value):
		return int(value)
	else:
		return value


## JSON.parse_string() + _denormalize_json_ints() in one call -- use
## this instead of a bare JSON.parse_string() for any payload that
## will later be looked up or compared by int peer_id/team_id.
static func _parse_json_with_ints(json_str: String):
	return _denormalize_json_ints(JSON.parse_string(json_str))


# ---------------------------------------------------------------------------
# Lobby: names, pods, ready state, level choice, start
#
# The host owns all lobby state. Clients only send requests, and the host
# validates each one using the sender id Godot supplies (never an id in the
# payload). After every change the host sends the whole lobby to everyone
# (it is tiny), so a device that joins late or misses a packet is always
# brought fully up to date by the next one.
#
# Everything the UI calls goes through the small public functions below
# (join_pod, set_ready, ...). They work the same for the host and for
# clients: an RPC addressed to yourself never runs, so the host applies its
# own requests directly instead.
# ---------------------------------------------------------------------------

const NEW_POD := -1
const MAX_PODS := 26   # pod names are letters A-Z


## Host: start a fresh lobby with the host sitting in Pod A.
func host_open_lobby(host_name: String) -> void:
	GameState.reset_match()
	GameState.room_title = NetLocal.room_name
	GameState.player_names[1] = host_name
	GameState.player_ready[1] = true  # the host starts the match, so it never needs to ready up
	_host_move_to_pod(1, 0)
	_broadcast_lobby_state()


## Host: a new device connected. It lands in the first pod so that, by
## default, everyone is on one team and the host only has to press Start.
func host_peer_joined(peer_id: int) -> void:
	GameState.player_ready[peer_id] = false
	var first_pod: int = GameState.teams.keys().min() if not GameState.teams.is_empty() else 0
	_host_move_to_pod(peer_id, first_pod)
	_broadcast_lobby_state()


## Host: a device disconnected. Before the match that just empties its seat;
## during a match it is handled like a snapped rope (design doc 4.9).
func host_peer_left(peer_id: int) -> void:
	if GameState.match_started:
		on_peer_left(peer_id)
		return
	_host_remove_from_pods(peer_id)
	GameState.player_names.erase(peer_id)
	GameState.player_ready.erase(peer_id)
	_prune_empty_pods()
	_broadcast_lobby_state()


## UI entry points (host or client). team_id may be NEW_POD.
func join_pod(team_id: int) -> void:
	if GameState.is_host():
		_host_request_join(1, team_id)
	elif multiplayer.has_multiplayer_peer():
		request_join_pod.rpc_id(1, team_id)


func leave_pod() -> void:
	if GameState.is_host():
		_host_request_leave(1)
	elif multiplayer.has_multiplayer_peer():
		request_leave_pod.rpc_id(1)


func set_ready(is_ready: bool) -> void:
	if GameState.is_host():
		_host_set_ready(1, is_ready)
	elif multiplayer.has_multiplayer_peer():
		request_set_ready.rpc_id(1, is_ready)


## Tell the host what to call this device. Sent right after connecting.
func send_my_name() -> void:
	var my_name := SaveData.player_name()
	if GameState.is_host():
		_host_set_name(1, my_name)
	elif multiplayer.has_multiplayer_peer():
		request_set_name.rpc_id(1, my_name)


## Host only: the level everyone will play (shown to clients immediately).
func host_set_level(level_id: int) -> void:
	# get_level() falls back to the first level for an unknown id, so check the id itself.
	if not GameState.is_host() or LevelData.get_level(level_id).id != level_id:
		return
	GameState.level_id = level_id
	_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable")
func request_join_pod(team_id: int) -> void:
	if GameState.is_host():
		_host_request_join(multiplayer.get_remote_sender_id(), team_id)


@rpc("any_peer", "call_remote", "reliable")
func request_leave_pod() -> void:
	if GameState.is_host():
		_host_request_leave(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func request_set_ready(is_ready: bool) -> void:
	if GameState.is_host():
		_host_set_ready(multiplayer.get_remote_sender_id(), is_ready)


@rpc("any_peer", "call_remote", "reliable")
func request_set_name(player_name: String) -> void:
	if GameState.is_host():
		_host_set_name(multiplayer.get_remote_sender_id(), player_name)


func _host_request_join(peer_id: int, team_id: int) -> void:
	if GameState.match_started or not _is_lobby_member(peer_id):
		return
	if team_id != NEW_POD and not GameState.teams.has(team_id):
		return
	_host_move_to_pod(peer_id, team_id)
	_broadcast_lobby_state()


func _host_request_leave(peer_id: int) -> void:
	if GameState.match_started or not _is_lobby_member(peer_id):
		return
	_host_remove_from_pods(peer_id)
	_prune_empty_pods()
	_broadcast_lobby_state()


func _host_set_ready(peer_id: int, is_ready: bool) -> void:
	if GameState.match_started or not _is_lobby_member(peer_id):
		return
	GameState.player_ready[peer_id] = is_ready or peer_id == 1
	_broadcast_lobby_state()


func _host_set_name(peer_id: int, player_name: String) -> void:
	if GameState.match_started or not _is_lobby_member(peer_id):
		return
	var clean := NetDiscovery.sanitize(player_name, 16)
	if clean == "":
		return
	GameState.player_names[peer_id] = clean
	_broadcast_lobby_state()


func _is_lobby_member(peer_id: int) -> bool:
	return peer_id == 1 or multiplayer.get_peers().has(peer_id)


## Moves a player into a pod, creating it if needed, and takes them out of any
## other pod. Chain order is join order (design doc 3.7).
func _host_move_to_pod(peer_id: int, team_id: int) -> void:
	if team_id == NEW_POD:
		team_id = _next_free_pod_id()
		if team_id == -1:
			return
	if not GameState.teams.has(team_id):
		GameState.teams[team_id] = {"name": "Pod %s" % char(65 + team_id), "original_size": 0, "member_order": []}
	var members: Array = GameState.teams[team_id]["member_order"]
	if members.has(peer_id) or members.size() >= GameState.MAX_PLAYERS:
		return
	_host_remove_from_pods(peer_id)
	members.append(peer_id)
	GameState.player_team[peer_id] = team_id
	_prune_empty_pods()


func _host_remove_from_pods(peer_id: int) -> void:
	for team_id in GameState.teams:
		GameState.teams[team_id]["member_order"].erase(peer_id)
	GameState.player_team.erase(peer_id)


func _prune_empty_pods() -> void:
	for team_id in GameState.teams.keys():
		if GameState.teams[team_id]["member_order"].is_empty():
			GameState.teams.erase(team_id)


func _next_free_pod_id() -> int:
	for i in range(MAX_PODS):
		if not GameState.teams.has(i):
			return i
	return -1


@rpc("authority", "call_local", "reliable")
func net_lobby_state(teams_json: String, names_json: String, ready_json: String, level_id: int, room_title: String) -> void:
	if GameState.match_started and not GameState.is_host():
		return  # a late lobby packet must not disturb a running match
	GameState.teams = _parse_json_with_ints(teams_json)
	GameState.player_names = _parse_json_with_ints(names_json)
	GameState.player_ready = _parse_json_with_ints(ready_json)
	GameState.level_id = level_id
	GameState.room_title = room_title
	GameState.player_team.clear()
	for team_id in GameState.teams:
		for peer_id in GameState.teams[team_id]["member_order"]:
			GameState.player_team[peer_id] = team_id
	lobby_state_changed.emit()


func _broadcast_lobby_state() -> void:
	net_lobby_state.rpc(JSON.stringify(GameState.teams), JSON.stringify(GameState.player_names),
			JSON.stringify(GameState.player_ready), GameState.level_id, GameState.room_title)


## Why the Start button is (not) available. Mirrors design doc 6.3.
func host_check_can_start() -> Dictionary:
	if GameState.teams.is_empty():
		return {"ok": false, "reason": "No pods yet"}
	var everyone: Array = [1]
	for id in multiplayer.get_peers():
		everyone.append(int(id))
	for id in everyone:
		if not GameState.player_team.has(id):
			return {"ok": false, "reason": "%s is not in a pod" % GameState.display_name(id)}
	for team_id in GameState.teams:
		var team: Dictionary = GameState.teams[team_id]
		if team["member_order"].size() < GameState.MIN_TEAM_SIZE:
			return {"ok": false, "reason": "%s needs at least %d players" % [team["name"], GameState.MIN_TEAM_SIZE]}
	for id in everyone:
		if id != 1 and not GameState.player_ready.get(id, false):
			return {"ok": false, "reason": "Waiting for %s to ready up" % GameState.display_name(id)}
	return {"ok": true, "reason": ""}


## Host only. Starts the match for everyone (including the host's own scene
## change, since net_start_match is call_local).
func host_start_match(seed_value: int) -> Dictionary:
	var check := host_check_can_start()
	if not GameState.is_host() or not check["ok"]:
		return check
	GameState.match_seed = seed_value
	net_start_match.rpc(seed_value, GameState.level_id, JSON.stringify(GameState.teams))
	return check


@rpc("authority", "call_local", "reliable")
func net_start_match(seed_value: int, level_id: int, teams_json: String) -> void:
	GameState.match_seed = seed_value
	GameState.level_id = level_id
	var level: LevelData.LevelDef = LevelData.get_level(level_id)
	GameState.maze_w = level.width
	GameState.maze_h = level.height
	GameState.teams = _parse_json_with_ints(teams_json)
	for team_id in GameState.teams:
		GameState.teams[team_id]["original_size"] = GameState.teams[team_id]["member_order"].size()
	GameState.match_started = true
	match_start_requested.emit()


# ---------------------------------------------------------------------------
# Input (client -> host, unreliable so stale packets are simply dropped)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(dir_x: float, dir_y: float) -> void:
	if not GameState.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if game_node and game_node.has_method("apply_input"):
		game_node.apply_input(sender, Vector2(dir_x, dir_y))


## Local player's movement input. The host (and an offline player, who is
## their own host) applies it directly; clients send it to the host.
func send_input(dir: Vector2) -> void:
	if GameState.is_host():
		if game_node and game_node.has_method("apply_input"):
			game_node.apply_input(multiplayer.get_unique_id(), dir)
	elif multiplayer.has_multiplayer_peer():
		net_input.rpc_id(1, dir.x, dir.y)


# ---------------------------------------------------------------------------
# Snapshots (host -> clients, unreliable, ~20Hz)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func net_snapshot(packed: PackedByteArray) -> void:
	if game_node and game_node.has_method("apply_snapshot"):
		game_node.apply_snapshot(packed)


func broadcast_snapshot(packed: PackedByteArray) -> void:
	if GameState.is_host():
		net_snapshot.rpc(packed)


# ---------------------------------------------------------------------------
# Tether events (host -> clients, reliable)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func net_link_snapped(a_id: int, b_id: int) -> void:
	link_snapped_visual.emit(a_id, b_id)


func broadcast_link_snapped(a_id: int, b_id: int) -> void:
	if GameState.is_host():
		net_link_snapped.rpc(a_id, b_id)


# ---------------------------------------------------------------------------
# Fragments / clues (reliable: low frequency, must not be dropped)
# ---------------------------------------------------------------------------

func request_read_fragment(fragment_id: int) -> void:
	if GameState.is_host():
		_host_read_fragment(multiplayer.get_unique_id(), fragment_id)
	else:
		net_read_fragment.rpc_id(1, fragment_id)


## Bots have no peer of their own, so the host reads on their behalf.
func bot_read_fragment(bot_id: int, fragment_id: int) -> void:
	if GameState.is_host() and GameState.is_bot(bot_id):
		_host_read_fragment(bot_id, fragment_id)


@rpc("any_peer", "call_remote", "reliable")
func net_read_fragment(fragment_id: int) -> void:
	if not GameState.is_host():
		return
	_host_read_fragment(multiplayer.get_remote_sender_id(), fragment_id)


func _host_read_fragment(peer_id: int, fragment_id: int) -> void:
	if not GameState.notebook.has(peer_id):
		GameState.notebook[peer_id] = {}
	GameState.notebook[peer_id][fragment_id] = true
	if fragment_id < GameState.exit_sequence.size():
		var symbol: String = GameState.exit_sequence[fragment_id]
		var pod: Array = _pod_containing(peer_id)
		net_fragment_revealed.rpc(pod, fragment_id, symbol)


## call_local so the host's own player (and the offline human) also see the
## symbol they just read; with call_remote only clients ever got the reveal.
## The membership test keeps a rival pod's reads private.
@rpc("authority", "call_local", "reliable")
func net_fragment_revealed(pod_members: Array, fragment_id: int, symbol: String) -> void:
	if pod_members.has(multiplayer.get_unique_id()):
		fragment_revealed.emit(fragment_id, symbol)


## The host calls this when a pod opens the exit; only that pod's members
## are told (a rival pod's progress stays private).
func broadcast_pod_unlocked(pod: Array) -> void:
	if GameState.is_host():
		net_pod_unlocked.rpc(pod)


@rpc("authority", "call_local", "reliable")
func net_pod_unlocked(pod_members: Array) -> void:
	if pod_members.has(multiplayer.get_unique_id()):
		pod_unlocked.emit(pod_members)


func _pod_containing(peer_id: int) -> Array:
	for pod in GameState.pods:
		if pod.has(peer_id):
			return pod
	return [peer_id]


# ---------------------------------------------------------------------------
# Elimination / scoring / match end (host -> clients, reliable)
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func net_match_finished(scores_json: String) -> void:
	GameState.final_scores = _parse_json_with_ints(scores_json)
	GameState.match_over = true
	_check_secret_level_unlock()
	match_finished.emit()


## Runs on every peer (this RPC is call_local), each checking only
## its OWN device's SaveData -- unlocks are per-device, not
## per-match, so a teammate who escaped intact unlocks the secret
## level on their own machine's save file, not everyone else's.
## Condition: finish LevelData.SECRET_LEVEL_UNLOCK_SOURCE_ID with a
## pod that scored the top tier (1200 -- a complete, unbroken team;
## see score_table.gd) and this device's own player was in that pod.
func _check_secret_level_unlock() -> void:
	if GameState.level_id != LevelData.SECRET_LEVEL_UNLOCK_SOURCE_ID:
		return
	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for entry in GameState.final_scores:
		if entry.get("points", 0) < 1200:
			continue
		var pod: Array = entry.get("pod", [])
		if pod.has(my_id):
			SaveData.unlock_level(LevelData.SECRET_LEVEL_ID)
			return


func broadcast_match_finished() -> void:
	if GameState.is_host():
		net_match_finished.rpc(JSON.stringify(GameState.final_scores))


func on_peer_left(peer_id: int) -> void:
	if game_node and game_node.has_method("on_player_disconnected"):
		game_node.on_player_disconnected(peer_id)
