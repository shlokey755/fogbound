extends PanelContainer
## PodCard
## One pod's row in the lobby pod matrix (design doc section 6.1-6.2):
## shows members, flags pods below the minimum size, and offers a
## join button.

@onready var title_label: Label = $VBox/Title
@onready var members_label: Label = $VBox/Members
@onready var warning_label: Label = $VBox/Warning
@onready var join_button: Button = $VBox/JoinButton

var _team_id: int
var _lobby: Control


func setup(team_id: int, team: Dictionary, lobby: Control) -> void:
	_team_id = team_id
	_lobby = lobby
	title_label.text = team.get("name", "Pod")
	var members: Array = team.get("member_order", [])
	members_label.text = ", ".join(members.map(func(x): return "Player %s" % str(x)))
	if members.size() < GameState.MIN_TEAM_SIZE:
		warning_label.text = "Min %d!" % GameState.MIN_TEAM_SIZE
		warning_label.visible = true
	else:
		warning_label.visible = false
	join_button.pressed.connect(func(): _lobby._join_pod(_team_id))
