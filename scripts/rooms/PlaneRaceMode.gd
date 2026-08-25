class_name PlaneRaceMode
extends ArenaBase
## PAPER PLANE RACE — bright backyard sky circuit. Wide glowing arches, fair
## flight model, readable next-gate beacons. Built as an arcade attraction,
## not a punishment simulator.

const TIME_LIMIT := 120.0
const HOOP_COUNT := 8
const COUNTDOWN := 3.0

var _plane: PaperPlane
var _hoops: Array[Area3D] = []
var _next := 0
var _time_left := TIME_LIMIT
var _started := false
var _finished := false
var _banner_cd := 0.0
var _guide: MeshInstance3D
var _countdown := COUNTDOWN
var _racing := false
var _beacon: OmniLight3D
var _hud_arrow: Label
var _hud_dist: Label
var _race_layer: CanvasLayer

func _init() -> void:
	arena_half = 62.0

## Bright daytime sky — overrides ArenaBase night lighting.
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.48, 0.68, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.88, 0.9, 0.98)
	env.ambient_light_energy = 1.05 if Game.low_gfx() else 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.2
	env.glow_enabled = not Game.low_gfx()
	env.glow_intensity = 0.55
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.84, 0.95)
	env.fog_density = 0.0004
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.82)
	sun.light_energy = 1.7 if Game.low_gfx() else 1.45
	sun.shadow_enabled = not Game.low_gfx()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.72, 1.0)
	fill.light_energy = 0.65
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-22, 145, 0)
	add_child(fill)
	# Dust / pollen in the sun — Operation Chrome "alive toybox" atmosphere.
	add_dust_motes(Vector3(0, 14, 0), Vector3(arena_half * 0.7, 10, arena_half * 0.7),
		36 if Game.low_gfx() else 55, Color(0.95, 0.9, 0.7))

func _build_arena() -> void:
	var s := arena_half
	var sand := ToyMaterials.carpet(Color(0.74, 0.64, 0.44))
	var wood := ToyMaterials.plank_floor(Color(0.55, 0.4, 0.26))
	_static_box(Vector3(0, -0.5, 0), Vector3(s * 2 + 16, 1.0, s * 2 + 16), sand)
	for spec in [
		[Vector3(0, 1.6, -s - 3), Vector3(s * 2 + 16, 3.2, 5)],
		[Vector3(0, 1.6, s + 3), Vector3(s * 2 + 16, 3.2, 5)],
		[Vector3(-s - 3, 1.6, 0), Vector3(5, 3.2, s * 2 + 16)],
		[Vector3(s + 3, 1.6, 0), Vector3(5, 3.2, s * 2 + 16)],
	]:
		_static_box(spec[0], spec[1], wood)
	# Center landmark — flag + colored toy crates (readable from altitude).
	_static_box(Vector3(0, 0.7, 0), Vector3(14, 1.4, 14),
		ToyMaterials.carpet(Color(0.62, 0.52, 0.34)), true)
	_static_cylinder(Vector3(0, 7, 0), 0.35, 12.0,
		ToyMaterials.plastic(Color(0.95, 0.55, 0.2), 0.3))
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(3.2, 1.8, 0.12)
	flag.mesh = fm
	flag.material_override = ToyMaterials.glow(Color(0.35, 0.85, 0.45), 1.2)
	flag.position = Vector3(1.6, 12.2, 0)
	add_child(flag)
	# Oversized toy blocks on the perimeter — spectacle, collide=false on tall ones.
	for spec2 in [
		[Vector3(38, 3, -34), Vector3(8, 6, 8), Color(0.9, 0.25, 0.25)],
		[Vector3(-36, 3.5, 30), Vector3(7, 7, 7), Color(0.25, 0.45, 0.95)],
		[Vector3(30, 2.5, 36), Vector3(9, 5, 6), Color(0.95, 0.85, 0.2)],
		[Vector3(-40, 2.5, -28), Vector3(6, 5, 10), Color(0.3, 0.75, 0.4)],
	]:
		_static_box(spec2[0], spec2[1], ToyMaterials.plastic(spec2[2], 0.4))

