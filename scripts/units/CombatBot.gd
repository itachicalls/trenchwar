class_name CombatBot
extends EnemySoldier
## Arena-mode bot: EnemySoldier's brain, but team-agnostic. Fights for ANY
## faction against every hostile faction — the "fake players" of Skirmish and
## Battle Royale.

## Bots on green defend greens; chrome hunts greens. Used for ally alerts only.
var is_player_team: bool = false

func _unit_ready() -> void:
	super()
	remove_from_group("enemies")
	add_to_group("combat_bots")
	add_to_group("team_" + faction.id)
	is_player_team = faction.id == "green_army"
	# Arena fights are open-field: see and engage further than room patrols.
	vision_range = 36.0
	attack_range = 18.0

## Non-green teams reuse the green soldier mold recolored into the faction's
## plastic batch (chrome keeps its own model via the is_chrome path in Unit).
func _body_params() -> Dictionary:
	var params := super()
	if faction != null and faction.id != "chrome_legion" and faction.id != "green_army":
		var pc := faction.primary_color
		params.tint = Color(pc.r / 0.78, pc.g / 1.0, pc.b / 0.72) * 1.25
	return params

func _faction_of(node: Node) -> FactionData:
	if node == null:
		return null
	if "faction" in node:
		return node.faction
	return null

func _consider(candidate: Node3D, best: Node3D, best_dist: float) -> Array:
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return [best, best_dist]
	if candidate.has_method("is_dead") and candidate.is_dead():
		return [best, best_dist]
	var their_fac := _faction_of(candidate)
	if their_fac == null or faction == null or not faction.hostile_to(their_fac):
		return [best, best_dist]
	var hunt: Node3D = candidate
	# Boarded human: chase the hull/plane.
	if candidate is Player and (candidate as Player).current_vehicle != null \
			and is_instance_valid((candidate as Player).current_vehicle):
		hunt = (candidate as Player).current_vehicle
	var d := global_position.distance_to(hunt.global_position)
	if d < best_dist:
		return [hunt, d]
	return [best, best_dist]

func _acquire_target() -> Node3D:
	var best: Node3D = null
	var best_dist := vision_range
	# Live bots (Units) + remote human puppets (RemoteSoldier, not a Unit).
	for c in get_tree().get_nodes_in_group("combat_bots"):
		if c is RemoteBot:
			continue  # client puppets — authority has real CombatBots
		if not (c is Node3D):
			continue
		var pair: Array = _consider(c as Node3D, best, best_dist)
		best = pair[0]
		best_dist = pair[1]
	# Local human (listen-host / offline) — always consider if hostile.
	if Game.player != null and is_instance_valid(Game.player):
		var pair2: Array = _consider(Game.player, best, best_dist)
		best = pair2[0]
		best_dist = pair2[1]
	# Dedicated + online: remote humans.
	for n in get_tree().get_nodes_in_group("net_players"):
		if not (n is Node3D):
			continue
		var pair3: Array = _consider(n as Node3D, best, best_dist)
		best = pair3[0]
		best_dist = pair3[1]
	return best

## Hold-the-Dune / assault spawn: path to the mound instead of idle-patrolling.
func _begin_dune_rush() -> void:
	state = AiState.ALERT
	target = _acquire_target()
	if _nav != null:
		_nav.target_position = Vector3(0, 1, 0) if target == null else target.global_position

## Alert teammates, not the campaign "enemies" group.
func _enter_combat() -> void:
	state = AiState.COMBAT
	for ally in get_tree().get_nodes_in_group("team_" + faction.id):
		if ally != self and ally is CombatBot and global_position.distance_to(ally.global_position) < alert_radius:
			if ally.state == AiState.PATROL:
				ally.state = AiState.ALERT
				ally.target = target
				if ally._nav != null and target != null:
					ally._nav.target_position = target.global_position
