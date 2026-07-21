class_name WeaponData
extends Resource
## Data definition for any weapon: infantry toys, tank cannons, turrets.
## New weapons are new .tres files in res://data/weapons — no code required.

@export var display_name: String = "Plastic Rifle"
@export var damage: float = 12.0
@export var fire_rate: float = 7.0            ## shots per second
@export var magazine_size: int = 24
@export var reload_time: float = 1.4
@export var projectile_speed: float = 55.0
@export var projectile_scale: float = 1.0
@export var spread_degrees: float = 1.2
@export var automatic: bool = true
@export var pellets: int = 1                  ## >1 for scatter weapons
@export var projectile_color: Color = Color(1.0, 0.85, 0.3)
@export var sound: String = "shoot"           ## Sfx stream name
@export var explosive_radius: float = 0.0     ## >0 = splash damage
@export var recoil: float = 1.0               ## camera kick multiplier
@export var knockback: float = 0.0            ## shove victims back (units/sec)
@export var pierce: int = 0                   ## extra bodies a shot drills through
