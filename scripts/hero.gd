extends CharacterBody3D

## Hero unit — click-to-move, spell casting, WC3-style feel.
## Uses multiple animated GLB models (one per animation state).

signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal spell_cast(spell_index: int)
signal spell_cooldown_updated(spell_index: int, remaining: float, total: float)
signal spell_unlocked(spell_index: int)
signal hero_died()

@export var move_speed: float = 8.0
@export var acceleration: float = 25.0
@export var deceleration: float = 35.0
@export var rotation_speed: float = 10.0
@export var approach_distance: float = 2.0  # Start slowing within this range of target
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
var _spell_set_index: int = 0  # 0 = default, 1 = alternate

# Spell unlock levels: spells 0-1 at start, spell 2 at level 5, spell 3 at level 10
var spell_unlock_levels: Array[int] = [1, 1, 5, 10]
var spells_unlocked: Array[bool] = [true, true, false, false]

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

# Status effects
var _base_move_speed: float = 8.0
var _is_stunned: bool = false
var _slow_amount: float = 0.0  # 0.0 = no slow, 0.5 = 50% slow

# Innate trait
var _trait_id: String = ""
var _phase_walk_charges: int = 5
var _phase_walk_max: int = 5

# Equipment stats (set by InventoryUI._apply_equipment_stats)
var equipment_damage_bonus: int = 0
var equipment_str_bonus: int = 0
var equipment_int_bonus: int = 0
var equipment_dex_bonus: int = 0
var equipment_con_bonus: int = 0
var equipment_crit_bonus: int = 0
var equipment_spell_power_bonus: int = 0
var equipment_armor_bonus: int = 0
var equipment_hp_bonus: int = 0
var equipment_speed_bonus: int = 0
var _base_max_health: int = 500
var _last_hit_was_crit: bool = false
var _walk_bob_time: float = 0.0

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

	# Load spell set from character selection
	_spell_set_index = CharacterData.selected_spell_set
	var spell_set = CharacterData.get_selected_spell_set()
	if spell_set.size() > 0:
		var names_arr = spell_set.get("names", [])
		spell_names = [names_arr[0] if names_arr.size() > 0 else "Strike",
					   names_arr[1] if names_arr.size() > 1 else "Fireball",
					   names_arr[2] if names_arr.size() > 2 else "Heal",
					   names_arr[3] if names_arr.size() > 3 else "Ground Slam"]
		var cd_arr = spell_set.get("cooldowns", [])
		spell_max_cooldowns = [cd_arr[0] if cd_arr.size() > 0 else 1.5,
							   cd_arr[1] if cd_arr.size() > 1 else 5.0,
							   cd_arr[2] if cd_arr.size() > 2 else 8.0,
							   cd_arr[3] if cd_arr.size() > 3 else 15.0]
		var mc_arr = spell_set.get("mana_costs", [])
		spell_mana_costs = [mc_arr[0] if mc_arr.size() > 0 else 0,
							mc_arr[1] if mc_arr.size() > 1 else 30,
							mc_arr[2] if mc_arr.size() > 2 else 40,
							mc_arr[3] if mc_arr.size() > 3 else 60]

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

	_base_move_speed = move_speed
	_base_max_health = max_health

	# Load innate trait
	_trait_id = char_data.get("trait_id", "")
	_apply_trait_passives()

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	health_changed.emit(current_health, max_health)
	mana_changed.emit(current_mana, max_mana)

	# Connect trait signals
	if _trait_id == "arcane_surge":
		GameManager.enemy_died.connect(_on_trait_enemy_died)
	if _trait_id == "adaptable" or _trait_id == "phase_walk":
		FloorManager.floor_changed.connect(_on_trait_floor_changed)

	# Spell unlock check (in case starting level > 1 from save)
	_refresh_spell_unlocks()
	XpManager.level_up.connect(_on_level_up_spell_check)

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

	# Stunned: can't do anything, just stand there
	if _is_stunned:
		velocity = Vector3.ZERO
		current_speed = 0.0
		move_and_slide()
		return

	_process_cooldowns(delta)
	_process_casting(delta)

	if not is_casting and not is_attacking:
		_process_movement(delta)

	_update_animation_state()

func _process_movement(delta: float) -> void:
	if not is_moving and attack_target == null:
		# Smooth ease-out deceleration (faster at high speed, gentle at low)
		var decel_factor := 1.0 + (current_speed / move_speed) * 2.0
		current_speed = move_toward(current_speed, 0.0, deceleration * decel_factor * delta)
		if current_speed > 0.1:
			velocity = velocity.normalized() * current_speed
		else:
			current_speed = 0.0
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
		var decel_factor := 1.0 + (current_speed / move_speed) * 2.0
		current_speed = move_toward(current_speed, 0.0, deceleration * decel_factor * delta)
		velocity = velocity.normalized() * current_speed if current_speed > 0.1 else Vector3.ZERO
		if current_speed < 0.1:
			current_speed = 0.0
			velocity = Vector3.ZERO
		move_and_slide()
		return

	var next_pos = nav_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	direction.y = 0

	# Approach slowdown — ease into target position
	var target_speed := move_speed
	var dist_to_target := global_position.distance_to(nav_agent.target_position)
	if dist_to_target < approach_distance and attack_target == null:
		var approach_ratio := clampf(dist_to_target / approach_distance, 0.15, 1.0)
		target_speed = move_speed * approach_ratio

	# Ease-in acceleration (snappy start, smooth ramp)
	var speed_ratio := current_speed / move_speed if move_speed > 0 else 0.0
	var accel_factor := 1.5 + (1.0 - speed_ratio) * 2.0  # Faster accel at low speed
	current_speed = move_toward(current_speed, target_speed, acceleration * accel_factor * delta)
	velocity = direction * current_speed

	_face_position(global_position + direction, delta)

	move_and_slide()

func _face_position(target: Vector3, delta: float) -> void:
	var look_dir = (target - global_position)
	look_dir.y = 0
	if look_dir.length_squared() < 0.001:
		return
	var target_rot = atan2(look_dir.x, look_dir.z)
	# Speed-dependent rotation: turn faster when slow, more momentum when fast
	var speed_ratio := clampf(current_speed / move_speed, 0.0, 1.0) if move_speed > 0 else 0.0
	var rot_factor := lerpf(1.4, 0.7, speed_ratio)  # 1.4x at standstill, 0.7x at full speed
	rotation.y = lerp_angle(rotation.y, target_rot, rotation_speed * rot_factor * delta)

