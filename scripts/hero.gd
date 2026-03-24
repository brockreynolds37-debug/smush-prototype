extends CharacterBody3D

## Hero unit — click-to-move, spell casting, WC3-style feel.
## Uses multiple animated GLB models (one per animation state).

signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal spell_cast(spell_index: int)
signal spell_cooldown_updated(spell_index: int, remaining: float, total: float)
signal hero_died()

@export var move_speed: float = 8.0
@export var acceleration: float = 30.0
@export var deceleration: float = 20.0
@export var rotation_speed: float = 12.0
@export var max_health: int = 500
@export var max_mana: int = 200

var current_health: int = 500
var current_mana: int = 200
var is_dead: bool = false

# Movement
var target_position: Vector3 = Vector3.ZERO
var is_moving: bool = false
var current_speed: float = 0.0
var nav_path: PackedVector3Array = []
var nav_path_index: int = 0

# Combat
var attack_target: Node3D = null
var is_attacking: bool = false
var is_casting: bool = false
var cast_timer: float = 0.0

# Spell cooldowns [Q, W, E, R]
var spell_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var spell_max_cooldowns: Array[float] = [1.5, 5.0, 8.0, 15.0]
var spell_mana_costs: Array[int] = [0, 30, 40, 60]
var spell_names: Array[String] = ["Strike", "Fireball", "Heal", "Ground Slam"]

# Animation state
enum AnimState { IDLE, WALK, ATTACK, CAST, DEATH }
var anim_state: AnimState = AnimState.IDLE
var prev_anim_state: AnimState = AnimState.IDLE

# Model container — holds the active animated GLB scene
@onready var model: Node3D = $HeroModel
@onready var selection_circle: MeshInstance3D = $SelectionCircle
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_bar: Node3D = $HealthBar
@onready var attack_timer_node: Timer = $AttackTimer
@onready var cast_timer_node: Timer = $CastTimer

# Animated GLB scenes — each has full model + one animation
var anim_scenes: Dictionary = {}
var active_model: Node3D = null
var active_anim_player: AnimationPlayer = null

var original_scale := Vector3.ONE
var _cached_mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Dictionary = {}
var _char_primary_color: Color = Color(0.15, 0.25, 0.5)
var _char_secondary_color: Color = Color(0.87, 0.72, 0.58)

func _ready() -> void:
	GameManager.register_hero(self)
	target_position = global_position

	# Load character data and apply stats
	var char_data = CharacterData.get_selected()
	max_health = char_data["stats"]["HP"]
	current_health = max_health
	max_mana = char_data["stats"]["Mana"]
	current_mana = max_mana
	_char_primary_color = char_data["color_primary"]
	_char_secondary_color = char_data["color_secondary"]

	# Build animation scene map from selected character
	var base_model = load(char_data["model_path"])
	var attack_model = load(char_data["attack_model"]) if char_data["attack_model"] != "" else base_model
	var death_model = load(char_data["death_model"]) if char_data["death_model"] != "" else base_model
	var cast_model = load(char_data["cast_model"]) if char_data["cast_model"] != "" else base_model

	anim_scenes = {
		AnimState.IDLE: base_model,
		AnimState.WALK: base_model,
		AnimState.ATTACK: attack_model,
		AnimState.CAST: cast_model,
		AnimState.DEATH: death_model,
	}

	# Set up the initial model
	_swap_model(AnimState.IDLE, false)  # Don't play for idle — we pause it
	original_scale = model.scale

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	health_changed.emit(current_health, max_health)
	mana_changed.emit(current_mana, max_mana)

	# Mana regen timer
	var mana_timer = Timer.new()
	mana_timer.wait_time = 1.0
	mana_timer.autostart = true
	mana_timer.timeout.connect(_on_mana_regen)
	add_child(mana_timer)

