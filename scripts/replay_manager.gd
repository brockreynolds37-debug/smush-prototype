extends Node

## ReplayManager — records key events per run and saves replay data to
## user://replays/. Supports playback mode with fast-forward.
## The Collective archives every run.

const REPLAY_DIR := "user://replays/"
const MAX_REPLAYS := 20  # Keep only the 20 most recent replays

signal recording_started
signal recording_stopped
signal playback_started
signal playback_stopped
signal playback_event(event: Dictionary)

# ── Recording state ──
var is_recording: bool = false
var _events: Array[Dictionary] = []
var _record_start_time: float = 0.0
var _run_metadata: Dictionary = {}

# ── Playback state ──
var is_playing: bool = false
var _playback_events: Array[Dictionary] = []
var _playback_index: int = 0
var _playback_timer: float = 0.0
var _playback_speed: float = 1.0

func _ready() -> void:
	_ensure_replay_dir()

func _process(delta: float) -> void:
	if is_playing:
		_playback_timer += delta * _playback_speed
		_advance_playback()

# ── RECORDING ──

func start_recording() -> void:
	_events.clear()
	_record_start_time = Time.get_ticks_msec() / 1000.0
	_run_metadata = {
		"character": CharacterData.get_selected().get("name", "Hero"),
		"difficulty": GameManager.get_difficulty_name(),
		"date": Time.get_date_string_from_system(),
		"time": Time.get_time_string_from_system(),
	}
	is_recording = true
	recording_started.emit()

	# Connect signals we want to record
	_connect_signals()

func stop_recording() -> void:
	if not is_recording:
		return
	is_recording = false
	_disconnect_signals()

	_run_metadata["duration"] = Time.get_ticks_msec() / 1000.0 - _record_start_time
	_run_metadata["event_count"] = _events.size()
	_run_metadata["floors_cleared"] = FloorManager.max_floor_reached
	_run_metadata["total_kills"] = GameManager.run_kills

	recording_stopped.emit()

func record_event(event_type: String, data: Dictionary = {}) -> void:
	if not is_recording:
		return

	var timestamp := Time.get_ticks_msec() / 1000.0 - _record_start_time
	var event := {
		"t": snapped(timestamp, 0.01),
		"type": event_type,
	}
	event.merge(data)
	_events.append(event)