func move_to(world_pos: Vector3) -> void:
	if is_dead or is_casting:
		return
	target_position = world_pos
	nav_agent.target_position = world_pos
	is_moving = true
	is_attacking = false
	attack_target = null
	_play_acknowledge_bounce()
	TutorialManager.notify_event("hero_moved")

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
	_last_hit_was_crit = false
	var base := 35
	var str_bonus = (XpManager.bonus_str + equipment_str_bonus) * 3  # +3 damage per STR
	var dmg := base + str_bonus + equipment_damage_bonus
	# Crit chance from equipment
	if equipment_crit_bonus > 0 and randf() * 100.0 < equipment_crit_bonus:
		dmg = int(dmg * 1.8)
		_last_hit_was_crit = true
	# Berserker Rage: +50% damage below 30% HP
	if _trait_id == "berserker_rage" and float(current_health) / float(max_health) < 0.3:
		dmg = int(dmg * 1.5)
	return dmg

func _get_spell_power() -> float:
	# Returns a multiplier: 1.0 at base, scales with bonus INT + equipment
	var power := 1.0 + (XpManager.bonus_int + equipment_int_bonus) * 0.08  # +8% per INT
	# Equipment spell power: +1% per point
	power += equipment_spell_power_bonus * 0.01
	# Berserker Rage: +50% spell power below 30% HP
	if _trait_id == "berserker_rage" and float(current_health) / float(max_health) < 0.3:
		power *= 1.5
	return power

func _apply_melee_damage() -> void:
	if attack_target and is_instance_valid(attack_target) and attack_target.has_method("take_damage"):
		var dmg = _get_melee_damage()
		attack_target.take_damage(dmg)
		RunStats.record_damage_dealt(dmg)
		TutorialManager.notify_event("enemy_hit")
		if _last_hit_was_crit:
			GameManager.request_screen_shake(6.0, 0.25)
			GameManager.request_hitstop(0.08)
			var dir = (attack_target.global_position - global_position).normalized()
			GameManager.request_camera_punch(dir, 5.0)
			ScreenEffects.screen_flash(Color(1.0, 0.9, 0.7, 0.3), 0.12)
		else:
			GameManager.request_screen_shake(3.0, 0.15)

func set_attack_target(target: Node3D) -> void:
	attack_target = target
	if target:
		is_moving = true
		nav_agent.target_position = target.global_position
		GameManager.hero_target_changed.emit(target)

# ---------- SPELL SYSTEM ----------

func is_spell_unlocked(index: int) -> bool:
	return index >= 0 and index < spells_unlocked.size() and spells_unlocked[index]

func cast_spell(index: int) -> void:
	if is_dead or is_casting:
		return
	if not is_spell_unlocked(index):
		return
	if spell_cooldowns[index] > 0:
		return
	if current_mana < spell_mana_costs[index]:
		return

	TutorialManager.notify_event("spell_cast")
	if _spell_set_index == 0:
		match index:
			0: _cast_strike()
			1: _start_fireball_targeting()
			2: _cast_heal()
			3: _cast_ground_slam()
	else:
		_cast_alt_spell(index)