func _swap_model(state: AnimState, play_anim: bool = true) -> void:
	# Remove old model children IMMEDIATELY (not deferred) to avoid
	# visual artifacts when new children are added in the same frame
	for child in model.get_children():
		model.remove_child(child)
		child.free()

	# Instance the GLB scene for this state
	var scene = anim_scenes.get(state)
	if scene == null:
		scene = anim_scenes[AnimState.IDLE]

	active_model = scene.instantiate()
	model.add_child(active_model)

	# Find the AnimationPlayer inside the GLB scene
	active_anim_player = _find_animation_player(active_model)

	if active_anim_player and play_anim:
		# Play the first animation found
		var anims = active_anim_player.get_animation_list()
		if anims.size() > 0:
			active_anim_player.play(anims[0])
	elif active_anim_player and not play_anim:
		# For idle: play walk anim at very slow speed for subtle movement
		var anims = active_anim_player.get_animation_list()
		if anims.size() > 0:
			active_anim_player.play(anims[0])
			active_anim_player.speed_scale = 0.3

	# Recache mesh instances for color flash
	_cache_mesh_instances()

	# Apply programmatic materials to Fat Nate (untextured GLB models)
	_apply_hero_materials()

func _apply_hero_materials() -> void:
	for mi in _cached_mesh_instances:
		for i in range(mi.mesh.get_surface_count() if mi.mesh else 0):
			var mat = StandardMaterial3D.new()
			var surface_name = mi.mesh.surface_get_material(i).resource_name if mi.mesh.surface_get_material(i) else ""
			if "Dots" in surface_name or i == 0:
				mat.albedo_color = _char_primary_color
				mat.roughness = 0.8
			else:
				mat.albedo_color = _char_secondary_color
				mat.roughness = 0.7
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.15
			mat.emission_energy_multiplier = 0.3
			mi.set_surface_override_material(i, mat)

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
	_original_materials.clear()
	_find_mesh_instances(model)
	for mi in _cached_mesh_instances:
		var mats: Array = []
		for i in range(mi.get_surface_override_material_count()):
			var mat = mi.get_surface_override_material(i)
			if mat == null:
				mat = mi.mesh.surface_get_material(i) if mi.mesh else null
			mats.append(mat)
		_original_materials[mi] = mats

func _find_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_cached_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_mesh_instances(child)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_process_cooldowns(delta)
	_process_casting(delta)

	if not is_casting and not is_attacking:
		_process_movement(delta)

	_update_animation_state()

func _process_movement(delta: float) -> void:
	if not is_moving and attack_target == null:
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		if current_speed > 0:
			velocity = velocity.normalized() * current_speed
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		return

	if attack_target != null and is_instance_valid(attack_target):
		nav_agent.target_position = attack_target.global_position
		if global_position.distance_to(attack_target.global_position) < 2.5:
			is_moving = false
			current_speed = 0.0
			velocity = Vector3.ZERO
			_face_position(attack_target.global_position, delta)
			_perform_melee_attack()
			move_and_slide()
			return

	if nav_agent.is_navigation_finished():
		is_moving = false
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		velocity = velocity.normalized() * current_speed if current_speed > 0 else Vector3.ZERO
		move_and_slide()
		return

	var next_pos = nav_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	direction.y = 0

	current_speed = move_toward(current_speed, move_speed, acceleration * delta)
	velocity = direction * current_speed

	_face_position(global_position + direction, delta)

	move_and_slide()

func _face_position(target: Vector3, delta: float) -> void:
	var look_dir = (target - global_position)
	look_dir.y = 0
	if look_dir.length_squared() < 0.001:
		return
	var target_rot = atan2(look_dir.x, look_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, rotation_speed * delta)

func move_to(world_pos: Vector3) -> void:
	if is_dead or is_casting:
		return
	target_position = world_pos
	nav_agent.target_position = world_pos
	is_moving = true
	is_attacking = false
	attack_target = null
	_play_acknowledge_bounce()

func _play_acknowledge_bounce() -> void:
	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.85, 1.2, 0.85), 0.06)
	tween.tween_property(model, "scale", original_scale * Vector3(1.1, 0.9, 1.1), 0.06)
	tween.tween_property(model, "scale", original_scale, 0.08)

func _perform_melee_attack() -> void:
	if not attack_timer_node.is_stopped():
		return
	is_attacking = true
	anim_state = AnimState.ATTACK
	attack_timer_node.start(0.8)

	# Swap to sword_slash animation model
	_swap_model(AnimState.ATTACK, true)
	AudioManager.on_hero_attack()

	# Squash/stretch juice on top of the animation
	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.3, 0.8, 1.3), 0.15)
	tween.tween_callback(_apply_melee_damage)
	tween.tween_property(model, "scale", original_scale * Vector3(0.9, 1.15, 0.9), 0.1)
	tween.tween_property(model, "scale", original_scale, 0.1)
	tween.tween_callback(func(): is_attacking = false)

