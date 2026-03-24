extends Node

## Loot Manager — singleton that defines items, loot tables, hero inventory,
## and spawns world drops when enemies die.
## Expanded: weapon types (sword/axe/staff/bow) with stat affixes,
## armor (helm/chestplate/boots), rarity-scaled stat rolls.

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

# Rarity stat multipliers — higher rarity = bigger stat rolls
const RARITY_MULT := {
	Rarity.COMMON: 1.0,
	Rarity.UNCOMMON: 1.5,
	Rarity.RARE: 2.2,
	Rarity.EPIC: 3.0,
	Rarity.LEGENDARY: 4.5,
}

# Item templates — id → base definition (stats get rolled at drop time)
var ITEMS := {
	# ----- Consumables -----
	"health_potion": {
		"id": "health_potion",
		"name": "Health Potion",
		"type": "consumable",
		"rarity": Rarity.COMMON,
		"heal_amount": 100,
		"model": "",
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

	# ----- Swords (+STR, +damage) -----
	"rusty_dagger": {
		"id": "rusty_dagger", "name": "Rusty Dagger", "type": "weapon",
		"subtype": "sword", "equip_slot": "weapon", "rarity": Rarity.COMMON,
		"base_damage": 3, "base_str": 1,
		"model": "res://assets/models/weapons/rusty_dagger.glb",
		"mesh_color": Color(0.5, 0.4, 0.3),
		"description": "A worn dagger.",
	},
	"iron_sword": {
		"id": "iron_sword", "name": "Iron Sword", "type": "weapon",
		"subtype": "sword", "equip_slot": "weapon", "rarity": Rarity.COMMON,
		"base_damage": 5, "base_str": 1,
		"model": "res://assets/models/weapons/iron_sword.glb",
		"mesh_color": Color(0.6, 0.6, 0.65),
		"description": "A sturdy iron blade.",
	},
	"steel_sword": {
		"id": "steel_sword", "name": "Steel Sword", "type": "weapon",
		"subtype": "sword", "equip_slot": "weapon", "rarity": Rarity.UNCOMMON,
		"base_damage": 8, "base_str": 2,
		"model": "res://assets/models/weapons/steel_sword.glb",
		"mesh_color": Color(0.75, 0.78, 0.82),
		"description": "Finely forged steel.",
	},
	"paladin_blade": {
		"id": "paladin_blade", "name": "Paladin Blade", "type": "weapon",
		"subtype": "sword", "equip_slot": "weapon", "rarity": Rarity.RARE,
		"base_damage": 12, "base_str": 3,
		"model": "res://assets/models/weapons/steel_sword.glb",
		"mesh_color": Color(0.95, 0.9, 0.6),
		"description": "Holy-forged blade of the order.",
	},
	"doom_edge": {
		"id": "doom_edge", "name": "Doom Edge", "type": "weapon",
		"subtype": "sword", "equip_slot": "weapon", "rarity": Rarity.EPIC,
		"base_damage": 18, "base_str": 5,
		"model": "res://assets/models/weapons/steel_sword.glb",
		"mesh_color": Color(0.6, 0.1, 0.5),
		"description": "Radiates dread. Enemies flinch.",
	},

	# ----- Axes (+crit chance) -----
	"iron_axe": {
		"id": "iron_axe", "name": "Iron Axe", "type": "weapon",
		"subtype": "axe", "equip_slot": "weapon", "rarity": Rarity.UNCOMMON,
		"base_damage": 7, "base_crit": 5,
		"model": "res://assets/models/weapons/iron_axe.glb",
		"mesh_color": Color(0.6, 0.55, 0.5),
		"description": "Heavy iron axe. Cleaves deep.",
	},
	"battle_axe": {
		"id": "battle_axe", "name": "Battle Axe", "type": "weapon",
		"subtype": "axe", "equip_slot": "weapon", "rarity": Rarity.RARE,
		"base_damage": 11, "base_crit": 8,
		"model": "res://assets/models/weapons/iron_axe.glb",
		"mesh_color": Color(0.4, 0.4, 0.5),
		"description": "Double-headed war axe.",
	},
	"berserker_cleaver": {
		"id": "berserker_cleaver", "name": "Berserker Cleaver", "type": "weapon",
		"subtype": "axe", "equip_slot": "weapon", "rarity": Rarity.EPIC,
		"base_damage": 16, "base_crit": 12,
		"model": "res://assets/models/weapons/iron_axe.glb",
		"mesh_color": Color(0.8, 0.15, 0.1),
		"description": "Feeds on rage. Devastating crits.",
	},

	# ----- Staves (+INT, +spell power) -----
	"apprentice_staff": {
		"id": "apprentice_staff", "name": "Apprentice Staff", "type": "weapon",
		"subtype": "staff", "equip_slot": "weapon", "rarity": Rarity.COMMON,
		"base_damage": 2, "base_int": 2, "base_spell_power": 5,
		"model": "res://assets/models/weapons/iron_sword.glb",
		"mesh_color": Color(0.35, 0.25, 0.6),
		"description": "A novice's focus.",
	},
	"arcane_staff": {
		"id": "arcane_staff", "name": "Arcane Staff", "type": "weapon",
		"subtype": "staff", "equip_slot": "weapon", "rarity": Rarity.UNCOMMON,
		"base_damage": 4, "base_int": 3, "base_spell_power": 10,
		"model": "res://assets/models/weapons/iron_sword.glb",
		"mesh_color": Color(0.3, 0.4, 0.9),
		"description": "Hums with arcane energy.",
	},
	"elder_staff": {
		"id": "elder_staff", "name": "Elder Staff", "type": "weapon",
		"subtype": "staff", "equip_slot": "weapon", "rarity": Rarity.RARE,
		"base_damage": 6, "base_int": 5, "base_spell_power": 18,
		"model": "res://assets/models/weapons/iron_sword.glb",
		"mesh_color": Color(0.2, 0.7, 0.9),
		"description": "Ancient wisdom crystallized.",
	},
	"void_scepter": {
		"id": "void_scepter", "name": "Void Scepter", "type": "weapon",
		"subtype": "staff", "equip_slot": "weapon", "rarity": Rarity.LEGENDARY,
		"base_damage": 10, "base_int": 8, "base_spell_power": 30,
		"model": "res://assets/models/weapons/iron_sword.glb",
		"mesh_color": Color(0.15, 0.0, 0.3),
		"description": "Channels the void itself.",
	},

	# ----- Bows (+DEX) -----
	"shortbow": {
		"id": "shortbow", "name": "Shortbow", "type": "weapon",
		"subtype": "bow", "equip_slot": "weapon", "rarity": Rarity.COMMON,
		"base_damage": 4, "base_dex": 2,
		"model": "res://assets/models/weapons/longbow.glb",
		"mesh_color": Color(0.5, 0.4, 0.2),
		"description": "Simple but reliable.",
	},
	"longbow": {
		"id": "longbow", "name": "Longbow", "type": "weapon",
		"subtype": "bow", "equip_slot": "weapon", "rarity": Rarity.RARE,
		"base_damage": 10, "base_dex": 4,
		"model": "res://assets/models/weapons/longbow.glb",
		"mesh_color": Color(0.55, 0.35, 0.15),
		"description": "Elven-crafted longbow.",
	},
	"eagle_bow": {
		"id": "eagle_bow", "name": "Eagle Bow", "type": "weapon",
		"subtype": "bow", "equip_slot": "weapon", "rarity": Rarity.EPIC,
		"base_damage": 14, "base_dex": 6,
		"model": "res://assets/models/weapons/longbow.glb",
		"mesh_color": Color(0.9, 0.85, 0.5),
		"description": "Strikes with piercing precision.",
	},

	# ----- Helms (armor, +CON) -----
	"leather_cap": {
		"id": "leather_cap", "name": "Leather Cap", "type": "armor",
		"equip_slot": "head", "rarity": Rarity.COMMON,
		"base_armor": 3, "base_con": 1, "base_hp": 15,
		"model": "", "mesh_color": Color(0.5, 0.35, 0.2),
		"description": "Basic head protection.",
	},
	"iron_helm": {
		"id": "iron_helm", "name": "Iron Helm", "type": "armor",
		"equip_slot": "head", "rarity": Rarity.UNCOMMON,
		"base_armor": 6, "base_con": 2, "base_hp": 30,
		"model": "", "mesh_color": Color(0.55, 0.55, 0.6),
		"description": "Solid iron headgear.",
	},
	"champions_crown": {
		"id": "champions_crown", "name": "Champion's Crown", "type": "armor",
		"equip_slot": "head", "rarity": Rarity.RARE,
		"base_armor": 10, "base_con": 3, "base_hp": 50,
		"model": "", "mesh_color": Color(0.85, 0.75, 0.3),
		"description": "Worn by arena victors.",
	},
	"skull_visor": {
		"id": "skull_visor", "name": "Skull Visor", "type": "armor",
		"equip_slot": "head", "rarity": Rarity.EPIC,
		"base_armor": 15, "base_con": 5, "base_hp": 80,
		"model": "", "mesh_color": Color(0.3, 0.3, 0.35),
		"description": "Forged from a giant's skull.",
	},

	# ----- Chestplates (armor, +HP) -----
	"leather_vest": {
		"id": "leather_vest", "name": "Leather Vest", "type": "armor",
		"equip_slot": "chest", "rarity": Rarity.COMMON,
		"base_armor": 5, "base_hp": 25,
		"model": "", "mesh_color": Color(0.45, 0.32, 0.18),
		"description": "Toughened hide.",
	},
	"chainmail": {
		"id": "chainmail", "name": "Chainmail", "type": "armor",
		"equip_slot": "chest", "rarity": Rarity.UNCOMMON,
		"base_armor": 10, "base_hp": 45,
		"model": "", "mesh_color": Color(0.6, 0.6, 0.65),
		"description": "Interlocking iron rings.",
	},
	"plate_armor": {
		"id": "plate_armor", "name": "Plate Armor", "type": "armor",
		"equip_slot": "chest", "rarity": Rarity.RARE,
		"base_armor": 16, "base_hp": 75,
		"model": "", "mesh_color": Color(0.7, 0.72, 0.78),
		"description": "Full steel plate. Heavyweight.",
	},
	"dragonscale_mail": {
		"id": "dragonscale_mail", "name": "Dragonscale Mail", "type": "armor",
		"equip_slot": "chest", "rarity": Rarity.LEGENDARY,
		"base_armor": 25, "base_hp": 120,
		"model": "", "mesh_color": Color(0.15, 0.6, 0.2),
		"description": "Scales of a fallen wyrm.",
	},

	# ----- Boots (armor, +DEX/move speed) -----
	"leather_boots": {
		"id": "leather_boots", "name": "Leather Boots", "type": "armor",
		"equip_slot": "feet", "rarity": Rarity.COMMON,
		"base_armor": 2, "base_dex": 1, "base_speed": 3,
		"model": "", "mesh_color": Color(0.42, 0.3, 0.18),
		"description": "Comfortable and worn.",
	},
	"iron_greaves": {
		"id": "iron_greaves", "name": "Iron Greaves", "type": "armor",
		"equip_slot": "feet", "rarity": Rarity.UNCOMMON,
		"base_armor": 5, "base_dex": 2, "base_speed": 5,
		"model": "", "mesh_color": Color(0.5, 0.5, 0.55),
		"description": "Heavy but protective.",
	},
	"windrunner_boots": {
		"id": "windrunner_boots", "name": "Windrunner Boots", "type": "armor",
		"equip_slot": "feet", "rarity": Rarity.RARE,
		"base_armor": 7, "base_dex": 4, "base_speed": 10,
		"model": "", "mesh_color": Color(0.4, 0.7, 0.9),
		"description": "Fleet as the gale.",
	},
	"boots_of_the_colossus": {
		"id": "boots_of_the_colossus", "name": "Boots of the Colossus", "type": "armor",
		"equip_slot": "feet", "rarity": Rarity.EPIC,
		"base_armor": 12, "base_dex": 3, "base_speed": 8, "base_hp": 40,
		"model": "", "mesh_color": Color(0.6, 0.4, 0.15),
		"description": "Earthquakes follow each step.",
	},

	# ----- Trinkets -----
	"torch": {
		"id": "torch", "name": "Torch", "type": "armor",
		"equip_slot": "offhand", "rarity": Rarity.UNCOMMON,
		"base_damage": 2,
		"model": "", "mesh_color": Color(1.0, 0.7, 0.2),
		"description": "Restores vision on night floors. A comforting flame.",
	},
	"healing_aura_trinket": {
		"id": "healing_aura_trinket", "name": "Healing Aura Trinket", "type": "armor",
		"equip_slot": "trinket", "rarity": Rarity.RARE,
		"base_hp": 20,
		"aura_type": "heal", "aura_radius": 4.0, "aura_value": 5.0,
		"model": "", "mesh_color": Color(0.2, 0.9, 0.3),
		"description": "Radiates a healing aura (5 HP/sec, radius 4). Affects summons too.",
	},
}

# Loot tables — source → weighted drop list
var LOOT_TABLES := {
	"default": [
		{"item_id": "gold_pile", "weight": 45, "min": 1, "max": 1},
		{"item_id": "health_potion", "weight": 20, "min": 1, "max": 1},
		{"item_id": "mana_potion", "weight": 12, "min": 1, "max": 1},
		{"item_id": "rusty_dagger", "weight": 5, "min": 1, "max": 1},
		{"item_id": "iron_sword", "weight": 4, "min": 1, "max": 1},
		{"item_id": "shortbow", "weight": 3, "min": 1, "max": 1},
		{"item_id": "apprentice_staff", "weight": 3, "min": 1, "max": 1},
		{"item_id": "leather_cap", "weight": 3, "min": 1, "max": 1},
		{"item_id": "leather_vest", "weight": 3, "min": 1, "max": 1},
		{"item_id": "leather_boots", "weight": 2, "min": 1, "max": 1},
	],
	"goblin": [
		{"item_id": "gold_pile", "weight": 35, "min": 1, "max": 2},
		{"item_id": "health_potion", "weight": 15, "min": 1, "max": 1},
		{"item_id": "rusty_dagger", "weight": 12, "min": 1, "max": 1},
		{"item_id": "mana_potion", "weight": 8, "min": 1, "max": 1},
		{"item_id": "iron_sword", "weight": 7, "min": 1, "max": 1},
		{"item_id": "iron_axe", "weight": 5, "min": 1, "max": 1},
		{"item_id": "shortbow", "weight": 4, "min": 1, "max": 1},
		{"item_id": "leather_cap", "weight": 4, "min": 1, "max": 1},
		{"item_id": "leather_vest", "weight": 4, "min": 1, "max": 1},
		{"item_id": "leather_boots", "weight": 3, "min": 1, "max": 1},
		{"item_id": "steel_sword", "weight": 3, "min": 1, "max": 1},
	],
	"skeleton": [
		{"item_id": "gold_pile", "weight": 30, "min": 1, "max": 1},
		{"item_id": "health_potion", "weight": 14, "min": 1, "max": 1},
		{"item_id": "iron_sword", "weight": 10, "min": 1, "max": 1},
		{"item_id": "iron_axe", "weight": 8, "min": 1, "max": 1},
		{"item_id": "mana_potion", "weight": 8, "min": 1, "max": 1},
		{"item_id": "steel_sword", "weight": 6, "min": 1, "max": 1},
		{"item_id": "iron_helm", "weight": 5, "min": 1, "max": 1},
		{"item_id": "chainmail", "weight": 5, "min": 1, "max": 1},
		{"item_id": "iron_greaves", "weight": 4, "min": 1, "max": 1},
		{"item_id": "arcane_staff", "weight": 4, "min": 1, "max": 1},
		{"item_id": "longbow", "weight": 3, "min": 1, "max": 1},
		{"item_id": "battle_axe", "weight": 3, "min": 1, "max": 1},
	],
	"boss": [
		{"item_id": "gold_pile", "weight": 15, "min": 3, "max": 5},
		{"item_id": "health_potion", "weight": 10, "min": 2, "max": 3},
		{"item_id": "mana_potion", "weight": 8, "min": 1, "max": 2},
		{"item_id": "paladin_blade", "weight": 8, "min": 1, "max": 1},
		{"item_id": "doom_edge", "weight": 5, "min": 1, "max": 1},
		{"item_id": "berserker_cleaver", "weight": 6, "min": 1, "max": 1},
		{"item_id": "elder_staff", "weight": 6, "min": 1, "max": 1},
		{"item_id": "void_scepter", "weight": 2, "min": 1, "max": 1},
		{"item_id": "eagle_bow", "weight": 5, "min": 1, "max": 1},
		{"item_id": "longbow", "weight": 5, "min": 1, "max": 1},
		{"item_id": "champions_crown", "weight": 6, "min": 1, "max": 1},
		{"item_id": "skull_visor", "weight": 4, "min": 1, "max": 1},
		{"item_id": "plate_armor", "weight": 6, "min": 1, "max": 1},
		{"item_id": "dragonscale_mail", "weight": 2, "min": 1, "max": 1},
		{"item_id": "windrunner_boots", "weight": 5, "min": 1, "max": 1},
		{"item_id": "boots_of_the_colossus", "weight": 4, "min": 1, "max": 1},
		{"item_id": "healing_aura_trinket", "weight": 5, "min": 1, "max": 1},
	],
	"chest": [
		{"item_id": "gold_pile", "weight": 25, "min": 2, "max": 4},
		{"item_id": "health_potion", "weight": 15, "min": 1, "max": 2},
		{"item_id": "mana_potion", "weight": 10, "min": 1, "max": 1},
		{"item_id": "steel_sword", "weight": 7, "min": 1, "max": 1},
		{"item_id": "iron_axe", "weight": 6, "min": 1, "max": 1},
		{"item_id": "battle_axe", "weight": 4, "min": 1, "max": 1},
		{"item_id": "arcane_staff", "weight": 5, "min": 1, "max": 1},
		{"item_id": "longbow", "weight": 4, "min": 1, "max": 1},
		{"item_id": "iron_helm", "weight": 5, "min": 1, "max": 1},
		{"item_id": "chainmail", "weight": 5, "min": 1, "max": 1},
		{"item_id": "iron_greaves", "weight": 4, "min": 1, "max": 1},
		{"item_id": "champions_crown", "weight": 3, "min": 1, "max": 1},
		{"item_id": "plate_armor", "weight": 3, "min": 1, "max": 1},
		{"item_id": "windrunner_boots", "weight": 3, "min": 1, "max": 1},
		{"item_id": "paladin_blade", "weight": 1, "min": 1, "max": 1},
	],
	"barrel": [
		{"item_id": "gold_pile", "weight": 60, "min": 1, "max": 2},
		{"item_id": "health_potion", "weight": 30, "min": 1, "max": 1},
		{"item_id": "mana_potion", "weight": 10, "min": 1, "max": 1},
	],
}

# Hero inventory + gold
var gold: int = 0
var inventory: Array[Dictionary] = []  # Array of item dicts
var equipped: Dictionary = {}  # SlotType int → item dict (persisted for save/load)
var max_inventory_size: int:
	get: return BalanceConfig.MAX_INVENTORY_SIZE

# Loot drop scene (built programmatically)
var _loot_drop_script: GDScript

func _ready() -> void:
	_loot_drop_script = load("res://scripts/loot_drop.gd")
	GameManager.enemy_died.connect(_on_enemy_died)

# ---------- STAT ROLLING ----------

## Roll rarity-scaled stats onto an item instance.
## Takes a base item template and returns a new dict with rolled stats.
func roll_item_stats(base_item: Dictionary) -> Dictionary:
	var item := base_item.duplicate(true)
	var rarity: int = item.get("rarity", Rarity.COMMON)
	var mult: float = RARITY_MULT.get(rarity, 1.0)
	# Slight randomness: ±15%
	var variance := randf_range(0.85, 1.15)
	mult *= variance
	# NG+ loot quality boost
	mult *= NewGamePlus.get_loot_quality_multiplier()

	# Roll each stat that starts with "base_"
	var stat_desc_parts: Array[String] = []

	if item.has("base_damage"):
		item["damage_bonus"] = maxi(int(item["base_damage"] * mult), 1)
		stat_desc_parts.append("+%d Dmg" % item["damage_bonus"])
	if item.has("base_str"):
		item["str_bonus"] = maxi(int(item["base_str"] * mult), 1)
		stat_desc_parts.append("+%d STR" % item["str_bonus"])
	if item.has("base_int"):
		item["int_bonus"] = maxi(int(item["base_int"] * mult), 1)
		stat_desc_parts.append("+%d INT" % item["int_bonus"])
	if item.has("base_dex"):
		item["dex_bonus"] = maxi(int(item["base_dex"] * mult), 1)
		stat_desc_parts.append("+%d DEX" % item["dex_bonus"])
	if item.has("base_con"):
		item["con_bonus"] = maxi(int(item["base_con"] * mult), 1)
		stat_desc_parts.append("+%d CON" % item["con_bonus"])
	if item.has("base_crit"):
		item["crit_bonus"] = maxi(int(item["base_crit"] * mult), 1)
		stat_desc_parts.append("+%d%% Crit" % item["crit_bonus"])
	if item.has("base_spell_power"):
		item["spell_power_bonus"] = maxi(int(item["base_spell_power"] * mult), 1)
		stat_desc_parts.append("+%d SP" % item["spell_power_bonus"])
	if item.has("base_armor"):
		item["armor_bonus"] = maxi(int(item["base_armor"] * mult), 1)
		stat_desc_parts.append("+%d Armor" % item["armor_bonus"])
	if item.has("base_hp"):
		item["hp_bonus"] = maxi(int(item["base_hp"] * mult), 5)
		stat_desc_parts.append("+%d HP" % item["hp_bonus"])
	if item.has("base_speed"):
		item["speed_bonus"] = maxi(int(item["base_speed"] * mult), 1)
		stat_desc_parts.append("+%d%% Speed" % item["speed_bonus"])

	# Build description from rolled stats
	if stat_desc_parts.size() > 0:
		item["description"] = item.get("description", "") + " " + ", ".join(stat_desc_parts) + "."

	return item

# Map equip_slot string to inventory SlotType int
const EQUIP_SLOT_MAP := {
	"head": 1,    # SlotType.HEAD
	"chest": 2,   # SlotType.CHEST
	"hands": 3,   # SlotType.HANDS
	"feet": 4,    # SlotType.FEET
	"ring": 5,    # SlotType.RING
	"trinket": 6, # SlotType.TRINKET
	"weapon": 7,  # SlotType.WEAPON
	"offhand": 8, # SlotType.OFFHAND
}

## Get the SlotType int for an item (which equip slot it goes to).
func get_item_slot_type(item: Dictionary) -> int:
	var slot_str: String = item.get("equip_slot", "")
	if slot_str == "" and item.get("type", "") == "weapon":
		return 7  # Default weapons to WEAPON slot
	return EQUIP_SLOT_MAP.get(slot_str, -1)

# ---------- ENEMY DROPS ----------

func _on_enemy_died(enemy: Node3D) -> void:
	var is_boss := "boss_type" in enemy
	var enemy_type := "default"

	if is_boss:
		var table: Array = LOOT_TABLES.get("boss", LOOT_TABLES["default"])
		for _roll in range(BalanceConfig.BOSS_DROP_COUNT):
			var rolled_item := _roll_weighted(table)
			if rolled_item.is_empty():
				continue
			var item_def: Dictionary = ITEMS.get(rolled_item["item_id"], {})
			if item_def.is_empty():
				continue
			var count := randi_range(rolled_item.get("min", 1), rolled_item.get("max", 1))
			for _i in range(count):
				var final_item := _prepare_drop(item_def)
				_spawn_drop(enemy.global_position, final_item)
		return

	if "enemy_type" in enemy:
		enemy_type = enemy.enemy_type
	var table_key := "default"
	if enemy_type.begins_with("goblin"):
		table_key = "goblin"
	elif enemy_type in ["skeleton", "orc"]:
		table_key = "skeleton"

	if randf() > BalanceConfig.LOOT_DROP_CHANCE:
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
		var final_item := _prepare_drop(item_def)
		_spawn_drop(enemy.global_position, final_item)

## Prepare a drop — roll stats for equipment, pass through consumables/currency.
func _prepare_drop(item_def: Dictionary) -> Dictionary:
	var item_type: String = item_def.get("type", "")
	if item_type == "weapon" or item_type == "armor":
		return roll_item_stats(item_def)
	return item_def

## Roll loot from a named table (for chests, barrels, etc.)
func roll_from_table(table_name: String) -> Dictionary:
	var table: Array = LOOT_TABLES.get(table_name, LOOT_TABLES["default"])
	var rolled := _roll_weighted(table)
	if rolled.is_empty():
		return {}
	var item_def: Dictionary = ITEMS.get(rolled["item_id"], {})
	if item_def.is_empty():
		return {}
	return _prepare_drop(item_def)

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

	var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	drop.position = world_pos + offset + Vector3.UP * 0.5

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
	elif item_def["type"] in ["weapon", "armor"]:
		if inventory.size() < max_inventory_size:
			inventory.append(item_def.duplicate())
			inventory_changed.emit()
			item_picked_up.emit(item_def)

func _apply_consumable(item_def: Dictionary) -> void:
	RunStats.record_potion_used()
	var hero = GameManager.hero
	if hero == null or hero.is_dead:
		return
	if item_def["id"] == "health_potion":
		var heal: int = item_def.get("heal_amount", 100)
		hero.current_health = mini(hero.current_health + heal, hero.max_health)
		hero.health_changed.emit(hero.current_health, hero.max_health)
		GameManager.request_damage_number(hero.global_position + Vector3.UP * 2.5, heal, false)
	elif item_def["id"] == "mana_potion":
		var mana: int = item_def.get("mana_amount", 60)
		hero.current_mana = mini(hero.current_mana + mana, hero.max_mana)
		hero.mana_changed.emit(hero.current_mana, hero.max_mana)
	elif item_def["id"] == "elixir_vial":
		var heal: int = item_def.get("heal_amount", 80)
		var mana: int = item_def.get("mana_amount", 50)
		hero.current_health = mini(hero.current_health + heal, hero.max_health)
		hero.health_changed.emit(hero.current_health, hero.max_health)
		hero.current_mana = mini(hero.current_mana + mana, hero.max_mana)
		hero.mana_changed.emit(hero.current_mana, hero.max_mana)
		GameManager.request_damage_number(hero.global_position + Vector3.UP * 2.5, heal, false)

## Remove a specific item from inventory by id. Removes first match found.
func remove_item(item_def: Dictionary) -> void:
	var target_id: String = item_def.get("id", "")
	for i in range(inventory.size()):
		if inventory[i].get("id", "") == target_id:
			inventory.remove_at(i)
			inventory_changed.emit()
			return
