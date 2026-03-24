extends Node

## THE SMUSHER — 30-minute countdown timer per floor.
## At 0:00, rooms collapse from entry-side toward exit, 1 room per 3 seconds.
## 60 seconds overtime before total collapse. Player in collapsed room = instant death.

signal time_updated(seconds_remaining: float)
signal warning_phase_entered  # < 5 minutes
signal critical_phase_entered  # < 1 minute
signal overtime_started
signal room_collapsed(room_index: int, room_name: String)
signal total_collapse  # 60s overtime done — everything gone

const DEFAULT_DURATION := 1800.0  # 30 minutes in seconds
const OVERTIME_DURATION := 60.0
const ROOM_COLLAPSE_INTERVAL := 3.0  # seconds between room collapses
const WARNING_THRESHOLD := 300.0  # 5 minutes
const CRITICAL_THRESHOLD := 60.0  # 1 minute

var time_remaining: float = DEFAULT_DURATION
var is_running: bool = false
var time_scale: float = 1.0  # Archetypes can speed up/slow down the timer
var is_overtime: bool = false
var overtime_elapsed: float = 0.0
var _collapse_timer: float = 0.0
var _next_collapse_index: int = 0
var _room_collapse_order: Array[int] = []  # Room indices, spawn-first
var _collapsed_rooms: Array[int] = []

# Track warning states to emit signals only once
var _warned_5min: bool = false
var _warned_1min: bool = false

# Reference to dungeon builder for room positions
var dungeon_builder: Node3D = null

func _ready() -> void:
	FloorManager.floor_changed.connect(_on_floor_changed)

func _process(delta: float) -> void:
	if not is_running or GameManager.game_state != GameManager.GameState.PLAYING:
		return

	if not is_overtime:
		time_remaining -= delta * time_scale
		time_updated.emit(time_remaining)

		# Warning thresholds
		if time_remaining <= WARNING_THRESHOLD and not _warned_5min:
			_warned_5min = true
			warning_phase_entered.emit()

		if time_remaining <= CRITICAL_THRESHOLD and not _warned_1min:
			_warned_1min = true
			critical_phase_entered.emit()

		# Timer expired — start overtime
		if time_remaining <= 0.0:
			time_remaining = 0.0
			_start_overtime()
	else:
		# Overtime — collapse rooms
		overtime_elapsed += delta
		_collapse_timer += delta

		if _collapse_timer >= ROOM_COLLAPSE_INTERVAL:
			_collapse_timer -= ROOM_COLLAPSE_INTERVAL
			_collapse_next_room()

		# Check total collapse
		if overtime_elapsed >= OVERTIME_DURATION:
			total_collapse.emit()
			_kill_hero("THE SMUSHER")
			is_running = false

		# Check if hero is in a collapsed room
		_check_hero_in_collapsed_room()

func start_timer(duration: float = DEFAULT_DURATION) -> void:
	time_remaining = duration
	is_running = true
	is_overtime = false
	overtime_elapsed = 0.0
	_collapse_timer = 0.0
	_next_collapse_index = 0
	_collapsed_rooms.clear()
	_warned_5min = false
	_warned_1min = false
	_build_collapse_order()
	time_updated.emit(time_remaining)

func stop_timer() -> void:
	is_running = false

func reset() -> void:
	stop_timer()
	time_remaining = DEFAULT_DURATION
	is_overtime = false
	overtime_elapsed = 0.0
	_collapsed_rooms.clear()
	_warned_5min = false
	_warned_1min = false

func _on_floor_changed(_floor_num: int) -> void:
	# Reset and restart timer for new floor
	start_timer()

func _start_overtime() -> void:
	is_overtime = true
	overtime_elapsed = 0.0
	_collapse_timer = 0.0
	overtime_started.emit()
	GameManager.request_screen_shake(0.3, 2.0)

func _build_collapse_order() -> void:
	# Rooms collapse from spawn toward exit (index order = spawn first)
	_room_collapse_order.clear()
	if dungeon_builder and dungeon_builder.rooms.size() > 0:
		for i in range(dungeon_builder.rooms.size()):
			_room_collapse_order.append(i)
	# Order is already spawn → exit in the layout definitions

func _collapse_next_room() -> void:
	if _next_collapse_index >= _room_collapse_order.size():
		return  # All rooms collapsed

	var room_idx: int = _room_collapse_order[_next_collapse_index]
	_collapsed_rooms.append(room_idx)

	var room_name: String = ""
	if dungeon_builder and room_idx < dungeon_builder.rooms.size():
		room_name = dungeon_builder.rooms[room_idx].get("name", "room_%d" % room_idx)

	room_collapsed.emit(room_idx, room_name)
	GameManager.request_screen_shake(0.5, 1.0)
	_next_collapse_index += 1

func _check_hero_in_collapsed_room() -> void:
	if not GameManager.hero or not dungeon_builder:
		return
	if GameManager.hero.is_dead:
		return

	var hero_pos: Vector3 = GameManager.hero.global_position
	var hero_cell := Vector2i(
		roundi(hero_pos.x / dungeon_builder.TILE_SIZE),
		roundi(hero_pos.z / dungeon_builder.TILE_SIZE)
	)

	for room_idx in _collapsed_rooms:
		if room_idx >= dungeon_builder.rooms.size():
			continue
		var room: Dictionary = dungeon_builder.rooms[room_idx]
		var rpos: Vector2i = room["pos"]
		var rsize: Vector2i = room["size"]
		if hero_cell.x >= rpos.x and hero_cell.x < rpos.x + rsize.x \
				and hero_cell.y >= rpos.y and hero_cell.y < rpos.y + rsize.y:
			_kill_hero("CRUSHED")
			return

func _kill_hero(cause: String) -> void:
	if GameManager.hero and not GameManager.hero.is_dead:
		if GameManager.hero.has_method("take_damage"):
			GameManager.hero.take_damage(99999)
		else:
			# Fallback — directly trigger death
			GameManager.game_state = GameManager.GameState.LOST
			GameManager.game_over.emit(false)

## Returns formatted time string MM:SS
func get_time_string() -> String:
	var t := maxi(0, int(ceil(time_remaining)))
	var minutes := t / 60
	var seconds := t % 60
	return "%02d:%02d" % [minutes, seconds]

## Returns 0.0-1.0 ratio of time remaining
func get_time_ratio() -> float:
	return clampf(time_remaining / DEFAULT_DURATION, 0.0, 1.0)

## Returns which phase the timer is in
func get_phase() -> String:
	if is_overtime:
		return "overtime"
	elif time_remaining <= CRITICAL_THRESHOLD:
		return "critical"
	elif time_remaining <= WARNING_THRESHOLD:
		return "warning"
	else:
		return "normal"
