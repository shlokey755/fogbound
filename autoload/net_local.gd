extends Node
## NetLocal
## Local-network play over a phone hotspot or shared Wi-Fi, using Godot's
## built-in ENet peer. The flow it supports:
##
##   1. Everyone is on the same Wi-Fi/hotspot (set up in the phone's settings,
##      outside the game).
##   2. The host taps "Host game": host_game() opens the game port and starts
##      answering discovery probes.
##   3. Everyone else taps "Join game": start_scan() sends probes, replies fill
##      `rooms`, the join screen lists them, tapping one calls join_game().
##
## Discovery details (why probe + reply instead of broadcast announcements) are
## in scripts/net_discovery.gd. The online room-code mode (autoload/net_online.gd)
## is still a stub; see docs/WALKTHROUGH.md "Phase 6".

signal peer_list_changed
signal rooms_changed
signal join_succeeded
signal join_failed(reason: String)

const DEFAULT_GAME_PORT := 7777
const DEFAULT_DISCOVERY_PORT := 7778
const SCAN_EVERY := 1.5          # seconds between probe rounds while the join screen is open
const ROOM_EXPIRES_AFTER := 5.0  # seconds without a reply before a room leaves the list
const JOIN_TIMEOUT := 8.0        # seconds to wait for the host before giving up

## Tests (and two games on one machine) can move these before hosting/joining.
var game_port: int = DEFAULT_GAME_PORT
var discovery_port: int = DEFAULT_DISCOVERY_PORT

## One-shot message for the next menu screen ("The host left the game.").
var last_message: String = ""

## Rooms found by the last scans. host_id -> {name, players, max, level, port, started, ip, seen}
var rooms: Dictionary = {}

var room_name: String = "Fogbound"
var hosting: bool = false

## Test shortcuts set by the main menu from the command line (see main_menu.gd).
var cmdline_applied: bool = false
var auto_join: bool = false
var temp_name: bool = false  # --name= was given: never write the name to the save file

var _host_id: String = ""          # random token so one room answering from two addresses is listed once
var _host_udp: PacketPeerUDP       # host: bound to the discovery port, answers probes
var _scan_udp: PacketPeerUDP       # joiner: unbound, sends probes and receives replies
var _scanning: bool = false
var _scan_timer: float = 0.0
var _joining: bool = false
var _join_timer: float = 0.0
var _local_ips: Array = []


func _ready() -> void:
	# Optional test/dev switches, e.g. to run two games on one machine:
	#   godot --path . -- --game-port=27777 --discovery-port=27778
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game-port=") and arg.substr(12).is_valid_int():
			game_port = int(arg.substr(12))
		elif arg.begins_with("--discovery-port=") and arg.substr(17).is_valid_int():
			discovery_port = int(arg.substr(17))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# Hosting and joining
# ---------------------------------------------------------------------------

## Opens a room. Returns OK, or the Godot error code if the port is taken
## (usually: another Fogbound is already hosting on this machine).
func host_game(p_room_name: String = "") -> Error:
	stop()
	room_name = NetDiscovery.sanitize(p_room_name if p_room_name != "" else "%s's room" % SaveData.player_name())
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(game_port, GameState.MAX_PLAYERS - 1)
	if err != OK:
		last_message = "Could not host: port %d is busy (is another Fogbound already hosting?)" % game_port
		push_warning("Fogbound: " + last_message)
		return err
	multiplayer.multiplayer_peer = peer
	hosting = true
	_host_id = "%06x" % (randi() & 0xFFFFFF)
	_local_ips = NetDiscovery.lan_addresses(IP.get_local_addresses())

	_host_udp = PacketPeerUDP.new()
	var bind_err := _host_udp.bind(discovery_port)
	if bind_err != OK:
		# Not fatal: joiners can still type this device's address by hand.
		push_warning("Fogbound: discovery port %d unavailable (%s); joiners must type the host address" % [discovery_port, bind_err])
		_host_udp = null

	NetRouter.host_open_lobby(SaveData.player_name())
	return OK


## Connects to a host found on the join screen (or typed by hand).
func join_game(ip: String, port: int = 0) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port if port > 0 else game_port)
	if err != OK:
		join_failed.emit("Could not connect to \"%s\" (check the address)" % ip)
		return err
	multiplayer.multiplayer_peer = peer
	_joining = true
	_join_timer = 0.0
	return OK


## Leaves any room (or stops hosting) and drops back to the default offline
## peer, so the next offline match behaves exactly like a fresh start.
func stop() -> void:
	stop_scan()
	_joining = false
	hosting = false
	if _host_udp:
		_host_udp.close()
		_host_udp = null
	var current := multiplayer.multiplayer_peer
	if current != null and not (current is OfflineMultiplayerPeer):
		current.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


