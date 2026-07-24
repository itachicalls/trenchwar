extends Node
## Game flow: animated main menu (3D diorama) → mission briefing → mission →
## victory / defeat → back. Owns the pause menu and screen-fade transitions.

## Mission registry: id → [menu label, room script, briefing text]. Add rooms here.
const MISSIONS := {
	"bedroom": [
		"ACT 1-1:  LIGHTS OUT  —  The Bedroom",
		preload("res://scripts/rooms/Bedroom.gd"),
		"2100 HOURS. The child is asleep. Chrome Legion drop pods have breached the\nbedroom perimeter and our boys are pinned across the carpet plains.\n\nRescue the prisoners. Break the patrols. Burn the beachhead.",
	],
	"living_room": [
		"ACT 1-2:  RUG BURN  —  The Living Room",
		preload("res://scripts/rooms/LivingRoom.gd"),
		"The Legion holds the TV command center and the great rug between us.\nOur forward squad is pinned behind the slipper.\n\nIntel reports something LARGE sleeping in the closet. Tread lightly, soldier.",
	],
	"kitchen": [
		"ACT 1-3:  COUNTER STRIKE  —  The Kitchen",
		preload("res://scripts/rooms/Kitchen.gd"),
		"The Legion is raiding the pantry. Their supply depot hides inside a\ncereal-box fort, heavies hold the walls, and snipers watch from the\ncounter ridge.\n\nClimb the drawers. Take the high ground. Burn the depot.",
	],
	"bathroom": [
		"ACT 2-1:  TUB THUMPING  —  The Bathroom",
		preload("res://scripts/rooms/Bathroom.gd"),
		"Chrome ears under the sink: a listening post is tapping the whole house.\nThe tub is a porcelain fortress, snipers roost on the toilet tower, and\nthe tile is open killing ground.\n\nUse the towel ramps. Silence the post. Watch the drain.",
	],
	"garage": [
		"ACT 2-2:  MOTOR POOL  —  The Garage",
		preload("res://scripts/rooms/Garage.gd"),
		"The Legion is massing armor beneath THE CAR. Their depot sits in the\nfar corner behind heavy guards, and snipers hold the paint-can shelves.\n\nTwo of our tanks survived. Take one. Roll them flat.",
	],
	"backyard": [
		"ACT 2-3:  NO MAN'S LAWN  —  The Backyard",
		preload("res://scripts/rooms/Backyard.gd"),
		"Open sky. Full moon. The Legion has cut the lawn in half with a trench\nnetwork, and their field HQ hides behind it. This is their last stand —\nand they know it.\n\nCross the trenches. Burn the HQ. Take back the house.",
	],
	"trenches": [
		"ACT 3-1:  THE TRENCHES  —  The Garden Bed",
		preload("res://scripts/rooms/GardenBed.gd"),
		"The garden bed. The Legion dug three trench lines through the tomato\nrows and their artillery pounds our positions from behind the bunkers.\n\nThis is the war the toybox will sing about.\n\nCapture the flags line by line. Silence the guns. Hold against the\ncounterattack. NO RETREAT.",
	],
	"laundry": [
		"ACT 3-2:  SPIN CYCLE  —  The Laundry Room",
		preload("res://scripts/rooms/LaundryRoom.gd"),
		"The Legion wired the washing machine into a doomsday agitator and the\nwhole room shakes on its spin cycle.\n\nRescue the laundry crew. Destroy the detergent pumps. Then hold on —\nwhen the machine spins up, EVERYTHING moves.",
	],
	"porch": [
		"ACT 3-3:  PORCH LIGHT  —  The Back Porch",
		preload("res://scripts/rooms/Porch.gd"),
		"Night air. A warm porch bulb. Chrome yard snipers in the hedge line and\na depot dug in past the watchtower.\n\nHold the signs. Burn the pods. Make the porch ours again.",
	],
	"basement": [
		"ACT 4-1:  UNDER THE STAIRS  —  The Basement",
		preload("res://scripts/rooms/Basement.gd"),
		"Under the stairs: fuel dumps, container aisles, and Chrome roomba drones\nskittering through the dark.\n\nDetonate the dumps. Recover the lost toys. Scrap the drones.",
	],
	"skirmish": [
		"SKIRMISH  —  Team Deathmatch (vs bots)",
		preload("res://scripts/rooms/SkirmishMode.gd"),
		"THE SANDBOX. Green Army versus Chrome Legion, full squads, everyone\nrespawns. First team to 25 eliminations owns the arena.\n\nTanks and a paper plane spawn mid-field. Casual rules — bots only.",
	],
	"royale": [
		"BATTLE ROYALE  —  Resurgence (vs bots)",
		preload("res://scripts/rooms/RoyaleMode.gd"),
		"Four toy squads drop into the Sandbox. The cleanup zone closes in —\nanyone caught outside gets swept.\n\nRESURGENCE: fallen return while a teammate stands. Final circles cut\nrespawns. Armor and a plane are up for grabs. Last squad wins.",
	],
	"tank_battle": [
		"TANK BATTLE  —  Armor duel (vs bots)",
		preload("res://scripts/rooms/TankBattleMode.gd"),
		"Deploy already boarded. Mouse aims the independent turret; A/D turns\nthe hull; W/S drives. Chrome AI tanks hunt you.\n\nFirst to 8 hull kills. Click once on web if look feels stuck.",
	],
	"plane_race": [
		"PAPER PLANE RACE  —  Sky circuit",
		preload("res://scripts/rooms/PlaneRaceMode.gd"),
		"Bright backyard sky course — thread numbered tire hoops in order.\n\nW throttle, A/D turn, mouse pitches. Stay airborne and beat the clock.",
	],
	"hold_dune": [
		"HOLD THE DUNE  —  Wave survival",
		preload("res://scripts/rooms/HoldDuneMode.gd"),
		"Chrome rushes the shovel mound in relentless waves — heavies, insects,\nand armor. Contested ground drains hard.\n\nStand on the dune and fill the meter. Survive the onslaught.",
	],
}
const MISSION_ORDER := ["bedroom", "living_room", "kitchen", "bathroom", "garage", "backyard", "trenches", "laundry", "porch", "basement"]

