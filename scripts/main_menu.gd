extends Control
## MainMenu
## Entry point: host or join over LAN hotspot. Online room codes
## (design doc section 4.3) are not wired up in this MVP -- see
## docs/WALKTHROUGH.md for the follow-up phase.

@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var ip_field: LineEdit = $VBox/IPField
@onready var room_name_field: LineEdit = $VBox/RoomNameField
@onready var status_label: Label = $VBox/StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetLocal.peer_list_changed.connect(_on_peer_list_changed)


func _on_host_pressed() -> void:
	var room_name: String = room_name_field.text if room_name_field.text != "" else "Fogbound"
	NetLocal.host_game(room_name)
	status_label.text = "Hosting \"%s\" on port %d. Share your hotspot IP with others." % [room_name, NetLocal.PORT]
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_join_pressed() -> void:
	var ip: String = ip_field.text.strip_edges()
	if ip == "":
		status_label.text = "Enter the host's IP address first."
		return
	NetLocal.join_game(ip)
	status_label.text = "Connecting to %s..." % ip


func _on_peer_list_changed() -> void:
	if not GameState.is_host() and multiplayer.has_multiplayer_peer():
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
