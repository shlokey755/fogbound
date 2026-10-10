extends Node
## NetLocal
## LAN / Wi-Fi hotspot transport using Godot's built-in ENet peer.
## This is the only transport implemented in the MVP; the design doc's
## WebRTC + room-code online mode (section 4.3) is deliberately left
## unimplemented here -- see docs/WALKTHROUGH.md "Phase 6" for why and
## how to add it later without touching gameplay code.

const PORT := 7777
const BROADCAST_PORT := 7778
const MAX_PLAYERS := GameState.MAX_PLAYERS

signal peer_list_changed

var udp := PacketPeerUDP.new()
var _advertise_timer: Timer
var _room_name: String = "Fogbound"
var _advertising := false
var _listening := false
var discovered_rooms: Dictionary = {}  # ip -> {name, last_seen}


func host_game(room_name: String = "Fogbound") -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		push_error("Fogbound: failed to create ENet server: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_room_name = room_name
	_start_advertising()


func join_game(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("Fogbound: failed to create ENet client: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func stop() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_stop_advertising()
	stop_listening()


func _on_peer_connected(id: int) -> void:
	peer_list_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	peer_list_changed.emit()
	if GameState.is_host():
		NetRouter.on_peer_left(id)


# ---------------------------------------------------------------------------
# LAN discovery. Best-effort: some hotspots block UDP broadcast between
# clients, so the lobby UI must always offer manual IP entry too.
# ---------------------------------------------------------------------------

func start_advertising(room_name: String) -> void:
	_room_name = room_name
	_start_advertising()


func _start_advertising() -> void:
	if _advertising:
		return
	udp.set_broadcast_enabled(true)
	var err := udp.set_dest_address("255.255.255.255", BROADCAST_PORT)
	if err != OK:
		push_warning("Fogbound: broadcast address unavailable, host IP must be shared manually")
		return
	_advertise_timer = Timer.new()
	_advertise_timer.wait_time = 1.0
	_advertise_timer.timeout.connect(_broadcast_tick)
	add_child(_advertise_timer)
	_advertise_timer.start()
	_advertising = true


func _stop_advertising() -> void:
	if _advertise_timer:
		_advertise_timer.stop()
		_advertise_timer.queue_free()
		_advertise_timer = null
	_advertising = false


func _broadcast_tick() -> void:
	var payload := "FOGBOUND|%s|%d" % [_room_name, GameState.MAX_PLAYERS]
	udp.put_packet(payload.to_utf8_buffer())


func start_listening() -> void:
	if _listening:
		return
	var err := udp.bind(BROADCAST_PORT)
	if err != OK:
		push_warning("Fogbound: could not bind discovery port %d (err %s); use manual IP entry" % [BROADCAST_PORT, err])
		return
	_listening = true
	discovered_rooms.clear()


func stop_listening() -> void:
	if _listening:
		udp.close()
		_listening = false


func _process(_delta: float) -> void:
	if not _listening:
		return
	while udp.get_available_packet_count() > 0:
		var msg: String = udp.get_packet().get_string_from_utf8()
		var ip: String = udp.get_packet_ip()
		if msg.begins_with("FOGBOUND|"):
			var parts := msg.split("|")
			var room_name: String = parts[1] if parts.size() > 1 else "Fogbound"
			discovered_rooms[ip] = {"name": room_name, "last_seen": Time.get_ticks_msec()}
