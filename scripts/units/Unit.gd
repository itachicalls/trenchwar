class_name Unit
extends CharacterBody3D
## Base class for every living toy: player, squadmates, enemies.
## Composition: Health component + Weapon component + faction-colored body rig.

@export var faction: FactionData
@export var base_health: float = 100.0
@export var move_speed: float = 6.0
@export var weapon_data: WeaponData

var health: Health
var weapon: Weapon
var body_rig: Node3D
var health_bar: HealthBar3D
var _anim: AnimationPlayer

func _ready() -> void:
	collision_layer = 0b0010
	collision_mask = 0b0111
	if faction == null:
		faction = load("res://data/factions/green_army.tres")

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	shape.shape = capsule
	shape.position.y = 0.7
	add_child(shape)

	var bp := _body_params()
	body_rig = ModelLib.build_character(faction, faction.id == "chrome_legion",
		bp.get("gun", ""), bp.get("tint", Color.WHITE), bp.get("scale", 1.0))
	add_child(body_rig)
	if body_rig.has_meta("anim"):
		_anim = body_rig.get_meta("anim")

	health = Health.new()
	health.setup(base_health * faction.health_multiplier)
	health.died.connect(_on_died)
	add_child(health)

	weapon = Weapon.new()
	weapon.data = weapon_data if weapon_data != null else load("res://data/weapons/plastic_rifle.tres")
	weapon.owner_unit = self
	weapon.faction = faction
	var mount := body_rig.get_node("WeaponMount")
	mount.add_child(weapon)

	# Floating health bar for AI units (the player has the HUD).
	if not self is Player:
		health_bar = HealthBar3D.new()
		health_bar.position.y = 1.85
		add_child(health_bar)
		health.changed.connect(func(c, m): health_bar.update_ratio(c / m))
	_unit_ready()

## Override point for subclasses (called after components exist).
func _unit_ready() -> void:
	pass

## Visual overrides for the body model: {gun, tint, scale}.
func _body_params() -> Dictionary:
	return {}

func take_damage(amount: float, attacker: Node = null) -> void:
	health.damage(amount * (attacker.faction.damage_multiplier if attacker is Unit and attacker.faction != null else 1.0), attacker)
	if not health.dead:
		_flinch()

func is_dead() -> bool:
	return health.dead

func heal(amount: float) -> void:
	health.heal(amount)

func _flinch() -> void:
	if body_rig == null:
		return
	var tween := create_tween()
	tween.tween_property(body_rig, "scale", Vector3(1.12, 0.9, 1.12), 0.05)
	tween.tween_property(body_rig, "scale", Vector3.ONE, 0.1)

func _on_died(attacker: Node) -> void:
	Fx.plastic_shatter(self, global_position + Vector3.UP * 0.7, faction.primary_color)
	Sfx.play_at("death", global_position)
	Events.unit_died.emit(self)
	_drop_loot()
	queue_free()

func _drop_loot() -> void:
	if not is_in_group("enemies"):
		return
	var scene := get_tree().current_scene
	if randf() < 0.6:
		Pickup.spawn_parts(scene, global_position, randi_range(2, 6))
	# Coins scatter from every kill — the store economy.
	for i in randi_range(1, 3):
		var jitter := Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		Pickup.spawn_coin(scene, global_position + jitter, 1)
	# Rare powerup drop: rapid fire / sugar rush / bubble shield.
	if randf() < 0.07:
		Pickup.spawn_powerup(scene, global_position + Vector3(0, 0, 0.5), Pickup.random_powerup())

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 24.0 * delta

## Locomotion animation. With an asset-pack rig this drives the real
## AnimationPlayer. NOTE: the pack's *_Shoot poses are deliberately unused —
## they blade the torso sideways, which made characters visibly face away
## from their own fire. Idle/Run_Gun keep the gun square with the aim.
var _waddle_time := 0.0
func animate_waddle(delta: float, moving: bool) -> void:
	if body_rig == null:
		return
	if _anim != null:
		play_anim("Run_Gun" if moving else "Idle")
		return
	if moving:
		_waddle_time += delta * 9.0
		body_rig.rotation.z = sin(_waddle_time) * 0.07
		body_rig.position.y = absf(sin(_waddle_time)) * 0.05
	else:
		body_rig.rotation.z = lerpf(body_rig.rotation.z, 0.0, 10.0 * delta)
		body_rig.position.y = lerpf(body_rig.position.y, 0.0, 10.0 * delta)

func play_anim(anim_name: String, blend: float = 0.25, speed: float = 1.0) -> void:
	if _anim != null and _anim.has_animation(anim_name) and _anim.current_animation != anim_name:
		_anim.play(anim_name, blend, speed)

## Turns only the body rig, never the CharacterBody3D node itself — the
## player's camera is a child of the node and must not inherit body turns.
func face_direction(dir: Vector3, delta: float, turn_speed: float = 10.0) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	var target_yaw := atan2(-dir.x, -dir.z) - rotation.y
	# Weight must clamp at 1: lerp_angle extrapolates past the target
	# otherwise, which read as "facing the wrong way" at high turn speeds.
	body_rig.rotation.y = lerp_angle(body_rig.rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

func aim_dir_at(target_pos: Vector3) -> Vector3:
	var from: Vector3 = weapon.muzzle.global_position if weapon != null else global_position + Vector3.UP
	return (target_pos - from).normalized()
