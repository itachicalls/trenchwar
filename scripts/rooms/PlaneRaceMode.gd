class_name PlaneRaceMode
extends ArenaBase
## PAPER PLANE RACE — fly through tire/pipe hoops before the timer runs out.
## Premade props form the course; hoops are Area3D rings (not solid air walls).

const TIME_LIMIT := 95.0
const HOOP_COUNT := 8

var _plane: PaperPlane
var _hoops: Array[Area3D] = []
var _next := 0
var _time_left := TIME_LIMIT
var _started := false
var _finished := false
var _banner_cd := 0.0

func _init() -> void:
	arena_half = 60.0

func _setup_mode() -> void:
	Missions.start_mission("PAPER PLANE RACE")
	_build_course()
	_plane = spawn_plane(Vector3(-arena_half + 10, 6, 0), 90.0)
	_plane.lock_bail = true
	var player := spawn_player(Vector3(-arena_half + 10, 1, 4))
	_plane.call_deferred("force_board", player)
	_started = true
	_update_banner()
	sub_banner.text = "FLY THROUGH THE HOOPS  •  W/S THROTTLE"
	Events.notify.emit("AIR RACE: thread the glowing hoops in order. Stay airborne — no bailouts!")

func _build_course() -> void:
	# Obstacle islands between hoops (solid props — landable, height-matched colliders).
	add_prop("crate", Vector3(8, 0, -18), 25.0, 3.5)
	add_prop("crate", Vector3(-12, 0, 22), -40.0, 3.2)
	add_prop("barrier_large", Vector3(0, 0, 0), 0.0, 6.0)
	add_prop("pallet", Vector3(22, 0, 10), 50.0, 3.8)
	add_prop("woodplanks", Vector3(-20, 0, -8), 15.0, 4.2)
	add_prop("pipes", Vector3(16, 0, -22), -30.0, 5.0)
	add_prop("cone", Vector3(-arena_half + 16, 0, -6), 0.0, 1.6)
	add_prop("cone", Vector3(-arena_half + 16, 0, 6), 0.0, 1.6)
	# Visual trees only — no tall invisible trunks choking the flight lane.
	add_prop("tree_2", Vector3(28, 0, 18), 20.0, 9.0, false)
	add_prop("tree_3", Vector3(-26, 0, -20), -40.0, 8.5, false)
	for i in HOOP_COUNT:
		var t := float(i) / float(HOOP_COUNT - 1)
		var ang := lerpf(-0.35, PI * 1.35, t)
		var r := lerpf(arena_half * 0.25, arena_half * 0.7, sin(t * PI))
		var pos := Vector3(cos(ang) * r, lerpf(7.0, 14.0, absf(sin(t * TAU))), sin(ang) * r)
		var yaw := rad_to_deg(ang) + 90.0
		_hoops.append(_make_hoop(pos, yaw, i))
	_highlight_next()

## Visual ring from tire/pipe props + pass-through Area3D (no solid blocker).
func _make_hoop(pos: Vector3, yaw_deg: float, index: int) -> Area3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	add_child(root)
	# Premade tire as the hoop silhouette (visual only — no prop collider).
	var tire := ModelLib.build_prop("tires", 5.5)
	if tire != null:
		tire.rotation_degrees.x = 90.0
		root.add_child(tire)
	else:
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.6
		cm.bottom_radius = 2.6
		cm.height = 0.55
		ring.mesh = cm
		ring.rotation_degrees.x = 90.0
		ring.material_override = ToyMaterials.plastic(Color(0.2, 0.2, 0.22), 0.5)
		root.add_child(ring)
	# Marker rim — glow only applied to the active gate (cheaper on web).
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 2.9
	gm.bottom_radius = 2.9
	gm.height = 0.15
	glow.mesh = gm
	glow.rotation_degrees.x = 90.0
	glow.material_override = ToyMaterials.plastic(Color(0.35, 0.75, 1.0), 0.4)
	glow.name = "Glow"
	root.add_child(glow)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 0b0100   # vehicles (plane)
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.2
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
	if not Game.low_gfx():
		Fx.ring_pulse(self, area.global_position, Color(0.4, 1.0, 0.9), 4.0, 0.5)
	Events.notify.emit("HOOP %d / %d" % [_next, HOOP_COUNT])
	if _next >= HOOP_COUNT:
		_finished = true
		var bonus := maxi(0, int(_time_left) * 2)
		Game.coins += 15 + bonus
		Events.coins_changed.emit(Game.coins)
		win_match("AIR RACE CLEARED  +%d COINS" % (15 + bonus))
	else:
		_highlight_next()
	_update_banner()

func _highlight_next() -> void:
	for i in _hoops.size():
		var area := _hoops[i]
		var glow: MeshInstance3D = area.get_parent().get_node_or_null("Glow")
		if glow == null:
			continue
		if i == _next:
			glow.material_override = ToyMaterials.glow(Color(0.3, 1.0, 0.55), 2.2 if not Game.low_gfx() else 1.2)
			glow.visible = true
		elif i < _next:
			glow.visible = false
		else:
			# Upcoming gates: cheap plastic, no emissive stack.
			glow.material_override = ToyMaterials.plastic(Color(0.4, 0.7, 0.9), 0.45)
			glow.visible = true

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing() or not _started or _finished:
		return
	# Plane destroyed mid-race → fail cleanly (bail is locked).
	if _plane != null and not is_instance_valid(_plane):
		_finished = true
		lose_match("Paper plane shredded — race over.")
		return
	_time_left -= delta
	_banner_cd -= delta
	if _banner_cd <= 0.0:
		_banner_cd = 0.25
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
