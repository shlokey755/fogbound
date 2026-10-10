extends Control
## Lobby
## Pre-game pod assignment screen (design doc section 6). Host sees a
## Start button; clients see a Ready toggle. Pod membership is synced
## via NetRouter's lobby RPCs.

@onready var pod_list: VBoxContainer = $VBox/PodList
@onready var new_pod_button: Button = $VBox/NewPodButton
const PodCardScene := preload("res://scenes/pod_card.tscn")
@onready var start_button: Button = $VBox/StartButton
@onready var status_label: Label = $VBox/StatusLabel

var _next_team_id := 0


func _ready() -> void:
	NetRouter.lobby_state_changed.connect(_refresh)
	NetRouter.match_start_requested.connect(_on_match_start)
	new_pod_button.pressed.connect(_on_new_pod_pressed)
	start_button.pressed.connect(_on_start_pressed)
	start_button.visible = GameState.is_host()
	_refresh()


func _on_new_pod_pressed() -> void:
	var team_id := _next_team_id
	_next_team_id += 1
	NetRouter.request_join_pod.rpc_id(1, team_id)


func _join_pod(team_id: int) -> void:
	NetRouter.request_join_pod.rpc_id(1, team_id)


func _refresh() -> void:
	for child in pod_list.get_children():
		child.queue_free()

	for team_id in GameState.teams:
		var team: Dictionary = GameState.teams[team_id]
		var card := PodCardScene.instantiate()
		pod_list.add_child(card)
		card.setup(team_id, team, self)

	if GameState.is_host():
		var check: Dictionary = NetRouter.host_check_can_start()
		start_button.disabled = not check["ok"]
		status_label.text = check["reason"]
	else:
		status_label.text = "Waiting for host to start..."


func _on_start_pressed() -> void:
	if not GameState.is_host():
		return
	var check: Dictionary = NetRouter.host_check_can_start()
	if not check["ok"]:
		status_label.text = check["reason"]
		return

	GameState.match_seed = int(Time.get_unix_time_from_system())
	NetRouter.net_start_match.rpc(GameState.match_seed, GameState.maze_w, GameState.maze_h, JSON.stringify(GameState.teams))


func _on_match_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
