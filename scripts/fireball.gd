extends Node3D

## Fireball projectile — travels to target, explodes on impact.

@export var speed: float = 18.0
@export var damage: int = 60
@export var aoe_radius: float = 4.0

var target_position: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO
var has_arrived: bool = false

@onready var mesh: MeshInstance3D = $FireballMesh
@onready var particles: GPUParticles3D = $TrailParticles
@onready var fire_light: OmniLight3D = $FireLight

func launch(target: Vector3) -> void:
	target_position = target
	target_position.y = 1.0
	direction = (target_position - global_position).normalized()

func _process(delta: float) -> void:
	if has_arrived:
		return

	global_position += direction * speed * delta

	# Rotate the fireball for visual effect
	if mesh:
		mesh.rotation.x += delta * 8.0
		mesh.rotation.z += delta * 5.0

	# Check if arrived at target
	var flat_pos = Vector3(global_position.x, 0, global_position.z)
	var flat_target = Vector3(target_position.x, 0, target_position.z)
	if flat_pos.distance_to(flat_target) < 0.5:
		_explode()

	# Safety: destroy if traveled too far
	if global_position.length() > 200:
		queue_free()

func _explode() -> void:
	has_arrived = true
	if mesh:
		mesh.visible = false
	if particles:
		particles.emitting = false
	if fire_light:
		var light_tween = create_tween()
		light_tween.tween_property(fire_light, "light_energy", 0.0, 0.3)

	# Damage enemies in AoE — scale with hero's spell power
	var hero = GameManager.hero
	var spell_power: float = 1.0
	if hero and hero.has_method("_get_spell_power"):
		spell_power = hero._get_spell_power()
	var final_damage = int(damage * spell_power)
	var enemies = GameManager.get_enemies_in_range(global_position, aoe_radius)
	for e in enemies:
		if e.has_method("take_damage"):
			e.take_damage(final_damage)

	# Explosion sound
	AudioManager.on_fireball_explode()
	# Screen shake
	GameManager.request_screen_shake(5.0, 0.25)

	# Spawn explosion particles
	var explosion = preload("res://scenes/explosion_particles.tscn").instantiate()
	get_tree().root.add_child(explosion)
	explosion.global_position = global_position
	explosion.emitting = true

	# Self destruct after particles finish
	await get_tree().create_timer(2.0).timeout
	queue_free()