func save_replay() -> String:
	## Save current recorded events to disk. Returns the file path.
	stop_recording()

	var replay_data := {
		"version": 1,
		"metadata": _run_metadata,
		"events": _events,
	}

	# Generate filename from date + character
	var filename := "%s_%s_%s.json" % [
		_run_metadata.get("date", "unknown").replace("/", "-"),
		_run_metadata.get("time", "000000").replace(":", ""),
		_run_metadata.get("character", "hero").to_lower().replace(" ", "_"),
	]
	var path := REPLAY_DIR + filename

	var json_str := JSON.stringify(replay_data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()

	_prune_old_replays()
	return path

func list_replays() -> Array[Dictionary]:
	## Returns metadata for all saved replays, newest first.
	var replays: Array[Dictionary] = []
	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return replays

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var meta := _read_replay_metadata(REPLAY_DIR + fname)
			if not meta.is_empty():
				meta["filename"] = fname
				meta["path"] = REPLAY_DIR + fname
				replays.append(meta)
		fname = dir.get_next()

	# Sort by date descending
	replays.sort_custom(func(a, b): return a.get("date", "") > b.get("date", ""))
	return replays

func _read_replay_metadata(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json_str := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return {}
	var data: Dictionary = json.data
	return data.get("metadata", {})

# ── PLAYBACK ──

func load_replay(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json_str := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return false
	var data: Dictionary = json.data
	_playback_events.clear()
	var events: Array = data.get("events", [])
	for e in events:
		if e is Dictionary:
			_playback_events.append(e)
	_run_metadata = data.get("metadata", {})
	return true

func start_playback(speed: float = 1.0) -> void:
	if _playback_events.is_empty():
		return
	is_playing = true
	_playback_index = 0
	_playback_timer = 0.0
	_playback_speed = speed
	playback_started.emit()

func stop_playback() -> void:
	is_playing = false
	_playback_index = 0
	_playback_timer = 0.0
	playback_stopped.emit()

func set_playback_speed(speed: float) -> void:
	_playback_speed = clampf(speed, 0.25, 8.0)

func _advance_playback() -> void:
	while _playback_index < _playback_events.size():
		var event: Dictionary = _playback_events[_playback_index]
		var event_time: float = event.get("t", 0.0)
		if event_time <= _playback_timer:
			playback_event.emit(event)
			_playback_index += 1
		else:
			break

	if _playback_index >= _playback_events.size():
		stop_playback()

func get_playback_progress() -> float:
	if _playback_events.is_empty():
		return 0.0
	var total_time: float = _playback_events[_playback_events.size() - 1].get("t", 1.0)
	if total_time <= 0:
		return 1.0
	return clampf(_playback_timer / total_time, 0.0, 1.0)

func get_playback_metadata() -> Dictionary:
	return _run_metadata

# ── SIGNAL CONNECTIONS ──

func _connect_signals() -> void:
	# Floor transitions
	if not FloorManager.floor_changed.is_connected(_on_floor_changed):
		FloorManager.floor_changed.connect(_on_floor_changed)

	# Enemy kills
	if not GameManager.enemy_died.is_connected(_on_enemy_died):
		GameManager.enemy_died.connect(_on_enemy_died)

	# Game over
	if not GameManager.game_over.is_connected(_on_game_over):
		GameManager.game_over.connect(_on_game_over)

	# Level up
	if XpManager.has_signal("level_up") and not XpManager.level_up.is_connected(_on_level_up):
		XpManager.level_up.connect(_on_level_up)

	# Loot
	if not LootManager.item_picked_up.is_connected(_on_item_picked_up):
		LootManager.item_picked_up.connect(_on_item_picked_up)

	# Audience mood
	if not AudienceManager.mood_changed.is_connected(_on_mood_changed):
		AudienceManager.mood_changed.connect(_on_mood_changed)

func _disconnect_signals() -> void:
	if FloorManager.floor_changed.is_connected(_on_floor_changed):
		FloorManager.floor_changed.disconnect(_on_floor_changed)
	if GameManager.enemy_died.is_connected(_on_enemy_died):
		GameManager.enemy_died.disconnect(_on_enemy_died)
	if GameManager.game_over.is_connected(_on_game_over):
		GameManager.game_over.disconnect(_on_game_over)
	if XpManager.has_signal("level_up") and XpManager.level_up.is_connected(_on_level_up):
		XpManager.level_up.disconnect(_on_level_up)
	if LootManager.item_picked_up.is_connected(_on_item_picked_up):
		LootManager.item_picked_up.disconnect(_on_item_picked_up)
	if AudienceManager.mood_changed.is_connected(_on_mood_changed):
		AudienceManager.mood_changed.disconnect(_on_mood_changed)

# ── EVENT HANDLERS ──

func _on_floor_changed(floor_num: int) -> void:
	record_event("floor", {"floor": floor_num})

func _on_enemy_died(enemy: Node3D) -> void:
	var pos := Vector3.ZERO
	if is_instance_valid(enemy):
		pos = enemy.global_position
	record_event("kill", {"pos": _v3_to_arr(pos)})

func _on_game_over(won: bool) -> void:
	record_event("game_over", {"won": won, "floor": FloorManager.current_floor})

func _on_level_up(level: int) -> void:
	record_event("level_up", {"level": level})

func _on_item_picked_up(item: Dictionary) -> void:
	record_event("loot", {"name": item.get("name", "item"), "rarity": item.get("rarity", 0)})

func _on_mood_changed(mood: int) -> void:
	record_event("mood", {"mood": mood})

# ── UTILITIES ──

func _v3_to_arr(v: Vector3) -> Array:
	return [snapped(v.x, 0.1), snapped(v.y, 0.1), snapped(v.z, 0.1)]

func _ensure_replay_dir() -> void:
	if not DirAccess.dir_exists_absolute(REPLAY_DIR):
		DirAccess.make_dir_recursive_absolute(REPLAY_DIR)

func _prune_old_replays() -> void:
	var replays := list_replays()
	if replays.size() > MAX_REPLAYS:
		# Delete oldest replays beyond limit
		for i in range(MAX_REPLAYS, replays.size()):
			var path: String = replays[i].get("path", "")
			if path != "":
				DirAccess.remove_absolute(path)
