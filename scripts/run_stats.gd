extends Node

## Run Statistics Tracker — centralized per-run stat recording.
## Tracks kills, damage, spells, gold, items, floors, and more.
## Feeds the game-over stats screen with rich data.

signal stat_updated(stat_name: String, value: int)

# Kill tracking
var total_kills: int = 0
var kills_by_type: Dictionary = {}  # enemy_type -> count
var boss_kills: int = 0
var elite_kills: int = 0

# Damage tracking
var damage_dealt: int = 0
var damage_taken: int = 0
var largest_hit: int = 0  # Single biggest hit dealt

# Spell tracking
var spells_cast: Array[int] = [0, 0, 0, 0]  # Q, W, E, R
var total_spells: int = 0

# Economy tracking
var gold_earned: int = 0
var gold_spent: int = 0
var items_collected: int = 0
var potions_used: int = 0

# Progression
var floors_cleared: int = 0
var highest_floor: int = 1

# Timing
var run_start_time: float = 0.0
var floor_start_times: Dictionary = {}  # floor_num -> start_time
var floor_clear_times: Dictionary = {}  # floor_num -> seconds_to_clear

func _ready() -> void:
	# Listen to existing signals
	GameManager.enemy_died.connect(_on_enemy_died)
	GameManager.game_over.connect(_on_game_over)
	FloorManager.floor_changed.connect(_on_floor_changed)
	LootManager.item_picked_up.connect(_on_item_picked_up)
	LootManager.gold_changed.connect(_on_gold_changed)

func start_run() -> void:
	run_start_time = Time.get_ticks_msec() / 1000.0
	floor_start_times[1] = run_start_time

func get_run_elapsed() -> float:
	return Time.get_ticks_msec() / 1000.0 - run_start_time

func get_run_time_string() -> String:
	var elapsed = get_run_elapsed()
	var minutes = int(elapsed) / 60
	var seconds = int(elapsed) % 60
	return "%d:%02d" % [minutes, seconds]

# ----- Recording Methods -----

func record_damage_dealt(amount: int) -> void:
	damage_dealt += amount
	if amount > largest_hit:
		largest_hit = amount
	stat_updated.emit("damage_dealt", damage_dealt)

func record_damage_taken(amount: int) -> void:
	damage_taken += amount
	stat_updated.emit("damage_taken", damage_taken)

func record_spell_cast(spell_index: int) -> void:
	if spell_index >= 0 and spell_index < 4:
		spells_cast[spell_index] += 1
		total_spells += 1
		stat_updated.emit("spells_cast", total_spells)

func record_potion_used() -> void:
	potions_used += 1
	stat_updated.emit("potions_used", potions_used)

func record_gold_spent(amount: int) -> void:
	gold_spent += amount
	stat_updated.emit("gold_spent", gold_spent)

# ----- Signal Handlers -----

func _on_enemy_died(enemy: Node3D) -> void:
	total_kills += 1

	var etype: String = "unknown"
	if enemy.get("boss_type") != null and enemy.boss_type != "":
		etype = "boss_" + enemy.boss_type
		boss_kills += 1
	elif enemy.get("enemy_type") != null:
		etype = enemy.enemy_type

	kills_by_type[etype] = kills_by_type.get(etype, 0) + 1

	# Track elite kills
	if EliteModifier.is_elite(enemy):
		elite_kills += 1

	stat_updated.emit("kills", total_kills)

func _on_game_over(_won: bool) -> void:
	# Record final floor clear time if applicable
	var current = FloorManager.current_floor
	if not floor_clear_times.has(current) and floor_start_times.has(current):
		floor_clear_times[current] = Time.get_ticks_msec() / 1000.0 - floor_start_times[current]

var _last_gold: int = 0

func _on_gold_changed(amount: int) -> void:
	var gained = amount - _last_gold
	if gained > 0:
		gold_earned += gained
	_last_gold = amount

func _on_item_picked_up(_item: Dictionary) -> void:
	items_collected += 1
	stat_updated.emit("items_collected", items_collected)

func _on_floor_changed(floor_num: int) -> void:
	# Record clear time for previous floor
	var prev_floor = floor_num - 1
	if prev_floor >= 1 and floor_start_times.has(prev_floor):
		floor_clear_times[prev_floor] = Time.get_ticks_msec() / 1000.0 - floor_start_times[prev_floor]
		floors_cleared = prev_floor

	# Start timing new floor
	floor_start_times[floor_num] = Time.get_ticks_msec() / 1000.0
	if floor_num > highest_floor:
		highest_floor = floor_num

# ----- Stats Summary for Game Over -----

func get_summary() -> Dictionary:
	return {
		"total_kills": total_kills,
		"boss_kills": boss_kills,
		"kills_by_type": kills_by_type,
		"damage_dealt": damage_dealt,
		"damage_taken": damage_taken,
		"largest_hit": largest_hit,
		"total_spells": total_spells,
		"spells_cast": spells_cast.duplicate(),
		"gold_earned": gold_earned,
		"gold_spent": gold_spent,
		"items_collected": items_collected,
		"potions_used": potions_used,
		"floors_cleared": floors_cleared,
		"highest_floor": highest_floor,
		"run_time": get_run_time_string(),
		"floor_times": floor_clear_times.duplicate(),
	}

func get_most_killed_enemy() -> String:
	var best_type := ""
	var best_count := 0
	for etype in kills_by_type:
		if kills_by_type[etype] > best_count:
			best_count = kills_by_type[etype]
			best_type = etype
	return best_type

# ----- Reset -----

func reset() -> void:
	total_kills = 0
	kills_by_type.clear()
	boss_kills = 0
	damage_dealt = 0
	damage_taken = 0
	largest_hit = 0
	spells_cast = [0, 0, 0, 0]
	total_spells = 0
	gold_earned = 0
	gold_spent = 0
	_last_gold = 0
	items_collected = 0
	potions_used = 0
	floors_cleared = 0
	highest_floor = 1
	run_start_time = 0.0
	floor_start_times.clear()
	floor_clear_times.clear()
