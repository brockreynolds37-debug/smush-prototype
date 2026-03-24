extends FloorArchetype

## CrawlArchetype — the standard dungeon crawl. Kill all enemies, find the exit.
## This is the default archetype that matches existing gameplay.

class_name CrawlArchetype

func _init() -> void:
	archetype_name = "Dungeon Crawl"
	flavor_text = "Clear the floor. Find the exit. Survive."
	accent_color = Color(0.7, 0.6, 0.4)
	solution_paths = {"combat": true, "speed": true, "social": false, "clever": true}
	audience_favorite_path = "combat"

func _register_solution_paths() -> void:
	SolutionPathTracker.register_floor_paths(
		SolutionPathTracker.paths_crawl(), "combat"
	)

func start() -> void:
	super.start()
	# Standard crawl: exit unlocks when all enemies are dead
	GameManager.all_enemies_cleared.connect(_on_enemies_cleared)
	show_message("DUNGEON CRAWL — Clear all enemies to open the exit.", accent_color, 3.0)

func _on_enemies_cleared() -> void:
	if not _is_active:
		return
	show_message("EXIT UNLOCKED!", Color(0.2, 1.0, 0.4), 2.5)

func stop() -> void:
	super.stop()
	if GameManager.all_enemies_cleared.is_connected(_on_enemies_cleared):
		GameManager.all_enemies_cleared.disconnect(_on_enemies_cleared)

func has_boss() -> bool:
	return true

func uses_default_enemy_spawning() -> bool:
	return true

func exit_visible_at_start() -> bool:
	return false
