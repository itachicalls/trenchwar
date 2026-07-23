class_name RotatePrompt
extends CanvasLayer
## Landscape gate for phones. COD / Fortnite / PUBG all fight in landscape —
## portrait leaves no look-pad for the right thumb. Menus may stay portrait;
## once PLAYING starts, this overlay blocks until the phone is sideways.

var _root: Control
var _label: Label

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.02, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := UiTheme.heading("ROTATE YOUR PHONE", 36, UiTheme.AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 280
	box.add_child(title)
	_label = Label.new()
	_label.text = "Landscape mode unlocks the look pad.\nTurn your device sideways to deploy."
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.82))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 280
	box.add_child(_label)
	# Prefer landscape on handheld builds (no-op on desktop / most browsers).
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var playing := Game.state == Game.State.PLAYING and not get_tree().paused
	var block := Game.is_touch() and playing and Game.is_portrait()
	Game.needs_landscape = block
	if visible != block:
		visible = block
		_root.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE
