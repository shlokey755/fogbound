class_name OfflineSetup
extends Control
## OfflineSetup
## "Play offline" screen: you plus bot teammates in your own pod, and
## optionally rival bot pods racing you to the same exit. No networking is
## involved -- with no peer Godot's default OfflineMultiplayerPeer makes this
## process its own host (peer id 1), so the whole normal match runs unchanged
## and bots simply take peer ids 2 and up (see GameState.bots).
##
## The UI is built in code (a plain Control root) so the screen stays one
## script instead of a scene full of hand-edited node paths.

const MAX_RIVAL_PODS := 3
const MIN_RIVAL_SIZE := 2
const MAX_RIVAL_SIZE := 5

var _levels: Array = []
var _level_picker: OptionButton
var _teammates: SpinBox
var _rivals: SpinBox
var _rival_size: SpinBox
var _skill: OptionButton
var _seed_field: LineEdit
var _summary: Label
var _description: Label
var _updating := false


func _ready() -> void:
	theme = CompactTheme.make()
	_build_ui()
	_update_limits()
	_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	# Controls scroll if a tiny screen needs it; the buttons below stay pinned
	# so START is never hidden.
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 3)
	margin.add_child(page)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "PLAY OFFLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_level_picker = OptionButton.new()
	_level_picker.clip_text = true
	_levels = LevelData.selectable_levels()
	for lvl in _levels:
		_level_picker.add_item("%s (%s)" % [lvl.name, lvl.difficulty])
	_select_level(LevelData.default_level_id())
	_level_picker.item_selected.connect(func(_i): _refresh())
	box.add_child(_pair("Level", _level_picker))

	# One row of three counters, then skill + seed: the whole form is three rows.
	var counts := HBoxContainer.new()
	box.add_child(counts)
	_teammates = _spin(1, 7, 2)
	counts.add_child(_pair("Bot mates", _teammates))
	_rivals = _spin(0, MAX_RIVAL_PODS, 1)
	counts.add_child(_pair("Rivals", _rivals))
	_rival_size = _spin(MIN_RIVAL_SIZE, MAX_RIVAL_SIZE, 3)
	counts.add_child(_pair("Rival size", _rival_size))

	var misc := HBoxContainer.new()
	box.add_child(misc)
	_skill = OptionButton.new()
	for i in range(BotBrain.skill_count()):
		_skill.add_item(BotBrain.skill_name(i))
	_skill.select(BotBrain.Skill.NORMAL)
	misc.add_child(_pair("Skill", _skill))
	_seed_field = LineEdit.new()
	_seed_field.placeholder_text = "random"
	misc.add_child(_pair("Seed", _seed_field))

	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)

	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_description)

	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	buttons.add_child(back)
	var start := Button.new()
	start.text = "START"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_on_start_pressed)
	buttons.add_child(start)


## "Label  [control]" side by side, sharing the row with its neighbours.
func _pair(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = text
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.value_changed.connect(func(_v): _on_count_changed())
	return s


func _select_level(level_id: int) -> void:
	for i in range(_levels.size()):
		if _levels[i].id == level_id:
			_level_picker.select(i)
			return


func _on_count_changed() -> void:
	if _updating:
		return
	_update_limits()
	_refresh()


## At most 16 players in a match (GameState.MAX_PLAYERS): you, your teammates
## and every rival pod must fit. Shrink each control's maximum to whatever
## room the others leave.
func _update_limits() -> void:
	_updating = true
	var room := GameState.MAX_PLAYERS - 1  # everyone but you
	var rivals := int(_rivals.value)
	var size := int(_rival_size.value)
	_teammates.max_value = maxi(1, room - rivals * size)
	_rival_size.max_value = maxi(MIN_RIVAL_SIZE, mini(MAX_RIVAL_SIZE, (room - int(_teammates.value)) / maxi(rivals, 1)))
	_rivals.max_value = clampi((room - int(_teammates.value)) / size, 0, MAX_RIVAL_PODS)
	_updating = false


func _refresh() -> void:
	var mates := int(_teammates.value)
	var rivals := int(_rivals.value)
	var size := int(_rival_size.value)
	var text := "Your pod: you + %d bot%s." % [mates, "" if mates == 1 else "s"]
	if rivals > 0:
		text += " %d rival pod%s of %d race you to the exit." % [rivals, "" if rivals == 1 else "s", size]
	else:
		text += " No rivals: just you and your team."
	text += " %d players." % total_players(mates, rivals, size)
	_summary.text = text
	var lvl: LevelData.LevelDef = _levels[_level_picker.selected]
	_description.text = "%dx%d maze, %d fragments. %s" % [lvl.width, lvl.height, lvl.fragment_count, lvl.description]


static func total_players(mates: int, rivals: int, rival_size: int) -> int:
	return 1 + mates + rivals * rival_size


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_start_pressed() -> void:
	var seed_value: int = int(_seed_field.text) if _seed_field.text.strip_edges().is_valid_int() else int(randi())
	configure_match(
		_levels[_level_picker.selected].id,
		int(_teammates.value), int(_rivals.value), int(_rival_size.value),
		_skill.selected, seed_value)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


## Fills GameState for an offline match. Static so tests (and a future
## "quick play" button) can start a match without touching any UI.
## You are always peer 1 in team 0, chained first; bots follow.
## `autoplay` hands your slot to a bot too (nobody drives it, so it also gets
## no camera): the whole match plays itself, which is how the tests run a
## complete match, and would serve an attract-mode demo.
static func configure_match(level_id: int, mates: int, rivals: int, rival_size: int, skill: int, seed_value: int,
		autoplay: bool = false) -> void:
	GameState.reset_match()
	GameState.offline_mode = true
	GameState.human_id = 1
	if autoplay:
		GameState.bots[1] = {"skill": skill}

	var next_id := 2
	var yours: Array = [1]
	for i in range(mates):
		GameState.bots[next_id] = {"skill": skill}
		yours.append(next_id)
		next_id += 1
	var teams := {0: {"name": "Your pod", "original_size": 0, "member_order": yours}}

	for r in range(rivals):
		var members: Array = []
		for j in range(rival_size):
			GameState.bots[next_id] = {"skill": skill}
			members.append(next_id)
			next_id += 1
		teams[r + 1] = {"name": "Rivals %s" % char(65 + r), "original_size": 0, "member_order": members}

	for team_id in teams:
		for id in teams[team_id]["member_order"]:
			GameState.player_team[id] = team_id
	GameState.teams = teams

	# Same entry point a hosted match uses: sets seed, level, original sizes.
	NetRouter.net_start_match(seed_value, level_id, JSON.stringify(teams))
