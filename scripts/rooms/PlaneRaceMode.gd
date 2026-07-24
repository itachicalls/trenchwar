class_name PlaneRaceMode
extends ArenaBase
## PAPER PLANE RACE — bright backyard sky circuit. Thread glowing tire hoops
## in order before the clock runs out. Daylight environment (not the night
## sandbox) so altitude never reads as a black void.

const TIME_LIMIT := 100.0
const HOOP_COUNT := 8

var _plane: PaperPlane
var _hoops: Array[Area3D] = []
var _next := 0
var _time_left := TIME_LIMIT
var _started := false
var _finished := false
var _banner_cd := 0.0
var _guide: MeshInstance3D

func _init() -> void:
	arena_half = 58.0

## Bright daytime sky — overrides ArenaBase night lighting.
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.92)   # clear afternoon sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.95 if Game.low_gfx() else 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = not Game.low_gfx()
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.92)
	env.fog_density = 0.00035
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	# Warm key sun + soft fill so sand and toys never crush to black.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.82)
	sun.light_energy = 1.55 if Game.low_gfx() else 1.35
	sun.shadow_enabled = not Game.low_gfx()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.light_energy = 0.55
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-25, 140, 0)
	add_child(fill)

func _build_arena() -> void:
	var s := arena_half
	var sand := ToyMaterials.carpet(Color(0.72, 0.62, 0.42))
	var wood := ToyMaterials.plank_floor(Color(0.55, 0.4, 0.26))
	_static_box(Vector3(0, -0.5, 0), Vector3(s * 2 + 14, 1.0, s * 2 + 14), sand)
	for spec in [
		[Vector3(0, 1.6, -s - 3), Vector3(s * 2 + 14, 3.2, 5)],
		[Vector3(0, 1.6, s + 3), Vector3(s * 2 + 14, 3.2, 5)],
		[Vector3(-s - 3, 1.6, 0), Vector3(5, 3.2, s * 2 + 14)],
		[Vector3(s + 3, 1.6, 0), Vector3(5, 3.2, s * 2 + 14)],
	]:
		_static_box(spec[0], spec[1], wood)
	# Low center mound — landmark, not a flight wall.
	_static_box(Vector3(0, 0.8, 0), Vector3(16, 1.6, 16),
		ToyMaterials.carpet(Color(0.65, 0.55, 0.36)), true)
	_static_cylinder(Vector3(0, 6, 0), 0.4, 10.0,
		ToyMaterials.plastic(Color(0.95, 0.55, 0.2), 0.35))

func _setup_mode() -> void:
	Missions.start_mission("PAPER PLANE RACE")
	_build_course()
	_plane = spawn_plane(Vector3(-arena_half + 12, 9, 0), 90.0)
	_plane.lock_bail = true
	var player := spawn_player(Vector3(-arena_half + 12, 1, 4))
	_plane.call_deferred("force_board", player)
	_started = true
	_update_banner()
	sub_banner.text = "THREAD THE HOOPS IN ORDER  •  W THROTTLE  •  A/D TURN"
	Events.notify.emit("AIR RACE: follow the green gate. Bright sky circuit — stay high and thread them!")

func _build_course() -> void:
	# Premade clutter as visual islands (landable, not flight blockers in the lane).
	add_prop("crate", Vector3(14, 0, -22), 20.0, 3.4)
	add_prop("crate", Vector3(-18, 0, 20), -35.0, 3.2)
	add_prop("pallet", Vector3(24, 0, 8), 40.0, 3.6)
	add_prop("barrier_large", Vector3(-8, 0, -8), 15.0, 5.5)
	add_prop("cone", Vector3(-arena_half + 18, 0, -5), 0.0, 1.6)
	add_prop("cone", Vector3(-arena_half + 18, 0, 5), 0.0, 1.6)
	add_prop("tree_2", Vector3(32, 0, 22), 15.0, 10.0, false)
	add_prop("tree_3", Vector3(-30, 0, -24), -25.0, 9.0, false)
	add_prop("tree_1", Vector3(8, 0, 34), 50.0, 8.0, false)
	# Oval sky circuit with rising / diving gates.
	for i in HOOP_COUNT:
		var t := float(i) / float(HOOP_COUNT)
		var ang := t * TAU - PI * 0.5
		var r := arena_half * 0.62
		var height := 9.0 + sin(t * TAU * 2.0) * 4.5 + (2.0 if i % 2 == 0 else 0.0)
		var pos := Vector3(cos(ang) * r, height, sin(ang) * r)
		# Face along the flight path (tangent).
		var yaw := rad_to_deg(ang + PI * 0.5)
		_hoops.append(_make_hoop(pos, yaw, i))
	_guide = MeshInstance3D.new()
	var arrow := PrismMesh.new()
	arrow.size = Vector3(1.6, 0.4, 2.2)
	_guide.mesh = arrow
	_guide.material_override = ToyMaterials.glow(Color(0.35, 1.0, 0.55), 1.6)
	add_child(_guide)
	_highlight_next()