func _cast_strike() -> void:
	var range_mult := 1.3 if _trait_id == "eagle_eye" else 1.0
	var target = GameManager.get_nearest_enemy(global_position, 3.5 * range_mult)
	if target:
		set_attack_target(target)
		spell_cooldowns[0] = spell_max_cooldowns[0]
		spell_cast.emit(0)
		AudienceManager.on_spell_cast(0)
		RunStats.record_spell_cast(0)
	else:
		target = GameManager.get_nearest_enemy(global_position, 15.0 * range_mult)
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
	AudienceManager.on_spell_cast(1)
	RunStats.record_spell_cast(1)

	anim_state = AnimState.CAST
	AudioManager.on_hero_cast_fireball()
	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.8, 1.3, 0.8), 0.2)
	tween.tween_callback(func(): _spawn_fireball(target_pos))
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(func(): is_casting = false)

	_flash_color(Color(1.0, 0.5, 0.0), 0.3)
	VFXManager.spawn_spell_impact(target_pos, Color(1.0, 0.5, 0.0), 3.0)

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
	AudienceManager.on_spell_cast(2)
	RunStats.record_spell_cast(2)

	anim_state = AnimState.CAST
	_set_model_color(Color(0.2, 1.0, 0.3))
	AudioManager.on_hero_cast_heal()

	var hp_ratio_before := float(current_health) / float(max_health)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * 1.2, 0.3)
	tween.tween_callback(func():
		var heal_amount = int(150 * _get_spell_power())
		Narrator.on_hero_healed(hp_ratio_before)
		current_health = mini(current_health + heal_amount, max_health)
		health_changed.emit(current_health, max_health)
		GameManager.request_damage_number(global_position + Vector3.UP * 2.5, heal_amount, false)
		_spawn_heal_particles()
		VFXManager.spawn_heal_glow(self)
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
	AudienceManager.on_spell_cast(3)
	RunStats.record_spell_cast(3)

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
				RunStats.record_damage_dealt(slam_damage)
			# Ground slam applies slow + stun
			StatusEffectManager.apply_slow(e, 3.0, 0.5)
			StatusEffectManager.apply_stun(e, 1.0)
		AudienceManager.on_aoe_hit(enemies.size())
		# Damage nearby breakables (barrels)
		_damage_nearby_interactables(slam_damage, 6.0)
		_spawn_slam_particles()
		VFXManager.spawn_spell_impact(global_position, Color(1.0, 0.8, 0.0), 6.0)
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

	# Phase Walk: chance to dodge entirely (uses charges)
	if _trait_id == "phase_walk" and _phase_walk_charges > 0:
		if randf() < 0.25:
			_phase_walk_charges -= 1
			GameManager.request_damage_number(global_position + Vector3.UP * 2.5, 0, false)
			_flash_color(Color(0.5, 0.3, 1.0), 0.15)
			return

	# Exoskeleton: flat 20% damage reduction
	if _trait_id == "exoskeleton":
		amount = maxi(int(amount * 0.8), 1)

	# Equipment armor: flat reduction (1 armor = 1 less damage, min 1)
	if equipment_armor_bonus > 0:
		amount = maxi(amount - equipment_armor_bonus, 1)

	current_health -= amount
	health_changed.emit(current_health, max_health)
	GameManager.request_damage_number(global_position + Vector3.UP * 2.5, amount, false)
	AudioManager.on_hero_take_damage()
	RunStats.record_damage_taken(amount)

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

		# Blend transition: brief scale squeeze before state change
		if new_state == AnimState.WALK and anim_state != AnimState.DEATH:
			_transition_blend(0.06)

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

	# Procedural walk bob (subtle Y oscillation while moving)
	if anim_state == AnimState.WALK and current_speed > 0.5:
		_walk_bob_time += current_speed * 0.8 * get_physics_process_delta_time()
		var bob_y := sin(_walk_bob_time * 8.0) * 0.06
		var lean := sin(_walk_bob_time * 4.0) * 0.03
		model.position.y = bob_y
		model.rotation.z = lean
	elif anim_state == AnimState.IDLE:
		# Gentle idle breathing
		_walk_bob_time += get_physics_process_delta_time() * 0.5
		model.position.y = sin(_walk_bob_time * 2.0) * 0.02
		model.rotation.z = lerp(model.rotation.z, 0.0, 8.0 * get_physics_process_delta_time())
	else:
		model.position.y = lerp(model.position.y, 0.0, 10.0 * get_physics_process_delta_time())
		model.rotation.z = lerp(model.rotation.z, 0.0, 10.0 * get_physics_process_delta_time())

func _transition_blend(duration: float) -> void:
	# Quick squash-stretch transition between animation states
	var tw = create_tween()
	tw.tween_property(model, "scale", original_scale * Vector3(1.05, 0.92, 1.05), duration * 0.5)
	tw.tween_property(model, "scale", original_scale, duration * 0.5)

# ---------- UTILITIES ----------

func _process_cooldowns(delta: float) -> void:
	# Arcane Surge: cooldowns tick 15% faster
	var cd_delta := delta * 1.15 if _trait_id == "arcane_surge" else delta
	for i in range(4):
		if spell_cooldowns[i] > 0:
			spell_cooldowns[i] = maxf(spell_cooldowns[i] - cd_delta, 0.0)
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

# ---------- INTERACTABLE DAMAGE ----------

func _damage_nearby_interactables(damage: int, radius: float) -> void:
	var interactables := get_tree().get_nodes_in_group("interactables")
	for obj in interactables:
		if not is_instance_valid(obj):
			continue
		if global_position.distance_to(obj.global_position) <= radius:
			if obj.has_method("take_damage"):
				obj.take_damage(damage)

# ---------- EQUIPMENT STATS ----------

func apply_equipment_stats(totals: Dictionary) -> void:
	# Remove old HP bonus before applying new one
	var old_hp_bonus := equipment_hp_bonus

	equipment_damage_bonus = totals.get("damage", 0)
	equipment_str_bonus = totals.get("str", 0)
	equipment_int_bonus = totals.get("int", 0)
	equipment_dex_bonus = totals.get("dex", 0)
	equipment_con_bonus = totals.get("con", 0)
	equipment_crit_bonus = totals.get("crit", 0)
	equipment_spell_power_bonus = totals.get("spell_power", 0)
	equipment_armor_bonus = totals.get("armor", 0)
	equipment_hp_bonus = totals.get("hp", 0)
	equipment_speed_bonus = totals.get("speed", 0)

	# HP bonus: adjust max_health and current_health proportionally
	var hp_diff := equipment_hp_bonus - old_hp_bonus
	if hp_diff != 0:
		max_health = _base_max_health + equipment_hp_bonus
		current_health = clampi(current_health + hp_diff, 1, max_health)
		health_changed.emit(current_health, max_health)

	# Speed bonus: percentage-based on base move speed
	var speed_mult := 1.0 + equipment_speed_bonus * 0.01
	move_speed = _base_move_speed * speed_mult * (1.0 - _slow_amount)
	nav_agent.max_speed = move_speed

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
	if stunned:
		is_moving = false
		is_casting = false
		is_attacking = false
		current_speed = 0.0
		velocity = Vector3.ZERO

# ---------- INNATE TRAITS ----------

func _apply_trait_passives() -> void:
	match _trait_id:
		"eagle_eye":
			# +30% attack approach range (lets hero engage from farther)
			approach_distance = approach_distance * 1.3
		"phase_walk":
			_phase_walk_charges = _phase_walk_max

func _on_trait_enemy_died(_enemy: Node3D) -> void:
	if is_dead:
		return
	# Arcane Surge: restore 20 mana on kill
	if _trait_id == "arcane_surge":
		current_mana = mini(current_mana + 20, max_mana)
		mana_changed.emit(current_mana, max_mana)

func _on_trait_floor_changed(_floor_number: int) -> void:
	if is_dead:
		return
	match _trait_id:
		"adaptable":
			# +1 to a random core stat per floor
			var stat_roll := randi() % 4
			match stat_roll:
				0:
					XpManager.bonus_str += 1
				1:
					XpManager.bonus_dex += 1
				2:
					XpManager.bonus_con += 1
					max_health += 15
					current_health += 15
					health_changed.emit(current_health, max_health)
				3:
					XpManager.bonus_int += 1
		"phase_walk":
			# Refresh dodge charges each floor
			_phase_walk_charges = _phase_walk_max

# ---------- SPELL UNLOCKS ----------

func _refresh_spell_unlocks() -> void:
	for i in range(spells_unlocked.size()):
		if not spells_unlocked[i] and XpManager.current_level >= spell_unlock_levels[i]:
			spells_unlocked[i] = true
			spell_unlocked.emit(i)

func _on_level_up_spell_check(_new_level: int) -> void:
	_refresh_spell_unlocks()

# ========== ALTERNATE SPELL SYSTEM ==========
# Each character has a unique alt spell set. Dispatches by character ID + spell index.

var _alt_targeted_index: int = -1  # Which alt spell is awaiting ground target
var _buff_war_cry: bool = false
var _buff_blood_frenzy: bool = false
var _buff_holy_shield: bool = false
var _buff_smoke_bomb: bool = false

func _start_alt_targeting(spell_index: int) -> void:
	_alt_targeted_index = spell_index
	GameManager.is_targeting_spell = true
	GameManager.targeting_spell_id = 100  # Generic alt targeted

func cast_alt_targeted_at(target_pos: Vector3) -> void:
	var idx = _alt_targeted_index
	_alt_targeted_index = -1
	if idx < 0:
		return
	var char_id = CharacterData.get_selected()["id"]
	match char_id:
		"fat_nate":
			if idx == 3:
				_alt_earthquake_at(target_pos)
		"knight":
			if idx == 2:
				_alt_consecrate_at(target_pos)
			elif idx == 3:
				_alt_divine_judgment_at(target_pos)
		"barbarian":
			pass  # No targeted alt spells
		"mage":
			if idx == 0:
				_alt_arcane_bolt_at(target_pos)
			elif idx == 2:
				_alt_chain_lightning_at(target_pos)
			elif idx == 3:
				_alt_meteor_at(target_pos)
		"ranger":
			if idx == 0:
				_alt_aimed_shot_at(target_pos)
			elif idx == 1:
				_alt_trap_at(target_pos)
			elif idx == 2:
				_alt_volley_at(target_pos)
			elif idx == 3:
				_alt_snipe_at(target_pos)
		"rogue":
			if idx == 3:
				_alt_shadow_strike_at(target_pos)

func _cast_alt_spell(index: int) -> void:
	var char_id = CharacterData.get_selected()["id"]
	match char_id:
		"fat_nate":
			_cast_alt_fat_nate(index)
		"knight":
			_cast_alt_knight(index)
		"barbarian":
			_cast_alt_barbarian(index)
		"mage":
			_cast_alt_mage(index)
		"ranger":
			_cast_alt_ranger(index)
		"rogue":
			_cast_alt_rogue(index)

# ---- Shared alt spell helpers ----

func _consume_spell(index: int) -> void:
	current_mana -= spell_mana_costs[index]
	mana_changed.emit(current_mana, max_mana)
	spell_cooldowns[index] = spell_max_cooldowns[index]
	spell_cast.emit(index)
	AudienceManager.on_spell_cast(index)
	RunStats.record_spell_cast(index)

func _begin_cast() -> void:
	is_casting = true
	is_moving = false
	current_speed = 0.0
	velocity = Vector3.ZERO
	anim_state = AnimState.CAST

func _end_cast() -> void:
	is_casting = false
	_restore_model_materials()

# ---- FAT NATE: Warlord (Charge, War Cry, Shield Bash, Earthquake) ----

func _cast_alt_fat_nate(index: int) -> void:
	match index:
		0: _alt_charge()
		1: _alt_war_cry()
		2: _alt_shield_bash()
		3: _start_alt_targeting(3)  # Earthquake needs ground target

func _alt_charge() -> void:
	var range_mult := 1.3 if _trait_id == "eagle_eye" else 1.0
	var target = GameManager.get_nearest_enemy(global_position, 12.0 * range_mult)
	if target == null:
		return
	_consume_spell(0)
	_begin_cast()
	AudioManager.play_sfx("ground_slam", 0.8)
	_flash_color(Color(0.9, 0.6, 0.2), 0.15)

	var dir = (target.global_position - global_position).normalized()
	var charge_dest = target.global_position - dir * 1.5
	var tween = create_tween()
	tween.tween_property(self, "global_position", charge_dest, 0.25).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		_face_position(target.global_position, 1.0)
		var dmg = int(_get_melee_damage() * 1.5)
		if target and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(dmg)
			RunStats.record_damage_dealt(dmg)
			StatusEffectManager.apply_stun(target, 0.8)
		GameManager.request_screen_shake(5.0, 0.2)
		VFXManager.spawn_impact_sparks(global_position + Vector3.UP, Color(0.9, 0.6, 0.2))
	)
	tween.tween_property(model, "scale", original_scale * Vector3(1.2, 0.8, 1.2), 0.1)
	tween.tween_property(model, "scale", original_scale, 0.1)
	tween.tween_callback(_end_cast)

