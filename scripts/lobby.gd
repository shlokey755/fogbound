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
@onready var level_picker: OptionButton = $VBox/LevelRow/LevelPicker
@onready var level_description: Label = $VBox/LevelDescription

var _next_team_id := 0
var _selected_level_id: int = -1  # -1 until _populate_level_picker sets it
var _picker_levels: Array = []    # mirrors level_picker's item order; see _populate_level_picker


func _ready() -> void:
	NetRouter.lobby_state_changed.connect(_refresh)
	NetRouter.match_start_requested.connect(_on_match_start)
	new_pod_button.pressed.connect(_on_new_pod_pressed)
	start_button.pressed.connect(_on_start_pressed)
	start_button.visible = GameState.is_host()
	_populate_level_picker()
	_refresh()


## Host picks the level; clients see the same picker but disabled, so
## everyone can read the chosen level's name/difficulty/description
## before the match starts without being able to change it themselves.
## Only levels SaveData.selectable_levels() currently allows show up
## here -- the secret level (level_data.gd id 99) is simply absent
## from this list until this device has unlocked it, same as any
## other "locked content" menu. See docs/WALKTHROUGH.md "Secret level".
func _populate_level_picker() -> void:
	level_picker.clear()
	_picker_levels = LevelData.selectable_levels()
	for lvl in _picker_levels:
		var label: String = "%s (%s)" % [lvl.name, lvl.difficulty]
		if lvl.secret:
			label = "✦ " + label  # small visual flag that this one isn't a normal level
		level_picker.add_item(label)
	var default_id: int = LevelData.default_level_id()
	_select_level_in_picker(default_id)
	_selected_level_id = default_id
	level_picker.disabled = not GameState.is_host()
	level_picker.item_selected.connect(_on_level_selected)
	_update_level_description()


func _select_level_in_picker(level_id: int) -> void:
	for i in range(_picker_levels.size()):
		if _picker_levels[i].id == level_id:
			level_picker.select(i)
			return


func _on_level_selected(index: int) -> void:
	if not GameState.is_host():
		return
	_selected_level_id = _picker_levels[index].id
	_update_level_description()


func _update_level_description() -> void:
	var lvl: LevelData.LevelDef = LevelData.get_level(_selected_level_id)
	level_description.text = "%dx%d maze, %d fragments. %s" % [lvl.width, lvl.height, lvl.fragment_count, lvl.description]


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
	NetRouter.net_start_match.rpc(GameState.match_seed, _selected_level_id, JSON.stringify(GameState.teams))


func _on_match_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
