extends Node

## Global character data — defines playable characters and stores the player's selection.

signal character_selected(char_id: String)

var selected_character: String = "fat_nate"
var selected_spell_set: int = 0  # 0 = default, 1 = alternate

# Character definitions
var characters: Array[Dictionary] = [
	{
		"id": "fat_nate",
		"name": "Fat Nate",
		"class": "Brawler",
		"description": "A hefty bruiser who hits hard and takes a beating.\nHigh HP, devastating ground slams.",
		"model_path": "res://assets/models/fat-nate/walking.glb",
		"attack_model": "res://assets/models/fat-nate/sword_slash.glb",
		"death_model": "res://assets/models/fat-nate/dead.glb",
		"cast_model": "res://assets/models/fat-nate/punch_combo.glb",
		"color_primary": Color(0.15, 0.25, 0.5),
		"color_secondary": Color(0.87, 0.72, 0.58),
		"stats": {"HP": 500, "Mana": 200, "STR": 8, "DEX": 4, "CON": 9, "INT": 3},
		"spell_sets": [
			{"names": ["Strike", "Fireball", "Heal", "Ground Slam"],
			 "cooldowns": [1.5, 5.0, 8.0, 15.0],
			 "mana_costs": [0, 30, 40, 60],
			 "label": "Elementalist"},
			{"names": ["Charge", "War Cry", "Shield Bash", "Earthquake"],
			 "cooldowns": [2.0, 10.0, 6.0, 18.0],
			 "mana_costs": [0, 40, 25, 70],
			 "label": "Warlord"},
		],
		"trait_id": "exoskeleton",
		"trait_name": "Exoskeleton",
		"trait_desc": "Natural armor reduces all damage taken by 20%.",
	},
	{
		"id": "knight",
		"name": "Sir Gallan",
		"class": "Paladin",
		"description": "Holy warrior clad in heavy armor.\nBalanced stats, powerful heal, resilient.",
		"model_path": "res://assets/models/npcs/Knight.glb",
		"attack_model": "",
		"death_model": "",
		"cast_model": "",
		"color_primary": Color(0.6, 0.6, 0.7),
		"color_secondary": Color(0.3, 0.3, 0.4),
		"stats": {"HP": 600, "Mana": 250, "STR": 7, "DEX": 4, "CON": 8, "INT": 5},
		"spell_sets": [
			{"names": ["Strike", "Fireball", "Heal", "Ground Slam"],
			 "cooldowns": [1.5, 5.0, 8.0, 15.0],
			 "mana_costs": [0, 30, 40, 60],
			 "label": "Elementalist"},
			{"names": ["Smite", "Holy Shield", "Consecrate", "Divine Judgment"],
			 "cooldowns": [1.5, 12.0, 8.0, 20.0],
			 "mana_costs": [0, 50, 35, 80],
			 "label": "Crusader"},
		],
		"trait_id": "adaptable",
		"trait_name": "Adaptable",
		"trait_desc": "+1 to a random stat each floor. Grows stronger the deeper you go.",
	},
	{
		"id": "barbarian",
		"name": "Grokk",
		"class": "Berserker",
		"description": "Raw fury incarnate. Low defense, absurd damage.\nEnrage passive: hits harder at low HP.",
		"model_path": "res://assets/models/npcs/Barbarian.glb",
		"attack_model": "",
		"death_model": "",
		"cast_model": "",
		"color_primary": Color(0.6, 0.25, 0.15),
		"color_secondary": Color(0.75, 0.6, 0.45),
		"stats": {"HP": 400, "Mana": 100, "STR": 10, "DEX": 6, "CON": 6, "INT": 2},
		"spell_sets": [
			{"names": ["Strike", "Fireball", "Heal", "Ground Slam"],
			 "cooldowns": [1.5, 5.0, 8.0, 15.0],
			 "mana_costs": [0, 30, 40, 60],
			 "label": "Elementalist"},
			{"names": ["Cleave", "Blood Frenzy", "Whirlwind", "Execute"],
			 "cooldowns": [1.0, 15.0, 6.0, 12.0],
			 "mana_costs": [0, 30, 35, 50],
			 "label": "Bloodletter"},
		],
		"trait_id": "berserker_rage",
		"trait_name": "Berserker Rage",
		"trait_desc": "Below 30% HP, deal 50% more damage from all sources.",
	},
	{
		"id": "mage",
		"name": "Elara",
		"class": "Sorcerer",
		"description": "Master of the arcane arts. Fragile but devastating.\nHuge mana pool, low cooldowns.",
		"model_path": "res://assets/models/npcs/Mage.glb",
		"attack_model": "",
		"death_model": "",
		"cast_model": "",
		"color_primary": Color(0.3, 0.15, 0.6),
		"color_secondary": Color(0.85, 0.8, 0.7),
		"stats": {"HP": 300, "Mana": 400, "STR": 3, "DEX": 5, "CON": 4, "INT": 10},
		"spell_sets": [
			{"names": ["Strike", "Fireball", "Heal", "Ground Slam"],
			 "cooldowns": [1.5, 5.0, 8.0, 15.0],
			 "mana_costs": [0, 30, 40, 60],
			 "label": "Elementalist"},
			{"names": ["Arcane Bolt", "Ice Wall", "Chain Lightning", "Meteor"],
			 "cooldowns": [1.0, 10.0, 7.0, 20.0],
			 "mana_costs": [10, 45, 50, 90],
			 "label": "Arcanist"},
		],
		"trait_id": "arcane_surge",
		"trait_name": "Arcane Surge",
		"trait_desc": "Each enemy kill restores 20 mana. Spell cooldowns reduced 15%.",
	},
	{
		"id": "ranger",
		"name": "Theron",
		"class": "Marksman",
		"description": "Eagle-eyed hunter. Fast and precise.\nLong attack range, quick cooldowns.",
		"model_path": "res://assets/models/npcs/Ranger.glb",
		"attack_model": "",
		"death_model": "",
		"cast_model": "",
		"color_primary": Color(0.2, 0.45, 0.2),
		"color_secondary": Color(0.55, 0.4, 0.25),
		"stats": {"HP": 350, "Mana": 200, "STR": 5, "DEX": 10, "CON": 5, "INT": 4},
		"spell_sets": [
			{"names": ["Strike", "Fireball", "Heal", "Ground Slam"],
			 "cooldowns": [1.5, 5.0, 8.0, 15.0],
			 "mana_costs": [0, 30, 40, 60],
			 "label": "Elementalist"},
			{"names": ["Aimed Shot", "Trap", "Volley", "Snipe"],
			 "cooldowns": [2.0, 12.0, 8.0, 16.0],
			 "mana_costs": [0, 30, 45, 60],
			 "label": "Sharpshooter"},
		],
		"trait_id": "eagle_eye",
		"trait_name": "Eagle Eye",
		"trait_desc": "+30% attack range and spell targeting range.",
	},
	{
		"id": "rogue",
		"name": "Shade",
		"class": "Assassin",
		"description": "Silent and lethal. Thrives in chaos.\nCritical strikes, evasion, fast movement.",
		"model_path": "res://assets/models/npcs/Rogue_Hooded.glb",
		"attack_model": "",
		"death_model": "",
		"cast_model": "",
		"color_primary": Color(0.15, 0.15, 0.2),
		"color_secondary": Color(0.4, 0.35, 0.3),
		"stats": {"HP": 350, "Mana": 150, "STR": 6, "DEX": 9, "CON": 5, "INT": 4},
		"spell_sets": [
			{"names": ["Strike", "Fireball", "Heal", "Ground Slam"],
			 "cooldowns": [1.5, 5.0, 8.0, 15.0],
			 "mana_costs": [0, 30, 40, 60],
			 "label": "Elementalist"},
			{"names": ["Backstab", "Smoke Bomb", "Fan of Knives", "Shadow Strike"],
			 "cooldowns": [1.0, 14.0, 5.0, 12.0],
			 "mana_costs": [0, 35, 30, 55],
			 "label": "Shadow Arts"},
		],
		"trait_id": "phase_walk",
		"trait_name": "Phase Walk",
		"trait_desc": "25% chance to dodge damage entirely. 5 charges per floor.",
	},
]

func get_character(char_id: String) -> Dictionary:
	for c in characters:
		if c["id"] == char_id:
			return c
	return characters[0]

func get_selected() -> Dictionary:
	return get_character(selected_character)

func select(char_id: String, spell_set_index: int = 0) -> void:
	selected_character = char_id
	selected_spell_set = spell_set_index
	character_selected.emit(char_id)

func get_selected_spell_set() -> Dictionary:
	var char_data = get_selected()
	var sets = char_data.get("spell_sets", [])
	if selected_spell_set >= 0 and selected_spell_set < sets.size():
		return sets[selected_spell_set]
	return sets[0] if sets.size() > 0 else {}
