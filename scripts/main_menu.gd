extends Control
## MainMenu
## Entry point. Three ways to play:
##   * Play offline (bots)  - alone, nothing to set up
##   * Host game            - you are the host; everyone else joins you
##   * Join game            - find a host on the same Wi-Fi / hotspot
##
## For a hotspot game, connect every phone to the hotspot FIRST (in the phone's
## own Wi-Fi settings), then one phone taps Host and the rest tap Join.
##
## Command-line shortcuts for testing on one computer (everything after `--`
## goes to the game): `--name=Ann`, `--auto-host`, `--auto-join`.
## tools/run_instances.sh uses them to open several windows in one go.

@onready var offline_button: Button = $VBox/OfflineButton
@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var name_field: LineEdit = $VBox/NameRow/NameField
@onready var status_label: Label = $VBox/StatusLabel


func _ready() -> void:
	theme = CompactTheme.make()  # the default font is too large for a 320x180 view
	NetLocal.stop()              # being on the menu means no session is running
	offline_button.pressed.connect(_on_offline_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	name_field.text = SaveData.player_name()
	name_field.text_submitted.connect(func(_t): _save_name())
	name_field.focus_exited.connect(_save_name)

	status_label.text = NetLocal.last_message
	NetLocal.last_message = ""

	_apply_command_line()


func _save_name() -> void:
	SaveData.set_player_name(name_field.text, not NetLocal.temp_name)
	name_field.text = SaveData.player_name()


func _on_offline_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/offline_setup.tscn")


func _on_host_pressed() -> void:
	_save_name()
	var err := NetLocal.host_game()
	if err != OK:
		status_label.text = NetLocal.last_message
		return
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_join_pressed() -> void:
	_save_name()
	get_tree().change_scene_to_file("res://scenes/join_screen.tscn")


## Test shortcuts, applied once per run (not again when returning to this menu).
func _apply_command_line() -> void:
	if NetLocal.cmdline_applied:
		return
	NetLocal.cmdline_applied = true
	var want_host := false
	var want_join := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--name="):
			NetLocal.temp_name = true
			SaveData.set_player_name(arg.substr(7), false)  # this run only
			name_field.text = SaveData.player_name()
		elif arg == "--auto-host":
			want_host = true
		elif arg == "--auto-join":
			want_join = true
	if want_host:
		_on_host_pressed.call_deferred()
	elif want_join:
		NetLocal.auto_join = true
		_on_join_pressed.call_deferred()
