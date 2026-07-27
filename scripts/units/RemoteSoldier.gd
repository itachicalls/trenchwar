class_name RemoteSoldier
extends CharacterBody3D
## Networked puppet for a remote human peer. Pose, health and gunfire all
## arrive from that peer's machine; local hits are forwarded back to them
## via Net.report_hit so the body's owner stays the authority on its own HP.

const SNAP_DISTANCE := 6.0        # teleport instead of sliding across the map
const EXTRAPOLATE_MAX := 0.2      # seconds of dead reckoning between packets
const SMOOTHING := 16.0

var peer_id: int = 0
var faction: FactionData
var display_name: String = "Soldier"
var health: Health
var body_rig: Node3D
var health_bar: HealthBar3D
var muzzle: Node3D

var _label: Label3D
var _yaw := 0.0
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _pose_age := 0.0
var _have_pose := false
var _anim: AnimationPlayer
var _last_weapon_path := ""
var _last_weapon: WeaponData = null

func _ready() -> void:
	collision_layer = 0b0010
	collision_mask = 0b0111
	add_to_group("net_players")
	add_to_group("combat_bots")  # aim-assist / hostility scans pick us up
	if faction == null:
		faction = load("res://data/factions/green_army.tres")
	add_to_group("team_" + faction.id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	shape.shape = capsule
	shape.position.y = 0.7
	add_child(shape)
	body_rig = ModelLib.build_character(faction, faction.id == "chrome_legion", "AK")
	add_child(body_rig)
	if body_rig.has_meta("anim"):
		_anim = body_rig.get_meta("anim")
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -0.45)
	var mount := body_rig.get_node_or_null("WeaponMount")
	if mount != null:
		mount.add_child(muzzle)
	else:
		muzzle.position = Vector3(0, 1.35, -0.45)
		add_child(muzzle)
	health = Health.new()
	health.setup(200.0 * faction.health_multiplier)
	add_child(health)
	health_bar = HealthBar3D.new()
	health_bar.position.y = 1.95
	add_child(health_bar)
	health.changed.connect(func(c, m): health_bar.update_ratio(c / m))
	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 48
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.3
	_label.modulate = faction.primary_color
	add_child(_label)
	_net_pos = global_position

## Packets arrive a few times a second at best on a phone link, so the puppet
## dead-reckons along its last known velocity and eases onto each new pose
## instead of snapping — a teleporting enemy is impossible to aim at.
func _physics_process(delta: float) -> void:
	if not _have_pose:
		return
	_pose_age += delta
	var target := _net_pos + _net_vel * minf(_pose_age, EXTRAPOLATE_MAX)
	if global_position.distance_to(target) > SNAP_DISTANCE:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-SMOOTHING * delta))
	if body_rig != null:
		body_rig.rotation.y = lerp_angle(body_rig.rotation.y, _yaw, minf(SMOOTHING * delta, 1.0))
	_animate(Vector2(_net_vel.x, _net_vel.z).length() > 1.0)

func _animate(moving: bool) -> void:
	if _anim == null:
		return
	var want := "Run_Gun" if moving else "Idle"
	if _anim.has_animation(want) and _anim.current_animation != want:
		_anim.play(want, 0.25)

func apply_net_pose(pos: Vector3, yaw: float, vel: Vector3) -> void:
	if not _have_pose:
		global_position = pos
	_net_pos = pos
	_net_vel = vel
	_yaw = yaw
	velocity = vel
	_pose_age = 0.0
	_have_pose = true

func apply_net_health(hp: float, max_hp: float) -> void:
	if health == null:
		return
	if not is_equal_approx(health.max_health, max_hp):
		health.max_health = max_hp
	health.current = clampf(hp, 0.0, max_hp)
	# Stop bots and aim-assist locking a corpse in the gap before the down RPC.
	health.dead = health.current <= 0.0
	health_bar.update_ratio(health.current / maxf(max_hp, 1.0))

## Replay of a shot the remote peer actually took: muzzle flash, sound and a
## tracer that can't hurt anyone (their client already reported the damage).
func fire_visual(origin: Vector3, dir: Vector3, weapon_path: String) -> void:
	var wd := _weapon_for(weapon_path)
	if wd == null:
		return
	if dir.length_squared() < 0.0001:
		return
	Projectile.spawn_cosmetic(self, origin, dir.normalized(), wd, self, faction)
	if muzzle != null:
		Fx.muzzle_flash(muzzle, wd.projectile_color, 0.7 + wd.recoil * 0.45)
	Sfx.play_at(wd.sound, origin, -6.0)

func _weapon_for(weapon_path: String) -> WeaponData:
	if weapon_path == _last_weapon_path and _last_weapon != null:
		return _last_weapon
	if weapon_path == "" or not ResourceLoader.exists(weapon_path):
		weapon_path = "res://data/weapons/plastic_rifle.tres"
	var wd := load(weapon_path) as WeaponData
	if wd == null:
		return _last_weapon
	_last_weapon_path = weapon_path
	_last_weapon = wd
	return wd

func take_damage(amount: float, attacker: Node = null) -> void:
	Fx.impact(self, global_position + Vector3.UP, faction.primary_color)
	# Authority of HP is the remote peer's Player — we only forward the hit.
	# Resolve via /root so this class_name script doesn't depend on autoload
	# parse order (Net is registered after global classes are scanned).
	var net := get_node_or_null("/root/Net")
	if net != null and net.get("is_online"):
		net.report_hit(peer_id, amount)
	else:
		apply_damage_visual(amount)

## Local echo of a hit so the bar reacts on the same frame as the impact. It
## can never finish the puppet off: only the owner's health packet or their
## down RPC decides that, otherwise a player with health upgrades would look
## dead over here while still fighting on their own screen.
func apply_damage_visual(amount: float) -> void:
	if health == null:
		return
	health.current = maxf(health.current - amount, 1.0)
	health_bar.update_ratio(health.current / maxf(health.max_health, 1.0))

func is_dead() -> bool:
	return health.dead
