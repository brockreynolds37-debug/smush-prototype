extends CharacterBody3D

## Ranged enemy AI — kites the hero and fires arrow projectiles.
## Used by goblin_archer and similar ranged enemy types.

signal health_changed(current: int, maximum: int)

@export var max_health: int = 70
@export var move_speed: float = 4.5
@export var aggro_range: float = 16.0
@export var attack_range: float = 12.0     # Preferred shooting distance
@export var min_range: float = 5.0         # Too close — kite away
@export var attack_damage: int = 12
@export var attack_cooldown: float = 2.2
@export var arrow_speed: float = 22.0

@export var enemy_type: String = "goblin_archer"

var current_health: int = 70
var is_dead: bool = false
var is_aggroed: bool = false
var current_speed: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var leash_range: float = 25.0

var original_scale := Vector3.ONE
var _cached_mesh_instances: Array[MeshInstance3D] = []

# Status effects
var _base_move_speed: float = 4.5
var _is_stunned: bool = false
var _slow_amount: float = 0.0

# Animation
enum AnimState { IDLE, WALK, ATTACK, DEATH }
var anim_state: AnimState = AnimState.IDLE
var prev_anim_state: AnimState = AnimState.IDLE

var anim_scenes: Dictionary = {}
var active_model: Node3D = null
var active_anim_player: AnimationPlayer = null

# Kiting
var _kite_direction: Vector3 = Vector3.ZERO
var _kite_timer: float = 0.0
const KITE_CHANGE_INTERVAL: float = 1.5  # Change strafe direction

@onready var model: Node3D = $EnemyModel
@onready var selection_circle: MeshInstance3D = $SelectionCircle
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var attack_timer: Timer = $AttackTimer

var _arrow_scene: PackedScene

func _ready() -> void:
	GameManager.register_enemy(self)
	spawn_position = global_position

	# Apply NG+ HP scaling
	var ngp_hp := NewGamePlus.get_enemy_hp_multiplier()
	if ngp_hp != 1.0:
		max_health = int(max_health * ngp_hp)
	current_health = max_health
	_base_move_speed = move_speed

	_arrow_scene = preload("res://scenes/arrow_projectile.tscn")

	_load_enemy_model()
	original_scale = model.scale

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	health_changed.emit(current_health, max_health)

