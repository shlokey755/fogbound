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

var game_node: Node = null  # set by game.tscn on _ready so RPCs can reach scene state


func register_game_node(node: Node) -> void:
	game_node = node


# ---------------------------------------------------------------------------
# Lobby: pod assignment, ready state, start
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func request_join_pod(team_id: int) -> void:
	if not GameState.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	_assign_to_pod(sender, team_id)


@rpc("any_peer", "call_remote", "reliable")
func request_leave_pod() -> void:
	if not GameState.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	GameState.player_team.erase(sender)
	_broadcast_lobby_state()


func _assign_to_pod(peer_id: int, team_id: int) -> void:
	if not GameState.teams.has(team_id):
		GameState.teams[team_id] = {"name": "Pod %s" % char(65 + team_id), "original_size": 0, "member_order": []}
	var team: Dictionary = GameState.teams[team_id]
	if team["member_order"].size() >= GameState.MAX_PLAYERS:
		return
	GameState.player_team[peer_id] = team_id
	if not team["member_order"].has(peer_id):
		team["member_order"].append(peer_id)
	_broadcast_lobby_state()


@rpc("authority", "call_local", "reliable")
func net_lobby_state(teams_json: String, player_team_json: String) -> void:
	GameState.teams = JSON.parse_string(teams_json)
	GameState.player_team = JSON.parse_string(player_team_json)
	lobby_state_changed.emit()


func _broadcast_lobby_state() -> void:
	net_lobby_state.rpc(JSON.stringify(GameState.teams), JSON.stringify(GameState.player_team))


func host_check_can_start() -> Dictionary:
	# Mirrors design doc section 6.3 start conditions.
	if GameState.teams.is_empty():
		return {"ok": false, "reason": "No pods formed yet"}
	for team_id in GameState.teams:
		var team: Dictionary = GameState.teams[team_id]
		if team["member_order"].size() < GameState.MIN_TEAM_SIZE:
			return {"ok": false, "reason": "%s needs at least %d players" % [team["name"], GameState.MIN_TEAM_SIZE]}
	return {"ok": true, "reason": ""}


@rpc("authority", "call_local", "reliable")
func net_start_match(seed_value: int, w: int, h: int, teams_json: String) -> void:
	GameState.match_seed = seed_value
	GameState.maze_w = w
	GameState.maze_h = h
	GameState.teams = JSON.parse_string(teams_json)
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


func send_input(dir: Vector2) -> void:
	if multiplayer.has_multiplayer_peer() and not GameState.is_host():
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


@rpc("authority", "call_remote", "reliable")
func net_fragment_revealed(pod_members: Array, fragment_id: int, symbol: String) -> void:
	if pod_members.has(multiplayer.get_unique_id()) or not multiplayer.has_multiplayer_peer():
		fragment_revealed.emit(fragment_id, symbol)


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
	GameState.final_scores = JSON.parse_string(scores_json)
	GameState.match_over = true
	match_finished.emit()


func broadcast_match_finished() -> void:
	if GameState.is_host():
		net_match_finished.rpc(JSON.stringify(GameState.final_scores))


func on_peer_left(peer_id: int) -> void:
	if game_node and game_node.has_method("on_player_disconnected"):
		game_node.on_player_disconnected(peer_id)
