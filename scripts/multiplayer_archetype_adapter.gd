extends Node

## MultiplayerArchetypeAdapter — patches floor archetypes for multiplayer.
## Adapts each archetype to handle multiple players:
##   Escape: danger wall kills any player, spike pits hit all players
##   SurvivalArena: enemy HP/count scales with player count
##   BossRush: boss HP scales with player count
##   Stealth: shared alarm state synced across clients
##   Political: per-player reputation, opposing win paths possible
##   Race: players race each other (ghosts reduced, player positions tracked)
##
## Applied once per floor after archetype.start() via adapt().

## Player count scaling factor: 1.0 + 0.35 * (players - 1)
## 2P = 1.35x, 3P = 1.70x, 4P = 2.05x
const SCALE_PER_EXTRA_PLAYER := 0.35

## Shared alarm state for stealth (host-authoritative)
var _stealth_alarm_synced: bool = false

## Per-player reputation for political (host tracks all, syncs to clients)
## Dictionary of peer_id -> { faction_name -> int }
var _player_reputations: Dictionary = {}

## Race: track per-player checkpoint progress
var _race_player_checkpoints: Dictionary = {}  # peer_id -> int

func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		return

## Adapt a floor archetype for multiplayer. Called after archetype.start().
func adapt(archetype: FloorArchetype) -> void:
	if not NetworkManager.is_multiplayer_active():
		return

	var player_count := _get_player_count()
	if player_count <= 1:
		return

	var scale := _hp_scale(player_count)

	if archetype is EscapeArchetype:
		_adapt_escape(archetype, player_count)
	elif archetype is SurvivalArenaArchetype:
		_adapt_survival_arena(archetype, player_count, scale)
	elif archetype is BossRushArchetype:
		_adapt_boss_rush(archetype, player_count, scale)
	elif archetype is StealthArchetype:
		_adapt_stealth(archetype, player_count)
	elif archetype is PoliticalArchetype:
		_adapt_political(archetype, player_count)
	elif archetype is RaceArchetype:
		_adapt_race(archetype, player_count)

## Per-frame update for multiplayer archetype state.
func update_mp(archetype: FloorArchetype, _delta: float) -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	if archetype is EscapeArchetype:
		_update_escape(archetype)
	elif archetype is RaceArchetype:
		_update_race(archetype)

# ---------- SCALING HELPERS ----------

func _get_player_count() -> int:
	return maxi(NetworkManager.get_player_count(), 1)

func _hp_scale(player_count: int) -> float:
	return 1.0 + SCALE_PER_EXTRA_PLAYER * (player_count - 1)

# ---------- ESCAPE ADAPTATION ----------
# Danger wall and spikes must hit ALL players, not just GameManager.hero.

func _adapt_escape(archetype: EscapeArchetype, _player_count: int) -> void:
	# Reconnect the danger area to hit any player hero
	var wall := archetype._danger_wall
	if wall == null:
		return
	var area := wall.get_node_or_null("DangerArea") as Area3D
	if area:
		# Disconnect old single-player callback, connect multiplayer version
		if area.body_entered.is_connected(archetype._on_danger_hit):
			area.body_entered.disconnect(archetype._on_danger_hit)
		area.body_entered.connect(_on_mp_danger_hit.bind(archetype))

	# Reconnect spike pits
	for obs in archetype._obstacles:
		if not is_instance_valid(obs):
			continue
		if obs is Area3D and obs.name.begins_with("SpikePit"):
			if obs.body_entered.is_connected(archetype._on_spike_hit):
				obs.body_entered.disconnect(archetype._on_spike_hit)
			obs.body_entered.connect(_on_mp_spike_hit.bind(archetype))

