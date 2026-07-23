class_name HUD
extends CanvasLayer
## Toy-box HUD: bright sticker panels, playful labels, hot crosshair on enemies.
## Designed to feel like plastic army-men packaging — not olive drab milsim.

var root: Control
var health_bar: ProgressBar
var health_label: Label
var fuel_bar: ProgressBar
var fuel_label: Label
var ammo_label: Label
var weapon_label: Label
var parts_label: Label
var coins_label: Label
var squad_label: Label
var powerup_box: HBoxContainer
var _powerups := {}
var objectives_box: VBoxContainer
var mission_label: Label
var crosshair: Control
var cross_ticks: Array[ColorRect] = []
var cross_dot: ColorRect
var cross_ring: ColorRect
var hit_marker: Label
var notify_label: Label
var notify_panel: PanelContainer
var damage_flash: ColorRect
var low_hp_vignette: TextureRect
var waypoint: Control
var waypoint_diamond: ColorRect
var waypoint_label: Label
var _notify_tween: Tween
var _spread := 10.0
var _cross_hot := false

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)
	_build()
	Events.player_health_changed.connect(_on_health)
	Events.fuel_changed.connect(_on_fuel)
	Events.ammo_changed.connect(_on_ammo)
	Events.weapon_changed.connect(func(n): weapon_label.text = n.to_upper())
	Events.parts_changed.connect(func(n): parts_label.text = "PARTS  %d" % n)
	Events.coins_changed.connect(_on_coins)
	Events.powerup_started.connect(_on_powerup)
	Events.squad_changed.connect(_on_squad)
	Events.squad_mode_changed.connect(func(m): squad_label.text = _squad_text(Game.squad.size(), m))
	Events.objectives_changed.connect(_on_objectives)
	Events.notify.connect(_on_notify)
	Events.hit_confirmed.connect(_on_hit_confirmed)
	Events.player_damaged.connect(_on_player_damaged)
	_on_objectives()
	var p := Game.player
	if p != null and is_instance_valid(p):
		_on_health(p.health.current, p.health.max_health)
		if "fuel" in p:
			_on_fuel(p.fuel, Player.FUEL_MAX)
		if p.weapon != null:
			_on_ammo(p.weapon.ammo, p.weapon.data.magazine_size)
			weapon_label.text = p.weapon.data.display_name.to_upper()

func _sticker(fill: Color, border: Color, margin: float = 16.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.hud_plate(fill, border))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p

func _label(parent: Node, size: int, color: Color = Color.WHITE, bold: bool = false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiTheme.title_font() if bold else UiTheme.body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.75))
	l.add_theme_constant_override("outline_size", 3 if bold else 2)
	parent.add_child(l)
	return l