func _alt_war_cry() -> void:
	_consume_spell(1)
	_begin_cast()
	AudioManager.play_sfx("boss_roar", 0.7)
	_set_model_color(Color(1.0, 0.5, 0.1))

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * 1.3, 0.2)
	tween.tween_callback(func():
		# Stun nearby enemies
		var enemies = GameManager.get_enemies_in_range(global_position, 5.0)
		for e in enemies:
			StatusEffectManager.apply_stun(e, 1.0)
		VFXManager.spawn_spell_impact(global_position, Color(1.0, 0.6, 0.2), 5.0)
		GameManager.request_screen_shake(4.0, 0.2)
		# Damage buff for 8s
		_buff_war_cry = true
		get_tree().create_timer(8.0).timeout.connect(func(): _buff_war_cry = false)
	)
	tween.tween_property(model, "scale", original_scale, 0.2)
	tween.tween_callback(_end_cast)

func _alt_shield_bash() -> void:
	var range_mult := 1.3 if _trait_id == "eagle_eye" else 1.0
	var target = GameManager.get_nearest_enemy(global_position, 3.5 * range_mult)
	if target == null:
		return
	_consume_spell(2)
	_begin_cast()
	_face_position(target.global_position, 1.0)
	AudioManager.on_hero_attack()

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.3, 0.85, 1.3), 0.12)
	tween.tween_callback(func():
		var dmg = int(_get_melee_damage() * 1.2)
		if target and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(dmg)
			RunStats.record_damage_dealt(dmg)
			StatusEffectManager.apply_stun(target, 1.5)
			# Knockback
			var kb_dir = (target.global_position - global_position).normalized()
			if target.has_method("set"):
				target.global_position += kb_dir * 2.0
		GameManager.request_screen_shake(4.0, 0.15)
		VFXManager.spawn_impact_sparks(target.global_position if target and is_instance_valid(target) else global_position, Color(0.7, 0.7, 0.8))
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(_end_cast)

func _alt_earthquake_at(target_pos: Vector3) -> void:
	_consume_spell(3)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.on_hero_cast_ground_slam()

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.7, 1.4, 0.7), 0.35)
	_set_model_color(Color(0.8, 0.5, 0.1))
	tween.tween_property(model, "scale", original_scale * Vector3(1.5, 0.5, 1.5), 0.1)
	tween.tween_callback(func():
		GameManager.request_screen_shake(12.0, 0.6)
		var quake_dmg = int(100 * _get_spell_power())
		var enemies = GameManager.get_enemies_in_range(target_pos, 8.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(quake_dmg)
				RunStats.record_damage_dealt(quake_dmg)
			StatusEffectManager.apply_slow(e, 4.0, 0.6)
		AudienceManager.on_aoe_hit(enemies.size())
		_damage_nearby_interactables(quake_dmg, 8.0)
		VFXManager.spawn_spell_impact(target_pos, Color(0.8, 0.5, 0.1), 8.0)
		ScreenEffects.screen_flash(Color(0.8, 0.5, 0.1, 0.25), 0.2)
	)
	tween.tween_property(model, "scale", original_scale, 0.3)
	tween.tween_callback(_end_cast)

# ---- SIR GALLAN: Crusader (Smite, Holy Shield, Consecrate, Divine Judgment) ----

func _cast_alt_knight(index: int) -> void:
	match index:
		0: _alt_smite()
		1: _alt_holy_shield()
		2: _start_alt_targeting(2)  # Consecrate targeted
		3: _start_alt_targeting(3)  # Divine Judgment targeted

func _alt_smite() -> void:
	var range_mult := 1.3 if _trait_id == "eagle_eye" else 1.0
	var target = GameManager.get_nearest_enemy(global_position, 10.0 * range_mult)
	if target == null:
		return
	_consume_spell(0)
	_begin_cast()
	_face_position(target.global_position, 1.0)
	AudioManager.play_sfx("lightning", 0.6)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.9, 1.15, 0.9), 0.15)
	tween.tween_callback(func():
		var dmg = int(50 * _get_spell_power())
		if target and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(dmg)
			RunStats.record_damage_dealt(dmg)
			GameManager.request_damage_number(target.global_position + Vector3.UP * 2.5, dmg, false)
		VFXManager.spawn_spell_impact(target.global_position if target and is_instance_valid(target) else global_position, Color(1.0, 0.9, 0.5), 1.5)
	)
	tween.tween_property(model, "scale", original_scale, 0.1)
	tween.tween_callback(_end_cast)

