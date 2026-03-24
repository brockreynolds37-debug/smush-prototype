extends CharacterBody3D

## Enemy unit with basic AI — aggro, chase, attack, die.
## Uses animated GLB models (one per animation state).

signal health_changed(current: int, maximum: int)

@export var max_health: int = 150
@export var move_speed: float = 5.0
@export var aggro_range: float = 10.0
@export var attack_range: float = 2.5
@export var attack_damage: int = 15
@export var attack_cooldown: float = 1.5

# Which model set to use — "goblin" or "orc"
@export var enemy_type: String = "goblin"

var current_health: int = 150
var is_dead: bool = false
var is_aggroed: bool = false
var current_speed: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var leash_range: float = 20.0

var original_scale := Vector3.ONE
var _cached_mesh_instances: Array[MeshInstance3D] = []

# Status effects
var _base_move_speed: float = 5.0
var _is_stunned: bool = false
var _slow_amount: float = 0.0
var _walk_bob_time: float = 0.0

# Animation
enum AnimState { IDLE, WALK, ATTACK, DEATH }
var anim_state: AnimState = AnimState.IDLE
var prev_anim_state: AnimState = AnimState.IDLE

var anim_scenes: Dictionary = {}
var active_model: Node3D = null
var active_anim_player: AnimationPlayer = null

@onready var model: Node3D = $EnemyModel
@onready var selection_circle: MeshInstance3D = $SelectionCircle
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var attack_timer: Timer = $AttackTimer

func _ready() -> void:
	GameManager.register_enemy(self)
	spawn_position = global_position

	# Apply BalanceConfig defaults based on enemy archetype
	_apply_balance_defaults()

	# Scale stats by floor number
	var floor_num := FloorManager.current_floor
	if floor_num > 1:
		max_health = int(max_health * pow(BalanceConfig.ENEMY_HP_SCALE_PER_FLOOR, floor_num - 1))
		attack_damage = int(attack_damage * pow(BalanceConfig.ENEMY_DAMAGE_SCALE_PER_FLOOR, floor_num - 1))

	# Apply difficulty multiplier
	var diff_mult := GameManager.get_difficulty_multiplier()
	if diff_mult != 1.0:
		max_health = int(max_health * diff_mult)
		attack_damage = int(attack_damage * diff_mult)

	current_health = max_health

	# Load model based on enemy type
	_base_move_speed = move_speed

	_load_enemy_model()
	original_scale = model.scale

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	health_changed.emit(current_health, max_health)

func _load_enemy_model() -> void:
	# Map enemy_type to model path
	var model_paths := {
		"rat": "res://assets/models/enemies/rat.glb",
		"slime": "res://assets/models/enemies/slime.glb",
		"spider": "res://assets/models/enemies/spider.glb",
		"wolf": "res://assets/models/enemies/wolf.glb",
		"goblin_warrior": "res://assets/models/enemies/goblin_warrior.glb",
		"goblin_archer": "res://assets/models/enemies/goblin_archer.glb",
		"skeleton": "res://assets/models/enemies/skeleton.glb",
		"goblin_shaman": "res://assets/models/enemies/goblin_shaman.glb",
		"animated_armor": "res://assets/models/enemies/animated_armor.glb",
		"mimic": "res://assets/models/enemies/mimic.glb",
		"orc": "res://assets/models/skeleton_warrior.glb",
	}

	if enemy_type == "goblin":
		# Animated goblin-scout with per-state models
		anim_scenes = {
			AnimState.IDLE: preload("res://assets/models/goblin-scout/idle_anim.glb"),
			AnimState.WALK: preload("res://assets/models/goblin-scout/walk.glb"),
			AnimState.ATTACK: preload("res://assets/models/goblin-scout/attack.glb"),
			AnimState.DEATH: preload("res://assets/models/goblin-scout/attack.glb"),
		}
		_swap_model(AnimState.IDLE)
	elif model_paths.has(enemy_type):
		# Static GLB model with tween-based animations
		anim_scenes = {}
		var scene := load(model_paths[enemy_type]) as PackedScene
		if scene:
			active_model = scene.instantiate()
			model.add_child(active_model)
			_cache_mesh_instances()
	else:
		# Unknown type fallback — use orc model
		anim_scenes = {}
		var static_scene = preload("res://assets/models/skeleton_warrior.glb")
		active_model = static_scene.instantiate()
		model.add_child(active_model)
		_cache_mesh_instances()

func _swap_model(state: AnimState) -> void:
	if anim_scenes.is_empty():
		return  # No animated models, keep whatever is there

	# Remove old model children IMMEDIATELY (not deferred) to avoid
	# visual artifacts when new children are added in the same frame
	for child in model.get_children():
		model.remove_child(child)
		child.free()

	var scene = anim_scenes.get(state)
	if scene == null:
		scene = anim_scenes.get(AnimState.IDLE)
	if scene == null:
		return

	active_model = scene.instantiate()
	model.add_child(active_model)

	active_anim_player = _find_animation_player(active_model)
	if active_anim_player:
		var anims = active_anim_player.get_animation_list()
		if anims.size() > 0:
			active_anim_player.play(anims[0])
			if state == AnimState.IDLE:
				active_anim_player.speed_scale = 0.5

	_cache_mesh_instances()

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null