func _build() -> void:
	var cine := TextureRect.new()
	cine.texture = UiTheme.radial_tex(Color(0, 0, 0, 0), Color(0, 0, 0, 0.22), 0.65)
	cine.set_anchors_preset(Control.PRESET_FULL_RECT)
	cine.stretch_mode = TextureRect.STRETCH_SCALE
	cine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cine)

	low_hp_vignette = TextureRect.new()
	low_hp_vignette.texture = UiTheme.radial_tex(Color(0.7, 0, 0, 0), Color(0.85, 0.1, 0.2, 0.8), 0.45)
	low_hp_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	low_hp_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	low_hp_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_hp_vignette.modulate.a = 0.0
	root.add_child(low_hp_vignette)

	damage_flash = ColorRect.new()
	damage_flash.color = Color(1.0, 0.2, 0.35, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_flash)

	# --- Mission card (top-left): sky-blue sticker ---
	var tl := _sticker(Color(0.18, 0.42, 0.72, 0.88), UiTheme.SKY)
	tl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	var tl_box := VBoxContainer.new()
	tl_box.add_theme_constant_override("separation", 5)
	tl.add_child(tl_box)
	mission_label = _label(tl_box, 18, UiTheme.GOLD, true)
	objectives_box = VBoxContainer.new()
	objectives_box.add_theme_constant_override("separation", 4)
	tl_box.add_child(objectives_box)

	# --- Loot chips (top-right) ---
	var tr := _sticker(Color(0.55, 0.22, 0.55, 0.86), UiTheme.PURPLE)
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var tr_box := VBoxContainer.new()
	tr_box.add_theme_constant_override("separation", 2)
	tr.add_child(tr_box)
	parts_label = _label(tr_box, 17, UiTheme.LIME, true)
	parts_label.text = "PARTS  0"
	parts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coins_label = _label(tr_box, 17, UiTheme.GOLD, true)
	coins_label.text = "COINS  %d" % Game.coins
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# --- Health / fuel (bottom-left): raised above the move stick ---
	var bl := _sticker(Color(0.12, 0.48, 0.28, 0.88), UiTheme.LIME)
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.offset_bottom = -118 if Game.is_touch() else -14
	var bl_box := VBoxContainer.new()
	bl_box.add_theme_constant_override("separation", 4)
	bl.add_child(bl_box)
	health_label = _label(bl_box, 15, Color(0.95, 1.0, 0.9), true)
	health_label.text = "HP"
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(230, 20)
	health_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.05, 0.12, 0.08, 0.85)
	hp_bg.set_corner_radius_all(8)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = UiTheme.LIME
	hp_fill.set_corner_radius_all(8)
	health_bar.add_theme_stylebox_override("background", hp_bg)
	health_bar.add_theme_stylebox_override("fill", hp_fill)
	bl_box.add_child(health_bar)
	fuel_label = _label(bl_box, 13, UiTheme.ORANGE, true)
	fuel_label.text = "FUEL"
	fuel_bar = ProgressBar.new()
	fuel_bar.custom_minimum_size = Vector2(230, 12)
	fuel_bar.show_percentage = false
	fuel_bar.max_value = 100.0
	fuel_bar.value = 100.0
	var fuel_bg := StyleBoxFlat.new()
	fuel_bg.bg_color = Color(0.15, 0.08, 0.02, 0.85)
	fuel_bg.set_corner_radius_all(6)
	var fuel_fill := StyleBoxFlat.new()
	fuel_fill.bg_color = UiTheme.ORANGE
	fuel_fill.set_corner_radius_all(6)
	fuel_bar.add_theme_stylebox_override("background", fuel_bg)
	fuel_bar.add_theme_stylebox_override("fill", fuel_fill)
	bl_box.add_child(fuel_bar)
	squad_label = _label(bl_box, 14, UiTheme.SKY, true)
	squad_label.text = _squad_text(0, "follow")

	# --- Ammo (bottom-right): candy coral sticker ---
	var br := _sticker(Color(0.72, 0.28, 0.22, 0.88), UiTheme.ORANGE)
	br.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.offset_bottom = -14
	var br_box := VBoxContainer.new()
	br_box.add_theme_constant_override("separation", 2)
	br.add_child(br_box)
	weapon_label = _label(br_box, 14, UiTheme.GOLD, true)
	weapon_label.text = "PLASTIC RIFLE"
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label = _label(br_box, 36, Color.WHITE, true)
	ammo_label.text = "100 / 100"
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	powerup_box = HBoxContainer.new()
	powerup_box.add_theme_constant_override("separation", 10)
	powerup_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	powerup_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	powerup_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	powerup_box.position.y = -96
	powerup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(powerup_box)

	waypoint = Control.new()
	waypoint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(waypoint)
	waypoint_diamond = ColorRect.new()
	waypoint_diamond.color = UiTheme.PINK
	waypoint_diamond.size = Vector2(16, 16)
	waypoint_diamond.position = Vector2(-8, -8)
	waypoint_diamond.rotation = PI / 4
	waypoint_diamond.pivot_offset = Vector2(8, 8)
	waypoint.add_child(waypoint_diamond)
	waypoint_label = _label(waypoint, 14, UiTheme.PINK, true)
	waypoint_label.position = Vector2(-24, 12)
	waypoint.visible = false

	_build_crosshair()

	notify_panel = PanelContainer.new()
	notify_panel.add_theme_stylebox_override("panel",
		UiTheme.hud_plate(Color(0.95, 0.55, 0.15, 0.92), UiTheme.GOLD, 14))
	notify_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notify_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notify_panel.position.y = 64
	notify_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notify_panel.modulate.a = 0.0
	root.add_child(notify_panel)
	var notify_box := VBoxContainer.new()
	notify_panel.add_child(notify_box)
	notify_label = _label(notify_box, 20, Color(0.12, 0.08, 0.05), true)
	notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_crosshair() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	# Soft ring behind the reticle — pops on bright bathroom tile.
	cross_ring = ColorRect.new()
	cross_ring.color = Color(1, 1, 1, 0.22)
	cross_ring.size = Vector2(22, 22)
	cross_ring.position = Vector2(-11, -11)
	crosshair.add_child(cross_ring)
	cross_dot = ColorRect.new()
	cross_dot.color = UiTheme.SKY
	cross_dot.size = Vector2(6, 6)
	cross_dot.position = Vector2(-3, -3)
	crosshair.add_child(cross_dot)
	for i in 4:
		var tick := ColorRect.new()
		tick.color = Color(UiTheme.SKY, 0.95)
		tick.size = Vector2(3, 10) if i < 2 else Vector2(10, 3)
		crosshair.add_child(tick)
		cross_ticks.append(tick)
	hit_marker = _label(crosshair, 28, UiTheme.PINK, true)
	hit_marker.text = "X"
	hit_marker.position = Vector2(-9, -20)
	hit_marker.modulate.a = 0.0

