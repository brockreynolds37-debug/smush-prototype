extends CharacterBody3D

## SummonMinion — AI-controlled ally that follows hero and attacks enemies.
## Follows hero at 3 units distance, attacks nearest enemy within 8 units.

class_name SummonMinion

signal minion_died(minion: Node3D)

const FOLLOW_DISTANCE: float = 3.0
const ATTACK_RANGE: float = 8.0
const ATTACK_MELEE_RANGE: float = 2.0
const MOVE_SPEED: float = 4.5
const TURN_RATE: float = 180.0  # Degrees per second (WC3-style pivot)
const ATTACK_COOLDOWN: float = 1.2
const LIFESPAN: float = 30.0  # Summons last 30 seconds

var max_health: int = 150
var current_health: int = 150
var attack_damage: int = 15
var is_dead: bool = false
var _attack_timer: float = 0.0
var _lifespan_timer: float = LIFESPAN
var _target: Node3D = null
var _model: Node3D = null
var _label: Label3D = null

func _ready() -> void:
	# Build visual — skeleton model or placeholder
	_model = Node3D.new()
	_model.name = "MinionModel"
	add_child(_model)

	# Try to load skeleton model, fall back to capsule
	var skel_path := "res://assets/models/enemies/skeleton.glb"
	var skel_res = load(skel_path)
	if skel_res:
		var skel_inst = skel_res.instantiate()
		skel_inst.scale = Vector3(0.8, 0.8, 0.8)
		_model.add_child(skel_inst)
		# Tint blue to distinguish from enemy skeletons
		_tint_model(skel_inst, Color(0.4, 0.6, 1.0))
	else:
		var mesh = MeshInstance3D.new()
		var capsule = CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.4
		mesh.mesh = capsule
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.6, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.4, 0.8)
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat
		mesh.position.y = 0.7
		_model.add_child(mesh)

	# Label
	_label = Label3D.new()
	_label.text = "Summon"
	_label.font_size = 24
	_label.modulate = Color(0.5, 0.7, 1.0)
	_label.position = Vector3(0, 2.0, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

	# Collision
	var col = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	col.shape = shape
	col.position.y = 0.8
	add_child(col)

	collision_layer = 2  # Units layer
	collision_mask = 1 | 3  # Ground + Obstacles

	# Spawn VFX — scale-in burst
	_model.scale = Vector3(0.01, 0.01, 0.01)
	var spawn_tw = create_tween()
	spawn_tw.tween_property(_model, "scale", Vector3(1.2, 0.8, 1.2), 0.15)
	spawn_tw.tween_property(_model, "scale", Vector3.ONE, 0.1)
	VFXManager.spawn_spell_impact(global_position, Color(0.4, 0.6, 1.0), 2.0)

func _tint_model(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count() if mi.mesh else 0):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color * 0.3
			mat.emission_energy_multiplier = 0.8
			mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_tint_model(child, color)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Lifespan countdown
	_lifespan_timer -= delta
	if _lifespan_timer <= 0.0:
		_die()
		return

	# Flash when about to expire
	if _lifespan_timer <= 5.0 and _label:
		_label.text = "Summon [%ds]" % ceili(_lifespan_timer)
		_label.modulate.a = 0.5 + sin(Time.get_ticks_msec() * 0.01) * 0.5

	_attack_timer = maxf(_attack_timer - delta, 0.0)

	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Find attack target
	_target = GameManager.get_nearest_enemy(global_position, ATTACK_RANGE)

	if _target and is_instance_valid(_target) and not _target.is_dead:
		var dist_to_target = global_position.distance_to(_target.global_position)
		if dist_to_target <= ATTACK_MELEE_RANGE:
			# Attack
			velocity = Vector3.ZERO
			_face_position(_target.global_position, delta)
			_try_attack()
		else:
			# Chase target
			var dir = (_target.global_position - global_position).normalized()
			dir.y = 0
			velocity = dir * MOVE_SPEED
			_face_position(_target.global_position, delta)
	else:
		# Follow hero at distance
		var dist_to_hero = global_position.distance_to(hero.global_position)
		if dist_to_hero > FOLLOW_DISTANCE:
			var dir = (hero.global_position - global_position).normalized()
			dir.y = 0
			velocity = dir * MOVE_SPEED
			_face_position(hero.global_position, delta)
		else:
			velocity = Vector3.ZERO

	move_and_slide()

func _face_position(target: Vector3, delta: float) -> void:
	var look_dir = (target - global_position)
	look_dir.y = 0
	if look_dir.length_squared() < 0.001:
		return
	var target_rot = atan2(look_dir.x, look_dir.z)
	# Turn-rate capped rotation (WC3-style pivot)
	var max_turn := deg_to_rad(TURN_RATE) * delta
	var diff := angle_difference(rotation.y, target_rot)
	rotation.y += clampf(diff, -max_turn, max_turn)

func _try_attack() -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = ATTACK_COOLDOWN

	if _target and is_instance_valid(_target) and _target.has_method("take_damage"):
		_target.take_damage(attack_damage)
		# Attack squash animation
		var tween = create_tween()
		tween.tween_property(_model, "scale", Vector3(1.2, 0.8, 1.2), 0.08)
		tween.tween_property(_model, "scale", Vector3.ONE, 0.08)

## Scale minion stats by hero's spell power multiplier.
func apply_spell_power(spell_power: float) -> void:
	max_health = int(max_health * spell_power)
	current_health = max_health
	attack_damage = int(attack_damage * spell_power)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	current_health -= amount
	if current_health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	minion_died.emit(self)
	var tween = create_tween()
	tween.tween_property(_model, "scale", Vector3(1.5, 0.05, 1.5), 0.3)
	tween.tween_callback(queue_free)
