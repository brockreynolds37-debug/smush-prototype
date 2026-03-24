extends Node

## Skill Tree — 3 branches per civilization (offensive/defensive/utility).
## Spend skill points on level-up. 3-4 nodes per branch. Persistent per run.

signal skill_unlocked(skill_id: String)
signal skill_points_changed(points: int)

var skill_points: int = 0
var unlocked_skills: Array[String] = []

# Skill definitions per character trait (keyed by trait_id)
# Each skill: {id, name, desc, branch, tier (0-3), effect: Dictionary}
const SKILL_TREES: Dictionary = {
	"exoskeleton": {  # Fat Nate — Brawler
		"offensive": [
			{"id": "ex_heavy_blows", "name": "Heavy Blows", "desc": "+20% melee damage", "tier": 0, "effect": {"melee_mult": 0.2}},
			{"id": "ex_cleave", "name": "Cleave", "desc": "Melee hits splash 30% damage to nearby enemies", "tier": 1, "effect": {"cleave_pct": 0.3}},
			{"id": "ex_ground_mastery", "name": "Ground Mastery", "desc": "Ground Slam +40% radius, -3s cooldown", "tier": 2, "effect": {"slam_radius": 0.4, "slam_cd": -3.0}},
		],
		"defensive": [
			{"id": "ex_iron_skin", "name": "Iron Skin", "desc": "+10% damage reduction (stacks with Exoskeleton)", "tier": 0, "effect": {"damage_reduce": 0.1}},
			{"id": "ex_regen", "name": "Regeneration", "desc": "Recover 1% max HP per second", "tier": 1, "effect": {"hp_regen_pct": 0.01}},
			{"id": "ex_fortress", "name": "Fortress", "desc": "+150 max HP, +25 armor", "tier": 2, "effect": {"bonus_hp": 150, "bonus_armor": 25}},
		],
		"utility": [
			{"id": "ex_intimidate", "name": "Intimidate", "desc": "+25% VP from kills", "tier": 0, "effect": {"vp_mult": 0.25}},
			{"id": "ex_scavenger", "name": "Scavenger", "desc": "+30% gold from all sources", "tier": 1, "effect": {"gold_mult": 0.3}},
			{"id": "ex_crowd_fav", "name": "Crowd Favorite", "desc": "Audience gifts arrive 50% more often", "tier": 2, "effect": {"gift_rate": 0.5}},
		],
	},
	"adaptable": {  # Sir Gallan — Paladin
		"offensive": [
			{"id": "ad_smite", "name": "Smite", "desc": "+15% spell power", "tier": 0, "effect": {"spell_mult": 0.15}},
			{"id": "ad_judgment", "name": "Judgment", "desc": "Melee attacks restore 5 mana", "tier": 1, "effect": {"melee_mana": 5}},
			{"id": "ad_radiance", "name": "Radiance", "desc": "Heal spell also damages nearby enemies for 50", "tier": 2, "effect": {"heal_damage": 50}},
		],
		"defensive": [
			{"id": "ad_blessed", "name": "Blessed Shield", "desc": "+15% damage reduction", "tier": 0, "effect": {"damage_reduce": 0.15}},
			{"id": "ad_holy_heal", "name": "Holy Heal", "desc": "Heal restores +50% more HP", "tier": 1, "effect": {"heal_mult": 0.5}},
			{"id": "ad_resilience", "name": "Resilience", "desc": "+2 stats per floor (up from +1)", "tier": 2, "effect": {"adapt_bonus": 1}},
		],
		"utility": [
			{"id": "ad_aura", "name": "Inspiring Aura", "desc": "+15% move speed", "tier": 0, "effect": {"speed_mult": 0.15}},
			{"id": "ad_wisdom", "name": "Wisdom", "desc": "+25% XP from all sources", "tier": 1, "effect": {"xp_mult": 0.25}},
			{"id": "ad_divine", "name": "Divine Luck", "desc": "+1 rarity tier on all loot drops", "tier": 2, "effect": {"rarity_bonus": 1}},
		],
	},
	"berserker_rage": {  # Grokk — Berserker
		"offensive": [
			{"id": "br_fury", "name": "Fury", "desc": "+25% attack speed", "tier": 0, "effect": {"attack_speed": 0.25}},
			{"id": "br_frenzy", "name": "Frenzy", "desc": "Each kill extends berserker threshold to 40% HP", "tier": 1, "effect": {"rage_threshold": 0.1}},
			{"id": "br_carnage", "name": "Carnage", "desc": "Berserker bonus increased to +80% damage", "tier": 2, "effect": {"rage_bonus": 0.3}},
		],
		"defensive": [
			{"id": "br_bloodlust", "name": "Bloodlust", "desc": "Heal 10% of damage dealt", "tier": 0, "effect": {"lifesteal": 0.1}},
			{"id": "br_thick_skin", "name": "Thick Skin", "desc": "+100 max HP", "tier": 1, "effect": {"bonus_hp": 100}},
			{"id": "br_undying", "name": "Undying Rage", "desc": "Survive lethal hit once per floor (1 HP)", "tier": 2, "effect": {"cheat_death": true}},
		],
		"utility": [
			{"id": "br_warcry", "name": "War Cry", "desc": "+20% VP from chain kills", "tier": 0, "effect": {"chain_vp": 0.2}},
			{"id": "br_plunder", "name": "Plunder", "desc": "Enemies drop +1 gold", "tier": 1, "effect": {"bonus_gold": 1}},
			{"id": "br_showman", "name": "Showmanship", "desc": "Near-death VP doubled", "tier": 2, "effect": {"near_death_vp": 2.0}},
		],
	},
	"arcane_surge": {  # Elara — Sorcerer
		"offensive": [
			{"id": "as_empowered", "name": "Empowered", "desc": "+25% spell power", "tier": 0, "effect": {"spell_mult": 0.25}},
			{"id": "as_chain", "name": "Chain Lightning", "desc": "Fireball hits 2 additional nearby enemies for 50% damage", "tier": 1, "effect": {"chain_spell": true}},
			{"id": "as_arcane_blast", "name": "Arcane Blast", "desc": "-30% all spell cooldowns", "tier": 2, "effect": {"cd_reduce": 0.3}},
		],
		"defensive": [
			{"id": "as_mana_shield", "name": "Mana Shield", "desc": "10% of damage taken from mana instead", "tier": 0, "effect": {"mana_shield": 0.1}},
			{"id": "as_deep_pool", "name": "Deep Pool", "desc": "+150 max mana", "tier": 1, "effect": {"bonus_mana": 150}},
			{"id": "as_aether", "name": "Aether Body", "desc": "+20% dodge chance", "tier": 2, "effect": {"dodge": 0.2}},
		],
		"utility": [
			{"id": "as_mana_regen", "name": "Mana Flow", "desc": "+100% mana regeneration", "tier": 0, "effect": {"mana_regen": 1.0}},
			{"id": "as_spell_variety", "name": "Spell Variety", "desc": "+50% VP from spell variety bonus", "tier": 1, "effect": {"variety_vp": 0.5}},
			{"id": "as_transcend", "name": "Transcendence", "desc": "Arcane Surge restores +15 mana on kill (35 total)", "tier": 2, "effect": {"surge_bonus": 15}},
		],
	},
	"eagle_eye": {  # Theron — Marksman
		"offensive": [
			{"id": "ee_precision", "name": "Precision", "desc": "+15% crit chance", "tier": 0, "effect": {"crit_bonus": 15}},
			{"id": "ee_headshot", "name": "Headshot", "desc": "Crits deal 2.5x damage (up from 1.8x)", "tier": 1, "effect": {"crit_mult": 0.7}},
			{"id": "ee_rapid_fire", "name": "Rapid Fire", "desc": "+40% attack speed", "tier": 2, "effect": {"attack_speed": 0.4}},
		],
		"defensive": [
			{"id": "ee_evasion", "name": "Evasion", "desc": "+15% dodge chance", "tier": 0, "effect": {"dodge": 0.15}},
			{"id": "ee_trap_immune", "name": "Trap Sense", "desc": "Immune to floor traps", "tier": 1, "effect": {"trap_immune": true}},
			{"id": "ee_windwalk", "name": "Wind Walk", "desc": "+25% move speed, -20% damage taken while moving", "tier": 2, "effect": {"speed_mult": 0.25, "move_reduce": 0.2}},
		],
		"utility": [
			{"id": "ee_tracker", "name": "Tracker", "desc": "+50% aggro range (spot enemies sooner)", "tier": 0, "effect": {"aggro_range": 0.5}},
			{"id": "ee_salvage", "name": "Salvage", "desc": "+25% more loot from chests", "tier": 1, "effect": {"chest_bonus": 0.25}},
			{"id": "ee_sniper", "name": "Sniper's Eye", "desc": "+50% spell range", "tier": 2, "effect": {"range_mult": 0.5}},
		],
	},
	"phase_walk": {  # Shade — Assassin
		"offensive": [
			{"id": "pw_backstab", "name": "Backstab", "desc": "+30% damage to enemies from behind", "tier": 0, "effect": {"backstab": 0.3}},
			{"id": "pw_poison_blade", "name": "Poison Blade", "desc": "Melee attacks apply 3s poison (6 dmg/tick)", "tier": 1, "effect": {"poison_melee": true}},
			{"id": "pw_execute", "name": "Execute", "desc": "Deal 3x damage to enemies below 20% HP", "tier": 2, "effect": {"execute_mult": 3.0}},
		],
		"defensive": [
			{"id": "pw_shadow_step", "name": "Shadow Step", "desc": "+3 phase walk charges per floor (8 total)", "tier": 0, "effect": {"phase_charges": 3}},
			{"id": "pw_smoke_bomb", "name": "Smoke Bomb", "desc": "On dodge, enemies lose aggro for 2s", "tier": 1, "effect": {"smoke_deaggro": 2.0}},
			{"id": "pw_phantom", "name": "Phantom", "desc": "Phase walk dodge chance increased to 35%", "tier": 2, "effect": {"dodge_boost": 0.1}},
		],
		"utility": [
			{"id": "pw_pickpocket", "name": "Pickpocket", "desc": "+50% gold from enemies", "tier": 0, "effect": {"gold_mult": 0.5}},
			{"id": "pw_assassin_vp", "name": "Assassin's Flair", "desc": "+30% VP from all kills", "tier": 1, "effect": {"vp_mult": 0.3}},
			{"id": "pw_vanish", "name": "Vanish", "desc": "3s invulnerability on floor start", "tier": 2, "effect": {"floor_invuln": 3.0}},
		],
	},
}