func _process(delta: float) -> void:
	_update_crosshair(delta)
	_update_waypoint()
	_update_powerups(delta)

const POWERUP_STYLE := {
	"rapid": ["RAPID FIRE", Color(1.0, 0.55, 0.15)],
	"speed": ["SUGAR RUSH", Color(0.35, 0.95, 1.0)],
	"shield": ["BUBBLE SHIELD", Color(0.55, 0.7, 1.0)],
}

func _on_coins(amount: int) -> void:
	coins_label.text = "COINS  %d" % amount
	coins_label.scale = Vector2(1.25, 1.25)
	var t := create_tween()
	t.tween_property(coins_label, "scale", Vector2.ONE, 0.2)

func _on_powerup(id: String, duration: float) -> void:
	if id in _powerups:
		_powerups[id].left = duration
		return
	var style: Array = POWERUP_STYLE.get(id, [id.to_upper(), UiTheme.CYAN])
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel",
		UiTheme.hud_plate(Color(style[1].r, style[1].g, style[1].b, 0.35), style[1], 12))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	powerup_box.add_child(pill)
	var l := _label(pill, 15, style[1], true)
	_powerups[id] = {"pill": pill, "label": l, "left": duration, "name": style[0]}

func _update_powerups(delta: float) -> void:
	for id in _powerups.keys():
		var entry: Dictionary = _powerups[id]
		entry.left -= delta
		if entry.left <= 0.0:
			entry.pill.queue_free()
			_powerups.erase(id)
			continue
		entry.label.text = "%s  %d" % [entry.name, ceili(entry.left)]
		entry.pill.modulate.a = 1.0 if entry.left > 3.0 else (0.4 + 0.6 * absf(sin(entry.left * 6.0)))

func _update_crosshair(delta: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or Game.needs_landscape:
		crosshair.visible = false
		return
	crosshair.visible = true
	var target_spread := 10.0
	if "velocity" in p:
		target_spread += clampf(Vector2(p.velocity.x, p.velocity.z).length() * 0.9, 0.0, 12.0)
	if Input.is_action_pressed("fire"):
		target_spread += 6.0
	if Input.is_action_pressed("aim"):
		target_spread *= 0.45
	_spread = lerpf(_spread, target_spread, 10.0 * delta)
	cross_ticks[0].position = Vector2(-1.5, -_spread - 10)
	cross_ticks[1].position = Vector2(-1.5, _spread)
	cross_ticks[2].position = Vector2(-_spread - 10, -1.5)
	cross_ticks[3].position = Vector2(_spread, -1.5)
	var hot: bool = "aim_at_enemy" in p and p.aim_at_enemy
	# Sky when idle, hot orange-pink when locked on a Chrome.
	var c := Color(1.0, 0.35, 0.2) if hot else UiTheme.SKY
	if hot != _cross_hot:
		_cross_hot = hot
		# Pop when we acquire a target.
		if hot:
			cross_ring.scale = Vector2(1.35, 1.35)
			var tw := create_tween()
			tw.tween_property(cross_ring, "scale", Vector2.ONE, 0.15)
	cross_dot.color = c
	cross_ring.color = Color(c.r, c.g, c.b, 0.35 if hot else 0.18)
	for tick in cross_ticks:
		tick.color = Color(c, 0.95)

func _update_waypoint() -> void:
	var pos := Missions.active_marker()
	var cam := get_viewport().get_camera_3d()
	if pos == Vector3.INF or cam == null or Game.player == null:
		waypoint.visible = false
		return
	if cam.is_position_behind(pos):
		waypoint.visible = false
		return
	var screen := cam.unproject_position(pos + Vector3.UP * 1.5)
	var vp := root.size
	screen = screen.clamp(Vector2(40, 60), vp - Vector2(40, 60))
	waypoint.position = screen
	var dist: float = Game.player.global_position.distance_to(pos)
	waypoint_label.text = "%dm" % int(dist)
	waypoint.visible = dist > 6.0
	waypoint_diamond.scale = Vector2.ONE * (1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.006))

