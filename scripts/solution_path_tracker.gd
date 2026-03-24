extends Node

## SolutionPathTracker — tracks which solution path the player uses per floor.
## Each FloorArchetype declares supported paths via register_floor_paths().
## Detects player actions and determines the dominant approach.
## Narrator and Audience react differently per path. History persists across floors.

signal path_changed(new_path: String, old_path: String)
signal path_score_updated(path: String, score: int)
signal floor_path_finalized(floor_num: int, path: String, archetype_name: String)

# ----- Path Definitions -----
enum Path { COMBAT, SPEED, SOCIAL, CLEVER }
const PATH_NAMES := ["combat", "speed", "social", "clever"]
const PATH_LABELS := {
	"combat": "Brute Force",
	"speed": "Speedrunner",
	"social": "Silver Tongue",
	"clever": "Trickster",
}
const PATH_COLORS := {
	"combat": Color(1.0, 0.3, 0.2),
	"speed": Color(0.2, 0.8, 1.0),
	"social": Color(1.0, 0.85, 0.2),
	"clever": Color(0.4, 1.0, 0.4),
}

# ----- Per-Floor State -----
var scores: Dictionary = {"combat": 0, "speed": 0, "social": 0, "clever": 0}
var current_path: String = "combat"
var _floor_start_time: float = 0.0
var _floor_kills: int = 0

## Archetype-declared paths for this floor: { "combat": { "name": "...", "desc": "..." }, ... }
var _floor_paths: Dictionary = {}

## Which path the audience favors this floor (set by archetype)
var archetype_preferred_path: String = "combat"

# ----- Run History -----
## Array of { floor_num, archetype, path, scores }
var floor_history: Array[Dictionary] = []
## Rolling window of last 3 floor paths (for Collective curation)
var last_three_paths: Array[String] = []

func _ready() -> void:
	GameManager.enemy_died.connect(_on_enemy_died)
	FloorManager.floor_changed.connect(_on_floor_changed)
	GameManager.all_enemies_cleared.connect(_on_all_cleared)

# ── Archetype Registration ──

func register_floor_paths(paths: Dictionary, favorite: String = "combat") -> void:
	## Called by FloorArchetype subclasses in start() to declare supported paths.
	## paths: { "combat": { "name": "Brute Force", "desc": "Kill everything." }, ... }
	_floor_paths = paths
	archetype_preferred_path = favorite

func get_floor_path_info(path_id: String) -> Dictionary:
	return _floor_paths.get(path_id, {})

# ── Pre-built path configs for each archetype ──

static func paths_crawl() -> Dictionary:
	return {
		"combat": {"name": "Brute Force", "desc": "Kill everything in sight."},
		"speed": {"name": "Speedrun", "desc": "Rush to the exit, skip fights."},
		"clever": {"name": "Resourceful", "desc": "Use traps, environment, summons."},
	}

static func paths_stealth() -> Dictionary:
	return {
		"combat": {"name": "Berserker", "desc": "Fight through the patrols head-on."},
		"speed": {"name": "Ghost Run", "desc": "Sprint past everything unseen."},
		"clever": {"name": "Shadow Operative", "desc": "Backstabs, distractions, precision."},
		"social": {"name": "Disguised", "desc": "Blend in and walk past guards."},
	}

static func paths_economy() -> Dictionary:
	return {
		"social": {"name": "Merchant Prince", "desc": "Trade, negotiate, earn the key."},
		"combat": {"name": "Robbery", "desc": "Kill the guards, take everything."},
		"clever": {"name": "Con Artist", "desc": "Gamble, steal, exploit the system."},
		"speed": {"name": "Quick Flip", "desc": "Buy low, sell high, get out fast."},
	}

static func paths_political() -> Dictionary:
	return {
		"social": {"name": "Diplomat", "desc": "Win the election through alliances."},
		"combat": {"name": "Assassin", "desc": "Kill the mayor. Simple."},
		"clever": {"name": "Puppeteer", "desc": "Bribe and manipulate from the shadows."},
	}

static func paths_boss_rush() -> Dictionary:
	return {
		"combat": {"name": "Gladiator", "desc": "Pure combat mastery."},
		"clever": {"name": "Tactician", "desc": "Use environment and summons vs bosses."},
		"speed": {"name": "Speedkill", "desc": "Down each boss in record time."},
	}

static func paths_survival() -> Dictionary:
	return {
		"combat": {"name": "Slayer", "desc": "Kill everything aggressively."},
		"clever": {"name": "Survivor", "desc": "Kite, trap, and outlast the waves."},
		"speed": {"name": "Wave Rusher", "desc": "Clear waves before they pile up."},
	}

static func paths_escape() -> Dictionary:
	return {
		"speed": {"name": "Sprinter", "desc": "Pure speed, dodge everything."},
		"combat": {"name": "Bulldozer", "desc": "Fight through obstacles."},
		"clever": {"name": "Pathfinder", "desc": "Find shortcuts and alternate routes."},
	}

static func paths_inversion() -> Dictionary:
	return {
		"combat": {"name": "Frontliner", "desc": "Personally fight the crawlers."},
		"clever": {"name": "Architect", "desc": "Traps and minions do all the work."},
	}

static func paths_race() -> Dictionary:
	return {
		"speed": {"name": "Racer", "desc": "Pure speed, first place."},
		"clever": {"name": "Shortcutter", "desc": "Find alternate routes and boosts."},
		"combat": {"name": "Enforcer", "desc": "Smash obstacles and ghosts aside."},
	}

