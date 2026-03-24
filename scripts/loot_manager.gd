extends Node

## Loot Manager — singleton that defines items, loot tables, hero inventory,
## and spawns world drops when enemies die.

signal item_picked_up(item: Dictionary)
signal gold_changed(amount: int)
signal inventory_changed()

# Item rarity tiers (from game bible)
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_COLORS := {
	Rarity.COMMON: Color(0.8, 0.8, 0.8),
	Rarity.UNCOMMON: Color(0.2, 0.9, 0.2),
	Rarity.RARE: Color(0.2, 0.4, 1.0),
	Rarity.EPIC: Color(0.7, 0.2, 0.9),
	Rarity.LEGENDARY: Color(1.0, 0.65, 0.0),
}

const RARITY_NAMES := {
	Rarity.COMMON: "Common",
	Rarity.UNCOMMON: "Uncommon",
	Rarity.RARE: "Rare",
	Rarity.EPIC: "Epic",
	Rarity.LEGENDARY: "Legendary",
}

# Item database — id → definition
var ITEMS := {
	"health_potion": {
		"id": "health_potion",
		"name": "Health Potion",
		"type": "consumable",
		"rarity": Rarity.COMMON,
		"heal_amount": 100,
		"model": "",  # Uses generated mesh
		"mesh_color": Color(0.9, 0.15, 0.15),
		"description": "Restores 100 health.",
	},
	"mana_potion": {
		"id": "mana_potion",
		"name": "Mana Potion",
		"type": "consumable",
		"rarity": Rarity.COMMON,
		"mana_amount": 60,
		"model": "",
		"mesh_color": Color(0.15, 0.3, 0.9),
		"description": "Restores 60 mana.",
	},
	"gold_pile": {
		"id": "gold_pile",
		"name": "Gold",
		"type": "currency",
		"rarity": Rarity.COMMON,
		"gold_min": 5,
		"gold_max": 25,
		"model": "",
		"mesh_color": Color(1.0, 0.85, 0.1),
		"description": "Shiny coins.",
	},
	"iron_sword": {
		"id": "iron_sword",
		"name": "Iron Sword",
		"type": "weapon",
		"rarity": Rarity.COMMON,
		"damage_bonus": 5,
		"model": "res://assets/models/weapons/iron_sword.glb",
		"mesh_color": Color(0.6, 0.6, 0.65),
		"description": "A sturdy iron blade. +5 damage.",
	},
	"rusty_dagger": {
		"id": "rusty_dagger",
		"name": "Rusty Dagger",
		"type": "weapon",
		"rarity": Rarity.COMMON,
		"damage_bonus": 3,
		"model": "res://assets/models/weapons/rusty_dagger.glb",
		"mesh_color": Color(0.5, 0.4, 0.3),
		"description": "A worn dagger. +3 damage.",
	},
	"steel_sword": {
		"id": "steel_sword",
		"name": "Steel Sword",
		"type": "weapon",
		"rarity": Rarity.UNCOMMON,
		"damage_bonus": 10,
		"model": "res://assets/models/weapons/steel_sword.glb",
		"mesh_color": Color(0.75, 0.78, 0.82),
		"description": "Finely forged steel. +10 damage.",
	},
	"iron_axe": {
		"id": "iron_axe",
		"name": "Iron Axe",
		"type": "weapon",
		"rarity": Rarity.UNCOMMON,
		"damage_bonus": 8,
		"model": "res://assets/models/weapons/iron_axe.glb",
		"mesh_color": Color(0.6, 0.55, 0.5),
		"description": "Heavy iron axe. +8 damage.",
	},
	"longbow": {
		"id": "longbow",
		"name": "Longbow",
		"type": "weapon",
		"rarity": Rarity.RARE,
		"damage_bonus": 12,
		"model": "res://assets/models/weapons/longbow.glb",
		"mesh_color": Color(0.55, 0.35, 0.15),
		"description": "Elven-crafted longbow. +12 damage.",
	},
}

# Loot tables — enemy_type → weighted drop list
# Each entry: {item_id, weight, min_count, max_count}
var LOOT_TABLES := {
	"default": [
		{"item_id": "gold_pile", "weight": 50, "min": 1, "max": 1},
		{"item_id": "health_potion", "weight": 25, "min": 1, "max": 1},
		{"item_id": "mana_potion", "weight": 15, "min": 1, "max": 1},
		{"item_id": "rusty_dagger", "weight": 5, "min": 1, "max": 1},
		{"item_id": "iron_sword", "weight": 4, "min": 1, "max": 1},
		{"item_id": "iron_axe", "weight": 1, "min": 1, "max": 1},
	],
	"goblin": [
		{"item_id": "gold_pile", "weight": 40, "min": 1, "max": 2},
		{"item_id": "health_potion", "weight": 20, "min": 1, "max": 1},
		{"item_id": "rusty_dagger", "weight": 15, "min": 1, "max": 1},
		{"item_id": "mana_potion", "weight": 10, "min": 1, "max": 1},
		{"item_id": "iron_sword", "weight": 10, "min": 1, "max": 1},
		{"item_id": "steel_sword", "weight": 5, "min": 1, "max": 1},
	],
	"skeleton": [
		{"item_id": "gold_pile", "weight": 35, "min": 1, "max": 1},
		{"item_id": "health_potion", "weight": 20, "min": 1, "max": 1},
		{"item_id": "iron_sword", "weight": 15, "min": 1, "max": 1},
		{"item_id": "mana_potion", "weight": 10, "min": 1, "max": 1},
		{"item_id": "iron_axe", "weight": 10, "min": 1, "max": 1},
		{"item_id": "steel_sword", "weight": 7, "min": 1, "max": 1},
		{"item_id": "longbow", "weight": 3, "min": 1, "max": 1},
	],
	"boss": [
		{"item_id": "gold_pile", "weight": 20, "min": 3, "max": 5},
		{"item_id": "health_potion", "weight": 15, "min": 2, "max": 3},
		{"item_id": "mana_potion", "weight": 10, "min": 1, "max": 2},
		{"item_id": "steel_sword", "weight": 20, "min": 1, "max": 1},
		{"item_id": "iron_axe", "weight": 15, "min": 1, "max": 1},
		{"item_id": "longbow", "weight": 20, "min": 1, "max": 1},
	],
}

