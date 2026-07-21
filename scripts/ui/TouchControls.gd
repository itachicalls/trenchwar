class_name TouchControls
extends CanvasLayer
## On-screen controls for phones and tablets. Created by Main only when a
## touchscreen is present; hides itself outside of gameplay.
##
## Layout (thumb-reach ergonomics):
##   left-bottom  — floating move joystick (appears where the thumb lands;
##                  push to the rim to sprint)
##   right side   — drag anywhere to look
##   right-bottom — FIRE (large), JUMP, AIM toggle, RELOAD, SWAP
##   center-right — INTERACT [E]
##   bottom-center— squad orders 1/2/3
## All buttons drive the same input actions the keyboard uses, so vehicles,
## rescues and menus need zero special-casing.

const LOOK_SENS := 0.0042
const STICK_RADIUS := 110.0

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_finger := -1
var _aim_on := false

var _canvas: Control            # full-screen draw surface (joystick visuals)
var _buttons: Array[Dictionary] = []   # {pos, radius, action, label, toggle, held}

func _ready() -> void:
	layer = 55
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var vp := _canvas.get_viewport_rect().size
	_buttons = [
		{"id": "fire", "pos": Vector2(vp.x - 130, vp.y - 150), "radius": 64.0,
			"action": "fire", "label": "FIRE", "toggle": false, "held": false},
		{"id": "jump", "pos": Vector2(vp.x - 280, vp.y - 100), "radius": 46.0,
			"action": "jump", "label": "JUMP", "toggle": false, "held": false},
		{"id": "aim", "pos": Vector2(vp.x - 120, vp.y - 290), "radius": 40.0,
			"action": "aim", "label": "AIM", "toggle": true, "held": false},
		{"id": "reload", "pos": Vector2(vp.x - 250, vp.y - 230), "radius": 36.0,
			"action": "reload", "label": "R", "toggle": false, "held": false},
		{"id": "swap", "pos": Vector2(vp.x - 350, vp.y - 170), "radius": 36.0,
			"action": "swap_weapon", "label": "SWAP", "toggle": false, "held": false},
		{"id": "interact", "pos": Vector2(vp.x - 90, vp.y * 0.52), "radius": 42.0,
			"action": "interact", "label": "E", "toggle": false, "held": false},
		{"id": "cmd1", "pos": Vector2(vp.x * 0.42, vp.y - 60), "radius": 30.0,
			"action": "cmd_follow", "label": "1", "toggle": false, "held": false},
		{"id": "cmd2", "pos": Vector2(vp.x * 0.5, vp.y - 60), "radius": 30.0,
			"action": "cmd_hold", "label": "2", "toggle": false, "held": false},
		{"id": "cmd3", "pos": Vector2(vp.x * 0.58, vp.y - 60), "radius": 30.0,
			"action": "cmd_charge", "label": "3", "toggle": false, "held": false},
		{"id": "pause", "pos": Vector2(vp.x * 0.5, 44), "radius": 30.0,
			"action": "pause", "label": "II", "toggle": false, "held": false},
	]
	_canvas.queue_redraw()

func _process(_delta: float) -> void:
	var playing := Game.state == Game.State.PLAYING and not get_tree().paused
	if visible != playing:
		visible = playing
		if not playing:
			_release_everything()
	if not playing:
		return
	# Feed the joystick into the four move actions (get_vector reads strength).
	if _stick_finger != -1:
		Input.action_press("move_right", maxf(_stick_vec.x, 0.0))
		Input.action_press("move_left", maxf(-_stick_vec.x, 0.0))
		Input.action_press("move_back", maxf(_stick_vec.y, 0.0))
		Input.action_press("move_forward", maxf(-_stick_vec.y, 0.0))
		if _stick_vec.length() > 0.92:
			Input.action_press("sprint")
		else:
			Input.action_release("sprint")
	_canvas.queue_redraw()

func _release_everything() -> void:
	_stick_finger = -1
	_look_finger = -1
	_stick_vec = Vector2.ZERO
	for a in ["move_right", "move_left", "move_back", "move_forward", "sprint", "fire", "jump", "aim"]:
		Input.action_release(a)
	_aim_on = false
	for b in _buttons:
		b.held = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position, event.relative)

func _touch_down(finger: int, pos: Vector2) -> void:
	# Buttons win over everything.
	for b in _buttons:
		if pos.distance_to(b.pos) <= b.radius * 1.25:
			b.held = true
			b["finger"] = finger
			if b.toggle:
				_aim_on = not _aim_on
				if _aim_on:
					Input.action_press(b.action)
				else:
					Input.action_release(b.action)
				b.held = _aim_on
			elif b.id == "pause":
				# Pause is handled in _unhandled_input, which raw action state
				# never reaches — dispatch a real event through the tree.
				var ev := InputEventAction.new()
				ev.action = "pause"
				ev.pressed = true
				Input.parse_input_event(ev)
			else:
				Input.action_press(b.action)
			_canvas.queue_redraw()
			return
	var vp := _canvas.get_viewport_rect().size
	if pos.x < vp.x * 0.42 and _stick_finger == -1:
		# Floating joystick: base spawns under the thumb.
		_stick_finger = finger
		_stick_origin = pos
		_stick_vec = Vector2.ZERO
	elif _look_finger == -1:
		_look_finger = finger

func _touch_up(finger: int) -> void:
	for b in _buttons:
		if b.get("finger", -1) == finger:
			b["finger"] = -1
			if not b.toggle:
				b.held = false
				Input.action_release(b.action)
	if finger == _stick_finger:
		_stick_finger = -1
		_stick_vec = Vector2.ZERO
		for a in ["move_right", "move_left", "move_back", "move_forward", "sprint"]:
			Input.action_release(a)
	if finger == _look_finger:
		_look_finger = -1
	_canvas.queue_redraw()

func _touch_drag(finger: int, pos: Vector2, relative: Vector2) -> void:
	if finger == _stick_finger:
		var v := (pos - _stick_origin) / STICK_RADIUS
		_stick_vec = v.limit_length(1.0)
	elif finger == _look_finger:
		Game.touch_look += relative * LOOK_SENS

## Joystick + button rings drawn directly — crisp at any resolution, no
## texture assets to ship or scale.
func _draw_controls() -> void:
	if _stick_finger != -1:
		_canvas.draw_circle(_stick_origin, STICK_RADIUS, Color(1, 1, 1, 0.08))
		_canvas.draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
		var knob := _stick_origin + _stick_vec * STICK_RADIUS * 0.8
		_canvas.draw_circle(knob, 40.0, Color(0.75, 0.9, 0.55, 0.55))
	for b in _buttons:
		var col := Color(0.75, 0.9, 0.55, 0.5 if b.held else 0.22)
		_canvas.draw_circle(b.pos, b.radius, Color(0.08, 0.12, 0.06, 0.5))
		_canvas.draw_arc(b.pos, b.radius, 0, TAU, 40, col, 3.0, true)
		var font := ThemeDB.fallback_font
		var size := int(b.radius * 0.55)
		var text_size := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		_canvas.draw_string(font, b.pos + Vector2(-text_size.x / 2.0, text_size.y * 0.32),
			b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, size,
			Color(0.95, 1.0, 0.9, 0.9 if b.held else 0.6))