func _ready() -> void:
	XpManager.level_up.connect(_on_level_up)

func _on_level_up(_new_level: int) -> void:
	skill_points += 1
	skill_points_changed.emit(skill_points)

func get_tree_for_character() -> Dictionary:
	var trait_id = CharacterData.get_selected().get("trait_id", "exoskeleton")
	return SKILL_TREES.get(trait_id, SKILL_TREES["exoskeleton"])

func can_unlock(skill_id: String) -> bool:
	if skill_points <= 0:
		return false
	if skill_id in unlocked_skills:
		return false
	# Find the skill and check tier prerequisites
	var tree = get_tree_for_character()
	for branch_name in tree:
		var branch: Array = tree[branch_name]
		for skill in branch:
			if skill["id"] == skill_id:
				# Tier 0 = no prereq. Tier 1+ requires previous tier in same branch.
				if skill["tier"] == 0:
					return true
				for prev_skill in branch:
					if prev_skill["tier"] == skill["tier"] - 1 and prev_skill["id"] in unlocked_skills:
						return true
				return false
	return false

func unlock_skill(skill_id: String) -> bool:
	if not can_unlock(skill_id):
		return false
	skill_points -= 1
	unlocked_skills.append(skill_id)
	skill_unlocked.emit(skill_id)
	skill_points_changed.emit(skill_points)
	return true

func has_skill(skill_id: String) -> bool:
	return skill_id in unlocked_skills

func get_skill_effect(skill_id: String) -> Dictionary:
	var tree = get_tree_for_character()
	for branch_name in tree:
		for skill in tree[branch_name]:
			if skill["id"] == skill_id:
				return skill.get("effect", {})
	return {}

func get_total_effect(effect_key: String) -> float:
	var total := 0.0
	var tree = get_tree_for_character()
	for branch_name in tree:
		for skill in tree[branch_name]:
			if skill["id"] in unlocked_skills:
				var effects: Dictionary = skill.get("effect", {})
				if effects.has(effect_key):
					var val = effects[effect_key]
					if val is bool:
						total = 1.0
					else:
						total += float(val)
	return total

func reset() -> void:
	skill_points = 0
	unlocked_skills.clear()