const TIPS := [
	"TIP: Rubber bands hurt. Aim-down-sights [RMB] tightens your spread.",
	"TIP: Squadmates obey [1] Follow, [2] Hold, [3] Charge. Use Hold to set ambushes.",
	"TIP: The tank's cannon has splash damage — lead groups, not stragglers.",
	"TIP: Lost toys glint gold. Five are hidden in every room.",
	"TIP: Enemies call friends when they spot you. Pick off scouts from range.",
	"TIP: Paper planes stall at low speed. Keep the throttle [W] pinned in turns.",
	"TIP: Mini-Games live under GAME MODES — tank duel, hoop race, and Hold the Dune.",
	"TIP: The Vacuum's armor is impervious. Shoot the green filter pods on its back.",
	"TIP: Sprint [SHIFT] kicks up dust. Stealthy soldiers walk.",
	"TIP: Chrome HEAVIES soak damage — feed them a tank shell instead.",
	"TIP: Chrome SCOUTS are fast but fragile. One burst drops them.",
	"TIP: A red tracer means a SNIPER has your range. Break line of sight.",
	"TIP: Squadmates never block you — walk right through and they'll step aside.",
	"TIP: The tank's cannon fires exactly where your crosshair points. Trust it.",
	"TIP: In the bathroom, towel ramps are the only way up the porcelain.",
	"TIP: The garage has TWO tanks. Bring a friend... or drive both, one at a time.",
	"TIP: Molehills on the lawn are natural foxholes. Crest them, don't cross them.",
	"TIP: On the porch, hold the signs to capture — standing still wins the zone.",
	"TIP: Basement fuel barrels chain-react. One shot can clear a whole dump.",
	"TIP: Roomba drones are low and fast. Aim down and lead the skitter.",
]

## Store catalog: permanent upgrades bought with coins. Levels stack.
const STORE_ITEMS := [
	{"id": "health", "name": "PLASTIC PLATING", "desc": "+50 max integrity per level", "costs": [120, 240, 400]},
	{"id": "damage", "name": "HOT GLUE ROUNDS", "desc": "+20% weapon damage per level", "costs": [150, 300, 480]},
	{"id": "reload", "name": "SPRING LOADER", "desc": "-15% reload time per level", "costs": [140, 320]},
	{"id": "speed", "name": "GREASED BOOTS", "desc": "+8% move speed per level", "costs": [130, 280]},
]

var current_room: Node3D = null
var current_mission_id: String = ""
var hud: HUD = null
var menu_layer: CanvasLayer = null
var diorama: Node3D = null
var fader: ColorRect = null

func _ready() -> void:
	# Menus (incl. pause) must keep processing while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# PERF (web/mobile): Compatibility renderer — MSAA + shadow atlases dominate.
	if OS.has_feature("web"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().positional_shadow_atlas_size = 1024
		RenderingServer.directional_shadow_atlas_set_size(1024, true)
		get_viewport().scaling_3d_scale = 0.78
	if Game.is_touch():
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().positional_shadow_atlas_size = 512
		RenderingServer.directional_shadow_atlas_set_size(512, true)
		get_viewport().scaling_3d_scale = 0.68
		# On-screen controls + landscape gate (touch devices only).
		add_child(preload("res://scripts/ui/TouchControls.gd").new())
		add_child(preload("res://scripts/ui/RotatePrompt.gd").new())
	# Compact type scale for touch OR any phone-sized window (incl. labs).
	_apply_mobile_ui_scale()
	get_tree().root.size_changed.connect(_apply_mobile_ui_scale)
	# Screen fader on its own top layer, always available.
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 99
	add_child(fade_layer)
	fader = ColorRect.new()
	fader.color = Color(0, 0, 0, 0)
	fader.set_anchors_preset(Control.PRESET_FULL_RECT)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fader)

	Game.release_mouse()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--lightlab"):
			add_child(LightLab.new())
			return
		if arg.begins_with("--landlab"):
			add_child(preload("res://scripts/util/LandLab.gd").new())
			return
	_show_main_menu()
	Events.player_died.connect(_on_defeat)
	Events.mission_failed.connect(_on_mode_defeat)
	Events.mission_completed.connect(_on_victory)
	# CI/headless smoke test: boot straight into the mission, run, then quit.
	if "--menushot" in args:
		get_tree().create_timer(1.5).timeout.connect(func():
			var img := get_viewport().get_texture().get_image()
			img.save_png("res://screenshots/menu.png")
			print("MENUSHOT OK")
			get_tree().quit())
	if "--barrackshot" in args:
		_show_barracks()
		get_tree().create_timer(2.0).timeout.connect(func():
			var img := get_viewport().get_texture().get_image()
			img.save_png("res://screenshots/barracks.png")
			print("BARRACKSHOT OK")
			get_tree().quit())
	if "--squadtest" in args:
		_deploy_mission("bedroom")
		get_tree().create_timer(2.0).timeout.connect(func():
			var mates := get_tree().get_nodes_in_group("green_allies")
			print("SQUADTEST mates=%d" % mates.size())
			for m in mates:
				if m is SquadMate:
					m.rescue()
			# Teleport the player far away and see if mates give chase.
			Game.player.global_position = Game.player.global_position + Vector3(14, 0, 10)
			var starts := {}
			for m in mates:
				starts[m] = (m as Node3D).global_position
			get_tree().create_timer(4.0).timeout.connect(func():
				for m in mates:
					if is_instance_valid(m):
						var moved: float = starts[m].distance_to((m as Node3D).global_position)
						print("SQUADTEST %s captive=%s cmd=%s moved=%.2f vel=%s target=%s" % [m.name, m.captive, m.command, moved, m.velocity, m.target])
						var nav: NavigationAgent3D = m._nav
						print("  nav_finished=%s nav_target=%s next=%s reachable=%s" % [nav.is_navigation_finished(), nav.target_position, nav.get_next_path_position(), nav.is_target_reachable()])
						var map: RID = (m as Node3D).get_world_3d().navigation_map
						print("  pos=%s closest_on_mesh=%s player=%s" % [(m as Node3D).global_position, NavigationServer3D.map_get_closest_point(map, (m as Node3D).global_position), Game.player.global_position])
				get_tree().quit()))
	for arg in args:
		# --smoketest / --smoketest-<mission_id>: boot the room, run, report.
		if arg.begins_with("--smoketest"):
			var smoke_id := arg.trim_prefix("--smoketest").trim_prefix("-")
			if smoke_id == "livingroom":
				smoke_id = "living_room"
			if not MISSIONS.has(smoke_id):
				smoke_id = "bedroom"
			_deploy_mission(smoke_id)
			var overhead := "--overhead" in args
			get_tree().create_timer(4.0).timeout.connect(func():
				if DisplayServer.get_name() != "headless":
					if overhead:
						var cam := Camera3D.new()
						cam.fov = 60.0
						add_child(cam)
						cam.fov = 70.0
						cam.global_position = Vector3(24, 140, 38)
						cam.look_at(Vector3(-6, 0, -6))
						cam.make_current()
						await get_tree().create_timer(0.5).timeout
					var img := get_viewport().get_texture().get_image()
					img.save_png("res://screenshots/smoke_%s.png" % current_mission_id)
				var unit_count: int = get_tree().get_nodes_in_group("enemies").size() + get_tree().get_nodes_in_group("combat_bots").size()
				print("SMOKETEST OK: room=%s units=%d" % [current_room.name, unit_count])
				get_tree().quit())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and Game.state == Game.State.PLAYING:
		_toggle_pause()