func _on_mp_danger_hit(body: Node3D, archetype: EscapeArchetype) -> void:
	if not archetype._is_active:
		return
	# Kill any player hero that touches the wall
	if body.has_meta("mp_peer_id") or body == GameManager.hero:
		archetype.show_message("CONSUMED BY THE COLLAPSE!", Color(1.0, 0.0, 0.0), 3.0)
		if body.has_method("take_damage"):
			body.take_damage(99999)

func _on_mp_spike_hit(body: Node3D, archetype: EscapeArchetype) -> void:
	if not archetype._is_active:
		return
	if body.has_meta("mp_peer_id") or body == GameManager.hero:
		if body.has_method("take_damage"):
			body.take_damage(80)
		archetype.show_message("SPIKE PIT!", Color(1.0, 0.3, 0.0), 1.5)
		GameManager.request_screen_shake(4.0, 0.2)

func _update_escape(archetype: EscapeArchetype) -> void:
	# Update HUD to show nearest player's distance from wall
	if archetype._hud_overlay == null or archetype._danger_wall == null:
		return
	var label = archetype._hud_overlay.get_node_or_null("DistLabel")
	if label == null:
		return

	var spawner := get_tree().current_scene.get_node_or_null("PlayerSpawner")
	if spawner == null:
		return

	# Show the closest player to the wall (most at risk)
	var min_dist := 9999.0
	for pid in spawner.player_heroes:
		var hero: Node3D = spawner.player_heroes[pid]
		if is_instance_valid(hero) and not hero.is_dead:
			var dist = hero.global_position.z - archetype._danger_wall_z
			min_dist = minf(min_dist, dist)
	label.text = "Wall: %.0fm behind (closest)" % maxf(min_dist, 0.0)

# ---------- SURVIVAL ARENA ADAPTATION ----------
# Scale enemy count and HP per wave with player count.

func _adapt_survival_arena(archetype: SurvivalArenaArchetype, player_count: int, scale: float) -> void:
	# Add one extra wave for 3+ players
	if player_count >= 3:
		archetype._total_waves += 1

	# Patch the wave enemy count formula: store the scale so it applies per wave
	archetype.set_meta("mp_enemy_scale", scale)
	archetype.set_meta("mp_hp_scale", scale)

# ---------- BOSS RUSH ADAPTATION ----------
# Scale boss HP/damage with player count.

func _adapt_boss_rush(archetype: BossRushArchetype, _player_count: int, scale: float) -> void:
	# Store the multiplayer HP scale — applied when each boss spawns
	archetype.set_meta("mp_boss_hp_scale", scale)

# ---------- STEALTH ADAPTATION ----------
# Shared alarm: if ANY player is spotted, alarm triggers for all.
# Host manages alarm state and broadcasts to clients.

func _adapt_stealth(archetype: StealthArchetype, player_count: int) -> void:
	_stealth_alarm_synced = false

	# Increase patrol count for more players (2 extra per additional player)
	var extra_patrols := (player_count - 1) * 2
	archetype.set_meta("mp_extra_patrols", extra_patrols)

	# Alarm swarm scales with player count
	archetype.set_meta("mp_swarm_scale", player_count)

# ---------- POLITICAL ADAPTATION ----------
# Each player tracks their own reputation. Players can pursue different
# win paths (one can bribe, another assassinate). Exit unlocks for all
# once ANY player meets a win condition.

func _adapt_political(archetype: PoliticalArchetype, _player_count: int) -> void:
	_player_reputations.clear()
	for pid in NetworkManager.players:
		_player_reputations[pid] = {}
		for fname in archetype._reputation:
			_player_reputations[pid][fname] = 0

	# Scale mayor and guard HP for multiplayer
	var scale := _hp_scale(_get_player_count())
	if is_instance_valid(archetype._mayor):
		var mayor_hp := int(archetype._mayor.get_meta("max_health", 100) * scale)
		archetype._mayor.set_meta("max_health", mayor_hp)
		archetype._mayor.set_meta("current_health", mayor_hp)

	for guard in archetype._guards:
		if is_instance_valid(guard):
			var guard_hp := int(guard.get_meta("max_health", 80) * scale)
			guard.set_meta("max_health", guard_hp)
			guard.set_meta("current_health", guard_hp)

