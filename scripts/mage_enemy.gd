extends CharacterBody3D

## Mage/caster enemy — telegraphs AoE circles on ground, delayed damage burst.
## Uses goblin_shaman model. Prioritizes range, kites when hero closes in.

signal health_changed(current: int, maximum: int)

@export var max_health: int = 55
@export var move_speed: float = 3.8
@export var aggro_range: float = 18.0
@export var preferred_range: float = 12.0   # Sweet spot for casting
@export var min_range: float = 6.0          # Too close — retreat
@export var attack_damage: int = 25
@export var attack_cooldown: float = 3.0    # Slow but hits hard
@export var aoe_radius: float = 2.5
@export var telegraph_duration: float = 1.2  # Warning before damage

@export var enemy_type: String = "goblin_shaman"

var current_health: int = 55
var is_dead: bool = false
var is_aggroed: bool = false
var current_speed: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var leash_range: float = 25.0

var original_scale := Vector3.ONE
var _cached_mesh_instances: Array[MeshInstance3D] = []

# Status effects
var _base_move_speed: float = 3.8
var _is_stunned: bool = false
var _slow_amount: float = 0.0

# Animation
enum AnimState { IDLE, WALK, ATTACK, DEATH }
var anim_state: AnimState = AnimState.IDLE
var prev_anim_state: AnimState = AnimState.IDLE

var anim_scenes: Dictionary = {}
var active_model: Node3D = null
var active_anim_player: AnimationPlayer = null

# Casting state
var _is_casting: bool = false
var _cast_timer: float = 0.0

# Kiting
var _kite_direction: Vector3 = Vector3.ZERO
var _kite_timer: float = 0.0
const KITE_CHANGE_INTERVAL: float = 1.8

@onready var model: Node3D = $EnemyModel
@onready var selection_circle: MeshInstance3D = $SelectionCircle
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var attack_timer: Timer = $AttackTimer

func _ready() -> void:
	add_to_group("enemies")
	GameManager.register_enemy(self)
	spawn_position = global_position
	current_health = max_health
	_base_move_speed = move_speed

	_load_enemy_model()
	original_scale = model.scale

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.max_speed = move_speed

	health_changed.emit(current_health, max_health)

func _load_enemy_model() -> void:
	var model_paths := {
		"goblin_shaman": "res://assets/models/enemies/goblin_shaman.glb",
	}

	if model_paths.has(enemy_type):
		anim_scenes = {}
		var scene := load(model_paths[enemy_type]) as PackedScene
		if scene:
			active_model = scene.instantiate()
			model.add_child(active_model)
			_cache_mesh_instances()
	else:
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

	# If casting, hold position and wait
	if _is_casting:
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
		_flash_color(Color(0.6, 0.2, 1.0), 0.15)  # Purple flash

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
			# Too close — retreat away from hero
			var away_dir = (global_position - hero.global_position).normalized()
			away_dir.y = 0
			_kite_timer += delta
			if _kite_timer >= KITE_CHANGE_INTERVAL:
				_kite_timer = 0.0
				var lateral = Vector3(-away_dir.z, 0, away_dir.x)
				if randf() > 0.5:
					lateral = -lateral
				_kite_direction = (away_dir + lateral * 0.4).normalized()
			if _kite_direction == Vector3.ZERO:
				_kite_direction = away_dir

			current_speed = move_toward(current_speed, move_speed * 1.2, 12.0 * delta)
			velocity = _kite_direction * current_speed
			new_state = AnimState.WALK

			# Panic cast while fleeing if attack is ready
			_try_cast_aoe(hero)

		elif dist_to_hero <= preferred_range:
			# In cast range — strafe slowly and cast
			_kite_timer += delta
			if _kite_timer >= KITE_CHANGE_INTERVAL:
				_kite_timer = 0.0
				var to_hero = (hero.global_position - global_position).normalized()
				var lateral = Vector3(-to_hero.z, 0, to_hero.x)
				if randf() > 0.5:
					lateral = -lateral
				_kite_direction = lateral

			if _kite_direction != Vector3.ZERO:
				current_speed = move_toward(current_speed, move_speed * 0.4, 8.0 * delta)
				velocity = _kite_direction * current_speed
				new_state = AnimState.WALK
			else:
				current_speed = 0.0
				velocity = Vector3.ZERO
				new_state = AnimState.IDLE

			_try_cast_aoe(hero)

		else:
			# Too far — close the gap
			nav_agent.target_position = hero.global_position
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
			direction.y = 0
			current_speed = move_toward(current_speed, move_speed, 12.0 * delta)
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

