extends CharacterBody3D

## SummonMinion — AI-controlled ally that follows hero and attacks enemies.
## Follows hero at 3 units distance, attacks nearest enemy within 8 units.

class_name SummonMinion

signal minion_died(minion: Node3D)

const FOLLOW_DISTANCE: float = 3.0
const ATTACK_RANGE: float = 8.0
const ATTACK_MELEE_RANGE: float = 2.0
const MOVE_SPEED: float = 7.0
const ATTACK_COOLDOWN: float = 1.2

var max_health: int = 150
var current_health: int = 150
var attack_damage: int = 15
var is_dead: bool = false
var _attack_timer: float = 0.0
var _target: Node3D = null
var _model: Node3D = null

func _ready() -> void:
	# Build visual — skeleton model or placeholder
	_model = Node3D.new()
	_model.name = "MinionModel"
	add_child(_model)

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
	var label = Label3D.new()
	label.text = "Summon"
	label.font_size = 24
	label.modulate = Color(0.5, 0.7, 1.0)
	label.position = Vector3(0, 2.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

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

func _physics_process(delta: float) -> void:
	if is_dead:
		return

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
	rotation.y = lerp_angle(rotation.y, target_rot, 10.0 * delta)

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