## Called by the scene to sync a player's political reputation change.
func sync_political_rep(pid: int, faction_name: String, new_rep: int) -> void:
	if NetworkManager.is_host:
		_player_reputations[pid] = _player_reputations.get(pid, {})
		_player_reputations[pid][faction_name] = new_rep
		rpc("_receive_political_rep", pid, faction_name, new_rep)

@rpc("authority", "reliable")
func _receive_political_rep(pid: int, faction_name: String, new_rep: int) -> void:
	_player_reputations[pid] = _player_reputations.get(pid, {})
	_player_reputations[pid][faction_name] = new_rep

## Get a specific player's faction reputation.
func get_player_rep(pid: int, faction_name: String) -> int:
	if _player_reputations.has(pid):
		return _player_reputations[pid].get(faction_name, 0)
	return 0

# ---------- RACE ADAPTATION ----------
# Players race each other alongside ghosts. Each player's checkpoint
# progress is tracked. Placement includes other players.

func _adapt_race(archetype: RaceArchetype, player_count: int) -> void:
	_race_player_checkpoints.clear()
	for pid in NetworkManager.players:
		_race_player_checkpoints[pid] = 0

	# Reduce ghost count in multiplayer (players ARE the competition)
	# Keep 1 ghost as pace reference, remove extras
	if player_count >= 2:
		while archetype._ghosts.size() > 1:
			var ghost: Node3D = archetype._ghosts.pop_back()
			if is_instance_valid(ghost):
				ghost.queue_free()
		archetype._ghost_speeds.resize(mini(archetype._ghost_speeds.size(), 1))
		archetype._ghost_waypoint_idx.resize(mini(archetype._ghost_waypoint_idx.size(), 1))

func _update_race(archetype: RaceArchetype) -> void:
	if not archetype._race_started:
		return

	var spawner := get_tree().current_scene.get_node_or_null("PlayerSpawner")
	if spawner == null:
		return

	# Check all players against checkpoints and finish line
	for pid in spawner.player_heroes:
		var hero: Node3D = spawner.player_heroes[pid]
		if not is_instance_valid(hero) or hero.is_dead:
			continue

		# Check checkpoints for this player
		for cp in archetype._checkpoints:
			if not is_instance_valid(cp):
				continue
			# Use per-player metadata to track hits
			var hit_key := "hit_pid_%d" % pid
			if cp.get_meta(hit_key, false):
				continue
			var dist = hero.global_position.distance_to(cp.global_position)
			if dist < 3.0:
				cp.set_meta(hit_key, true)
				_race_player_checkpoints[pid] = _race_player_checkpoints.get(pid, 0) + 1
				if pid == NetworkManager.get_my_id():
					var my_cps: int = _race_player_checkpoints[pid]
					archetype.show_message(
						"Checkpoint %d/%d!" % [my_cps, archetype.CHECKPOINT_COUNT],
						archetype.accent_color, 1.5
					)

		# Check finish line for all players
		if is_instance_valid(archetype._finish_portal):
			var cps: int = _race_player_checkpoints.get(pid, 0)
			if cps >= archetype.CHECKPOINT_COUNT:
				var dist = hero.global_position.distance_to(archetype._finish_portal.global_position)
				if dist < 3.0:
					_on_player_finished_race(archetype, pid)

	# Update position label to include other players
	_update_race_position_hud(archetype, spawner)

