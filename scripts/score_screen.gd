extends Control
## ScoreScreen
## Per-pod results screen (design doc section 10) shown once
## NetRouter.match_finished fires. Reads GameState.final_scores,
## which the host populated and broadcast via net_match_finished.

@onready var results_list: VBoxContainer = $VBox/ResultsList
@onready var back_button: Button = $VBox/BackButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_populate()


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