func _get_melee_damage() -> int:
	var base := 35
	var str_bonus = XpManager.bonus_str * 3  # +3 damage per bonus STR
	return base + str_bonus

func _get_spell_power() -> float:
	# Returns a multiplier: 1.0 at base, scales with bonus INT
	return 1.0 + XpManager.bonus_int * 0.08  # +8% per bonus INT

func _apply_melee_damage() -> void:
	if attack_target and is_instance_valid(attack_target) and attack_target.has_method("take_damage"):
		attack_target.take_damage(_get_melee_damage())
		GameManager.request_screen_shake(3.0, 0.15)

func set_attack_target(target: Node3D) -> void:
	attack_target = target
	if target:
		is_moving = true
		nav_agent.target_position = target.global_position
		GameManager.hero_target_changed.emit(target)

# ---------- SPELL SYSTEM ----------

func cast_spell(index: int) -> void:
	if is_dead or is_casting:
		return
	if spell_cooldowns[index] > 0:
		return
	if current_mana < spell_mana_costs[index]:
		return

	match index:
		0: _cast_strike()
		1: _start_fireball_targeting()
		2: _cast_heal()
		3: _cast_ground_slam()

func _cast_strike() -> void:
	var target = GameManager.get_nearest_enemy(global_position, 3.5)
	if target:
		set_attack_target(target)
		spell_cooldowns[0] = spell_max_cooldowns[0]
		spell_cast.emit(0)
	else:
		target = GameManager.get_nearest_enemy(global_position, 15.0)
		if target:
			set_attack_target(target)

func _start_fireball_targeting() -> void:
	GameManager.is_targeting_spell = true
	GameManager.targeting_spell_id = 1

func cast_fireball_at(target_pos: Vector3) -> void:
	if spell_cooldowns[1] > 0 or current_mana < spell_mana_costs[1]:
		return
	is_casting = true
	is_moving = false
	current_speed = 0.0
	velocity = Vector3.ZERO
	_face_position(target_pos, 1.0)

	current_mana -= spell_mana_costs[1]
	mana_changed.emit(current_mana, max_mana)
	spell_cooldowns[1] = spell_max_cooldowns[1]
	spell_cast.emit(1)

	anim_state = AnimState.CAST
	AudioManager.on_hero_cast_fireball()
	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.8, 1.3, 0.8), 0.2)
	tween.tween_callback(func(): _spawn_fireball(target_pos))
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(func(): is_casting = false)

	_flash_color(Color(1.0, 0.5, 0.0), 0.3)

func _spawn_fireball(target_pos: Vector3) -> void:
	var fireball_scene = preload("res://scenes/fireball.tscn")
	var fireball = fireball_scene.instantiate()
	get_tree().root.add_child(fireball)
	fireball.global_position = global_position + Vector3.UP * 1.5
	fireball.launch(target_pos)

func _cast_heal() -> void:
	if current_health >= max_health:
		return

	is_casting = true
	is_moving = false
	current_speed = 0.0
	velocity = Vector3.ZERO

	current_mana -= spell_mana_costs[2]
	mana_changed.emit(current_mana, max_mana)
	spell_cooldowns[2] = spell_max_cooldowns[2]
	spell_cast.emit(2)

	anim_state = AnimState.CAST
	_set_model_color(Color(0.2, 1.0, 0.3))
	AudioManager.on_hero_cast_heal()

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * 1.2, 0.3)
	tween.tween_callback(func():
		var heal_amount = int(150 * _get_spell_power())
		current_health = mini(current_health + heal_amount, max_health)
		health_changed.emit(current_health, max_health)
		GameManager.request_damage_number(global_position + Vector3.UP * 2.5, heal_amount, false)
		_spawn_heal_particles()
	)
	tween.tween_property(model, "scale", original_scale, 0.2)
	tween.tween_callback(func():
		is_casting = false
		_restore_model_materials()
	)

