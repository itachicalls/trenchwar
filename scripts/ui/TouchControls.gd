class_name TouchControls
extends CanvasLayer
## COD-lite mobile HUD (landscape-first):
##   left-bottom  — move joystick (rim = sprint)
##   right-bottom — look joystick (camera)
##   mid-right    — FIRE / JUMP / AIM cluster above the look stick
##   left edge    — squad 1/2/3
## Fire-finger drag and free-look swipes still steer the camera.

## Radians for a full screen-height drag.
const LOOK_TURN := 3.2
## Full-deflection look-stick turn rate (rad/s).
const LOOK_STICK_SPEED := 3.1

var _stick_finger := -1
var _stick_home := Vector2.ZERO
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _stick_radius := 120.0
var _lookstick_finger := -1
var _lookstick_home := Vector2.ZERO
var _lookstick_origin := Vector2.ZERO
var _lookstick_vec := Vector2.ZERO
var _lookstick_radius := 110.0
var _look_finger := -1
var _aim_on := false

var _canvas: Control
var _buttons: Array[Dictionary] = []
var _last_vp := Vector2.ZERO
var _safe_origin := Vector2.ZERO
var _dirty := true
var _stick_redraw_cd := 0.0

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
	_lookstick_radius = 12.5 * u
	_stick_home = _safe_origin + Vector2(18.0 * u, vp.y - 20.0 * u)
	# LOOK sits left of the ammo sticker, same bottom row (ammo keeps the corner).
	_lookstick_home = _safe_origin + Vector2(vp.x - 40.0 * u, vp.y - 14.0 * u)
	# FIRE cluster sits above that bottom ammo/look row.
	_buttons = [
		{"id": "fire", "pos": Vector2(vp.x - 16.0 * u, vp.y - 48.0 * u), "radius": 8.5 * u,
			"action": "fire", "label": "FIRE", "toggle": false, "held": false},
		{"id": "jump", "pos": Vector2(vp.x - 16.0 * u, vp.y - 68.0 * u), "radius": 6.5 * u,
			"action": "jump", "label": "JUMP", "toggle": false, "held": false},
		{"id": "aim", "pos": Vector2(vp.x - 34.0 * u, vp.y - 60.0 * u), "radius": 5.8 * u,
			"action": "aim", "label": "AIM", "toggle": true, "held": false},
		{"id": "reload", "pos": Vector2(vp.x - 36.0 * u, vp.y - 42.0 * u), "radius": 5.0 * u,
			"action": "reload", "label": "R", "toggle": false, "held": false},
		{"id": "swap", "pos": Vector2(vp.x - 50.0 * u, vp.y - 52.0 * u), "radius": 5.0 * u,
			"action": "swap_weapon", "label": "SWAP", "toggle": false, "held": false},
		{"id": "interact", "pos": Vector2(vp.x - 16.0 * u, vp.y - 84.0 * u), "radius": 5.5 * u,
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
	_dirty = true

func _process(delta: float) -> void:
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
	if _lookstick_finger != -1 and _lookstick_vec.length() > 0.08:
		Game.touch_look += _lookstick_vec * LOOK_STICK_SPEED * delta
		_stick_redraw_cd -= delta
		if _stick_redraw_cd <= 0.0:
			_stick_redraw_cd = 0.05
			_dirty = true
	if _dirty:
		_dirty = false
		_canvas.queue_redraw()

func _release_everything() -> void:
	_stick_finger = -1
	_lookstick_finger = -1
	_look_finger = -1
	_stick_vec = Vector2.ZERO
	_lookstick_vec = Vector2.ZERO
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
	# Look stick wins over nearby action buttons so R/FIRE can't bury it.
	if _lookstick_finger == -1 and pos.distance_to(_lookstick_home) <= _lookstick_radius * 1.55:
		_lookstick_finger = finger
		_lookstick_origin = _lookstick_home
		_lookstick_vec = Vector2.ZERO
		_dirty = true
		return
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
			_dirty = true
			return
	var vp := _canvas.get_viewport_rect().size
	# Left 40% owns the move stick.
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
	if finger == _lookstick_finger:
		_lookstick_finger = -1
		_lookstick_vec = Vector2.ZERO
	if finger == _look_finger:
		_look_finger = -1
	_dirty = true

func _touch_drag(finger: int, pos: Vector2, relative: Vector2) -> void:
	if finger == _stick_finger:
		var v := (pos - _stick_origin) / _stick_radius
		_stick_vec = v.limit_length(1.0)
		_dirty = true
		return
	if finger == _lookstick_finger:
		var lv := (pos - _lookstick_origin) / _lookstick_radius
		_lookstick_vec = lv.limit_length(1.0)
		_dirty = true
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

func _draw_stick(home: Vector2, origin: Vector2, vec: Vector2, radius: float, held: bool, label: String) -> void:
	var base := origin if held else home
	var fill_a := 0.58 if held else 0.5
	_canvas.draw_circle(base, radius, Color(0.04, 0.08, 0.05, fill_a))
	_canvas.draw_arc(base, radius, 0, TAU, 20, Color(0.95, 1.0, 0.88, 0.85), 5.0, true)
	var knob := base + vec * radius * 0.75
	_canvas.draw_circle(knob, radius * 0.42, Color(0.78, 0.95, 0.55, 0.95 if held else 0.75))
	var font := ThemeDB.fallback_font
	var hs := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, int(radius * 0.28))
	_canvas.draw_string(font, base + Vector2(-hs.x / 2.0, hs.y * 0.3), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, int(radius * 0.28), Color(1, 1, 1, 0.9 if held else 0.8))

func _draw_controls() -> void:
	_draw_stick(_stick_home, _stick_origin, _stick_vec, _stick_radius, _stick_finger != -1, "MOVE")
	_draw_stick(_lookstick_home, _lookstick_origin, _lookstick_vec, _lookstick_radius,
		_lookstick_finger != -1, "LOOK")
	var font := ThemeDB.fallback_font
	for b in _buttons:
		_canvas.draw_circle(b.pos, b.radius, Color(0.05, 0.09, 0.04, 0.62 if b.held else 0.42))
		_canvas.draw_arc(b.pos, b.radius, 0, TAU, 16,
			Color(0.72, 0.95, 0.5, 0.95) if b.held else Color(0.9, 1.0, 0.85, 0.55), 4.0, true)
		var size := int(b.radius * 0.5)
		var text_size := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		_canvas.draw_string(font, b.pos + Vector2(-text_size.x / 2.0, text_size.y * 0.32),
			b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, size,
			Color(0.98, 1.0, 0.95, 1.0 if b.held else 0.85))
