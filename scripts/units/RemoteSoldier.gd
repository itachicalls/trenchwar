class_name RemoteSoldier
extends CharacterBody3D
## Networked puppet for a remote human peer. Pose comes from Net RPCs;
## local hits forward damage to the victim peer via Net.report_hit.

var peer_id: int = 0
var faction: FactionData
var display_name: String = "Soldier"
var health: Health
var body_rig: Node3D
var _label: Label3D
var _yaw := 0.0

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
	health = Health.new()
	health.setup(200.0 * faction.health_multiplier)
	add_child(health)
	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 48
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.3
	_label.modulate = faction.primary_color
	add_child(_label)

func apply_net_pose(pos: Vector3, yaw: float, vel: Vector3) -> void:
	global_position = pos
	_yaw = yaw
	velocity = vel
	if body_rig != null:
		body_rig.rotation.y = yaw

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

func apply_damage_visual(amount: float) -> void:
	health.damage(amount, null)

func is_dead() -> bool:
	return health.dead
