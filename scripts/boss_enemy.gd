extends CharacterBody3D

## Boss enemy — bigger, tougher, special attacks, boss health bar in HUD.
## Extends the same pattern as enemy.gd but with boss-specific mechanics:
## - Phase transitions at health thresholds
## - AoE slam attack
## - Enrage at low HP
## - Boss intro camera moment
## - Signals for HUD boss health bar

signal health_changed(current: int, maximum: int)
signal boss_defeated(boss_type: String)

@export var max_health: int = 800
@export var move_speed: float = 4.0
@export var aggro_range: float = 18.0
@export var attack_range: float = 3.0
@export var attack_damage: int = 30
@export var attack_cooldown: float = 2.0
@export var boss_type: String = "goblin_king"
@export var boss_display_name: String = "Goblin King"
@export var model_scale: float = 2.0

var current_health: int = 800
var is_dead: bool = false
var is_aggroed: bool = false
var current_speed: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var leash_range: float = 30.0

var original_scale := Vector3.ONE
var _cached_mesh_instances: Array[MeshInstance3D] = []

# Boss phases
enum Phase { IDLE, PHASE_1, PHASE_2, ENRAGED }
var current_phase: Phase = Phase.IDLE

# Special attack tracking
var slam_cooldown_timer: float = 0.0
const SLAM_COOLDOWN: float = 8.0
const SLAM_RADIUS: float = 5.0
const SLAM_DAMAGE: int = 50

# Enrage
var is_enraged: bool = false
const ENRAGE_THRESHOLD: float = 0.25  # 25% HP

# Animation
enum AnimState { IDLE, WALK, ATTACK, DEATH }
var anim_state: AnimState = AnimState.IDLE
var prev_anim_state: AnimState = AnimState.IDLE

var active_model: Node3D = null

@onready var model: Node3D = $EnemyModel
@onready var selection_circle: MeshInstance3D = $SelectionCircle
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var attack_timer: Timer = $AttackTimer

func _ready() -> void:
	GameManager.register_enemy(self)
	spawn_position = global_position
	current_health = max_health

	_load_boss_model()
	original_scale = model.scale

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	health_changed.emit(current_health, max_health)

	# Boss intro — brief camera shake + scale pop
	_boss_intro()

func _load_boss_model() -> void:
	var model_paths := {
		"goblin_king": "res://assets/models/bosses/goblin_king.glb",
		"spider_queen": "res://assets/models/bosses/spider_queen.glb",
		"slime_lord": "res://assets/models/bosses/slime_lord.glb",
		"forest_guardian": "res://assets/models/bosses/forest_guardian.glb",
		"crab_king": "res://assets/models/bosses/crab_king.glb",
		"kraken_spawn": "res://assets/models/bosses/kraken_spawn.glb",
	}

	var path = model_paths.get(boss_type, model_paths["goblin_king"])
	var scene := load(path) as PackedScene
	if scene:
		active_model = scene.instantiate()
		model.add_child(active_model)
		# Scale up — bosses are bigger
		model.scale = Vector3.ONE * model_scale
		_cache_mesh_instances()

func _boss_intro() -> void:
	# Scale pop entrance
	model.scale = Vector3.ZERO
	var tween = create_tween()
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * 1.3, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(model, "scale", Vector3.ONE * model_scale, 0.2)
	tween.tween_callback(func():
		GameManager.request_screen_shake(4.0, 0.3)
	)

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

	# Slam cooldown countdown
	if slam_cooldown_timer > 0.0:
		slam_cooldown_timer -= delta

	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		_return_to_spawn(delta)
		return

	var dist_to_hero = global_position.distance_to(hero.global_position)
	var dist_to_spawn = global_position.distance_to(spawn_position)

	# Boss aggro — wider range, never de-aggro once started
	if not is_aggroed and dist_to_hero < aggro_range:
		is_aggroed = true
		current_phase = Phase.PHASE_1
		_flash_color(Color(1.0, 0.1, 0.0), 0.2)
		GameManager.request_screen_shake(3.0, 0.2)

	# Leash (bosses have bigger leash)
	if is_aggroed and dist_to_spawn > leash_range:
		is_aggroed = false
		current_phase = Phase.IDLE
		current_health = max_health
		health_changed.emit(current_health, max_health)
		is_enraged = false
		_restore_model_materials()
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
			var effective_speed = move_speed * (1.4 if is_enraged else 1.0)
			current_speed = move_toward(current_speed, effective_speed, 15.0 * delta)
			velocity = direction * current_speed
			_face_position(hero.global_position, delta)
			new_state = AnimState.WALK

		# Try AoE slam when hero is close enough
		if dist_to_hero < SLAM_RADIUS and slam_cooldown_timer <= 0.0:
			_slam_attack()
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
	var cd = attack_cooldown * (0.7 if is_enraged else 1.0)
	attack_timer.start(cd)

	var dmg = attack_damage * (1.5 if is_enraged else 1.0)

	var tween = create_tween()
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(1.3, 0.8, 1.3), 0.12)
	tween.tween_callback(func():
		if is_instance_valid(hero) and hero.has_method("take_damage"):
			hero.take_damage(int(dmg))
		GameManager.request_screen_shake(2.0, 0.1)
	)
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(0.85, 1.15, 0.85), 0.1)
	tween.tween_property(model, "scale", Vector3.ONE * model_scale, 0.12)

