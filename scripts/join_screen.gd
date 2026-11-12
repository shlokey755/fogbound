class_name JoinScreen
extends Control
## JoinScreen
## "Join game": lists the rooms found on this Wi-Fi/hotspot. Tap one to join.
## The list fills in by itself (NetLocal sends discovery probes every second or
## two); a manual address box at the bottom is the fallback for networks that
## block discovery.

var _status: Label
var _list: VBoxContainer
var _address: LineEdit
var _connecting := false


func _ready() -> void:
	theme = CompactTheme.make()
	_build_ui()
	NetLocal.rooms_changed.connect(_rebuild_list)
	NetLocal.join_succeeded.connect(_on_join_succeeded)
	NetLocal.join_failed.connect(_on_join_failed)
	_start_scanning()


func _exit_tree() -> void:
	NetLocal.stop_scan()
	for pair in [[NetLocal.rooms_changed, _rebuild_list], [NetLocal.join_succeeded, _on_join_succeeded],
			[NetLocal.join_failed, _on_join_failed]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 3)
	margin.add_child(page)

	var title := Label.new()
	title.text = "JOIN GAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	var manual := HBoxContainer.new()
	page.add_child(manual)
	_address = LineEdit.new()
	_address.placeholder_text = "or type the host's address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t): _on_manual_pressed())
	manual.add_child(_address)
	var go := Button.new()
	go.text = "Join"
	go.pressed.connect(_on_manual_pressed)
	manual.add_child(go)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)


func _start_scanning() -> void:
	_connecting = false
	NetLocal.start_scan()
	_rebuild_list()


func _rebuild_list() -> void:
	if _list == null or _connecting:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var rooms: Array = NetLocal.room_list()
	for info in rooms:
		var button := Button.new()
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var tag := ""
		if info["started"]:
			tag = "  [in progress]"
		elif info["players"] >= info["max"]:
			tag = "  [full]"
		button.text = "%s  %d/%d  %s%s" % [info["name"], info["players"], info["max"], info["level"], tag]
		button.disabled = info["started"] or info["players"] >= info["max"]
		button.pressed.connect(func(): join_room(info))
		_list.add_child(button)

	if rooms.is_empty():
		if NetDiscovery.lan_addresses(IP.get_local_addresses()).is_empty():
			_status.text = "No Wi-Fi network found. Connect to the host's hotspot (phone Wi-Fi settings), then come back."
		else:
			_status.text = "Looking for rooms on this Wi-Fi... (the host taps Host game)"
	else:
		_status.text = "Tap a room to join."

	if NetLocal.auto_join and not rooms.is_empty() and not rooms[0]["started"]:
		join_room(rooms[0])


## Also called by the tests and --auto-join.
func join_room(info: Dictionary) -> void:
	_join(String(info["ip"]), int(info["port"]), String(info["name"]))


func _on_manual_pressed() -> void:
	var text := _address.text.strip_edges()
	if text == "":
		_status.text = "Type the host's address first (the host's lobby shows it)."
		return
	_join(text, 0, text)


func _join(ip: String, port: int, label: String) -> void:
	if _connecting:
		return
	_connecting = true
	NetLocal.stop_scan()
	_status.text = "Connecting to %s..." % label
	NetLocal.join_game(ip, port)


func _on_join_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_join_failed(reason: String) -> void:
	NetLocal.auto_join = false
	_start_scanning()
	_status.text = reason


func _on_back_pressed() -> void:
	NetLocal.stop()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