## Web: leaving pointer lock (browser ESC) should pause, not leave the player
## staring at an unresponsive game.
var _web_had_capture := false
func _check_web_pointer_lock() -> void:
	if not OS.has_feature("web") or Game.state != Game.State.PLAYING:
		return
	if get_tree().paused:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_web_had_capture = true
	elif _web_had_capture:
		_web_had_capture = false
		_toggle_pause()

func _fade(to_alpha: float, duration: float = 0.35) -> void:
	var t := create_tween()
	t.tween_property(fader, "color:a", to_alpha, duration)
	await t.finished

## MOBILE: the 1600x900 canvas stretched with aspect=expand means a phone
## screen spans THOUSANDS of design units — text renders a few real pixels
## tall and "centered" content sits in a sea of empty canvas. Scale the whole
## UI so the short screen edge always spans ~700 design units: menus, HUD and
## touch controls all become thumb-sized and readable.
func _apply_mobile_ui_scale() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return
	if not Game.compact_ui():
		get_tree().root.content_scale_factor = 1.0
		UiTheme.invalidate()
		return
	# Short edge → ~360 design units so type renders large on phones.
	# Menus are authored for that width (wrap + scroll), never shrink-to-fit.
	var short := minf(win.x, win.y)
	var factor := clampf(short / 360.0, 1.2, 2.2)
	get_tree().root.content_scale_factor = factor
	UiTheme.invalidate()

## Menu column width in content-scale units. Side gutters stay readable.
func _menu_width() -> float:
	var vp := get_viewport().get_visible_rect().size
	# Nearly full-bleed on phones — gutters are the MarginContainer's job.
	var gutter := 0.0 if Game.compact_ui() else 40.0
	return clampf(vp.x - gutter * 2.0, 280.0, 560.0 if Game.compact_ui() else 720.0)

## Mission title shortened for narrow screens (drop " — The Room" suffix).
func _mission_title(mission_id: String) -> String:
	var full: String = MISSIONS[mission_id][0]
	if not Game.compact_ui():
		return full
	var em := " — "
	if em in full:
		return full.get_slice(em, 0).strip_edges()
	if " - " in full:
		return full.get_slice(" - ", 0).strip_edges()
	return full

## Compact: "ACT 1-3" + "COUNTER STRIKE" as two readable lines.
func _mission_lines(mission_id: String) -> PackedStringArray:
	var short := _mission_title(mission_id)
	if ":  " in short:
		var parts := short.split(":  ", true, 1)
		return PackedStringArray([parts[0].strip_edges(), parts[1].strip_edges()])
	if ": " in short:
		var parts := short.split(": ", true, 1)
		return PackedStringArray([parts[0].strip_edges(), parts[1].strip_edges()])
	return PackedStringArray([short])

# ------------------------------------------------------------------ MENUS

func _clear_menu() -> void:
	if menu_layer != null:
		menu_layer.queue_free()
		menu_layer = null

func _menu_base(dim: float = 0.55) -> VBoxContainer:
	_clear_menu()
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	var themed := Control.new()
	themed.set_anchors_preset(Control.PRESET_FULL_RECT)
	themed.theme = UiTheme.build()
	menu_layer.add_child(themed)
	if dim > 0.0:
		var bg := TextureRect.new()
		bg.texture = UiTheme.radial_tex(Color(0, 0, 0, dim * 0.5), Color(0, 0, 0, minf(dim + 0.3, 1.0)), 0.5)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		themed.add_child(bg)
	# Margins + scroll: content never clips under notches or browser chrome.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 18 if Game.compact_ui() else 28
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad + (12 if Game.compact_ui() else 0))
	margin.add_theme_constant_override("margin_bottom", pad)
	themed.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	# Compact: top-align so brand + buttons own the screen (no floating island).
	# Desktop: keep the classic centered poster.
	if Game.compact_ui():
		box.alignment = BoxContainer.ALIGNMENT_BEGIN
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.custom_minimum_size.x = _menu_width()
	else:
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(center)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.custom_minimum_size.x = _menu_width()
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		center.add_child(box)
	box.add_theme_constant_override("separation", 16 if Game.compact_ui() else 12)
	if Game.compact_ui():
		scroll.add_child(box)
	box.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.28)
	box.position.y += 16
	tw.tween_property(box, "position:y", box.position.y - 16, 0.28).set_ease(Tween.EASE_OUT)
	return box

func _wrap_label(l: Label) -> void:
	l.custom_minimum_size.x = _menu_width()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _title(box: VBoxContainer, text: String, size: int, color: Color) -> Label:
	# Compact: keep display sizes BIG — wrap to two lines instead of shrinking.
	var use := size
	if Game.compact_ui() and size > 48:
		use = 48
	elif Game.compact_ui() and size > 36:
		use = size
	var l := UiTheme.heading(text, use, color)
	_wrap_label(l)
	box.add_child(l)
	return l

func _subtitle(box: VBoxContainer, text: String, size: int, color: Color) -> Label:
	var use := size
	if Game.compact_ui() and size < 16:
		use = 16   # never go micro on phones
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.body_font())
	l.add_theme_font_size_override("font_size", use)
	l.add_theme_color_override("font_color", color)
	_wrap_label(l)
	box.add_child(l)
	return l

