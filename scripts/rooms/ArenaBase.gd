class_name ArenaBase
extends RoomBase
## Shared foundation for the arena game modes (Skirmish, Battle Royale).
## Builds THE SANDBOX — a moonlit backyard sandbox turned toy battlefield —
## and owns the plumbing every mode needs: player respawns, bot spawning,
## and a score banner overlay.
##
## The campaign's defeat-on-death flow is bypassed via Game.mode_respawns;
## modes decide themselves when the match is won or lost.

var arena_half: float = 50.0   # half-width of the play area
var mode_ui: CanvasLayer
var banner: Label
var sub_banner: Label
var _match_over := false

func _ready() -> void:
	Game.mode_respawns = true
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_arena()
	_build_mode_ui()
	_setup_mode()          # subclass: spawn combatants, set rules
	_bake_navmesh()
	Events.unit_died.connect(_on_arena_unit_died)
	Events.player_died.connect(_on_player_died_base)
	tree_exiting.connect(func(): Game.mode_respawns = false)

## Death spectator view: the player node (and its camera) is freed on death,
## so cut to a high angle over the arena until the respawn.
var _spectator: Camera3D
func _on_player_died_base() -> void:
	if _spectator == null:
		_spectator = Camera3D.new()
		_spectator.fov = 55.0
		add_child(_spectator)
		_spectator.position = Vector3(0, arena_half * 1.2, arena_half * 0.9)
		_spectator.look_at(Vector3.ZERO, Vector3.UP)
	_spectator.make_current()
	_on_player_died()

## ---- subclass hooks -------------------------------------------------------
func _setup_mode() -> void:
	pass

func _on_arena_unit_died(_unit: Node) -> void:
	pass

func _on_player_died() -> void:
	pass

## ---- world ----------------------------------------------------------------
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.1, 0.12, 0.2), Color(0.4, 0.44, 0.58), 1.0)
	add_child(we)
	add_light_rig(self, Vector3(-44, 130, 0), Color(0.68, 0.76, 1.0), 1.2)
	# Porch floodlight raking across the sand from one corner.
	var flood := SpotLight3D.new()
	flood.light_color = Color(1.0, 0.85, 0.6)
	flood.light_energy = 3.0
	flood.spot_range = arena_half * 3.0
	flood.spot_angle = 40.0
	flood.position = Vector3(-arena_half, 40, arena_half)
	flood.rotation_degrees = Vector3(-40, -45, 0)
	add_child(flood)
	register_flicker(flood, 3.0, 0.8, 0.06)

func _build_arena() -> void:
	var s := arena_half
	var sand := ToyMaterials.carpet(Color(0.6, 0.51, 0.34))
	var wood := ToyMaterials.plank_floor(Color(0.5, 0.36, 0.22))
	# Sand floor + wooden sandbox frame (tall enough to be the world border).
	_static_box(Vector3(0, -0.5, 0), Vector3(s * 2 + 12, 1.0, s * 2 + 12), sand)
	for spec in [
		[Vector3(0, 4, -s - 3), Vector3(s * 2 + 12, 8, 6)],
		[Vector3(0, 4, s + 3), Vector3(s * 2 + 12, 8, 6)],
		[Vector3(-s - 3, 4, 0), Vector3(6, 8, s * 2 + 12)],
		[Vector3(s + 3, 4, 0), Vector3(6, 8, s * 2 + 12)],
	]:
		_static_box(spec[0], spec[1], wood)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260721
	# Sandcastle strongholds: one per quadrant, fightable cover clusters.
	for quad in [Vector3(-0.55, 0, -0.55), Vector3(0.55, 0, -0.55), Vector3(-0.55, 0, 0.55), Vector3(0.55, 0, 0.55)]:
		_build_sandcastle(Vector3(quad.x * s, 0, quad.z * s), rng)
	# Center hill: king-of-the-hill dune with a planted shovel.
	_build_center_dune()
	# Scattered toy cover between the castles.
	var cover_mats := [
		ToyMaterials.plastic(Color(0.85, 0.3, 0.25), 0.3),
		ToyMaterials.plastic(Color(0.3, 0.5, 0.85), 0.3),
		ToyMaterials.plastic(Color(0.9, 0.75, 0.25), 0.3),
	]
	for i in 14:
		var pos := Vector3(rng.randf_range(-s * 0.8, s * 0.8), 0, rng.randf_range(-s * 0.8, s * 0.8))
		if pos.length() < 14.0:
			continue
		match i % 3:
			0:  # toy block
				var size := Vector3(rng.randf_range(3, 6), rng.randf_range(2.5, 5), rng.randf_range(3, 6))
				_static_box(pos + Vector3(0, size.y / 2, 0), size, cover_mats[rng.randi() % 3])
			1:  # bucket
				_static_cylinder(pos + Vector3(0, 2.2, 0), rng.randf_range(2.2, 3.2), 4.4, cover_mats[rng.randi() % 3])
			2:  # half-buried dune mound
				_static_box(pos + Vector3(0, 0.8, 0), Vector3(rng.randf_range(5, 9), 1.6, rng.randf_range(4, 7)),
					ToyMaterials.carpet(Color(0.55, 0.46, 0.3)), true)
	add_dust_motes(Vector3(0, 8, 0), Vector3(s, 8, s), 40, Color(0.85, 0.8, 0.6))

