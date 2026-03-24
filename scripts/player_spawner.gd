extends Node

## PlayerSpawner — handles multiplayer player spawning and synchronization.
## Spawns one hero per connected player with unique multiplayer authority.
## Provides MultiplayerSynchronizer-like behavior via RPCs for position/state.

signal player_hero_spawned(peer_id: int, hero: Node3D)
signal player_hero_despawned(peer_id: int)

const HERO_SCENE := preload("res://scenes/hero.tscn")

## Map of peer_id -> hero node
var player_heroes: Dictionary = {}

## Interpolation targets for remote players: peer_id -> { pos, rot }
var _remote_targets: Dictionary = {}

## Sync rate (unreliable position updates per second)
const POSITION_SYNC_RATE := 20.0
var _sync_timer: float = 0.0

func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

func _process(delta: float) -> void:
	if not NetworkManager.is_multiplayer_active():
		return

	# Send local player position at fixed rate (unreliable)
	_sync_timer += delta
	if _sync_timer >= 1.0 / POSITION_SYNC_RATE:
		_sync_timer = 0.0
		_send_local_position()

	# Interpolate remote players toward their targets
	_interpolate_remote_players(delta)

## Spawn heroes for all connected players. Called by dungeon scene after floor builds.
func spawn_all_players(spawn_position: Vector3, units_node: Node3D) -> void:
	if not NetworkManager.is_multiplayer_active():
		# Singleplayer — hero already in scene, just register it
		return

	var offset_idx := 0
	var offsets := [Vector3.ZERO, Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, 2)]

	for pid in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[pid]
		var hero := HERO_SCENE.instantiate() as CharacterBody3D
		hero.name = "Hero_%d" % pid

		# Set character data from lobby selection
		var char_idx: int = info.get("character_index", 0)
		var spell_set: int = info.get("spell_set", 0)
		hero.set_meta("mp_peer_id", pid)
		hero.set_meta("mp_character_index", char_idx)
		hero.set_meta("mp_spell_set", spell_set)

		# Offset spawn positions so players don't overlap
		var offset: Vector3 = offsets[offset_idx % offsets.size()]
		hero.global_position = spawn_position + offset
		offset_idx += 1

		units_node.add_child(hero)
		player_heroes[pid] = hero

		# The local player's hero is the "main" hero
		var my_id := NetworkManager.get_my_id()
		if pid == my_id:
			GameManager.register_hero(hero)
		else:
			# Remote players: disable local input processing
			_configure_remote_hero(hero, pid)
			_remote_targets[pid] = {
				"pos": hero.global_position,
				"rot_y": hero.rotation.y,
				"health": hero.max_health,
				"mana": hero.max_mana,
			}

		player_hero_spawned.emit(pid, hero)

	# Remove the scene-baked hero if it exists (we spawned our own)
	var baked_hero := units_node.get_node_or_null("Hero")
	if baked_hero and not player_heroes.values().has(baked_hero):
		GameManager.unregister_enemy(baked_hero)  # Just in case
		baked_hero.queue_free()

func _configure_remote_hero(hero: CharacterBody3D, _pid: int) -> void:
	# Disable navigation agent to prevent remote heroes from running AI movement
	var nav := hero.get_node_or_null("NavigationAgent3D")
	if nav:
		nav.set_process(false)
		nav.set_physics_process(false)

## Get the local player's hero
func get_local_hero() -> CharacterBody3D:
	var my_id := NetworkManager.get_my_id()
	return player_heroes.get(my_id, null) as CharacterBody3D

## Get a remote player's hero by peer ID
func get_player_hero(pid: int) -> CharacterBody3D:
	return player_heroes.get(pid, null) as CharacterBody3D

## Get all living player heroes
func get_alive_heroes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for pid in player_heroes:
		var hero: CharacterBody3D = player_heroes[pid]
		if is_instance_valid(hero) and not hero.is_dead:
			result.append(hero)
	return result