func _button(box: VBoxContainer, text: String, action: Callable, accent: Color = Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.text = text
	var w := _menu_width()
	b.custom_minimum_size = Vector2(w, 84 if Game.compact_ui() else 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if Game.compact_ui() else Control.SIZE_SHRINK_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if Game.compact_ui():
		# Cream type + accent EDGE only — rainbow text was the "gaudy" look.
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", UiTheme.CREAM)
		b.add_theme_color_override("font_hover_color", UiTheme.AMBER)
		if accent.a > 0.0:
			var sb: StyleBoxFlat = UiTheme.build().get_stylebox("normal", "Button").duplicate()
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.9)
			sb.set_border_width_all(3)
			sb.border_width_left = 8
			b.add_theme_stylebox_override("normal", sb)
			var hover: StyleBoxFlat = UiTheme.build().get_stylebox("hover", "Button").duplicate()
			hover.border_color = accent
			hover.set_border_width_all(3)
			hover.border_width_left = 8
			b.add_theme_stylebox_override("hover", hover)
	elif accent.a > 0.0:
		b.add_theme_color_override("font_color", accent)
		var sb: StyleBoxFlat = UiTheme.build().get_stylebox("normal", "Button").duplicate()
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.7)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)
	b.mouse_entered.connect(func(): Sfx.play("click", -16.0))
	b.pressed.connect(func():
		Sfx.play("click")
		action.call())
	box.add_child(b)
	return b

## Two-line mission row: act code over the mission name (readable, not cramped).
func _mission_button(box: VBoxContainer, mission_id: String, action: Callable, accent: Color, cleared: bool = false) -> Button:
	if not Game.compact_ui():
		var label: String = MISSIONS[mission_id][0]
		if cleared:
			label += "   [CLEARED]"
		return _button(box, label, action, accent)
	var lines := _mission_lines(mission_id)
	var title_line: String = lines[0]
	var name_line: String = lines[1] if lines.size() > 1 else ""
	if cleared:
		name_line = (name_line + "  ✓") if name_line != "" else (title_line + "  ✓")
	var b := Button.new()
	b.custom_minimum_size = Vector2(_menu_width(), 84)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Nested labels so both lines stay large — Button.text alone can't do hierarchy.
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(vb)
	var a := Label.new()
	a.text = title_line
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_theme_font_override("font", UiTheme.title_font())
	a.add_theme_font_size_override("font_size", 15)
	a.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.9))
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(a)
	var n := Label.new()
	n.text = name_line if name_line != "" else title_line
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_override("font", UiTheme.title_font())
	n.add_theme_font_size_override("font_size", 22)
	n.add_theme_color_override("font_color", UiTheme.CREAM)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(n)
	var sb: StyleBoxFlat = UiTheme.build().get_stylebox("normal", "Button").duplicate()
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	sb.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", Color(0, 0, 0, 0))  # hide default text
	b.pressed.connect(func():
		Sfx.play("click")
		action.call())
	box.add_child(b)
	return b

