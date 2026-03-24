extends Node

## Global game manager singleton.
## Handles screen shake, damage numbers, and global game state.

signal screen_shake_requested(intensity: float, duration: float)
signal damage_number_requested(position: Vector3, amount: int, is_crit: bool)
signal enemy_died(enemy: Node3D)
signal hero_target_changed(target: Node3D)

var hero: Node3D = null
var enemies: Array[Node3D] = []
var camera: Node3D = null

# Spell targeting state
var is_targeting_spell: bool = false
var targeting_spell_id: int = -1  # 0=Q, 1=W, 2=E, 3=R

func request_screen_shake(intensity: float, duration: float) -> void:
	screen_shake_requested.emit(intensity, duration)

func request_damage_number(pos: Vector3, amount: int, is_crit: bool = false) -> void:
	damage_number_requested.emit(pos, amount, is_crit)

func register_hero(h: Node3D) -> void:
	hero = h

func register_enemy(e: Node3D) -> void:
	enemies.append(e)

func unregister_enemy(e: Node3D) -> void:
	enemies.erase(e)
	enemy_died.emit(e)

func register_camera(c: Node3D) -> void:
	camera = c

func get_nearest_enemy(from_pos: Vector3, max_range: float = 999.0) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = max_range
	for e in enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var dist = from_pos.distance_to(e.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e
	return nearest

func get_enemies_in_range(from_pos: Vector3, radius: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for e in enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		if from_pos.distance_to(e.global_position) <= radius:
			result.append(e)
	return result
