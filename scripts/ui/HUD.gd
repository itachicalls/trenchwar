class_name HUD
extends CanvasLayer
## Toy-military heads-up display. Stenciled olive plates, Black Ops One headers,
## dynamic crosshair, objective waypoint marker, damage/low-HP vignettes.

var root: Control
var health_bar: ProgressBar
var health_label: Label
var ammo_label: Label
var weapon_label: Label
var parts_label: Label
var coins_label: Label
var squad_label: Label
var powerup_box: HBoxContainer
## id -> {pill: PanelContainer, label: Label, left: float}
var _powerups := {}
var objectives_box: VBoxContainer
var mission_label: Label
var crosshair: Control
var cross_ticks: Array[ColorRect] = []
var cross_dot: ColorRect
var hit_marker: Label
var notify_label: Label
var notify_panel: PanelContainer
var damage_flash: ColorRect
var low_hp_vignette: TextureRect
var waypoint: Control
var waypoint_diamond: ColorRect
var waypoint_label: Label
var _notify_tween: Tween
var _spread := 8.0

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)
	_build()
	Events.player_health_changed.connect(_on_health)
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
		if p.weapon != null:
			_on_ammo(p.weapon.ammo, p.weapon.data.magazine_size)
			weapon_label.text = p.weapon.data.display_name.to_upper()

func _panel(anchor_preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(anchor_preset, Control.PRESET_MODE_MINSIZE, 18)
	if anchor_preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]:
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if anchor_preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]:
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p

func _label(parent: Node, size: int, color: Color = UiTheme.CREAM, stencil: bool = false) -> Label:
	var l := Label.new()
	if stencil:
		l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _build() -> void:
	# Always-on cinematic vignette (subtle dark edges).
	var cine := TextureRect.new()
	cine.texture = UiTheme.radial_tex(Color(0, 0, 0, 0), Color(0, 0, 0, 0.32), 0.62)
	cine.set_anchors_preset(Control.PRESET_FULL_RECT)
	cine.stretch_mode = TextureRect.STRETCH_SCALE
	cine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cine)

	# Low-HP red vignette (alpha driven by missing health).
	low_hp_vignette = TextureRect.new()
	low_hp_vignette.texture = UiTheme.radial_tex(Color(0.7, 0, 0, 0), Color(0.65, 0.02, 0.02, 0.85), 0.45)
	low_hp_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	low_hp_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	low_hp_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_hp_vignette.modulate.a = 0.0
	root.add_child(low_hp_vignette)

	# Damage flash.
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.8, 0.1, 0.1, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_flash)

	# Bottom-left: health + squad.
	var bl := _panel(Control.PRESET_BOTTOM_LEFT)
	var bl_box := VBoxContainer.new()
	bl.add_child(bl_box)
	health_label = _label(bl_box, 14, UiTheme.CREAM, true)
	health_label.text = "INTEGRITY"
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(250, 18)
	health_bar.show_percentage = false
	bl_box.add_child(health_bar)
	squad_label = _label(bl_box, 14, Color(0.75, 0.85, 0.6))
	squad_label.text = _squad_text(0, "follow")

	# Bottom-right: weapon + ammo.
	var br := _panel(Control.PRESET_BOTTOM_RIGHT)
	var br_box := VBoxContainer.new()
	br.add_child(br_box)
	weapon_label = _label(br_box, 14, UiTheme.AMBER, true)
	weapon_label.text = "PLASTIC RIFLE"
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label = _label(br_box, 34, UiTheme.CREAM, true)
	ammo_label.text = "24 / 24"
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Top-left: mission + objectives, with a military accent stripe.
	var tl := _panel(Control.PRESET_TOP_LEFT)
	var tl_h := HBoxContainer.new()
	tl_h.add_theme_constant_override("separation", 10)
	tl.add_child(tl_h)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.AMBER
	stripe.custom_minimum_size = Vector2(3, 0)
	tl_h.add_child(stripe)
	var tl_box := VBoxContainer.new()
	tl_box.add_theme_constant_override("separation", 4)
	tl_h.add_child(tl_box)
	mission_label = _label(tl_box, 17, UiTheme.AMBER, true)
	var divider := ColorRect.new()
	divider.color = Color(UiTheme.AMBER, 0.35)
	divider.custom_minimum_size = Vector2(0, 1)
	tl_box.add_child(divider)
	objectives_box = VBoxContainer.new()
	objectives_box.add_theme_constant_override("separation", 3)
	tl_box.add_child(objectives_box)

	# Top-right: resources.
	var tr := _panel(Control.PRESET_TOP_RIGHT)
	var tr_box := VBoxContainer.new()
	tr_box.add_theme_constant_override("separation", 2)
	tr.add_child(tr_box)
	parts_label = _label(tr_box, 16, UiTheme.GREEN, true)
	parts_label.text = "PARTS  0"
	parts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coins_label = _label(tr_box, 16, Color(1.0, 0.8, 0.25), true)
	coins_label.text = "COINS  %d" % Game.coins
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Bottom-center: active powerup pills with countdowns.
	powerup_box = HBoxContainer.new()
	powerup_box.add_theme_constant_override("separation", 10)
	powerup_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	powerup_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	powerup_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	powerup_box.position.y = -96
	powerup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(powerup_box)

	# Objective waypoint marker (repositioned every frame).
	waypoint = Control.new()
	waypoint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(waypoint)
	waypoint_diamond = ColorRect.new()
	waypoint_diamond.color = UiTheme.AMBER
	waypoint_diamond.size = Vector2(14, 14)
	waypoint_diamond.position = Vector2(-7, -7)
	waypoint_diamond.rotation = PI / 4
	waypoint_diamond.pivot_offset = Vector2(7, 7)
	waypoint.add_child(waypoint_diamond)
	waypoint_label = _label(waypoint, 13, UiTheme.AMBER, true)
	waypoint_label.position = Vector2(-22, 10)
	waypoint.visible = false

	# Crosshair: center dot + four ticks that breathe with movement/fire.
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	cross_dot = ColorRect.new()
	cross_dot.color = UiTheme.CREAM
	cross_dot.size = Vector2(4, 4)
	cross_dot.position = Vector2(-2, -2)
	crosshair.add_child(cross_dot)
	for i in 4:
		var tick := ColorRect.new()
		tick.color = Color(UiTheme.CREAM, 0.85)
		tick.size = Vector2(2, 8) if i < 2 else Vector2(8, 2)
		crosshair.add_child(tick)
		cross_ticks.append(tick)
	hit_marker = _label(crosshair, 26, UiTheme.RED, true)
	hit_marker.text = "X"
	hit_marker.position = Vector2(-9, -19)
	hit_marker.modulate.a = 0.0

	# Top-center notifications: a stenciled radio-message plate that slides in.
	notify_panel = PanelContainer.new()
	var toast := StyleBoxFlat.new()
	toast.bg_color = Color(0.07, 0.09, 0.05, 0.88)
	toast.border_color = Color(UiTheme.AMBER, 0.9)
	toast.set_border_width_all(0)
	toast.border_width_left = 3
	toast.border_width_right = 3
	toast.corner_radius_top_left = 3
	toast.corner_radius_top_right = 3
	toast.corner_radius_bottom_left = 3
	toast.corner_radius_bottom_right = 3
	toast.content_margin_left = 22.0
	toast.content_margin_right = 22.0
	toast.content_margin_top = 9.0
	toast.content_margin_bottom = 9.0
	notify_panel.add_theme_stylebox_override("panel", toast)
	notify_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notify_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notify_panel.position.y = 64
	notify_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notify_panel.modulate.a = 0.0
	root.add_child(notify_panel)
	var notify_box := VBoxContainer.new()
	notify_box.add_theme_constant_override("separation", 1)
	notify_panel.add_child(notify_box)
	var radio_tag := _label(notify_box, 10, Color(UiTheme.AMBER, 0.8), true)
	radio_tag.text = "- FIELD RADIO -"
	radio_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notify_label = _label(notify_box, 22, Color(0.98, 0.92, 0.6), true)
	notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _process(delta: float) -> void:
	_update_crosshair(delta)
	_update_waypoint()
	_update_powerups(delta)