func _make_hoop(pos: Vector3, yaw_deg: float, index: int) -> Area3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	add_child(root)
	# Twin posts + tire ring — readable silhouette against the bright sky.
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.18
		pm.bottom_radius = 0.22
		pm.height = 5.2
		post.mesh = pm
		post.material_override = ToyMaterials.plastic(Color(0.9, 0.85, 0.35), 0.4)
		post.position = Vector3(side * 2.8, 0, 0)
		root.add_child(post)
	var tire := ModelLib.build_prop("tires", 5.8)
	if tire != null:
		tire.rotation_degrees.x = 90.0
		root.add_child(tire)
	else:
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.7
		cm.bottom_radius = 2.7
		cm.height = 0.5
		ring.mesh = cm
		ring.rotation_degrees.x = 90.0
		ring.material_override = ToyMaterials.plastic(Color(0.18, 0.18, 0.2), 0.5)
		root.add_child(ring)
	var glow := MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = 2.35
	gm.outer_radius = 2.85
	gm.rings = 16 if Game.low_gfx() else 24
	gm.ring_segments = 6
	glow.mesh = gm
	glow.rotation_degrees.x = 90.0
	glow.material_override = ToyMaterials.plastic(Color(0.4, 0.85, 1.0), 0.35)
	glow.name = "Glow"
	root.add_child(glow)
	# Number plaque so order is obvious.
	var num := Label3D.new()
	num.text = str(index + 1)
	num.font_size = 96
	num.pixel_size = 0.025
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.modulate = Color(1, 1, 1)
	num.outline_size = 16
	num.position = Vector3(0, 3.6, 0)
	num.name = "Num"
	root.add_child(num)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 0b0100
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.6
	cs.shape = sphere
	area.add_child(cs)
	area.set_meta("index", index)
	area.body_entered.connect(_on_hoop_body.bind(area))
	root.add_child(area)
	return area

func _on_hoop_body(body: Node, area: Area3D) -> void:
	if _finished or not (body is PaperPlane):
		return
	var idx: int = int(area.get_meta("index", -1))
	if idx != _next:
		return
	_next += 1
	Sfx.play("objective", -4.0)
	Fx.ring_pulse(self, area.global_position, Color(0.4, 1.0, 0.55), 5.0, 0.45)
	Events.notify.emit("HOOP %d / %d" % [_next, HOOP_COUNT])
	if _next >= HOOP_COUNT:
		_finished = true
		var bonus := maxi(0, int(_time_left) * 2)
		Game.coins += 20 + bonus
		Events.coins_changed.emit(Game.coins)
		win_match("AIR RACE CLEARED  +%d COINS" % (20 + bonus))
	else:
		_highlight_next()
	_update_banner()

func _highlight_next() -> void:
	for i in _hoops.size():
		var area := _hoops[i]
		var root := area.get_parent()
		var glow: MeshInstance3D = root.get_node_or_null("Glow")
		var num: Label3D = root.get_node_or_null("Num")
		if glow == null:
			continue
		if i == _next:
			glow.material_override = ToyMaterials.glow(Color(0.3, 1.0, 0.5), 2.4 if not Game.low_gfx() else 1.4)
			glow.visible = true
			if num:
				num.modulate = Color(0.4, 1.0, 0.55)
		elif i < _next:
			glow.visible = false
			if num:
				num.modulate = Color(0.5, 0.5, 0.5, 0.5)
		else:
			glow.material_override = ToyMaterials.plastic(Color(0.45, 0.8, 1.0), 0.4)
			glow.visible = true
			if num:
				num.modulate = Color(0.85, 0.95, 1.0)
	_update_guide()

func _update_guide() -> void:
	if _guide == null or _next >= _hoops.size():
		if _guide:
			_guide.visible = false
		return
	_guide.visible = true
	var target: Vector3 = _hoops[_next].global_position
	_guide.global_position = target + Vector3(0, 4.5, 0)
	# Point the prism toward the previous / approach direction.
	if _plane != null and is_instance_valid(_plane):
		var from := _plane.global_position
		var flat := Vector3(target.x - from.x, 0, target.z - from.z)
		if flat.length_squared() > 0.01:
			_guide.look_at(target, Vector3.UP)

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing() or not _started or _finished:
		return
	if _plane != null and not is_instance_valid(_plane):
		_finished = true
		lose_match("Paper plane shredded — race over.")
		return
	_update_guide()
	_time_left -= delta
	_banner_cd -= delta
	if _banner_cd <= 0.0:
		_banner_cd = 0.2
		_update_banner()
	if _time_left <= 0.0:
		_finished = true
		lose_match("Time's up — the paper plane race slipped away.")

func _on_player_died() -> void:
	if not _match_over:
		lose_match("Crashed out of the race.")

func _on_arena_unit_died(_unit: Node) -> void:
	pass

func _update_banner() -> void:
	banner.text = "HOOP  %d / %d      TIME  %ds" % [mini(_next, HOOP_COUNT), HOOP_COUNT, maxi(0, ceili(_time_left))]
