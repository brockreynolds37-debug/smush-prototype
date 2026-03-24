extends Node

## Achievement Manager — tracks 15 Steam-style achievements.
## Saves unlock state to user://achievements.json. Shows popup on unlock.

signal achievement_unlocked(achievement_id: String, achievement: Dictionary)

# Achievement definitions: id → { title, description, icon_emoji, unlocked }
var achievements: Dictionary = {}

# Persistent unlock state loaded from disk
var _save_path: String = "user://achievements.json"

# Floor damage tracking (for "Untouchable")
var _floor_damage_taken: int = 0

# Character usage tracking (for "Polyglot")
var _characters_used: Dictionary = {}  # char_name → true

# Negotiation count tracking (for "Social Butterfly")
var _negotiations_this_run: int = 0

func _ready() -> void:
	_define_achievements()
	_load()
	# Connect to game signals
	GameManager.enemy_died.connect(_on_enemy_died)
	GameManager.game_over.connect(_on_game_over)
	AudienceManager.mood_changed.connect(_on_mood_changed)
	RunStats.stat_updated.connect(_on_stat_updated)
	FloorManager.floor_changed.connect(_on_floor_changed)
	LootManager.inventory_changed.connect(_on_inventory_changed)
	BriberySystem.bribe_attempted.connect(_on_bribe_attempted)

func _define_achievements() -> void:
	var defs := [
		["first_blood", "First Blood", "Get your first kill.", "🗡️"],
		["crowd_goes_wild", "The Crowd Goes Wild", "Reach ERUPTING audience mood.", "🎉"],
		["speed_smusher", "Speed Smusher", "Clear Floor 1 in under 3 minutes.", "⚡"],
		["smush_kill", "Smush Kill", "Lure an enemy into the collapsing Smush wall.", "💀"],
		["true_champion", "True Champion", "Beat all 3 floors and defeat the final boss.", "🏆"],
		["overkill", "Overkill", "Deal 1000+ damage in a single hit.", "💥"],
		["social_butterfly", "Social Butterfly", "Successfully negotiate or bribe 5 times in one run.", "🦋"],
		["untouchable", "Untouchable", "Complete a floor without taking any damage.", "🛡️"],
		["hoarder", "Hoarder", "Fill all 20 inventory slots at once.", "🎒"],
		["polyglot", "Polyglot", "Play as 6 different characters across runs.", "🌍"],
		["boss_slayer", "Boss Slayer", "Defeat 10 bosses across all runs.", "👑"],
		["spell_master", "Spell Master", "Cast 100 spells in a single run.", "✨"],
		["gold_rush", "Gold Rush", "Earn 500 gold in a single run.", "💰"],
		["elite_hunter", "Elite Hunter", "Kill 25 elite enemies across all runs.", "⚔️"],
		["deep_diver", "Deep Diver", "Reach Floor 4 — The Deep.", "🕳️"],
	]
	for d in defs:
		achievements[d[0]] = {
			"title": d[1],
			"description": d[2],
			"icon": d[3],
			"unlocked": false,
			"unlock_time": "",
		}

# ---- Unlock Logic ----

func _try_unlock(id: String) -> void:
	if not achievements.has(id):
		return
	if achievements[id]["unlocked"]:
		return
	achievements[id]["unlocked"] = true
	achievements[id]["unlock_time"] = Time.get_datetime_string_from_system()
	_save()
	achievement_unlocked.emit(id, achievements[id])
	_show_popup(achievements[id])

