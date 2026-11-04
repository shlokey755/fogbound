class_name CompactTheme
extends RefCounted
## CompactTheme
## The game renders at 320x180 (design doc 3.1), so Godot's default 16 px UI
## font makes a menu with more than five or six rows overflow the screen.
## Assign `CompactTheme.make()` to a menu's root Control to shrink every
## control under it to a size that fits.

static func make(font_size: int = 10) -> Theme:
	var t := Theme.new()
	for type_name in ["Label", "Button", "OptionButton", "LineEdit", "CheckBox", "PopupMenu"]:
		t.set_font_size("font_size", type_name, font_size)
	return t