func _alt_holy_shield() -> void:
	_consume_spell(1)
	_begin_cast()
	AudioManager.play_sfx("heal", 0.8)
	_set_model_color(Color(1.0, 0.95, 0.5))

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * 1.15, 0.2)
	tween.tween_callback(func():
		_buff_holy_shield = true
		VFXManager.spawn_heal_glow(self)
		# Shield lasts 3 seconds
		get_tree().create_timer(3.0).timeout.connect(func():
			_buff_holy_shield = false
			_restore_model_materials()
		)
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(func(): is_casting = false)

func _alt_consecrate_at(target_pos: Vector3) -> void:
	_consume_spell(2)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.play_sfx("heal", 0.6)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.85, 1.2, 0.85), 0.2)
	tween.tween_callback(func():
		# Spawn a golden DoT zone at target_pos for 5 seconds
		_spawn_consecrate_zone(target_pos)
		VFXManager.spawn_spell_impact(target_pos, Color(1.0, 0.9, 0.4), 4.0)
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(_end_cast)

func _spawn_consecrate_zone(pos: Vector3) -> void:
	var zone = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	disc.top_radius = 4.0
	disc.bottom_radius = 4.0
	disc.height = 0.05
	disc.radial_segments = 24
	zone.mesh = disc
	zone.position = pos + Vector3.UP * 0.05
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 1.5
	zone.set_surface_override_material(0, mat)
	get_tree().root.add_child(zone)

	var tick_count := 0
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	zone.add_child(timer)
	timer.timeout.connect(func():
		tick_count += 1
		var dmg = int(30 * _get_spell_power())
		var enemies = GameManager.get_enemies_in_range(pos, 4.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(dmg)
				RunStats.record_damage_dealt(dmg)
		if tick_count >= 5:
			timer.stop()
			var fade = zone.create_tween()
			fade.tween_property(mat, "albedo_color:a", 0.0, 0.5)
			fade.tween_callback(zone.queue_free)
	)

func _alt_divine_judgment_at(target_pos: Vector3) -> void:
	_consume_spell(3)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.play_sfx("lightning", 0.9)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.8, 1.3, 0.8), 0.3)
	_set_model_color(Color(1.0, 0.9, 0.4))
	tween.tween_callback(func():
		# Gold pillar of light at target
		var dmg = int(180 * _get_spell_power())
		var enemies = GameManager.get_enemies_in_range(target_pos, 3.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(dmg)
				RunStats.record_damage_dealt(dmg)
		AudienceManager.on_aoe_hit(enemies.size())
		_spawn_judgment_pillar(target_pos)
		GameManager.request_screen_shake(8.0, 0.35)
		ScreenEffects.screen_flash(Color(1.0, 0.9, 0.5, 0.35), 0.2)
	)
	tween.tween_property(model, "scale", original_scale, 0.25)
	tween.tween_callback(_end_cast)

func _spawn_judgment_pillar(pos: Vector3) -> void:
	var pillar = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 2.0
	cyl.height = 15.0
	pillar.mesh = cyl
	pillar.position = pos + Vector3.UP * 7.5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.4, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.4)
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	pillar.set_surface_override_material(0, mat)
	get_tree().root.add_child(pillar)
	var tw = pillar.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(pillar.queue_free)

# ---- GROKK: Bloodletter (Cleave, Blood Frenzy, Whirlwind, Execute) ----

func _cast_alt_barbarian(index: int) -> void:
	match index:
		0: _alt_cleave()
		1: _alt_blood_frenzy()
		2: _alt_whirlwind()
		3: _alt_execute()

