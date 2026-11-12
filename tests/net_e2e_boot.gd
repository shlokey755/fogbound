extends Node
## Entry scene of the two-process test (see tests/net_e2e.sh). All it does is
## hand over to the real main menu and leave a runner node on the tree root,
## where it survives the scene changes the real game makes (menu -> lobby ->
## game).


func _ready() -> void:
	var runner: Node = load("res://tests/net_e2e_runner.gd").new()
	get_tree().root.add_child.call_deferred(runner)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