func _spacer(box: VBoxContainer, height: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	box.add_child(s)

# --------------------------------------------------------------- MAIN MENU

func _show_main_menu() -> void:
	Game.state = Game.State.MENU
	_ensure_diorama()
	var box := _menu_base(0.35)
	if Game.compact_ui():
		# Stacked brand: hero-sized, wraps cleanly, never micro-scaled.
		var eyebrow := _title(box, "TOY SOLDIERS AT WAR", 20, UiTheme.AMBER)
		eyebrow.add_theme_constant_override("outline_size", 4)
		_title(box, "THE", 40, UiTheme.GREEN)
		var brand := _title(box, "TRENCHES", 56, UiTheme.GREEN)
		brand.add_theme_constant_override("shadow_offset_y", 5)
		_subtitle(box, "When the lights go out,\nthe war begins.", 20, Color(0.95, 0.95, 0.9))
		_spacer(box, 28)
		_button(box, "CAMPAIGN", _show_campaign, UiTheme.GREEN)
		_button(box, "SKIRMISH & ROYALE", _show_modes, UiTheme.CYAN)
		_button(box, "ARMORY", func(): _show_store(_show_main_menu), UiTheme.AMBER)
		_button(box, "BARRACKS", _show_barracks, UiTheme.PURPLE)
		_button(box, "QUIT", func(): get_tree().quit(), UiTheme.RED)
		_spacer(box, 20)
		_subtitle(box, "Rotate to landscape to deploy.\nHold AIM for auto-fire on targets.", 18, UiTheme.CYAN)
	else:
		var small := _title(box, "TOY SOLDIERS AT WAR", 24, UiTheme.AMBER)
		small.add_theme_constant_override("outline_size", 5)
		var big := _title(box, "THE TRENCHES", 88, UiTheme.GREEN)
		big.add_theme_constant_override("shadow_offset_y", 6)
		_subtitle(box, "When the lights go out, the war begins.", 18, Color(0.92, 0.92, 0.85))
		_spacer(box, 28)
		_button(box, "CAMPAIGN  —  RETAKE THE HOUSE", _show_campaign, UiTheme.GREEN)
		_button(box, "SKIRMISH & BATTLE ROYALE", _show_modes, UiTheme.CYAN)
		_button(box, "ARMORY  —  WEAPONS & UPGRADES", func(): _show_store(_show_main_menu), UiTheme.AMBER)
		_button(box, "BARRACKS  —  SOLDIER SKINS", _show_barracks, UiTheme.PURPLE)
		_button(box, "QUIT", func(): get_tree().quit(), UiTheme.RED)
		_spacer(box, 22)
		_subtitle(box, "WASD move   SHIFT sprint   SPACE jump   double-tap SPACE + hold = JETPACK   MOUSE aim/fire
RMB zoom   R reload   Q swap weapon   E interact / rescue / vehicles   1-2-3 squad orders   ESC pause", 13, Color(0.72, 0.76, 0.7))
		if OS.has_feature("web"):
			_subtitle(box, "Browser: click once in-mission to lock the mouse.", 12, Color(0.7, 0.82, 0.95))
	var version := Label.new()
	version.text = "PRE-ALPHA 0.4"
	version.add_theme_font_size_override("font_size", 14 if Game.compact_ui() else 12)
	version.add_theme_color_override("font_color", Color(0.55, 0.6, 0.5))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_layer.get_child(0).add_child(version)

## Mission select: campaign acts as a bright poster wall.
func _show_campaign() -> void:
	var box := _menu_base(0.5)
	_title(box, "CAMPAIGN", 42 if Game.compact_ui() else 52, UiTheme.GREEN)
	_subtitle(box, "Take back the house, room by room.", 17 if Game.compact_ui() else 15, Color(0.88, 0.9, 0.82))
	_subtitle(box, "COINS  %d" % Game.coins, 18 if Game.compact_ui() else 15, UiTheme.AMBER)
	_spacer(box, 12)
	var prev_beaten := true
	for id in MISSION_ORDER:
		var mission_id: String = id
		var beaten: bool = id in Game.completed_missions
		var accent: Color = UiTheme.ORANGE if id in ["trenches", "laundry"] else UiTheme.GREEN
		if prev_beaten:
			_mission_button(box, mission_id, func(): _show_briefing(mission_id), accent, beaten)
		else:
			var locked := _button(box, "LOCKED", func(): pass, Color(0.5, 0.52, 0.46))
			if not Game.compact_ui():
				locked.text = "LOCKED  —  clear the previous chapter"
			locked.disabled = true
		prev_beaten = beaten
	_spacer(box, 10)
	_button(box, "BACK", _show_main_menu)

## Living 3D scene behind the menu: a Green Army squad posed on a carpet disc
## under a nightlight, with a slow orbiting camera and drifting dust motes.
func _ensure_diorama() -> void:
	if diorama != null and is_instance_valid(diorama):
		return
	diorama = Node3D.new()
	add_child(diorama)

	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.1, 0.11, 0.2), Color(0.4, 0.44, 0.58), 1.15)
	diorama.add_child(we)
	RoomBase.add_light_rig(diorama, Vector3(-40, 150, 0), Color(0.66, 0.75, 1.0), 1.4)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.78, 0.5)
	warm.light_energy = 2.6
	warm.omni_range = 22.0
	warm.position = Vector3(4, 5, 4)
	diorama.add_child(warm)

	# Carpet disc stage.
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 10.0
	cyl.bottom_radius = 10.5
	cyl.height = 0.8
	disc.mesh = cyl
	disc.material_override = ToyMaterials.soft(Color(0.36, 0.3, 0.42))
	disc.position.y = -0.4
	diorama.add_child(disc)

	# The squad, posed.
	var green: FactionData = load("res://data/factions/green_army.tres")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	for i in 3:
		var soldier := ModelLib.build_character(green)
		soldier.position = Vector3(-1.5 + i * 1.5, 0, 1.0 - absf(i - 1) * 0.6)
		soldier.rotation_degrees.y = -8 + i * 8
		diorama.add_child(soldier)
	var enemy := ModelLib.build_character(chrome, true)
	enemy.position = Vector3(4.2, 0, -2.0)
	enemy.rotation_degrees.y = 160
	diorama.add_child(enemy)
	var menu_tank := ModelLib.build_tank(3.4)
	if menu_tank != null:
		menu_tank.position = Vector3(1.8, 0, -3.2)
		menu_tank.rotation_degrees.y = -25
		diorama.add_child(menu_tank)
	var bear := ToyBodyBuilder.build_plush_bear()
	bear.position = Vector3(-3.6, 0, -1.4)
	bear.rotation_degrees.y = 35
	bear.scale = Vector3.ONE * 1.6
	diorama.add_child(bear)
	# A couple of blocks for the skyline.
	for spec in [[Vector3(-5, 1.25, -4), Color(0.85, 0.2, 0.15)], [Vector3(6, 1.25, 2.5), Color(0.2, 0.45, 0.8)], [Vector3(-6.2, 3.7, -4.2), Color(0.95, 0.75, 0.1)]]:
		var block := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.5, 2.5, 2.5)
		block.mesh = bm
		block.material_override = ToyMaterials.plastic(spec[1], 0.5)
		block.position = spec[0]
		block.rotation_degrees.y = randf_range(0, 45)
		diorama.add_child(block)

	# Drifting dust motes in the nightlight.
	var motes := CPUParticles3D.new()
	motes.amount = 40
	motes.lifetime = 6.0
	motes.preprocess = 6.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(9, 4, 9)
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.4
	motes.direction = Vector3(0.3, -0.2, 0.1)
	motes.scale_amount_min = 0.015
	motes.scale_amount_max = 0.04
	var mm := BoxMesh.new()
	mm.size = Vector3.ONE
	mm.material = ToyMaterials.glow(Color(0.9, 0.85, 0.7), 0.8)
	motes.mesh = mm
	motes.position.y = 3.0
	diorama.add_child(motes)

	# Slow orbit camera.
	var pivot := Node3D.new()
	pivot.name = "CamPivot"
	diorama.add_child(pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.2, 9.5)
	cam.rotation_degrees.x = -12
	cam.fov = 55
	pivot.add_child(cam)
	cam.make_current()

func _process(delta: float) -> void:
	_check_web_pointer_lock()
	if diorama != null and is_instance_valid(diorama):
		var pivot := diorama.get_node_or_null("CamPivot")
		if pivot != null:
			pivot.rotate_y(delta * 0.12)

func _clear_diorama() -> void:
	if diorama != null and is_instance_valid(diorama):
		diorama.queue_free()
	diorama = null

# --------------------------------------------------------------- BRIEFING

func _show_briefing(mission_id: String) -> void:
	var box := _menu_base(0.6)
	_title(box, "BRIEFING", 20 if Game.compact_ui() else 26, Color(0.72, 0.8, 0.62))
	if Game.compact_ui():
		var lines := _mission_lines(mission_id)
		_title(box, lines[0], 20, UiTheme.AMBER)
		if lines.size() > 1:
			_title(box, lines[1], 32, UiTheme.AMBER)
	else:
		_title(box, MISSIONS[mission_id][0], 40, UiTheme.AMBER)
	_spacer(box, 8)
	_subtitle(box, MISSIONS[mission_id][2], 17 if Game.compact_ui() else 16, Color(0.9, 0.9, 0.84))
	_spacer(box, 12)
	_subtitle(box, TIPS[randi() % TIPS.size()], 16 if Game.compact_ui() else 14, UiTheme.CYAN)
	_spacer(box, 18 if Game.compact_ui() else 22)
	_button(box, "DEPLOY", func():
		# Capture NOW, inside the click gesture — browsers refuse pointer lock
		# once the fade delays it, leaving the camera frozen until first click.
		Game.capture_mouse()
		await _fade(1.0, 0.4)
		_deploy_mission(mission_id)
		await _fade(0.0, 0.6), UiTheme.GREEN)
	_button(box, "BACK", _show_modes if mission_id in ["skirmish", "royale", "tank_battle", "plane_race", "hold_dune"] else _show_campaign)