func _on_player_finished_race(archetype: RaceArchetype, pid: int) -> void:
	if not archetype._race_started:
		return

	var my_id := NetworkManager.get_my_id()

	# Determine placement among all players
	var players_finished := 0
	for p in _race_player_checkpoints:
		if _race_player_checkpoints[p] > archetype.CHECKPOINT_COUNT:
			players_finished += 1

	# Mark this player as finished (use > CHECKPOINT_COUNT as marker)
	_race_player_checkpoints[pid] = archetype.CHECKPOINT_COUNT + 1

	# Also count ghosts that finished
	var ghosts_finished := 0
	for i in range(archetype._ghost_waypoint_idx.size()):
		if archetype._ghost_waypoint_idx[i] >= archetype._race_path.size():
			ghosts_finished += 1

	var place := players_finished + ghosts_finished + 1

	if pid == my_id:
		archetype.show_message(
			"RACE COMPLETE! Time: %.1fs — Place: #%d" % [archetype._race_timer, place],
			Color(0.2, 1.0, 0.4), 4.0
		)

		var vp_reward := 30
		if place == 1:
			vp_reward = 80
			archetype.show_message("FIRST PLACE! Bonus loot!", archetype.accent_color, 3.0)
			LootManager.gold += 50 + archetype.floor_number * 10
			LootManager.gold_changed.emit(LootManager.gold)
		elif place == 2:
			vp_reward = 50
		elif place == 3:
			vp_reward = 35
		AudienceManager.grant_vp(vp_reward, "Race finished #%d!" % place)

	# Once all alive players finish, complete the archetype
	var all_done := true
	var spawner := get_tree().current_scene.get_node_or_null("PlayerSpawner")
	if spawner:
		for p in spawner.player_heroes:
			var hero: Node3D = spawner.player_heroes[p]
			if is_instance_valid(hero) and not hero.is_dead:
				if _race_player_checkpoints.get(p, 0) <= archetype.CHECKPOINT_COUNT:
					all_done = false
					break

	if all_done and NetworkManager.is_host:
		archetype._race_started = false
		archetype.complete()

func _update_race_position_hud(archetype: RaceArchetype, spawner: Node) -> void:
	if archetype._position_label == null:
		return

	var my_id := NetworkManager.get_my_id()
	var my_hero: Node3D = spawner.player_heroes.get(my_id, null)
	if my_hero == null or not is_instance_valid(my_hero):
		return

	# Calculate my progress along the path
	var my_progress := _calc_race_progress(archetype, my_hero)

	# Count who's ahead of me
	var ahead := 0
	var total_racers := 0

	# Other players
	for pid in spawner.player_heroes:
		var hero: Node3D = spawner.player_heroes[pid]
		if not is_instance_valid(hero) or hero.is_dead:
			continue
		total_racers += 1
		if pid != my_id:
			var their_progress := _calc_race_progress(archetype, hero)
			if their_progress > my_progress:
				ahead += 1

	# Ghosts
	for i in range(archetype._ghost_waypoint_idx.size()):
		total_racers += 1
		var ghost_progress := float(archetype._ghost_waypoint_idx[i]) / float(archetype._race_path.size())
		if ghost_progress > my_progress:
			ahead += 1

	archetype._position_label.text = "Position: #%d / %d" % [ahead + 1, total_racers]

func _calc_race_progress(archetype: RaceArchetype, hero: Node3D) -> float:
	if archetype._race_path.is_empty():
		return 0.0
	var best_idx := 0
	var min_dist := 9999.0
	for i in range(archetype._race_path.size()):
		var d = hero.global_position.distance_to(archetype._race_path[i])
		if d < min_dist:
			min_dist = d
			best_idx = i
	return float(best_idx) / float(archetype._race_path.size())

# ---------- STEALTH SYNC ----------

## Called when any player triggers an alarm — host broadcasts to all.
func sync_stealth_alarm() -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	if NetworkManager.is_host:
		rpc("_receive_stealth_alarm")

@rpc("authority", "reliable")
func _receive_stealth_alarm() -> void:
	_stealth_alarm_synced = true

func is_alarm_synced() -> bool:
	return _stealth_alarm_synced

func reset_alarm_sync() -> void:
	_stealth_alarm_synced = false