# ── Action Recording ──

func record_kill() -> void:
	_floor_kills += 1
	_add_score("combat", 10)

func record_npc_interaction() -> void:
	_add_score("social", 20)

func record_bribe() -> void:
	_add_score("social", 30)

func record_persuasion() -> void:
	_add_score("social", 25)

func record_quest_complete() -> void:
	_add_score("social", 35)

func record_disguise_used() -> void:
	_add_score("social", 25)
	_add_score("clever", 10)

func record_door_opened_social() -> void:
	_add_score("social", 15)

func record_environmental_kill() -> void:
	_add_score("clever", 35)

func record_trap_used_on_enemy() -> void:
	_add_score("clever", 25)

func record_creative_item_use() -> void:
	_add_score("clever", 20)

func record_secret_found() -> void:
	_add_score("clever", 40)

func record_stealth_bypass() -> void:
	_add_score("speed", 15)
	_add_score("clever", 10)

func record_smush_lure_kill() -> void:
	_add_score("clever", 30)

func record_speed_checkpoint() -> void:
	_add_score("speed", 15)

# ── Internal Scoring ──

func _add_score(path: String, amount: int) -> void:
	scores[path] = scores.get(path, 0) + amount
	path_score_updated.emit(path, scores[path])
	_recalculate_dominant_path()

func _recalculate_dominant_path() -> void:
	var best_path := "combat"
	var best_score := 0
	for p in PATH_NAMES:
		if scores.get(p, 0) > best_score:
			best_score = scores.get(p, 0)
			best_path = p
	if best_path != current_path:
		var old := current_path
		current_path = best_path
		path_changed.emit(current_path, old)

# ── Floor Lifecycle ──

func _on_enemy_died(_enemy: Node3D) -> void:
	record_kill()

func _on_all_cleared() -> void:
	if _floor_kills >= 10:
		_add_score("combat", 30)

func _on_floor_changed(floor_num: int) -> void:
	if floor_num > 1:
		_finalize_floor_path(floor_num - 1)
	_reset_floor()
	_floor_start_time = Time.get_ticks_msec() / 1000.0

func _finalize_floor_path(floor_num: int) -> void:
	# Speed bonus based on clear time
	var elapsed := Time.get_ticks_msec() / 1000.0 - _floor_start_time
	if elapsed > 0 and elapsed < 60.0:
		_add_score("speed", 50)
	elif elapsed > 0 and elapsed < 120.0:
		_add_score("speed", 25)
	elif elapsed > 0 and elapsed < 180.0:
		_add_score("speed", 10)

	# Low-kill bonus for speed
	if _floor_kills <= 3:
		_add_score("speed", 30)

	# Recalculate one last time
	_recalculate_dominant_path()

	# Build history entry
	var archetype_name := ""
	if FloorManager.current_archetype:
		archetype_name = FloorManager.current_archetype.archetype_name
	var entry := {
		"floor_num": floor_num,
		"archetype": archetype_name,
		"path": current_path,
		"scores": scores.duplicate(),
	}
	floor_history.append(entry)

	# Rolling window
	last_three_paths.append(current_path)
	if last_three_paths.size() > 3:
		last_three_paths.pop_front()

	# VP bonus for using the audience's favorite path
	if current_path == archetype_preferred_path:
		AudienceManager.grant_vp(40, "Audience Favorite Path!")

	floor_path_finalized.emit(floor_num, current_path, archetype_name)

func _reset_floor() -> void:
	scores = {"combat": 0, "speed": 0, "social": 0, "clever": 0}
	current_path = "combat"
	_floor_kills = 0
	_floor_paths.clear()
	archetype_preferred_path = "combat"

# ── Queries ──

func get_dominant_path() -> String:
	return current_path

func get_path_label() -> String:
	return PATH_LABELS.get(current_path, "Unknown")

func get_path_color() -> Color:
	return PATH_COLORS.get(current_path, Color.WHITE)

func get_scores() -> Dictionary:
	return scores.duplicate()

func is_audience_favorite_path() -> bool:
	return current_path == archetype_preferred_path

func get_last_n_paths(n: int) -> Array[String]:
	var result: Array[String] = []
	var start := maxi(0, floor_history.size() - n)
	for i in range(start, floor_history.size()):
		result.append(floor_history[i].path)
	return result

func was_same_path_streak(n: int) -> bool:
	## Returns true if the last N floors used the same solution path.
	if last_three_paths.size() < n:
		return false
	var check_path: String = last_three_paths[last_three_paths.size() - 1]
	for i in range(last_three_paths.size() - n, last_three_paths.size()):
		if last_three_paths[i] != check_path:
			return false
	return true

func get_most_used_path() -> String:
	var counts: Dictionary = {}
	for entry in floor_history:
		var p: String = entry.path
		counts[p] = counts.get(p, 0) + 1
	var best := "combat"
	var best_count := 0
	for p in counts:
		if counts[p] > best_count:
			best_count = counts[p]
			best = p
	return best

func get_run_path_summary() -> String:
	if floor_history.is_empty():
		return "No floors completed"
	var lines: Array[String] = []
	for entry in floor_history:
		var label := PATH_LABELS.get(entry.path, "Unknown")
		lines.append("Floor %d (%s): %s" % [entry.floor_num, entry.archetype, label])
	return "\n".join(lines)

# ── Reset ──

func reset() -> void:
	_reset_floor()
	floor_history.clear()
	last_three_paths.clear()
	_floor_start_time = 0.0
