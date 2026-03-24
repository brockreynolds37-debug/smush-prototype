extends CharacterBody3D

## Enemy unit with basic AI — aggro, chase, attack, die.

signal health_changed(current: int, maximum: int)

@export var max_health: int = 150
@export var move_speed: float = 5.0
@export var aggro_range: float = 10.0
@export var attack_range: float = 2.5
@export var attack_damage: int = 15
@export var attack_cooldown: float = 1.5

var current_health: int = 150
var is_dead: bool = false
var is_aggroed: bool = false
var current_speed: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var leash_range: float = 20.0

var base_mesh_color := Color(0.8, 0.15, 0.1)
var original_scale := Vector3.ONE

@onready var mesh: MeshInstance3D = $EnemyMesh
@onready var selection_circle: MeshInstance3D = $SelectionCircle
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var attack_timer: Timer = $AttackTimer

func _ready() -> void:
	GameManager.register_enemy(self)
	spawn_position = global_position
	current_health = max_health
	original_scale = mesh.scale
	_set_mesh_color(base_mesh_color)

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	health_changed.emit(current_health, max_health)

	# Idle bob
	var tween = create_tween().set_loops()
	tween.tween_property(mesh, "position:y", 0.6 + 0.05, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mesh, "position:y", 0.6 - 0.05, 0.8).set_trans(Tween.TRANS_SINE)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		_return_to_spawn(delta)
		return

	var dist_to_hero = global_position.distance_to(hero.global_position)
	var dist_to_spawn = global_position.distance_to(spawn_position)

	# Aggro check
	if not is_aggroed and dist_to_hero < aggro_range:
		is_aggroed = true
		# Aggro reaction - flash and grow
		var tween = create_tween()
		tween.tween_property(mesh, "scale", original_scale * 1.2, 0.1)
		tween.tween_property(mesh, "scale", original_scale, 0.1)
		_set_mesh_color(Color(1.0, 0.2, 0.1))
		await get_tree().create_timer(0.15).timeout
		_set_mesh_color(base_mesh_color)

	# Leash check
	if is_aggroed and dist_to_spawn > leash_range:
		is_aggroed = false
		current_health = max_health
		health_changed.emit(current_health, max_health)
		_return_to_spawn(delta)
		return

	if is_aggroed:
		if dist_to_hero <= attack_range:
			# In range — attack
			current_speed = 0.0
			velocity = Vector3.ZERO
			_face_position(hero.global_position, delta)
			_try_attack(hero)
		else:
			# Chase
			nav_agent.target_position = hero.global_position
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
			direction.y = 0
			current_speed = move_toward(current_speed, move_speed, 15.0 * delta)
			velocity = direction * current_speed
			_face_position(hero.global_position, delta)
	else:
		current_speed = 0.0
		velocity = Vector3.ZERO

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
	else:
		current_speed = 0.0
		velocity = Vector3.ZERO
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

	# Attack animation - lunge forward
	var tween = create_tween()
	tween.tween_property(mesh, "scale", original_scale * Vector3(1.2, 0.85, 1.2), 0.1)
	tween.tween_callback(func():
		if is_instance_valid(hero) and hero.has_method("take_damage"):
			hero.take_damage(attack_damage)
	)
	tween.tween_property(mesh, "scale", original_scale * Vector3(0.9, 1.1, 0.9), 0.1)
	tween.tween_property(mesh, "scale", original_scale, 0.1)

func take_damage(amount: int) -> void:
	if is_dead:
		return

	current_health -= amount
	health_changed.emit(current_health, max_health)
	is_aggroed = true

	# Damage number
	GameManager.request_damage_number(global_position + Vector3.UP * 2.0, amount, amount > 50)

	# Hit flash — turn white briefly
	_set_mesh_color(Color.WHITE)
	var flash_tween = create_tween()
	flash_tween.tween_interval(0.08)
	flash_tween.tween_callback(func():
		if not is_dead:
			_set_mesh_color(base_mesh_color)
	)

	# Hit knockback squash
	var hit_tween = create_tween()
	hit_tween.tween_property(mesh, "scale", original_scale * Vector3(1.2, 0.8, 1.2), 0.05)
	hit_tween.tween_property(mesh, "scale", original_scale, 0.1)

	if current_health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO

	# Satisfying death: fall over and shrink
	var tween = create_tween()
	# Flatten
	tween.tween_property(mesh, "scale", Vector3(1.5, 0.1, 1.5), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(mesh, "position:y", 0.05, 0.3)
	# Fade out selection circle
	tween.parallel().tween_property(selection_circle, "scale", Vector3.ZERO, 0.2)
	# Brief pause then shrink away
	tween.tween_interval(0.5)
	tween.tween_property(mesh, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tween.tween_callback(func():
		GameManager.unregister_enemy(self)
		queue_free()
	)

	GameManager.request_screen_shake(2.0, 0.1)

func _set_mesh_color(color: Color) -> void:
	var mat = mesh.get_surface_override_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, mat)
	mat.albedo_color = color