func _cache_mesh_instances() -> void:
	_cached_mesh_instances.clear()
	_find_mesh_instances(model)

func _find_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_cached_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_mesh_instances(child)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if _is_stunned:
		velocity = Vector3.ZERO
		current_speed = 0.0
		move_and_slide()
		return

	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		_return_to_spawn(delta)
		return

	var dist_to_hero = global_position.distance_to(hero.global_position)
	var dist_to_spawn = global_position.distance_to(spawn_position)

	if not is_aggroed and dist_to_hero < aggro_range:
		is_aggroed = true
		var tween = create_tween()
		tween.tween_property(model, "scale", original_scale * 1.2, 0.1)
		tween.tween_property(model, "scale", original_scale, 0.1)
		_flash_color(Color(1.0, 0.2, 0.1), 0.15)

	if is_aggroed and dist_to_spawn > leash_range:
		is_aggroed = false
		current_health = max_health
		health_changed.emit(current_health, max_health)
		_return_to_spawn(delta)
		return

	var new_state := AnimState.IDLE

	if is_aggroed:
		if dist_to_hero <= attack_range:
			current_speed = 0.0
			velocity = Vector3.ZERO
			_face_position(hero.global_position, delta)
			_try_attack(hero)
			new_state = AnimState.ATTACK
		else:
			nav_agent.target_position = hero.global_position
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
			direction.y = 0
			current_speed = move_toward(current_speed, move_speed, 15.0 * delta)
			velocity = direction * current_speed
			_face_position(hero.global_position, delta)
			new_state = AnimState.WALK
	else:
		current_speed = 0.0
		velocity = Vector3.ZERO
		new_state = AnimState.IDLE

	# Update animation if state changed
	if new_state != prev_anim_state:
		prev_anim_state = new_state
		anim_state = new_state
		_swap_model(new_state)

	# Procedural walk bob
	if anim_state == AnimState.WALK and current_speed > 0.3:
		_walk_bob_time += current_speed * 0.9 * delta
		model.position.y = sin(_walk_bob_time * 8.0) * 0.04
		model.rotation.z = sin(_walk_bob_time * 4.0) * 0.02
	elif anim_state == AnimState.IDLE:
		_walk_bob_time += delta * 0.4
		model.position.y = sin(_walk_bob_time * 2.0) * 0.015
		model.rotation.z = lerp(model.rotation.z, 0.0, 6.0 * delta)
	else:
		model.position.y = lerp(model.position.y, 0.0, 8.0 * delta)
		model.rotation.z = lerp(model.rotation.z, 0.0, 8.0 * delta)

	move_and_slide()

func _return_to_spawn(delta: float) -> void:
	if global_position.distance_to(spawn_position) > 1.0:
		nav_agent.target_position = spawn_position
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		direction.y = 0
		current_speed = move_toward(current_speed, move_speed * 0.5, 10.0 * delta)
		velocity = direction * current_speed
		_face_position(spawn_position, delta)

		if anim_state != AnimState.WALK:
			anim_state = AnimState.WALK
			prev_anim_state = AnimState.WALK
			_swap_model(AnimState.WALK)
	else:
		current_speed = 0.0
		velocity = Vector3.ZERO
		if anim_state != AnimState.IDLE:
			anim_state = AnimState.IDLE
			prev_anim_state = AnimState.IDLE
			_swap_model(AnimState.IDLE)
	move_and_slide()

func _face_position(target: Vector3, delta: float) -> void:
	var look_dir = (target - global_position)
	look_dir.y = 0
	if look_dir.length_squared() < 0.001:
		return
	var target_rot = atan2(look_dir.x, look_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, 10.0 * delta)

func _try_attack(hero: Node3D) -> void:
	if not attack_timer.is_stopped():
		return
	attack_timer.start(attack_cooldown)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.2, 0.85, 1.2), 0.1)
	tween.tween_callback(func():
		if is_instance_valid(hero) and hero.has_method("take_damage"):
			hero.take_damage(attack_damage)
			# Enemy-type status effects on melee hit
			match enemy_type:
				"spider":
					StatusEffectManager.apply_poison(hero, 4.0, 6, 1.0)
				"slime":
					StatusEffectManager.apply_slow(hero, 3.0, 0.4)
				"wolf":
					if randf() < 0.25:
						StatusEffectManager.apply_slow(hero, 2.0, 0.3)
			# Elite: Venomous applies poison on any hit
			if has_meta("venomous_dot") and get_meta("venomous_dot"):
				StatusEffectManager.apply_poison(hero, 5.0, 8, 1.0)
			# Elite: Vampiric heals on damage dealt
			if has_meta("vampiric_leech"):
				var leech_pct: float = get_meta("vampiric_leech")
				var heal_amount := int(attack_damage * leech_pct)
				current_health = mini(current_health + heal_amount, max_health)
				health_changed.emit(current_health, max_health)
	)
	tween.tween_property(model, "scale", original_scale * Vector3(0.9, 1.1, 0.9), 0.1)
	tween.tween_property(model, "scale", original_scale, 0.1)