func _alt_cleave() -> void:
	_consume_spell(0)
	_begin_cast()
	_swap_model(AnimState.ATTACK, true)
	AudioManager.on_hero_attack()

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.4, 0.8, 1.4), 0.15)
	tween.tween_callback(func():
		var cleave_dmg = int(_get_melee_damage() * 0.9)
		if _buff_war_cry:
			cleave_dmg = int(cleave_dmg * 1.3)
		var enemies = GameManager.get_enemies_in_range(global_position, 4.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(cleave_dmg)
				RunStats.record_damage_dealt(cleave_dmg)
		AudienceManager.on_aoe_hit(enemies.size())
		GameManager.request_screen_shake(4.0, 0.15)
		VFXManager.spawn_impact_sparks(global_position + Vector3.FORWARD * 1.5 + Vector3.UP, Color(0.8, 0.3, 0.2))
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(_end_cast)

func _alt_blood_frenzy() -> void:
	_consume_spell(1)
	_begin_cast()
	AudioManager.play_sfx("boss_roar", 0.6)
	_set_model_color(Color(0.9, 0.15, 0.1))

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * 1.2, 0.2)
	tween.tween_callback(func():
		_buff_blood_frenzy = true
		VFXManager.spawn_spell_impact(global_position, Color(0.9, 0.15, 0.1), 2.0)
		get_tree().create_timer(8.0).timeout.connect(func():
			_buff_blood_frenzy = false
			_restore_model_materials()
		)
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(func(): is_casting = false)

func _alt_whirlwind() -> void:
	_consume_spell(2)
	_begin_cast()
	AudioManager.play_sfx("sword_swing", 1.0)
	_set_model_color(Color(0.7, 0.2, 0.15))

	var tween = create_tween()
	# 3 spin hits over 1.2s
	for hit_i in range(3):
		tween.tween_callback(func():
			model.rotation.y += TAU / 3.0
			var spin_dmg = int(_get_melee_damage() * 0.6)
			if _buff_blood_frenzy:
				spin_dmg = int(spin_dmg * 1.4)
				# Lifesteal
				var heal = int(spin_dmg * 0.15)
				current_health = mini(current_health + heal, max_health)
				health_changed.emit(current_health, max_health)
			var enemies = GameManager.get_enemies_in_range(global_position, 3.5)
			for e in enemies:
				if e.has_method("take_damage"):
					e.take_damage(spin_dmg)
					RunStats.record_damage_dealt(spin_dmg)
			AudienceManager.on_aoe_hit(enemies.size())
			AudioManager.play_sfx("sword_swing", 0.7)
		)
		tween.tween_interval(0.4)
	tween.tween_callback(func():
		GameManager.request_screen_shake(3.0, 0.1)
		_end_cast()
	)

func _alt_execute() -> void:
	var range_mult := 1.3 if _trait_id == "eagle_eye" else 1.0
	var target = GameManager.get_nearest_enemy(global_position, 3.5 * range_mult)
	if target == null:
		return
	_consume_spell(3)
	_begin_cast()
	_face_position(target.global_position, 1.0)
	_swap_model(AnimState.ATTACK, true)
	AudioManager.on_hero_attack()

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.8, 1.4, 0.8), 0.25)
	_set_model_color(Color(0.9, 0.1, 0.05))
	tween.tween_property(model, "scale", original_scale * Vector3(1.4, 0.7, 1.4), 0.1)
	tween.tween_callback(func():
		var base_dmg = int(_get_melee_damage() * 2.0)
		# 3x damage if target below 30% HP
		if target and is_instance_valid(target) and target.has_method("get") and target.get("current_health") != null:
			var hp_ratio: float = float(target.current_health) / float(target.max_health) if target.max_health > 0 else 1.0
			if hp_ratio < 0.3:
				base_dmg = int(base_dmg * 1.5)
		if target and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(base_dmg)
			RunStats.record_damage_dealt(base_dmg)
		GameManager.request_screen_shake(7.0, 0.3)
		ScreenEffects.screen_flash(Color(0.9, 0.1, 0.05, 0.3), 0.15)
		VFXManager.spawn_impact_sparks(target.global_position + Vector3.UP if target and is_instance_valid(target) else global_position, Color(0.9, 0.1, 0.05), 20)
	)
	tween.tween_property(model, "scale", original_scale, 0.2)
	tween.tween_callback(_end_cast)

# ---- ELARA: Arcanist (Arcane Bolt, Ice Wall, Chain Lightning, Meteor) ----

func _cast_alt_mage(index: int) -> void:
	match index:
		0: _start_alt_targeting(0)  # Arcane Bolt targeted
		1: _alt_ice_wall()
		2: _start_alt_targeting(2)  # Chain Lightning targeted
		3: _start_alt_targeting(3)  # Meteor targeted

func _alt_arcane_bolt_at(target_pos: Vector3) -> void:
	_consume_spell(0)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.play_sfx("fireball_cast", 0.7)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.9, 1.1, 0.9), 0.1)
	tween.tween_callback(func():
		# Spawn a fast purple projectile (reuse fireball scene)
		var fireball_scene = preload("res://scenes/fireball.tscn")
		var bolt = fireball_scene.instantiate()
		get_tree().root.add_child(bolt)
		bolt.global_position = global_position + Vector3.UP * 1.5
		bolt.launch(target_pos)
		_flash_color(Color(0.6, 0.3, 1.0), 0.15)
	)
	tween.tween_property(model, "scale", original_scale, 0.1)
	tween.tween_callback(_end_cast)

func _alt_ice_wall() -> void:
	_consume_spell(1)
	_begin_cast()
	AudioManager.play_sfx("ice_shard", 0.8)
	_set_model_color(Color(0.4, 0.7, 1.0))

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * 1.15, 0.2)
	tween.tween_callback(func():
		# Spawn ice wall 4 units in front of hero
		var forward = -global_transform.basis.z.normalized()
		var wall_pos = global_position + forward * 4.0
		_spawn_ice_wall(wall_pos, forward)
		VFXManager.spawn_spell_impact(wall_pos, Color(0.4, 0.7, 1.0), 3.0)
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(_end_cast)

func _spawn_ice_wall(pos: Vector3, _facing: Vector3) -> void:
	# 3 ice blocks in a line perpendicular to facing
	var right = Vector3(_facing.z, 0, -_facing.x).normalized()
	for i in range(-1, 2):
		var block = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1.2, 2.5, 0.6)
		block.mesh = box
		block.position = pos + right * float(i) * 1.3 + Vector3.UP * 1.25
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.8, 1.0, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.7, 1.0)
		mat.emission_energy_multiplier = 1.0
		block.set_surface_override_material(0, mat)
		get_tree().root.add_child(block)

		# Slow enemies that pass near
		var block_pos = block.position
		var tick := 0
		var slow_timer = Timer.new()
		slow_timer.wait_time = 0.5
		slow_timer.autostart = true
		block.add_child(slow_timer)
		slow_timer.timeout.connect(func():
			tick += 1
			var enemies = GameManager.get_enemies_in_range(block_pos, 2.0)
			for e in enemies:
				StatusEffectManager.apply_slow(e, 1.0, 0.5)
			if tick >= 14:  # 7 seconds
				slow_timer.stop()
				var fade = block.create_tween()
				fade.tween_property(mat, "albedo_color:a", 0.0, 0.5)
				fade.tween_callback(block.queue_free)
		)