## Get the nearest player to a world position (for enemy targeting)
func get_nearest_player(from_pos: Vector3, max_range: float = 999.0) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = max_range
	for pid in player_heroes:
		var hero: CharacterBody3D = player_heroes[pid]
		if not is_instance_valid(hero) or hero.is_dead:
			continue
		var dist := from_pos.distance_to(hero.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = hero
	return nearest

## Count alive players
func get_alive_count() -> int:
	var count := 0
	for pid in player_heroes:
		var hero: CharacterBody3D = player_heroes[pid]
		if is_instance_valid(hero) and not hero.is_dead:
			count += 1
	return count

# ---------- POSITION SYNC ----------

func _send_local_position() -> void:
	var my_hero := get_local_hero()
	if my_hero == null or not is_instance_valid(my_hero):
		return
	# Send position, rotation, health, mana via unreliable RPC
	rpc("_receive_player_position",
		NetworkManager.get_my_id(),
		my_hero.global_position,
		my_hero.rotation.y,
		my_hero.current_health,
		my_hero.current_mana,
		my_hero.anim_state
	)

@rpc("any_peer", "unreliable")
func _receive_player_position(pid: int, pos: Vector3, rot_y: float, hp: int, mp: int, anim: int) -> void:
	# Don't process our own position
	if pid == NetworkManager.get_my_id():
		return

	if _remote_targets.has(pid):
		_remote_targets[pid]["pos"] = pos
		_remote_targets[pid]["rot_y"] = rot_y
		_remote_targets[pid]["health"] = hp
		_remote_targets[pid]["mana"] = mp
		_remote_targets[pid]["anim_state"] = anim
	else:
		_remote_targets[pid] = {
			"pos": pos,
			"rot_y": rot_y,
			"health": hp,
			"mana": mp,
			"anim_state": anim,
		}

func _interpolate_remote_players(delta: float) -> void:
	var lerp_speed := 12.0  # Smooth interpolation factor
	for pid in _remote_targets:
		var hero: CharacterBody3D = player_heroes.get(pid, null)
		if hero == null or not is_instance_valid(hero):
			continue
		var target: Dictionary = _remote_targets[pid]

		# Lerp position
		hero.global_position = hero.global_position.lerp(target["pos"], lerp_speed * delta)

		# Lerp rotation
		hero.rotation.y = lerp_angle(hero.rotation.y, target["rot_y"], lerp_speed * delta)

		# Update health/mana (reliable state)
		var hp: int = target.get("health", hero.max_health)
		if hero.current_health != hp:
			hero.current_health = hp
			hero.health_changed.emit(hero.current_health, hero.max_health)

		var mp: int = target.get("mana", hero.max_mana)
		if hero.current_mana != mp:
			hero.current_mana = mp
			hero.mana_changed.emit(hero.current_mana, hero.max_mana)

# ---------- RELIABLE STATE SYNC ----------

## Broadcast a player's HP change (host -> all)
func sync_player_hp(pid: int, hp: int) -> void:
	rpc("_receive_hp_sync", pid, hp)

@rpc("any_peer", "reliable")
func _receive_hp_sync(pid: int, hp: int) -> void:
	var hero: CharacterBody3D = player_heroes.get(pid, null)
	if hero and is_instance_valid(hero):
		hero.current_health = hp
		hero.health_changed.emit(hero.current_health, hero.max_health)
		if hp <= 0 and not hero.is_dead:
			hero.is_dead = true
			hero.hero_died.emit()

## Broadcast spell cast (for visual/audio sync on remote clients)
func sync_spell_cast(pid: int, spell_index: int, target_pos: Vector3) -> void:
	rpc("_receive_spell_cast", pid, spell_index, target_pos)

@rpc("any_peer", "reliable")
func _receive_spell_cast(pid: int, spell_index: int, _target_pos: Vector3) -> void:
	if pid == NetworkManager.get_my_id():
		return
	var hero: CharacterBody3D = player_heroes.get(pid, null)
	if hero and is_instance_valid(hero) and hero.has_method("_play_cast_animation"):
		hero._play_cast_animation(spell_index)

# ---------- PLAYER DISCONNECT ----------

func _on_player_disconnected(pid: int) -> void:
	if player_heroes.has(pid):
		var hero: CharacterBody3D = player_heroes[pid]
		if is_instance_valid(hero):
			hero.queue_free()
		player_heroes.erase(pid)
		_remote_targets.erase(pid)
		player_hero_despawned.emit(pid)

## Reposition all players at a new spawn point (floor transition)
func reposition_all(spawn_pos: Vector3) -> void:
	var offsets := [Vector3.ZERO, Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, 2)]
	var idx := 0
	for pid in player_heroes:
		var hero: CharacterBody3D = player_heroes[pid]
		if is_instance_valid(hero):
			var offset: Vector3 = offsets[idx % offsets.size()]
			hero.global_position = spawn_pos + offset
			hero.is_moving = false
			hero.velocity = Vector3.ZERO
			hero.current_speed = 0.0
			# Update remote targets to avoid interpolation snap
			if _remote_targets.has(pid):
				_remote_targets[pid]["pos"] = hero.global_position
		idx += 1

## Clean up all spawned heroes
func cleanup() -> void:
	for pid in player_heroes:
		var hero: CharacterBody3D = player_heroes[pid]
		if is_instance_valid(hero):
			hero.queue_free()
	player_heroes.clear()
	_remote_targets.clear()
