extends Node

## CombatSync — multiplayer combat synchronization.
## All damage calls routed through host for validation.
## Spell projectiles spawned locally with prediction, host confirms hit.
## AoE: host radius check. Friendly fire toggle. All player HP bars visible.
## Heal spells can target nearby allies.

## Reference to PlayerSpawner for looking up heroes
var _player_spawner: Node = null
var _units_node: Node3D = null

func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		return

func setup(units_node: Node3D, player_spawner: Node) -> void:
	_units_node = units_node
	_player_spawner = player_spawner

# ---------- DAMAGE: CLIENT -> HOST -> BROADCAST ----------

## Request damage on any target (enemy or player). Host validates.
func request_damage(target: Node3D, amount: int, source_peer_id: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_path := str(target.get_path())

	if NetworkManager.is_host:
		_host_apply_damage(target_path, amount, source_peer_id)
	else:
		rpc_id(1, "_host_validate_damage", target_path, amount, source_peer_id)

@rpc("any_peer", "reliable")
func _host_validate_damage(target_path: String, amount: int, source_peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	_host_apply_damage(target_path, amount, source_peer_id)

func _host_apply_damage(target_path: String, amount: int, source_peer_id: int) -> void:
	var target := get_tree().root.get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		return

	# Check friendly fire rules
	if _is_player_hero(target):
		# Target is a player hero
		var target_pid: int = target.get_meta("mp_peer_id", -1)
		if target_pid == source_peer_id:
			return  # Can't damage yourself
		if not NetworkManager.friendly_fire_enabled:
			return  # Friendly fire is off

	if target.has_method("take_damage"):
		target.take_damage(amount)

	# Broadcast HP update
	if target.get("current_health") != null:
		rpc("_broadcast_hp_update", target_path, target.current_health)

@rpc("authority", "reliable")
func _broadcast_hp_update(target_path: String, hp: int) -> void:
	var target := get_tree().root.get_node_or_null(target_path)
	if target and is_instance_valid(target):
		if target.get("current_health") != null:
			target.current_health = hp
			if target.has_signal("health_changed"):
				target.health_changed.emit(hp, target.max_health)

# ---------- SPELL PROJECTILE SYNC ----------

## Locally spawn a projectile (prediction), then ask host to validate hit.
func spawn_projectile_local(spell_index: int, origin: Vector3, direction: Vector3, caster_pid: int) -> void:
	# Broadcast visual projectile to all players
	rpc("_receive_projectile_visual", spell_index, origin, direction, caster_pid)

@rpc("any_peer", "unreliable")
func _receive_projectile_visual(spell_index: int, origin: Vector3, direction: Vector3, _caster_pid: int) -> void:
	# Spawn a visual-only projectile for remote players
	# The actual hit detection is done on the host
	var vfx_name := ""
	match spell_index:
		1: vfx_name = "fireball"
		_: return  # Only fireball has a visible projectile

	if VFXManager and VFXManager.has_method("spawn_projectile_visual"):
		VFXManager.spawn_projectile_visual(vfx_name, origin, direction)

## Host validates a projectile hit
func request_projectile_hit(target: Node3D, amount: int, caster_pid: int) -> void:
	request_damage(target, amount, caster_pid)

# ---------- AOE SYNC ----------

## Request AoE damage from host. Host does the radius check.
func request_aoe_damage(center: Vector3, radius: float, amount: int, caster_pid: int) -> void:
	if NetworkManager.is_host:
		_host_process_aoe(center, radius, amount, caster_pid)
	else:
		rpc_id(1, "_host_validate_aoe", center, radius, amount, caster_pid)

@rpc("any_peer", "reliable")
func _host_validate_aoe(center: Vector3, radius: float, amount: int, caster_pid: int) -> void:
	if not NetworkManager.is_host:
		return
	_host_process_aoe(center, radius, amount, caster_pid)

func _host_process_aoe(center: Vector3, radius: float, amount: int, caster_pid: int) -> void:
	# Damage all enemies in radius
	if _units_node:
		for child in _units_node.get_children():
			if child.name.begins_with("Hero"):
				# Player hero — check friendly fire
				if not NetworkManager.friendly_fire_enabled:
					continue
				var pid: int = child.get_meta("mp_peer_id", -1)
				if pid == caster_pid:
					continue  # Don't AoE yourself
			if not child.has_method("take_damage"):
				continue
			if child.get("is_dead") and child.is_dead:
				continue
			if child.global_position.distance_to(center) <= radius:
				child.take_damage(amount)
				if child.get("current_health") != null:
					rpc("_broadcast_hp_update", str(child.get_path()), child.current_health)

# ---------- HEAL SPELLS: TARGET ALLIES ----------

## Heal nearby ally. Called by local player, validated on host.
func request_heal(target: Node3D, amount: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_path := str(target.get_path())

	if NetworkManager.is_host:
		_host_apply_heal(target_path, amount)
	else:
		rpc_id(1, "_host_validate_heal", target_path, amount)

@rpc("any_peer", "reliable")
func _host_validate_heal(target_path: String, amount: int) -> void:
	if not NetworkManager.is_host:
		return
	_host_apply_heal(target_path, amount)

func _host_apply_heal(target_path: String, amount: int) -> void:
	var target := get_tree().root.get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		return
	if not _is_player_hero(target):
		return  # Can only heal player heroes

	if target.has_method("heal"):
		target.heal(amount)
	else:
		# Manual heal
		target.current_health = mini(target.current_health + amount, target.max_health)
		target.health_changed.emit(target.current_health, target.max_health)

	rpc("_broadcast_hp_update", target_path, target.current_health)

## Get the nearest ally to heal (excluding self)
func get_nearest_ally_to_heal(from_pos: Vector3, max_range: float, my_pid: int) -> Node3D:
	if _player_spawner == null:
		return null
	var nearest: Node3D = null
	var nearest_dist: float = max_range
	for pid in _player_spawner.player_heroes:
		if pid == my_pid:
			continue  # Skip self
		var hero: Node3D = _player_spawner.player_heroes[pid]
		if not is_instance_valid(hero) or hero.is_dead:
			continue
		# Only heal damaged allies
		if hero.current_health >= hero.max_health:
			continue
		var dist := from_pos.distance_to(hero.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = hero
	return nearest

# ---------- PLAYER HP BARS ----------

## Make all remote player HP bars visible. Call after spawning.
func setup_player_hp_bars() -> void:
	if _player_spawner == null:
		return
	for pid in _player_spawner.player_heroes:
		var hero: Node3D = _player_spawner.player_heroes[pid]
		if not is_instance_valid(hero):
			continue
		# Ensure health bar node is visible for all players
		var hb := hero.get_node_or_null("HealthBar")
		if hb:
			hb.visible = true

# ---------- UTILITY ----------

func _is_player_hero(node: Node3D) -> bool:
	return node.has_meta("mp_peer_id")
