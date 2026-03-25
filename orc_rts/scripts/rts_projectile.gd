class_name RTSProjectile
extends Node3D

## Homing projectile that always hits. Travels toward target with
## a fixed speed, deals damage on contact.

var _target: RTSUnit = null
var _damage: int = 0
var _speed: float = 15.0
var _source: RTSUnit = null
var _last_target_pos: Vector3 = Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh

func setup(target: RTSUnit, damage: int, speed: float, source: RTSUnit) -> void:
	_target = target
	_damage = damage
	_speed = speed
	_source = source
	if target and is_instance_valid(target):
		_last_target_pos = target.global_position + Vector3.UP * 1.0

func _physics_process(delta: float) -> void:
	# Update target position if still alive
	if _target and is_instance_valid(_target) and not _target.is_dead:
		_last_target_pos = _target.global_position + Vector3.UP * 1.0

	var direction: Vector3 = _last_target_pos - global_position
	var dist: float = direction.length()

	if dist < 0.3:
		# Hit!
		if _target and is_instance_valid(_target) and not _target.is_dead:
			_target.take_damage(_damage, _source)
		_explode()
		return

	direction = direction.normalized()
	global_position += direction * _speed * delta

	# Face travel direction
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

	# Timeout safety — kill after 5 seconds
	if Engine.get_physics_frames() % 300 == 0:
		queue_free()

func _explode() -> void:
	# Brief flash then remove
	if _mesh:
		var mat: StandardMaterial3D = _mesh.get_surface_override_material(0)
		if mat:
			mat.emission_energy_multiplier = 5.0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.15)
	tween.tween_callback(queue_free)
