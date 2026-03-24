extends Node3D

## Ice Shard projectile — piercing frost missile that slows on impact.

@export var speed: float = 22.0
@export var damage: int = 45
@export var aoe_radius: float = 3.0
@export var slow_duration: float = 2.0

var target_position: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.ZERO
var has_arrived: bool = false

@onready var mesh: MeshInstance3D = $ShardMesh
@onready var frost_trail: GPUParticles3D = $FrostTrail
@onready var ice_light: OmniLight3D = $IceLight

func launch(target: Vector3) -> void:
	target_position = target
	target_position.y = 1.0
	direction = (target_position - global_position).normalized()
	# Point shard in travel direction
	look_at(target_position, Vector3.UP)

func _process(delta: float) -> void:
	if has_arrived:
		return

	global_position += direction * speed * delta

	# Spin the shard for visual flair
	if mesh:
		mesh.rotate_y(delta * 12.0)

	# Check arrival
	var flat_pos = Vector3(global_position.x, 0, global_position.z)
	var flat_target = Vector3(target_position.x, 0, target_position.z)
	if flat_pos.distance_to(flat_target) < 0.5:
		_impact()

	# Safety: destroy if too far
	if global_position.length() > 200:
		queue_free()

func _impact() -> void:
	has_arrived = true
	if mesh:
		mesh.visible = false
	if frost_trail:
		frost_trail.emitting = false
	if ice_light:
		var light_tween = create_tween()
		light_tween.tween_property(ice_light, "light_energy", 0.0, 0.4)

	# Damage enemies in AoE
	var enemies = GameManager.get_enemies_in_range(global_position, aoe_radius)
	for e in enemies:
		if e.has_method("take_damage"):
			e.take_damage(damage)
			RunStats.record_damage_dealt(damage)
		# Apply slow via status effect system
		StatusEffectManager.apply_slow(e, slow_duration, 0.6)

	# Impact sound
	AudioManager.on_hero_cast_ice_shard()
	# Screen shake (lighter than fireball)
	GameManager.request_screen_shake(3.0, 0.15)

	# Spawn frost burst particles
	var burst = preload("res://scenes/frost_burst_particles.tscn").instantiate()
	get_tree().root.add_child(burst)
	burst.global_position = global_position
	burst.emitting = true

	# Self destruct
	await get_tree().create_timer(2.0).timeout
	queue_free()