# ------------------------------------------------------------------ FLOW

func _deploy_mission(mission_id: String) -> void:
	_clear_menu()
	_clear_diorama()
	_end_mission()
	Game.state = Game.State.PLAYING
	Game.squad.clear()
	Game.plastic_parts = 0
	Game.kills = 0
	current_mission_id = mission_id
	current_room = MISSIONS[mission_id][1].new()
	add_child(current_room)
	hud = HUD.new()
	add_child(hud)
	Game.capture_mouse_on_web()

func _end_mission() -> void:
	if current_room != null:
		current_room.queue_free()
		current_room = null
	if hud != null:
		hud.queue_free()
		hud = null
	Game.release_mouse()

func _toggle_pause() -> void:
	if get_tree().paused:
		get_tree().paused = false
		_clear_menu()
		# Direct capture: pause-menu button press is a user gesture, so the
		# browser allows pointer lock here.
		Game.capture_mouse()
	else:
		get_tree().paused = true
		Game.release_mouse()
		_show_pause_menu()

func _show_pause_menu() -> void:
	var box := _menu_base(0.6)
	_title(box, "PAUSED", 40 if Game.compact_ui() else 52, UiTheme.CREAM)
	_subtitle(box, _mission_title(current_mission_id), 15, Color(0.7, 0.75, 0.65))
	_subtitle(box, "COINS  %d" % Game.coins, 15, Color(1, 0.8, 0.25))
	_spacer(box, 12)
	_button(box, "RESUME", _toggle_pause)
	_button(box, "ARMORY", func(): _show_store(_show_pause_menu))
	if Game.is_touch():
		_button(box, "GYRO AIM: %s" % ("ON" if Game.gyro_enabled else "OFF"), func():
			Game.gyro_enabled = not Game.gyro_enabled
			Game.save_progress()
			_show_pause_menu(), UiTheme.CYAN)
		_button(box, "AUTO-FIRE (AIM): %s" % ("ON" if Game.auto_fire_enabled else "OFF"), func():
			Game.auto_fire_enabled = not Game.auto_fire_enabled
			Game.save_progress()
			_show_pause_menu(), UiTheme.AMBER)
	_button(box, "RESTART MISSION", func():
		get_tree().paused = false
		Game.capture_mouse()   # inside the click gesture (web pointer lock)
		await _fade(1.0, 0.3)
		_deploy_mission(current_mission_id)
		await _fade(0.0, 0.5))
	_button(box, "ABANDON MISSION", func():
		get_tree().paused = false
		Game.save_progress()
		_end_mission()
		_show_main_menu())

# ---------------------------------------------------------------- GAME MODES

func _show_modes() -> void:
	var box := _menu_base(0.62)
	_title(box, "GAME MODES", 36 if Game.compact_ui() else 46, UiTheme.CYAN)
	_subtitle(box, "Sandbox arenas & toy mini-games. Coins and loadout carry over.", 14, Color(0.75, 0.78, 0.7))
	_spacer(box, 10)
	_subtitle(box, "VERSUS", 13, Color(0.55, 0.7, 0.85))
	if Game.compact_ui():
		_button(box, "SKIRMISH (VS BOTS)", func(): _show_briefing("skirmish"))
		_button(box, "BATTLE ROYALE (VS BOTS)", func(): _show_briefing("royale"))
	else:
		_button(box, "SKIRMISH  —  CASUAL (VS BOTS)", func(): _show_briefing("skirmish"))
		_button(box, "BATTLE ROYALE: RESURGENCE  —  CASUAL (VS BOTS)", func(): _show_briefing("royale"))
	_spacer(box, 8)
	_subtitle(box, "MINI-GAMES", 13, Color(0.85, 0.7, 0.45))
	if Game.compact_ui():
		_button(box, "TANK BATTLE", func(): _show_briefing("tank_battle"))
		_button(box, "PAPER PLANE RACE", func(): _show_briefing("plane_race"))
		_button(box, "HOLD THE DUNE", func(): _show_briefing("hold_dune"))
	else:
		_button(box, "TANK BATTLE  —  ARMOR DUEL", func(): _show_briefing("tank_battle"))
		_button(box, "PAPER PLANE RACE  —  HOOP COURSE", func(): _show_briefing("plane_race"))
		_button(box, "HOLD THE DUNE  —  KING OF THE HILL", func(): _show_briefing("hold_dune"))
	_spacer(box, 6)
	var online := _button(box, "ONLINE — COMING SOON", func(): pass)
	online.disabled = true
	_spacer(box, 6)
	_subtitle(box, "Premade toy cover you can land on. Race hoops are pass-through — no floating air blockers.", 12, Color(0.6, 0.65, 0.6))
	_spacer(box, 10)
	_button(box, "BACK", _show_main_menu)

# ------------------------------------------------------------------ BARRACKS

## Skin picker: every entry is a different plastic batch of the same soldier.
func _show_barracks() -> void:
	var box := _menu_base(0.7)
	_title(box, "BARRACKS", 46, UiTheme.GREEN)
	var coins_line := _subtitle(box, "COINS  %d" % Game.coins, 20, Color(1, 0.8, 0.25))
	_subtitle(box, "Pick your soldier. New molds are unlocked with coins.", 14, Color(0.75, 0.78, 0.7))
	_spacer(box, 12)
	for skin in Game.SKINS:
		_skin_row(box, skin)
	_spacer(box, 14)
	_button(box, "BACK", _show_main_menu)

