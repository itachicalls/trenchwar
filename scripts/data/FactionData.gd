class_name FactionData
extends Resource
## A toy faction. Units read colors/stat multipliers from here, so adding a faction
## is a new .tres file plus (optionally) unique units and abilities.

@export var display_name: String = "Green Army"
@export var description: String = ""
@export var primary_color: Color = Color(0.35, 0.55, 0.25)
@export var secondary_color: Color = Color(0.2, 0.32, 0.15)
@export var accent_color: Color = Color(0.9, 0.85, 0.6)
@export var health_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0
@export_enum("green_army", "chrome_legion", "brick_kingdom", "wind_up_empire", "plush_alliance", "rc_syndicate") var id: String = "green_army"

## Godot collision layers used for team hit detection.
func hostile_to(other: FactionData) -> bool:
	return other != null and other.id != id