func _build_sandcastle(center: Vector3, rng: RandomNumberGenerator) -> void:
	var castle := ToyMaterials.carpet(Color(0.64, 0.54, 0.36))
	# Keep walls: a broken square with entrances.
	_static_box(center + Vector3(0, 1.75, -6), Vector3(12, 3.5, 2), castle)
	_static_box(center + Vector3(-6, 1.75, 2), Vector3(2, 3.5, 8), castle)
	_static_box(center + Vector3(6, 1.75, 2), Vector3(2, 3.5, 8), castle)
	# Corner towers with battlement tops.
	for corner in [Vector3(-6, 0, -6), Vector3(6, 0, -6)]:
		_static_cylinder(center + corner + Vector3(0, 3, 0), 2.4, 6.0, castle)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 2.6
		cm.height = 2.4
		cone.mesh = cm
		cone.material_override = castle
		cone.position = center + corner + Vector3(0, 7.2, 0)
		add_child(cone)
	# A toothpick flag on one tower.
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(2.2, 1.4, 0.1)
	flag.mesh = fm
	flag.material_override = ToyMaterials.plastic(Color(rng.randf(), rng.randf() * 0.6 + 0.3, 0.3), 0.5)
	flag.position = center + Vector3(-6, 9.6, -6)
	add_child(flag)

func _build_center_dune() -> void:
	var dune := ToyMaterials.carpet(Color(0.58, 0.49, 0.32))
	_static_box(Vector3(0, 1.0, 0), Vector3(20, 2.0, 20), dune, true)
	_static_box(Vector3(0, 2.6, 0), Vector3(12, 1.6, 12), dune, true)
	# Planted beach shovel: the arena's landmark centerpiece.
	_static_cylinder(Vector3(0, 8, 0), 0.5, 12.0, ToyMaterials.plastic(Color(0.95, 0.55, 0.15), 0.3))
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.5, 6.0, 0.6)
	blade.mesh = bm
	blade.material_override = ToyMaterials.plastic(Color(0.95, 0.55, 0.15), 0.3)
	blade.position = Vector3(0, 16.5, 0)
	add_child(blade)

## ---- combatants ------------------------------------------------------------
func spawn_player(pos: Vector3) -> Player:
	var player := Player.new()
	player.faction = load("res://data/factions/green_army.tres")
	add_child(player)
	player.position = pos
	return player

func spawn_bot(faction_path: String, pos: Vector3, variant_name: String = "trooper") -> CombatBot:
	var bot := CombatBot.new()
	bot.faction = load(faction_path)
	bot.variant = variant_name
	# Wander between own spawn and mid-field so bots seek fights.
	var wander: Array[Vector3] = [pos, pos * 0.3, Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))]
	bot.patrol_points = wander
	add_child(bot)
	bot.position = pos
	return bot

## ---- UI --------------------------------------------------------------------
func _build_mode_ui() -> void:
	mode_ui = CanvasLayer.new()
	mode_ui.layer = 5
	add_child(mode_ui)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position.y = 8
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_ui.add_child(box)
	banner = UiTheme.heading("", 26, UiTheme.CREAM)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(banner)
	sub_banner = Label.new()
	sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_banner.add_theme_font_size_override("font_size", 14)
	sub_banner.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	sub_banner.add_theme_constant_override("outline_size", 4)
	sub_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	box.add_child(sub_banner)

## ---- match end -------------------------------------------------------------
func win_match(title: String) -> void:
	if _match_over:
		return
	_match_over = true
	Game.mode_respawns = false
	Events.mission_completed.emit(title)

func lose_match(reason: String) -> void:
	if _match_over:
		return
	_match_over = true
	Game.mode_respawns = false
	Events.mission_failed.emit(reason)