func _skin_row(box: VBoxContainer, skin: Dictionary) -> void:
	var row := PanelContainer.new()
	var selected: bool = Game.selected_skin == skin.id
	var unlocked: bool = skin.id in Game.unlocked_skins
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.08, 0.95) if selected else Color(0.09, 0.11, 0.07, 0.9)
	sb.border_color = UiTheme.GREEN if selected else Color(UiTheme.AMBER, 0.3)
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", sb)
	row.custom_minimum_size = Vector2(560, 0)
	box.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	# Live 3D portrait: the actual soldier mold in this plastic batch,
	# idling and slowly turning on a dime like a store display.
	h.add_child(_skin_portrait(skin))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var name_l := UiTheme.heading(skin.name, 16, UiTheme.CREAM)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(name_l)
	var desc_l := Label.new()
	desc_l.text = skin.desc
	desc_l.add_theme_font_size_override("font_size", 12)
	desc_l.add_theme_color_override("font_color", Color(0.72, 0.75, 0.68))
	info.add_child(desc_l)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 38)
	if selected:
		btn.text = "EQUIPPED"
		btn.disabled = true
	elif unlocked:
		btn.text = "EQUIP"
		btn.pressed.connect(func():
			Game.selected_skin = skin.id
			Game.save_progress()
			Sfx.play("pickup")
			_show_barracks())
	else:
		btn.text = "%d c" % skin.cost
		btn.disabled = Game.coins < skin.cost
		btn.pressed.connect(func():
			if Game.coins >= skin.cost:
				Game.coins -= skin.cost
				Game.unlocked_skins.append(skin.id)
				Game.selected_skin = skin.id
				Game.save_progress()
				Sfx.play("pickup")
				_show_barracks())
	h.add_child(btn)

## Miniature 3D viewport rendering the real (tinted) soldier model.
func _skin_portrait(skin: Dictionary) -> Control:
	var container := SubViewportContainer.new()
	# stretch_shrink=1 with the vp pre-sized to the slot: the container's
	# minimum size is derived from the viewport, so a mismatched vp.size
	# stretched the slot wide and shoved the soldier off to the left.
	container.stretch = true
	container.custom_minimum_size = Vector2(84, 84)
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.world_3d = World3D.new()
	vp.transparent_bg = true
	vp.size = Vector2i(84, 84)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.06, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.85)
	env.ambient_light_energy = 1.3
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 28, 0)
	key.light_energy = 1.5
	vp.add_child(key)

	var green: FactionData = load("res://data/factions/green_army.tres")
	var rig := ModelLib.build_character(green, false, Game.weapon_info(Game.selected_weapon).gun, skin.tint, 1.0)
	vp.add_child(rig)

	var cam := Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	# look_at() FAILS outside the tree (this whole subtree is built before the
	# row is added) — the camera silently kept its default orientation and the
	# portraits rendered garbage. Build the aim transform by hand instead.
	var cam_pos := Vector3(0, 1.5, -4.4)
	cam.transform = Transform3D(
		Basis.looking_at(Vector3(0, 1.1, 0) - cam_pos, Vector3.UP), cam_pos)
	# Tweens can only be created inside the tree — start the display spin
	# once the menu row is actually added.
	container.tree_entered.connect(func():
		var spin := rig.create_tween().set_loops()
		spin.tween_property(rig, "rotation:y", TAU, 7.0).from(0.0))
	return container

# ------------------------------------------------------------------ STORE

func _show_store(back: Callable) -> void:
	var box := _menu_base(0.7)
	_title(box, "ARMORY", 46, UiTheme.AMBER)
	var coins_line := _subtitle(box, "COINS  %d" % Game.coins, 22, Color(1, 0.8, 0.25))
	_subtitle(box, "Salvaged coins buy weapons and permanent field upgrades.", 14, Color(0.75, 0.78, 0.7))
	_spacer(box, 12)
	# Two columns: weapon rack | field upgrades. Keeps the menu on-screen.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	left.add_child(UiTheme.heading("WEAPON RACK", 20, UiTheme.CYAN))
	for w in Game.WEAPONS:
		_weapon_row(left, w, back)
	right.add_child(UiTheme.heading("FIELD UPGRADES", 20, UiTheme.GREEN))
	for item in STORE_ITEMS:
		_store_row(right, item, coins_line, back)
	_spacer(box, 14)
	_button(box, "BACK", back)

