class_name CombatBot
extends EnemySoldier
## Arena-mode bot: EnemySoldier's brain, but team-agnostic. Fights for ANY
## faction against every hostile faction — the "fake players" of Skirmish and
## Battle Royale. Targets are found through the "combat_bots" group instead of
## the campaign's hardcoded player/green_allies lists.

## Bots on the player's team defend them; hostile bots hunt them.
var is_player_team: bool = false

func _unit_ready() -> void:
	super()
	remove_from_group("enemies")
	add_to_group("combat_bots")
	add_to_group("team_" + faction.id)
	is_player_team = faction.id == "green_army"
	# Arena fights are open-field: see and engage further than room patrols.
	vision_range = 30.0
	attack_range = 16.0

## Non-green teams reuse the green soldier mold recolored into the faction's
## plastic batch (chrome keeps its own model via the is_chrome path in Unit).
func _body_params() -> Dictionary:
	var params := super()
	if faction != null and faction.id != "chrome_legion" and faction.id != "green_army":
		var pc := faction.primary_color
		params.tint = Color(pc.r / 0.78, pc.g / 1.0, pc.b / 0.72) * 1.25
	return params

func _acquire_target() -> Node3D:
	var best: Node3D = null
	var best_dist := vision_range
	for c in get_tree().get_nodes_in_group("combat_bots"):
		if c == self or not (c is Unit) or not is_instance_valid(c) or c.is_dead():
			continue
		if not faction.hostile_to(c.faction):
			continue
		var d := global_position.distance_to(c.global_position)
		if d < best_dist:
			best_dist = d
			best = c
	if not is_player_team and Game.player != null and is_instance_valid(Game.player) \
			and not Game.player.is_dead():
		var pd := global_position.distance_to(Game.player.global_position)
		if pd < best_dist:
			best = Game.player
	return best

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
