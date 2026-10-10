extends Node
## NetOnline
## Reference implementation of the WebRTC + room-code transport
## (design doc section 4.3). NOT wired up as an autoload in
## project.godot yet, and NOT covered by the test suite -- this file
## ships as a documented starting point for Phase 6
## (docs/WALKTHROUGH.md), not as tested production code.
##
## To activate it:
##   1. Add the webrtc-native GDExtension for your target platforms
##      (Android/desktop; Web export has WebRTC built in). Verify the
##      release matching your Godot version before relying on this.
##   2. Add "NetOnline" to the [autoload] section of project.godot.
##   3. Point SIGNAL_URL at a running server/server.js instance.
##   4. Add a "Create Online Room" / "Join by code" path in
##      main_menu.gd alongside the existing hotspot host/join buttons,
##      calling host_room() / join_room(code) instead of
##      NetLocal.host_game() / join_game().
##   5. Everything downstream (net_router.gd RPCs, game_controller.gd,
##      tether_system.gd, etc.) is transport-agnostic and needs NO
##      changes -- they all go through multiplayer.multiplayer_peer,
##      which this script sets to a WebRTCMultiplayerPeer the same
##      way net_local.gd sets it to an ENetMultiplayerPeer.
##
## Not implemented here (left for a later pass, see design doc
## section 4.3/4.9 and open question 7 in the design doc): TURN
## credential fetching from a trusted endpoint (hardcoding long-lived
## TURN credentials client-side is not safe for a public release),
## reconnect-on-drop, and host migration.

signal room_created(code: String)
signal join_failed(reason: String)

const SIGNAL_URL := "wss://signal.example.com"  # replace with your deployed server/server.js
const RTC_CONFIG := {
	"iceServers": [
		{"urls": ["stun:stun.l.google.com:19302"]},
		# {"urls": ["turn:turn.example.com:3478"], "username": "user", "credential": "secret"},
	]
}

var ws := WebSocketPeer.new()
var rtc := WebRTCMultiplayerPeer.new()
var conns: Dictionary = {}  # peer_id -> WebRTCPeerConnection
var _first_msg := ""
var _opened := false


func host_room() -> void:
	rtc.create_server()
	multiplayer.multiplayer_peer = rtc
	_open({"type": "create_room"})


func join_room(code: String) -> void:
	_open({"type": "join_room", "code": code})


func _open(msg: Dictionary) -> void:
	_first_msg = JSON.stringify(msg)
	ws.connect_to_url(SIGNAL_URL)


func _process(_delta: float) -> void:
	ws.poll()
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _opened:
		_opened = true
		ws.send_text(_first_msg)
	while ws.get_available_packet_count() > 0:
		_on_message(JSON.parse_string(ws.get_packet().get_string_from_utf8()))


func _on_message(m: Dictionary) -> void:
	match m.get("type", ""):
		"room_created":
			room_created.emit(m.code)
		"joined":  # client side
			rtc.create_client(int(m.id))
			multiplayer.multiplayer_peer = rtc
			_new_conn(1, true)  # client sends the offer to the host
		"peer_joined":  # host side
			_new_conn(int(m.id), false)
		"offer", "answer":
			if conns.has(int(m.from)):
				conns[int(m.from)].set_remote_description(m.type, m.sdp)
		"candidate":
			if conns.has(int(m.from)):
				conns[int(m.from)].add_ice_candidate(m.media, int(m.index), m.name)
		"error":
			join_failed.emit(m.get("reason", "unknown"))


func _new_conn(id: int, make_offer: bool) -> void:
	var pc := WebRTCPeerConnection.new()
	pc.initialize(RTC_CONFIG)
	pc.session_description_created.connect(func(type, sdp):
		pc.set_local_description(type, sdp)
		_send({"type": type, "to": id, "sdp": sdp}))
	pc.ice_candidate_created.connect(func(media, index, name):
		_send({"type": "candidate", "to": id, "media": media, "index": index, "name": name}))
	conns[id] = pc
	rtc.add_peer(pc, id)
	if make_offer:
		pc.create_offer()


func _send(msg: Dictionary) -> void:
	ws.send_text(JSON.stringify(msg))
