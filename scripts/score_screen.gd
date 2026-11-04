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

	if GameState.final_scores.is_empty():
		var label := Label.new()
		label.text = "No pod reached the exit."
		results_list.add_child(label)
		return

	for entry in GameState.final_scores:
		var label := Label.new()
		var pod: Array = entry["pod"]
		var team_name: String = GameState.teams.get(entry["team_id"], {}).get("name", "Pod")
		label.text = "%s — %d players — %d points" % [team_name, pod.size(), entry["points"]]
		results_list.add_child(label)


func _on_back_pressed() -> void:
	GameState.reset_match()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
