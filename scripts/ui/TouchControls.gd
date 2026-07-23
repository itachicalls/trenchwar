class_name TouchControls
extends CanvasLayer
## COD-lite mobile HUD (landscape-first):
##   left-bottom  — move joystick (rim = sprint)
##   right HALF   — free look pad (bottom-right stays mostly empty)
##   mid-right    — FIRE (raised so the look thumb has room)
##   upper-right  — JUMP + AIM (claw-friendly, out of the look pad)
##   left edge    — squad 1/2/3
## Fire-finger drag still steers the camera (fixed-fire + look rotation).

## Radians for a full screen-height drag.
const LOOK_TURN := 3.2

var _stick_finger := -1
var _stick_home := Vector2.ZERO
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _stick_radius := 120.0
var _look_finger := -1
var _aim_on := false

var _canvas: Control
var _buttons: Array[Dictionary] = []
var _last_vp := Vector2.ZERO
var _safe_origin := Vector2.ZERO

func _ready() -> void:
	layer = 55
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	_layout()
	Events.player_damaged.connect(func(): Input.vibrate_handheld(60))
	Events.hit_confirmed.connect(func(killed: bool):
		if killed:
			Input.vibrate_handheld(30))

func _layout() -> void:
	var vp := _canvas.get_viewport_rect().size
	_last_vp = vp
	var u := minf(vp.x, vp.y) / 100.0
	var win := Vector2(DisplayServer.window_get_size())
	if win.x > 0.0 and win.y > 0.0:
		var safe := DisplayServer.get_display_safe_area()
		var to_canvas := vp / win
		var left := maxf(safe.position.x, 0.0) * to_canvas.x
		var top := maxf(safe.position.y, 0.0) * to_canvas.y
		var right := maxf(win.x - safe.end.x, 0.0) * to_canvas.x
		var bottom := maxf(win.y - safe.end.y, 0.0) * to_canvas.y
		vp = Vector2(vp.x - left - right, vp.y - top - bottom)
		_safe_origin = Vector2(left, top)
	else:
		_safe_origin = Vector2.ZERO
	_stick_radius = 14.0 * u
	_stick_home = _safe_origin + Vector2(18.0 * u, vp.y - 20.0 * u)
	# COD 2-thumb: FIRE sits mid-right (not bottom-right). Bottom-right is
	# reserved as the look pad so the right thumb can swipe freely.
	_buttons = [
		{"id": "fire", "pos": Vector2(vp.x - 14.0 * u, vp.y - 38.0 * u), "radius": 8.5 * u,
			"action": "fire", "label": "FIRE", "toggle": false, "held": false},
		{"id": "jump", "pos": Vector2(vp.x - 14.0 * u, vp.y - 58.0 * u), "radius": 6.5 * u,
			"action": "jump", "label": "JUMP", "toggle": false, "held": false},
		{"id": "aim", "pos": Vector2(vp.x - 30.0 * u, vp.y - 52.0 * u), "radius": 5.8 * u,
			"action": "aim", "label": "AIM", "toggle": true, "held": false},
		{"id": "reload", "pos": Vector2(vp.x - 32.0 * u, vp.y - 34.0 * u), "radius": 5.0 * u,
			"action": "reload", "label": "R", "toggle": false, "held": false},
		{"id": "swap", "pos": Vector2(vp.x - 46.0 * u, vp.y - 44.0 * u), "radius": 5.0 * u,
			"action": "swap_weapon", "label": "SWAP", "toggle": false, "held": false},
		{"id": "interact", "pos": Vector2(vp.x - 14.0 * u, vp.y - 74.0 * u), "radius": 5.5 * u,
			"action": "interact", "label": "E", "toggle": false, "held": false},
		{"id": "cmd1", "pos": Vector2(8.0 * u, vp.y - 42.0 * u), "radius": 4.2 * u,
			"action": "cmd_follow", "label": "1", "toggle": false, "held": false},
		{"id": "cmd2", "pos": Vector2(8.0 * u, vp.y - 53.0 * u), "radius": 4.2 * u,
			"action": "cmd_hold", "label": "2", "toggle": false, "held": false},
		{"id": "cmd3", "pos": Vector2(8.0 * u, vp.y - 64.0 * u), "radius": 4.2 * u,
			"action": "cmd_charge", "label": "3", "toggle": false, "held": false},
		{"id": "pause", "pos": Vector2(vp.x - 8.0 * u, 8.0 * u), "radius": 4.8 * u,
			"action": "pause", "label": "II", "toggle": false, "held": false},
	]
	for b in _buttons:
		b.pos += _safe_origin
	_canvas.queue_redraw()