# ---------------------------------------------------------------------------
# Multiplayer signals
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if GameState.is_host():
		if GameState.match_started:
			# Rooms lock when the match starts (design doc 4.3): no late joiners.
			multiplayer.multiplayer_peer.disconnect_peer(id)
			return
		NetRouter.host_peer_joined(id)
	peer_list_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if GameState.is_host():
		NetRouter.host_peer_left(id)
	peer_list_changed.emit()


func _on_connected_to_server() -> void:
	_joining = false
	NetRouter.send_my_name()
	join_succeeded.emit()


func _on_connection_failed() -> void:
	_joining = false
	stop()
	join_failed.emit("Could not reach the host. Same Wi-Fi? Host game still open?")


## The host closed the game or the network dropped. Mid-lobby or mid-match
## that ends the session for this device; on the score screen it is harmless.
func _on_server_disconnected() -> void:
	var finished := GameState.match_over
	stop()
	if finished:
		return
	last_message = "The host left the game."
	GameState.reset_match()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

func start_scan() -> void:
	stop_scan()
	rooms.clear()
	_local_ips = NetDiscovery.lan_addresses(IP.get_local_addresses())
	_scan_udp = PacketPeerUDP.new()
	_scan_udp.set_broadcast_enabled(true)
	_scanning = true
	_scan_timer = 0.0  # probe right away
	rooms_changed.emit()


func stop_scan() -> void:
	_scanning = false
	if _scan_udp:
		_scan_udp.close()
		_scan_udp = null


## Rooms sorted by name, newest first for equal names, ready for a list UI.
func room_list() -> Array:
	var list: Array = rooms.values()
	list.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return list


## "192.168.43.1" style address(es) other devices can type to reach this one.
func my_addresses() -> Array:
	return NetDiscovery.lan_addresses(IP.get_local_addresses())


func _process(delta: float) -> void:
	if _joining:
		_join_timer += delta
		if _join_timer > JOIN_TIMEOUT:
			_joining = false
			stop()
			join_failed.emit("The host did not answer. Same Wi-Fi? Host game still open?")
	if _host_udp:
		_answer_probes()
	if _scanning and _scan_udp:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = SCAN_EVERY
			_send_probes()
		_read_replies()


## Host side: reply to every probe with a one-line room description.
func _answer_probes() -> void:
	while _host_udp.get_available_packet_count() > 0:
		var msg := _host_udp.get_packet().get_string_from_utf8()
		var from_ip := _host_udp.get_packet_ip()
		var from_port := _host_udp.get_packet_port()
		if not NetDiscovery.is_probe(msg):
			continue
		_host_udp.set_dest_address(from_ip, from_port)
		_host_udp.put_packet(_room_reply().to_utf8_buffer())


func _room_reply() -> String:
	var level_name := "?"
	if LevelData.get_level(GameState.level_id) != null:
		level_name = LevelData.get_level(GameState.level_id).name
	return NetDiscovery.build_reply(_host_id, room_name, multiplayer.get_peers().size() + 1,
			GameState.MAX_PLAYERS, level_name, game_port, GameState.match_started)


func _send_probes() -> void:
	var probe := NetDiscovery.PROBE.to_utf8_buffer()
	for target in NetDiscovery.scan_targets(_local_ips):
		if _scan_udp.set_dest_address(target, discovery_port) == OK:
			_scan_udp.put_packet(probe)
	# Forget rooms that stopped answering.
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	for id in rooms.keys():
		if now - float(rooms[id]["seen"]) > ROOM_EXPIRES_AFTER:
			rooms.erase(id)
			changed = true
	if changed:
		rooms_changed.emit()


func _read_replies() -> void:
	var changed := false
	while _scan_udp.get_available_packet_count() > 0:
		var msg := _scan_udp.get_packet().get_string_from_utf8()
		var from_ip := _scan_udp.get_packet_ip()
		var info := NetDiscovery.parse_reply(msg)
		if info.is_empty():
			continue
		var id: String = info["host_id"]
		var is_new := not rooms.has(id)
		# Keep the first address a room answered from; replies from the same
		# room via another interface only refresh it.
		info["ip"] = from_ip if is_new else rooms[id]["ip"]
		info["seen"] = Time.get_ticks_msec() / 1000.0
		if is_new or rooms[id]["players"] != info["players"] or rooms[id]["level"] != info["level"] \
				or rooms[id]["started"] != info["started"] or rooms[id]["name"] != info["name"]:
			changed = true
		rooms[id] = info
	if changed:
		rooms_changed.emit()
