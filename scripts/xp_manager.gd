extends Node

## XP and leveling autoload singleton.
## Tracks experience, level, and stat bonuses. Grants XP on enemy kills.

signal xp_gained(amount: int, total: int, needed: int)
signal level_up(new_level: int)

var current_xp: int = 0
var current_level: int = 1
var max_level: int = 20

# XP required for each level (index 0 = level 1→2, etc.)
# Formula: level * 100 + (level - 1)^2 * 20
var xp_table: Array[int] = []

# XP rewards by enemy type
var xp_rewards: Dictionary = {
	"rat": 15,
	"slime": 20,
	"spider": 25,
	"wolf": 30,
	"goblin": 25,
	"goblin_warrior": 35,
	"goblin_archer": 30,
	"goblin_shaman": 40,
	"skeleton": 30,
	"animated_armor": 45,
	"mimic": 50,
	"orc": 35,
	# Bosses
	"boss_goblin_king": 200,
	"boss_spider_queen": 250,
	"boss_slime_lord": 300,
	"boss_forest_guardian": 250,
	"boss_crab_king": 350,
	"boss_kraken_spawn": 400,
}

# Stat bonuses per level (cumulative)
# Each level grants: +15 HP, +10 Mana, +1 to two random stats
var bonus_hp: int = 0
var bonus_mana: int = 0
var bonus_str: int = 0
var bonus_dex: int = 0
var bonus_con: int = 0
var bonus_int: int = 0

func _ready() -> void:
	# Build XP table
	for i in range(max_level):
		var lvl = i + 1
		var needed = lvl * 100 + int(pow(lvl - 1, 2)) * 20
		xp_table.append(needed)

	# Listen for enemy deaths
	GameManager.enemy_died.connect(_on_enemy_died)

func get_xp_for_next_level() -> int:
	if current_level >= max_level:
		return 0
	return xp_table[current_level - 1]

func get_xp_progress() -> float:
	var needed = get_xp_for_next_level()
	if needed <= 0:
		return 1.0
	return float(current_xp) / float(needed)

func grant_xp(amount: int) -> void:
	if current_level >= max_level:
		return

	# Floor bonus: +25% per floor beyond 1
	var floor_bonus = 1.0 + (FloorManager.current_floor - 1) * 0.25
	amount = int(amount * floor_bonus)

	current_xp += amount
	xp_gained.emit(amount, current_xp, get_xp_for_next_level())

	# Check for level up (can multi-level from big XP grants)
	while current_xp >= get_xp_for_next_level() and current_level < max_level:
		current_xp -= get_xp_for_next_level()
		current_level += 1
		_apply_level_up()
		level_up.emit(current_level)

func _on_enemy_died(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	var etype: String = ""
	# Boss enemies have a boss_type property
	if enemy.has_method("get") and enemy.get("boss_type") != null:
		etype = "boss_" + enemy.boss_type
	elif enemy.get("enemy_type") != null:
		etype = enemy.enemy_type

	var reward = xp_rewards.get(etype, 20)  # Default 20 XP for unknown types

	# Elite enemies give 2.5x XP
	if EliteModifier.is_elite(enemy):
		reward = int(reward * 2.5)

	grant_xp(reward)

func _apply_level_up() -> void:
	# Grant stat bonuses
	bonus_hp += 15
	bonus_mana += 10

	# +1 to two stats based on character's highest stats (weighted)
	var char_data = CharacterData.get_selected()
	var stats = char_data.get("stats", {})

	# Weight toward the character's best stats
	var stat_weights := {
		"STR": stats.get("STR", 5),
		"DEX": stats.get("DEX", 5),
		"CON": stats.get("CON", 5),
		"INT": stats.get("INT", 5),
	}

	var picked := _weighted_pick_two(stat_weights)
	for stat_name in picked:
		match stat_name:
			"STR": bonus_str += 1
			"DEX": bonus_dex += 1
			"CON": bonus_con += 1
			"INT": bonus_int += 1

	# Apply to hero
	_apply_to_hero()

	# Play level-up sound
	AudioManager.play_sfx("level_up")

func _apply_to_hero() -> void:
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		return

	var char_data = CharacterData.get_selected()
	var base_stats = char_data.get("stats", {})

	# Update max HP/Mana with bonuses
	hero.max_health = base_stats.get("HP", 500) + bonus_hp
	hero.max_mana = base_stats.get("Mana", 200) + bonus_mana

	# Full heal on level up
	hero.current_health = hero.max_health
	hero.current_mana = hero.max_mana
	hero.health_changed.emit(hero.current_health, hero.max_health)
	hero.mana_changed.emit(hero.current_mana, hero.max_mana)

func _weighted_pick_two(weights: Dictionary) -> Array[String]:
	var total_weight: float = 0.0
	for w in weights.values():
		total_weight += w

	var result: Array[String] = []
	var remaining = weights.duplicate()

	for _i in range(2):
		var roll = randf() * total_weight
		var cumulative: float = 0.0
		for stat_name in remaining:
			cumulative += remaining[stat_name]
			if roll <= cumulative:
				result.append(stat_name)
				total_weight -= remaining[stat_name]
				remaining.erase(stat_name)
				break

	# Fallback if selection failed
	while result.size() < 2:
		result.append("STR")

	return result

func get_stat_total(stat_name: String) -> int:
	var char_data = CharacterData.get_selected()
	var base = char_data.get("stats", {}).get(stat_name, 0)
	match stat_name:
		"HP": return base + bonus_hp
		"Mana": return base + bonus_mana
		"STR": return base + bonus_str
		"DEX": return base + bonus_dex
		"CON": return base + bonus_con
		"INT": return base + bonus_int
	return base

func reset() -> void:
	current_xp = 0
	current_level = 1
	bonus_hp = 0
	bonus_mana = 0
	bonus_str = 0
	bonus_dex = 0
	bonus_con = 0
	bonus_int = 0
