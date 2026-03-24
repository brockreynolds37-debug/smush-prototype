extends FloorArchetype

## SurvivalArenaArchetype — locked arena, survive waves of enemies.
## Full implementation in Task 43.

class_name SurvivalArenaArchetype

func _init() -> void:
	archetype_name = "Survival Arena"
	flavor_text = "The exits are sealed. Survive the onslaught."
	accent_color = Color(0.9, 0.2, 0.2)

func start() -> void:
	super.start()
	show_message("SURVIVAL ARENA — Defeat all waves to escape!", accent_color, 3.0)

func has_boss() -> bool:
	return false

func has_smusher() -> bool:
	return false

func exit_visible_at_start() -> bool:
	return false

func uses_default_enemy_spawning() -> bool:
	return false
