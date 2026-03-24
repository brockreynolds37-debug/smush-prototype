extends CharacterBody3D

## Hero unit — click-to-move, spell casting, WC3-style feel.

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

# References
@onready var mesh: MeshInstance3D = $HeroMesh
@onready var selection_circle: MeshInstance3D = $SelectionCircle
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_bar: Node3D = $HealthBar
@onready var attack_timer_node: Timer = $AttackTimer
@onready var cast_timer_node: Timer = $CastTimer

var base_mesh_color := Color(0.2, 0.5, 1.0)  # Hero blue
var original_scale := Vector3.ONE

func _ready() -> void:
	GameManager.register_hero(self)
	target_position = global_position
	original_scale = mesh.scale
	_set_mesh_color(base_mesh_color)

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

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_process_cooldowns(delta)
	_process_casting(delta)

	if not is_casting:
		_process_movement(delta)

	_update_animation_state()

func _process_movement(delta: float) -> void:
	if not is_moving and attack_target == null:
		# Decelerate to stop
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		if current_speed > 0:
			velocity = velocity.normalized() * current_speed
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		return

	# If we have an attack target, move toward it
	if attack_target != null and is_instance_valid(attack_target):
		nav_agent.target_position = attack_target.global_position
		if global_position.distance_to(attack_target.global_position) < 2.5:
			# In melee range - attack
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

	# Accelerate
	current_speed = move_toward(current_speed, move_speed, acceleration * delta)
	velocity = direction * current_speed

	# Rotate toward movement direction
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
	attack_target = null
	# WC3-style "acknowledgment" squash and stretch
	_play_acknowledge_bounce()

func _play_acknowledge_bounce() -> void:
	var tween = create_tween()
	tween.tween_property(mesh, "scale", original_scale * Vector3(0.85, 1.2, 0.85), 0.06)
	tween.tween_property(mesh, "scale", original_scale * Vector3(1.1, 0.9, 1.1), 0.06)
	tween.tween_property(mesh, "scale", original_scale, 0.08)

func _perform_melee_attack() -> void:
	if not attack_timer_node.is_stopped():
		return
	anim_state = AnimState.ATTACK
	attack_timer_node.start(0.8)

	# Attack animation
	var tween = create_tween()
	tween.tween_property(mesh, "scale", original_scale * Vector3(1.3, 0.8, 1.3), 0.15)
	tween.tween_callback(_apply_melee_damage)
	tween.tween_property(mesh, "scale", original_scale * Vector3(0.9, 1.15, 0.9), 0.1)
	tween.tween_property(mesh, "scale", original_scale, 0.1)

func _apply_melee_damage() -> void:
	if attack_target and is_instance_valid(attack_target) and attack_target.has_method("take_damage"):
		attack_target.take_damage(35)
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
	# Melee attack - find nearest enemy in range
	var target = GameManager.get_nearest_enemy(global_position, 3.5)
	if target:
		set_attack_target(target)
		spell_cooldowns[0] = spell_max_cooldowns[0]
		spell_cast.emit(0)
	else:
		# No target nearby, find any enemy and move to them
		target = GameManager.get_nearest_enemy(global_position, 15.0)
		if target:
			set_attack_target(target)

