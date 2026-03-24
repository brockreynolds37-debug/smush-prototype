extends Node

## Leaderboard — persistent top 10 high scores saved to user://leaderboard.json.
## Tracks: floors cleared, kills, time survived, gold earned, difficulty, character.
## Submit at end of each run. Display on main menu + death recap.

const SAVE_PATH := "user://leaderboard.json"
const MAX_ENTRIES := 10

var entries: Array[Dictionary] = []

func _ready() -> void:
	_load()

func submit_run() -> int:
	## Record current run stats and return the rank (1-based), or 0 if not ranked.
	var s := RunStats.get_summary()
	var time_secs := GameManager.get_run_elapsed()
	var entry := {
		"floors": FloorManager.max_floor_reached,
		"kills": s.get("total_kills", 0),
		"time": time_secs,
		"time_str": "%d:%02d" % [int(time_secs) / 60, int(time_secs) % 60],
		"gold": s.get("gold_earned", 0),
		"difficulty": GameManager.difficulty,
		"difficulty_name": GameManager.get_difficulty_name(),
		"character": CharacterData.get_selected().get("name", "Hero"),
		"level": XpManager.current_level,
		"vp": AudienceManager.total_vp,
		"won": GameManager.game_state == GameManager.GameState.WON,
		"date": Time.get_date_string_from_system(),
	}
	# Score: floors * 1000 + kills * 10 + gold + difficulty bonus
	entry["score"] = _calc_score(entry)

	# Insert sorted by score descending
	var rank := 0
	for i in range(entries.size()):
		if entry["score"] > entries[i].get("score", 0):
			entries.insert(i, entry)
			rank = i + 1
			break
	if rank == 0:
		entries.append(entry)
		rank = entries.size()

	# Trim to top 10
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)
	if rank > MAX_ENTRIES:
		rank = 0  # Didn't make the board

	_save()
	return rank

func _calc_score(entry: Dictionary) -> int:
	var base: int = entry.get("floors", 0) * 1000
	base += entry.get("kills", 0) * 10
	base += entry.get("gold", 0)
	# Difficulty bonus: Easy=1x, Normal=1.5x, Hard=2.5x, Insane=4x
	var diff_bonus := {0: 1.0, 1: 1.5, 2: 2.5, 3: 4.0}
	var mult: float = diff_bonus.get(entry.get("difficulty", 1), 1.0)
	return int(base * mult)

func get_entries() -> Array[Dictionary]:
	return entries

func _save() -> void:
	var data: Array = []
	for e in entries:
		data.append(e)
	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()

func _load() -> void:
	entries.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json_string := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_string)
	if err != OK:
		return
	var data = json.data
	if data is Array:
		for item in data:
			if item is Dictionary:
				entries.append(item)