func _setup_mode() -> void:
	Missions.start_mission("PAPER PLANE RACE")
	_build_course()
	_build_race_hud()
	var lane := 0
	if Net.is_online:
		var ids: Array = Net.peers.keys()
		ids.sort()
		lane = ids.find(Net.my_id())
		if lane < 0:
			lane = 0
		Net.race_won.connect(_on_net_race_won)
	var start := Vector3(-arena_half + 14, 12, float(lane) * 7.0 - 3.5)
	_plane = spawn_plane(start, 90.0)
	_plane.lock_bail = true
	var pad := start + Vector3(0, -10, 0)
	var player: Player = null
	if Net.is_dedicated:
		spawn_online_humans({
			"green_army": pad, "chrome_legion": pad,
			"brick_kingdom": pad, "wind_up_empire": pad,
		})
		if is_instance_valid(_plane):
			_plane.queue_free()
		_plane = null
	elif Net.is_online:
		player = spawn_online_humans({
			"green_army": pad, "chrome_legion": pad,
			"brick_kingdom": pad, "wind_up_empire": pad,
		})
		if player != null:
			_plane.call_deferred("force_board", player)
	else:
		player = spawn_player(pad + Vector3(0, 0, 4))
		_plane.call_deferred("force_board", player)
	_started = not Net.is_dedicated
	_racing = false
	_countdown = COUNTDOWN
	_update_banner()
	sub_banner.text = ("ONLINE RACE  •  FIRST THROUGH ALL GATES WINS" if Net.is_online
		else "THREAD THE GREEN GATE  •  W THROTTLE  •  A/D TURN  •  MOUSE PITCH")
	Events.notify.emit("AIR RACE — get ready. Wide gates, bright sky. Follow the green arch!")

func _build_race_hud() -> void:
	_race_layer = CanvasLayer.new()
	_race_layer.layer = 8
	add_child(_race_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_layer.add_child(root)
	_hud_arrow = Label.new()
	_hud_arrow.text = "▲"
	_hud_arrow.add_theme_font_size_override("font_size", 48)
	_hud_arrow.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	_hud_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud_arrow.add_theme_constant_override("outline_size", 8)
	_hud_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_arrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud_arrow.position = Vector2(-40, 90)
	_hud_arrow.size = Vector2(80, 60)
	_hud_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud_arrow)
	_hud_dist = Label.new()
	_hud_dist.add_theme_font_size_override("font_size", 22)
	_hud_dist.add_theme_color_override("font_color", Color(0.9, 0.95, 0.85))
	_hud_dist.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud_dist.add_theme_constant_override("outline_size", 6)
	_hud_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_dist.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud_dist.position = Vector2(-80, 140)
	_hud_dist.size = Vector2(160, 32)
	_hud_dist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud_dist)

func _on_net_race_won(peer_id: int) -> void:
	if _match_over:
		return
	_finished = true
	if peer_id == Net.my_id():
		var bonus := maxi(0, int(_time_left) * 2)
		Game.coins += 25 + bonus
		Events.coins_changed.emit(Game.coins)
		win_match("AIR RACE WIN  +%d COINS" % (25 + bonus))
	else:
		lose_match("%s finished the circuit first." % Net.name_for_peer(peer_id))