func _squad_text(count: int, mode: String) -> String:
	return "SQUAD  %d  ·  %s" % [count, mode.to_upper()]

func _on_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "HP  %d / %d" % [int(current), int(maximum)]
	var ratio := current / maximum if maximum > 0 else 1.0
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill").duplicate()
	fill.bg_color = UiTheme.LIME if ratio > 0.4 else (UiTheme.ORANGE if ratio > 0.2 else UiTheme.RED)
	health_bar.add_theme_stylebox_override("fill", fill)
	var missing := 1.0 - ratio
	low_hp_vignette.modulate.a = clampf(missing - 0.25, 0.0, 0.75)

func _on_fuel(fuel: float, max_fuel: float) -> void:
	fuel_bar.max_value = max_fuel
	fuel_bar.value = fuel
	fuel_label.text = "FUEL  %d%%" % int(round(fuel / max_fuel * 100.0))
	fuel_label.add_theme_color_override("font_color",
		UiTheme.RED if fuel <= 15.0 else UiTheme.ORANGE)

func _on_ammo(ammo: int, magazine: int) -> void:
	ammo_label.text = "%d / %d" % [ammo, magazine]
	ammo_label.add_theme_color_override("font_color",
		UiTheme.GOLD if ammo == 0 else Color.WHITE)

func _on_squad(members: Array) -> void:
	squad_label.text = _squad_text(members.size(), "follow")

func _on_objectives() -> void:
	mission_label.text = Missions.mission_title
	for child in objectives_box.get_children():
		child.queue_free()
	for o in Missions.objectives:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		objectives_box.add_child(row)
		var check := Panel.new()
		check.custom_minimum_size = Vector2(16, 16)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.LIME if o.done else Color(1, 1, 1, 0.12)
		sb.border_color = Color.WHITE if o.done else UiTheme.GOLD
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(5)
		check.add_theme_stylebox_override("panel", sb)
		row.add_child(check)
		var l := Label.new()
		l.add_theme_font_override("font", UiTheme.body_font())
		l.add_theme_font_size_override("font_size", 15)
		l.text = o.label()
		l.add_theme_color_override("font_color",
			Color(0.75, 0.95, 0.8, 0.75) if o.done else Color(0.95, 0.98, 1.0))
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.2, 0.7))
		l.add_theme_constant_override("outline_size", 2)
		row.add_child(l)

func _on_notify(text: String) -> void:
	notify_label.text = text
	if _notify_tween != null:
		_notify_tween.kill()
	notify_panel.reset_size()
	notify_panel.position.y = 48
	notify_panel.modulate.a = 0.0
	_notify_tween = create_tween()
	_notify_tween.set_parallel(true)
	_notify_tween.tween_property(notify_panel, "modulate:a", 1.0, 0.18)
	_notify_tween.tween_property(notify_panel, "position:y", 64.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_notify_tween.set_parallel(false)
	_notify_tween.tween_interval(3.2)
	_notify_tween.tween_property(notify_panel, "modulate:a", 0.0, 0.7)

func _on_hit_confirmed(killed: bool) -> void:
	hit_marker.modulate = Color(1, 0.25, 0.45, 1.0) if killed else Color(1, 0.9, 0.3, 0.95)
	hit_marker.scale = Vector2(1.5, 1.5) if killed else Vector2.ONE
	var t := create_tween().set_parallel(true)
	t.tween_property(hit_marker, "modulate:a", 0.0, 0.3)
	t.tween_property(hit_marker, "scale", Vector2.ONE, 0.3)

func _on_player_damaged() -> void:
	damage_flash.color.a = 0.28
	var t := create_tween()
	t.tween_property(damage_flash, "color:a", 0.0, 0.5)
