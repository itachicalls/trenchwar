extends Node
## Global game state: input registration, resources, player reference, pause and flow.

enum State { MENU, PLAYING, PAUSED, VICTORY, DEFEAT }

var state: State = State.MENU
var player: Node = null
var plastic_parts: int = 0:
	set(value):
		plastic_parts = value
		Events.parts_changed.emit(plastic_parts)

## Squad roster persists between missions later; for now runtime-only.
var squad: Array[Node] = []
var kills: int = 0

## Set by arena game modes: player death triggers a mode respawn instead of
## the campaign defeat screen.
var mode_respawns: bool = false

## Coins persist across missions and sessions — the store currency.
var coins: int = 0:
	set(value):
		coins = value
		Events.coins_changed.emit(coins)

## Purchased upgrade levels (persisted). Applied when the player spawns.
var upgrades := {"health": 0, "damage": 0, "reload": 0, "speed": 0}

## Soldier appearance variants. Tint multiplies the base mold color, so each
## skin reads as a different plastic batch off the same production line.
const SKINS := [
	{"id": "classic", "name": "CLASSIC GREEN", "desc": "The original 1962 mold.", "tint": Color(1, 1, 1), "cost": 0},
	{"id": "desert", "name": "DESERT RAT", "desc": "Sandbox campaign veteran.", "tint": Color(1.25, 0.92, 0.62), "cost": 150},
	{"id": "arctic", "name": "ARCTIC FOX", "desc": "Freezer-aisle special forces.", "tint": Color(1.2, 1.18, 1.35), "cost": 150},
	{"id": "navy", "name": "NAVY BLUE", "desc": "Bathtub fleet marine.", "tint": Color(0.5, 0.72, 1.45), "cost": 250},
	{"id": "crimson", "name": "CRIMSON GUARD", "desc": "Limited holiday-edition plastic.", "tint": Color(1.55, 0.5, 0.55), "cost": 250},
	{"id": "shadow", "name": "SHADOW OPS", "desc": "Molded from under-the-bed darkness.", "tint": Color(0.42, 0.45, 0.5), "cost": 400},
	{"id": "gold", "name": "GOLDEN COMMANDO", "desc": "The trophy-shelf legend himself.", "tint": Color(1.6, 1.25, 0.4), "cost": 600},
]
var selected_skin: String = "classic"
var unlocked_skins: Array = ["classic"]

func skin_data(id: String) -> Dictionary:
	for s in SKINS:
		if s.id == id:
			return s
	return SKINS[0]

## Player weapon catalog: buy in the Armory, equip one as your loadout.
## "gun" is the in-hand prop name on the character model.
const WEAPONS := [
	{"id": "rifle", "name": "PLASTIC RIFLE", "desc": "Trusty full-auto. Does everything well.",
		"path": "res://data/weapons/plastic_rifle.tres", "gun": "AK", "cost": 0},
	{"id": "repeater", "name": "RUBBER BAND REPEATER", "desc": "Hard-hitting snap shots. Satisfying twang.",
		"path": "res://data/weapons/rubber_band_repeater.tres", "gun": "Revolver", "cost": 250},
	{"id": "scatter", "name": "NERF SCATTERGUN", "desc": "Five foam pellets. King of close quarters.",
		"path": "res://data/weapons/nerf_scatter.tres", "gun": "Shotgun", "cost": 350},
	{"id": "soaker", "name": "SUPER SOAKER XL", "desc": "A firehose of water beads. Never stops.",
		"path": "res://data/weapons/super_soaker.tres", "gun": "SMG", "cost": 400},
	{"id": "sniper", "name": "DART SNIPER", "desc": "One dart, one toy. Cross-room deletion.",
		"path": "res://data/weapons/dart_sniper.tres", "gun": "Sniper", "cost": 550},
	{"id": "marble", "name": "MARBLE CANNON", "desc": "Explosive glass marbles. Splash damage.",
		"path": "res://data/weapons/marble_cannon.tres", "gun": "GrenadeLauncher", "cost": 800},
]
var selected_weapon: String = "rifle"
var owned_weapons: Array = ["rifle"]

func weapon_info(id: String) -> Dictionary:
	for w in WEAPONS:
		if w.id == id:
			return w
	return WEAPONS[0]

const SAVE_PATH := "user://carpetstorm.cfg"

func _ready() -> void:
	_register_inputs()
	_load_progress()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.player_spawned.connect(func(p): player = p)
	Events.player_died.connect(func(): player = null)
	Events.unit_died.connect(_on_unit_died)

func _on_unit_died(unit: Node) -> void:
	if unit.is_in_group("enemies"):
		kills += 1
	if unit in squad:
		squad.erase(unit)
		Events.squad_changed.emit(squad)

func add_squad_member(unit: Node) -> void:
	if unit not in squad:
		squad.append(unit)
		Events.squad_changed.emit(squad)

func capture_mouse() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func capture_mouse_on_web() -> void:
	# Browsers only allow pointer lock after a user click — skip auto-capture on web.
	if not OS.has_feature("web"):
		capture_mouse()

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func is_playing() -> bool:
	return state == State.PLAYING and not get_tree().paused

func save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "coins", coins)
	cf.set_value("save", "upgrades", upgrades)
	cf.set_value("save", "selected_skin", selected_skin)
	cf.set_value("save", "unlocked_skins", unlocked_skins)
	cf.set_value("save", "selected_weapon", selected_weapon)
	cf.set_value("save", "owned_weapons", owned_weapons)
	cf.save(SAVE_PATH)

func _load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	coins = cf.get_value("save", "coins", 0)
	var saved: Dictionary = cf.get_value("save", "upgrades", {})
	for k in upgrades.keys():
		upgrades[k] = int(saved.get(k, 0))
	selected_skin = cf.get_value("save", "selected_skin", "classic")
	unlocked_skins = cf.get_value("save", "unlocked_skins", ["classic"])
	selected_weapon = cf.get_value("save", "selected_weapon", "rifle")
	owned_weapons = cf.get_value("save", "owned_weapons", ["rifle"])

# -------------------------------------------------------------------------
# Input map (registered in code so the project is self-documenting and the
# bindings live next to the gameplay code that uses them).
# -------------------------------------------------------------------------
func _register_inputs() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("reload", KEY_R)
	_key("interact", KEY_E)
	_key("cmd_follow", KEY_1)
	_key("cmd_hold", KEY_2)
	_key("cmd_charge", KEY_3)
	_key("pause", KEY_ESCAPE)
	# P as backup pause: browsers swallow ESC for pointer-lock exit.
	var p_ev := InputEventKey.new()
	p_ev.physical_keycode = KEY_P
	InputMap.action_add_event("pause", p_ev)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)

func _key(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