func _spawn_heal_particles() -> void:
	var particles = preload("res://scenes/heal_particles.tscn").instantiate()
	add_child(particles)
	particles.position = Vector3.ZERO
	particles.emitting = true
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func _cast_ground_slam() -> void:
	is_casting = true
	is_moving = false
	current_speed = 0.0
	velocity = Vector3.ZERO

	current_mana -= spell_mana_costs[3]
	mana_changed.emit(current_mana, max_mana)
	spell_cooldowns[3] = spell_max_cooldowns[3]
	spell_cast.emit(3)

	anim_state = AnimState.CAST
	AudioManager.on_hero_cast_ground_slam()

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.7, 1.5, 0.7), 0.4)
	_set_model_color(Color(1.0, 0.8, 0.0))
	tween.tween_property(model, "scale", original_scale * Vector3(1.5, 0.6, 1.5), 0.1)
	tween.tween_callback(func():
		GameManager.request_screen_shake(8.0, 0.4)
		var slam_damage = int(80 * _get_spell_power())
		var enemies = GameManager.get_enemies_in_range(global_position, 6.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(slam_damage)
		_spawn_slam_particles()
	)
	tween.tween_property(model, "scale", original_scale, 0.3)
	tween.tween_callback(func():
		is_casting = false
		_restore_model_materials()
	)

func _spawn_slam_particles() -> void:
	var particles = preload("res://scenes/slam_particles.tscn").instantiate()
	get_tree().root.add_child(particles)
	particles.global_position = global_position
	particles.emitting = true
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

# ---------- DAMAGE / DEATH ----------

func take_damage(amount: int) -> void:
	if is_dead:
		return
	current_health -= amount
	health_changed.emit(current_health, max_health)
	GameManager.request_damage_number(global_position + Vector3.UP * 2.5, amount, false)
	AudioManager.on_hero_take_damage()

	_flash_color(Color.WHITE, 0.08)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.15, 0.85, 1.15), 0.05)
	tween.tween_property(model, "scale", original_scale, 0.1)

	if current_health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	is_moving = false
	anim_state = AnimState.DEATH
	velocity = Vector3.ZERO

	# Swap to death model
	_swap_model(AnimState.DEATH, true)

	var tween = create_tween()
	tween.tween_interval(1.5)  # Let death animation play
	tween.tween_property(model, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	hero_died.emit()

# ---------- ANIMATION STATE MACHINE ----------

func _update_animation_state() -> void:
	var new_state: AnimState

	if is_dead:
		new_state = AnimState.DEATH
	elif is_casting:
		new_state = AnimState.CAST
	elif is_attacking:
		new_state = AnimState.ATTACK
	elif current_speed > 0.5:
		new_state = AnimState.WALK
	else:
		new_state = AnimState.IDLE

	# Only swap model when state changes (avoid constant re-instancing)
	if new_state != prev_anim_state:
		prev_anim_state = new_state
		anim_state = new_state

		match new_state:
			AnimState.IDLE:
				_swap_model(AnimState.IDLE, false)  # Slow walk as idle
			AnimState.WALK:
				_swap_model(AnimState.WALK, true)
				if active_anim_player:
					active_anim_player.speed_scale = 1.0
			AnimState.ATTACK:
				pass  # Handled in _perform_melee_attack()
			AnimState.CAST:
				_swap_model(AnimState.CAST, true)
			AnimState.DEATH:
				pass  # Handled in _die()
	else:
		anim_state = new_state

# ---------- UTILITIES ----------

func _process_cooldowns(delta: float) -> void:
	for i in range(4):
		if spell_cooldowns[i] > 0:
			spell_cooldowns[i] = maxf(spell_cooldowns[i] - delta, 0.0)
			spell_cooldown_updated.emit(i, spell_cooldowns[i], spell_max_cooldowns[i])

func _process_casting(_delta: float) -> void:
	pass

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
	# Re-apply hero materials instead of clearing to null, since Fat Nate
	# has no embedded textures and would revert to default gray
	_apply_hero_materials()

func _flash_color(color: Color, duration: float) -> void:
	_set_model_color(color)
	await get_tree().create_timer(duration).timeout
	if not is_dead:
		_restore_model_materials()

func _on_mana_regen() -> void:
	if not is_dead and current_mana < max_mana:
		current_mana = mini(current_mana + 5, max_mana)
		mana_changed.emit(current_mana, max_mana)