func _show_popup(ach: Dictionary) -> void:
	# Create a CanvasLayer popup that fades in/out
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(660, 20)
	panel.size = Vector2(600, 80)
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	stylebox.border_color = Color(1.0, 0.85, 0.0)
	stylebox.border_width_bottom = 2
	stylebox.border_width_top = 2
	stylebox.border_width_left = 2
	stylebox.border_width_right = 2
	stylebox.corner_radius_top_left = 8
	stylebox.corner_radius_top_right = 8
	stylebox.corner_radius_bottom_left = 8
	stylebox.corner_radius_bottom_right = 8
	stylebox.content_margin_left = 16
	stylebox.content_margin_right = 16
	stylebox.content_margin_top = 8
	stylebox.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", stylebox)
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "%s Achievement Unlocked!" % ach["icon"]
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	header.add_theme_font_size_override("font_size", 20)
	vbox.add_child(header)

	var desc := Label.new()
	desc.text = "%s — %s" % [ach["title"], ach["description"]]
	desc.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	desc.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc)

	# Fade in
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.4)
	tween.tween_interval(4.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(layer.queue_free)

# ---- Signal Handlers ----

func _on_enemy_died(_enemy: Node3D) -> void:
	# First Blood
	_try_unlock("first_blood")

func _on_mood_changed(new_mood: int) -> void:
	# The Crowd Goes Wild — ERUPTING = 4
	if new_mood >= AudienceManager.Mood.ERUPTING:
		_try_unlock("crowd_goes_wild")

func _on_stat_updated(stat_name: String, value: int) -> void:
	match stat_name:
		"damage_dealt":
			# Check largest_hit for Overkill
			if RunStats.largest_hit >= 1000:
				_try_unlock("overkill")
		"spells_cast":
			# Spell Master — 100 spells in one run
			if value >= 100:
				_try_unlock("spell_master")
		"kills":
			pass

func _on_floor_changed(floor_num: int) -> void:
	# Speed Smusher — Floor 1 cleared in under 3 min
	if floor_num == 2:  # Just moved to floor 2 = floor 1 cleared
		if RunStats.floor_clear_times.has(1):
			if RunStats.floor_clear_times[1] < 180.0:
				_try_unlock("speed_smusher")
		# Check untouchable for floor 1
		if _floor_damage_taken == 0 and RunStats.damage_taken == 0:
			_try_unlock("untouchable")
	elif floor_num >= 2:
		# Check untouchable for the floor we just left
		if _floor_damage_taken == 0:
			_try_unlock("untouchable")

	# Deep Diver — reach Floor 4
	if floor_num >= 4:
		_try_unlock("deep_diver")

	# Reset floor damage counter
	_floor_damage_taken = 0

func _on_game_over(won: bool) -> void:
	# True Champion — win the game
	if won:
		_try_unlock("true_champion")

	# Smush Kill — check if any smush kills happened this run
	if SmusherTimer.get_run_smush_kills() > 0:
		_try_unlock("smush_kill")

	# Gold Rush — 500 gold earned in one run
	if RunStats.gold_earned >= 500:
		_try_unlock("gold_rush")

	# Boss Slayer — cumulative 10 boss kills (load + add current)
	var total_bosses := _get_cumulative_stat("boss_kills") + RunStats.boss_kills
	_set_cumulative_stat("boss_kills", total_bosses)
	if total_bosses >= 10:
		_try_unlock("boss_slayer")

	# Elite Hunter — cumulative 25 elite kills
	var total_elites := _get_cumulative_stat("elite_kills") + RunStats.elite_kills
	_set_cumulative_stat("elite_kills", total_elites)
	if total_elites >= 25:
		_try_unlock("elite_hunter")

	# Polyglot — track character used this run
	var char_name: String = CharacterData.selected_character if CharacterData.get("selected_character") else ""
	if char_name != "":
		_characters_used[char_name] = true
		_save_cumulative()
		if _characters_used.size() >= 6:
			_try_unlock("polyglot")

	# Social Butterfly check (also checked on each bribe)
	if _negotiations_this_run >= 5:
		_try_unlock("social_butterfly")

	# Reset per-run trackers
	_negotiations_this_run = 0
	_floor_damage_taken = 0

func _on_inventory_changed() -> void:
	# Hoarder — all 20 slots filled
	if LootManager.inventory.size() >= LootManager.max_inventory_size:
		_try_unlock("hoarder")

func _on_bribe_attempted(_target: Node3D, success: bool, _cost: int) -> void:
	if success:
		_negotiations_this_run += 1
		if _negotiations_this_run >= 5:
			_try_unlock("social_butterfly")

func _process(_delta: float) -> void:
	# Track damage taken per floor for Untouchable
	_floor_damage_taken = RunStats.damage_taken - _get_floor_damage_baseline()

var _damage_baseline: int = 0

func _get_floor_damage_baseline() -> int:
	return _damage_baseline

func _on_floor_started() -> void:
	_damage_baseline = RunStats.damage_taken

# ---- Persistence ----

func _save() -> void:
	var data := {}
	for id in achievements:
		data[id] = {
			"unlocked": achievements[id]["unlocked"],
			"unlock_time": achievements[id]["unlock_time"],
		}
	# Also save cumulative stats
	data["_cumulative"] = _load_cumulative_data()
	data["_characters_used"] = _characters_used.duplicate()
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func _load() -> void:
	if not FileAccess.file_exists(_save_path):
		return
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	for id in achievements:
		if data.has(id):
			achievements[id]["unlocked"] = data[id].get("unlocked", false)
			achievements[id]["unlock_time"] = data[id].get("unlock_time", "")
	if data.has("_characters_used"):
		_characters_used = data["_characters_used"]

func _load_cumulative_data() -> Dictionary:
	if not FileAccess.file_exists(_save_path):
		return {}
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data.get("_cumulative", {})

func _get_cumulative_stat(key: String) -> int:
	var data := _load_cumulative_data()
	return data.get(key, 0)

func _set_cumulative_stat(key: String, value: int) -> void:
	var data := _load_cumulative_data()
	data[key] = value
	# Re-save with updated cumulative
	_save_cumulative_data(data)

func _save_cumulative_data(cumulative: Dictionary) -> void:
	# Load full file, update _cumulative, re-save
	var full_data := {}
	if FileAccess.file_exists(_save_path):
		var file := FileAccess.open(_save_path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				full_data = json.data
	full_data["_cumulative"] = cumulative
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(full_data, "\t"))

func _save_cumulative() -> void:
	_save()

# ---- Query Methods ----

func get_unlocked_count() -> int:
	var count := 0
	for id in achievements:
		if achievements[id]["unlocked"]:
			count += 1
	return count

func get_total_count() -> int:
	return achievements.size()

func get_all() -> Dictionary:
	return achievements

func is_unlocked(id: String) -> bool:
	return achievements.get(id, {}).get("unlocked", false)