func _build_course() -> void:
	add_prop("crate", Vector3(18, 0, -26), 20.0, 3.4)
	add_prop("crate", Vector3(-22, 0, 24), -35.0, 3.2)
	add_prop("pallet", Vector3(28, 0, 10), 40.0, 3.6)
	add_prop("cone", Vector3(-arena_half + 20, 0, -6), 0.0, 1.6)
	add_prop("cone", Vector3(-arena_half + 20, 0, 6), 0.0, 1.6)
	add_prop("tree_2", Vector3(36, 0, 26), 15.0, 10.0, false)
	add_prop("tree_3", Vector3(-34, 0, -28), -25.0, 9.0, false)
	add_prop("tree_1", Vector3(10, 0, 38), 50.0, 8.0, false)
	# High oval — every gate stays well above the sand cushion.
	for i in HOOP_COUNT:
		var t := float(i) / float(HOOP_COUNT)
		var ang := t * TAU - PI * 0.5
		var r := arena_half * 0.58
		# Height 11–16: no ground-skimming dives.
		var height := 13.0 + sin(t * TAU * 2.0) * 2.5 + (1.5 if i % 2 == 0 else 0.0)
		var pos := Vector3(cos(ang) * r, height, sin(ang) * r)
		var yaw := rad_to_deg(ang + PI * 0.5)
		_hoops.append(_make_hoop(pos, yaw, i))
	_guide = MeshInstance3D.new()
	var arrow := PrismMesh.new()
	arrow.size = Vector3(2.0, 0.5, 2.8)
	_guide.mesh = arrow
	_guide.material_override = ToyMaterials.glow(Color(0.35, 1.0, 0.55), 2.0)
	add_child(_guide)
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(0.4, 1.0, 0.55)
	_beacon.light_energy = 4.5
	_beacon.omni_range = 28.0
	_beacon.shadow_enabled = false
	add_child(_beacon)
	_highlight_next()

## Wide arch gate — tire ring + tall uprights with a big clear tunnel.
func _make_hoop(pos: Vector3, yaw_deg: float, index: int) -> Area3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	add_child(root)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.22
		pm.bottom_radius = 0.28
		pm.height = 7.0
		post.mesh = pm
		post.material_override = ToyMaterials.plastic(Color(0.95, 0.82, 0.25), 0.35)
		post.position = Vector3(side * 3.6, 0, 0)
		root.add_child(post)
	# Crossbar.
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(7.4, 0.35, 0.35)
	bar.mesh = bm
	bar.material_override = ToyMaterials.plastic(Color(0.95, 0.82, 0.25), 0.35)
	bar.position = Vector3(0, 3.4, 0)
	root.add_child(bar)
	var tire := ModelLib.build_prop("tires", 7.2)
	if tire != null:
		tire.rotation_degrees.x = 90.0
		root.add_child(tire)
	else:
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 3.3
		cm.bottom_radius = 3.3
		cm.height = 0.55
		ring.mesh = cm
		ring.rotation_degrees.x = 90.0
		ring.material_override = ToyMaterials.plastic(Color(0.15, 0.15, 0.18), 0.45)
		root.add_child(ring)
	var glow := MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = 2.9
	gm.outer_radius = 3.5
	gm.rings = 12 if Game.low_gfx() else 20
	gm.ring_segments = 6
	glow.mesh = gm
	glow.rotation_degrees.x = 90.0
	glow.material_override = ToyMaterials.plastic(Color(0.4, 0.85, 1.0), 0.35)
	glow.name = "Glow"
	root.add_child(glow)
	var num := Label3D.new()
	num.text = str(index + 1)
	num.font_size = 110
	num.pixel_size = 0.028
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.modulate = Color(1, 1, 1)
	num.outline_size = 18
	num.position = Vector3(0, 4.6, 0)
	num.name = "Num"
	root.add_child(num)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 0b0100
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 4.4
	cs.shape = sphere
	area.add_child(cs)
	area.set_meta("index", index)
	area.body_entered.connect(_on_hoop_body.bind(area))
	root.add_child(area)
	return area