func _try_cast_aoe(hero: Node3D) -> void:
	if not attack_timer.is_stopped():
		return
	attack_timer.start(attack_cooldown)
	_begin_cast(hero)

func _begin_cast(hero: Node3D) -> void:
	_is_casting = true

	# Wind-up: mage glows purple and grows slightly
	var tween = create_tween()
	tween.tween_property(model, "scale", original_scale * Vector3(0.9, 1.3, 0.9), 0.2)
	_set_model_color(Color(0.6, 0.2, 1.0))

	# Narrator callout
	Narrator.announce_mage_cast()

	# Spawn telegraph circle at hero's current position
	var target_pos = hero.global_position if is_instance_valid(hero) else global_position + Vector3.FORWARD * 5.0
	target_pos.y = 0.1  # Just above floor
	_spawn_aoe_telegraph(target_pos)

	# After telegraph_duration, deal damage and release
	await get_tree().create_timer(telegraph_duration).timeout
	if is_dead:
		return

	_detonate_aoe(target_pos)

	# Cast recoil animation
	var recoil = create_tween()
	recoil.tween_property(model, "scale", original_scale * Vector3(1.15, 0.85, 1.15), 0.1)
	recoil.tween_property(model, "scale", original_scale, 0.15)
	_restore_model_materials()

	_is_casting = false

func _spawn_aoe_telegraph(pos: Vector3) -> void:
	# Create a glowing circle on the ground as warning
	var telegraph = MeshInstance3D.new()
	var circle_mesh = PlaneMesh.new()
	circle_mesh.size = Vector2(aoe_radius * 2.0, aoe_radius * 2.0)
	telegraph.mesh = circle_mesh

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.1, 1.0, 0.15)  # Faint purple
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.0, 1.0)
	mat.emission_energy_multiplier = 0.5
	mat.no_depth_test = true
	telegraph.material_override = mat

	telegraph.global_position = pos
	get_tree().root.add_child(telegraph)

	# Animate: grow brighter over telegraph_duration, then flash and remove
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color", Color(1.0, 0.2, 0.8, 0.6), telegraph_duration * 0.8)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 3.0, telegraph_duration * 0.8)
	# Final flash
	tween.tween_property(mat, "albedo_color", Color(1.0, 1.0, 1.0, 0.9), telegraph_duration * 0.2)
	tween.tween_callback(func():
		telegraph.queue_free()
	)

func _detonate_aoe(pos: Vector3) -> void:
	# Damage hero if in radius
	var hero = GameManager.hero
	if hero and is_instance_valid(hero) and not hero.is_dead:
		var dist = Vector3(hero.global_position.x, 0, hero.global_position.z).distance_to(Vector3(pos.x, 0, pos.z))
		if dist <= aoe_radius:
			var dmg = attack_damage
			# Elite: venomous adds poison
			if has_meta("venomous_dot") and get_meta("venomous_dot"):
				StatusEffectManager.apply_poison(hero, 5.0, 8, 1.0)
			# Elite: vampiric heals
			if has_meta("vampiric_leech"):
				var leech_pct: float = get_meta("vampiric_leech")
				var heal_amount := int(dmg * leech_pct)
				current_health = mini(current_health + heal_amount, max_health)
				health_changed.emit(current_health, max_health)
			if hero.has_method("take_damage"):
				hero.take_damage(dmg)

	# Also damage any enemies caught in friendly fire? No — mage is smart.

	# Detonation VFX: purple burst
	var burst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	burst.mesh = sphere
	var burst_mat = StandardMaterial3D.new()
	burst_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst_mat.albedo_color = Color(0.8, 0.1, 1.0, 0.8)
	burst_mat.emission_enabled = true
	burst_mat.emission = Color(0.7, 0.0, 1.0)
	burst_mat.emission_energy_multiplier = 5.0
	burst.material_override = burst_mat
	burst.global_position = pos + Vector3.UP * 0.5
	get_tree().root.add_child(burst)

	var burst_tween = create_tween()
	burst_tween.tween_property(burst, "scale", Vector3(aoe_radius, aoe_radius, aoe_radius), 0.15)
	burst_tween.parallel().tween_property(burst_mat, "albedo_color", Color(0.8, 0.1, 1.0, 0.0), 0.4)
	burst_tween.tween_callback(func():
		burst.queue_free()
	)

	# Sound + screen shake
	AudioManager.play_sfx("lightning_strike", 0.6, 0.2)
	GameManager.request_screen_shake(4.0, 0.15)

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
	_is_casting = false
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