func _load_enemy_model() -> void:
	var model_paths := {
		"goblin_archer": "res://assets/models/enemies/goblin_archer.glb",
	}

	if model_paths.has(enemy_type):
		anim_scenes = {}
		var scene := load(model_paths[enemy_type]) as PackedScene
		if scene:
			active_model = scene.instantiate()
			model.add_child(active_model)
			_cache_mesh_instances()
	else:
		# Fallback
		anim_scenes = {}
		var fallback = preload("res://assets/models/skeleton_warrior.glb")
		active_model = fallback.instantiate()
		model.add_child(active_model)
		_cache_mesh_instances()

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

	# Aggro check
	if not is_aggroed and dist_to_hero < aggro_range:
		is_aggroed = true
		var tween = create_tween()
		tween.tween_property(model, "scale", original_scale * 1.2, 0.1)
		tween.tween_property(model, "scale", original_scale, 0.1)
		_flash_color(Color(1.0, 0.2, 0.1), 0.15)

	# Leash
	if is_aggroed and dist_to_spawn > leash_range:
		is_aggroed = false
		current_health = max_health
		health_changed.emit(current_health, max_health)
		_return_to_spawn(delta)
		return

	var new_state := AnimState.IDLE

	if is_aggroed:
		_face_position(hero.global_position, delta)

		if dist_to_hero < min_range:
			# Too close — kite backwards away from hero
			var away_dir = (global_position - hero.global_position).normalized()
			away_dir.y = 0
			_kite_timer += delta
			if _kite_timer >= KITE_CHANGE_INTERVAL:
				_kite_timer = 0.0
				# Add lateral component for unpredictable movement
				var lateral = Vector3(-away_dir.z, 0, away_dir.x)
				if randf() > 0.5:
					lateral = -lateral
				_kite_direction = (away_dir + lateral * 0.5).normalized()
			if _kite_direction == Vector3.ZERO:
				_kite_direction = away_dir

			current_speed = move_toward(current_speed, move_speed * 1.1, 15.0 * delta)
			velocity = _kite_direction * current_speed
			new_state = AnimState.WALK

			# Still try to shoot while kiting
			_try_ranged_attack(hero)

		elif dist_to_hero <= attack_range:
			# In range — strafe and shoot
			_kite_timer += delta
			if _kite_timer >= KITE_CHANGE_INTERVAL:
				_kite_timer = 0.0
				# Strafe perpendicular to hero
				var to_hero = (hero.global_position - global_position).normalized()
				var lateral = Vector3(-to_hero.z, 0, to_hero.x)
				if randf() > 0.5:
					lateral = -lateral
				_kite_direction = lateral

			if _kite_direction != Vector3.ZERO:
				current_speed = move_toward(current_speed, move_speed * 0.6, 10.0 * delta)
				velocity = _kite_direction * current_speed
				new_state = AnimState.WALK
			else:
				current_speed = 0.0
				velocity = Vector3.ZERO
				new_state = AnimState.IDLE

			_try_ranged_attack(hero)

		else:
			# Too far — close the gap
			nav_agent.target_position = hero.global_position
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
			direction.y = 0
			current_speed = move_toward(current_speed, move_speed, 15.0 * delta)
			velocity = direction * current_speed
			new_state = AnimState.WALK
	else:
		current_speed = 0.0
		velocity = Vector3.ZERO
		new_state = AnimState.IDLE

	if new_state != prev_anim_state:
		prev_anim_state = new_state
		anim_state = new_state

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
		anim_state = AnimState.WALK
		prev_anim_state = AnimState.WALK
	else:
		current_speed = 0.0
		velocity = Vector3.ZERO
		anim_state = AnimState.IDLE
		prev_anim_state = AnimState.IDLE
	move_and_slide()

func _face_position(target: Vector3, delta: float) -> void:
	var look_dir = (target - global_position)
	look_dir.y = 0
	if look_dir.length_squared() < 0.001:
		return
	var target_rot = atan2(look_dir.x, look_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, 10.0 * delta)

func _try_ranged_attack(hero: Node3D) -> void:
	if not attack_timer.is_stopped():
		return
	attack_timer.start(attack_cooldown)

	# Wind-up squash
	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.85, 1.2, 0.85), 0.15)
	tween.tween_callback(func():
		_fire_arrow(hero)
	)
	tween.tween_property(model, "scale", original_scale * Vector3(1.1, 0.9, 1.1), 0.1)
	tween.tween_property(model, "scale", original_scale, 0.1)

func _fire_arrow(hero: Node3D) -> void:
	if not is_instance_valid(hero) or hero.is_dead:
		return

	var arrow = _arrow_scene.instantiate()
	get_tree().root.add_child(arrow)
	arrow.global_position = global_position + Vector3.UP * 1.2
	arrow.damage = attack_damage
	arrow.speed = arrow_speed
	# Pass elite flags to arrow for on-hit effects
	if has_meta("venomous_dot") and get_meta("venomous_dot"):
		arrow.set_meta("venomous_dot", true)
	if has_meta("vampiric_leech"):
		arrow.set_meta("vampiric_leech", get_meta("vampiric_leech"))
		arrow.set_meta("vampiric_source", self)
	arrow.launch(hero.global_position + Vector3.UP * 0.8)

	# Arrow whoosh sound
	AudioManager.play_sfx("sword_swing", 0.4, 0.3)

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

	var tween = create_tween()
	tween.tween_interval(0.3)
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