func _on_hoop_body(body: Node, area: Area3D) -> void:
	if _finished or not _racing or not (body is PaperPlane):
		return
	var idx: int = int(area.get_meta("index", -1))
	if idx != _next:
		return
	_next += 1
	Sfx.play("objective", -2.0)
	Fx.ring_pulse(self, area.global_position, Color(0.4, 1.0, 0.55), 7.0, 0.5)
	Fx.shake_camera(self, 0.18)
	# Coin sparkle burst for that Operation Chrome collectible read.
	for i in 5:
		var jitter := Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.5), randf_range(-1.5, 1.5))
		Pickup.spawn_coin(self, area.global_position + jitter, 1)
	Events.notify.emit("GATE %d / %d  CLEARED" % [_next, HOOP_COUNT])
	if _next >= HOOP_COUNT:
		_finished = true
		Fx.ordnance_explosion(self, area.global_position, 4.0)
		Fx.shake_camera(self, 0.55)
		if Net.is_online:
			Net.report_race_finish()
		else:
			var bonus := maxi(0, int(_time_left) * 2)
			Game.coins += 25 + bonus
			Events.coins_changed.emit(Game.coins)
			win_match("AIR RACE CLEARED  +%d COINS" % (25 + bonus))
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
			glow.material_override = ToyMaterials.glow(Color(0.3, 1.0, 0.5), 2.8 if not Game.low_gfx() else 1.6)
			glow.visible = true
			if num:
				num.modulate = Color(0.4, 1.0, 0.55)
		elif i < _next:
			glow.visible = false
			if num:
				num.modulate = Color(0.45, 0.45, 0.45, 0.4)
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
		if _beacon:
			_beacon.visible = false
		return
	_guide.visible = true
	if _beacon:
		_beacon.visible = true
	var target: Vector3 = _hoops[_next].global_position
	_guide.global_position = target + Vector3(0, 5.5, 0)
	_guide.rotate_y(0.03)
	if _beacon:
		_beacon.global_position = target
		_beacon.light_energy = 3.5 + sin(Time.get_ticks_msec() * 0.006) * 1.2
	if _plane != null and is_instance_valid(_plane):
		var from := _plane.global_position
		var flat := Vector3(target.x - from.x, 0, target.z - from.z)
		if flat.length_squared() > 0.01:
			_guide.look_at(_guide.global_position + flat.normalized(), Vector3.UP)

func _update_race_hud() -> void:
	if _hud_arrow == null or _next >= _hoops.size() or _plane == null or not is_instance_valid(_plane):
		if _hud_arrow:
			_hud_arrow.visible = _racing and not _finished
		return
	_hud_arrow.visible = _racing and not _finished
	_hud_dist.visible = _hud_arrow.visible
	var target: Vector3 = _hoops[_next].global_position
	var to := target - _plane.global_position
	var dist := to.length()
	_hud_dist.text = "%dm  →  GATE %d" % [int(dist), _next + 1]
	# Screen-space hint: arrow color warms when you're lined up.
	var fwd := -_plane.global_transform.basis.z
	fwd.y = 0.0
	var flat := to
	flat.y = 0.0
	if fwd.length_squared() > 0.01 and flat.length_squared() > 0.01:
		var align := fwd.normalized().dot(flat.normalized())
		_hud_arrow.modulate = Color(0.4, 1.0, 0.55).lerp(Color(1.0, 0.9, 0.3), clampf(1.0 - align, 0.0, 1.0))

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing() or not _started or _finished:
		return
	if _plane != null and not is_instance_valid(_plane):
		_finished = true
		lose_match("Paper plane shredded — race over.")
		return
	# Countdown before the clock starts — practice loft to feel the stick.
	if not _racing:
		_countdown -= delta
		banner.text = "GET READY  %d" % maxi(1, ceili(_countdown))
		if _countdown <= 0.0:
			_racing = true
			Sfx.play("objective", -2.0)
			Events.notify.emit("GO!  Thread the green gate!")
		_update_guide()
		return
	_update_guide()
	_update_race_hud()
	_time_left -= delta
	_banner_cd -= delta
	if _banner_cd <= 0.0:
		_banner_cd = 0.15
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
	var spd := 0
	var stall := ""
	if _plane != null and is_instance_valid(_plane):
		spd = int((_plane.speed() / 28.0) * 100.0)
		if _plane.stalling():
			stall = "  ·  STALL"
	banner.text = "GATE  %d / %d      TIME  %ds      SPD  %d%%%s" % [
		mini(_next, HOOP_COUNT), HOOP_COUNT, maxi(0, ceili(_time_left)), spd, stall]
