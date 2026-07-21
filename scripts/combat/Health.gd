class_name Health
extends Node
## Reusable health component. Attach to anything that can take damage:
## soldiers, tanks, drop pods, base structures, furniture forts.

signal changed(current: float, maximum: float)
signal died(attacker: Node)

@export var max_health: float = 100.0
var current: float
var dead: bool = false

func _ready() -> void:
	current = max_health

func setup(maximum: float) -> void:
	max_health = maximum
	current = maximum
	dead = false
	changed.emit(current, max_health)

func damage(amount: float, attacker: Node = null) -> void:
	if dead:
		return
	current = maxf(current - amount, 0.0)
	changed.emit(current, max_health)
	if current <= 0.0:
		dead = true
		died.emit(attacker)

func heal(amount: float) -> void:
	if dead:
		return
	current = minf(current + amount, max_health)
	changed.emit(current, max_health)

func ratio() -> float:
	return current / max_health if max_health > 0.0 else 0.0
