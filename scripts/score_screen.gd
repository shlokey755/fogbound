extends Control
## ScoreScreen
## Per-pod results screen (design doc section 10) shown once
## NetRouter.match_finished fires. Reads GameState.final_scores,
## which the host populated and broadcast via net_match_finished.

@onready var results_list: VBoxContainer = $VBox/ResultsList
@onready var back_button: Button = $VBox/BackButton
@onready var unlock_banner: Label = $VBox/UnlockBanner


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_populate()
	_show_unlock_banner_if_any()


## The actual unlock_level() call already happened (in
## net_router.gd's net_match_finished, before this scene even loaded)
## -- this only surfaces it. consume_just_unlocked() returns -1 on
## every subsequent screen view, so the banner shows exactly once,
## the run it was earned.
func _show_unlock_banner_if_any() -> void:
	var unlocked_id: int = SaveData.consume_just_unlocked()
	if unlocked_id == -1:
		unlock_banner.visible = false
		return
	var lvl: LevelData.LevelDef = LevelData.get_level(unlocked_id)
	unlock_banner.text = "✦ New level unlocked: %s — it's now in your level picker." % lvl.name
	unlock_banner.visible = true


func _populate() -> void:
	for child in results_list.get_children():
		child.queue_free()

	# Offline there is one human; in a hosted match "you" is this device's own id.
	if GameState.offline_mode or GameState.room_title != "":
		var verdict := Label.new()
		verdict.text = "You escaped!" if _human_scored() else "You didn't make it out."
		results_list.add_child(verdict)

	if GameState.final_scores.is_empty():
		var label := Label.new()
		label.text = "No pod reached the exit."
		results_list.add_child(label)
		return

	for entry in GameState.final_scores:
		var label := Label.new()
		var pod: Array = entry["pod"]
		var team_name: String = GameState.teams.get(entry["team_id"], {}).get("name", "Pod")
		var you := " (you)" if pod.has(_my_id()) else ""
		label.text = "%s%s — %d points\n%s" % [team_name, you, entry["points"], _member_names(pod)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		results_list.add_child(label)


## This device's player: the offline human, or our id in a hosted match.
func _my_id() -> int:
	if GameState.offline_mode:
		return GameState.human_id
	return multiplayer.get_unique_id()


func _member_names(pod: Array) -> String:
	var names: Array = []
	for peer_id in pod:
		names.append(GameState.display_name(int(peer_id)))
	return ", ".join(names)


func _human_scored() -> bool:
	for entry in GameState.final_scores:
		if entry["pod"].has(_my_id()):
			return true
	return false


func _on_back_pressed() -> void:
	NetLocal.stop()
	GameState.reset_match()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