func _weapon_row(box: VBoxContainer, w: Dictionary, back: Callable) -> void:
	var equipped: bool = Game.selected_weapon == w.id
	var owned: bool = w.id in Game.owned_weapons
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.13, 0.1, 0.95) if equipped else Color(0.09, 0.11, 0.07, 0.9)
	sb.border_color = UiTheme.CYAN if equipped else Color(UiTheme.AMBER, 0.3)
	sb.set_border_width_all(2 if equipped else 1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", sb)
	row.custom_minimum_size = Vector2(560, 0)
	box.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var name_l := UiTheme.heading(w.name, 16, UiTheme.CREAM)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(name_l)
	var wd: WeaponData = load(w.path)
	var desc_l := Label.new()
	desc_l.text = "%s   [DMG %d  •  RATE %.1f/s  •  MAG %d]" % [w.desc, int(wd.damage), wd.fire_rate, wd.magazine_size]
	desc_l.add_theme_font_size_override("font_size", 12)
	desc_l.add_theme_color_override("font_color", Color(0.72, 0.75, 0.68))
	info.add_child(desc_l)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(130, 38)
	if equipped:
		btn.text = "EQUIPPED"
		btn.disabled = true
	elif owned:
		btn.text = "EQUIP"
		btn.pressed.connect(func():
			Game.selected_weapon = w.id
			Game.save_progress()
			Sfx.play("pickup")
			# Mid-mission equip applies immediately.
			if Game.player != null and is_instance_valid(Game.player):
				Game.player.set_loadout(load(w.path), w.gun)
			_show_store(back))
	else:
		btn.text = "%d c" % w.cost
		btn.disabled = Game.coins < w.cost
		btn.pressed.connect(func():
			if Game.coins >= w.cost:
				Game.coins -= w.cost
				Game.owned_weapons.append(w.id)
				Game.selected_weapon = w.id
				Game.save_progress()
				Sfx.play("pickup")
				if Game.player != null and is_instance_valid(Game.player):
					Game.player.weapon.set_data(load(w.path))
				_show_store(back))
	h.add_child(btn)

func _store_row(box: VBoxContainer, item: Dictionary, coins_line: Label, back: Callable) -> void:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.07, 0.9)
	sb.border_color = Color(UiTheme.AMBER, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", sb)
	row.custom_minimum_size = Vector2(560, 0)
	box.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var level: int = Game.upgrades.get(item.id, 0)
	var costs: Array = item.costs
	var name_l := UiTheme.heading("%s" % item.name, 17, UiTheme.CREAM)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(name_l)
	var desc_l := Label.new()
	desc_l.text = item.desc
	desc_l.add_theme_font_size_override("font_size", 13)
	desc_l.add_theme_color_override("font_color", Color(0.72, 0.75, 0.68))
	info.add_child(desc_l)

	# Level pips.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	h.add_child(pips)
	for i in costs.size():
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(12, 12)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ps := StyleBoxFlat.new()
		ps.bg_color = UiTheme.GREEN if i < level else Color(0, 0, 0, 0.4)
		ps.border_color = Color(UiTheme.GREEN, 0.7) if i < level else Color(0.4, 0.45, 0.38)
		ps.set_border_width_all(1)
		ps.set_corner_radius_all(6)
		pip.add_theme_stylebox_override("panel", ps)
		pips.add_child(pip)

	var maxed := level >= costs.size()
	var cost: int = 0 if maxed else costs[level]
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(120, 40)
	buy.text = "MAXED" if maxed else "%d c" % cost
	buy.disabled = maxed or Game.coins < cost
	buy.pressed.connect(func():
		if Game.coins >= cost and not maxed:
			Game.coins -= cost
			Game.upgrades[item.id] = level + 1
			Game.save_progress()
			Sfx.play("pickup")
			# Live-apply to the current soldier if mid-mission.
			if Game.player != null and is_instance_valid(Game.player):
				var p := Game.player
				p.base_health = 200.0 + 50.0 * Game.upgrades.get("health", 0)
				p.health.max_health = p.base_health
				p.weapon.damage_mult = 1.0 + 0.2 * Game.upgrades.get("damage", 0)
				p.weapon.reload_mult = 1.0 - 0.15 * Game.upgrades.get("reload", 0)
			_show_store(back))
	h.add_child(buy)

func _next_mission_id() -> String:
	var idx := MISSION_ORDER.find(current_mission_id)
	if idx >= 0 and idx + 1 < MISSION_ORDER.size():
		return MISSION_ORDER[idx + 1]
	return ""

func _on_victory(title: String) -> void:
	if Game.state != Game.State.PLAYING:
		return
	Game.state = Game.State.VICTORY
	if current_mission_id in MISSION_ORDER:
		Game.mark_mission_complete(current_mission_id)
	# Victory lap: the soldier turns to camera and waves while the moment
	# breathes, then the screen appears.
	if Game.player != null and is_instance_valid(Game.player):
		Game.player.celebrate()
	await get_tree().create_timer(2.6).timeout
	Game.release_mouse()
	var box := _menu_base(0.62)
	_title(box, "MISSION COMPLETE", 58, UiTheme.GREEN)
	_subtitle(box, title, 20, Color(0.9, 0.9, 0.8))
	_spacer(box, 10)
	var next_id := _next_mission_id()
	if next_id != "":
		_subtitle(box, "This room is ours again... for now.\nChrome forces are regrouping deeper in the house.", 16, Color(0.78, 0.8, 0.72))
	else:
		_subtitle(box, "The house is quiet. Act 2 awaits beyond the hallway...", 16, Color(0.78, 0.8, 0.72))
	_spacer(box, 8)
	_subtitle(box, "ENEMIES DOWN  %d      PARTS SALVAGED  %d      LOST TOYS  %d / %d" % [Game.kills, Game.plastic_parts, LostToy.found_in_level, LostToy.total_in_level], 16, UiTheme.AMBER)
	_subtitle(box, "COIN PURSE  %d" % Game.coins, 16, Color(1, 0.8, 0.25))
	Game.save_progress()
	_spacer(box, 20)
	if next_id != "":
		var adv: String = ("NEXT: %s" % _mission_title(next_id)) if Game.compact_ui() else ("ADVANCE  —  " + MISSIONS[next_id][0])
		_button(box, adv, func(): _show_briefing(next_id))
	_button(box, "ARMORY", func(): _show_store(func(): _on_victory_menu_return(title, next_id)))
	_button(box, "RETURN TO BASE", func():
		_end_mission()
		_show_main_menu())

## Rebuild the victory menu after visiting the store from it.
func _on_victory_menu_return(title: String, next_id: String) -> void:
	var box := _menu_base(0.62)
	_title(box, "MISSION COMPLETE", 40 if Game.compact_ui() else 58, UiTheme.GREEN)
	_subtitle(box, title, 18 if Game.compact_ui() else 20, Color(0.9, 0.9, 0.8))
	_subtitle(box, "COIN PURSE  %d" % Game.coins, 16, Color(1, 0.8, 0.25))
	_spacer(box, 20)
	if next_id != "":
		var adv: String = ("NEXT: %s" % _mission_title(next_id)) if Game.compact_ui() else ("ADVANCE  —  " + MISSIONS[next_id][0])
		_button(box, adv, func(): _show_briefing(next_id))
	_button(box, "ARMORY", func(): _show_store(func(): _on_victory_menu_return(title, next_id)))
	_button(box, "RETURN TO BASE", func():
		_end_mission()
		_show_main_menu())

func _on_defeat() -> void:
	# Arena modes respawn the player and decide defeat themselves.
	if Game.mode_respawns:
		return
	if Game.state != Game.State.PLAYING:
		return
	Game.state = Game.State.DEFEAT
	await get_tree().create_timer(1.5).timeout
	Game.release_mouse()
	Game.save_progress()
	_show_defeat_menu("Your plastic shattered on the carpet plains.")

## Match lost in an arena mode (skirmish score / royale squad wipe).
func _on_mode_defeat(reason: String) -> void:
	if Game.state != Game.State.PLAYING:
		return
	Game.state = Game.State.DEFEAT
	await get_tree().create_timer(1.5).timeout
	Game.release_mouse()
	Game.save_progress()
	_show_defeat_menu(reason)

func _show_defeat_menu(flavor: String) -> void:
	var box := _menu_base(0.72)
	_title(box, "YOU GOT PLAYED WITH", 54, UiTheme.RED)
	_subtitle(box, flavor, 17, Color(0.85, 0.8, 0.75))
	_subtitle(box, "ENEMIES DOWN  %d      PARTS SALVAGED  %d      COINS KEPT  %d" % [Game.kills, Game.plastic_parts, Game.coins], 15, Color(0.7, 0.7, 0.62))
	_spacer(box, 18)
	_button(box, "ARMORY", func(): _show_store(func(): _show_defeat_menu(flavor)))
	_button(box, "REDEPLOY", func():
		Game.capture_mouse()   # inside the click gesture (web pointer lock)
		await _fade(1.0, 0.3)
		_deploy_mission(current_mission_id)
		await _fade(0.0, 0.5))
	_button(box, "MAIN MENU", func():
		_end_mission()
		_show_main_menu())