func _process(_delta: float) -> void:
	if _canvas.get_viewport_rect().size != _last_vp:
		_layout()
	var playing := Game.state == Game.State.PLAYING and not get_tree().paused \
			and not Game.needs_landscape
	if visible != playing:
		visible = playing
		if not playing:
			_release_everything()
	if not playing:
		return
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
	for b in _buttons:
		if pos.distance_to(b.pos) <= b.radius * 1.15:
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
				var ev := InputEventAction.new()
				ev.action = "pause"
				ev.pressed = true
				Input.parse_input_event(ev)
			else:
				Input.action_press(b.action)
			_canvas.queue_redraw()
			return
	var vp := _canvas.get_viewport_rect().size
	# Left 40% owns the stick; everything else is look (incl. the empty
	# bottom-right pad COD leaves free for camera flicks).
	if pos.x < vp.x * 0.40 and _stick_finger == -1:
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
		var v := (pos - _stick_origin) / _stick_radius
		_stick_vec = v.limit_length(1.0)
		return
	var is_fire_finger := false
	for b in _buttons:
		if b.get("finger", -1) == finger:
			if b.id != "fire":
				return
			is_fire_finger = true
			break
	if finger == _look_finger or is_fire_finger:
		var vp := _canvas.get_viewport_rect().size
		if relative.length() > vp.y * 0.25:
			return
		Game.touch_look += relative * (LOOK_TURN / maxf(vp.y, 1.0))

func _draw_controls() -> void:
	var base := _stick_origin if _stick_finger != -1 else _stick_home
	_canvas.draw_circle(base, _stick_radius, Color(0.05, 0.09, 0.04, 0.42))
	_canvas.draw_arc(base, _stick_radius, 0, TAU, 48, Color(0.9, 1.0, 0.85, 0.55), 4.0, true)
	var knob := base + _stick_vec * _stick_radius * 0.75
	_canvas.draw_circle(knob, _stick_radius * 0.42, Color(0.72, 0.9, 0.5, 0.85 if _stick_finger != -1 else 0.55))
	var font := ThemeDB.fallback_font
	if _stick_finger == -1:
		var hint := "MOVE"
		var hs := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, int(_stick_radius * 0.28))
		_canvas.draw_string(font, base + Vector2(-hs.x / 2.0, hs.y * 0.3), hint,
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(_stick_radius * 0.28), Color(1, 1, 1, 0.7))
	# Soft look-pad hint in the empty bottom-right (COD's free swipe zone).
	var full := _canvas.get_viewport_rect().size
	var look_hint := Vector2(full.x - _stick_radius * 1.1, full.y - _stick_radius * 0.85)
	var lh := "LOOK"
	var ls := int(_stick_radius * 0.28)
	var lsz := font.get_string_size(lh, HORIZONTAL_ALIGNMENT_CENTER, -1, ls)
	_canvas.draw_string(font, look_hint + Vector2(-lsz.x / 2.0, 0), lh,
		HORIZONTAL_ALIGNMENT_CENTER, -1, ls, Color(1, 1, 1, 0.28))
	for b in _buttons:
		_canvas.draw_circle(b.pos, b.radius, Color(0.05, 0.09, 0.04, 0.62 if b.held else 0.42))
		_canvas.draw_arc(b.pos, b.radius, 0, TAU, 40,
			Color(0.72, 0.95, 0.5, 0.95) if b.held else Color(0.9, 1.0, 0.85, 0.55), 4.0, true)
		var size := int(b.radius * 0.5)
		var text_size := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		_canvas.draw_string(font, b.pos + Vector2(-text_size.x / 2.0, text_size.y * 0.32),
			b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, size,
			Color(0.98, 1.0, 0.95, 1.0 if b.held else 0.85))
