class_name Lobby
extends Control
## Lobby
## The pre-match room for a hosted game (design doc section 6). Built in code,
## like the offline setup screen, so the whole screen is one readable script.
##
##   * Everyone sees the room, who is in it, and which pod each person is in.
##     By default everybody lands in Pod A (one big team); anyone can move to
##     another pod or start a new one.
##   * The HOST chooses the level and an optional seed. Clients see the choice
##     update live but cannot change it.
##   * Clients tap Ready; the host's Start button lights up once every pod has
##     at least two players and every client is ready.
##
## All state lives in GameState and is owned by the host; this screen only
## shows it and sends requests through NetRouter (see the lobby section there).

var _banner: Label
var _level_picker: OptionButton
var _level_label: Label
var _level_info: Label
var _seed_field: LineEdit
var _pod_box: VBoxContainer
var _status: Label
var _ready_button: Button
var _start_button: Button
var _levels: Array = []
var _updating := false


func _ready() -> void:
	theme = CompactTheme.make()
	_build_ui()
	NetRouter.lobby_state_changed.connect(_refresh)
	NetRouter.match_start_requested.connect(_on_match_start)
	NetLocal.peer_list_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if NetRouter.lobby_state_changed.is_connected(_refresh):
		NetRouter.lobby_state_changed.disconnect(_refresh)
	if NetRouter.match_start_requested.is_connected(_on_match_start):
		NetRouter.match_start_requested.disconnect(_on_match_start)
	if NetLocal.peer_list_changed.is_connected(_refresh):
		NetLocal.peer_list_changed.disconnect(_refresh)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 3)
	margin.add_child(page)

	_banner = Label.new()
	_banner.clip_text = true
	page.add_child(_banner)

	if GameState.is_host():
		var row := HBoxContainer.new()
		page.add_child(row)
		var level_text := Label.new()
		level_text.text = "Level"
		row.add_child(level_text)
		_level_picker = OptionButton.new()
		_level_picker.clip_text = true
		_level_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_levels = LevelData.selectable_levels()
		for lvl in _levels:
			_level_picker.add_item("%s (%s)" % [lvl.name, lvl.difficulty])
		_level_picker.item_selected.connect(_on_level_selected)
		row.add_child(_level_picker)
		var seed_text := Label.new()
		seed_text.text = "Seed"
		row.add_child(seed_text)
		_seed_field = LineEdit.new()
		_seed_field.placeholder_text = "random"
		_seed_field.custom_minimum_size.x = 48
		row.add_child(_seed_field)
	else:
		_level_label = Label.new()
		_level_label.clip_text = true
		page.add_child(_level_label)

	_level_info = Label.new()
	_level_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_info.modulate = Color(1, 1, 1, 0.7)
	page.add_child(_level_info)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_pod_box = VBoxContainer.new()
	_pod_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pod_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_pod_box)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status)

	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_on_leave_pressed)
	buttons.add_child(leave)
	var new_pod := Button.new()
	new_pod.text = "New pod"
	new_pod.pressed.connect(func(): NetRouter.join_pod(NetRouter.NEW_POD))
	buttons.add_child(new_pod)
	if GameState.is_host():
		_start_button = Button.new()
		_start_button.text = "START"
		_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_start_button.pressed.connect(_on_start_pressed)
		buttons.add_child(_start_button)
	else:
		_ready_button = Button.new()
		_ready_button.toggle_mode = true
		_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ready_button.toggled.connect(func(on: bool): if not _updating: NetRouter.set_ready(on))
		buttons.add_child(_ready_button)


func _refresh() -> void:
	if _banner == null:
		return
	_updating = true
	var my_id := multiplayer.get_unique_id()
	var count := multiplayer.get_peers().size() + 1

	var title: String = GameState.room_title if GameState.room_title != "" else "Fogbound"
	_banner.text = "%s  (%d/%d)" % [title, count, GameState.MAX_PLAYERS]

	var lvl: LevelData.LevelDef = LevelData.get_level(GameState.level_id)
	_level_info.text = "%dx%d maze, %d fragments. %s" % [lvl.width, lvl.height, lvl.fragment_count, lvl.description]
	if _level_picker:
		for i in range(_levels.size()):
			if _levels[i].id == GameState.level_id:
				_level_picker.select(i)
	else:
		_level_label.text = "Level: %s (%s) - chosen by the host" % [lvl.name, lvl.difficulty]

	_rebuild_pods(my_id)

	var my_pod: int = GameState.player_team.get(my_id, -1)
	if GameState.is_host():
		var check: Dictionary = NetRouter.host_check_can_start()
		_start_button.disabled = not check["ok"]
		_status.text = check["reason"] if not check["ok"] else "Everyone is ready. Press START."
	else:
		_ready_button.button_pressed = GameState.player_ready.get(my_id, false)
		_ready_button.text = "Ready!" if _ready_button.button_pressed else "Tap when ready"
		_ready_button.disabled = my_pod == -1
		_status.text = "Waiting for the host to start..." if my_pod != -1 else "Join a pod to get ready."
	_updating = false


func _rebuild_pods(my_id: int) -> void:
	for child in _pod_box.get_children():
		_pod_box.remove_child(child)
		child.queue_free()
	var ids: Array = GameState.teams.keys()
	ids.sort()
	for team_id in ids:
		var team: Dictionary = GameState.teams[team_id]
		var members: Array = team["member_order"]
		var names: Array = []
		for id in members:
			var shown: String = GameState.display_name(id)
			if id == my_id:
				shown += " (you)"
			if id != 1 and not GameState.player_ready.get(id, false):
				shown += " ..."
			names.append(shown)
		var row := HBoxContainer.new()
		var label := Label.new()
		var mine: bool = members.has(my_id)
		label.text = "%s%s (%d): %s" % ["> " if mine else "", team["name"], members.size(), ", ".join(names)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var join := Button.new()
		join.text = "Join"
		join.disabled = mine
		join.pressed.connect(func(): NetRouter.join_pod(team_id))
		row.add_child(join)
		_pod_box.add_child(row)
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "No pods yet. Tap New pod."
		_pod_box.add_child(empty)


func _on_level_selected(index: int) -> void:
	if _updating or not GameState.is_host():
		return
	NetRouter.host_set_level(_levels[index].id)


func _on_start_pressed() -> void:
	var text := _seed_field.text.strip_edges()
	var seed_value: int = int(text) if text.is_valid_int() else int(randi())
	var result := NetRouter.host_start_match(seed_value)
	if not result["ok"]:
		_status.text = result["reason"]


func _on_match_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_leave_pressed() -> void:
	NetLocal.stop()
	GameState.reset_match()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
