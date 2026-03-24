extends Node

## EnemySync — handles multiplayer enemy synchronization.
## Host spawns all enemies, runs AI, and broadcasts position/state.
## Clients receive state and interpolate. Damage RPCs go client->host->broadcast.

const SYNC_RATE := 15.0  # Position updates per second
var _sync_timer: float = 0.0

## Remote enemy targets for client interpolation: enemy_name -> { pos, rot_y, hp, state }
var _remote_targets: Dictionary = {}

## Track synced enemies by name for lookup
var _synced_enemies: Dictionary = {}  # name -> enemy node

## Reference to Units node
var _units_node: Node3D = null

func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		return

func setup(units_node: Node3D) -> void:
	_units_node = units_node

func _process(delta: float) -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	if _units_node == null:
		return

	# Host broadcasts enemy positions
	if NetworkManager.is_host:
		_sync_timer += delta
		if _sync_timer >= 1.0 / SYNC_RATE:
			_sync_timer = 0.0
			_host_broadcast_enemy_state()
	else:
		# Client interpolates remote enemies
		_client_interpolate_enemies(delta)

# ---------- HOST: ENEMY AI TARGET OVERRIDE ----------

## Override enemy targeting to use nearest player (not just GameManager.hero).
## Call this after enemies are spawned to patch their targeting.
func patch_enemy_targeting() -> void:
	if not NetworkManager.is_multiplayer_active():
		return
	if _units_node == null:
		return
	# Register all enemies for sync
	for child in _units_node.get_children():
		if child.has_method("take_damage") and child != GameManager.hero:
			_synced_enemies[child.name] = child

# ---------- HOST: BROADCAST STATE ----------

func _host_broadcast_enemy_state() -> void:
	if _units_node == null:
		return

	var batch: Array = []
	for child in _units_node.get_children():
		# Skip hero nodes (they start with "Hero_")
		if child.name.begins_with("Hero"):
			continue
		if not child.has_method("take_damage"):
			continue
		if not is_instance_valid(child):
			continue

		var hp: int = child.get("current_health") if child.get("current_health") != null else 0
		var is_dead: bool = child.get("is_dead") if child.get("is_dead") != null else false

		if is_dead:
			continue

		batch.append({
			"name": str(child.name),
			"pos": child.global_position,
			"rot_y": child.rotation.y,
			"hp": hp,
		})

	if batch.size() > 0:
		rpc("_receive_enemy_batch", batch)

@rpc("authority", "unreliable")
func _receive_enemy_batch(batch: Array) -> void:
	for entry in batch:
		var ename: String = entry["name"]
		_remote_targets[ename] = {
			"pos": entry["pos"],
			"rot_y": entry["rot_y"],
			"hp": entry["hp"],
		}

# ---------- CLIENT: INTERPOLATION ----------

func _client_interpolate_enemies(delta: float) -> void:
	if _units_node == null:
		return
	var lerp_speed := 10.0
	for ename in _remote_targets:
		var enemy := _units_node.get_node_or_null(ename)
		if enemy == null or not is_instance_valid(enemy):
			continue
		var target: Dictionary = _remote_targets[ename]

		# Interpolate position and rotation
		enemy.global_position = enemy.global_position.lerp(target["pos"], lerp_speed * delta)
		enemy.rotation.y = lerp_angle(enemy.rotation.y, target["rot_y"], lerp_speed * delta)

		# Sync HP
		var hp: int = target.get("hp", 0)
		if enemy.get("current_health") != null and enemy.current_health != hp:
			enemy.current_health = hp
			if enemy.has_signal("health_changed"):
				enemy.health_changed.emit(hp, enemy.max_health)

# ---------- DAMAGE: CLIENT -> HOST -> BROADCAST ----------

## Client requests damage on an enemy. Host validates and applies.
func request_enemy_damage(enemy_name: String, amount: int, source_peer_id: int) -> void:
	if NetworkManager.is_host:
		# Host can apply directly
		_apply_enemy_damage(enemy_name, amount, source_peer_id)
	else:
		rpc_id(1, "_host_validate_enemy_damage", enemy_name, amount, source_peer_id)

@rpc("any_peer", "reliable")
func _host_validate_enemy_damage(enemy_name: String, amount: int, source_peer_id: int) -> void:
	if not NetworkManager.is_host:
		return
	_apply_enemy_damage(enemy_name, amount, source_peer_id)

func _apply_enemy_damage(enemy_name: String, amount: int, _source_peer_id: int) -> void:
	if _units_node == null:
		return
	var enemy := _units_node.get_node_or_null(enemy_name)
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.get("is_dead") and enemy.is_dead:
		return
	if enemy.has_method("take_damage"):
		enemy.take_damage(amount)
	# Broadcast the HP update to all clients
	var hp: int = enemy.get("current_health") if enemy.get("current_health") != null else 0
	rpc("_broadcast_enemy_hp", enemy_name, hp)

	# If enemy died, broadcast death
	if enemy.get("is_dead") and enemy.is_dead:
		rpc("_broadcast_enemy_death", enemy_name)

@rpc("authority", "reliable")
func _broadcast_enemy_hp(enemy_name: String, hp: int) -> void:
	if _units_node == null:
		return
	var enemy := _units_node.get_node_or_null(enemy_name)
	if enemy and is_instance_valid(enemy):
		enemy.current_health = hp
		if enemy.has_signal("health_changed"):
			enemy.health_changed.emit(hp, enemy.max_health)

@rpc("authority", "reliable")
func _broadcast_enemy_death(enemy_name: String) -> void:
	if _units_node == null:
		return
	var enemy := _units_node.get_node_or_null(enemy_name)
	if enemy and is_instance_valid(enemy) and not enemy.is_dead:
		if enemy.has_method("_die"):
			enemy._die()
		else:
			enemy.is_dead = true
			enemy.queue_free()

# ---------- DISABLE CLIENT AI ----------

## On clients, disable enemy AI so only the host runs it.
func disable_client_enemy_ai() -> void:
	if NetworkManager.is_host:
		return  # Host runs all AI
	if _units_node == null:
		return
	for child in _units_node.get_children():
		if child.name.begins_with("Hero"):
			continue
		if child.has_method("take_damage"):
			# Disable physics process so enemies don't run AI locally
			child.set_physics_process(false)
			# Keep process for animation/visual updates