func _alt_chain_lightning_at(target_pos: Vector3) -> void:
	_consume_spell(2)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.on_hero_cast_lightning()

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.85, 1.2, 0.85), 0.2)
	_set_model_color(Color(0.4, 0.6, 1.0))
	tween.tween_callback(func():
		# Spawn lightning bolt (reuse existing scene)
		var bolt_scene = preload("res://scenes/lightning_bolt.tscn")
		var bolt = bolt_scene.instantiate()
		get_tree().root.add_child(bolt)
		bolt.global_position = global_position + Vector3.UP * 1.5
		if bolt.has_method("launch"):
			bolt.launch(target_pos)
		VFXManager.spawn_spell_impact(target_pos, Color(0.4, 0.6, 1.0), 3.0)
		ScreenEffects.screen_flash(Color(0.6, 0.7, 1.0, 0.2), 0.1)
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(_end_cast)

func _alt_meteor_at(target_pos: Vector3) -> void:
	_consume_spell(3)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.play_sfx("fireball_cast", 1.0)
	_set_model_color(Color(1.0, 0.4, 0.1))

	# Show telegraph circle
	var telegraph = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	disc.top_radius = 5.0
	disc.bottom_radius = 5.0
	disc.height = 0.03
	telegraph.mesh = disc
	telegraph.position = target_pos + Vector3.UP * 0.05
	var tel_mat = StandardMaterial3D.new()
	tel_mat.albedo_color = Color(1.0, 0.3, 0.1, 0.3)
	tel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tel_mat.emission_enabled = true
	tel_mat.emission = Color(1.0, 0.3, 0.1)
	tel_mat.emission_energy_multiplier = 1.5
	telegraph.set_surface_override_material(0, tel_mat)
	get_tree().root.add_child(telegraph)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.8, 1.3, 0.8), 0.3)
	tween.tween_interval(1.2)  # Delay before impact
	tween.tween_callback(func():
		# IMPACT
		var meteor_dmg = int(200 * _get_spell_power())
		var enemies = GameManager.get_enemies_in_range(target_pos, 5.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(meteor_dmg)
				RunStats.record_damage_dealt(meteor_dmg)
		AudienceManager.on_aoe_hit(enemies.size())
		_damage_nearby_interactables(meteor_dmg, 5.0)
		GameManager.request_screen_shake(14.0, 0.5)
		ScreenEffects.screen_flash(Color(1.0, 0.4, 0.1, 0.4), 0.25)
		AudioManager.play_sfx("fireball_explode", 1.2)
		VFXManager.spawn_spell_impact(target_pos, Color(1.0, 0.4, 0.1), 5.0)
		telegraph.queue_free()
	)
	tween.tween_property(model, "scale", original_scale, 0.25)
	tween.tween_callback(_end_cast)

# ---- THERON: Sharpshooter (Aimed Shot, Trap, Volley, Snipe) ----

func _cast_alt_ranger(index: int) -> void:
	match index:
		0: _start_alt_targeting(0)
		1: _start_alt_targeting(1)
		2: _start_alt_targeting(2)
		3: _start_alt_targeting(3)

func _alt_aimed_shot_at(target_pos: Vector3) -> void:
	_consume_spell(0)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.play_sfx("sword_swing", 0.6)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.9, 1.1, 0.9), 0.15)
	tween.tween_callback(func():
		# Precise single-target hit at target position
		var nearest = GameManager.get_nearest_enemy(target_pos, 2.5)
		if nearest and is_instance_valid(nearest) and nearest.has_method("take_damage"):
			var dmg = int(60 * _get_spell_power())
			# 50% crit chance on aimed shot
			if randf() < 0.5:
				dmg = int(dmg * 1.8)
				GameManager.request_damage_number(nearest.global_position + Vector3.UP * 2.5, dmg, true)
				GameManager.request_screen_shake(5.0, 0.2)
			else:
				GameManager.request_damage_number(nearest.global_position + Vector3.UP * 2.5, dmg, false)
			nearest.take_damage(dmg)
			RunStats.record_damage_dealt(dmg)
		VFXManager.spawn_impact_sparks(target_pos + Vector3.UP, Color(0.3, 0.8, 0.3))
	)
	tween.tween_property(model, "scale", original_scale, 0.1)
	tween.tween_callback(_end_cast)

func _alt_trap_at(target_pos: Vector3) -> void:
	_consume_spell(1)
	_begin_cast()
	AudioManager.play_sfx("chest_open", 0.5)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.05, 0.95, 1.05), 0.15)
	tween.tween_callback(func():
		_spawn_trap(target_pos)
	)
	tween.tween_property(model, "scale", original_scale, 0.1)
	tween.tween_callback(_end_cast)

func _spawn_trap(pos: Vector3) -> void:
	var trap_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.5, 0.1, 1.5)
	trap_mesh.mesh = box
	trap_mesh.position = pos + Vector3.UP * 0.05
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.6, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.6, 0.2)
	mat.emission_energy_multiplier = 0.8
	trap_mesh.set_surface_override_material(0, mat)
	get_tree().root.add_child(trap_mesh)

	var tick := 0
	var triggered := false
	var check_timer = Timer.new()
	check_timer.wait_time = 0.3
	check_timer.autostart = true
	trap_mesh.add_child(check_timer)
	check_timer.timeout.connect(func():
		tick += 1
		if triggered:
			return
		var enemies = GameManager.get_enemies_in_range(pos, 1.5)
		if enemies.size() > 0:
			triggered = true
			var trap_dmg = int(70 * _get_spell_power())
			for e in enemies:
				if e.has_method("take_damage"):
					e.take_damage(trap_dmg)
					RunStats.record_damage_dealt(trap_dmg)
				StatusEffectManager.apply_stun(e, 2.0)
			AudioManager.play_sfx("spike_trap", 0.8)
			VFXManager.spawn_impact_sparks(pos + Vector3.UP, Color(0.4, 0.6, 0.2), 15)
			var fade = trap_mesh.create_tween()
			fade.tween_property(mat, "albedo_color:a", 0.0, 0.3)
			fade.tween_callback(trap_mesh.queue_free)
		elif tick >= 100:  # 30s timeout
			check_timer.stop()
			trap_mesh.queue_free()
	)

func _alt_volley_at(target_pos: Vector3) -> void:
	_consume_spell(2)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.play_sfx("sword_swing", 0.8)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.85, 1.2, 0.85), 0.2)
	tween.tween_callback(func():
		# Rain of arrows — 3 waves in target area
		for wave in range(3):
			get_tree().create_timer(0.3 * wave).timeout.connect(func():
				var volley_dmg = int(35 * _get_spell_power())
				var enemies = GameManager.get_enemies_in_range(target_pos, 4.0)
				for e in enemies:
					if e.has_method("take_damage"):
						e.take_damage(volley_dmg)
						RunStats.record_damage_dealt(volley_dmg)
				VFXManager.spawn_impact_sparks(target_pos + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)), Color(0.5, 0.35, 0.2), 8)
				AudioManager.play_sfx("melee_hit", 0.5)
			)
		AudienceManager.on_aoe_hit(GameManager.get_enemies_in_range(target_pos, 4.0).size())
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_interval(0.8)
	tween.tween_callback(_end_cast)