func take_damage(amount: int) -> void:
	if is_dead:
		return

	current_health -= amount
	health_changed.emit(current_health, max_health)
	is_aggroed = true

	GameManager.request_damage_number(global_position + Vector3.UP * 2.0, amount, amount > 50)
	AudioManager.on_enemy_take_damage()

	_flash_color(Color.WHITE, 0.08)

	var hit_tween = create_tween()
	hit_tween.tween_property(model, "scale", original_scale * Vector3(1.2, 0.8, 1.2), 0.05)
	hit_tween.tween_property(model, "scale", original_scale, 0.1)

	if current_health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	anim_state = AnimState.DEATH
	prev_anim_state = AnimState.DEATH

	# Swap to death animation model if available
	_swap_model(AnimState.DEATH)

	var tween = create_tween()
	# Let the death animation play briefly before collapsing
	tween.tween_interval(0.6)
	tween.tween_property(model, "scale", Vector3(1.5, 0.1, 1.5), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(model, "position:y", 0.05, 0.3)
	tween.parallel().tween_property(selection_circle, "scale", Vector3.ZERO, 0.2)
	tween.tween_interval(0.5)
	tween.tween_property(model, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tween.tween_callback(func():
		GameManager.unregister_enemy(self)
		queue_free()
	)

	GameManager.request_screen_shake(2.0, 0.1)

func _set_model_color(color: Color) -> void:
	for mi in _cached_mesh_instances:
		for i in range(mi.get_surface_override_material_count()):
			var mat = mi.get_surface_override_material(i)
			if mat == null:
				var base = mi.mesh.surface_get_material(i) if mi.mesh else null
				if base:
					mat = base.duplicate()
				else:
					mat = StandardMaterial3D.new()
				mi.set_surface_override_material(i, mat)
			if mat is StandardMaterial3D:
				mat.albedo_color = color

func _restore_model_materials() -> void:
	for mi in _cached_mesh_instances:
		for i in range(mi.get_surface_override_material_count()):
			mi.set_surface_override_material(i, null)

func _flash_color(color: Color, duration: float) -> void:
	_set_model_color(color)
	await get_tree().create_timer(duration).timeout
	if not is_dead:
		_restore_model_materials()

# ---------- BALANCE CONFIG ----------

func _apply_balance_defaults() -> void:
	if enemy_type in ["goblin_archer"]:
		max_health = BalanceConfig.ENEMY_RANGED_HP
		attack_damage = BalanceConfig.ENEMY_RANGED_DAMAGE
		move_speed = BalanceConfig.ENEMY_RANGED_SPEED
		aggro_range = BalanceConfig.ENEMY_RANGED_AGGRO_RANGE
		attack_range = BalanceConfig.ENEMY_RANGED_ATTACK_RANGE
		attack_cooldown = BalanceConfig.ENEMY_RANGED_ATTACK_COOLDOWN
	elif enemy_type in ["goblin_shaman"]:
		max_health = BalanceConfig.ENEMY_MAGE_HP
		attack_damage = BalanceConfig.ENEMY_MAGE_DAMAGE
		move_speed = BalanceConfig.ENEMY_MAGE_SPEED
		aggro_range = BalanceConfig.ENEMY_MAGE_AGGRO_RANGE
		attack_range = BalanceConfig.ENEMY_MAGE_ATTACK_RANGE
		attack_cooldown = BalanceConfig.ENEMY_MAGE_ATTACK_COOLDOWN
	else:
		max_health = BalanceConfig.ENEMY_MELEE_HP
		attack_damage = BalanceConfig.ENEMY_MELEE_DAMAGE
		move_speed = BalanceConfig.ENEMY_MELEE_SPEED
		aggro_range = BalanceConfig.ENEMY_MELEE_AGGRO_RANGE
		attack_range = BalanceConfig.ENEMY_MELEE_ATTACK_RANGE
		attack_cooldown = BalanceConfig.ENEMY_MELEE_ATTACK_COOLDOWN

# ---------- STATUS EFFECTS ----------

func _apply_status_slow(slow_pct: float) -> void:
	_slow_amount = slow_pct
	move_speed = _base_move_speed * (1.0 - _slow_amount)
	nav_agent.max_speed = move_speed

func _remove_status_slow() -> void:
	_slow_amount = 0.0
	move_speed = _base_move_speed
	nav_agent.max_speed = move_speed

func _apply_status_stun(stunned: bool) -> void:
	_is_stunned = stunned

# ---------- ELITE SYSTEM ----------

func _apply_elite_tint() -> void:
	if not has_meta("elite_tint"):
		return
	var tint: Color = get_meta("elite_tint")
	_set_model_color(tint)

func is_elite() -> bool:
	return EliteModifier.is_elite(self)

func get_elite_display_name() -> String:
	return EliteModifier.get_display_name(self)