func _start_fireball_targeting() -> void:
	# Enter targeting mode - spell will be cast on next ground click
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

	# Consume mana
	current_mana -= spell_mana_costs[1]
	mana_changed.emit(current_mana, max_mana)
	spell_cooldowns[1] = spell_max_cooldowns[1]
	spell_cast.emit(1)

	# Cast animation
	anim_state = AnimState.CAST
	var tween = create_tween()
	tween.tween_property(mesh, "scale", original_scale * Vector3(0.8, 1.3, 0.8), 0.2)
	tween.tween_callback(func(): _spawn_fireball(target_pos))
	tween.tween_property(mesh, "scale", original_scale, 0.15)
	tween.tween_callback(func(): is_casting = false)

	# Brief color flash
	_set_mesh_color(Color(1.0, 0.5, 0.0))
	await get_tree().create_timer(0.3).timeout
	_set_mesh_color(base_mesh_color)

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
	_set_mesh_color(Color(0.2, 1.0, 0.3))

	# Heal animation - grow and glow green
	var tween = create_tween()
	tween.tween_property(mesh, "scale", original_scale * 1.2, 0.3)
	tween.tween_callback(func():
		var heal_amount = 150
		current_health = mini(current_health + heal_amount, max_health)
		health_changed.emit(current_health, max_health)
		GameManager.request_damage_number(global_position + Vector3.UP * 2.5, heal_amount, false)
		_spawn_heal_particles()
	)
	tween.tween_property(mesh, "scale", original_scale, 0.2)
	tween.tween_callback(func():
		is_casting = false
		_set_mesh_color(base_mesh_color)
	)

func _spawn_heal_particles() -> void:
	var particles = preload("res://scenes/heal_particles.tscn").instantiate()
	add_child(particles)
	particles.position = Vector3.ZERO
	particles.emitting = true
	# Auto cleanup
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

	# Big windup
	var tween = create_tween()
	tween.tween_property(mesh, "scale", original_scale * Vector3(0.7, 1.5, 0.7), 0.4)
	_set_mesh_color(Color(1.0, 0.8, 0.0))
	tween.tween_property(mesh, "scale", original_scale * Vector3(1.5, 0.6, 1.5), 0.1)
	tween.tween_callback(func():
		# SLAM! Damage all enemies nearby
		GameManager.request_screen_shake(8.0, 0.4)
		var enemies = GameManager.get_enemies_in_range(global_position, 6.0)
		for e in enemies:
			if e.has_method("take_damage"):
				e.take_damage(80)
		_spawn_slam_particles()
	)
	tween.tween_property(mesh, "scale", original_scale, 0.3)
	tween.tween_callback(func():
		is_casting = false
		_set_mesh_color(base_mesh_color)
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

	# Hit flash
	_set_mesh_color(Color.WHITE)
	await get_tree().create_timer(0.08).timeout
	if not is_dead:
		_set_mesh_color(base_mesh_color)

	# Hit squash
	var tween = create_tween()
	tween.tween_property(mesh, "scale", original_scale * Vector3(1.15, 0.85, 1.15), 0.05)
	tween.tween_property(mesh, "scale", original_scale, 0.1)

	if current_health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	is_moving = false
	anim_state = AnimState.DEATH
	velocity = Vector3.ZERO

	var tween = create_tween()
	tween.tween_property(mesh, "scale", Vector3(1.5, 0.1, 1.5), 0.5)
	tween.tween_property(mesh, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	hero_died.emit()

# ---------- UTILITIES ----------

func _process_cooldowns(delta: float) -> void:
	for i in range(4):
		if spell_cooldowns[i] > 0:
			spell_cooldowns[i] = maxf(spell_cooldowns[i] - delta, 0.0)
			spell_cooldown_updated.emit(i, spell_cooldowns[i], spell_max_cooldowns[i])

func _process_casting(_delta: float) -> void:
	pass  # Casting is tween-driven

func _update_animation_state() -> void:
	if is_dead:
		anim_state = AnimState.DEATH
	elif is_casting:
		anim_state = AnimState.CAST
	elif current_speed > 0.5:
		anim_state = AnimState.WALK
		# Subtle walk bob
		mesh.position.y = 0.75 + sin(Time.get_ticks_msec() * 0.01) * 0.05
	else:
		anim_state = AnimState.IDLE
		# Idle breathing
		mesh.position.y = 0.75 + sin(Time.get_ticks_msec() * 0.003) * 0.03

func _set_mesh_color(color: Color) -> void:
	var mat = mesh.get_surface_override_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, mat)
	mat.albedo_color = color

func _on_mana_regen() -> void:
	if not is_dead and current_mana < max_mana:
		current_mana = mini(current_mana + 5, max_mana)
		mana_changed.emit(current_mana, max_mana)