func _alt_snipe_at(target_pos: Vector3) -> void:
	_consume_spell(3)
	_begin_cast()
	_face_position(target_pos, 1.0)

	var tween = create_tween()
	# Brief channel
	tween.tween_property(model, "scale", original_scale * Vector3(0.85, 1.15, 0.85), 0.5)
	_set_model_color(Color(0.2, 0.6, 0.3))
	tween.tween_callback(func():
		AudioManager.play_sfx("lightning", 0.7)
		var nearest = GameManager.get_nearest_enemy(target_pos, 3.0)
		if nearest and is_instance_valid(nearest) and nearest.has_method("take_damage"):
			var dmg = int(250 * _get_spell_power())
			nearest.take_damage(dmg)
			RunStats.record_damage_dealt(dmg)
			GameManager.request_damage_number(nearest.global_position + Vector3.UP * 2.5, dmg, true)
			GameManager.request_screen_shake(6.0, 0.25)
			VFXManager.spawn_impact_sparks(nearest.global_position + Vector3.UP, Color(0.2, 0.8, 0.3), 18)
		ScreenEffects.screen_flash(Color(0.2, 0.6, 0.3, 0.2), 0.1)
	)
	tween.tween_property(model, "scale", original_scale, 0.2)
	tween.tween_callback(_end_cast)

# ---- SHADE: Shadow Arts (Backstab, Smoke Bomb, Fan of Knives, Shadow Strike) ----

func _cast_alt_rogue(index: int) -> void:
	match index:
		0: _alt_backstab()
		1: _alt_smoke_bomb()
		2: _alt_fan_of_knives()
		3: _start_alt_targeting(3)

func _alt_backstab() -> void:
	var range_mult := 1.3 if _trait_id == "eagle_eye" else 1.0
	var target = GameManager.get_nearest_enemy(global_position, 10.0 * range_mult)
	if target == null:
		return
	_consume_spell(0)
	_begin_cast()
	AudioManager.play_sfx("enemy_death", 0.5)

	# Teleport behind target
	var behind = target.global_position + (target.global_position - global_position).normalized() * 1.5
	_flash_color(Color(0.3, 0.1, 0.5), 0.1)

	var tween = create_tween()
	tween.tween_property(model, "scale", Vector3(0.5, 0.5, 0.5), 0.1)
	tween.tween_callback(func():
		global_position = behind
		_face_position(target.global_position, 1.0)
	)
	tween.tween_property(model, "scale", original_scale * Vector3(1.2, 0.9, 1.2), 0.08)
	tween.tween_callback(func():
		var dmg = int(_get_melee_damage() * 2.0)
		if target and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(dmg)
			RunStats.record_damage_dealt(dmg)
			GameManager.request_damage_number(target.global_position + Vector3.UP * 2.5, dmg, true)
		VFXManager.spawn_impact_sparks(target.global_position + Vector3.UP if target and is_instance_valid(target) else global_position, Color(0.4, 0.1, 0.6), 15)
		GameManager.request_screen_shake(4.0, 0.15)
	)
	tween.tween_property(model, "scale", original_scale, 0.1)
	tween.tween_callback(_end_cast)

func _alt_smoke_bomb() -> void:
	_consume_spell(1)
	_begin_cast()
	AudioManager.play_sfx("fire_vent", 0.5)
	_set_model_color(Color(0.3, 0.3, 0.4))

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.1, 0.9, 1.1), 0.15)
	tween.tween_callback(func():
		# Stun nearby enemies briefly + smoke effect
		var enemies = GameManager.get_enemies_in_range(global_position, 5.0)
		for e in enemies:
			StatusEffectManager.apply_stun(e, 1.5)
		VFXManager.spawn_spell_impact(global_position, Color(0.3, 0.3, 0.4), 5.0)
		# Invisibility visual: make hero semi-transparent for 4s
		_buff_smoke_bomb = true
		get_tree().create_timer(4.0).timeout.connect(func():
			_buff_smoke_bomb = false
			_restore_model_materials()
		)
	)
	tween.tween_property(model, "scale", original_scale, 0.15)
	tween.tween_callback(func(): is_casting = false)

func _alt_fan_of_knives() -> void:
	_consume_spell(2)
	_begin_cast()
	AudioManager.play_sfx("sword_swing", 0.8)

	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(1.3, 0.85, 1.3), 0.12)
	tween.tween_callback(func():
		var knife_dmg = int(45 * _get_spell_power())
		# Hit all enemies within 5 units in a wide arc (360° for simplicity)
		var enemies = GameManager.get_enemies_in_range(global_position, 5.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(knife_dmg)
				RunStats.record_damage_dealt(knife_dmg)
				# Spawn knife VFX toward each enemy
				var dir = (e.global_position - global_position).normalized()
				VFXManager.spawn_impact_sparks(global_position + dir * 2.0 + Vector3.UP, Color(0.5, 0.5, 0.6), 4)
		AudienceManager.on_aoe_hit(enemies.size())
		GameManager.request_screen_shake(3.0, 0.12)
	)
	tween.tween_property(model, "scale", original_scale, 0.12)
	tween.tween_callback(_end_cast)

func _alt_shadow_strike_at(target_pos: Vector3) -> void:
	_consume_spell(3)
	_begin_cast()
	_face_position(target_pos, 1.0)
	AudioManager.play_sfx("enemy_death", 0.7)
	_set_model_color(Color(0.2, 0.05, 0.3))

	# Mark with purple pulse, then detonate after 1.5s
	var mark_pos = target_pos
	var mark = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	mark.mesh = sphere
	mark.position = mark_pos + Vector3.UP * 1.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.1, 0.8, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.1, 0.8)
	mat.emission_energy_multiplier = 2.0
	mark.set_surface_override_material(0, mat)
	get_tree().root.add_child(mark)

	var tween = create_tween()
	tween.tween_property(mark, "scale", Vector3(1.5, 1.5, 1.5), 1.2)
	tween.tween_callback(func():
		# Detonate
		var strike_dmg = int(180 * _get_spell_power())
		var enemies = GameManager.get_enemies_in_range(mark_pos, 3.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(strike_dmg)
				RunStats.record_damage_dealt(strike_dmg)
		AudienceManager.on_aoe_hit(enemies.size())
		GameManager.request_screen_shake(8.0, 0.3)
		ScreenEffects.screen_flash(Color(0.4, 0.1, 0.6, 0.3), 0.15)
		VFXManager.spawn_spell_impact(mark_pos, Color(0.5, 0.1, 0.8), 3.0)
		mark.queue_free()
	)
	tween.tween_property(model, "scale", original_scale, 0.2)
	tween.tween_callback(_end_cast)

# ---- BUFF INTEGRATION INTO DAMAGE ----

func _get_buff_damage_multiplier() -> float:
	var mult := 1.0
	if _buff_war_cry:
		mult *= 1.3
	if _buff_blood_frenzy:
		mult *= 1.4
	return mult
