class_name RemoteBot
extends CharacterBody3D
## Client-side puppet for a server-authoritative CombatBot.

var bot_id: int = 0
var faction: FactionData
var variant: String = "trooper"
var body_rig: Node3D
var _yaw := 0.0
var _dead := false

func _ready() -> void:
	collision_layer = 0b0010
	collision_mask = 0b0111
	add_to_group("combat_bots")
	add_to_group("net_bots")
	if faction == null:
		faction = load("res://data/factions/chrome_legion.tres")
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

func apply_net_pose(pos: Vector3, yaw: float) -> void:
	global_position = global_position.lerp(pos, 0.55)
	_yaw = yaw
	if body_rig != null:
		body_rig.rotation.y = yaw

func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead:
		return
	Fx.impact(self, global_position + Vector3.UP, faction.primary_color)
	var net := get_node_or_null("/root/Net")
	if net != null and net.get("is_online"):
		net.report_bot_hit(bot_id, amount)

func is_dead() -> bool:
	return _dead

func mark_dead() -> void:
	_dead = true
	Events.unit_died.emit(self)
	Fx.plastic_shatter(self, global_position + Vector3.UP * 0.7, faction.primary_color)
	queue_free()
