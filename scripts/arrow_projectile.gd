extends Node3D

## Arrow projectile — travels in a line, damages hero on hit.

@export var speed: float = 22.0
@export var damage: int = 12

var direction: Vector3 = Vector3.ZERO
var has_hit: bool = false
var _traveled: float = 0.0
const MAX_RANGE: float = 30.0

@onready var mesh: MeshInstance3D = $ArrowMesh

func launch(target_pos: Vector3) -> void:
	var dir = (target_pos - global_position)
	dir.y = 0
	direction = dir.normalized()
	# Face the arrow along its travel direction
	if direction.length_squared() > 0.001:
		rotation.y = atan2(direction.x, direction.z)

func _process(delta: float) -> void:
	if has_hit:
		return

	var move = direction * speed * delta
	global_position += move
	_traveled += move.length()

	# Check hit against hero
	var hero = GameManager.hero
	if hero and is_instance_valid(hero) and not hero.is_dead:
		var dist = global_position.distance_to(hero.global_position + Vector3.UP * 0.8)
		if dist < 1.2:
			_hit_hero(hero)
			return

	# Destroy if traveled too far
	if _traveled > MAX_RANGE:
		queue_free()

func _hit_hero(hero: Node3D) -> void:
	has_hit = true
	if hero.has_method("take_damage"):
		hero.take_damage(damage)
	GameManager.request_screen_shake(1.5, 0.1)
	AudioManager.play_sfx("melee_hit", 0.6)

	# Brief flash then destroy
	if mesh:
		mesh.visible = false
	await get_tree().create_timer(0.1).timeout
	queue_free()
