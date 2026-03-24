extends Node

## Global game manager singleton.
## Handles screen shake, damage numbers, and global game state.

signal screen_shake_requested(intensity: float, duration: float)
signal damage_number_requested(position: Vector3, amount: int, is_crit: bool)
signal enemy_died(enemy: Node3D)
signal hero_target_changed(target: Node3D)
signal game_over(won: bool)

enum GameState { PLAYING, WON, LOST }
var game_state: GameState = GameState.PLAYING

var hero: Node3D = null
var enemies: Array[Node3D] = []
var camera: Node3D = null
var total_enemies_spawned: int = 0

# Run statistics
var run_start_time: float = 0.0
var run_kills: int = 0
var run_damage_dealt: int = 0
var run_gold_earned: int = 0
const MAX_FLOOR: int = 3

# Spell targeting state
var is_targeting_spell: bool = false
var targeting_spell_id: int = -1  # 0=Q, 1=W, 2=E, 3=R

func request_screen_shake(intensity: float, duration: float) -> void:
	screen_shake_requested.emit(intensity, duration)

func request_damage_number(pos: Vector3, amount: int, is_crit: bool = false) -> void:
	damage_number_requested.emit(pos, amount, is_crit)

func start_run() -> void:
	run_start_time = Time.get_ticks_msec() / 1000.0
	RunStats.start_run()

func get_run_elapsed() -> float:
	return Time.get_ticks_msec() / 1000.0 - run_start_time

func get_run_time_string() -> String:
	var elapsed = get_run_elapsed()
	var minutes = int(elapsed) / 60
	var seconds = int(elapsed) % 60
	return "%d:%02d" % [minutes, seconds]

func register_hero(h: Node3D) -> void:
	hero = h
	if h.has_signal("hero_died"):
		h.hero_died.connect(_on_hero_died)

func register_enemy(e: Node3D) -> void:
	enemies.append(e)
	total_enemies_spawned += 1

func unregister_enemy(e: Node3D) -> void:
	enemies.erase(e)
	run_kills += 1
	enemy_died.emit(e)
	_check_win_condition()

func _on_hero_died() -> void:
	if game_state != GameState.PLAYING:
		return
	game_state = GameState.LOST
	game_over.emit(false)

signal all_enemies_cleared  # Emitted when floor is cleared (enemies dead)

func on_boss_defeated(_boss_type: String) -> void:
	# If the final floor boss is killed, trigger victory
	if FloorManager.current_floor >= MAX_FLOOR:
		if game_state == GameState.PLAYING:
			game_state = GameState.WON
			game_over.emit(true)
			return

func _check_win_condition() -> void:
	if game_state != GameState.PLAYING:
		return
	# When all enemies on this floor are dead
	if total_enemies_spawned > 0 and enemies.size() == 0:
		all_enemies_cleared.emit()

func reset_game_state() -> void:
	game_state = GameState.PLAYING
	total_enemies_spawned = 0
	enemies.clear()
	hero = null
	run_kills = 0
	run_damage_dealt = 0
	run_gold_earned = 0
	run_start_time = 0.0
	XpManager.reset()
	AudienceManager.reset()
	StatusEffectManager.reset()
	FloorManager.reset()
	RunStats.reset()

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