const POWERUP_STYLE := {
	"rapid": ["RAPID FIRE", Color(1.0, 0.45, 0.1)],
	"speed": ["SUGAR RUSH", Color(0.3, 0.9, 1.0)],
	"shield": ["BUBBLE SHIELD", Color(0.45, 0.6, 1.0)],
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.05, 0.85)
	sb.border_color = style[1]
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	pill.add_theme_stylebox_override("panel", sb)
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
	if p == null or not is_instance_valid(p):
		crosshair.visible = false
		return
	crosshair.visible = true
	var target_spread := 8.0
	if "velocity" in p:
		target_spread += clampf(Vector2(p.velocity.x, p.velocity.z).length() * 0.9, 0.0, 12.0)
	if Input.is_action_pressed("fire"):
		target_spread += 6.0
	if Input.is_action_pressed("aim"):
		target_spread *= 0.5
	_spread = lerpf(_spread, target_spread, 10.0 * delta)
	cross_ticks[0].position = Vector2(-1, -_spread - 8)
	cross_ticks[1].position = Vector2(-1, _spread)
	cross_ticks[2].position = Vector2(-_spread - 8, -1)
	cross_ticks[3].position = Vector2(_spread, -1)
	var hot: bool = "aim_at_enemy" in p and p.aim_at_enemy
	var c := UiTheme.RED if hot else UiTheme.CREAM
	cross_dot.color = c
	for tick in cross_ticks:
		tick.color = Color(c, 0.85)

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
	return "SQUAD  %d   |   %s" % [count, mode.to_upper()]

func _on_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "INTEGRITY  %d / %d" % [int(current), int(maximum)]
	var missing := 1.0 - (current / maximum if maximum > 0 else 0.0)
	low_hp_vignette.modulate.a = clampf(missing - 0.25, 0.0, 0.75)

func _on_ammo(ammo: int, magazine: int) -> void:
	ammo_label.text = "%d / %d" % [ammo, magazine]
	ammo_label.add_theme_color_override("font_color", UiTheme.RED if ammo == 0 else UiTheme.CREAM)

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
		# Checkbox plate: amber outline, fills green when done.
		var check := Panel.new()
		check.custom_minimum_size = Vector2(13, 13)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.35, 0.6, 0.3, 0.95) if o.done else Color(0, 0, 0, 0.25)
		sb.border_color = Color(0.6, 0.8, 0.5) if o.done else Color(UiTheme.AMBER, 0.7)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		check.add_theme_stylebox_override("panel", sb)
		row.add_child(check)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 14)
		l.text = o.label()
		l.add_theme_color_override("font_color", Color(0.62, 0.72, 0.55) if o.done else UiTheme.CREAM)
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
	hit_marker.modulate = Color(1, 0.3, 0.2, 1.0) if killed else Color(1, 1, 1, 0.9)
	hit_marker.scale = Vector2(1.5, 1.5) if killed else Vector2.ONE
	var t := create_tween().set_parallel(true)
	t.tween_property(hit_marker, "modulate:a", 0.0, 0.3)
	t.tween_property(hit_marker, "scale", Vector2.ONE, 0.3)

func _on_player_damaged() -> void:
	damage_flash.color.a = 0.28
	var t := create_tween()
	t.tween_property(damage_flash, "color:a", 0.0, 0.5)
