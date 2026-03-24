extends Node

## RunModifiers — before each run, offer random mutators that alter gameplay.
## Player picks 0-2 from a selection of 3-4 offered. Adds variety per run.
## Active modifiers persist for the entire run and are checked by game systems.

signal modifiers_selected(active: Array[Dictionary])

const MAX_ACTIVE := 2
const OFFER_COUNT := 4  # How many modifiers to offer per run

var active_modifiers: Array[Dictionary] = []

# Master modifier pool — each entry:
#   id: unique string
#   name: display name
#   description: what it does
#   color: accent color for UI
#   effect: callable or string key checked by game systems
var _modifier_pool: Array[Dictionary] = [
	{
		"id": "explode_on_death",
		"name": "Volatile Enemies",
		"description": "All enemies explode on death, dealing 30 AoE damage.",
		"color": Color(1.0, 0.4, 0.1),
	},
	{
		"id": "no_healing",
		"name": "No Mercy",
		"description": "Healing items and spells are disabled.",
		"color": Color(0.8, 0.2, 0.2),
	},
	{
		"id": "double_gold_half_hp",
		"name": "Glass Collector",
		"description": "Double gold drops, but hero has 50% max HP.",
		"color": Color(1.0, 0.85, 0.0),
	},
	{
		"id": "permanent_fog",
		"name": "Deep Fog",
		"description": "Fog of war never lifts. Navigate by memory.",
		"color": Color(0.4, 0.4, 0.5),
	},
	{
		"id": "speed_demon",
		"name": "Speed Demon",
		"description": "Hero moves 40% faster, but Smusher is 25% faster too.",
		"color": Color(0.3, 0.9, 0.6),
	},
	{
		"id": "big_enemies",
		"name": "Giant Foes",
		"description": "All enemies have 2x HP but give 3x XP.",
		"color": Color(0.6, 0.3, 0.8),
	},
	{
		"id": "friendly_fire",
		"name": "Chaos Mode",
		"description": "Enemies can damage each other. So can traps.",
		"color": Color(1.0, 0.6, 0.2),
	},
	{
		"id": "loot_magnet",
		"name": "Loot Magnet",
		"description": "Double loot drops, but all enemies are Elite.",
		"color": Color(0.2, 0.8, 1.0),
	},
	{
		"id": "one_hit_wonder",
		"name": "One-Hit Wonder",
		"description": "Hero deals 5x damage but dies in one hit.",
		"color": Color(1.0, 0.1, 0.5),
	},
	{
		"id": "pacifist_gold",
		"name": "Pacifist's Purse",
		"description": "+100 starting gold, but -25% damage dealt.",
		"color": Color(0.5, 0.8, 0.3),
	},
	{
		"id": "audience_frenzy",
		"name": "Audience Frenzy",
		"description": "VP gains are doubled, but audience gifts can be cruel.",
		"color": Color(0.9, 0.3, 0.7),
	},
	{
		"id": "timer_pressure",
		"name": "Rush Hour",
		"description": "Smusher timer runs 40% faster. No time to breathe.",
		"color": Color(0.9, 0.2, 0.2),
	},
]

# ── API ──

func has_modifier(modifier_id: String) -> bool:
	for m in active_modifiers:
		if m.get("id", "") == modifier_id:
			return true
	return false

func get_offered_modifiers() -> Array[Dictionary]:
	## Returns a random selection of modifiers for the player to choose from.
	var pool := _modifier_pool.duplicate()
	pool.shuffle()
	var offered: Array[Dictionary] = []
	for i in range(mini(OFFER_COUNT, pool.size())):
		offered.append(pool[i])
	return offered

func set_active_modifiers(selected: Array[Dictionary]) -> void:
	active_modifiers.clear()
	for i in range(mini(selected.size(), MAX_ACTIVE)):
		active_modifiers.append(selected[i])
	modifiers_selected.emit(active_modifiers)

func apply_modifiers() -> void:
	## Apply modifier effects that need to be set at run start.
	for m in active_modifiers:
		match m.get("id", ""):
			"double_gold_half_hp":
				# Half HP applied when hero spawns
				pass  # Checked in hero.gd
			"speed_demon":
				# Speed boost applied in hero movement
				pass  # Checked in hero.gd
			"pacifist_gold":
				LootManager.gold += 100
				LootManager.gold_changed.emit(LootManager.gold)

func reset() -> void:
	active_modifiers.clear()

func get_modifier_summary() -> String:
	if active_modifiers.is_empty():
		return "No modifiers"
	var names: Array[String] = []
	for m in active_modifiers:
		names.append(m.get("name", "?"))
	return ", ".join(names)