# Hero inventory + gold
var gold: int = 0
var inventory: Array[Dictionary] = []  # Array of item dicts
var max_inventory_size: int = 20

# Loot drop scene (built programmatically)
var _loot_drop_script: GDScript

func _ready() -> void:
	_loot_drop_script = load("res://scripts/loot_drop.gd")
	GameManager.enemy_died.connect(_on_enemy_died)

func _on_enemy_died(enemy: Node3D) -> void:
	# Check if this is a boss (has boss_type property)
	var is_boss := "boss_type" in enemy
	var enemy_type := "default"

	if is_boss:
		# Bosses always drop loot — 3 guaranteed rolls on boss table
		var table: Array = LOOT_TABLES.get("boss", LOOT_TABLES["default"])
		for _roll in range(3):
			var rolled_item := _roll_weighted(table)
			if rolled_item.is_empty():
				continue
			var item_def: Dictionary = ITEMS.get(rolled_item["item_id"], {})
			if item_def.is_empty():
				continue
			var count := randi_range(rolled_item.get("min", 1), rolled_item.get("max", 1))
			for _i in range(count):
				_spawn_drop(enemy.global_position, item_def)
		return

	if "enemy_type" in enemy:
		enemy_type = enemy.enemy_type
	# Map enemy types to loot tables
	var table_key := "default"
	if enemy_type.begins_with("goblin"):
		table_key = "goblin"
	elif enemy_type in ["skeleton", "orc"]:
		table_key = "skeleton"

	# Roll drops (60% chance to drop something)
	if randf() > 0.6:
		return

	var table: Array = LOOT_TABLES.get(table_key, LOOT_TABLES["default"])
	var rolled_item := _roll_weighted(table)
	if rolled_item.is_empty():
		return

	var item_def: Dictionary = ITEMS.get(rolled_item["item_id"], {})
	if item_def.is_empty():
		return

	var count := randi_range(rolled_item.get("min", 1), rolled_item.get("max", 1))
	for _i in range(count):
		_spawn_drop(enemy.global_position, item_def)

func _roll_weighted(table: Array) -> Dictionary:
	var total_weight := 0
	for entry in table:
		total_weight += entry["weight"]
	var roll := randi() % total_weight
	var cumulative := 0
	for entry in table:
		cumulative += entry["weight"]
		if roll < cumulative:
			return entry
	return table[-1]

func _spawn_drop(world_pos: Vector3, item_def: Dictionary) -> void:
	var drop := Area3D.new()
	drop.set_script(_loot_drop_script)
	drop.set_meta("item_data", item_def)

	# Scatter slightly from death position
	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	drop.position = world_pos + offset + Vector3.UP * 0.5

	# Add to scene tree
	var tree := get_tree()
	if tree and tree.root:
		tree.root.add_child(drop)

func pickup_item(item_def: Dictionary) -> void:
	if item_def["type"] == "currency":
		var amount := randi_range(item_def.get("gold_min", 5), item_def.get("gold_max", 25))
		gold += amount
		gold_changed.emit(gold)
		item_picked_up.emit({"name": "%d Gold" % amount, "rarity": item_def["rarity"], "type": "currency"})
	elif item_def["type"] == "consumable":
		_apply_consumable(item_def)
		item_picked_up.emit(item_def)
	elif item_def["type"] == "weapon":
		if inventory.size() < max_inventory_size:
			inventory.append(item_def.duplicate())
			inventory_changed.emit()
			item_picked_up.emit(item_def)

func _apply_consumable(item_def: Dictionary) -> void:
	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		return
	if item_def["id"] == "health_potion":
		var heal := item_def.get("heal_amount", 100)
		hero.current_health = mini(hero.current_health + heal, hero.max_health)
		hero.health_changed.emit(hero.current_health, hero.max_health)
		GameManager.request_damage_number(hero.global_position + Vector3.UP * 2.5, heal, false)
	elif item_def["id"] == "mana_potion":
		var mana := item_def.get("mana_amount", 60)
		hero.current_mana = mini(hero.current_mana + mana, hero.max_mana)
		hero.mana_changed.emit(hero.current_mana, hero.max_mana)
