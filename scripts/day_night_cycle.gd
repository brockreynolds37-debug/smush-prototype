extends Node

## DayNightCycle — autoload controlling floor lighting.
## Odd floors = day, even floors = night.
## Night: dim ambient to 0.1, spawn 2 shadow wolves, minimap vision -3.
## Torch item restores vision on night floors.

signal cycle_changed(is_night: bool)

var is_night: bool = false
var _has_torch: bool = false
var _shadow_wolves_spawned: bool = false

const NIGHT_AMBIENT_ENERGY: float = 0.25
const DAY_AMBIENT_ENERGY: float = 0.8
const SHADOW_WOLF_COUNT: int = 2
const MINIMAP_VISION_PENALTY: int = 3

func _ready() -> void:
	FloorManager.floor_changed.connect(_on_floor_changed)

func _on_floor_changed(floor_number: int) -> void:
	var was_night = is_night
	is_night = (floor_number % 2 == 0) and floor_number > 0
	_shadow_wolves_spawned = false
	_check_torch()

	if is_night != was_night:
		cycle_changed.emit(is_night)

	# Apply lighting changes after a frame (so dungeon builder has finished)
	await get_tree().process_frame
	_apply_lighting()

	if is_night:
		_spawn_shadow_wolves()

func _apply_lighting() -> void:
	# Find the WorldEnvironment in the scene
	var env_node = _find_world_environment(get_tree().root)
	if env_node and env_node.environment:
		if is_night and not _has_torch:
			env_node.environment.ambient_light_energy = NIGHT_AMBIENT_ENERGY
			env_node.environment.fog_density = 0.03
		else:
			# Day or has torch — use theme defaults (already applied by builder)
			pass

	# Adjust directional lights
	var lights = _find_nodes_of_type(get_tree().root, "DirectionalLight3D")
	for light in lights:
		if is_night and not _has_torch:
			light.light_energy = 0.35
		# Day lighting is set by dungeon builder, no override needed

func _spawn_shadow_wolves() -> void:
	if _shadow_wolves_spawned:
		return
	_shadow_wolves_spawned = true

	var hero = GameManager.hero
	if not hero:
		return

	for i in range(SHADOW_WOLF_COUNT):
		var enemy_scene = load("res://scenes/enemy.tscn")
		if not enemy_scene:
			return
		var wolf = enemy_scene.instantiate()
		wolf.enemy_type = "wolf"
		wolf.max_health = 200  # Tougher shadow variant
		wolf.attack_damage = 25

		var offset = Vector3(randf_range(-8.0, 8.0), 0, randf_range(-8.0, 8.0))
		wolf.position = hero.global_position + offset

		get_tree().root.add_child(wolf)

func _check_torch() -> void:
	_has_torch = false
	if not LootManager:
		return
	# Check if hero has equipped a torch
	for slot_key in LootManager.equipped:
		var item = LootManager.equipped[slot_key]
		if item.get("id", "") == "torch":
			_has_torch = true
			break

func equip_torch() -> void:
	_has_torch = true
	if is_night:
		_apply_lighting()

## Get minimap vision radius modifier
func get_vision_modifier() -> int:
	if is_night and not _has_torch:
		return -MINIMAP_VISION_PENALTY
	return 0

func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child in node.get_children():
		var found = _find_world_environment(child)
		if found:
			return found
	return null

func _find_nodes_of_type(node: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	if node.get_class() == type_name:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_nodes_of_type(child, type_name))
	return result