func _slam_attack() -> void:
	slam_cooldown_timer = SLAM_COOLDOWN

	# Visual windup
	var tween = create_tween()
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(0.8, 1.5, 0.8), 0.3)
	tween.tween_callback(func():
		# Slam down
		var slam_tween = create_tween()
		slam_tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(1.5, 0.6, 1.5), 0.1)
		slam_tween.tween_callback(func():
			# Damage all enemies in radius
			var hero = GameManager.hero
			if is_instance_valid(hero) and hero.has_method("take_damage"):
				var dist = global_position.distance_to(hero.global_position)
				if dist <= SLAM_RADIUS:
					hero.take_damage(SLAM_DAMAGE)
			GameManager.request_screen_shake(6.0, 0.4)
			_spawn_slam_vfx()
		)
		slam_tween.tween_property(model, "scale", Vector3.ONE * model_scale, 0.3)
	)

func _spawn_slam_vfx() -> void:
	# Ring of expanding particles — simple tween-based ground shockwave
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 1.0
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.set_surface_override_material(0, mat)
	ring.position = global_position + Vector3.UP * 0.1
	ring.rotation_degrees.x = 90.0
	get_tree().current_scene.add_child(ring)

	var tween = create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * SLAM_RADIUS * 2.0, 0.4).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.tween_callback(ring.queue_free)

func take_damage(amount: int) -> void:
	if is_dead:
		return

	current_health -= amount
	health_changed.emit(current_health, max_health)
	is_aggroed = true

	if current_phase == Phase.IDLE:
		current_phase = Phase.PHASE_1

	GameManager.request_damage_number(global_position + Vector3.UP * 3.0, amount, amount > 50)
	_flash_color(Color.WHITE, 0.08)

	var hit_tween = create_tween()
	hit_tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(1.15, 0.85, 1.15), 0.05)
	hit_tween.tween_property(model, "scale", Vector3.ONE * model_scale, 0.1)

	# Phase transitions
	var hp_pct = float(current_health) / float(max_health)
	if hp_pct <= 0.5 and current_phase == Phase.PHASE_1:
		current_phase = Phase.PHASE_2
		_phase_transition()
	if hp_pct <= ENRAGE_THRESHOLD and not is_enraged:
		is_enraged = true
		_enrage()

	if current_health <= 0:
		_die()

func _phase_transition() -> void:
	# Visual burst — boss gets angrier
	GameManager.request_screen_shake(5.0, 0.3)
	_flash_color(Color(1.0, 0.5, 0.0), 0.3)
	var tween = create_tween()
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * 1.2, 0.2)
	tween.tween_property(model, "scale", Vector3.ONE * model_scale, 0.15)

func _enrage() -> void:
	# Boss glows red, attacks faster and harder
	current_phase = Phase.ENRAGED
	GameManager.request_screen_shake(8.0, 0.5)

	# Persistent red tint
	_set_model_color(Color(1.0, 0.3, 0.2))

	var tween = create_tween()
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * 1.4, 0.15)
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * 1.1, 0.2)

	# Slightly larger permanently when enraged
	model.scale = Vector3.ONE * model_scale * 1.1

func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	anim_state = AnimState.DEATH
	prev_anim_state = AnimState.DEATH

	boss_defeated.emit(boss_type)

	# Epic death — longer, more dramatic
	GameManager.request_screen_shake(10.0, 0.8)

	var tween = create_tween()
	# Stumble
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(1.3, 0.7, 1.3), 0.2)
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(0.8, 1.4, 0.8), 0.15)
	tween.tween_property(model, "scale", Vector3.ONE * model_scale * Vector3(1.1, 0.9, 1.1), 0.15)
	# Pause
	tween.tween_interval(0.5)
	# Collapse
	tween.tween_property(model, "scale", Vector3(2.0, 0.05, 2.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(model, "position:y", 0.02, 0.4)
	tween.parallel().tween_property(selection_circle, "scale", Vector3.ZERO, 0.3)
	# Final flash
	tween.tween_callback(func():
		_flash_color(Color.WHITE, 0.3)
		GameManager.request_screen_shake(5.0, 0.3)
	)
	tween.tween_interval(0.8)
	# Dissolve
	tween.tween_property(model, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	tween.tween_callback(func():
		GameManager.unregister_enemy(self)
		queue_free()
	)

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
	if not is_dead and not is_enraged:
		_restore_model_materials()
