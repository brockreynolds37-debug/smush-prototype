extends Node

## Save/Load Manager — persists run state between sessions.
## Auto-saves on floor transition. Deletes save on death (roguelike).
## "Continue" on main menu loads the saved run.

const SAVE_PATH := "user://savegame.json"

signal save_completed
signal load_completed

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	# INSANE difficulty = permadeath, no auto-saving
	if GameManager.is_permadeath():
		return
	var data := _gather_save_data()
	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		save_completed.emit()

func load_game() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json_string := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_string)
	if err != OK:
		return {}
	var data: Dictionary = json.data
	load_completed.emit()
	return data

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)

func _gather_save_data() -> Dictionary:
	var hero = GameManager.hero
	var hero_data := {}
	if hero and is_instance_valid(hero):
		hero_data = {
			"current_health": hero.current_health,
			"max_health": hero.max_health,
			"current_mana": hero.current_mana,
			"max_mana": hero.max_mana,
		}

	# Serialize inventory — strip non-serializable fields (Color, etc.)
	var inv_data: Array = []
	for item in LootManager.inventory:
		inv_data.append(_serialize_item(item))

	# Serialize equipped items
	var equip_data := {}
	for slot_type in LootManager.equipped:
		equip_data[str(slot_type)] = _serialize_item(LootManager.equipped[slot_type])

	return {
		"version": 1,
		"difficulty": GameManager.difficulty,
		"character_id": CharacterData.selected_character,
		"floor": FloorManager.current_floor,
		"hero": hero_data,
		"gold": LootManager.gold,
		"inventory": inv_data,
		"equipped": equip_data,
		"xp": {
			"current_xp": XpManager.current_xp,
			"current_level": XpManager.current_level,
			"bonus_hp": XpManager.bonus_hp,
			"bonus_mana": XpManager.bonus_mana,
			"bonus_str": XpManager.bonus_str,
			"bonus_dex": XpManager.bonus_dex,
			"bonus_con": XpManager.bonus_con,
			"bonus_int": XpManager.bonus_int,
		},
		"audience": {
			"vp": AudienceManager.total_vp,
		},
		"run_time": GameManager.get_run_elapsed(),
		"run_kills": GameManager.run_kills,
		"skills": {
			"points": SkillTree.skill_points,
			"unlocked": SkillTree.unlocked_skills.duplicate(),
		},
	}

func apply_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	# Restore difficulty
	GameManager.difficulty = int(data.get("difficulty", GameManager.Difficulty.NORMAL))

	# Restore character selection
	CharacterData.selected_character = data.get("character_id", "fat_nate")

	# Restore floor
	FloorManager.current_floor = int(data.get("floor", 1))
	FloorManager.max_floor_reached = FloorManager.current_floor

	# Restore gold + inventory
	LootManager.gold = int(data.get("gold", 0))
	LootManager.inventory.clear()
	var inv_array: Array = data.get("inventory", [])
	for item_data in inv_array:
		LootManager.inventory.append(_deserialize_item(item_data))
	# Restore equipped items
	LootManager.equipped.clear()
	var equip_dict: Dictionary = data.get("equipped", {})
	for slot_key in equip_dict:
		LootManager.equipped[int(slot_key)] = _deserialize_item(equip_dict[slot_key])
	LootManager.inventory_changed.emit()
	LootManager.gold_changed.emit(LootManager.gold)

	# Restore XP state
	var xp_data: Dictionary = data.get("xp", {})
	XpManager.current_xp = int(xp_data.get("current_xp", 0))
	XpManager.current_level = int(xp_data.get("current_level", 1))
	XpManager.bonus_hp = int(xp_data.get("bonus_hp", 0))
	XpManager.bonus_mana = int(xp_data.get("bonus_mana", 0))
	XpManager.bonus_str = int(xp_data.get("bonus_str", 0))
	XpManager.bonus_dex = int(xp_data.get("bonus_dex", 0))
	XpManager.bonus_con = int(xp_data.get("bonus_con", 0))
	XpManager.bonus_int = int(xp_data.get("bonus_int", 0))

	# Restore audience VP
	var audience_data: Dictionary = data.get("audience", {})
	AudienceManager.total_vp = int(audience_data.get("vp", 0))

	# Restore run stats
	GameManager.run_kills = int(data.get("run_kills", 0))

	# Restore skill tree
	var skill_data: Dictionary = data.get("skills", {})
	SkillTree.skill_points = int(skill_data.get("points", 0))
	SkillTree.unlocked_skills.clear()
	for sid in skill_data.get("unlocked", []):
		SkillTree.unlocked_skills.append(str(sid))

func apply_hero_state(data: Dictionary) -> void:
	## Call after hero is spawned to restore HP/Mana from save.
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		return
	var hero_data: Dictionary = data.get("hero", {})
	if hero_data.is_empty():
		return
	hero.max_health = int(hero_data.get("max_health", hero.max_health))
	hero.current_health = int(hero_data.get("current_health", hero.current_health))
	hero.max_mana = int(hero_data.get("max_mana", hero.max_mana))
	hero.current_mana = int(hero_data.get("current_mana", hero.current_mana))
	hero.health_changed.emit(hero.current_health, hero.max_health)
	hero.mana_changed.emit(hero.current_mana, hero.max_mana)

# ---------- SERIALIZATION HELPERS ----------

func _serialize_item(item: Dictionary) -> Dictionary:
	var out := {}
	for key in item:
		var val = item[key]
		if val is Color:
			out[key] = "#%s" % val.to_html(true)
		elif val is int or val is float or val is String or val is bool:
			out[key] = val
		# Skip non-serializable types (PackedScene, etc.)
	return out

func _deserialize_item(data: Dictionary) -> Dictionary:
	var out := {}
	for key in data:
		var val = data[key]
		if val is String and val.begins_with("#") and val.length() >= 7:
			out[key] = Color.html(val)
		else:
			out[key] = val
	return out
